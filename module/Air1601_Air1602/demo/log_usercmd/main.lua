--[[
日志口用户指令协议 v2 demo
配合 host/luat_usercmd.py 上位机库使用, 协议见 PROTOCOL.md

设备端仅注册标准文件系统操作集, 具体权限由本脚本控制(可裁剪 reg_op 或加路径白名单)
]]
local sys = require "sys"
local uc = require "log_usercmd"

-- 可选: 开启鉴权(HMAC 挑战应答, 见 PROTOCOL.md §5.5)
-- 开启后未鉴权连接仅允许 HELLO/AUTH, 上位机需 dev.auth("同款token")
-- 生产建议 >=16 字节随机串; 默认关闭, 保持开箱即用
-- uc.set_auth("0123456789abcdef")

-- 心跳日志用于验证协议帧与日志帧在日志口共存时不互相干扰
sys.timerLoopStart(function()
    log.info("usercmd", "heartbeat")
end, 5000)

uc.fs()
uc.start()

-- 启动信息: 挂载点与根分区空间(也便于人工确认 io.lsmount/io.fsstat 可用)
if io.lsmount then
    local parts = {}
    for _, m in ipairs(io.lsmount()) do
        parts[#parts + 1] = (m.path == "" and "/" or m.path) .. ":" .. tostring(m.fs)
    end
    log.info("usercmd", "mounts", table.concat(parts, " "))
end
if io.fsstat then
    local ok, tb, ub, bs, fst = io.fsstat("/")
    if ok then
        log.info("usercmd", "fsstat /", fst, string.format("%d/%d bytes, block %d", ub * bs, tb * bs, bs))
    end
end
log.info("usercmd", "demo v2 ready")

sys.run()
