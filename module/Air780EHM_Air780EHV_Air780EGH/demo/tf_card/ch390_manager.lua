--[[
@module ch390_manager
@summary CH390以太网芯片控制模块
@version 1.0.0
@date 2025.08.25
@author 王棚嶙
@usage
本文件专为Air780EHM/EHV/EGH开发板设计，用于管理CH390以太网芯片的供电和片选控制：
1. 控制CH390供电引脚（GPIO20）的开关
2. 控制CH390片选引脚（GPIO8）的电平状态
主要用途：
- 初始化时确保CH390不会干扰TF卡操作
本文件没有对外接口，直接在main.lua中require "ch390_manager"即可
]]

--[[详细解释为什么必须要先初始化打开ch390，并拉高：

 1. 本demo使用的是Air780EHM/EHV/EGH开发板硬件环境测试；
    在Air780EHM/EHV/EGH开发板上，spi0上同时外挂了tf卡和ch390h以太网芯片两种spi从设备，这两种外设通过不同的cs引脚区分；
    测试tf功能前，需要将ch390h的cs引脚拉高，这样可以保证ch390h不会干扰到tf功能；
    将ch390h的cs引脚拉高的方法为：打开ch390h供电，然后将ch390h的pin_cs，也就是gpio8输出高电平；

 2. 本功能模块是针对Air780EHM/EHV/EGH开发板写的，并不是通用代码，如果使用其他硬件环境，需要根据硬件原理图自行修改；
    例如：如果tf独立占用一路spi，就不需要加载本功能模块。


]]

-- 打开ch390供电脚
gpio.setup(20, 1, gpio.PULLUP) 

--上拉ch390使用spi的cs引脚避免干扰
gpio.setup(8,1)