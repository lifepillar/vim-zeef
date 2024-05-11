vim9script

# Requirements Check {{{
if !has('popupwin') || !has('textprop') || v:version < 901
  echomsg 'Zeef requires Vim 9.1 compiled with popupwin and textprop.'
  finish
endif
# }}}
# User Configuration {{{
export var exactsymbol:    string       = get(g:, 'zeef_exactsymbol',    '[Exact]')
export var fuzzy:          bool         = get(g:, 'zeef_fuzzy',          true     )
export var fuzzysymbol:    string       = get(g:, 'zeef_fuzzysymbol',    '[Fuzzy]')
export var keyaliases:     dict<string> = get(g:, 'zeef_keyaliases',     {}       )
export var keymap:         dict<func()> = get(g:, 'zeef_keymap',         {}       )
export var limit:          number       = get(g:, 'zeef_limit',          0        )
export var matchseq:       bool         = get(g:, 'zeef_matchseq',       false    )
export var popupmaxheight: number       = get(g:, 'zeef_popupmaxheight', 100      )
export var prompt:         string       = get(g:, 'zeef_prompt',         ' ❯ '    )
export var reuselastmode:  bool         = get(g:, 'zeef_reuselastmode',  false    )
export var sidescroll:     number       = get(g:, 'zeef_sidescroll',     5        )
export var skipfirst:      number       = get(g:, 'zeef_skipfirst',      0        )
export var stlname:        string       = get(g:, 'zeef_stlname',        'Zeef'   )
export var wildchar:       string       = get(g:, 'zeef_wildchar',       ' '      )
export var winheight:      number       = get(g:, 'zeef_winheight',      10       )
export var winhighlight:   string       = get(g:, 'zeef_winhighlight',   ''       )
# }}}
# Internal State {{{
var sBufnr:                  number       = -1     # Zeef buffer number
var sFinish:                 bool         = false  # The event loop is exited when this becomes true
var sFuzzy:                  bool         = true   # Use fuzzy matching?
var sInput:                  string       = ''     # The current text typed by the user
var sKeyAlias:               string       = ''     # The actual key press (different from sKeyPress if aliased)
var sKeyAliases:             dict<string> = {}     # The current key aliases
var sKeyMap:                 dict<func()> = {}     # The current key map (key press -> action)
var sKeyPress:               string       = ''     # Last key press (after aliasing is resolved)
var sPopupId:                number       = -1     # ID of the Selected Items popup
var sResult:                 list<string> = []     # The currently selected items
# The following are set when opening Zeef
var sLabel:                  string       = 'Zeef' # Prompt label
var sMultipleSelection:      bool         = true   # Whether muliple selections are allowed
var sDuplicateInsertion:     bool         = false  # Whether duplicate items in the result are allowed
var sDuplicateDeletion:      bool         = true   # Whether all duplicates should be removed when one is removed

# Stack of booleans that tells whether to undo when pressing backspace.
# If the top of the stack is true then undo; if it is false, do not undo.
var sUndoStack:  list<bool> = []

# Commands to restore the window layout when Zeef's window is closed
var sWinRestCmd: string = ''

class Config
  static var Fuzzy          = () => fuzzy
  static var KeyAliases     = () => keyaliases
  static var KeyMap         = () => keymap
  static var Limit          = () => limit
  static var MatchSeq       = () => matchseq
  static var PopupMaxHeight = () => popupmaxheight
  static var Prompt         = () => sLabel .. ' ' .. (sFuzzy ? fuzzysymbol : exactsymbol) .. prompt
  static var ReuseLastMode  = () => reuselastmode
  static var SideScroll     = () => sidescroll
  static var SkipFirst      = () => skipfirst
  static var StatusLineName = () => stlname
  static var Wildchar       = () => wildchar
  static var WinHeight      = () => winheight
  static var WinHighlight   = () => winhighlight
endclass
# }}}
# Highlight Groups {{{
hi default link ZeefMatch Label
hi default link ZeefName StatusLine
hi default link ZeefPopupWinColor Normal
hi default link ZeefPopupBorderColor Identifier
hi default link ZeefPopupScrollbarColor PmenuSbar
hi default link ZeefPopupScrollbarThumbColor PmenuThumb
# }}}
# Helper Functions {{{
def In(v: string, items: list<string>): bool
  return index(items, v) != -1
enddef

def NotIn(v: string, items: list<string>): bool
  return index(items, v) == -1
enddef

def Min(m: number, n: number): number
  return m < n ? m : n
enddef

def AddToSelection(item: string)
  if empty(item)
    return
  endif

  if !sDuplicateInsertion && item->In(sResult)
    return
  endif

  sResult->add(item)
enddef

def RemoveFromSelection(item: string)
  if sDuplicateInsertion && sDuplicateDeletion # Remove all occurrences of item
    var newResult: list<string> = []

    for result in sResult
      if result != item
        newResult->add(result)
      endif
    endfor

    sResult = newResult
  else # Remove one occurrence of item
    var i = sResult->index(item)

    if i > -1
      remove(sResult, i)
    endif
  endif
enddef

def ToggleItem(item: string)
  if item->NotIn(sResult)
    AddToSelection(item)
  else
    RemoveFromSelection(item)
  endif
enddef

def EchoPrompt()
  redrawstatus
  redraw
  echo "\r"
  echo Config.Prompt() .. sInput
enddef

def EchoResult(items: list<string>)
  echo sResult
enddef

# Default regexp filter for exact matching.
#
# This behaves mostly like globbing, except that ^ and $ can be used to anchor
# a pattern. All characters are matched literally except ^, $, and the
# wildchar; the latter matches zero 0 more characters.
def Regexp(input: string): string
  return substitute(escape(input, '~.\[:'), Config.Wildchar(), '.*', 'g')
enddef

def MatchExactly()
  if empty(sInput)
    return
  endif

  var regexp = Regexp(sInput)

  try
    execute 'silent keeppatterns g!:\m' .. regexp .. ':norm "_dd'
  catch /^Vim\%((\a\+)\)\=:E538:/  # Raised when all lines match
  endtry

  normal gg

  clearmatches()
  matchadd('ZeefMatch', '\c' .. regexp)
enddef

def MatchFuzzily()
  var opts: dict<any> = {'limit': Config.Limit()}

  if Config.MatchSeq()
    opts['matchseq'] = true
  endif

  var [lines, charpos, _] = matchfuzzypos(getbufline(sBufnr, 1, line('$')), sInput, opts)

  deletebufline(sBufnr, 1, '$')
  setbufline(sBufnr, 1, lines)

  # Highlight matches
  var i = 0

  while i < len(charpos)
    for k in charpos[i]
      prop_add(i + 1, 1 + byteidx(lines[i], k), {
        bufnr: sBufnr, type: 'zeefmatch', length: strlen(lines[i][k])
      })
    endfor
    ++i
  endwhile
enddef

def Match()
  var old_seq = get(undotree(), 'seq_cur', 0)

  if sFuzzy
    MatchFuzzily()
  else
    MatchExactly()
  endif

  var new_seq = get(undotree(), 'seq_cur', 0)

  add(sUndoStack, new_seq != old_seq) # new_seq != old_seq iff the buffer has changed
enddef

def! g:ZeefStatusLine(): string
  return $'%#ZeefName# {Config.StatusLineName()} %* %l of %L' .. (empty(sResult) ? '' : $' ({len(sResult)} selected)')
enddef

def OpenZeefBuffer(items: list<string>): number
  # botright 10new may not set the right height, e.g., if the quickfix window is open
  execute $'botright :1new | :{Config.WinHeight()}wincmd +'

  if !empty(Config.WinHighlight())
    &wincolor = Config.WinHighlight()
  endif

  prop_type_add('zeefmatch', {bufnr: bufnr(), 'highlight': 'ZeefMatch'})

  abclear <buffer>
  setlocal
        \ bufhidden=wipe
        \ buftype=nofile
        \ colorcolumn&
        \ cursorline
        \ filetype=zeef
        \ foldmethod=manual
        \ modifiable
        \ nobuflisted
        \ nocursorcolumn
        \ nofoldenable
        \ nolist
        \ nonumber
        \ noreadonly
        \ norelativenumber
        \ nospell
        \ noswapfile
        \ noundofile
        \ nowrap
        \ scrolloff=0
        \ statusline=%!ZeefStatusLine()
        \ textwidth=0
        \ winfixheight

  setline(1, items)

  return bufnr()
enddef

def CloseZeefBuffer()
  wincmd p
  execute 'bwipe!' sBufnr
  execute sWinRestCmd
  sBufnr = -1
  redraw
  echo "\r"
enddef
# }}}
# Selection Popup {{{
def HideSelectionPopup()
  popup_hide(sPopupId)
enddef

def ShowSelectionPopup()
  if sPopupId <= 0
    CreateSelectionPopup()
  else
    popup_settext(sPopupId, sResult)
    popup_show(sPopupId)
  endif
enddef

def UpdateSelectionPopupStatus()
  if len(sResult) > 0
    ShowSelectionPopup()
  else
    popup_settext(sPopupId, [''])
    HideSelectionPopup()
  endif
enddef

def SelectionPopupClosed(winid: number, result: any = '')
  sPopupId = -1
enddef

def RemoveFromSelectionPopup(winid: number, key: string): bool
  if key == "\<LeftMouse>"
    var mousepos = getmousepos()

    if mousepos.winid == winid
      var item = getbufoneline(winbufnr(winid), mousepos.line)
      RemoveFromSelection(item)
      UpdateSelectionPopupStatus()
      return true
    endif
  endif

  return false
enddef

def CreateSelectionPopup()
  sPopupId = popup_create(sResult, {
    border: [1, 1, 1, 1],
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    borderhighlight: ['ZeefPopupBorderColor'],
    callback: SelectionPopupClosed,
    close: 'button',
    col: 1,
    cursorline: false,
    drag: false,
    filter: RemoveFromSelectionPopup,
    highlight: 'ZeefPopupWinColor',
    line: screenpos(bufwinid(sBufnr), 1, 1).row - 1,
    minheight: 1,
    maxheight: Min(Config.PopupMaxHeight(), &lines - Config.WinHeight() - 10),
    padding: [0, 1, 0, 1],
    pos: 'botleft',
    resize: false,
    scrollbar: true,
    scrollbarhighlight: 'ZeefPopupScrollbarColor',
    thumbhighlight: 'ZeefPopupScrollbarThumbColor',
    title: 'Selected Items',
    minwidth: &columns - 5,
    maxwidth: &columns - 5,
    wrap: false,
  })
enddef

def CloseSelectionPopup()
  if sPopupId > 0
    popup_close(sPopupId)
  endif
  sPopupId = -1
enddef

def IsSelectionPopupVisible(): bool
  return sPopupId > 0 && get(popup_getpos(sPopupId), 'visible', false)
enddef
# }}}
# Actions {{{
def ActionAccept()
  if empty(sResult)
    var line = getbufoneline(sBufnr, line('.'))

    if !empty(line)
      sResult->add(line)
    endif
  endif

  CloseSelectionPopup()
  CloseZeefBuffer()
  sFinish = true
enddef

def ActionCancel()
  sResult = []
  CloseSelectionPopup()
  CloseZeefBuffer()
  sFinish = true
enddef

def ActionClearPrompt()
  silent undo 1
  sUndoStack = []
  sInput = ''
enddef

def ActionDeselectAll()
  sResult = []
  UpdateSelectionPopupStatus()
enddef

def ActionDeselectCurrent()
  var items = getbufline(sBufnr, 1, '$')

  for item in items
    RemoveFromSelection(item)
  endfor

  UpdateSelectionPopupStatus()
enddef

def ActionDeselectItem()
  RemoveFromSelection(getbufoneline(sBufnr, line('.')))
  UpdateSelectionPopupStatus()
  normal k
enddef

def ActionLeftClick()
  var mousepos = getmousepos()

  if mousepos.winid != bufwinid(sBufnr)
    return
  endif

  ToggleItem(getbufoneline(sBufnr, mousepos.line))
  UpdateSelectionPopupStatus()
enddef

def ActionMoveUp()
  normal k
enddef

def ActionPassthrough()
  execute 'normal' sKeyPress
enddef

def ActionScrollLeft()
  execute $'normal {Config.SideScroll()}zh'
enddef

def ActionScrollRight()
  execute $'normal {Config.SideScroll()}zl'
enddef

def ActionSelectCurrent()
  if sMultipleSelection
    var items = getbufline(sBufnr, 1, '$')

    for item in items
      AddToSelection(item)
    endfor

    UpdateSelectionPopupStatus()
  else
    ActionSelectItem()
  endif
enddef

def ActionSelectItem()
  if !sMultipleSelection
    sResult = []
  endif

  AddToSelection(getbufoneline(sBufnr, line('.')))
  UpdateSelectionPopupStatus()
  normal j
enddef

def ActionSplitAccept()
  ActionAccept()
  split
enddef

def ActionTabNewAccept()
  ActionAccept()
  tabnew
enddef

def ActionToggleFuzzy()
  sFuzzy = !sFuzzy
  clearmatches()
  ActionClearPrompt()
enddef

def ActionToggleItem()
  var item = getbufoneline(sBufnr, line('.'))

  if !sMultipleSelection && len(sResult) > 0 && item->NotIn(sResult)
    return
  endif

  ToggleItem(item)
  UpdateSelectionPopupStatus()
enddef

def ActionUndo()
  sInput = strcharpart(sInput, 0, strchars(sInput) - 1)

  if !empty(sUndoStack) && remove(sUndoStack, -1)
    silent undo
    normal gg
  endif

  clearmatches()

  if !empty(sInput)
    matchadd('ZeefMatch', '\c' .. Regexp(sInput))
  endif
enddef

def ActionVertSplitAccept()
  ActionAccept()
  vsplit
enddef

def ActionToggleSelectionPopup()
  if IsSelectionPopupVisible()
    HideSelectionPopup()
  else
    ShowSelectionPopup()
  endif
enddef
# }}}
# Default Key Map {{{
const cDefaultKeyMap = {
  "\<LeftMouse>":        ActionLeftClick,
  "\<ScrollWheelDown>":  ActionPassthrough,
  "\<ScrollWheelLeft>":  ActionPassthrough,
  "\<ScrollWheelRight>": ActionPassthrough,
  "\<ScrollWheelUp>":    ActionPassthrough,
  "\<bs>":               ActionUndo,
  "\<c-a>":              ActionSelectCurrent,
  "\<c-b>":              ActionPassthrough,
  "\<c-d>":              ActionPassthrough,
  "\<c-e>":              ActionPassthrough,
  "\<c-f>":              ActionPassthrough,
  "\<c-g>":              ActionDeselectAll,
  "\<c-j>":              ActionPassthrough,
  "\<c-k>":              ActionMoveUp,
  "\<c-l>":              ActionClearPrompt,
  "\<c-p>":              ActionToggleSelectionPopup,
  "\<c-r>":              ActionDeselectCurrent,
  "\<c-s>":              ActionSplitAccept,
  "\<c-t>":              ActionTabNewAccept,
  "\<c-u>":              ActionPassthrough,
  "\<c-v>":              ActionVertSplitAccept,
  "\<c-x>":              ActionToggleItem,
  "\<c-y>":              ActionPassthrough,
  "\<c-z>":              ActionToggleFuzzy,
  "\<down>":             ActionPassthrough,
  "\<enter>":            ActionAccept,
  "\<esc>":              ActionCancel,
  "\<left>":             ActionScrollLeft,
  "\<right>":            ActionScrollRight,
  "\<s-tab>":            ActionDeselectItem,
  "\<tab>":              ActionSelectItem,
  "\<up>":               ActionPassthrough,
  '':                    ActionCancel,
}
# }}}
# Event Processing  {{{
def GetKeyPress(): string
  try
    sKeyAlias = getcharstr()
    return get(sKeyAliases, sKeyAlias, sKeyAlias)
  catch /^Vim:Interrupt$/ # CTRL-C
    return ''
  endtry

  return ''
enddef

def ProcessKeyPress(key: string)
  if sKeyMap->has_key(key)
    sKeyMap[key]()
    return
  endif

  # Skip other non-printable characters
  var charCode = char2nr(key[0])
  if charCode == 0x80 || charCode < 0x20
    return
  endif

  sInput ..= key

  if strchars(sInput) > Config.SkipFirst()
    Match()
  endif
enddef

def EventLoop()
  while true
    EchoPrompt()
    sKeyPress = GetKeyPress()
    ProcessKeyPress(sKeyPress)

    if sFinish
      break
    endif
  endwhile
enddef
# }}}
# Public Interface {{{
export def Open(
    items:                  list<string>,
    Callback:               func(list<string>) = EchoResult,
    promptLabel:            string             = 'Zeef',
    options:                dict<any>          = {},
    )
  sLabel              = promptLabel
  sMultipleSelection  = get(options, 'multi', true)
  sDuplicateInsertion = get(options, 'dupinsert', false) && sMultipleSelection
  sDuplicateDeletion  = get(options, 'dupdelete', false) && sDuplicateInsertion
  sKeyMap             = extend(extend(get(options, 'keymap', {}), Config.KeyMap(), 'keep'), cDefaultKeyMap, 'keep')
  sKeyAliases         = extend(get(options, 'keyaliases', {}), Config.KeyAliases(), 'keep')
  sWinRestCmd         = winrestcmd()
  sInput              = ''
  sResult             = []
  sFinish             = false
  sFuzzy              = Config.Fuzzy()
  sBufnr              = OpenZeefBuffer(items)

  EventLoop()

  if !empty(sResult)
    Callback(sResult)
  endif

  if Config.ReuseLastMode()
    fuzzy = sFuzzy
  endif

  sInput = ''
  sResult = []
enddef

export def LastKeyPressed(): string
  return sKeyAlias
enddef

export def SelectedItems(): list<string>
  return sResult
enddef
# }}}}
# Zeefs {{{
# Path Filters {{{

def SetArglist(items: list<string>)
  execute 'args' join(mapnew(items, (_, p) => fnameescape(p)))
enddef

# Filter a list of paths and populate the arglist with the selected items.
export def Args(paths: list<string>)
  Open(paths, SetArglist, 'Choose files')
enddef

# Ditto, but use the paths in the specified directory
export def Files(directory = '.')
  var dir = shellescape(fnamemodify(directory, ':p'))
  var cmd = executable('rg') ? $"rg --files {dir}" : $"find {dir} -type f"

  Open(systemlist(cmd), SetArglist, 'Choose files')
enddef
# }}}
# Buffer Switcher {{{
def SwitchToBuffer(items: list<string>)
  execute 'buffer' matchstr(items[0], '^\s*\zs\d\+')
enddef

# props is a dictionary with the following keys:
#   - unlisted: when set to true, show also unlisted buffers
export def BufferSwitcher(props: dict<any> = {})
  var showUnlisted = get(props, 'unlisted', false)
  var cmd = 'ls' .. (showUnlisted ? '!' : '')
  var buffers = split(execute(cmd), "\n")
  map(buffers, (_, b): string => substitute(b, '"\(.*\)"\s*line\s*\d\+$', '\1', ''))

  Open(buffers, SwitchToBuffer, 'Switch buffer', {multi: false})
enddef
# }}}
# Quickfix/Location List Filter {{{
def JumpToQuickfixEntry(items: list<string>)
  execute 'crewind' matchstr(items[0], '^\s*\d\+')
enddef

def JumpToLocationListEntry(items: list<string>)
  execute 'lrewind' matchstr(items[0], '^\s*\d\+')
enddef

export def QuickfixList(Callback = JumpToQuickfixEntry)
  var qflist = getqflist()

  if empty(qflist)
    echo '[Zeef] Quickfix list is empty'
    return
  endif

  var cmd = split(execute('clist'), "\n")

  Open(cmd, Callback, 'Filter quickfix entry')
enddef

export def LocationList(winnr = 0, Callback = JumpToLocationListEntry)
  var loclist = getloclist(winnr)

  if empty(loclist)
    echo '[Zeef] Location list is empty'
    return
  endif

  var cmd = split(execute('llist'), "\n")

  Open(cmd, Callback, 'Filter loclist entry')
enddef
# }}}
# Find Color Scheme {{{
def SetColorscheme(items: list<string>)
  execute 'colorscheme' items[0]
enddef

export def ColorschemeSwitcher()
  var searchPaths = [
    globpath(&runtimepath, 'colors/*.vim', 0, 1),
    globpath(&packpath, 'pack/*/{opt,start}/*/colors/*.vim', 0, 1),
  ]
  var colorschemes = []

  for pathList in searchPaths
    colorschemes += map(pathList, (_, p): string => fnamemodify(p, ':t:r'))
  endfor

  Open(colorschemes, SetColorscheme, 'Choose colorscheme', {multi: false})
enddef
# }}}
# Buffer Tags Using Ctags {{{
const sCtagsBin = executable('uctags') ? 'uctags' : 'ctags'

# Adapted from CtrlP's buffertag.vim
const sCtagsTypes = {
  'aspperl': 'asp',
  'aspvbs':  'asp',
  'cpp':     'c++',
  'cs':      'c#',
  'delphi':  'pascal',
  'expect':  'tcl',
  'mf':      'metapost',
  'mp':      'metapost',
  'rmd':     'rmarkdown',
  'csh':     'sh',
  'zsh':     'sh',
  'tex':     'latex',
}

def Tags(path: string, filetype: string, ctagsPath: string, ctagsTypes: dict<string>): list<string>
  var language = get(ctagsTypes, filetype, filetype)
  var filepath = shellescape(expand(path))

  return systemlist(
    $'{ctagsPath} -f - --sort=no --excmd=number --fields= --extras=+F --language-force={language} {filepath}'
  )
enddef

def JumpToTag(item: string, bufname: string)
  if item =~ '^\d\+'
    var [lnum, _] = split(item, '\s\+')
    execute $'buffer +{lnum} {bufname}'
  endif
enddef

export def BufferTags(ctagsTypes: dict<string> = {}, ctagsPath = sCtagsBin)
  var bufname = bufname("%")
  var tags = Tags(bufname, &ft, ctagsPath, extend(ctagsTypes, sCtagsTypes, 'keep'))

  map(tags, (_, t) => substitute(t, '^\(\S\+\)\s.*\s\(\d\+\)$', '\2 \1', ''))

  Open(tags, (t: list<string>) => JumpToTag(t[0], bufname), 'Choose tag', {multi: false})
enddef
# }}}
# }}}
