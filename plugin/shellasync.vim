" shellasync.vim plugin for asynchronously executing shell commands in vim
" Maintainer: Dmitry "troydm" Geurkov <d.geurkov@gmail.com>
" Version: 0.1
" Description: shellasync.vim plugin allows you to execute shell commands
" asynchronously inside vim and see output in seperate buffer window.
" Last Change: 20 August, 2012
" License: Vim License (see :help license)
" Website: https://github.com/troydm/shellasync.vim
"
" See shellasync.vim for help.  This can be accessed by doing:

if !has("python")
    echo "ShellAsync needs vim compiled with +python option"
    finish
endif

if !exists("g:shellasync_print_return_value")
    let g:shellasync_print_return_value = 1
endif

python << EOF
import vim, sys, os, subprocess, threading, signal, time, fcntl

shellasync_cmds = {}
shellasync_pids = {}

def ExecuteCmd(cmd,print_retval):
    global shellasync_cmds,shellasync_pids
    print_retval = print_retval == 1
    if TermCmd(cmd):
        shellasync_cmds[cmd] = threading.Thread(target=ExecuteInSubprocess, args=(cmd,print_retval,))
        shellasync_cmds[cmd].start()

def TermCmd(cmd):
    global shellasync_cmds,shellasync_pids
    if cmd in shellasync_cmds and cmd in shellasync_pids:
        os.kill(shellasync_pids[cmd],signal.SIGTERM)
        if cmd in shellasync_cmds:
            shellasync_cmds[cmd].join(15.0)
            if cmd in shellasync_pids:
                vim.command("echomsg 'Shell command "+cmd+" is still running'")
                return False
    return True

def KillCmd(cmd):
    global shellasync_cmds,shellasync_pids
    if cmd in shellasync_cmds and cmd in shellasync_pids:
        os.kill(shellasync_pids[cmd],signal.SIGKILL)
        if cmd in shellasync_cmds:
            shellasync_cmds[cmd].join(15.0)
            if cmd in shellasync_pids:
                vim.command("echomsg 'Shell command "+cmd+" is still running'")
                return False
    return True

def ExecuteInSubprocess(cmd,print_retval):
    global shellasync_cmds,shellasync_pids
    p = subprocess.Popen(cmd+" 2>&1", shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    fcntl.fcntl(p.stdout.fileno(), fcntl.F_SETFL, os.O_NONBLOCK)
    shellasync_pids[cmd] = p.pid
    time.sleep(0.5)
    retval = None
    out = ''
    first = True
    buf = vim.current.buffer
    try:
        vim.command("normal dGG")
        vim.command("silent! redraw!")
    except vim.error:
        pass
    while True:
        try:
            outread = p.stdout.read()
            if len(outread) > 0:
                out += outread
                while out.find("\n") != -1:
                    out = out.split("\n")
                    lines = out[:-1]
                    out = out[-1]
                    try:
                        if first:
                            buf[0] = lines[0]
                            first = False
                            lines = lines[1:]
                            if len(lines) > 0:
                                buf.append(lines)
                        else:
                            buf.append(lines)
                    except vim.error:
                        pass
                try:
                    if vim.current.buffer.number == buf.number:
                        vim.command("call setpos('.',["+str(buf.number)+","+str(len(buf))+",0,0])")
                    vim.command("silent! redraw!")
                except vim.error:
                    pass
            else:
                retval = p.poll()
                if retval != None:
                    shellasync_pids.pop(cmd)
                    break
        except IOError:
            pass
        time.sleep(0.5)
    try:
        if len(out) > 0:
            buf.append(out)
        if print_retval:
            buf.append(["","Shell command "+cmd+" completed with return value "+str(retval)])
        vim.command("silent! redraw!")
    except vim.error:
        pass
    shellasync_cmds.pop(cmd)
EOF

function! s:ExecuteInShell(command)
    let command = join(map(split(a:command), 'expand(v:val)'))
    let winnr = bufwinnr('^' . command . '$')
    if winnr < 0
        execute &lines/3 . 'sp ' . fnameescape(command)
        setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile nowrap
        exe "au BufWipeout <buffer> ShellTerm ".command
        exe "python ExecuteCmd('".command."',".g:shellasync_print_return_value.")"
    else
        exe winnr . 'wincmd w'
        exe "python ExecuteCmd('".command."',".g:shellasync_print_return_value.")"
    endif
endfunction
command! -complete=shellcmd -nargs=+ Shell call s:ExecuteInShell(<q-args>)
command! -complete=shellcmd -nargs=+ ShellTerm python TermCmd(<q-args>)
command! -complete=shellcmd -nargs=+ ShellKill python KillCmd(<q-args>)
command! ShellsRunning python print shellasync_pids

