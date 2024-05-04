vim9script

# Requirements Check {{{
if !has('popupwin') || !has('textprop') || v:version < 901
  export def Open(
      items: list<string>, F: func(list<string>) = null_function, promptLabel = ''
      )
    echomsg 'Zeef requires Vim 9.1 compiled with popupwin and textprop.'
  enddef
  finish
endif
# }}}
# Settings and Internal State {{{
var sName:           string             = get(g:, 'zeef_stl_name', 'Zeef9')
var sHeight:         number             = get(g:, 'zeef_height', 10) - 1
var sPrompt:         string             = get(g:, 'zeef_prompt', '> ')
var sSkipFirst:      number             = get(g:, 'zeef_skip_first', 0)
var sHorizScroll:    number             = get(g:, 'zeef_horizontal_scroll', 5)
var sPopupMaxHeight: number             = 100
var sBufnr:          number             = -1     # Zeef buffer number
var sLabel:          string             = 'Zeef' # Prompt label
var sInput:          string             = ''     # The user input
var sKeyPress:       string             = ''     # Last key press
var sResult:         list<string>       = []     # The selected items
var sPopupId:        number             = -1     # ID of the selection popup (for multiple selection)

# Stack of booleans that tells whether to undo when pressing backspace.
# If the top of the stack is true then undo; if it is false, do not undo.
var sUndoStack:  list<bool> = []

# Commands to restore the window layout when Zeef's window is closed
var sWinRestCmd: string = ''
# }}}
# Selection Popup {{{
def SelectionPopupClosed(winId: number, result: any = '')
  sPopupId = -1
enddef

def IsSelectionPopupVisible(): bool
  return sPopupId > 0 && get(popup_getpos(sPopupId), 'visible', false)
enddef

def ShowSelectionPopup()
  if sPopupId <= 0
    sPopupId = popup_create(sResult, {
      border: [1, 1, 1, 1],
      borderchars: ['-', '|', '-', '|', '┌', '┐', '┘', '└'],
      borderhighlight: ['Label'],
      callback: SelectionPopupClosed,
      close: 'button',
      col: 1,
      cursorline: false,
      drag: false,
      highlight: 'Identifier',
      line: screenpos(bufwinid(sBufnr), 1, 1).row - 1,
      minheight: 1,
      maxheight: Min(sPopupMaxHeight, &lines - sHeight - 10),
      padding: [0, 1, 0, 1],
      pos: 'botleft',
      resize: false,
      scrollbar: true,
      title: 'Selected Items',
      minwidth: &columns - 5,
      maxwidth: &columns - 5,
      wrap: false,
      zindex: 32000,
    })
  else
    popup_settext(sPopupId, sResult)
    popup_show(sPopupId)
  endif
enddef

def HideSelectionPopup()
  popup_hide(sPopupId)
enddef

def RefreshSelectionPopup()
  if IsSelectionPopupVisible()
    if len(sResult) > 0
      popup_settext(sPopupId, sResult)
    else
      HideSelectionPopup()
    endif
  endif
enddef
# }}}
# Helper Function {{{
def Min(m: number, n: number): number
  return m < n ? m : n
enddef

def AddToSelection(lnum: number, allowDuplicates = false)
  var line = getline(lnum)

  if !allowDuplicates && index(sResult, line) != -1
    return
  endif

  add(sResult, getline(lnum))

  if len(sResult) > 0
    ShowSelectionPopup()
  endif
enddef

def RemoveFromSelection(lnum: number)
  var line = getline(lnum)
  var newResult: list<string> = []

  for item in sResult
    if item != line
      newResult->add(item)
    endif
  endfor

  sResult = newResult

  RefreshSelectionPopup()
enddef

def EchoPrompt()
  redraw
  echo "\r"
  echo sLabel .. sPrompt .. sInput
enddef

def EchoResult(items: list<string>)
  echo sResult
enddef

def FuzzyFilter(): number
  var [lines, charpos, _] = matchfuzzypos(
    getbufline(bufnr(), 1, line('$')), sInput, {}
  )

  deletebufline(bufnr(), 1, '$')
  setbufline(bufnr(), 1, lines)

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

  return 0
enddef

def g:ZeefStatusLine(): string
  return $'%#ZeefName# {sName} %* %l of %L' .. (empty(sResult) ? '' : $' ({len(sResult)} selected)')
enddef

def OpenZeefBuffer(items: list<string>): number
  # botright 10new may not set the right height, e.g., if the quickfix window is open
  execute $'botright :1new | :{sHeight}wincmd +'

  hi default link ZeefMatch Label
  hi default link ZeefName StatusLine

  prop_type_add('zeefmatch', {bufnr: bufnr(), 'highlight': 'ZeefMatch'})

  abclear <buffer>
  setlocal
        \ bufhidden=wipe
        \ buftype=nofile
        \ colorcolumn&
        \ cursorline
        \ filetype=zeef
        \ foldmethod=manual
        \ formatexpr=FuzzyFilter()
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

def CloseSelectionPopup()
  if sPopupId > 0
    popup_close(sPopupId)
  endif
  sPopupId = -1
enddef

def CloseZeefBuffer()
  CloseSelectionPopup()
  wincmd p
  execute 'bwipe!' sBufnr
  execute sWinRestCmd
  sBufnr = -1
  redraw
  echo "\r"
enddef
# }}}
# Actions {{{
def Accept(): bool
  if empty(sResult)
    add(sResult, getline('.'))
  endif

  CloseZeefBuffer()

  return false
enddef

def Cancel(): bool
  CloseZeefBuffer()
  sResult = []

  return false
enddef

def Clear(): bool
  silent undo 1

  sUndoStack = []
  sInput = ''

  return true
enddef

def DeselectAll(): bool
  sResult = []
  popup_close(sPopupId)
  sPopupId = -1

  return true
enddef

def DeselectCurrent(): bool
  var i = 1
  var n = line('$')

  while i <= n
    RemoveFromSelection(i)
    ++i
  endwhile

  return true
enddef

def MoveUp(): bool
  normal k
  return true
enddef

def Noop(): bool
  return true
enddef

def Passthrough(): bool
  execute 'normal' sKeyPress
  return true
enddef

def ScrollLeft(): bool
  execute $'normal {sHorizScroll}zh'
  return true
enddef

def ScrollRight(): bool
  execute $'normal {sHorizScroll}zl'
  return true
enddef

def SelectCurrent(): bool
  var i = 1
  var n = line('$')

  while i <= n
    AddToSelection(i)
    ++i
  endwhile

  return true
enddef

def SplitAccept(): bool
  Accept()
  split
  return false
enddef

def TabNewAccept(): bool
  Accept()
  tabnew
  return false
enddef

def Toggle(): bool
  if index(sResult, getline(line('.'))) == -1
    AddToSelection(line('.'))
  else
    RemoveFromSelection(line('.'))
  endif

  return true
enddef

def Undo(): bool
  sInput = strcharpart(sInput, 0, strchars(sInput) - 1)

  if !empty(sUndoStack) && remove(sUndoStack, -1)
    silent undo
  endif

  return true
enddef

def VertSplitAccept(): bool
  Accept()
  vsplit
  return false
enddef

def ToggleSelected(): bool
  if IsSelectionPopupVisible()
    HideSelectionPopup()
  else
    ShowSelectionPopup()
  endif
  return true
enddef
# }}}
# Key Map {{{
var sKeyMap = {
  "\<ScrollWheelDown>":  Passthrough,
  "\<ScrollWheelLeft>":  Passthrough,
  "\<ScrollWheelRight>": Passthrough,
  "\<ScrollWheelUp>":    Passthrough,
  "\<bs>":               Undo,
  "\<c-a>":              SelectCurrent,
  "\<c-b>":              Passthrough,
  "\<c-d>":              Passthrough,
  "\<c-e>":              Passthrough,
  "\<c-f>":              Passthrough,
  "\<c-g>":              DeselectAll,
  "\<c-j>":              Passthrough,
  "\<c-k>":              MoveUp,
  "\<c-l>":              Clear,
  "\<c-r>":              DeselectCurrent,
  "\<c-s>":              SplitAccept,
  "\<c-t>":              TabNewAccept,
  "\<c-u>":              Passthrough,
  "\<c-v>":              VertSplitAccept,
  "\<c-w>":              ToggleSelected,
  "\<c-y>":              Passthrough,
  "\<c-z>":              Toggle,
  "\<down>":             Passthrough,
  "\<enter>":            Accept,
  "\<esc>":              Cancel,
  "\<left>":             ScrollLeft,
  "\<right>":            ScrollRight,
  "\<up>":               Passthrough,
  '':                    Cancel,
}
# }}}
# Event Processing  {{{
def GetKeyPress(): string
  try
    return getcharstr()
  catch /^Vim:Interrupt$/ # CTRL-C
    return ''
  endtry

  return ''
enddef

def ProcessKeyPress(): bool
  if sKeyMap->has_key(sKeyPress)
    var keepGoing = sKeyMap[sKeyPress]()
    return keepGoing
  endif

  # Skip other non-printable characters
  if char2nr(sKeyPress[0]) == 0x80
    return true
  endif

  sInput ..= sKeyPress

  if strchars(sInput) > sSkipFirst
    var old_seq = get(undotree(), 'seq_cur', 0)
    normal gggqG
    var new_seq = get(undotree(), 'seq_cur', 0)

    add(sUndoStack, new_seq != old_seq) # new_seq != old_seq iff the buffer has changed
  endif

  return true
enddef

def EventLoop()
  while true
    redrawstatus

    EchoPrompt()
    sKeyPress = GetKeyPress()

    if !ProcessKeyPress()
      break
    endif
  endwhile
enddef
# }}}
# Public Interface {{{
export def Open(
    items: list<string>, F: func(list<string>) = EchoResult, promptLabel = 'Zeef'
    )
  sLabel      = promptLabel
  sInput      = ''
  sResult     = []
  sWinRestCmd = winrestcmd()
  sBufnr      = OpenZeefBuffer(items)

  EventLoop()

  if !empty(sResult)
    F(sResult)
  endif
enddef
# }}}}
