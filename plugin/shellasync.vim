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

let s:save_cpo = &cpo
set cpo&vim

" check if running on windows {{{
if has("win32") || has("win64")
    let &cpo = s:save_cpo
    unlet s:save_cpo
    if exists("g:shellasync_suppress_load_warning") && g:shellasync_suppress_load_warning
        finish
    endif
    echo "shellasync won't work windows operating system"
    finish
endif
" }}}

" check python support {{{
if !has("python")
    let &cpo = s:save_cpo
    unlet s:save_cpo
    if exists("g:shellasync_suppress_load_warning") && g:shellasync_suppress_load_warning
        finish
    endif
    echo "shellasync needs vim compiled with +python option"
    finish
endif

if !exists('*pyeval')
    let &cpo = s:save_cpo
    unlet s:save_cpo
    if exists("g:shellasync_suppress_load_warning") && g:shellasync_suppress_load_warning
        finish
    endif
    echo "shellasync needs vim 7.3 with atleast 569 patchset included"
    finish
endif
" }}}

" options {{{
if !exists("g:shellasync_print_return_value")
    let g:shellasync_print_return_value = 0
endif

if !exists("g:shellasync_terminal_insert_on_enter")
    let g:shellasync_terminal_insert_on_enter = 1
endif

if !exists("g:shellasync_update_interval")
    let g:shellasync_update_interval = 100
endif

if !exists("g:shellasync_terminal_prompt")
    let g:shellasync_terminal_prompt = "'$ '"
endif

if !exists("g:shellasync_loaded")
    let g:shellasync_loaded = 0
endif
" }}}

" commands {{{
command! -complete=shellcmd -bang -nargs=+ Shell call shellasync#ExecuteInShell('<bang>',1,<q-args>)
command! -complete=shellcmd -bang -nargs=+ ShellNew call shellasync#ExecuteInShell('<bang>',0,<q-args>)
command! -complete=customlist,<SID>ShellPidCompletion -nargs=* ShellTerm call shellasync#TermShell(shellasync#GetPidList(<f-args>))
command! -complete=customlist,<SID>ShellPidCompletion -nargs=* ShellKill call shellasync#KillShell(shellasync#GetPidList(<f-args>))
command! -complete=customlist,<SID>ShellPidCompletion -nargs=* ShellDelete call shellasync#DeleteShell(shellasync#GetPidList(<f-args>))
command! -complete=customlist,<SID>ShellPidCompletion -nargs=* -range ShellSend call shellasync#SendShell(<count>,<line1>,<line2>,shellasync#GetPidList(<f-args>))
command! -complete=customlist,<SID>ShellPidCompletion -nargs=? ShellSelect call shellasync#ShellSelect(<f-args>)
command! ShellSelected call shellasync#ShellSelected(bufnr('%'))
command! ShellList call shellasync#OpenShellsList(0)
command! ShellTerminal call shellasync#OpenShellTerminal()
au VimLeavePre * if g:shellasync_loaded | exe 'python shellasync.ShellAsyncTermAllCmds()' | endif
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set sw=4 sts=4 et fdm=marker:
