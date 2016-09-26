"
" neovim-fuzzy
"
" Author:       Alexis Sellier <http://cloudhead.io>
" Version:      0.1
"
if exists("g:loaded_fuzzy") || &cp || !has('nvim')
  finish
endif
let g:loaded_fuzzy = 1

if !exists("g:fuzzy_opencmd")
  let g:fuzzy_opencmd = 'edit'
endif

let s:fuzzy_job_id = 0
let s:fuzzy_prev_window = -1
let s:fuzzy_prev_window_height = -1
let s:fuzzy_bufnr = -1
let s:fuzzy_source = {}

function! s:fuzzy_err_noexec()
  throw "Fuzzy: no search executable was found. " .
      \ "Please make sure either '" .  s:ag.path .
      \ "' or '" . s:rg.path . "' are in your path"
endfunction

" Methods to be replaced by an actual implementation.
function! s:fuzzy_source.find(il) dict
  call s:fuzzy_err_noexec()
endfunction

function! s:fuzzy_source.find_contents() dict
  call s:fuzzy_err_noexec()
endfunction

"
" ag (the silver searcher)
"
let s:ag = { 'path': 'ag' }

function! s:ag.find(ignorelist) dict
  let ignorefile = tempname()
  call writefile(a:ignorelist, ignorefile, 'w')
  return systemlist(
    \ "ag --silent --nocolor -g '' -Q --path-to-agignore " . ignorefile)
endfunction

function! s:ag.find_contents() dict
  return systemlist("ag --noheading --nogroup --nocolor '^(?=.)' .")
endfunction

"
" rg (ripgrep)
"
let s:rg = { 'path': 'rg' }

function! s:rg.find(ignorelist) dict
  let ignores = []
  for str in a:ignorelist
    call add(ignores, printf("-g '!%s'", str))
  endfor
  return systemlist("rg --color never --files --fixed-strings " . join(ignores, ' '))
endfunction

function! s:rg.find_contents() dict
  return systemlist("rg -n --no-heading --color never '.' .")
endfunction

" Set the finder based on available binaries.
if executable(s:rg.path)
  let s:fuzzy_source = s:rg
elseif executable(s:ag.path)
  let s:fuzzy_source = s:ag
endif

command! FuzzySearch call s:fuzzy_search()
command! FuzzyOpen   call s:fuzzy_open()
command! FuzzyKill   call s:fuzzy_kill()

autocmd FileType fuzzy tnoremap <buffer> <Esc> <C-\><C-n>:FuzzyKill<CR>

function! s:fuzzy_kill()
  echo
  call jobstop(s:fuzzy_job_id)
endfunction

function! s:fuzzy_search() abort
  try
    let contents = s:fuzzy_source.find_contents()
  catch
    echoerr v:exception
    return
  endtry

  let opts = { 'lines': 12 }

  function! opts.handler(result) abort
    let parts = split(join(a:result), ':')
    let name = parts[0]
    let lnum = parts[1]
    let text = parts[2] " Not used.

    return { 'name': name, 'lnum': lnum }
  endfunction

  return s:fuzzy(contents, opts)
endfunction

function! s:fuzzy_open() abort
  " Get open buffers.
  let bufs = filter(range(1, bufnr('$')),
    \ 'buflisted(v:val) && bufnr("%") != v:val && bufnr("#") != v:val')
  let bufs = map(bufs, 'bufname(v:val)')
  call reverse(bufs)

  " Add the '#' buffer at the head of the list.
  if bufnr('#') > 0 && bufnr('%') != bufnr('#')
    call insert(bufs, bufname('#'))
  endif

  " Save a list of files the find command should ignore.
  let ignorelist = !empty(bufname('%')) ? bufs + [bufname('%')] : bufs

  " Get all files, minus the open buffers.
  try
    let files = s:fuzzy_source.find(ignorelist)
  catch
    echoerr v:exception
    return
  endtry

  " Put it all together.
  let result = bufs + files

  let opts = { 'lines': 12 }
  function! opts.handler(result)
    return { 'name': join(a:result) }
  endfunction

  return s:fuzzy(result, opts)
endfunction

function! s:fuzzy(choices, opts) abort
  let inputs = tempname()
  let outputs = tempname()

  if !executable('fzy')
    echoerr "Fuzzy: the executable 'fzy' was not found in your path"
    return
  endif

  " Clear the command line.
  echo

  call writefile(a:choices, inputs)

  let command = "fzy -l " . a:opts.lines . " > " . outputs . " < " . inputs
  let opts = { 'outputs': outputs, 'handler': a:opts.handler }

  function! opts.on_exit(id, code) abort
    " NOTE: The order of these operations is important: Doing the delete first
    " would leave an empty buffer in netrw. Doing the resize first would break
    " the height of other splits below it.
    call win_gotoid(s:fuzzy_prev_window)
    exe 'silent' 'bdelete!' s:fuzzy_bufnr
    exe 'resize' s:fuzzy_prev_window_height

    if a:code != 0 || !filereadable(self.outputs)
      return
    endif

    let result = readfile(self.outputs)
    if !empty(result)
      let file = self.handler(result)
      silent execute g:fuzzy_opencmd fnameescape(file.name)
      if has_key(file, 'lnum')
        silent execute file.lnum
        normal! zz
      endif
    endif
  endfunction

  let s:fuzzy_prev_window = win_getid()
  let s:fuzzy_prev_window_height = winheight('%')

  if bufnr(s:fuzzy_bufnr) > 0
    exe 'keepalt' 'below' a:opts.lines . 'sp' bufname(s:fuzzy_bufnr)
  else
    exe 'keepalt' 'below' a:opts.lines . 'new'
    let s:fuzzy_job_id = termopen(command, opts)
    let b:fuzzy_status = 'FuzzyOpen (' . len(a:choices) . ' choices)'
    setlocal statusline=%{b:fuzzy_status}
  endif
  let s:fuzzy_bufnr = bufnr('%')
  set filetype=fuzzy
  startinsert
endfunction

