--[[
@module  app_main
@summary 今天吃什么 - 应用主入口：硬件初始化 + 启动编排
@version 1.0
@date    2026.10.26
@board   Air8607(Air1603) + 10 寸 RGB 1024x600 免序列屏 + GT911 电容触摸
         引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17（低有效）
           背光 PWM3 (GPIO13)      触摸 I2C1  pin_rst = 14  pin_int = 51
@usage
require 即执行，启动顺序（和 widget_gallery 同款，先关背光再点亮，避免上电花屏）：
1、power_on()        背光 PWM3 占空比 0 / LCD 供电与使能 / I2C 引脚
2、exd.setup()       显示初始化（RGB 时序 + 帧缓冲，display 优先 lcd 兜底）
3、airui.init()      分辨率 + 旋转
4、font_load()       按 ui_theme.font_sizes 逐个载入 hzfont 字号
5、foods.check()     菜品条数自检（少一条就报警，避免界面静默错位）
6、ui_main.build()   搭界面（默认进减脂餐页，另两页懒加载）
7、touch_init()      GT911 初始化 + airui 绑定（必须早于动画任务）
8、backlight_on()    界面就绪后点亮背光

PC 模拟器（非 GUI 版）没有 airui，这里只打日志 + 跑数据自检后返回，
方便用现成的 luatos-lua.exe 做纯逻辑校验而不崩。
]]

local T = require "ui_theme"
local F = require "foods"
local D = require "ui_draw"
local exd = require "exd_air8607_rgb"

local SCREEN_W, SCREEN_H = T.screen.w, T.screen.h
local BACKLIGHT_DUTY = 92   -- PWM3 占空比，0~100

local function is_pc()
    return rtos and rtos.bsp and rtos.bsp() == "PC"
end

-- ==================== 供电与背光 ====================
-- 背光先关：UI 搭好再点亮，避免上电花屏
local function power_on()
    if is_pc() then return end
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    gpio.setup(17, 0)     -- LCD 供电使能（低有效）
    gpio.setup(15, 1)     -- 显示使能 / 复位脚
    i2c.setup(1, i2c.FAST)
    sys.wait(100)
end

local function backlight_on()
    if is_pc() then return end
    if pwm.setup(3, 1000, BACKLIGHT_DUTY) then
        pwm.start(3)
        log.info("app_main", "背光已点亮", BACKLIGHT_DUTY)
    else
        log.error("app_main", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

--[[GT911 触摸初始化
w/h 必须给：缺了会让 input 适配器以 EINVAL 静默拒绝，
表现为「日志说初始化完成但点不动」。]]
local function touch_init()
    if is_pc() then return false end
    local dev = tp.init("gt911", {
        port = 1,
        pin_rst = 14,
        pin_int = 51,
        int_type = tp.FALLING,
        w = SCREEN_W,
        h = SCREEN_H,
    })
    if dev then
        airui.device_bind_touch(dev)
        log.info("app_main", "GT911 触摸初始化完成")
        return true
    end
    log.error("app_main", "触摸初始化失败")
    return false
end

-- ==================== 字库 ====================
--[[按 ui_theme.font_sizes 逐个把字号建出来（label 只给 font_size 时会按需创建，
--预建一遍可以避免第一次渲染某个字号时卡一下）。
--cache_size 是「点阵缓存条数」：界面里同时出现的字形不多，192 条足够，
--调大只会多占内存；只有 global 那一档会替换全局默认字体，其余走 local 即可。]]
local function font_load()
    local ok = true
    for _, sz in ipairs(T.font_sizes) do
        local ret = airui.font_load({
            type = "hzfont", size = sz, cache_size = 192, antialias = 1,
            global = (sz == T.f.recipe),
        })
        if not ret then
            ok = false
            log.error("app_main", "字号载入失败", sz)
        end
    end
    log.info("app_main", "字库就绪", #T.font_sizes, "个字号")
    return ok
end

-- ==================== 主任务 ====================
sys.taskInit(function()
    -- 数据自检放最前面：就算没有屏幕也能在串口里看到数据对不对
    F.check()

    if not (airui and airui.init) then
        log.error("app_main", "固件缺少 airui 核心库（PC 非 GUI 模拟器属正常），本次只校验数据")
        return
    end

    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("app_main", "显示初始化失败", info)
        return
    end
    log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)

    if not airui.init(SCREEN_W, SCREEN_H) then
        log.error("app_main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)
    local okfont = font_load()

    D.seed()

    require("ui_main").build()
    touch_init()
    backlight_on()

    log.info("app_main", "今天吃什么已就绪", "airui", tostring(airui.version()),
        "屏幕", SCREEN_W .. "x" .. SCREEN_H, "字库", okfont and "ok" or "partial")
end)
