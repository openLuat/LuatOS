

--[[
本demo用于演示调试功能

提示: 需要最新代码, 编译最新固件, 需要Luatools 2.1.3以上, vscode找LuatOS debug插件


local.ini需要配置:
MAIN_LUA_DEBUG = 1
LUA_DEBUG = 1

否则因为没有调试信息, 导致无法触发断点

luatools 配置 config/global.ini
确保有如下配置

[luatdbg]
enable = 1




]]
dbg.wait()

local sys = require("sys")

local function call_abc(tag, val, date, time)
    log.info(tag, val, date)
    log.info(tag, val + time, date)
end

local function call_def(t)
    call_abc("QQ", 123, os.date(), t)
end

sys.taskInit(function()
    while true do
        call_def(os.time())
        sys.wait(3000)
    end
end)

sys.run()
