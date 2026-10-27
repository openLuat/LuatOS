--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排
@author  王世豪
@version 1.0
@date    2026.10.26
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡
@usage
require 即执行：
1、power_on()      背光 PWM3 占空比 0、LCD 供电、SD_EN 上电、功放关断、I2C1 轮询模式
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + 旋转 + 中文字库
4、建界面          渐变背景 + 可选壁纸 + ui_main.build()
5、touch_init()    GT911 + airui 绑定
6、backlight_on()  界面就绪后点亮背光，防花屏
7、time_init()     RTC 基准年 + 时区
8、timerLoopStart  每秒刷新时钟（ui_main.refresh）
@note PC 分支
rtos.bsp() == "PC" 时跳过全部硬件初始化（GPIO/PWM/I2C/显示/触摸/SD），
只跑界面与日期算法，方便先在电脑上验证再烧真机。
]]
local conf = require "conf"
local theme = require "theme"
local ui_main = require "ui_main"
local wallpaper = require "wallpaper"
local settings = require "settings"
local rtc_util = require "rtc_util"

local SW, SH = conf.W, conf.H
local C = theme.C

-- PC 模拟器判定：用于跳过全部硬件初始化。
-- 把 bsp 的实际返回值打出来，换固件 / 换模拟器时能直接看到为什么判错。
local IS_PC = false
do
    local ok, bsp = pcall(function() return rtos.bsp() end)
    if ok and bsp == "PC" then IS_PC = true end
    log.info("app_main", "运行环境检测", "rtos.bsp() =", tostring(bsp), "=> IS_PC =", tostring(IS_PC))
end

-- ==================== 上电时序（仅真机）====================
local function power_on()
    -- 背光先给 0 占空比，界面搭好再点亮
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
    pwm.start(conf.backlight.pwm_ch)

    gpio.setup(17, 0)      -- LCD 供电使能（低有效，先关）
    gpio.setup(15, 1)      -- LCD_DISP
    gpio.setup(74, 1)      -- SD_EN 高电平供电
    gpio.setup(73, 0)      -- 功放 PA 关断（本工程不出声）

    -- GT911 触摸必须走轮询模式（第三参 true），中断模式会在触摸时丢点/报 I2C 错
    i2c.setup(1, 0, true)
    sys.wait(120)
end

-- ==================== RTC ====================
--[[时间初始化：设置 RTC 基准年与时区（见 drv/rtc_util.lua）]]
local function time_init()
    local m = rtc_util.init()
    local t = rtc_util.now()
    log.info("app_main", "校时方式 =", m, "当前时间",
        t and string.format("%04d-%02d-%02d %02d:%02d:%02d",
            t.year, t.month, t.day, t.hour, t.min, t.sec) or "?")
end

-- ==================== 触摸（仅真机）====================
local function touch_init()
    for attempt = 1, 2 do
        local dev = tp.init("gt911", {
            port = 1,
            pin_rst = 14,
            pin_int = 51,
            int_type = tp.FALLING,
            w = SW,
            h = SH,
        })
        if dev then
            airui.device_bind_touch(dev)
            log.info("app_main", "GT911 触摸初始化完成")
            return true
        end
        log.warn("app_main", "GT911 未成功，200ms 后重试", attempt)
        sys.wait(200)
    end
    log.error("app_main", "触摸初始化失败")
    return false
end

-- ==================== 主流程 ====================
sys.taskInit(function()
    if not IS_PC then power_on() end

    if not IS_PC then
        local exd = require "exd_air8607_rgb"
        local ok, info = exd.setup({ pin_rst = 15 })
        if not ok then
            log.error("app_main", "显示初始化失败", info)
            return
        end
        log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)
        if info.backend ~= "display" then
            log.warn("app_main", "固件缺少 display 核心库（当前走旧 lcd 后端）")
        end
    end

    if not airui.init(SW, SH) then
        log.error("app_main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)
    airui.font_load({
        type = "hzfont",
        size = conf.font.size,
        cache_size = conf.font.cache_size,
        antialias = conf.font.antialias,
    })

    -- 根页面：渐变底色，再叠壁纸（有卡才有），最后叠界面
    local page = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(page, 0, 0, SW, SH, C.bg1, C.bg2, 16)

    -- 壁纸必须在建 UI 之前创建：LVGL 里后创建的对象在上层，
    -- 晚于 UI 创建会把时钟文字整个盖住
    if not IS_PC then
        wallpaper.load(page)
    end

    -- 搭界面（时钟页 + 设置页 + 页面切换回调）
    ui_main.build(page)
    -- 建好后立即刷一次：否则首屏要等 1 秒定时器才出时间，
    -- 会有一瞬间停在默认值
    ui_main.refresh()

    if not IS_PC then
        touch_init()
        local b = settings.apply_brightness(settings.get_brightness())
        log.info("app_main", "背光已点亮", b and (b .. "%") or "失败")
    end

    time_init()
    sys.timerLoopStart(ui_main.refresh, conf.clock.tick_ms)

    log.info("app_main", "桌面时钟已就绪", PROJECT, VERSION, os.date("%Y-%m-%d %H:%M:%S"))
end)
