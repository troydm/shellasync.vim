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

syntax match ShellAsyncTermRetVal /^Shell command / 
syntax match ShellAsyncTermRetVal / completed with return value / 
syntax match ShellAsyncTermPrompt /^$ / 

highlight default link ShellAsyncTermPrompt    Identifier
highlight default link ShellAsyncTermRetVal   Comment

let b:current_syntax = "shellasyncterm"

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: ts=8 sw=4 sts=4 et foldenable foldmethod=marker foldcolumn=1
