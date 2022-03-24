local testfs = {}

local sys = require "sys"

local function fs_test()
    -- 文件读取
    local f = io.open("/boot_time", "rb")
    local c = 0
    if f then
        local data = f:read("*a")
        log.info("fs", "data", data, data:toHex())
        c = tonumber(data)
        f:close()
    end
    -- 文件写入
    log.info("fs", "boot count", c)
    c = c + 1
    f = io.open("/boot_time", "wb")
    --if f ~= nil then
    log.info("fs", "write c to file", c, tostring(c))
    f:write(tostring(c))
    f:close()
    --end

    -- 文件追加
    f = io.open("/abc", "a")
    if f then
        log.info("fs", "open with 'a' ok")
        f:write("abc")
        f:close()
    else
        log.info("fs", "open with 'a' fail")
    end

    if fs then
        log.info("fsstat", fs.fsstat(""))
    end
end

sys.taskInit(function()
    fs_test() -- 每次开机,把记录的数值+1
    while 1 do
        sys.wait(100)
    end
end)

return testfs