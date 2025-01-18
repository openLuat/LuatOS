local ch390h = {
    buff = zbuff.create(2048)
}

local sys = require "sys"

local spiId = 0
local cs = 8
local CS = gpio.setup(cs, 1, gpio.PULLUP)

function ch390h.read(addr, len)
    if not len then
        len = 1
    end
    CS(0)
    local data = ""
    if addr == 0x72 then
        spi.send(spiId, string.char(addr))
        while len > 0 do
            if len > 64 then
                data = data .. spi.recv(spiId, 64)
                len = len - 64
            else
                data = data .. spi.recv(spiId, len)
                len = 0
                break
            end
        end
    else
        for i = 1, len, 1 do
            spi.send(spiId, string.char(addr + i - 1))
            data = data .. spi.recv(spiId, 1)
        end
    end
    CS(1)
    return data
end

function ch390h.write(addr, data)
    -- log.info("ch390h", "写入寄存器", addr, data, (string.char(addr | 0x80, data):toHex()))
    if type(data) == "number" then
        data = string.char(data)
    end
    CS(0)
    local tmp = string.char(addr | 0x80) .. data
    spi.send(spiId, tmp)
    -- local len = #tmp
    -- local offset = 1
    -- while len > 0 do
    --     if len > 64 then
    --         spi.send(spiId, data:sub(offset, offset + 64))
    --         len = len - 64
    --         offset = offset + 64
    --     else
    --         spi.send(spiId, data:sub(offset))
    --         break
    --     end
    -- end
    CS(1)
    -- log.info("读到的数据", addr, data:toHex())
    return data
end

function ch390h.mac()
    return ch390h.read(0x10, 6)
end

function ch390h.vid()
    return ch390h.read(0x28, 2)
end

function ch390h.pid()
    return ch390h.read(0x2A, 2)
end

function ch390h.revision()
    return ch390h.read(0x2C, 1)
end

function ch390h.default_config()
    ch390h.write(0, 0x01)
    sys.wait(20)
    ch390h.write(0x01, (1 << 5) | (1 << 3) | (1 << 2))
    ch390h.write(0x7E, 0xFF)
    ch390h.write(0x2D, 0x80)
    -- write_reg(0x31, 0x1F)
    ch390h.write(0x7F, 0xFF)

    ch390h.write(0x55, 0x01)
    ch390h.write(0x75, 0x0c)
    sys.wait(20)
    -- ch390h.enable_rx()
end

function ch390h.software_reset()
    ch390h.write(0, 0x01)
    sys.wait(20)
    ch390h.write(0, 0x00)
    ch390h.write(0, 0x01)
    sys.wait(20)
end

function ch390h.enable_rx()
    -- ch390h.write(0x05, (1 <<4) | (1 <<0) | (1 << 1) | (1 << 3))
    ch390h.write(0x05, (1 <<4) | (1 <<0) | (1 << 3))
    -- ch390h.write(0x05, (1 <<4) | (1 <<0))
    ch390h.write(0x1F, 0)
end

function ch390h.disable_rx()
    ch390h.write(0x05, 0)
end

function ch390h.enable_phy()
    ch390h.write(0x1F, 0)
end

function ch390h.link()
    local link = (ch390h.read(0x01, 1):byte() & (1 << 6))
    return link ~= 0
end

function ch390h.receive_packet()
    -- 先假读一次
    ch390h.read(0x70, 1)
    local rx_ready = ch390h.read(0x70, 1):byte()
    if (rx_ready & 0xFE) ~= 0x0 then
        log.info("ch390h", "出错了,复位!!!", (string.char(rx_ready):toHex()))
        ch390h.write(0x05, 0)
        ch390h.write(0x55, 1)
        ch390h.write(0x75, 0)
        sys.wait(1)
        -- ch390h.enable_rx()
        -- ch390h.software_reset()
        ch390h.default_config()
        -- ch390h.write(0x05, (1 <<4) | (1 <<3) | (1 <<1) | (1 <<0))
        return
    end
    if (rx_ready & 0x01) == 0 then
        -- log.info("ch390h", "没有数据", (string.char(rx_ready):toHex()))
        return -- 没有数据
    end
    -- 读4个字节
    local tmp = ch390h.read(0x72, 4)
    local rx_status = tmp:byte(2)
    local rx_len = tmp:byte(3) + (tmp:byte(4) << 8)
    -- log.info("ch390h", rx_status, rx_len, (tmp:toHex()))
    return ch390h.read(0x72, rx_len)
end

function ch390h.send_packet(buff)
    ch390h.write(0x78, buff:query())
    local tmp = ch390h.read(0x02, 1):byte()
    if (tmp & 0x01) == 0 then
        local len = buff:used()
        ch390h.write(0x7C, len & 0xFF)
        ch390h.write(0x7D, (len >> 8) & 0xFF)
        tmp = ch390h.read(0x02, 1):byte()
        ch390h.write(0x02, tmp | (1<<0))
        -- log.info("ch390h", "底层发送", buff:used())
    else
        log.info("ch390h", "底层忙")
    end
end

return ch390h
