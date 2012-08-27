" shellasync.vim plugin for asynchronously executing shell commands in vim
" Maintainer: Dmitry "troydm" Geurkov <d.geurkov@gmail.com>
" Version: 0.3.3
" Description: shellasync.vim plugin allows you to execute shell commands
" asynchronously inside vim and see output in seperate buffer window.
" Last Change: 27 August, 2012
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
shellasync_bufs = {}

class ShellAsyncOutput:
    def __init__(self):
        self.lock = threading.Lock()
        self.output = []
    
    def get(self):
        self.lock.acquire()
        r = self.output
        self.output = []
        self.lock.release()
        return r

    def extend(self,data):
        self.lock.acquire()
        self.output.extend(data)
        self.lock.release()

def ShellAsyncRefreshOutput():
    global shellasync_bufs,shellasync_pids
    cmd = vim.eval("getbufvar('%','command')")
    if cmd in shellasync_bufs:
        out = shellasync_bufs[cmd]
        if out != None:
            out = out.get()
            if len(out) > 0:
                if len(vim.current.buffer) == 1 and len(vim.current.buffer[0]) == 0:
                    vim.current.buffer[0] = out[0]
                    out = out[1:]
                    if len(out) > 0:
                        vim.current.buffer.append(out)
                else:
                    vim.current.buffer.append(out)
                vim.command("call setpos('.',["+str(vim.current.buffer.number)+","+str(len(vim.current.buffer))+",0,0])")
            else:
                if not cmd in shellasync_pids:
                    shellasync_bufs.pop(cmd)                    
    vim.command("call feedkeys(\"f\e\")")

def ShellAsyncExecuteCmd():
    global shellasync_cmds
    print_retval = vim.eval("g:shellasync_print_return_value") == '1'
    cmd = vim.eval("command")
    if ShellAsyncTermCmd():
        ShellAsyncRefreshOutput()
        vim.command("normal ggdGG")
        vim.command("silent! refresh!")
        shellasync_cmds[cmd] = threading.Thread(target=ShellAsyncExecuteInSubprocess, args=(cmd,print_retval,))
        shellasync_cmds[cmd].start()

def ShellAsyncTermCmd():
    global shellasync_cmds,shellasync_pids
    cmd = vim.eval("command")
    if cmd in shellasync_cmds and cmd in shellasync_pids:
        try:
            os.killpg(shellasync_pids[cmd],signal.SIGTERM)
        except OSError:
            os.kill(shellasync_pids[cmd],signal.SIGTERM)
        if cmd in shellasync_cmds:
            shellasync_cmds[cmd].join(15.0)
            if cmd in shellasync_pids:
                vim.command("echomsg 'Shell command "+cmd+" is still running'")
                return False
    return True

def ShellAsyncKillCmd():
    global shellasync_cmds,shellasync_pids
    cmd = vim.eval("command")
    if cmd in shellasync_cmds and cmd in shellasync_pids:
        try:
            os.killpg(shellasync_pids[cmd],signal.SIGKILL)
        except OSError:
            os.kill(shellasync_pids[cmd],signal.SIGKILL)
        if cmd in shellasync_cmds:
            shellasync_cmds[cmd].join(15.0)
            if cmd in shellasync_pids:
                vim.command("echomsg 'Shell command "+cmd+" is still running'")
                return False
    return True

def ShellAsyncTermAllCmds():
    global shellasync_cmds,shellasync_pids
    for cmd in list(shellasync_pids.keys()):
        try:
            os.killpg(shellasync_pids[cmd],signal.SIGTERM)
        except OSError:
            os.kill(shellasync_pids[cmd],signal.SIGTERM)
        if cmd in shellasync_cmds:
            shellasync_cmds[cmd].join(15.0)
            if cmd in shellasync_pids:
                try:
                    os.killpg(shellasync_pids[cmd],signal.SIGKILL)
                except OSError:
                    os.kill(shellasync_pids[cmd],signal.SIGKILL)
                shellasync_cmds[cmd].join(5.0)

def ShellAsyncExecuteInSubprocess(cmd,print_retval):
    global shellasync_cmds,shellasync_pids,shellasync_bufs
    p = subprocess.Popen(cmd+" 2>&1", shell=True, preexec_fn=os.setsid, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    fcntl.fcntl(p.stdout.fileno(), fcntl.F_SETFL, os.O_NONBLOCK)
    shellasync_pids[cmd] = p.pid
    retval = None
    out = ''
    shellasync_bufs[cmd] = ShellAsyncOutput()
    buf = shellasync_bufs[cmd]
    while True:
        try:
            outread = p.stdout.read()
            if len(outread) == 0:
                retval = p.poll()
                if retval != None:
                    break
                else:
                    time.sleep(0.25)
            else:
                out += outread
                while out.find("\n") != -1:
                    out = out.split("\n")
                    lines = out[:-1]
                    out = out[-1]
                    buf.extend(lines)
        except IOError:
            pass
    if len(out) > 0:
        buf.extend(out)
    if print_retval:
        buf.extend(["","Shell command "+cmd+" completed with return value "+str(retval)])
    shellasync_cmds.pop(cmd)
    shellasync_pids.pop(cmd)
EOF

function! s:ExpandCommand(command)
    return join(map(split(a:command), 'expand(v:val)'))
endfunction
function! s:ExecuteInShell(bang, command)
    if a:bang == '!'
        let command = s:ExpandCommand(a:command)
    else
        let command = a:command
    endif
    let winnr = bufwinnr('^' . command . '$')
    if winnr < 0
        execute &lines/3 . 'sp ' . fnameescape(command)
        setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
        call setbufvar("%","prevupdatetime",&updatetime)
        call setbufvar("%","command",command)
        set updatetime=500
        au BufWipeout <buffer> call s:TermShellInBuf()
        au BufEnter <buffer> set updatetime=500
        au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
        au CursorHold <buffer> python ShellAsyncRefreshOutput()
        python ShellAsyncExecuteCmd()
    else
        exe winnr . 'wincmd w'
        python ShellAsyncExecuteCmd()
    endif
endfunction
function! s:TermShell(bang,command)
    if a:bang == '!'
        let command = s:ExpandCommand(a:command)
    else
        let command = a:command
    endif
    python ShellAsyncTermCmd()
endfunction
function! s:TermShellInBuf()
    let command = getbufvar('%','command')
    python ShellAsyncTermCmd()
endfunction
function! s:KillShell(bang,command)
    if a:bang == '!'
        let command = s:ExpandCommand(a:command)
    else
        let command = a:command
    endif
    python ShellAsyncKillCmd()
endfunction
command! -complete=shellcmd -bang -nargs=+ Shell call s:ExecuteInShell('<bang>',<q-args>)
command! -complete=shellcmd -bang -nargs=+ ShellTerm call s:TermShell('<bang>',<q-args>)
command! -complete=shellcmd -bang -nargs=+ ShellKill call s:KillShell('<bang>',<q-args>)
command! ShellsRunning python print shellasync_pids
au VimLeavePre * python ShellAsyncTermAllCmds()

