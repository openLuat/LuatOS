--[[
@module  lcd_display_rgb
@summary RGB 屏统一通过 display 库初始化（替代 lcd.init）
@version 2.0
@date    2026.09.15
@usage
params 透传给 display.init("custom", ...)：
  w, h, hbp, hspw, hfp, vbp, vspw, vfp, pclk_hz / bus_speed,
  pin_rst, pin_bl, pin_pwr, interface

可选 SPI IC 初始化（NV3052C/ST7701S/GC9503 等需要 SPI 寄存器配置的 RGB IC）：
  pin_clk, pin_sda, pin_cs  → SPI 总线引脚
  ic_init                    → function(params) IC 寄存器写入回调

PC 模拟器 AirUI 走 SDL2，跳过 display.init 避免双窗口。
]]
local M = {}

-- SPI IC 初始化：通过 lcd.init 建立 SPI 通道，发送 IC 寄存器序列
local function spi_ic_init(params)
    if not params.pin_clk or not params.pin_sda or not params.pin_cs then
        return
    end
    if not lcd or not lcd.init then
        log.error("lcd_display_rgb", "lcd 模块不存在，无法进行 SPI IC 初始化")
        return
    end
    -- lcd.init("custom", ...) 仅建立 SPI 通道，port 不走 RGB
    local spi_params = {
        port      = lcd.HWID_0,
        pin_clk   = params.pin_clk,
        pin_sda   = params.pin_sda,
        pin_cs    = params.pin_cs,
        pin_rst   = params.pin_rst,
        direction = 0,
        w         = params.w,
        h         = params.h,
    }
    local r = lcd.init("custom", spi_params)
    if not r then
        log.error("lcd_display_rgb", "lcd.init SPI 通道失败")
        return
    end
    -- 发送 IC 寄存器序列
    if type(params.ic_init) == "function" then
        params.ic_init(params)
        log.info("lcd_display_rgb", "SPI IC 初始化完成")
    end
end

function M.init(params)
    if params.pin_pwr then
        gpio.setup(params.pin_pwr, 1)
        gpio.set(params.pin_pwr, 1)
    end
    if params.pin_bl then
        gpio.setup(params.pin_bl, 1)
        gpio.set(params.pin_bl, 1)
    end

    if rtos.bsp() == "PC" then
        log.info("lcd_display_rgb", "PC sim skip display.init")
        return true
    end

    if not display or not display.init then
        log.error("lcd_display_rgb", "display 模块不存在，请使用带 LUAT_USE_DISPLAY 的固件")
        return false
    end

    -- 可选：SPI IC 初始化（在 display.init 之前完成 IC 寄存器配置）
    spi_ic_init(params)

    local cfg = {
        id = 0,
        interface = params.interface or "rgb",
        w = params.w,
        h = params.h,
        hbp = params.hbp,
        hspw = params.hspw,
        hfp = params.hfp,
        vbp = params.vbp,
        vspw = params.vspw,
        vfp = params.vfp,
        pclk_hz = params.pclk_hz or params.bus_speed,
        pin_rst = params.pin_rst,
        pin_bl = params.pin_bl or params.pin_pwr,
        pin_pwr = params.pin_pwr,
    }

    local r, err = display.init("custom", cfg)
    log.info("lcd_display_rgb", "display.init", r, err)
    if r then
        local addr, fb_size, fb_count = display.getFbInfo()
        log.info("lcd_display_rgb", "getFbInfo", addr, fb_size, fb_count)
    end
    return r
end

return M
