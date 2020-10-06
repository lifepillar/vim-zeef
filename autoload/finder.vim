" Name:        Finder
" Author:      Lifepillar <lifepillar@lifepillar.me>
" Maintainer:  Lifepillar <lifepillar@lifepillar.me>
" License:     Public domain

" Internal state {{{
const s:prompt = get(g:, 'finder_prompt', ' ❯❯ ')
" Finder's buffer number
let s:bufnr = -1
" Window layout to restore when the finder is closed
let s:winrestsize = {}
" The items to be filtered
let s:items = []
" The selected items
let s:result = []
" The callback to be invoked on the selected items
let s:callback = ''
" The latest key press
let s:keypressed = ''
" Text used to filter the input list
let s:filter = ''
" Stack of 0s/1s that tells whether to undo when pressing backspace.
" If the top of the stack is 1 then undo; if it is 0, do not undo.
let s:undoseq = []
" }}}
" Key actions {{{
fun! finder#up()
  norm k
  return 0
endf

fun! finder#down()
  norm j
  return 0
endf

fun! finder#right()
  norm 5zl
  return 0
endf

fun! finder#left()
  norm 5zh
  return 0
endf

fun! finder#passthrough()
  execute "normal" s:keypressed
  return 0
endf

fun! finder#clear()
  call setline(1, s:items)
  let s:undoseq = []
  let s:filter = ''
  return 0
endf

fun! finder#close(action)
  call add(s:result, getline('.'))
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

call prop_type_delete('foo')
call prop_type_add('foo', {'highlight': 'Error'})

fun! finder#toggle()
  let l:idx = index(s:result, getline('.'))
  if l:idx != -1
    call remove(s:result, l:idx)
    call prop_remove(#{ type: 'foo' }, line('.'))
  else
    call add(s:result, getline('.'))
    call prop_add(line('.'), 1,  #{ type: 'foo', length: len(getline('.')) })
  endif
  return 0
endf

fun! s:accept(action)
  call finder#close(a:action)
  if !empty(s:result)
    call function(s:callback)(s:result)
  endif
  return 1
endf

fun! finder#accept()
  return s:accept('')
endf

fun! finder#accept_split()
  return s:accept('split')
endf

fun! finder#accept_vsplit()
  return s:accept('vsplit')
endf

fun! finder#accept_tabnew()
  return s:accept('tabnew')
endf
" }}}
" Keymap {{{
let s:keymap = extend({
      \ "\<c-k>":   function('finder#up'),
      \ "\<up>":    function('finder#up'),
      \ "\<c-j>":   function('finder#down'),
      \ "\<down>":  function('finder#down'),
      \ "\<left>":  function('finder#left'),
      \ "\<right>": function('finder#right'),
      \ "\<c-b>":   function('finder#passthrough'),
      \ "\<c-d>":   function('finder#passthrough'),
      \ "\<c-e>":   function('finder#passthrough'),
      \ "\<c-y>":   function('finder#passthrough'),
      \ "\<c-f>":   function('finder#passthrough'),
      \ "\<c-u>":   function('finder#passthrough'),
      \ "\<c-l>":   function('finder#clear'),
      \ "\<c-z>":   function('finder#toggle'),
      \ "\<enter>": function('finder#accept'),
      \ "\<c-s>":   function('finder#accept_split'),
      \ "\<c-v>":   function('finder#accept_vsplit'),
      \ "\<c-t>":   function('finder#accept_tabnew'),
      \ }, get(g:, "finder_keymap", {}))
" }}}
" Main interface {{{

" Default regexp filter.
"
" This behaves mostly like globbing, except that ^ and $ can be used to anchor
" a pattern. All characters are matched literally except ^, $, and *; the
" latter matches zero 0 more characters.
fun! s:default_regexp(input)
  return substitute(escape(a:input, '~.\[:'), '\*', '.*', 'g')
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
  let s:result = []

  " botright 10new does not set the right height, e.g., if the quickfix window is open
  execute printf("botright :1new | %dwincmd +", get(g:, 'finder_height', 9))

  setlocal buftype=nofile bufhidden=wipe nobuflisted
        \  modifiable noreadonly noswapfile noundofile
        \  foldmethod=manual nofoldenable nospell
        \  nowrap scrolloff=0 winfixheight
        \  cursorline nonumber norelativenumber
        \  statusline=%#CommandMode#\ Finder\ %*\ %l\ of\ %L

  let s:bufnr = bufnr('%')

  call finder#clear()

  let l:Regexp = get(g:, 'Finder_regexp', function('s:default_regexp'))
  let l:prompt = a:label .. s:prompt
  echo l:prompt
  redraw

  while 1
    let &ro=&ro     " Force status line update
    let l:error = 0 " Set to 1 when the input pattern is invalid
    let s:keypressed = ''

    try
      let ch = getchar()
    catch /^Vim:Interrupt$/  " CTRL-C
      return finder#close('')
    endtry

    let s:keypressed = (type(ch) == 0 ? nr2char(ch) : ch)

    if ch >=# 0x20 " Printable character
      let s:filter ..= s:keypressed
      if strchars(s:filter) < get(g:, 'finder_skip_first', 0)
        redraw
        echo l:prompt s:filter
        continue
      endif
      let l:seq_old = get(undotree(), 'seq_cur', 0)
      try
        execute 'silent keeppatterns g!:\m' .. l:Regexp(s:filter) .. ':norm "_dd'
      catch /^Vim\%((\a\+)\)\=:E/
        let l:error = 1
      endtry
      let l:seq_new = get(undotree(), 'seq_cur', 0)
      call add(s:undoseq, l:seq_new != l:seq_old) " seq_new != seq_old iff the buffer has changed
      norm gg
    elseif s:keypressed ==# "\<bs>" " Backspace
      let s:filter = strcharpart(s:filter, 0, strchars(s:filter) - 1)
      if (empty(s:undoseq) ? 0 : remove(s:undoseq, -1))
        silent undo
      endif
      norm gg
    elseif s:keypressed == "\<esc>"
      return finder#close('')
    else
      if get(s:keymap, s:keypressed, function('s:noop'))()
        return
      endif
    endif

    redraw
    echo (l:error ? '[Invalid pattern] ' : '') .. l:prompt s:filter
  endwhile
endf
" }}}
" Sample applications {{{

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Simple path filters
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
fun! s:set_arglist(result)
  execute "args" join(map(a:result, 'fnameescape(v:val)'))
endf

" Filter a list of paths and populate the arglist with the selected items.
fun! finder#args(paths)
  call finder#open(a:paths, 's:set_arglist', 'Choose files')
endf

" Ditto, but use the paths in the specified directory
fun! finder#file(...) " ... is an optional directory
  let l:dir = (a:0 > 0 ? a:1 : '.')
  call finder#open(systemlist(executable('rg') ? 'rg --files ' .. l:dir : 'find ' .. l:dir .. ' -type f'), 's:set_arglist', 'Choose files')
endf

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" A buffer switcher
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
fun! s:switch_to_buffer(result)
  execute "buffer" matchstr(a:result[0], '^\s*\zs\d\+')
endf

" props is a dictionary with the following keys:
"   - unlisted: when set to 1, show also unlisted buffers
fun! finder#buffer(props)
  let l:buffers = map(split(execute('ls' .. (get(a:props, 'unlisted', 0) ? '!' : '')), "\n"), { i,v -> substitute(v, '"\(.*\)"\s*line\s*\d\+$', '\1', '') })
  call finder#open(l:buffers, 's:switch_to_buffer', 'Switch buffer')
endf

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Find in quickfix/location list
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
fun! s:jump_to_qf_entry(result)
  execute "crewind" matchstr(a:result[0], '^\s*\d\+', '')
endf

fun! s:jump_to_loclist_entry(result)
  execute "lrewind" matchstr(a:result[0], '^\s*\d\+', '')
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

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Find colorscheme
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
fun! s:set_colorscheme(result)
  execute "colorscheme" a:result[0]
endf

let s:colors = []

fun! finder#colorscheme()
  if empty(s:colors)
    let s:colors = map(globpath(&runtimepath, "colors/*.vim", v:false, v:true) , 'fnamemodify(v:val, ":t:r")')
    let s:colors += map(globpath(&packpath, "pack/*/{opt,start}/*/colors/*.vim", v:false, v:true) , 'fnamemodify(v:val, ":t:r")')
  endif
  call finder#open(s:colors, 's:set_colorscheme', 'Choose colorscheme')
endf

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" For tests
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
fun! s:test(result)
  echo a:result
endf

fun! finder#test()
  call finder#open(['a😉', 'b', 'c😉❯❯', 'd😉❯ye', 'e ❯🎺'], 's:test', 'Select multiple')
endf
" }}}
