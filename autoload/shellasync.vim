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

" check if already loaded {{{
if exists('g:shellasync_loaded') && g:shellasync_loaded
    let &cpo = s:save_cpo
    unlet s:save_cpo
    finish
else
    let g:shellasync_loaded = 1
endif
" }}}

" load python module {{{
python << EOF
import vim, os, sys
shellasync_path = vim.eval("expand('<sfile>:h')")
if not shellasync_path in sys.path:
    sys.path.insert(0, shellasync_path)
del shellasync_path 
import shellasync
EOF
" }}}

" functions {{{
" utility functions {{{
function! s:ShellWindow(pid)
    for wnr in range(1,winnr('$'))
        let bnr = winbufnr(wnr)
        let buftype = getbufvar(bnr,'&ft') 
        if buftype == 'shellasync' || buftype == 'shellasyncterm'
            if getbufvar(bnr,'pid') == a:pid
                return wnr
            endif
        endif
    endfor
    return -1
endfunction

function! s:ExpandCommand(command)
    return join(map(split(a:command), 'expand(v:val)'))
endfunction

function! s:ShellPidCompletion(ArgLead, CmdLine, CursorPos)
    let pidlist = pyeval("filter(shellasync.ShellAsyncShellRunning,shellasync.shellasync_cmds.keys())")
    return map(filter(pidlist,"v:val =~ \'^".a:ArgLead."\'"),"\'\'.v:val")
endfunction
" }}}

" shell functions {{{
function! s:TermShellInBuf(del)
    let pid = getbufvar('%','pid')
    if pid != ''
        call shellasync#TermShell([pid])
        if a:del
            call shellasync#DeleteShell([pid])
        endif
    endif
endfunction

function! s:SelectShell(pidlist)
    if len(a:pidlist) > 0
        let pid = a:pidlist[0]
        let selectbnr = getbufvar('%','selectbnr')
        let selectbnrlist = getbufvar('%','selectbnrlist')
        if selectbnr != '' && selectbnr > 0
            call setbufvar(selectbnr,'pid',pid)
            if len(selectbnrlist) > 0 && selectbnrlist == 1
                bd!
            else
                unlet b:selectbnr
                unlet b:selectbnrlist
                python shellasync.ShellAsyncListShells()
            endif
            let wnr = bufwinnr(selectbnr)
            if wnr != -1
                exe wnr.'wincmd w'
            endif
            echo "Shell ".pid." selected!"
        endif
    else
        echo 'please select shell'
    endif
endfunction

function! s:SendShellInput(pid,input_data,nl)
    let send_input = a:input_data
    if len(send_input) == 0
        let send_input = ''
    endif
    redraw!
    if pyeval('shellasync.ShellAsyncShellRunning('.a:pid.')')
        exe 'python shellasync.ShellAsyncSendCmd('.a:pid.','.a:nl.')'
        let wnr = s:ShellWindow(a:pid)
        if wnr != -1 && winnr() != wnr
            let bnr = winbufnr(wnr)
            let pwnr = winnr()
            call setbufvar(bnr,'switchbackwnr',pwnr)
            exe wnr.'wincmd w' 
        endif
    else
        echo 'shell '.a:pid.' is not running'
    endif
endfunction

function! s:CmdShell(cmd, pidlist)
    if len(a:pidlist) == 0
        echo 'please specify a pid or associate a pid with current buffer using ShellSelect'
    else
        for pid in a:pidlist
            exe 'python shellasync.'.a:cmd.'('.pid.')'
        endfor
    endif
endfunction
" }}}

" terminal functions {{{
function! s:GetTerminalPrompt()
    let cfinished = getbufvar('%','cfinished')
    if cfinished == 0
        let pid = getbufvar('%','pid')
        let prompt = pyeval('shellasync.shellasync_cmds['.pid.'].getRemainder()').' '
        if len(prompt) > 0
            let b:prompt = prompt
        else
            let prompt = b:prompt
        endif
        return prompt
    else
        return eval(g:shellasync_terminal_prompt).' '
    endif
endfunction

function! s:TerminalStartInsert()
    let cfinished = getbufvar('%','cfinished')
    let pos = getpos('.')
    let prompt = s:GetTerminalPrompt()
    if cfinished == 0
        let pos[1] = line('$')
        if len(prompt) > len(getline('$')) && len(prompt) > 0
            call setline('$',prompt)
        endif
    else
        let pos[1] = getbufvar('%','pl')
    endif
    if pos[2] < len(prompt) 
        let pos[2] = col([pos[1],'$'])-1
    endif
    call setpos('.',pos)
    " set to override restoration of cursor to previous position
    let v:char = '.'
endfunction

function! s:TerminalGetCommand()
    let cfinished = getbufvar('%','cfinished')
    if cfinished == 0
        let pl = line('$')
    else
        let pl = getbufvar('%','pl')
    endif
    let prompt = s:GetTerminalPrompt()
    let ln = getline(pl)
    let ln = ln[len(prompt)-1: len(ln)-2]
    return ln
endfunction

function! s:TerminalSetCommand(command)
    let cfinished = getbufvar('%','cfinished')
    if cfinished == 0
        let pl = line('$')
    else
        let pl = getbufvar('%','pl')
    endif
    let prompt = s:GetTerminalPrompt()[:-2]
    call setline(pl,prompt.a:command.' ')
    normal! $
endfunction

function! s:TerminalCtrlDPressed()
    let cfinished = getbufvar('%','cfinished')
    if cfinished == 0
        call s:SendShellInput(b:pid,"\x04",0)
    else
        bd!
    endif
endfunction

function! s:TerminalBackspacePressed()
    let prompt = s:GetTerminalPrompt()
    if col('.') >= len(prompt)
        normal! x
    else
        normal! l
    endif
    startinsert
endfunction

function! s:TerminalLeftPressed()
    let prompt = s:GetTerminalPrompt()
    if col('.') < len(prompt)
        normal! l
    endif
    startinsert
endfunction

function! s:TerminalRightPressed()
    normal! l
    if col('.') != (col('$')-1)
        normal! l
    endif
    startinsert
endfunction

function! s:TerminalUpPressed()
    let cfinished = getbufvar('%','cfinished')
    let termnr = getbufvar('%','termnr')
    if cfinished == 0
        let command = pyeval('shellasync.shellasync_terms['.termnr.'].sendhistoryup()')
    else
        let command = pyeval('shellasync.shellasync_terms['.termnr.'].historyup()')
    endif
    call s:TerminalSetCommand(command)
    startinsert
endfunction

function! s:TerminalDownPressed()
    let cfinished = getbufvar('%','cfinished')
    let termnr = getbufvar('%','termnr')
    if cfinished == 0
        let command = pyeval('shellasync.shellasync_terms['.termnr.'].sendhistorydown()')
    else
        let command = pyeval('shellasync.shellasync_terms['.termnr.'].historydown()')
    endif
    call s:TerminalSetCommand(command)
    startinsert
endfunction

function! s:TerminalEnterPressed()
    let cfinished = getbufvar('%','cfinished')
    let command = s:TerminalGetCommand()
    if cfinished == 0
        let termnr = getbufvar('%','termnr')
        let send_input = command
        if len(send_input) == 0
            let send_input = ''
        endif
        exe 'python shellasync.shellasync_terms['.termnr.'].send(1)'
        return
    endif
    if empty(command)
        startinsert
    elseif command =~ '^\s*clear\s*$' 
        silent! normal! gg"_dG
        call setbufvar('%','pl',1)
        call shellasync#RefreshShellTerminal()
        startinsert
    else
        let termnr = getbufvar('%','termnr')
        let pid = getbufvar('%','pid')
        let cwd = pyeval('shellasync.shellasync_terms['.termnr.'].cwd')
        if pid != ''
            silent! call shellasync#DeleteShell([pid])
        endif
        call setbufvar('%','cfinished',0)
        exe 'python shellasync.shellasync_terms['.termnr.'].execute()'
        python shellasync.ShellAsyncTerminalRefreshOutput()
    endif
endfunction

function! s:TerminalBufEnter()
    if g:shellasync_terminal_insert_on_enter
        normal! G0
        startinsert
    endif
endfunction

function! s:CloseShellTerminal()
    call s:TermShellInBuf(1)
endfunction
" }}}

" global functions {{{
function! shellasync#ExecuteInShell(bang, samewin, command)
    if a:bang == '!'
        let command = s:ExpandCommand(a:command)
    else
        let command = a:command
    endif
    let cwd = getcwd()
    let winnr = bufwinnr('^shellasync - ' . command . '$')
    if !a:samewin
        let shellnr = 0
        for b in map(filter(range(1,bufnr("$")), "buflisted(v:val)"),"bufname(v:val)")
            let m = matchlist(b,'^shellasync \(\d\+\) - ')
            if !empty(m) && str2nr(m[1]) > shellnr 
                let shellnr = str2nr(m[1])
            endif
        endfor
        let shellnr = ''.(shellnr+1).' '
    else
        let shellnr = ''
    endif
    
    if winnr < 0 || !a:samewin
        execute &lines/3 . 'sp ' . fnameescape('shellasync '.shellnr.'- '.command)
        setlocal buftype=nofile bufhidden=wipe buflisted noswapfile nowrap nonumber
        setlocal filetype=shellasync
        call setbufvar("%","prevupdatetime",&updatetime)
        call setbufvar("%","command",command)
        exe 'set updatetime='.g:shellasync_update_interval
        au BufWipeout <buffer> silent call <SID>TermShellInBuf(1)
        exe 'au BufEnter <buffer> set updatetime='.g:shellasync_update_interval
        au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
        au CursorHold <buffer> python shellasync.ShellAsyncRefreshOutput()
        au CursorHoldI <buffer> python shellasync.ShellAsyncRefreshOutputI()
        nnoremap <buffer> <C-c> :echo '' \| call <SID>TermShellInBuf(0)<CR>
        python shellasync.ShellAsyncExecuteCmd(True,os.environ)
    else
        exe winnr . 'wincmd w'
        python shellasync.ShellAsyncExecuteCmd(True,os.environ)
    endif
endfunction

function! shellasync#GetPidList(...)
    if &filetype == 'shellasynclist'
        let words = split(getline('.'), '\s\+')
        if len(words) >= 4 && match(words[2],'\d\+') == 0
            let pid = words[2]
            return [pid]
        endif
    else
        if len(a:000) > 0
            return a:000
        else
            let pid = getbufvar('%','pid')
            if len(pid) > 0
                return [pid]
            endif
        endif
    endif
    return []
endfunction

function! shellasync#TermShell(pidlist)
    call s:CmdShell('ShellAsyncTermCmd',a:pidlist)
endfunction

function! shellasync#KillShell(pidlist)
    call s:CmdShell('ShellAsyncKillCmd',a:pidlist)
endfunction

function! shellasync#DeleteShell(pidlist)
    call s:CmdShell('ShellAsyncDeleteCmd',a:pidlist)
endfunction

function! shellasync#SendShell(c,l1,l2,pidlist)
    if len(a:pidlist) == 0
        echo 'no pid specified and no shell associated with buffer, use ShellSelect to associate shell with this buffer'
        return
    endif
    if a:c != -1
        let send_input = []
        for i in range(a:l1,a:l2)
            call add(send_input,getline(i))
        endfor
    else
        let send_input = input('send input: ')
        echo ''
    endif
    call s:SendShellInput(a:pidlist[0],send_input,1)
endfunction

function! shellasync#ShellSelect(...)
    let bnr = bufnr('%')
    if len(a:000) == 0
        call shellasync#OpenShellsList(bnr)
    else
        let pid = a:1
        if pyeval('shellasync.ShellAsyncShellRunning('.pid.')')
            let b:pid = pid
            echo 'shell '.pid.' selected!'
        else
            echo 'shell '.pid.' is not running!'
        endif
    endif
endfunction

function! shellasync#ShellSelected(bnr)
    let pid = getbufvar(a:bnr,'pid')
    if pid != ''
        let wnr = s:ShellWindow(pid)
        if wnr == -1
            echo 'shell '.pid.' is associated with this buffer'
        else
            echo 'shell '.pid.' in window '.wnr.' is associated with this buffer'
        endif
    else
        echo 'no shell associated with this buffer'
    endif
endfunction

function! shellasync#OpenShellsList(selectbnr)
    let command = 'shellasync'
    let winnr = bufwinnr('^' . command . '$')
    if winnr < 0
        execute &lines/3 . 'sp ' . fnameescape(command)
        setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap nonumber filetype=shellasynclist
        call setbufvar("%","prevupdatetime",&updatetime)
        call setbufvar("%","command",command)
        exe 'set updatetime='.g:shellasync_update_interval
        exe 'au BufEnter <buffer> set updatetime='.g:shellasync_update_interval
        au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
        au CursorHold <buffer> python shellasync.ShellAsyncListShells()
        nnoremap <silent> <buffer> t :call shellasync#TermShell(shellasync#GetPidList()) \| python shellasync.ShellAsyncListShells()<CR>
        nnoremap <silent> <buffer> K :call shellasync#KillShell(shellasync#GetPidList()) \| python shellasync.ShellAsyncListShells()<CR>
        nnoremap <silent> <buffer> d :call shellasync#DeleteShell(shellasync#GetPidList()) \| python shellasync.ShellAsyncListShells()<CR>
        nnoremap <silent> <buffer> x :call shellasync#DeleteShell(shellasync#GetPidList()) \| python shellasync.ShellAsyncListShells()<CR>
        nnoremap <silent> <buffer> s :call shellasync#SendShell(-1,0,0,shellasync#GetPidList()) \| python shellasync.ShellAsyncListShells()<CR>
        if a:selectbnr > 0
            call setbufvar("%","selectbnr",a:selectbnr)
            call setbufvar("%","selectbnrlist",1)
            nnoremap <silent> <buffer> S :call <SID>SelectShell(shellasync#GetPidList())<CR>
        endif
        python shellasync.ShellAsyncListShells()
    else
        exe winnr . 'wincmd w'
        if a:selectbnr > 0
            call setbufvar("%","selectbnr",a:selectbnr)
            call setbufvar("%","selectbnrlist",0)
            nnoremap <silent> <buffer> S :call <SID>SelectShell(shellasync#GetPidList())<CR>
        endif
    endif
endfunction

function! shellasync#OpenShellTerminal()
    let termnr = 0
    for b in map(filter(range(1,bufnr("$")), "buflisted(v:val)"),"bufname(v:val)")
        let m = matchlist(b, 'shellasyncterm - \(\d\+\)')
        if !empty(m) && str2nr(m[1]) > termnr
            let termnr = str2nr(m[1])
        endif
    endfor
    let termnr += 1
    execute 'belowright '.(&lines/3) . 'sp ' . fnameescape('shellasyncterm - '.termnr)
    setlocal buftype=nofile bufhidden=wipe buflisted noswapfile nowrap nonumber filetype=shellasyncterm
    call setbufvar("%","prevupdatetime",&updatetime)
    call setbufvar("%","termnr",termnr)
    call setbufvar("%","pl",1)
    call setbufvar("%","cfinished",1)
    exe 'python shellasync.shellasync_terms['.termnr.'] = shellasync.ShellAsyncTerminal()'
    exe 'set updatetime='.g:shellasync_update_interval
    au BufWipeout <buffer> silent call <SID>CloseShellTerminal()
    exe 'au BufEnter <buffer> set updatetime='.g:shellasync_update_interval.' | call <SID>TerminalBufEnter()'
    au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime') | stopinsert
    au InsertEnter <buffer> call <SID>TerminalStartInsert()
    au CursorHold <buffer> python shellasync.ShellAsyncTerminalRefreshOutput()
    au CursorHoldI <buffer> python shellasync.ShellAsyncTerminalRefreshOutputI()
    inoremap <silent> <buffer> <Enter> <ESC>:call <SID>TerminalEnterPressed() \| normal! 0<CR>
    inoremap <silent> <buffer> <Left> <ESC>:call <SID>TerminalLeftPressed()<CR>
    inoremap <silent> <buffer> <Right> <ESC>:call <SID>TerminalRightPressed()<CR>
    inoremap <silent> <buffer> <Up> <ESC>:call <SID>TerminalUpPressed()<CR>
    inoremap <silent> <buffer> <Down> <ESC>:call <SID>TerminalDownPressed()<CR>
    inoremap <silent> <buffer> <BS> <ESC>:call <SID>TerminalBackspacePressed()<CR>
    inoremap <silent> <buffer> <C-d> <ESC>:call <SID>TerminalCtrlDPressed()<CR>
    nnoremap <silent> <buffer> <C-c> :call shellasync#TermShell([getbufvar('%','pid')])<CR>
    nnoremap <silent> <buffer> t :call shellasync#TermShell([getbufvar('%','pid')])<CR>
    nnoremap <silent> <buffer> K :call shellasync#KillShell([getbufvar('%','pid')])<CR>
    nnoremap <silent> <buffer> s :call shellasync#SendShell(-1,0,0,[getbufvar('%','pid')])<CR>
    call shellasync#RefreshShellTerminal()
    startinsert
endfunction

function! shellasync#RefreshShellTerminal()
    let pl = getbufvar('%','pl')
    if !(getline(pl) =~ '^'.s:GetTerminalPrompt())
        call setline(pl,s:GetTerminalPrompt())
    endif
    redraw!
endfunction
" }}}
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set sw=4 sts=4 et fdm=marker:
