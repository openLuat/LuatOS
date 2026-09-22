--[[
hzadb demo: 日志口用户指令协议 v2 (合宙adb)
配合 host/luat_usercmd.py 上位机库使用, 协议见 PROTOCOL.md

设备端仅注册标准操作集, 具体权限由本脚本控制(可裁剪安装或加路径白名单)。
通用库为 script/libs/hzadb.lua, 本目录不再自带协议栈。
]]
PROJECT = "hzadb"
VERSION = "001.000.000"
local sys = require "sys"
local hzadb = require "hzadb"

-- 可选: 开启鉴权(HMAC 挑战应答, 见 PROTOCOL.md §5.5)
-- 开启后未鉴权连接仅允许 HELLO/AUTH, 上位机需 dev.auth("同款token")
-- 生产建议 >=16 字节随机串; 默认关闭, 保持开箱即用
-- hzadb.set_auth("0123456789abcdef")

-- 心跳日志用于验证协议帧与日志帧在日志口共存时不互相干扰
sys.timerLoopStart(function()
    log.info("hzadb", "heartbeat")
end, 5000)

hzadb.fs()      -- 文件系统指令 + file_sha1(默认拦截 /luadb 的读文件请求)
hzadb.mem()     -- 内存状态指令(rtos.meminfo)
hzadb.netdrv()  -- 网络状态指令(netdrv 适配器状态)
local hzadb_ok = hzadb.start()

-- 启动信息: 挂载点与根分区空间(也便于人工确认 io.lsmount/io.fsstat 可用)
if io.lsmount then
    local parts = {}
    for _, m in ipairs(io.lsmount()) do
        parts[#parts + 1] = (m.path == "" and "/" or m.path) .. ":" .. tostring(m.fs)
    end
    log.info("hzadb", "mounts", table.concat(parts, " "))
end
if io.fsstat then
    local ok, tb, ub, bs, fst = io.fsstat("/")
    if ok then
        log.info("hzadb", "fsstat /", fst, string.format("%d/%d bytes, block %d", ub * bs, tb * bs, bs))
    end
end
-- 固件没开 LUAT_USE_LOG_USER_CMD 时不报错、只提示; 心跳继续打, 便于确认日志口本身正常
if hzadb_ok then
    log.info("hzadb", "demo ready, lib", hzadb.version())
else
    log.info("hzadb", "demo: 日志口用户指令未启用(固件需打开 LUAT_USE_LOG_USER_CMD), 仅保留心跳")
end

sys.run()
