" Name:        Finder
" Author:      Lifepillar <lifepillar@lifepillar.me>
" Maintainer:  Lifepillar <lifepillar@lifepillar.me>
" License:     Public domain

const s:prompt = get(g:, 'finder_prompt', ' ❯❯ ')

" Finder's buffer number
let s:bufnr = -1
" Window layout to restore when Finder is closed
let s:winrestsize = {}
" The items to be filtered
let s:items = []
" The selected item
let s:result = ''
" The callback to be invoked on the selected item
let s:callback = ''
" The latest key press
let s:keypressed = ''
" Text used to filter the list
let s:filter = ''
" Stack of 0s/1s that tells whether to undo when pressing backspace.
" If the top of the stack is 1 then undo; if it is 0, do not undo.
let s:undoseq = []

let s:keymap = extend({
      \ "\<c-k>":   "norm k",
      \ "\<up>":    "norm k",
      \ "\<c-j>":   "norm j",
      \ "\<down>":  "norm j",
      \ "\<left>":  "norm 5zh",
      \ "\<right>": "norm 5zl",
      \ "\<c-b>":   'execute "normal" "\<c-b>"',
      \ "\<c-d>":   'execute "normal" s:keypressed',
      \ "\<c-e>":   'execute "normal" s:keypressed',
      \ "\<c-y>":   'execute "normal" s:keypressed',
      \ "\<c-f>":   'execute "normal" s:keypressed',
      \ "\<c-u>":   'execute "normal" s:keypressed',
      \ "\<c-l>":   "return finder#clear()",
      \ "\<enter>": "return finder#accept('')",
      \ "\<c-s>":   "return finder#accept('split')",
      \ "\<c-v>":   "return finder#accept('vsplit')",
      \ "\<c-t>":   "return finder#accept('tabnew')",
      \ "":         "",
      \ }, get(g:, "finder_keymap", {}))

fun! s:do()
  execute get(s:keymap, s:keypressed, "")
  return 0
endf

fun! finder#clear()
  call setline(1, s:items)
  let s:undoseq = []
  let s:filter = ''
  return 0
endf

fun! finder#close(action)
  let s:result = getline('.')
  wincmd p
  execute "bwipe!" s:bufnr
  execute s:winrestsize
  if index(['split', 'vsplit', 'tabnew'], a:action) != -1
    execute a:action
  endif
  redraw
  echo "\r"
  return 1
endf

fun! finder#result()
  return s:result
endf

fun! finder#keypressed()
  return s:keypressed
endf

fun! finder#accept(action)
  call finder#close(a:action)
  if !empty(s:result)
    call function(s:callback)()
  endif
  return 1
endf

" Interactively filter a list of items as you type,
" and execute an action on the selected item.
"
" items: A List of items to be filtered
" callback: A function, funcref, or lambda to be called on the selected item(s)
" label: A name for the finder's prompt
fun! finder#open(items, callback, label) abort
  let s:winrestsize = winrestcmd()
  let s:items = a:items
  let s:callback = a:callback

  " botright 10new does not set the right height, e.g., if the quickfix window is open
  botright 1new | 9wincmd +

  setlocal buftype=nofile bufhidden=wipe cursorline foldmethod=manual modifiable
        \  nobuflisted nofoldenable nonumber noreadonly norelativenumber nospell
        \  noswapfile noundofile nowrap scrolloff=0 winfixheight
  setlocal statusline=%#CommandMode#\ Finder\ %*\ %l\ of\ %L
  let s:bufnr = bufnr('%')

  let l:prompt = a:label .. s:prompt
  echo l:prompt

  call finder#clear()
  redraw

  while 1
    let &ro=&ro     " Force status line update
    let l:error = 0 " Set to 1 when the input pattern is invalid
    let s:keypressed = ''

    try
      let ch = getchar()
    catch /^Vim:Interrupt$/  " CTRL-C
      let s:keypressed = "\<c-c>"
      let s:result = ''
      return finder#close('')
    endtry

    let s:keypressed = (type(ch) == 0 ? nr2char(ch) : ch)

    if ch >=# 0x20 " Printable character
      let s:filter ..= s:keypressed
      let l:seq_old = get(undotree(), 'seq_cur', 0)
      try
        execute 'silent keeppatterns g!:\m' .. substitute(escape(s:filter, '~.\[:'), '\*', '.*', 'g') .. ':norm "_dd'
      catch /^Vim\%((\a\+)\)\=:E/
        echomsg "ERROR"
        let l:error = 1
      endtry
      let l:seq_new = get(undotree(), 'seq_cur', 0)
      call add(s:undoseq, l:seq_new != l:seq_old) " seq_new != seq_old iff buffer has changed
      norm gg
    elseif s:keypressed ==# "\<bs>" " Backspace
      let s:filter = s:filter[:-2]
      if (empty(s:undoseq) ? 0 : remove(s:undoseq, -1))
        silent undo
      endif
      norm gg
    elseif s:keypressed == "\<esc>"
      return finder#close('')
    else
      if s:do()
        return
      endif
    endif

    redraw
    echo (l:error ? '[Invalid pattern] ' : '') .. l:prompt s:filter
  endwhile
endf


"
" Find a file
"
fun! s:set_arglist()
  let paths = [finder#result()]
  execute "args" join(map(paths, 'fnameescape(v:val)'))
endf

" Filter a list of paths and populate the arglist with the selected items.
fun! finder#args(paths)
  call finder#open(a:paths, 's:set_arglist', 'Choose file')
endf

fun! finder#file(...) " ... is an optional directory
  let l:dir = (a:0 > 0 ? a:1 : '.')
  call finder#open(systemlist(executable('rg') ? 'rg --files ' .. l:dir : 'find ' .. l:dir .. ' -type f'), 's:set_arglist', 'Choose file')
endf

"
" Find buffer
"
fun! s:switch_to_buffer()
  execute "buffer" split(finder#result(), '\s\+')[0]
endf


" When 'unlisted' is set to 1, show also unlisted buffers
fun! finder#buffer(unlisted)
  let l:buffers = map(split(execute('ls'.(a:unlisted ? '!' : '')), "\n"), { i,v -> substitute(v, '"\(.*\)"\s*line\s*\d\+$', '\1', '') })
  call finder#open(l:buffers, 's:switch_to_buffer', 'Switch buffer')
endf

"
" Find in quickfix/location list
"
fun! s:jump_to_qf_entry()
  let items = [finder#result()]
  execute "crewind" matchstr(a:items[0], '^\s*\d\+', '')
endf

fun! s:jump_to_loclist_entry()
  let items = [finder#result()]
  execute "lrewind" matchstr(items[0], '^\s*\d\+', '')
endf

fun! finder#qflist()
  let l:qflist = getqflist()
  if empty(l:qflist)
    echo '[Finder] Quickfix list is empty'
    return
  endif
  call finder#open(split(execute('clist'), "\n"), 's:jump_to_qf_entry', 'Filter quickfix entry')
endf

fun! finder#loclist(winnr)
  let l:loclist = getloclist(a:winnr)
  if empty(l:loclist)
    echo '[Finder] Location list is empty'
    return
  endif
  call finder#open(split(execute('llist'), "\n"), 's:jump_to_loclist_entry', 'Filter loclist entry')
endf

"
" Find colorscheme
"
fun! s:set_colorscheme()
  let colors = [finder#result()]
  execute "colorscheme" colors[0]
endf

let s:colors = []

fun! finder#colorscheme()
  if empty(s:colors)
    let s:colors = map(globpath(&runtimepath, "colors/*.vim", v:false, v:true) , 'fnamemodify(v:val, ":t:r")')
    let s:colors += map(globpath(&packpath, "pack/*/{opt,start}/*/colors/*.vim", v:false, v:true) , 'fnamemodify(v:val, ":t:r")')
  endif
  call finder#open(s:colors, 's:set_colorscheme', 'Choose colorscheme')
endf

