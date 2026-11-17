--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排
@version 1.0
@date    2026.11.17
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚配置
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + hzfont 矢量字库（一次载齐）+ 旋转
4、boot_logo()     开机画面（中心绿色闪电 + 品牌名）
5、ui_main.build() 搭建充放电终端界面
6、touch_init()    GT911 初始化 + airui 绑定（必须早于动画任务）
7、ui_main.run()   30fps 主循环
8、backlight_on()  界面就绪后点亮背光，防花屏
]]

local T = require "theme"
local fx = require "fx"
local exd = require "exd_air8607_rgb"
local ui_main = require "ui_main"

local SCREEN_W, SCREEN_H = T.screen.w, T.screen.h

-- ==================== 供电与背光 ====================
local function power_on()
    -- 背光先关：UI 搭好再点亮，避免上电花屏
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    gpio.setup(17, 0)     -- LCD 供电使能（低有效）
    gpio.setup(15, 1)     -- 显示使能 / 复位脚
    i2c.setup(1, i2c.FAST)
    sys.wait(100)
end

local function backlight_on()
    if pwm.setup(3, 1000, 100) then
        pwm.start(3)
        log.info("app_main", "背光已点亮")
    else
        log.error("app_main", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

-- ==================== 触摸 ====================
--[[GT911 触摸初始化
w/h 必须给：缺了会让 input 适配器以 EINVAL 静默拒绝，
表现为"日志说初始化完成但点不动"。]]
local function touch_init()
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

-- ==================== 开机画面 ====================
local function boot_logo()
    local root = airui.container({ x = 0, y = 0, w = SCREEN_W, h = SCREEN_H, color = T.c.bg })
    local cx, cy = 512, 280
    local P = fx.pool()
    -- 中心圆角方块
    P:box(cx - 56, cy - 56, 112, 112, T.c.panel, 255, 22)
    P:frame(cx - 56, cy - 56, 112, 112, T.c.line, 2, 255, 22)
    -- 绿色闪电折线（7 点闭合，尖角）
    local xs = { cx + 4, cx - 32, cx - 8, cx - 12, cx + 24, cx, cx + 4 }
    local ys = { cy - 40, cy + 8, cy + 8, cy + 40, cy - 8, cy - 8, cy - 40 }
    P:poly(xs, ys, 7, T.c.green, 4, 255, false)
    P:finish()
    airui.shape({ parent = root, x = 0, y = 0, w = SCREEN_W, h = SCREEN_H, items = P.items })

    T.label(root, 0, cy + 84, SCREEN_W, 26, "移动电源", 22, T.c.snow, T.CT)
    T.label(root, 0, cy + 116, SCREEN_W, 16, "POWERBANK 20000 MAH", 13, T.c.steel, T.CT)
    sys.wait(1100)
    root:destroy()
end

-- ==================== 主任务 ====================
sys.taskInit(function()
    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("app_main", "显示初始化失败", info)
        return
    end
    log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)

    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    -- 界面用到的字号一次载齐：16/18/22/26/40/64（与 theme.font_sizes 一致）
    for _, sz in ipairs(T.font_sizes) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 2048, antialias = 1 })
    end

    airui.debug(false)

    boot_logo()

    ui_main.build()

    -- 触摸必须早于动画任务绑定，否则启动期会撞在一起导致点不动
    touch_init()

    sys.taskInit(function()
        ui_main.run()
    end)

    backlight_on()
    log.info("app_main", "充放电终端已就绪，airui 版本 " .. tostring(airui.version()))
end)
