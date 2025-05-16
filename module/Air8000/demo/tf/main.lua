
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fatfs"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

local rtos_bsp = rtos.bsp()

-- spi_id,pin_cs
local function fatfs_spi_pin()     
    return 1, 20    -- Air8000整机开发板上的pin_cs为gpio20
end

sys.taskInit(function()
    sys.wait(1000)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因

    -- 此为spi方式
    local spi_id, pin_cs,tp = fatfs_spi_pin() 
    -- 仅SPI方式需要自行初始化spi, sdio不需要
    spi.setup(spi_id, nil, 0, 0, pin_cs, 400 * 1000)
    gpio.setup(pin_cs, 1)
    fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)

    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end

    -- #################################################
    -- 文件操作测试
    -- #################################################
    local f = io.open("/sd/boottime", "rb")
    local c = 0
    if f then
        local data = f:read("*a")
        log.info("fs", "data", data, data:toHex())
        c = tonumber(data)
        f:close()
    end
    log.info("fs", "boot count", c)
    if c == nil then
        c = 0
    end
    c = c + 1
    f = io.open("/sd/boottime", "wb")
    if f ~= nil then
        log.info("fs", "write c to file", c, tostring(c))
        f:write(tostring(c))
        f:close()
    else
        log.warn("sdio", "mount not good?!")
    end
    if fs then
        log.info("fsstat", fs.fsstat("/"))
        log.info("fsstat", fs.fsstat("/sd"))
    end

    -- 测试一下追加, fix in 2021.12.21
    os.remove("/sd/test_a")
    sys.wait(50)
    f = io.open("/sd/test_a", "w")
    if f then
        f:write("ABC")
        f:close()
    end
    f = io.open("/sd/test_a", "a+")
    if f then
        f:write("def")
        f:close()
    end
    f = io.open("/sd/test_a", "r")
    if  f then
        local data = f:read("*a")
        log.info("data", data, data == "ABCdef")
        f:close()
    end

    -- 测试一下按行读取, fix in 2022-01-16
    f = io.open("/sd/testline", "w")
    if f then
        f:write("abc\n")
        f:write("123\n")
        f:write("wendal\n")
        f:close()
    end
    sys.wait(100)
    f = io.open("/sd/testline", "r")
    if f then
        log.info("sdio", "line1", f:read("*l"))
        log.info("sdio", "line2", f:read("*l"))
        log.info("sdio", "line3", f:read("*l"))
        f:close()
    end

    -- #################################################

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
