--[[
@module  lcd_tp
@summary 显示 + 触摸 + AirUI 初始化模块（按 conf.lua 的板型 profile 执行）
@version 1.0
@date    2026.11.11
@author  谌程
@usage
-- 本文件负责 U盘FOTA升级(有UI版) 的全部硬件初始化，对外接口2个：
-- 1. lcd_tp.init()        : 上电时序 -> 显示初始化 -> AirUI -> 字体 -> 触摸，成功返回true
-- 2. lcd_tp.backlight_on(): 点亮背光（界面画好后再调用，避免上电花屏/残影）
--
-- 初始化顺序即依赖关系（与 factory 工程、play_hzv_sd demo 一致）：
--   供电轨 -> 背光压灭(PWM 0占空比) -> display.init(RGB时序) -> 整屏刷黑 ->
--   airui.init -> hzfont逐字号加载 -> I2C轮询模式 -> tp.init(GT911) -> airui绑定触摸
]]

local conf = require "conf"
local S = conf.screen
local T = conf.touch

local M = {}

-- 生效的屏幕分辨率（display.init 之后以 getSize 返回值为准）
local scr_w, scr_h = S.w, S.h
local backlight_is_on = false

-- ==================== 上电时序 ====================
local function power_on()
    -- 屏供电使能脚（8603/8605 无独立屏供电脚, profile 里恒为 nil, 字段保留以备扩展）
    if S.pin_pwr then
        gpio.setup(S.pin_pwr, S.pin_pwr_low and 0 or 1)
    end

    -- 供电轨按 profile 顺序上电（顺序即依赖，来自各板 factory 实测配置）
    for _, item in ipairs(conf.power_on or {}) do
        gpio.setup(item.pin, item.level)
        if item.delay then
            sys.wait(item.delay)
        end
    end

    -- 背光先压到最暗：PWM 通道输出有效但占空比为0，UI 画好首帧前保持熄灭
    pwm.setup(S.backlight.pwm_ch, S.backlight.freq, 0)
    pwm.start(S.backlight.pwm_ch)

    -- 触摸 I2C 用轮询模式(第3参true)：中断驱动I2C与嵌套中断相互干扰时会"仅触摸时报错"，
    -- 轮询模式根治；触摸带宽极小，性能无感（factory tp_gt911.lua 实测结论）
    pcall(i2c.setup, T.port, 0, true)

    sys.wait(100)
end

-- ==================== 初始化 ====================
function M.init()
    power_on()

    -- 显示初始化（RGB 1024x600 时序参数来自各板 factory 实测组）
    if not display or not display.init then
        log.error("lcd_tp", "固件不支持 display 库, 请烧录带 LUAT_USE_DISPLAY 的固件")
        return false
    end
    local ok, err = display.init("custom", {
        id        = 0,
        interface = "rgb",
        w         = S.w,
        h         = S.h,
        hbp       = S.rgb.hbp,
        hspw      = S.rgb.hspw,
        hfp       = S.rgb.hfp,
        vbp       = S.rgb.vbp,
        vspw      = S.rgb.vspw,
        vfp       = S.rgb.vfp,
        pclk_hz   = S.rgb.pclk_hz,
        pin_rst   = S.pin_rst,
    })
    if not ok then
        log.error("lcd_tp", "display.init 失败", err)
        return false
    end
    -- display 内部可能按屏的实际能力调整分辨率，以返回值为准
    if display.getSize then
        local w, h = display.getSize()
        if w and w > 0 and h and h > 0 then
            scr_w, scr_h = w, h
        end
    end
    log.info("lcd_tp", "显示初始化成功", scr_w .. "x" .. scr_h)

    -- 整屏刷黑，清掉上电时显存里的随机内容
    if display.fill then
        display.fill(0, 0, scr_w, scr_h, 0x0000)
    end

    -- AirUI 初始化
    if not airui or not airui.init then
        log.error("lcd_tp", "固件不支持 AirUI, 请烧录带 LUAT_USE_AIRUI 的固件")
        return false
    end
    if not airui.init(scr_w, scr_h) then
        log.error("lcd_tp", "airui.init 失败")
        return false
    end
    airui.set_rotation(0)

    -- 界面用到的字号必须逐个加载，漏了不会报错，只会渲染出方框
    for _, sz in ipairs(conf.font_sizes) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 1024, antialias = 1 })
    end
    log.info("lcd_tp", "中文字库加载完成", "字号: " .. table.concat(conf.font_sizes, "/"))

    -- 触摸初始化（GT911，I2C1）
    -- 8603 批次差异: TP_RST 有 GPIO14 / GPIO72 两种(eng_8603x头注释与hw.tp不一致, 见conf注意1),
    -- W 板实测出现过 14 无应答的情况 —— 两个复位脚依次自动探测, 谁应答用谁
    local rst_pins = { T.pin_rst }
    if T.pin_rst ~= 72 then table.insert(rst_pins, 72) end
    if T.pin_rst ~= 14 then table.insert(rst_pins, 14) end
    local dev = nil
    for _, rst in ipairs(rst_pins) do
        dev = tp.init("gt911", {
            port     = T.port,
            pin_rst  = rst,
            pin_int  = T.pin_int,
            int_type = tp.FALLING,
            w        = scr_w,
            h        = scr_h,
        })
        if dev then
            log.info("lcd_tp", "GT911 触摸初始化成功", "TP_RST=GPIO" .. rst)
            break
        end
        log.warn("lcd_tp", "GT911 在 TP_RST=GPIO" .. rst .. " 上无应答, 换下一复位脚重试")
    end
    if dev then
        airui.device_bind_touch(dev)
        log.info("lcd_tp", "GT911 触摸已绑定 airui")
    else
        log.error("lcd_tp", "触摸初始化失败(两种复位脚均无应答): 查FPC排线/触摸型号/TP供电, 升级流程不受影响")
    end

    return true
end

-- ==================== 点亮背光 ====================
function M.backlight_on()
    if backlight_is_on then
        return
    end
    pwm.setup(S.backlight.pwm_ch, S.backlight.freq, S.backlight.duty)
    pwm.start(S.backlight.pwm_ch)
    backlight_is_on = true
    log.info("lcd_tp", "背光已点亮", "PWM通道" .. S.backlight.pwm_ch)
end

-- ==================== 查询屏幕分辨率 ====================
function M.get_size()
    return scr_w, scr_h
end

return M
