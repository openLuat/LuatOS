
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air302_spi_demo"
VERSION = "1.0.1"

local sys = require "sys"

local spiId = 0
local cs = 16
-- 这里注意了！！ 设备CS连接到 GPIO17, 不要接 cs脚。
local cspin = gpio.setup(17, 1)

--收发数据
local function sendRecv(data,len)
    local r = ""
    cspin(0)
    if data then spi.send(spiId,data) end
    if len then r = spi.recv(spiId,len) end
    cspin(1)
    return r
end


sys.taskInit(function()

    local result = spi.setup(
        spiId,--串口id
        cs,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        100000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    print("open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        print("spi open error",result)
        return
    end

    --检查芯片型号
    local chip = sendRecv(string.char(0x9f),3)
    if chip == string.char(0xef,0x40,0x16) then
        log.info("spi", "chip id read ok 0xef,0x40,0x16")
    else
        log.info("spi", "chip id read error")
        for i=1,#chip do
            print(chip:byte(i))
        end
        return
    end

    local data = "test data 123456"

    --enable write
    sendRecv(string.char(0x06))

    --写页数据到地址0x000001
    sendRecv(string.char(0x02,0x00,0x00,0x01)..data)
    log.info("spi","write",data)

    sys.wait(500)--等写入操作完成

    --读数据
    local r = sendRecv(string.char(0x03,0x00,0x00,0x01),data:len())
    log.info("spi","read",r)

    --disable write
    sendRecv(string.char(0x04))

    spi.close(spiId)
end)

-- 结尾总是这一句哦
sys.run()
