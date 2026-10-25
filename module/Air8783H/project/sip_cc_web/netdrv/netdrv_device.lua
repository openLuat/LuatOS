--[[
@module  netdrv_device
@summary 项目网络驱动加载入口
@usage
加载当前项目选择的网络驱动，业务配置的 socket adapter 应与该驱动一致。
]]

-- 只启用一行；同时在 config.lua 设置对应的 adapter。
require "netdrv_4g"
-- require "netdrv_wifi"
