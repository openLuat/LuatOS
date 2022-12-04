
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fsdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local function fs_test()
    -- 根目录/是可写
    local f = io.open("/boot_time", "rb")
    local c = 0
    if f then
        local data = f:read("*a")
        log.info("fs", "data", data, data:toHex())
        c = tonumber(data)
        f:close()
    end
    log.info("fs", "boot count", c)
    c = c + 1
    f = io.open("/boot_time", "wb")
    --if f ~= nil then
    log.info("fs", "write c to file", c, tostring(c))
    f:write(tostring(c))
    f:close()
    --end

    if fs then
        log.info("fsstat", fs.fsstat("/"))
    end

    local ret, files = io.lsdir("/")
    log.info("fatfs", "lsdir", json.encode(files))

    -- 读取刷机时加入的文件, 并演示按行读取
    -- 刷机时选取的非lua文件, 均存放在/luadb/目录下, 单层无子文件夹
    f = io.open("/luadb/abc.txt", "a")
    if f then
        while true do
            local line = f:read("l")
            if not line or #line == 0 then
                break
            end
            log.info("fs", "read line", line)
        end
        f:close()
        log.info("fs", "close f")
    else
        log.info("fs", "pls add abc.txt!!")
    end
end



sys.taskInit(function()
    -- 为了显示日志,这里特意延迟一秒
    -- 正常使用不需要delay
    sys.wait(1000)
    fs_test()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
