
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "spislave"
VERSION = "1.0.1"

--[[
本demo分成主从两部分, 这里是SPI主机, Air780E的
]]

sys = require("sys")

PIN_CS = gpio.setup(8, 1, gpio.PULLUP)
SPI_ID = 0

tmpbuff = zbuff.create(4)

function xt804_read(addr, len)
    -- 尝试读取
    if not len or len < 1 or len > 1500 then
        return
    end
    tmpbuff:seek(0)
    PIN_CS(0)
    spi.send(SPI_ID, string.char(addr & 0xFF))
    local data = spi.recv(SPI_ID, len, tmpbuff)
    -- local data = spi.recv(SPI_ID, len)
    PIN_CS(1)
    return tmpbuff:query(0, len)
    -- return data
end


function xt804_write(addr, data)
    -- 尝试读取
    PIN_CS(0)
    spi.send(SPI_ID, string.char((addr & 0xFF) | 0x80))
    spi.send(SPI_ID, data)
    PIN_CS(1)
end

sys.taskInit(function()
    sys.wait(500)
    local result = spi.setup(SPI_ID, nil, 0 , 0, 8, 10 * 1000 * 1000)
    log.info("SPI初始化完成", result)

    -- 长度读一个寄存器试试
    while 1 do
        -- 数据读取测试
        local data = xt804_read(0x02, 2)
        if data and #data == 2 then
            log.info("待读取数据长度寄存器", data:toHex())
            local _, len = pack.unpack(data, "<H")
            log.info("待读取数据长度", len)
            if len and len > 0 then
                local tmpdata = ""
                for i = 0, len - 4, 4 do
                    local data = xt804_read(0x00, 4)
                    tmpdata = tmpdata .. data
                end
                local data = xt804_read(0x10, 4)
                tmpdata = tmpdata .. data
                log.info("从机数据", tmpdata:toHex())
            end
        end
        -- 数据写入测试
        xt804_write(0x01, string.char(0xA5, 0, 0x04, 0x00))
        xt804_write(0x11, string.char(0x01, 0x00, 0x01, 0x00))
        sys.wait(1000)
    end
end)

-- 结尾总是这一句哦
sys.run()
