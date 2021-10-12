

--[[
当前仅MCU固件支持SD卡挂载


SD 模块接线说明

TF模块      --  Air640W
CS          --  PB9(对应为gpio29)
SCK         --  SPI_SCK,  PB16, gpio21
MISO        --  SPI_MISO, PB17, gpio22
MOSI        --  SPI_MOSI, PB18, gpio23

淘宝链接: https://item.taobao.com/item.htm?id=609983719613 小卡版本
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "tfdemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "sdcard demo")

sys.timerLoopStart(function()
    print("rdy")
end, 3000)

sys.taskInit(function()
    sys.wait(1000)
    -- 挂载sd卡
    fs.mkdir("/sd")
    spi.setup(0 * 10 + 1, 29) -- 生成的设备为 spi01
    fs.mount("spi01", "elm", "/sd", "sd")

    sys.wait(100)

    -- 写入文件
    local f = io.open("/sd/lua_ver.txt", "wb")
    f:write(_VERSION)
    f:close()

    sys.wait(100)

    f = io.open("/sd/lua_ver.txt", "rb")
    log.info("sdcard", f:read())
    f:close()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
