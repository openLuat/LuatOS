**English** | [中文](./README_zh.md) 

![github license](https://img.shields.io/github/license/Dozingfiretruck/nes)![linux](https://github.com/Dozingfiretruck/nes/actions/workflows/action.yml/badge.svg?branch=master)



# nes

#### Introduction
The nes simulator implemented in c , requires c11

**attention：**

**This repository is only for the nes simulator and does not provide the game ！！！**

Support：

- [x] CUP

- [x] PPU

- [ ] APU

mapper  support：0，2

#### Software Architecture
The example is based on SDL2 for image and sound output, without special dependencies, and you can port to any hardware by yourself


#### Compile Tutorial

​	clone repository，install[xmake](https://github.com/xmake-io/xmake)  ，execute `xmake` directly to compile

#### Instructions

​	on linux enter  `./nes xxx.nes` load the game to run
​	on windows enter `.\nes.exe xxx.nes` load the game to run



Key mapping:：

​                                      up                                                    A            B

​                           left  down  right	  select      start        

P1:

​                                      W                                                     J            K

​                            A	    S	    D		      V             B        

P2:

​                                       ↑                                                      5            6

​                             ←	  ↓	    →		    1             2        

#### Literature reference

https://www.nesdev.org/



