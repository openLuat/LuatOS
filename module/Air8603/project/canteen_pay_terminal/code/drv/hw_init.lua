--[[
@module  hw_init
@summary 屏幕 / 触摸 / 中文字库 / 背光 / 供电 一次性初始化
@note    参考 module/Air8603/factory/drv/lcd/lcd_display_rgb.lua 与 lcd_common.lua
         参考 module/Air1601.../demo/ui/airui/{lcd_drv,tp_drv}.lua
         内含 sys.wait，必须在 sys.taskInit 的协程里调用
]]

local CFG = require "config"
local M = {}

function M.init()
    local hw = CFG.hw

    -- 1) 上电：5V 供电 + USB 摄像头供电（UVC_EN 拉高后等枚举）
    gpio.setup(hw.pwr_5v_en, 1)
    gpio.set(hw.pwr_5v_en, 1)
    gpio.setup(hw.uvc_en, 1)
    gpio.set(hw.uvc_en, 1)
    sys.wait(300)

    -- 2) RGB 屏：display.init("custom", ...) 分配帧缓冲并输出时序
    if display and display.init then
        local ok, err = display.init("custom", {
            id        = 0,
            interface = "rgb",
            w         = hw.screen_w,
            h         = hw.screen_h,
            hbp       = hw.hbp, hspw = hw.hspw, hfp = hw.hfp,
            vbp       = hw.vbp, vspw = hw.vspw, vfp = hw.vfp,
            pclk_hz   = hw.pclk_hz,
            pin_rst   = hw.lcd_rst,
        })
        log.info("hw_init", "display.init", ok, err)
    else
        log.error("hw_init", "固件缺少 display 库，屏幕不可用")
    end

    -- 3) AirUI 引擎 + 固件内置中文字库（Air8603 走内置字库，无需外部 ttf）
    --    size 是全局默认字号；label / button 传各自的 font_size 时，引擎会按需创建
    --    对应字号的 hzfont 实例（airui_font_hzfont_get_size），无需在这里预建。
    --    注意：控件字号字段必须叫 font_size，写成 size 会被忽略、退回 20px 小字。
    airui.init(hw.screen_w, hw.screen_h)
    airui.font_load({
        type       = "hzfont",
        size       = 20,
        cache_size = 1024,
        antialias  = 1,
    })

    -- 4) 背光 PWM3（首帧上屏后再点亮，避免残影闪屏）
    pwm.setup(hw.pwm_ch, hw.pwm_freq, hw.pwm_duty)
    pwm.start(hw.pwm_ch)

    -- 5) GT911 电容触摸，绑定到 AirUI 输入设备
    gpio.setup(hw.tp_rst, 0)
    gpio.close(hw.tp_rst)
    i2c.setup(hw.tp_port, i2c.SLOW)
    local tp_dev = tp.init("gt911", {
        port     = hw.tp_port,
        pin_rst  = hw.tp_rst,
        pin_int  = hw.tp_int,
        int_type = tp.FALLING or 1,
        w        = hw.screen_w,
        h        = hw.screen_h,
    })
    log.info("hw_init", "tp.init", tp_dev)
    if tp_dev then
        airui.device_bind_touch(tp_dev)
    else
        log.warn("hw_init", "触摸初始化失败，界面可显示但不可点击")
    end

    return true
end

return M
