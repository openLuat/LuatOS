--[[
@module  drv_lcd_rgb
@summary RGB 屏统一通过 display 库初始化（Air8603 10寸 1024×600）
@version 1.0.0
@date    2026.11.09

params 透传给 display.init("custom", ...)：
  w, h, hbp, hspw, hfp, vbp, vspw, vfp, pclk_hz / bus_speed, pin_rst, interface

pin_pwr / pin_bl 由 board.lua 的上电时序与 backlight_on 统一驱动，不透传给
display.init —— display.init 末尾会无条件拉高这两个脚，架空"首帧后再开背光"的时序。
]]
local M = {}

function M.init(params)
    if rtos.bsp() == "PC" then
        log.info("drv_lcd_rgb", "PC 模拟器跳过 display.init")
        return true
    end

    if not display or not display.init then
        log.error("drv_lcd_rgb", "display 模块不存在，请使用带 LUAT_USE_DISPLAY 的固件")
        return false
    end

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
    }

    local r, err = display.init("custom", cfg)
    log.info("drv_lcd_rgb", "display.init", r, err)
    if r then
        local addr, size, count = display.getFbInfo()
        log.info("drv_lcd_rgb", "getFbInfo", addr, size, count)
    end
    return r
end

return M
