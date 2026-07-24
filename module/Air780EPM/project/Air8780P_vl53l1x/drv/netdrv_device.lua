--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2026.07.21
@author  江访
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：
根据Air8780P项目需求，选择并且配置合适的网卡(网络适配器)
本demo使用4G网卡（LWIP_GP）

本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行
]]

-- 加载"4G网卡"驱动模块
require "netdrv_4g"
