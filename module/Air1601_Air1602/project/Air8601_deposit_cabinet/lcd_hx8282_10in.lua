--[[
@module  hx8282
@summary HX8282 RGB 5/7/10.1寸 1024×600 通用屏幕驱动（display 库版）
@version 3.0
@date    2026.05.25
@author  江访
]]
local M = {}

-- ★ 必须保留：把 PIN43 复用成 GPIO13
-- Air8601 的背光驱动脚就是 PIN43（默认不是 GPIO 功能），hardware.lua 的 power_on 里
-- { pin = 43, level = 1 } 依赖这行复用才会真正作用到引脚上，否则 gpio.set(43,1) 无效 -> 白屏。
pins.setup(43, "GPIO13")

function M.init(params)
    if params.pin_pwr then
        gpio.setup(params.pin_pwr, 0)
        gpio.set(params.pin_pwr, 1)
    end

    if not display or not display.init then
        log.error("lcd_hx8282_10in", "display 模块不存在，请使用带 LUAT_USE_DISPLAY 的固件")
        return false
    end

    -- 构建 display.init 配置（AirUI 取默认屏 luat_display_get_by_id(0)，必须显式 id = 0）
    -- 说明：display.init 接收 RGB 时序 + 引脚；原 lcd.init 的 pin_de / direction 不在其列，
    --       HX8282 为四合一 IC，无需 SPI 寄存器初始化序列，也不需要 DE 引脚配置。
    local cfg = {
        id        = 0,
        interface = params.interface or "rgb",
        w         = params.w,
        h         = params.h,
        hbp       = params.hbp,
        hspw      = params.hspw,
        hfp       = params.hfp,
        vbp       = params.vbp,
        vspw      = params.vspw,
        vfp       = params.vfp,
        pclk_hz   = params.pclk_hz or params.bus_speed,
        pin_rst   = params.pin_rst,
        -- pin_bl / pin_pwr 不透传给 display.init：LCD 供电脚已在本函数开头的 Lua 前导里
        -- 用 gpio 拉高（与原 lcd 路径一致），参考工程 factory_new 的 eng_8601_7i_v0 也不传，
        -- 避免 display 库把它当电源脚重做时序 —— 8601 上 GPIO57 是 WIFI_EN，翻转会误动外设。
    }

    local r, err = display.init("custom", cfg)
    log.info("lcd_hx8282_10in", "display.init", r, err)
    if r and display.getFbInfo then
        local addr, fb_size, fb_count = display.getFbInfo()
        log.info("lcd_hx8282_10in", "getFbInfo", addr, fb_size, fb_count)
    end
    return r
end

return M
