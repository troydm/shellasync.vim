" shellasync.vim plugin for asynchronously executing shell commands in vim
" Maintainer: Dmitry "troydm" Geurkov <d.geurkov@gmail.com>
" Version: 0.3.7
" Description: shellasync.vim plugin allows you to execute shell commands
" asynchronously inside vim and see output in seperate buffer window.
" Last Change: 31 January, 2013
" License: Vim License (see :help license)
" Website: https://github.com/troydm/shellasync.vim
"
" See shellasync.vim for help.  This can be accessed by doing:

if exists("b:current_syntax")
  finish
endif

let s:save_cpo = &cpo
set cpo&vim

syntax match ShellAsyncListTitle /^shellasync -/ 
syntax match ShellAsyncListTitle /press/ 
syntax match ShellAsyncListTitle /to terminate/ 
syntax match ShellAsyncListTitle /to kill/ 
syntax match ShellAsyncListTitle /to delete/ 
syntax match ShellAsyncListTitle /to send input/ 
syntax match ShellAsyncListTitle /to select shell/ 
syntax match ShellAsyncListColumn /Status/ 
syntax match ShellAsyncListColumn /Return/ 
syntax match ShellAsyncListColumn /PID/ 
syntax match ShellAsyncListColumn /Command/ 
syntax match ShellAsyncListInfo  / list of running processes / 
syntax match ShellAsyncListInfo /No running processes/ 
syntax match ShellAsyncListPID / -\?[0-9]\+ / 
syntax match ShellAsyncListPID / - / 
syntax match ShellAsyncListStatus /Running/ 
syntax match ShellAsyncListStatus /Finished/ 

highlight default link ShellAsyncListTitle    Comment
highlight default link ShellAsyncListColumn   String
highlight default link ShellAsyncListInfo     Constant
highlight default link ShellAsyncListPID      Number
highlight default link ShellAsyncListStatus   Keyword

let b:current_syntax = "shellasynclist"

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: ts=8 sw=4 sts=4 et foldenable foldmethod=marker foldcolumn=1
