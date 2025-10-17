
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fatfs"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
接线要求:

SPI 使用常规4线解法
开发板(Air105)         TF模块
PB3                    CS
PB2(SPI2_CLK)          CLK
PB4(SPI2_MISO)         MOSI
PB5(SPI2_MISO)         MISO
3.3V                   VCC
GND                    GND

核心要义: 找对应SPI端口的3个脚, CLK时钟, MISO和MOSI, CS脚可以选硬件默认的,也可以自选一个普通GPIO

SD/TF模块请选不带电平转换的版本!!
https://detail.tmall.com/item.htm?abbucket=10&id=634710962749&ns=1&spm=a21n57.1.0.0.696f523csnpBFA&skuId=4710673879054

如果是带电平转换的, SPI波特率要限制在10M或以下
]]

-- 特别提醒, 由于FAT32是DOS时代的产物, 文件名超过8个字节是需要额外支持的(需要更大的ROM)
-- 例如 /sd/boottime 是合法文件名, 而/sd/boot_time就不是合法文件名, 需要启用长文件名支持.

local rtos_bsp = rtos.bsp()

-- spi_id,pin_cs
local function fatfs_spi_pin()     
    if rtos_bsp == "AIR101" then
        return 0, pin.PB04
    elseif rtos_bsp == "AIR103" then
        return 0, pin.PB04
    elseif rtos_bsp == "AIR105" then
        return 2, pin.PB03
    elseif rtos_bsp == "ESP32C3" then
        return 2, 7
    elseif rtos_bsp == "ESP32S3" then
        return 2, 14
    elseif rtos_bsp == "EC618" then
        return 0, 8
    elseif string.find(rtos_bsp,"EC718") then
        return 0, 8
    elseif string.find(rtos_bsp,"Air810") then
        return 0, 3, fatfs.SDIO
    else
        log.info("main", "bsp not support")
        return
    end
end

sys.taskInit(function()
    sys.wait(1000)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因

    -- 此为spi方式
    local spi_id, pin_cs,tp = fatfs_spi_pin() 
    if tp and tp == fatfs.SPI then
        -- 仅SPI方式需要自行初始化spi, sdio不需要
        spi.setup(spi_id, nil, 0, 0, 8, 400 * 1000)
        gpio.setup(pin_cs, 1)
    end
    fatfs.mount(tp or fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)

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
