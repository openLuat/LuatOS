--[[
@module main
@summary 天气预报大屏 - AirUI 工程（合宙 Engine Air8603，10寸 1024×600 RGB 屏）
@version 1.0.0
@usage
参考 Windows 11 天气应用（深色版）设计，见同目录 preview.html（浏览器 1:1 预览稿）。
两个页面：当前天气（城市切换/日期切换/概览-降水-风速图表）/ 天气详细信息（12 张指标卡）。
数据为虚拟模拟数据（mock.lua），1.5 秒刷新一次。
工程不使用任何 PNG 贴图（规避单 IDAT / 图片预缩放两个实机坑）。

=== Air8603 屏幕点亮链路（与智慧农场工程一致，官方工厂固件实测参数）===
1. 供电轨上电：5V_EN=GPIO12 / 9V_EN=GPIO56 / 12V_EN=GPIO44 / 5VOUT_EN=GPIO52
2. display.init("custom", {...})：RGB 时序 1024×600 @50MHz
   时序 hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12；LCD_DISP(pin_rst)=GPIO15
3. airui.init(1024, 600)：LVGL 引擎启动（必须先于任何控件创建和 font_load！）
4. 首帧上屏后开背光：PWM3 @1kHz 占空比 100（提前开会闪屏）
5. airui.font_load：矢量字库（必须在 airui.init 之后调用，否则总线错误死机）
6. tp.init：GT911 触摸 I2C1（TP_RST=GPIO14，TP_INT=GPIO51）
]]

PROJECT = "smart_weather_ui"
VERSION = "1.0.0"

local sys   = require "sys"
local exwin = require "exwin"

local theme = require "theme"

-- 加载页面模块（双页版：页面1当前天气 / 页面2详细信息，顶栏按钮切换；
-- 12 张详情卡不再挂在主页面长滚动里，滑动控件数减半）
require "page_weather"

-- Air8603 10寸 1024×600 RGB 屏配置（官方工厂固件实测参数）
local SCREEN_W, SCREEN_H = 1024, 600

sys.taskInit(function()
    log.info("main", "boot start")

    -- 1. 底板供电轨上电（屏和背光都挂在这几路电源上）
    pcall(gpio.setup, 12, 1)  -- 5V_EN
    pcall(gpio.setup, 56, 1)  -- 9V_EN
    sys.wait(100)             -- 等 9V 轨就绪
    pcall(gpio.setup, 44, 1)  -- 12V_EN
    pcall(gpio.setup, 52, 1)  -- 5VOUT_EN
    log.info("main", "power rails on")

    -- 2. RGB 屏硬件初始化（FrameBuffer 分配 + RGB 时序 + 显示使能脚复位）
    local ok, err = pcall(display.init, "custom", {
        id        = 0,
        interface = "rgb",
        pin_rst   = 15,               -- LCD_DISP = PIN80 = GPIO15
        w         = SCREEN_W,
        h         = SCREEN_H,
        hbp = 140, hspw = 20, hfp = 160,
        vbp = 20,  vspw = 3,  vfp = 12,
        bus_speed = 50 * 1000 * 1000, -- RGB 总线时钟 50MHz
    })
    log.info("main", "display.init ok=" .. tostring(ok) .. " err=" .. tostring(err))

    -- 3. airui 引擎初始化（必须在任何控件创建 / font_load 之前）
    ok, err = pcall(airui.init, SCREEN_W, SCREEN_H)
    log.info("main", "airui.init ok=" .. tostring(ok) .. " err=" .. tostring(err))
    pcall(airui.set_rotation, 0)   -- 面板为横屏原生方向，无需旋转

    -- 4. 首帧上屏后开背光（PWM3 @1kHz，提前开会闪屏）
    sys.wait(100)
    local pok, pret = pcall(pwm.open, 3, 1000, 100)
    if not pok or pret == false then
        pcall(pwm.setup, 3, 1000, 100)
        pcall(pwm.start, 3)
    end
    log.info("main", "backlight pwm3: " .. tostring(pok) .. "/" .. tostring(pret))

    -- 5. 矢量字库（注意：必须在 airui.init 之后，否则总线错误死机）
    -- 踩坑：hzfont 的 cache_size 只允许 128/256/512/1024/2048，
    --       传 4096 会被静默回退成默认小缓存（512），滑动明显卡顿
    ok, err = pcall(airui.font_load, {
        type = "hzfont", size = 16, cache_size = 2048, antialias = 1 })
    if not ok then
        log.info("main", "font_load cache 2048 fail, retry 1024: " .. tostring(err))
        ok, err = pcall(airui.font_load, {
            type = "hzfont", size = 16, cache_size = 1024, antialias = 1 })
    end
    log.info("main", "font_load ok=" .. tostring(ok) .. " err=" .. tostring(err))

    -- 6. GT911 触摸初始化（I2C1）
    --    官方 demo 三步（缺一步按钮 on_click 都不会触发）：
    --    i2c.setup → tp.init("gt911", {...}) → airui.device_bind_touch(dev)
    pcall(i2c.setup, 1, i2c.SLOW)
    pcall(gpio.setup, 14, 0)   -- TP_RST 复位脉冲
    pcall(gpio.close, 14)
    local dev
    ok, dev = pcall(tp.init, "gt911", {
        port = 1, pin_rst = 14, pin_int = 51,
        int_type = 1, w = SCREEN_W, h = SCREEN_H })
    log.info("main", "tp.init ok=" .. tostring(ok) .. " dev=" .. tostring(dev))
    if dev then
        pcall(airui.device_bind_touch, dev)
        log.info("main", "touch bound to airui")
    else
        log.error("main", "touch init failed, page switching disabled")
    end

    -- 7. 打开第一个页面（出错时打日志+调用栈，避免直接崩溃重启）
    log.info("main", "open_page ...")
    ok, err = pcall(theme.open_page, 1)
    if not ok then
        log.error("main", "open_page failed: " .. tostring(err)
            .. "\n" .. tostring(debug.traceback()))
    end
    log.info("main", "boot done")
end)

-- 调度器：必须是 main.lua 的最后一行，否则 Lua VM 直接退出并重启
sys.run()
