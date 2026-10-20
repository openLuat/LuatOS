--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2026.09.16
@description
本工程使用 4G 网卡，加载 netdrv_4g 完成网络适配。
本文件没有对外接口，在 main.lua 中加载即可。
]]

-- 与官方 SIP demo 保持网络驱动模块分层，本工程仅启用 4G。
require "netdrv_4g"
