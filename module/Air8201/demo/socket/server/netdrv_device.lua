--[[
@module  netdrv_device
@summary 网络驱动设备功能模块 
@version 1.0
@date    2025.11.15
@author  王世豪
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_4g：socket.LWIP_GP，4G网卡（Air8201整机板默认）；
2、netdrv_pc：PC模拟器网卡，仅用于PC端调试；

根据自己的项目需求，只需要require以上两种中的一种即可；

本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]

-- 加载"4G网卡"驱动模块
require "netdrv_4g"

-- 加载"PC模拟器网卡"驱动模块（仅PC端调试使用）
-- require "netdrv_pc"
