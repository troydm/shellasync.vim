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

def ShellAsyncRefreshOutput(cmd):
    global shellasync_bufs
    if cmd in shellasync_bufs:
        out = shellasync_bufs[cmd]
        if out != None:
            out = out.get()
            if len(out) > 0:
                if len(vim.current.buffer) == 1 and len(vim.current.buffer[0]) == 0:
                    vim.current.buffer[0] = out[0]
                    out = out[1:]
                vim.current.buffer.append(out)
                vim.command("call setpos('.',["+str(vim.current.buffer.number)+","+str(len(vim.current.buffer))+",0,0])")
    vim.command("call feedkeys(\"f\e\")")

def ShellAsyncExecuteCmd(cmd,print_retval):
    global shellasync_cmds,shellasync_pids
    print_retval = print_retval == 1
    if ShellAsyncTermCmd(cmd):
        ShellAsyncRefreshOutput(cmd)
        vim.command("normal ggdGG")
        vim.command("silent! refresh!")
        shellasync_cmds[cmd] = threading.Thread(target=ShellAsyncExecuteInSubprocess, args=(cmd,print_retval,))
        shellasync_cmds[cmd].start()

def ShellAsyncTermCmd(cmd):
    global shellasync_cmds,shellasync_pids
    if cmd in shellasync_cmds and cmd in shellasync_pids:
        os.kill(shellasync_pids[cmd],signal.SIGTERM)
        if cmd in shellasync_cmds:
            shellasync_cmds[cmd].join(15.0)
            if cmd in shellasync_pids:
                vim.command("echomsg 'Shell command "+cmd+" is still running'")
                return False
    return True

def ShellAsyncKillCmd(cmd):
    global shellasync_cmds,shellasync_pids
    if cmd in shellasync_cmds and cmd in shellasync_pids:
        os.kill(shellasync_pids[cmd],signal.SIGKILL)
        if cmd in shellasync_cmds:
            shellasync_cmds[cmd].join(15.0)
            if cmd in shellasync_pids:
                vim.command("echomsg 'Shell command "+cmd+" is still running'")
                return False
    return True

def ShellAsyncExecuteInSubprocess(cmd,print_retval):
    global shellasync_cmds,shellasync_pids,shellasync_bufs
    p = subprocess.Popen(cmd+" 2>&1", shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    fcntl.fcntl(p.stdout.fileno(), fcntl.F_SETFL, os.O_NONBLOCK)
    shellasync_pids[cmd] = p.pid
    time.sleep(0.5)
    retval = None
    out = ''
    shellasync_bufs[cmd] = ShellAsyncOutput()
    buf = shellasync_bufs[cmd]
    while True:
        try:
            outread = p.stdout.read()
            if len(outread) > 0:
                out += outread
                while out.find("\n") != -1:
                    out = out.split("\n")
                    lines = out[:-1]
                    out = out[-1]
                    buf.extend(lines)
            else:
                retval = p.poll()
                if retval != None:
                    shellasync_pids.pop(cmd)
                    break
        except IOError:
            pass
        time.sleep(0.5)
    if len(out) > 0:
        buf.extend(out)
    if print_retval:
        buf.extend(["","Shell command "+cmd+" completed with return value "+str(retval)])
    shellasync_cmds.pop(cmd)
EOF

function! s:ExecuteInShell(command)
    let command = join(map(split(a:command), 'expand(v:val)'))
    let winnr = bufwinnr('^' . command . '$')
    if winnr < 0
        execute &lines/3 . 'sp ' . fnameescape(command)
        setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile nowrap
        call setbufvar("%","prevupdatetime",&updatetime)
        set updatetime=500
        exe "au BufWipeout <buffer> ShellTerm ".command
        exe "au BufEnter <buffer> set updatetime=500"
        exe "au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')"
        exe "au CursorHold <buffer> python ShellAsyncRefreshOutput('".command."')"
        exe "python ShellAsyncExecuteCmd('".command."',".g:shellasync_print_return_value.")"
    else
        exe winnr . 'wincmd w'
        exe "python ShellAsyncExecuteCmd('".command."',".g:shellasync_print_return_value.")"
    endif
endfunction
command! -complete=shellcmd -nargs=+ Shell call s:ExecuteInShell(<q-args>)
command! -complete=shellcmd -nargs=+ ShellTerm python ShellAsyncTermCmd(<q-args>)
command! -complete=shellcmd -nargs=+ ShellKill python ShellAsyncKillCmd(<q-args>)
command! ShellsRunning python print shellasync_pids

