--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排
@author  蒋骞
@version 1.0
@date    2026.10.30
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡
@usage
require 即执行：
1、power_on()      背光 PWM3 占空比 0、LCD 供电、SD_EN 上电、功放关断、I2C1 轮询模式
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + 旋转 + 中文字库
4、time_init()     RTC 基准年 + 时区 + 用固件编译日期校时（每次烧录 = 当天）
5、建界面          奶油色渐变底 + ui_main.build()
6、touch_init()    GT911 + airui 绑定
7、backlight.on()  界面就绪后点亮背光，防花屏
8、timerLoopStart  每秒检查跨天（ui_main.refresh）
@note PC 分支
rtos.bsp() == "PC" 时跳过全部硬件初始化（GPIO/PWM/I2C/显示/触摸/SD），
只跑界面与日期算法，方便先在电脑上验证再烧真机。
]]
local conf = require "conf"
local theme = require "theme"
local ui_main = require "ui_main"
local backlight = require "backlight"
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
    backlight.off()        -- 背光先关，界面搭好再点亮

    gpio.setup(17, 0)      -- LCD 供电使能（低有效，先关）
    gpio.setup(15, 1)      -- LCD_DISP
    gpio.setup(74, 1)      -- SD_EN 高电平供电
    gpio.setup(73, 0)      -- 功放 PA 关断（本工程不出声）

    -- GT911 触摸必须走轮询模式（第三参 true），中断模式会在触摸时丢点/报 I2C 错
    i2c.setup(1, 0, true)
    sys.wait(120)
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

-- ==================== RTC ====================
--[[必须在建界面之前跑：日历的「今天」、默认月份都取 os.date，
时间不对的话首屏就是错的月份。
rtc_util.calibrate() 会用固件编译日期（= 烧录当天）把 RTC 拉正。
]]
local function time_init()
    local m = rtc_util.init()
    rtc_util.calibrate()
    local t = rtc_util.now()
    log.info("app_main", "时间来源 =", m, "当前时间",
        t and string.format("%04d-%02d-%02d %02d:%02d:%02d",
            t.year, t.month, t.day, t.hour, t.min, t.sec) or "?")
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

    -- 校时要在建界面之前：日历首屏的「今天」直接取 os.date
    time_init()

    -- 根页面：奶油色竖向渐变（治愈风底色），再叠界面
    local page = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(page, 0, 0, SW, SH, C.bg1, C.bg2, 16)

    -- 搭界面（日历页 + 两个浮层 + 互相的回调）
    ui_main.build(page)
    -- 建好后立即刷一次：否则首屏要等 1 秒定时器才出日期
    ui_main.refresh()

    if not IS_PC then
        touch_init()
        local pct = backlight.on()
        log.info("app_main", "背光已点亮", pct and (pct .. "%") or "失败")
    end

    sys.timerLoopStart(ui_main.refresh, conf.tick_ms)

    log.info("app_main", "情绪日历已就绪", PROJECT, VERSION, os.date("%Y-%m-%d %H:%M:%S"))
end)
