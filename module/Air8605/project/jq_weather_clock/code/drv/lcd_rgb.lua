--[[
@module  lcd_rgb
@summary RGB 屏初始化（display.init 直出，不依赖 factory 的驱动框架）
@version 1.0
@date    2026.11.08

=== 为什么不用 lcd.init ===
10.1 寸 1024x600 是纯 RGB 时序屏（免序列四合一），AirUI 的真机后端优先挂 display 库；
display.init 会一次性完成 RGB 时序、FrameBuffer 分配与显示使能，
之后再 airui.init 就能直接拿到这块 FB。走旧 lcd 库反而要自己管 setupBuff/autoFlush。

=== 引脚策略 ===
pin_rst = GPIO15 是 LCD_DISP（显示使能），交给 display.init 内部做复位时序。
背光（PWM3）故意不在这里点亮：等首帧画面建好再开，避免 RGB 帧缓冲里的
残留内容闪一下（跨热复位时 FB 不清零）。
]]

local M = {}

function M.init(params)
    if rtos.bsp() == "PC" then
        log.info("lcd_rgb", "PC 模拟器，跳过 display.init")
        return true
    end

    if not display or not display.init then
        log.error("lcd_rgb", "固件缺少 display 库（需要 LUAT_USE_DISPLAY）")
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

    local ok, err = display.init("custom", cfg)
    log.info("lcd_rgb", "display.init", ok, err)
    if ok then
        local addr, size, count = display.getFbInfo()
        log.info("lcd_rgb", "fb", addr, size, count)
    end
    return ok
end

return M
