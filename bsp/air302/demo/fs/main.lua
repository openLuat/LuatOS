
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fsdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- 日志TAG, 非必须
local NETLED = gpio.setup(19, 0)

function fs_test()
    local f = io.open("boot_time", "rb")
    local c = 0
    if f then
        local data = f:read("*a")
        log.info("fs", "data", data, data:toHex())
        c = tonumber(data)
        f:close()
    end
    log.info("fs", "boot count", c)
    c = c + 1
    f = io.open("boot_time", "wb")
    --if f ~= nil then
    log.info("fs", "write c to file", c, tostring(c))
    f:write(tostring(c))
    f:close()
    --end

    if fs then
        log.info("fsstat", fs.fsstat("/"))
    end
end

fs_test() -- 每次开机,把记录的数值+1

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            NETLED(1)
            sys.wait(100)
            NETLED(0)
            sys.wait(1900)
        else
            NETLED(1)
            sys.wait(500)
            NETLED(0)
            sys.wait(500)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
