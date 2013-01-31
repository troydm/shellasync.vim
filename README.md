shellasync.vim
==============

shellasync.vim plugin for asynchronously executing shell commands in vim


Introduction
------------
shellasync.vim plugin allows you to asynchronously execute shell commands inside vim 
and see output inside a seperate window buffer without waiting for a command to finish.
It also includes shell emulator so you can interactivly execute commands inside vim buffer.
It uses python's subprocess and threading capabilities to execute shell commands in seperate
thread and non-blockingly get the output as the command executes

Note: this plugin is highly experimental, so it might make your vim process unstable

Platform: 
    only unix based operating systems are supported

Requirements: 
    vim 7.3 with atleast 569 patchset included and compiled with python support

Screenshot
----------
![image](http://imgur.com/GxM0U.png)

Usage
-----

See :help shellasync
