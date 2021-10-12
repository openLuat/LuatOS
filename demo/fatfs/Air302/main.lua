
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fatfs"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- 注意: V0006 beta5 开始才有fatfs模块,而且默认不包含进固件.

--[[
接线要求:
TF模块通常是5V, 然后用转3.3v, 记得使用5V供电.

SPI 使用常规4线解法, 本demo使用的GPIO18作为CS, 没使用默认SPI_CS.
]]

local NETLED = gpio.setup(19, 0, gpio.PULLUP) -- 输出模式

sys.taskInit(function()

    while 1 do
        -- 一闪一闪亮晶晶
        NETLED(0)
        sys.wait(500)
        NETLED(1)
        --G18(1)
        sys.wait(500)
    end
end)

sys.taskInit(function()
    sys.wait(5000) -- 启动延时
    local spiId = 0
    local cs = 0
    local result = spi.setup(
        spiId,--串口id
        cs,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        400*0000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    gpio.setup(18, 1)
    --fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
    fatfs.mount("SD", 0, 18)
    local data, err = fatfs.getfree("SD")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end

    -- 重新设置spi,使用更高速率
    spi.close(0)
    sys.wait(100)
    spi.setup(spiId, cs, 0, 0, 8, 2*1000*1000)

    local data, err = fatfs.getfree("SD")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
