" shellasync.vim plugin for asynchronously executing shell commands in vim
" Maintainer: Dmitry "troydm" Geurkov <d.geurkov@gmail.com>
" Version: 0.3.4
" Description: shellasync.vim plugin allows you to execute shell commands
" asynchronously inside vim and see output in seperate buffer window.
" Last Change: 8 September, 2012
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

class ShellAsyncOutput(threading.Thread):
    def __init__(self):
        threading.Thread.__init__(self)
        self.lock = threading.Lock()
        self.processPid = None
        self.command = None
        self.print_retval = False
        self.retval = None
        self.output = []

    def startProcess(self,cmd,print_retval):
        self.lock.acquire()
        self.command = cmd
        self.print_retval = print_retval
        self.lock.release()
        self.start()
        i = 0
        pid = None
        while True:
            pid = self.pid()
            if i >= 100 or pid != None:
                return pid
            time.sleep(0.01)
            i += 1
        return None
    
    def run(self):
        self.lock.acquire()
        p = subprocess.Popen(self.command+" 2>&1", shell=True, preexec_fn=os.setsid, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        fcntl.fcntl(p.stdout.fileno(), fcntl.F_SETFL, os.O_NONBLOCK)
        self.processPid = p.pid
        self.lock.release()
        retval = None
        out = ''
        while True:
            try:
                outread = p.stdout.read()
                if len(outread) == 0:
                    retval = p.poll()
                    if retval != None:
                        self.lock.acquire()
                        self.retval = retval
                        self.lock.release()
                        break
                    else:
                        time.sleep(0.25)
                else:
                    out += outread
                    while out.find("\n") != -1:
                        out = out.split("\n")
                        lines = out[:-1]
                        out = out[-1]
                        self.extend(lines)
            except IOError:
                time.sleep(0.25)
        if len(out) > 0:
            self.extend(out)
        if self.print_retval:
            self.extend(["","Shell command "+self.command+" completed with return value "+str(retval)])

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

    def pid(self):
        self.lock.acquire()
        pid = self.processPid
        self.lock.release()
        return pid

    def returnValue(self):
        self.lock.acquire()
        retval = self.retval
        self.lock.release()
        return retval

    def processCommand(self):
        self.lock.acquire()
        command = self.command
        self.lock.release()
        return command

def ShellAsyncRefreshOutput():
    global shellasync_cmds
    pid = vim.eval("getbufvar('%','pid')")
    if pid == None:
        return
    pid = int(pid)
    if pid in shellasync_cmds:
        output = shellasync_cmds[pid]
        if output != None:
            out = output.get()
            if len(out) > 0:
                if len(vim.current.buffer) == 1 and len(vim.current.buffer[0]) == 0:
                    vim.current.buffer[0] = out[0]
                    out = out[1:]
                    if len(out) > 0:
                        vim.current.buffer.append(out)
                else:
                    vim.current.buffer.append(out)
                vim.command("call setpos('.',["+str(vim.current.buffer.number)+","+str(len(vim.current.buffer))+",0,0])")
    vim.command("call feedkeys(\"f\e\")")

def ShellAsyncExecuteCmd():
    global shellasync_cmds
    print_retval = vim.eval("g:shellasync_print_return_value") == '1'
    cmd = vim.eval("command")
    pid = vim.eval("getbufvar('%','pid')")
    if pid != None:
        ShellAsyncTermCmd(int(pid))
        ShellAsyncRefreshOutput()
        ShellAsyncDeleteCmd(int(pid))
    vim.current.buffer[:] = None
    vim.command("silent! refresh!")
    out = ShellAsyncOutput()
    pid = out.startProcess(cmd,print_retval)
    if pid != None:
        vim.eval("setbufvar('%','pid',"+str(pid)+")")
        shellasync_cmds[pid] = out

def ShellAsyncTermCmd(pid):
    global shellasync_cmds
    if pid in shellasync_cmds:
        out = shellasync_cmds[pid]
        if not out.isAlive():
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" is finished'")
            return True
        try:
            os.killpg(pid,signal.SIGTERM)
        except OSError:
            os.kill(pid,signal.SIGTERM)
        out.join(15.0)
        if out.isAlive():
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" is still running'")
            return False
        else:
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" terminated'")
    return True

def ShellAsyncKillCmd(pid):
    global shellasync_cmds
    if pid in shellasync_cmds:
        out = shellasync_cmds[pid]
        if not out.isAlive():
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" is finished'")
            return True
        try:
            os.killpg(pid,signal.SIGKILL)
        except OSError:
            os.kill(pid,signal.SIGKILL)
        out.join(15.0)
        if out.isAlive():
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" is still running'")
            return False
        else:
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" killed'")
    return True

def ShellAsyncDeleteCmd(pid):
    global shellasync_cmds
    if pid in shellasync_cmds:
        out = shellasync_cmds[pid]
        if not out.isAlive():
            shellasync_cmds.pop(pid)
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" deleted'")
            return True
        else:
            vim.command("echomsg 'Shell command "+out.processCommand()+" pid: "+str(pid)+" is still running'")
            return False
    return True

def ShellAsyncTermAllCmds():
    global shellasync_cmds
    for pid in list(shellasync_cmds.keys()):
        if not ShellAsyncTermCmd(pid):
            ShellAsyncKillCmd(pid)

def ShellAsyncRunningCmds():
    global shellasync_cmds
    cmds = {}
    for i in shellasync_cmds.keys():
        out = shellasync_cmds[i]
        if out.isAlive():
            cmds[i] = out.command
    return cmds

def ShellAsyncListShells():
    global shellasync_cmds
    pos = vim.eval("getpos('.')")
    vim.current.buffer[:] = None
    vim.current.buffer[0]='shellasync - list of running processes (press t to terminate, K to kill, d to delete)'
    vim.current.buffer.append('<Status>  <Return>  <PID>    <Command>')
    i = 2
    if len(shellasync_cmds) > 0:
        for pid in shellasync_cmds.keys():
            out = shellasync_cmds[pid]
            if out.isAlive():
                s="Running   "
            else:
                s="Finished  "
            retval = out.returnValue()
            if retval == None:
                s += "   -      "
            else:
                retval = str(retval)
                l = (8-len(retval))/2
                retval = (" "*l)+retval+(" "*l)
                if len(retval) < 10:
                    retval += " "*(10-len(retval))
                s += retval
            pid = str(pid)
            if len(pid) < 9:
                pid += " "*(9-len(pid))
            s += pid
            s += out.processCommand()
            vim.current.buffer.append(s)
            i += 1
    else:
        vim.current.buffer.append("--------No running processes----------")
    vim.eval("setpos('.',"+str(pos)+")")
    vim.command("call feedkeys(\"f\e\")")

EOF

function! s:ExpandCommand(command)
    return join(map(split(a:command), 'expand(v:val)'))
endfunction
function! s:ExecuteInShell(bang, samewin, command)
    if a:bang == '!'
        let command = s:ExpandCommand(a:command)
    else
        let command = a:command
    endif
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
        setlocal buftype=nofile bufhidden=wipe buflisted noswapfile nowrap
        setlocal filetype=shellasync
        call setbufvar("%","prevupdatetime",&updatetime)
        call setbufvar("%","command",command)
        set updatetime=500
        au BufWipeout <buffer> silent call s:TermShellInBuf()
        au BufEnter <buffer> set updatetime=500
        au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
        au CursorHold <buffer> python ShellAsyncRefreshOutput()
        nnoremap <buffer> <C-c> :ShellTerm<CR>
        python ShellAsyncExecuteCmd()
    else
        exe winnr . 'wincmd w'
        python ShellAsyncExecuteCmd()
    endif
endfunction
function! s:TermShellInBuf()
    let pid = getbufvar('%','pid')
    if pid != ''
        call s:TermShell([pid])
        call s:DeleteShell([pid])
    endif
endfunction
function! s:GetPidList(...)
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
            return [pid]
        endif
    endif
    return []
endfunction
function! s:TermShell(pidlist)
    call s:CmdShell('ShellAsyncTermCmd',a:pidlist)
endfunction
function! s:KillShell(pidlist)
    call s:CmdShell('ShellAsyncKillCmd',a:pidlist)
endfunction
function! s:DeleteShell(pidlist)
    call s:CmdShell('ShellAsyncDeleteCmd',a:pidlist)
endfunction
function! s:CmdShell(cmd, pidlist)
    for pid in a:pidlist
        exe 'python '.a:cmd.'('.pid.')'
    endfor
endfunction
function! s:OpenShellsList()
    let command = 'shellasync'
    let winnr = bufwinnr('^' . command . '$')
    if winnr < 0
        execute &lines/3 . 'sp ' . fnameescape(command)
        setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
        setlocal filetype=shellasynclist
        call setbufvar("%","prevupdatetime",&updatetime)
        call setbufvar("%","command",command)
        set updatetime=500
        au BufEnter <buffer> set updatetime=500
        au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
        au CursorHold <buffer> python ShellAsyncListShells()
        nnoremap <buffer> t :echo '' \| call <SID>TermShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        nnoremap <buffer> K :echo '' \| call <SID>KillShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        nnoremap <buffer> d :echo '' \| call <SID>DeleteShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        nnoremap <buffer> x :echo '' \| call <SID>DeleteShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        python ShellAsyncListShells()
    else
        exe winnr . 'wincmd w'
    endif
endfunction
command! -complete=shellcmd -bang -nargs=+ Shell call <SID>ExecuteInShell('<bang>',1,<q-args>)
command! -complete=shellcmd -bang -nargs=+ ShellNew call <SID>ExecuteInShell('<bang>',0,<q-args>)
command! -complete=shellcmd -nargs=* ShellTerm call <SID>TermShell(<SID>GetPidList(<args>))
command! -complete=shellcmd -nargs=* ShellKill call <SID>KillShell(<SID>GetPidList(<args>))
command! -complete=shellcmd -nargs=* ShellDelete call <SID>DeleteShell(<SID>GetPidList(<args>))
command! ShellList call <SID>OpenShellsList()
au VimLeavePre * python ShellAsyncTermAllCmds()

