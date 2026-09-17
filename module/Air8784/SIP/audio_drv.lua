--[[
@module  audio_drv
@summary 音频驱动入口模块
@version 1.0
@date    2026.09.16
@description
本模块返回 audio_1103 的接口，具体硬件适配由 audio_1103.lua 实现。
]]

-- 与官方 SIP demo 保持 audio_drv 入口；硬件实现集中在 audio_1103。
return require "audio_1103"
