--[[
@module  app_main
@summary 应用主入口：板级初始化 + 启动编排
@version 1.0
@date    2026.11.03
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚配置
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + hzfont 矢量字库 + 旋转
4、ui_main.build() 搭大厅骨架
5、touch_init()    GT911 初始化 + airui 绑定（必须早于动画任务）
6、ui_main.run()   30fps 主循环
7、backlight_on()  界面就绪后点亮背光，防花屏
@note
触摸必须早于动画任务绑定：先起动画再绑定，动画任务会抢在绑定完成前就开始每帧 set_items，
触摸绑定与 LVGL 重绘在启动期撞在一起，表现为"日志说初始化完成但点不动"。
]]

local T = require "theme"
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

--[[GT911 触摸初始化
w / h 必须给：缺了会让 input 适配器以 EINVAL 静默拒绝，
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
    -- 界面用到的字号一次载齐（与 theme.font_sizes 一致）
    for _, sz in ipairs(T.font_sizes) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 2048, antialias = 1 })
    end

    -- 开局随机数种子：不固定，保证每局出题不同
    local seed = os.time()
    if mcu and mcu.ticks then seed = seed + mcu.ticks() end
    pcall(math.randomseed, seed)

    ui_main.build()

    -- 触摸绑定必须早于动画任务（见文件头 note）
    touch_init()

    sys.taskInit(function()
        ui_main.run()
    end)

    backlight_on()
    log.info("app_main", "益智乐园已就绪，airui 版本 " .. tostring(airui.version()))
end)
