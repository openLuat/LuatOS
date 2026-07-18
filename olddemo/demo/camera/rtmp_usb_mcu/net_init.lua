-- spi id
local spi_id = 1
-- 片选引脚
local spi_cs = 14
-- 数据宽度
local spi_databits = 8
-- CPHA
local spi_cpha = 0
-- CPOL
local spi_cpol = 0
-- 时钟速率
local spi_speed = 25600000
-- 高低位顺序，可选，默认高位在前
local spi_bit_order = spi.MSB
-- 模式，可选，默认主模式
local spi_mode = spi.master
-- 通信方式，可选，默认全双工
local spi_communication = spi.full

local function ch390_init()
    local result = spi.setup(spi_id, nil, spi_cpha, spi_cpol, spi_databits, spi_speed, spi_bit_order, spi_mode, spi_communication)
    log.info("main", "open", result)
    if result ~= 0 then -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        return
    end
    -- netdrv.debug(0, true)
    netdrv.setup(socket.LWIP_USER0, netdrv.CH390, {
        spi = spi_id,
        cs = spi_cs
    })
    netdrv.dhcp(socket.LWIP_USER0, true)
end

ch390_init()