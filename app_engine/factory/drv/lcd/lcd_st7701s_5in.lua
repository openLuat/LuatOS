--[[
@module  st7701s_5in
@summary ST7701S RGB 5寸 480×854 屏幕驱动（含 IC 初始化命令）
@version 1.0
@date    2026.05.22
@author  江访
@usage
params: { port, pin_clk, pin_sda, pin_cs, pin_rst, direction, w, h, xoffset, yoffset,
          hbp, hspw, hfp, vbp, vspw, vfp, bus_speed, pclk }
]]
local M = {}

function M.init(params)
    gpio.setup(params.pin_cs or 3, 0)

    local r = lcd.init("custom", {
        port      = params.port or lcd.RGB,
        pin_rst   = params.pin_rst or 9,
        pin_clk   = params.pin_clk or 2,
        pin_sda   = params.pin_sda or 4,
        pin_cs    = params.pin_cs or 3,
        direction = params.direction or 0,
        pclk      = params.pclk or lcd.PCLK_RISING,
        w         = params.w or 480,
        h         = params.h or 854,
        xoffset   = params.xoffset or 0,
        yoffset   = params.yoffset or 0,
        hbp       = params.hbp or 30,
        hspw      = params.hspw or 6,
        hfp       = params.hfp or 12,
        vbp       = params.vbp or 30,
        vspw      = params.vspw or 1,
        vfp       = params.vfp or 12,
        bus_speed = params.bus_speed or (26 * 1000 * 1000),
    })
    if not r then return r end

    -- 复位序列
    local rp = gpio.setup(params.pin_rst or 9, 1)
    rp(1); sys.wait(20); rp(0); sys.wait(20); rp(1); sys.wait(120)

    -- ST7701S 初始化命令
    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x13)
    lcd.cmd(0xEF); lcd.data(0x08)
    -- Bank0
    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x10)
    lcd.cmd(0xC0); lcd.data(0xE9); lcd.data(0x03)
    lcd.cmd(0xC1); lcd.data(0x11); lcd.data(0x02)
    lcd.cmd(0xC2); lcd.data(0x01); lcd.data(0x08)
    lcd.cmd(0xCC); lcd.data(0x18)
    -- Gamma
    lcd.cmd(0xB0); lcd.data(0x00); lcd.data(0x0D); lcd.data(0x14); lcd.data(0x0D)
    lcd.data(0x10); lcd.data(0x05); lcd.data(0x02); lcd.data(0x08); lcd.data(0x08)
    lcd.data(0x1E); lcd.data(0x05); lcd.data(0x13); lcd.data(0x11); lcd.data(0xA3)
    lcd.data(0x29); lcd.data(0x18)
    lcd.cmd(0xB1); lcd.data(0x00); lcd.data(0x0C); lcd.data(0x14); lcd.data(0x0C)
    lcd.data(0x10); lcd.data(0x05); lcd.data(0x03); lcd.data(0x08); lcd.data(0x07)
    lcd.data(0x20); lcd.data(0x05); lcd.data(0x13); lcd.data(0x11); lcd.data(0xA4)
    lcd.data(0x29); lcd.data(0x18)
    -- Bank1 Power
    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x11)
    lcd.cmd(0xB0); lcd.data(0x6C)
    lcd.cmd(0xB1); lcd.data(0x43)
    lcd.cmd(0xB2); lcd.data(0x87)
    lcd.cmd(0xB3); lcd.data(0x80)
    lcd.cmd(0xB5); lcd.data(0x47)
    lcd.cmd(0xB7); lcd.data(0x85)
    lcd.cmd(0xB8); lcd.data(0x20)
    lcd.cmd(0xB9); lcd.data(0x10)
    lcd.cmd(0xC1); lcd.data(0x78)
    lcd.cmd(0xC2); lcd.data(0x78)
    lcd.cmd(0xD0); lcd.data(0x88)
    sys.wait(100)
    -- GIP
    lcd.cmd(0xE0); lcd.data(0x00); lcd.data(0x00); lcd.data(0x02)
    lcd.cmd(0xE1); lcd.data(0x08); lcd.data(0x00); lcd.data(0x0A); lcd.data(0x00); lcd.data(0x07)
    lcd.data(0x00); lcd.data(0x09); lcd.data(0x00); lcd.data(0x00); lcd.data(0x33); lcd.data(0x33)
    lcd.cmd(0xE2); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
    lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
    lcd.data(0x00); lcd.data(0x00)
    lcd.cmd(0xE3); lcd.data(0x00); lcd.data(0x00); lcd.data(0x33); lcd.data(0x33)
    lcd.cmd(0xE4); lcd.data(0x44); lcd.data(0x44)
    lcd.cmd(0xE5); lcd.data(0x0E); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x10)
    lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x0A); lcd.data(0x60); lcd.data(0xA0)
    lcd.data(0xA0); lcd.data(0x0C); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0)
    lcd.cmd(0xE6); lcd.data(0x00); lcd.data(0x00); lcd.data(0x33); lcd.data(0x33)
    lcd.cmd(0xE7); lcd.data(0x44); lcd.data(0x44)
    lcd.cmd(0xE8); lcd.data(0x0D); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x0F)
    lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x09); lcd.data(0x60); lcd.data(0xA0)
    lcd.data(0xA0); lcd.data(0x0B); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0)
    lcd.cmd(0xEB); lcd.data(0x02); lcd.data(0x01); lcd.data(0xE4); lcd.data(0xE4); lcd.data(0x44)
    lcd.data(0x00); lcd.data(0x40)
    lcd.cmd(0xEC); lcd.data(0x02); lcd.data(0x01)
    lcd.cmd(0xED); lcd.data(0xAB); lcd.data(0x89); lcd.data(0x76); lcd.data(0x54); lcd.data(0x01)
    lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF)
    lcd.data(0x10); lcd.data(0x45); lcd.data(0x67); lcd.data(0x98); lcd.data(0xBA)
    lcd.cmd(0xEF); lcd.data(0x08); lcd.data(0x08); lcd.data(0x08); lcd.data(0x45)
    lcd.data(0x3F); lcd.data(0x54)
    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x13)
    lcd.cmd(0xE8); lcd.data(0x00); lcd.data(0x0E)
    -- Exit
    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
    lcd.cmd(0x11); sys.wait(120)
    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x13)
    lcd.cmd(0xE8); lcd.data(0x00); lcd.data(0x0C); sys.wait(10)
    lcd.cmd(0xE8); lcd.data(0x00); lcd.data(0x00)
    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
    lcd.cmd(0x29)
    lcd.cmd(0x3a); lcd.data(0x77)
    lcd.cmd(0x36); lcd.data(0x08)
    sys.wait(20)

    log.info("st7701s", "初始化命令完成")
    return true
end

return M
