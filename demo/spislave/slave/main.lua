
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "spislave"
VERSION = "1.0.1"

--[[
本demo分成主从两部分, 这里是SPI从机, Air601的
]]

sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    sys.wait(500)
    spislave.setup(2)
    rbuff = zbuff.create(1500)
    spislave.on(2, function(event, ptr, len)
        log.info("spi从机", event, ptr, len)
        if event == 0 then
            log.info("spi从机", "cmd数据", ptr, len)
        end
        if event == 1 then
            log.info("spi从机", "data数据", ptr, len)
        end
        if len and len > 0 then
            spislave.read(2, ptr, rbuff, len)
            log.info("spi从机", "数据读取完成,前4个字节分别是", rbuff[0], rbuff[1], rbuff[2], rbuff[3])
        end
    end)
    wbuff = zbuff.create(1024)
    wbuff[0] = 0xA5
    wbuff[1] = 0x5A
    wbuff[2] = 0x00
    wbuff[3] = 0x16
    local count = 0
    while true do
        --wbuff:seek(0)
        wbuff[7] = count & 0xFF
        wbuff[8] = (count >> 8) & 0xFF
        if spislave.ready(2) then
            spislave.write(2, 0, wbuff, 16 + 4)
        else
            log.info("spislave", "当前不可写入")
        end
        --log.info("wbuff数据", wbuff[7], wbuff[8])
        sys.wait(1000)
        count = count + 1
    end
end)

-- 结尾总是这一句哦
sys.run()
