# shellasync.vim plugin for asynchronously executing shell commands in vim
# Maintainer: Dmitry "troydm" Geurkov <d.geurkov@gmail.com>
# Version: 0.3.7
# Description: shellasync.vim plugin allows you to execute shell commands
# asynchronously inside vim and see output in seperate buffer window.
# Last Change: 31 January, 2013
# License: Vim License (see :help license)
# Website: https://github.com/troydm/shellasync.vim

import vim, sys, os, re, select, subprocess, threading, signal, time, fcntl

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
        self.outputrem = False
        self.outputremc = False
        self.newdata = False
        self.input = []
        self.waitingForInput = False
        self.remainder = ''

    def startProcess(self,cmd,cwd,env,print_retval):
        self.lock.acquire()
        self.command = cmd
        self.cwd = cwd
        self.env = env
        self.print_retval = print_retval
        self.lock.release()
        self.start()
        time.sleep(0.0000001)
        i = 0
        pid = None
        while True:
            pid = self.pid()
            if i >= 1000 or pid != None:
                return pid
            time.sleep(0.001)
            i += 1
        return None
    
    def run(self):
        self.lock.acquire()
        p = subprocess.Popen(self.command+" 2>&1", shell=True, cwd=self.cwd, env=self.env, preexec_fn=os.setsid, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        fcntl.fcntl(p.stdout.fileno(), fcntl.F_SETFL, os.O_NONBLOCK)
        if 'poll' in dir(select):
            pl = select.poll()
            pl.register(p.stdout)
        else:
            pl = None
            # kq = select.kevent(p.stdout.fileno(),filter=select.KQ_FILTER_READ)
        self.processPid = p.pid
        self.lock.release()
        retval = None
        out = ''
        while True:
            try:
                canWrite = False
                if pl != None:
                    plr = pl.poll(50)
                    if len(plr) == 0:
                        outread = ''
                    else:
                        plr = plr[0][1]
                        try:
                            if plr & select.POLLIN or plr & select.POLLPRI:
                                outread = p.stdout.read()
                            else:
                                outread = ''
                        except IOError:
                            outread = ''
                    canWrite = type(plr) == list or (pl != None and (plr & select.POLLOUT) > 0)
                else:
                    try:
                        outread = p.stdout.read()
                    except IOError:
                        outread = ''
                    canWrite = True
                if len(outread) == 0 and canWrite:
                    wr = self.getWrite()
                    if wr != None:
                        if wr == "\x04":
                            p.stdin.close()
                        else:
                            p.stdin.write(wr)
                            p.stdin.flush()
                            outread += wr
                        time.sleep(0.001)
                if len(outread) == 0:
                    retval = p.poll()
                    if retval != None:
                        self.lock.acquire()
                        self.waitingForInput = False
                        self.retval = retval
                        self.lock.release()
                        break
                    else:
                        if len(out) > 0:
                            self.extendrem(out)
                        self.lock.acquire()
                        self.waitingForInput = True
                        self.lock.release()
                        time.sleep(0.01)
                else:
                    self.lock.acquire()
                    self.waitingForInput = False
                    self.lock.release()
                    out += outread
                    while out.find("\n") != -1:
                        out = out.split("\n")
                        lines = out[:-1]
                        out = out[-1]
                        self.extend(lines)
                    if len(out) > 0:
                        self.extendrem(out)
                        self.lock.acquire()
                        self.waitingForInput = True
                        self.lock.release()
            except IOError:
                time.sleep(0.01)
        if pl != None:
            pl.unregister(p.stdout)
        if len(out) > 0:
            while out.find("\n") != -1:
                out = out.split("\n")
                lines = out[:-1]
                out = out[-1]
                self.extend(lines)
            if len(out) > 0:
                self.extend([out])
        if self.print_retval:
            self.extend(["","Shell command "+self.command+" completed with exit status "+str(retval)])

    def isRunning(self):
        self.lock.acquire()
        ret = self.retval == None
        self.lock.release()
        return ret

    def isWaitingForInput(self):
        self.lock.acquire()
        ret = len(self.input) == 0 and self.waitingForInput
        self.lock.release()
        return ret

    def getRemainder(self):
        self.lock.acquire()
        if self.waitingForInput:
            ret = self.remainder
        else:
            ret = '' 
        self.lock.release()
        return ret

    def get(self):
        r = None
        self.lock.acquire()
        self.newdata = False
        if len(self.output) > 0:
            r = (self.outputrem, self.outputremc, self.output)
            self.outputremc = False
            self.output = []
        self.lock.release()
        return r

    def hasdata(self):
        self.lock.acquire()
        r = len(self.output) > 0
        self.lock.release()
        return r

    def hasnewdata(self):
        self.lock.acquire()
        r = self.newdata
        self.lock.release()
        return r

    def extend(self,data):
        # remove ANSI escape sequences
        for d in data:
            if "\033" in d:
                r = re.compile("\033\[\d*;?\d*[A-KST]")
                data = map(lambda i: r.sub("",i), data)
                break
        self.lock.acquire()
        self.newdata = True
        if self.outputrem:
            self.output = []
        self.outputremc = self.outputrem or self.outputremc
        self.outputrem = False
        self.output.extend(data)
        self.lock.release()

    def extendrem(self,data):
        # remove ANSI escape sequences
        if "\033" in data:
            r = re.compile("\033\[\d*;?\d*[A-KST]")
            data = r.sub("", data)
        self.lock.acquire()
        if len(self.output) > 0:
            self.lock.release()
            return
        self.outputremc = not self.outputrem
        self.outputrem = True
        self.remainder = data
        if len(self.output) > 0:
            self.output[0] = data
        else:
            self.output.append(data)
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

    def write(self,data):
        if data == None:
            return
        if type(data) == list:
            for i in xrange(len(data)):
                data[i] += "\n"
        else:
            data += "\n"
        self.writenonl(data)

    def writenonl(self,data):
        if data == None:
            return
        self.lock.acquire()
        if type(data) == list:
            self.input.extend(data)
        else:
            self.input.append(data)
        self.lock.release()

    def getWrite(self):
        out = None
        self.lock.acquire()
        if len(self.input) > 0:
            out = self.input.pop(0)
        self.lock.release()
        return out

class ShellAsyncTerminal:
    def __init__(self):
        self.cwd = vim.eval('getcwd()')
        self.env = dict(os.environ)
        self.pid = None
        self.history = []
        self.historyind = -1
        self.sendhistory = []
        self.sendhistoryind = -1

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

    def sendhistoryup(self):
        if len(self.sendhistory) == 0:
            return ""
        if self.sendhistoryind == -1:
            self.sendhistoryind = len(self.sendhistory)-1
        else:
            self.sendhistoryind -= 1
        if self.sendhistoryind in xrange(len(self.sendhistory)):
            return self.sendhistory[self.sendhistoryind]
        else:
            self.sendhistoryind = -1
        return ""

    def sendhistorydown(self):
        if len(self.sendhistory) == 0:
            return ""
        if self.sendhistoryind == -1:
            self.sendhistoryind = 0
        else:
            self.sendhistoryind += 1
        if self.sendhistoryind in xrange(len(self.sendhistory)):
            return self.sendhistory[self.sendhistoryind]
        else:
            self.sendhistoryind = -1
        return ""

    def send(self,nl):
        if self.pid != None:
            command = vim.eval('send_input')
            if len(command) > 0:
                if len(self.sendhistory) > 0:
                    if self.sendhistory[-1] != command:
                        self.sendhistory.append(command)
                else:
                    self.sendhistory.append(command)
            self.sendhistoryind = -1
            ShellAsyncSendCmd(self.pid,nl)

    def execute(self):
        self.sendhistory = []
        self.sendhistoryind = -1
        self.pid = None
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
                self.pid = ShellAsyncExecuteCmd(False,self.env)
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
            self.pid = ShellAsyncExecuteCmd(False,self.env)

    def commandAppend(self,line):
        vim.current.buffer.append(line)

    def commandFinished(self):
        self.sendhistory = []
        self.sendhistoryind = -1
        self.pid = None
        vim.current.buffer.append("")
        vim.eval("setbufvar('%','pl',"+str(len(vim.current.buffer))+")")
        vim.eval("setbufvar('%','cfinished',1)")
        vim.command("call shellasync#RefreshShellTerminal()")
        vim.command("startinsert")

def ShellAsyncRefreshOutputFetch(output):
    switchbackint = 0
    while True:
        out = output.get()
        if out != None:
            rem = out[0]
            remc = out[1]
            out = out[2]
            if rem:
                remc = remc and len(vim.current.buffer) != 1
                if remc:
                    vim.current.buffer.append(out)
                    vim.command("normal! G0")
                switchbackwnr = vim.eval("getbufvar('%','switchbackwnr')")
                if switchbackwnr != None and switchbackwnr != '':
                    if switchbackint > 9:
                        if output.isWaitingForInput():
                            vim.command("unlet! b:switchbackwnr")
                            vim.command(str(switchbackwnr)+"wincmd w")
                            break
                    else:
                        time.sleep(0.001)
                        switchbackint += 1
                        continue
                if remc and int(vim.eval("&filetype == 'shellasyncterm'")) == 1:
                    vim.command("startinsert")
                break
            else:
                if remc and len(vim.current.buffer) > 1:
                    if out[0].rstrip().find(vim.current.buffer[-1].rstrip()) == 0:
                        vim.current.buffer[-1] = None
                if len(vim.current.buffer) == 1 and len(vim.current.buffer[0]) == 0:
                    vim.current.buffer[0] = out[0]
                    out = out[1:]
                    if len(out) > 0:
                        vim.current.buffer.append(out)
                else:
                    vim.current.buffer.append(out)
                vim.command("normal! G0")
                time.sleep(0.001)
                switchbackint = 0
        else:
            break

def ShellAsyncRefreshOutput():
    global shellasync_cmds
    pid = vim.eval("getbufvar('%','pid')")
    if pid == None or pid == '':
        return 
    pid = int(pid)
    if pid in shellasync_cmds:
        output = shellasync_cmds[pid]
        if output != None:
            ShellAsyncRefreshOutputFetch(output)
    vim.command("call feedkeys(\"f\e\",'n')")

def ShellAsyncRefreshOutputI():
    global shellasync_cmds
    pid = vim.eval("getbufvar('%','pid')")
    if pid == None or pid == '':
        return 
    pid = int(pid)
    if pid in shellasync_cmds:
        output = shellasync_cmds[pid]
        if output != None:
            if output.hasnewdata():
                vim.command('stopinsert')
                return
    linelen = int(vim.eval("col('$')-1"))
    if linelen > 0:
        if int(vim.eval("col('.')")) == 1:
            vim.command("call feedkeys(\"\<Right>\<Left>\",'n')")
        else:
            vim.command("call feedkeys(\"\<Left>\<Right>\",'n')")
    else:
        vim.command("call feedkeys(\"\ei\",'n')")


def ShellAsyncTerminalRefreshOutput():
    global shellasync_cmds
    cfinished = vim.eval("getbufvar('%','cfinished')")
    if cfinished == None or cfinished == '':
        return
    cfinished = int(cfinished)
    if cfinished == 1:
        return
    ShellAsyncRefreshOutput()
    pid = vim.eval("getbufvar('%','pid')")
    if pid == None or pid == '':
        return
    pid = int(pid)
    if pid in shellasync_cmds:
        output = shellasync_cmds[pid]
        if output.returnValue() != None and not output.hasdata():
            vim.current.buffer.append("")
            vim.eval("setbufvar('%','cfinished',1)")
            vim.eval("setbufvar('%','pl',"+str(len(vim.current.buffer))+")")
            vim.command("call shellasync#RefreshShellTerminal()")
            vim.command("call feedkeys(\"i\")")
    else:
        vim.eval("setbufvar('%','cfinished',1)")
        vim.eval("setbufvar('%','pl',"+str(len(vim.current.buffer))+")")
        vim.command("call shellasync#RefreshShellTerminal()")
        vim.command("call feedkeys(\"i\")")

def ShellAsyncTerminalRefreshOutputI():
    global shellasync_cmds
    cfinished = vim.eval("getbufvar('%','cfinished')")
    if cfinished == None or cfinished == '':
        return
    cfinished = int(cfinished)
    if cfinished == 1:
        return
    ShellAsyncRefreshOutputI()

def ShellAsyncExecuteCmd(clear,enviroment):
    global shellasync_cmds
    print_retval = vim.eval("g:shellasync_print_return_value") == '1'
    cmd = vim.eval("command")
    cwd = vim.eval("cwd")
    pid = vim.eval("getbufvar('%','pid')")
    if pid != None and pid != '':
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
    return pid

def ShellAsyncEchoMessage(message):
    message = message.replace('"','\\"')
    vim.command("echomsg \""+message+"\"")

def ShellAsyncTermCmd(pid):
    global shellasync_cmds
    if pid in shellasync_cmds:
        out = shellasync_cmds[pid]
        if not out.isAlive():
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" is finished")
            return True
        try:
            os.killpg(pid,signal.SIGTERM)
        except OSError:
            os.kill(pid,signal.SIGTERM)
        out.join(15.0)
        if out.isAlive():
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" is still running")
            return False
        else:
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" terminated")
    return True

def ShellAsyncKillCmd(pid):
    global shellasync_cmds
    if pid in shellasync_cmds:
        out = shellasync_cmds[pid]
        if not out.isAlive():
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" is finished")
            return True
        try:
            os.killpg(pid,signal.SIGKILL)
        except OSError:
            os.kill(pid,signal.SIGKILL)
        out.join(15.0)
        if out.isAlive():
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" is still running")
            return False
        else:
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" killed")
    return True

def ShellAsyncDeleteCmd(pid):
    global shellasync_cmds
    if pid in shellasync_cmds:
        out = shellasync_cmds[pid]
        if not out.isAlive():
            shellasync_cmds.pop(pid)
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" deleted")
            return True
        else:
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" is still running")
            return False
    return True

def ShellAsyncShellRunning(pid):
    global shellasync_cmds
    if pid in shellasync_cmds:
        return shellasync_cmds[pid].isRunning()
    return False

def ShellAsyncSendCmd(pid,nl):
    global shellasync_cmds
    input = vim.eval('send_input')
    if pid in shellasync_cmds:
        out = shellasync_cmds[pid]
        if not out.isAlive():
            ShellAsyncEchoMessage("shell command "+out.processCommand()+" pid: "+str(pid)+" is finished")
            return False
        else:
            if nl:
                out.write(input)
            else:
                out.writenonl(input)
            return True
    return False

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
    selectbnr = vim.eval("getbufvar('%','selectbnr')")
    vim.current.buffer[:] = None
    title='shellasync - list of running processes (press t to terminate, K to kill, d to delete, s to send input' 
    if selectbnr != None and selectbnr != '':
        vim.current.buffer[0]=title+', S to select shell)'
    else:
        vim.current.buffer[0]=title+')'
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

