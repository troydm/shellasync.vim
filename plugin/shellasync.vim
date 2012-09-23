" shellasync.vim plugin for asynchronously executing shell commands in vim
" Maintainer: Dmitry "troydm" Geurkov <d.geurkov@gmail.com>
" Version: 0.3.5
" Description: shellasync.vim plugin allows you to execute shell commands
" asynchronously inside vim and see output in seperate buffer window.
" Last Change: 19 September, 2012
" License: Vim License (see :help license)
" Website: https://github.com/troydm/shellasync.vim
"
" See shellasync.vim for help.  This can be accessed by doing:

if !has("python")
    echo "ShellAsync needs vim compiled with +python option"
    finish
endif

if !exists("g:shellasync_print_return_value")
    let g:shellasync_print_return_value = 0
endif

if !exists("g:shellasync_terminal_insert_on_enter")
    let g:shellasync_terminal_insert_on_enter = 1
endif

if !exists("g:shellasync_terminal_prompt")
    let g:shellasync_terminal_prompt = "'$ '"
endif

python << EOF
import vim, sys, os, subprocess, threading, signal, time, fcntl

shellasync_cmds = {}
shellasync_terms = {}

class ShellAsyncOutput(threading.Thread):
    def __init__(self):
        threading.Thread.__init__(self)
        self.lock = threading.Lock()
        self.processPid = None
        self.command = None
        self.cwd = None
        self.env = None
        self.print_retval = False
        self.retval = None
        self.output = []

    def startProcess(self,cmd,cwd,env,print_retval):
        self.lock.acquire()
        self.command = cmd
        self.cwd = cwd
        self.env = env
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
        p = subprocess.Popen(self.command+" 2>&1", shell=True, cwd=self.cwd, env=self.env, preexec_fn=os.setsid, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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

    def hasdata(self):
        self.lock.acquire()
        r = len(self.output) > 0
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

class ShellAsyncTerminal:
    def __init__(self):
        self.cwd = vim.eval('getcwd()')
        self.env = dict(os.environ)
        self.history = []
        self.historyind = -1

    def historyup(self):
        if len(self.history) == 0:
            return ""
        if self.historyind == -1:
            self.historyind = len(self.history)-1
        else:
            self.historyind -= 1
        if self.historyind in xrange(len(self.history)):
            return self.history[self.historyind]
        else:
            self.historyind = -1
        return ""

    def historydown(self):
        if len(self.history) == 0:
            return ""
        if self.historyind == -1:
            self.historyind = 0
        else:
            self.historyind += 1
        if self.historyind in xrange(len(self.history)):
            return self.history[self.historyind]
        else:
            self.historyind = -1
        return ""

    def execute(self):
        command = vim.eval('command')
        if len(self.history) > 0:
            if self.history[-1] != command:
                self.history.append(command)
        else:
            self.history.append(command)
        self.historyind = -1
        if command.startswith("cd"):
            if command == "cd":
                command = "cd ~"
            if len(command.split(" ")) == 2 and not ('&' in command or ';' in command):
                command = command+' && pwd'
                p = subprocess.Popen(command, shell=True, cwd=self.cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                p.wait()
                for l in p.stderr.read().split("\n"):
                    if len(l) > 0:
                        self.commandAppend(l)
                pwd = p.stdout.read().split("\n")
                if len(pwd) > 1:
                    self.cwd = pwd[-2]
                self.commandFinished()
            else:
                ShellAsyncExecuteCmd(False,self.env)
        elif command.startswith("setenv") or command.startswith("export"):
            command = command[7:]
            i = 0
            b = None
            e = None
            var = None
            varp = None
            val = None
            for c in command:
                if var != None:
                    if val == None and e == i:
                        e = None
                        if c == '\'' or c == '"':
                            varp = c
                            b = i+1
                        else:
                            varp = " "
                            b = i
                        if i == (len(command)-1):
                            val = command[b:]
                    if (b != None and val == None and i > b) and ((c == varp and command[i-1] != "\\") or ((len(command)-1) == i)):
                        e = i 
                        if c == varp:
                            val = command[b:e]
                        else:
                            val = command[b:]
                    if val != None:
                        for k in self.env:
                            val = val.replace("$"+k,self.env[k])
                            val = val.replace("${"+k+"}",self.env[k])
                        self.env[var] = val
                        b = None
                        e = None
                        var = None
                        varp = None
                        val = None
                else:
                    if c == '=' and b != None:
                        e = i
                        var = command[b:e]
                        b = None
                        e = i+1
                    if c != ' ' and b == None:
                        b = i
                i += 1
            self.commandFinished()
        elif command.startswith("unset"):
            command = command[6:]
            command = command.split(' ')
            for var in command:
                if var in self.env:
                    self.env.pop(var)
            self.commandFinished()
        elif command == "env":
            for var in self.env:
                self.commandAppend(var+"="+self.env[var])
            self.commandFinished()
        elif command == "pwd":
            self.commandAppend(self.cwd)
            self.commandFinished()
        elif command == "exit":
            vim.command(":bd!")
        else:
            ShellAsyncExecuteCmd(False,self.env)

    def commandAppend(self,line):
        vim.current.buffer.append(line)

    def commandFinished(self):
        vim.current.buffer.append("")
        vim.eval("setbufvar('%','pl',"+str(len(vim.current.buffer))+")")
        vim.eval("setbufvar('%','cfinished',1)")
        vim.command("call s:RefreshShellTerminal()")
        vim.command("startinsert")

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

def ShellAsyncTerminalRefreshOutput():
    global shellasync_cmds
    cfinished = vim.eval("getbufvar('%','cfinished')")
    if cfinished == None:
        return
    cfinished = int(cfinished)
    if cfinished == 1:
        return
    ShellAsyncRefreshOutput()
    pid = vim.eval("getbufvar('%','pid')")
    if pid == None:
        return
    pid = int(pid)
    if pid in shellasync_cmds:
        output = shellasync_cmds[pid]
        if output.returnValue() != None and not output.hasdata():
            vim.current.buffer.append("")
            vim.eval("setbufvar('%','cfinished',1)")
            vim.eval("setbufvar('%','pl',"+str(len(vim.current.buffer))+")")
            vim.command("call s:RefreshShellTerminal()")
            vim.command("call feedkeys(\"i\")")

def ShellAsyncExecuteCmd(clear,enviroment):
    global shellasync_cmds
    print_retval = vim.eval("g:shellasync_print_return_value") == '1'
    cmd = vim.eval("command")
    cwd = vim.eval("cwd")
    pid = vim.eval("getbufvar('%','pid')")
    if pid != None:
        pid = int(pid)
        ShellAsyncTermCmd(pid)
        ShellAsyncRefreshOutput()
        ShellAsyncDeleteCmd(pid)
    if clear:
        vim.current.buffer[:] = None
        vim.command("silent! refresh!")
    out = ShellAsyncOutput()
    pid = out.startProcess(cmd,cwd,enviroment,print_retval)
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
        set updatetime=500
        au BufWipeout <buffer> silent call <SID>TermShellInBuf(1)
        au BufEnter <buffer> set updatetime=500
        au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
        au CursorHold <buffer> python ShellAsyncRefreshOutput()
        nnoremap <buffer> <C-c> :echo '' \| call <SID>TermShellInBuf(0)<CR>
        python ShellAsyncExecuteCmd(True,os.environ)
    else
        exe winnr . 'wincmd w'
        python ShellAsyncExecuteCmd(True,os.environ)
    endif
endfunction
function! s:TermShellInBuf(del)
    let pid = getbufvar('%','pid')
    if pid != ''
        call s:TermShell([pid])
        if a:del
            call s:DeleteShell([pid])
        endif
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
        setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap nonumber filetype=shellasynclist
        call setbufvar("%","prevupdatetime",&updatetime)
        call setbufvar("%","command",command)
        set updatetime=500
        au BufEnter <buffer> set updatetime=500
        au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
        au CursorHold <buffer> python ShellAsyncListShells()
        nnoremap <silent> <buffer> t :call <SID>TermShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        nnoremap <silent> <buffer> K :call <SID>KillShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        nnoremap <silent> <buffer> d :call <SID>DeleteShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        nnoremap <silent> <buffer> x :call <SID>DeleteShell(<SID>GetPidList()) \| python ShellAsyncListShells()<CR>
        python ShellAsyncListShells()
    else
        exe winnr . 'wincmd w'
    endif
endfunction
function! s:GetTerminalPrompt()
    return eval(g:shellasync_terminal_prompt).' '
endfunction
function! s:RefreshShellTerminal()
    let pl = getbufvar('%','pl')
    if !(getline(pl) =~ '^'.s:GetTerminalPrompt())
        call setline(pl,s:GetTerminalPrompt())
    endif
    redraw!
endfunction
function! s:TerminalStartInsert()
    let pl = getbufvar('%','pl')
    let pos = getpos('.')
    let prompt = s:GetTerminalPrompt()
    if pos[1] != pl
        let pos[1] = pl
    endif
    if pos[1] == pl && pos[2] < len(prompt) 
        let pos[2] = col([pl,'$'])-1
    endif
    call setpos('.',pos)
endfunction
function! s:TerminalGetCommand()
    let pl = getbufvar('%','pl')
    let prompt = s:GetTerminalPrompt()
    let ln = getline(pl)
    let ln = ln[len(prompt)-1: len(ln)-2]
    return ln
endfunction
function! s:TerminalSetCommand(command)
    let pl = getbufvar('%','pl')
    call setline(pl,eval(g:shellasync_terminal_prompt).a:command.' ')
    normal! $
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
    let termnr = getbufvar('%','termnr')
    let command = pyeval('shellasync_terms['.termnr.'].historyup()')
    call s:TerminalSetCommand(command)
    startinsert
endfunction
function! s:TerminalDownPressed()
    let termnr = getbufvar('%','termnr')
    let command = pyeval('shellasync_terms['.termnr.'].historydown()')
    call s:TerminalSetCommand(command)
    startinsert
endfunction
function! s:TerminalEnterPressed()
    let cfinished = getbufvar('%','cfinished')
    let command = s:TerminalGetCommand()
    if cfinished == 0
        echo 'command is still running'
        return
    endif
    if empty(command)
        startinsert
    elseif command =~ '^\s*clear\s*$' 
        silent! normal! ggdGG
        call setbufvar('%','pl',1)
        call s:RefreshShellTerminal()
        startinsert
    else
        let termnr = getbufvar('%','termnr')
        let pid = getbufvar('%','pid')
        let cwd = pyeval('shellasync_terms['.termnr.'].cwd')
        if pid != ''
            silent! call s:DeleteShell([pid])
        endif
        call setbufvar('%','cfinished',0)
        exe 'python shellasync_terms['.termnr.'].execute()'
        python ShellAsyncTerminalRefreshOutput()
    endif
endfunction
function! s:TerminalBufEnter()
    if g:shellasync_terminal_insert_on_enter
        if b:cfinished
            startinsert
        else
            normal! G
        endif
    endif
endfunction
function! s:CloseShellTerminal()
    call s:TermShellInBuf(1)
endfunction
function! s:OpenShellTerminal()
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
    exe 'python shellasync_terms['.termnr.'] = ShellAsyncTerminal()'
    set updatetime=500
    au BufWipeout <buffer> silent call <SID>CloseShellTerminal()
    au BufEnter <buffer> set updatetime=500 | call <SID>TerminalBufEnter()
    au BufLeave <buffer> let &updatetime=getbufvar('%','prevupdatetime')
    au InsertEnter <buffer> call <SID>TerminalStartInsert()
    au CursorHold <buffer> python ShellAsyncTerminalRefreshOutput()
    inoremap <silent> <buffer> <Enter> <ESC>:call <SID>TerminalEnterPressed() \| normal! 0<CR>
    inoremap <silent> <buffer> <Left> <ESC>:call <SID>TerminalLeftPressed()<CR>
    inoremap <silent> <buffer> <Right> <ESC>:call <SID>TerminalRightPressed()<CR>
    inoremap <silent> <buffer> <Up> <ESC>:call <SID>TerminalUpPressed()<CR>
    inoremap <silent> <buffer> <Down> <ESC>:call <SID>TerminalDownPressed()<CR>
    inoremap <silent> <buffer> <BS> <ESC>:call <SID>TerminalBackspacePressed()<CR>
    nnoremap <silent> <buffer> <C-c> :call <SID>TermShell([getbufvar('%','pid')])<CR>
    call s:RefreshShellTerminal()
    startinsert
endfunction
command! -complete=shellcmd -bang -nargs=+ Shell call <SID>ExecuteInShell('<bang>',1,<q-args>)
command! -complete=shellcmd -bang -nargs=+ ShellNew call <SID>ExecuteInShell('<bang>',0,<q-args>)
command! -complete=shellcmd -nargs=+ ShellTerm call <SID>TermShell(<SID>GetPidList(<args>))
command! -complete=shellcmd -nargs=+ ShellKill call <SID>KillShell(<SID>GetPidList(<args>))
command! -complete=shellcmd -nargs=+ ShellDelete call <SID>DeleteShell(<SID>GetPidList(<args>))
command! ShellList call <SID>OpenShellsList()
command! ShellTerminal call <SID>OpenShellTerminal()
au VimLeavePre * python ShellAsyncTermAllCmds()

