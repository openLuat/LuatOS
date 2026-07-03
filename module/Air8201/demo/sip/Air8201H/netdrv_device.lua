--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2025.07.24
@author  朱天华
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_4g：socket.LWIP_GP，4G网卡；
2、netdrv_pc：pc模拟器上的网卡

本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]


-- 加载"4G网卡"驱动模块
require "netdrv_4g"

-- 加载"pc模拟器网卡"驱动模块
-- require "netdrv_pc"
