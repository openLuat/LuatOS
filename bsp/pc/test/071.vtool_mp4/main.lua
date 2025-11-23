
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    
    local src = "/luadb/abc.h264"
    local dst = "abc.mp4"

    local data = io.readFile(src)
    local mp4 = vtool.mp4create(dst, 1280, 720, 16)
    vtool.mp4write(mp4, data)
    vtool.mp4close(mp4)
    log.info("测试结束", io.fileSize(dst))
    os.exit(1)
end)

sys.run()
