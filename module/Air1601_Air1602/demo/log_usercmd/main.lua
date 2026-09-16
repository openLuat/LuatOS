--[[
日志口用户指令协议 v2 demo
配合 host/luat_usercmd.py 上位机库使用, 协议见 PROTOCOL.md

设备端仅注册标准文件系统操作集, 具体权限由本脚本控制(可裁剪 reg_op 或加路径白名单)
]]
local sys = require "sys"
local uc = require "log_usercmd"

-- 心跳日志用于验证协议帧与日志帧在日志口共存时不互相干扰
sys.timerLoopStart(function()
    log.info("usercmd", "heartbeat")
end, 5000)

uc.fs()
uc.start()

log.info("usercmd", "demo v2 ready")

sys.run()
