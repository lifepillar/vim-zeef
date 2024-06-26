vim9script

# Requirements Check {{{
def Msg(msg: string)
  echomsg '[Zeef]' msg
enddef

if !has('job') || !has('popupwin') || !has('timers') || !has('textprop') || v:version < 901
  Msg('Vim 9.1 compiled with job, popupwin, timers and textprop is required.')
  finish
endif
# }}}
# User Configuration {{{
export var andchar:          string       = get(g:, 'zeef_andchar',          '&'                                     )
export var exactlabel:       string       = get(g:, 'zeef_exactlabel',       ' [Exact]'                              )
export var fuzzy:            bool         = get(g:, 'zeef_fuzzy',            true                                    )
export var fuzzylabel:       string       = get(g:, 'zeef_fuzzylabel',       ' [Fuzzy]'                              )
export var keyaliases:       dict<string> = get(g:, 'zeef_keyaliases',       {}                                      )
export var keymap:           dict<func()> = get(g:, 'zeef_keymap',           {}                                      )
export var limit:            number       = get(g:, 'zeef_limit',            0                                       )
export var matchseq:         bool         = get(g:, 'zeef_matchseq',         false                                   )
export var popupborder:      list<number> = get(g:, 'zeef_popupborder',      [1, 1, 1, 0]                            )
export var popupborderchars: list<string> = get(g:, 'zeef_popupborderchars', ['─', ' ', '─', ' ', ' ', ' ', ' ', ' '])
export var popupmaxheight:   number       = get(g:, 'zeef_popupmaxheight',   100                                     )
export var prompt:           string       = get(g:, 'zeef_prompt',           ' ❯ '                                   )
export var reuselastmode:    bool         = get(g:, 'zeef_reuselastmode',    false                                   )
export var sidescroll:       number       = get(g:, 'zeef_sidescroll',       5                                       )
export var skipfirst:        number       = get(g:, 'zeef_skipfirst',        0                                       )
export var stlname:          string       = get(g:, 'zeef_stlname',          'Zeef'                                  )
export var wildchar:         string       = get(g:, 'zeef_wildchar',         ' '                                     )
export var winheight:        number       = get(g:, 'zeef_winheight',        10                                      )
export var winhighlight:     string       = get(g:, 'zeef_winhighlight',     ''                                      )
# }}}
# Internal State {{{
const kEscapeChars = '~.\[:*' # Special characters that must be escaped when exact matching is used
const kUndoLevels  = 1000     # Undo levels. This basically limits the maximum length of the prompt

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
var sSkipFirst:              number       = 0      # How many characters to type before starting to filter
# The following are set when opening Zeef
var sDuplicateDeletion:      bool         = true   # Whether all duplicates should be removed when one is removed
var sDuplicateInsertion:     bool         = false  # Whether duplicate items in the result are allowed
var sEscapeChars:            string       = ''     # Characters to escape when using exact matching
var sLabel:                  string       = 'Zeef' # Prompt label
var sMultipleSelection:      bool         = true   # Whether muliple selections are allowed
var sWildChar:               string       = ''     # (Escaped) character interpreted as .* in exact matching

# Stack of booleans that tells whether to undo when pressing backspace.
# If the top of the stack is true then undo; if it is false, do not undo.
var sUndoStack:  list<bool> = []

# Commands to restore the window layout when Zeef's window is closed
var sWinRestCmd: string = ''

class Config
  static var AndChar          = () => escape(andchar, kEscapeChars)
  static var EscapeChars      = () => substitute(kEscapeChars, escape(wildchar, kEscapeChars), '', 'g')
  static var Fuzzy            = () => fuzzy
  static var KeyAliases       = () => keyaliases
  static var KeyMap           = () => keymap
  static var MatchFuzzyOpts   = () => matchseq ? {limit: limit, matchseq: matchseq} : {limit: limit}
  static var PopupBorder      = () => popupborder
  static var PopupBorderChars = () => popupborderchars
  static var PopupMaxHeight   = () => popupmaxheight
  static var Prompt           = () => sLabel .. (sFuzzy ? fuzzylabel : exactlabel) .. prompt
  static var ReuseLastMode    = () => reuselastmode
  static var SideScroll       = () => sidescroll
  static var SkipFirst        = () => skipfirst
  static var StatusLineName   = () => stlname
  static var WildChar         = () => escape(wildchar, kEscapeChars)
  static var WinHeight        = () => winheight
  static var WinHighlight     = () => winhighlight
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

def ToggleItem(lnum: number)
  var item = getbufoneline(sBufnr, lnum)
  var itemExists = item->In(sResult)

  if itemExists
      RemoveFromSelection(item)
  else
    if !sMultipleSelection
      sResult = []
    endif

    AddToSelection(item)
  endif
enddef

def EchoPrompt()
  redrawstatus
  redraw
  echo "\r"
  echo Config.Prompt() .. sInput
enddef

def EchoResult(items: list<string>)
  echo items
enddef

# Default regexp filter for exact matching.
#
# This behaves mostly like globbing, except that ^ and $ can be used to anchor
# a pattern. All characters are matched literally except ^, $, and the
# wildchar; the latter matches zero 0 more characters.
def Regexp(input: string): string
  return substitute(escape(input, sEscapeChars), sWildChar, '.*', 'g')
enddef

def MatchExactly()
  clearmatches()

  var inputs = split(sInput, Config.AndChar())

  for input in inputs
    var regexp = Regexp(input)

    try
      execute 'silent keeppatterns g!:\m' .. regexp .. ':norm "_dd'
    catch /^Vim\%((\a\+)\)\=:E538:/  # Raised when all lines match
    endtry

    matchadd('ZeefMatch', '\c' .. regexp)
  endfor

  normal gg
enddef

def MatchFuzzily()
  var [lines, charpos, _] = matchfuzzypos(getbufline(sBufnr, 1, line('$')), sInput, Config.MatchFuzzyOpts())

  deletebufline(sBufnr, 1, '$')
  undojoin
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

  # Force a new change (see https://github.com/vim/vim/issues/15025)
  execute 'normal' "i\<c-g>u"

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

def OpenZeefBuffer(): number
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
        \ cursorlineopt=line
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
  var border = Config.PopupBorder()

  sPopupId = popup_create(sResult, {
    border:             border,
    borderchars:        Config.PopupBorderChars(),
    borderhighlight:    ['ZeefPopupBorderColor'],
    callback:           SelectionPopupClosed,
    close:              'none',
    col:                0,
    cursorline:         false,
    drag:               false,
    filter:             RemoveFromSelectionPopup,
    highlight:          'ZeefPopupWinColor',
    line:               screenpos(bufwinid(sBufnr), 1, 1).row - 1,
    maxheight:          Min(Config.PopupMaxHeight(), &lines - Config.WinHeight() - 10),
    maxwidth:           &columns - border[1] - border[3],
    minheight:          1,
    minwidth:           &columns - border[1] - border[3],
    padding:            [0, 0, 0, 0],
    pos:                'botleft',
    resize:             false,
    scrollbar:          true,
    scrollbarhighlight: 'ZeefPopupScrollbarColor',
    thumbhighlight:     'ZeefPopupScrollbarThumbColor',
    title:              sMultipleSelection ? 'Selected Items' : 'Selected Item',
    wrap:               false,
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

export def ActionCancel()
  sResult = []
  CloseSelectionPopup()
  CloseZeefBuffer()
  sFinish = true
enddef

def ActionClearPrompt()
  clearmatches()
  silent undo 0
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

  if mousepos.winid == bufwinid(sBufnr)
    ToggleItem(mousepos.line)
    UpdateSelectionPopupStatus()
  endif
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
  ActionClearPrompt()
enddef

def ActionToggleItem()
  ToggleItem(line('.'))
  UpdateSelectionPopupStatus()
enddef

def ActionUndo()
  sInput = strcharpart(sInput, 0, strchars(sInput) - 1)

  if !empty(sUndoStack) && remove(sUndoStack, -1)
    silent undo
    normal gg
  endif

  if !sFuzzy
    clearmatches()

    if strchars(sInput) > sSkipFirst
      var inputs = split(sInput, Config.AndChar())

      for input in inputs
        matchadd('ZeefMatch', '\c' .. Regexp(input))
      endfor
    endif
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
const kDefaultKeyMap = {
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

  if strchars(sInput) > sSkipFirst
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

def Finalize(Callback: func(list<string>))
  if Config.ReuseLastMode()
    fuzzy = sFuzzy
  endif

  sInput = ''

  if !empty(sResult)
    Callback(sResult)
  endif

  sResult = []
enddef
# }}}
# Init {{{
def InitState(label: string, options: dict<any>)
  sLabel              = label
  sSkipFirst          = get(options, 'skipfirst', Config.SkipFirst())
  sMultipleSelection  = get(options, 'multi', true)
  sDuplicateInsertion = get(options, 'dupinsert', false) && sMultipleSelection
  sDuplicateDeletion  = get(options, 'dupdelete', false) && sDuplicateInsertion
  sEscapeChars        = Config.EscapeChars()
  sWildChar           = Config.WildChar()
  sKeyMap             = extend(extend(get(options, 'keymap', {}), Config.KeyMap(), 'keep'), kDefaultKeyMap, 'keep')
  sKeyAliases         = extend(get(options, 'keyaliases', {}), Config.KeyAliases(), 'keep')
  sWinRestCmd         = winrestcmd()
  sInput              = ''
  sResult             = []
  sFinish             = false
  sFuzzy              = Config.Fuzzy()
  sBufnr              = OpenZeefBuffer()
enddef

def StartZeef(Callback: func(list<string>))
  setbufvar(sBufnr, '&undolevels', kUndoLevels)
  normal gg
  EventLoop()
  Finalize(Callback)
enddef
# }}}
# Public Interface {{{
export def Open(
    items:       list<string>,
    Callback:    func(list<string>) = EchoResult,
    promptLabel: string             = 'Zeef',
    options:     dict<any>          = {},
    )
  InitState(promptLabel, options)

  setbufvar(sBufnr, '&undolevels', -1)
  setbufline(sBufnr, 1, items)

  StartZeef(Callback)
enddef

def CheckKeyPress(tid: number, jid: job)
  if job_status(jid) != 'run'
    timer_stop(tid)
    return
  endif

  if getchar(0) == 27  # Press Esc to stop the job
    job_stop(jid)
    timer_stop(tid)
  endif
enddef

export def OpenCmd(
    cmd:         any,  # list or string
    Callback:    func(list<string>) = EchoResult,
    promptLabel: string             = 'Zeef',
    options:     dict<any>          = {},
    )
  InitState(promptLabel, options)

  setbufvar(sBufnr, '&undolevels', -1)  # Disable undo for the duration of the job

  var jid = job_start(cmd, {
    close_cb: (ch) => StartZeef(Callback),
    cwd:      get(options, 'cwd',     getcwd()),
    env:      get(options, 'env',     {}      ),
    err_buf:  get(options, 'err_buf', sBufnr  ),
    err_io:   get(options, 'err_io',  'null'  ),
    err_name: '',
    in_io:    'null',
    out_buf:  sBufnr,
    out_io:   'buffer',
  })

  var timerId = timer_start(5, (tid) => CheckKeyPress(tid, jid), {repeat: -1})
enddef

export def LastKeyPressed(): string
  return sKeyAlias
enddef

export def SelectedItems(): list<string>
  if empty(sResult)
    return getbufline(sBufnr, line('.'))
  else
    return sResult
  endif
enddef

export def ClearPrompt()
  ActionClearPrompt()
enddef

export def DeselectAll()
  ActionDeselectAll()
enddef

export def Dismiss()
  ActionCancel()
enddef
# }}}}
# Zeefs {{{
# Path Filters {{{
export def SetArglist(items: list<string>)
  execute 'args' join(mapnew(items, (_, p) => fnameescape(p)))
enddef

def Paths(paths: list<string>, options: dict<any>): list<string>
  if get(options, 'fullpath', false)
    return mapnew(paths, (_, p) => fnamemodify(p, ':p'))
  endif
  return paths
enddef

# Filter a list of paths and populate the arglist with the selected items.
export def Args(paths: list<string>, options: dict<any> = {})
  Open(Paths(paths, options), SetArglist, 'Choose files', options)
enddef

# Ditto, but use the paths in the specified directory
export def Files(directory = getcwd(), options: dict<any> = {})
  var dir = fnamemodify(directory, ':p')
  var cmd = executable('rg') ? ['rg', '--files', dir] : ['find', dir, '-type', 'f']

  OpenCmd(cmd, SetArglist, 'Choose files', options)
enddef
# }}}
# Buffer Switcher {{{
def SwitchToBuffer(items: list<string>)
  execute 'buffer' matchstr(items[0], '^\s*\d\+')
enddef

export def BufferSwitcher(options: dict<any> = {})
  var fullpath = get(options, 'fullpath', false)
  var buffers: list<string> = []

  for info in getbufinfo(options)
    var bufline = printf('%4d ', info.bufnr)

    if empty(info.name)
      var buftype = getbufvar(info.bufnr, '&buftype')

      if empty(buftype)
        buftype = '[No Name]'
      endif

      bufline ..= buftype

      if fullpath
        bufline ..= '   ' .. getbufoneline(info.bufnr, 1)
      endif
    else
      bufline ..= fnamemodify(info.name, ':t')

      if fullpath
        bufline ..= '   ' .. info.name
      endif
    endif

    buffers->add(bufline)
  endfor

  Open(buffers, SwitchToBuffer, 'Choose buffer', {multi: false})
enddef

# }}}
# Quickfix/Location List Filter {{{
def JumpToQuickfixEntry(items: list<string>)
  execute 'crewind' matchstr(items[0], '^\s*\d\+')
enddef

def JumpToLocationListEntry(items: list<string>)
  execute 'lrewind' matchstr(items[0], '^\s*\d\+')
enddef

export def QuickfixList(Callback = JumpToQuickfixEntry, options: dict<any> = {})
  var qflist = getqflist()

  if empty(qflist)
    Msg('Quickfix list is empty.')
    return
  endif

  var cmd = split(execute('clist'), "\n")

  Open(cmd, Callback, 'Filter quickfix entry', options)
enddef

export def LocationList(winnr = 0, Callback = JumpToLocationListEntry, options: dict<any> = {})
  var loclist = getloclist(winnr)

  if empty(loclist)
    Msg('Location list is empty.')
    return
  endif

  var cmd = split(execute('llist'), "\n")

  Open(cmd, Callback, 'Filter loclist entry', options)
enddef
# }}}
# Find Color Scheme {{{
def SetColorscheme(items: list<string>)
  execute 'colorscheme' items[0]
enddef

export def ColorschemeSwitcher(options: dict<any> = {})
  var searchPaths = [
    globpath(&runtimepath, 'colors/*.vim',                      0, 1),
    globpath(&packpath,    'pack/*/{opt,start}/*/colors/*.vim', 0, 1),
  ]
  var colorschemes = []

  for pathList in searchPaths
    colorschemes += map(pathList, (_, p): string => fnamemodify(p, ':t:r'))
  endfor

  uniq(sort(colorschemes))

  Open(colorschemes,
    SetColorscheme,
    'Choose colorscheme',
    extend(options, {multi: false}, 'keep')
  )
enddef
# }}}
# Buffer Tags Using Ctags {{{
const kCtagsBin = executable('uctags') ? 'uctags' : 'ctags'

def JumpToTag(item: string)
  # Jump to a tag. Item must have the following format:
  # <tag name> <kind> <line number> <file> ...
  var fields = split(item)

  if len(fields) < 4
    Msg($'Failed to parse Ctags entry: {item}')
    return
  endif

  execute $'buffer +{fields[2]} {fields[3]}'
enddef

export def BufferTags(options: dict<any> = {})
  var names: list<string>

  if get(options, 'all', false)
    names = map(
      getbufinfo({buflisted: true}), (_, info) => info.name
    )
  else
    names = [getbufinfo('%')[0].name]
  endif

  filter(names, (_, name) => !empty(name))

  if empty(names)
    Msg('Saving the buffer(s) is required to search for tags.')
    return
  endif

  var ctagsPath  = get(options, 'bin', kCtagsBin)
  var cmd        = [ctagsPath, '-x', '--sort=no'] + names

  OpenCmd(cmd,
    (t: list<string>) => JumpToTag(t[0]),
    'Choose tag',
    extend(options, {multi: false}, 'keep')
  )
enddef
# }}}
# }}}
