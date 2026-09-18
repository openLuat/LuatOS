--[[
@module  lcd_st7701s_5in
@summary ST7701S RGB 5寸 480×854 IC 初始化命令序列
@version 2.0
@date    2026.09.16
@author  江访
@usage
方式一（推荐）: 作为 lcd_display_rgb 的 ic_init 回调
  lcd = {
      model = "lcd_display_rgb",
      params = {
          ic_init = require("lcd_st7701s_5in").ic_init,
          ... 其他 RGB 参数 ...
      },
  }

方式二: 独立使用（内部自动建立 SPI 通道）
  local drv = require("lcd_st7701s_5in")
  drv.init({ pin_clk = 23, pin_sda = 2, pin_cs = 22, pin_rst = 15,
             w = 480, h = 854, hbp = 40, hspw = 10, hfp = 40,
             vbp = 10, vspw = 8, vfp = 20 })
]]
local M = {}

--- ST7701S IC 寄存器初始化命令（SPI 3-wire 9bit）
-- 由 lcd_display_rgb 的 spi_ic_init 建立 SPI 通道后调用
-- @param table params  含 pin_cs, pin_rst 等引脚参数
local function st7701s_ic_init(params)
    -- 复位序列
    local rp = gpio.setup(params.pin_rst or 15, 1)
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
end

-- 暴露 ic_init 供 lcd_display_rgb 调用（方式一）
M.ic_init = st7701s_ic_init

--[[
独立初始化（方式二）：建立 SPI 通道 + 发送 IC 命令
用于不经过 lcd_display_rgb 的场景
]]
function M.init(params)
    gpio.setup(params.pin_cs or 22, 0)

    local r = lcd.init("custom", {
        port      = lcd.HWID_0,
        pin_clk   = params.pin_clk,
        pin_sda   = params.pin_sda,
        pin_cs    = params.pin_cs,
        direction = 0,
        w         = params.w,
        h         = params.h,
    })
    if not r then return r end

    st7701s_ic_init(params)
    log.info("st7701s", "独立初始化完成")
    return true
end

return M
