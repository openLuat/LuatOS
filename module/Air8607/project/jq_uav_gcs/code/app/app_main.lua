--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排
@version 1.0
@date    2026.11.02
@board  Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
        引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
          LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
          背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
require 即执行，顺序固定：
1、power_on()        供电 / 背光 PWM3 占空比 0 / I2C
2、exd.setup()       显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()      分辨率 + 旋转
4、font_load()       按 theme.font_sizes 逐个载入 hzfont
5、sim.init()        仿真状态机先就绪（界面构建时顶栏就要读它）
6、ui_main.build()   搭界面
7、touch_init()      GT911 + airui 绑定（必须早于动画任务）
8、ui_main.run()     30fps 主循环
9、backlight_on()    界面就绪后点亮背光，防花屏
@note
hzfont 必须按字号逐个 font_load：漏载的字号不会报错，只会渲染成方框。
]]
local exd = require "exd_air8607_rgb"
local T = require "theme"
local sim = require "sim"
local ui = require "ui_main"

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

local function font_load()
    for _, sz in ipairs(T.font_sizes) do
        local ok, ret = pcall(airui.font_load, {
            type = "hzfont", size = sz, cache_size = 512, antialias = 1,
        })
        if not ok or ret == false then
            log.warn("app_main", "字号加载失败", sz)
        end
    end
end

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
    font_load()

    -- 界面构建时顶栏就要读仿真状态，所以仿真先启动
    sim.init()

    airui.debug(true)
    ui.build()

    -- 触摸必须早于动画任务绑定
    touch_init()

    sys.taskInit(function()
        ui.run()
    end)

    -- 先让 LVGL 画完首帧再亮背光：用户看到的是"直接亮起"而不是先黑一下
    sys.wait(220)
    backlight_on()
    log.info("app_main", "UAV GCS 已就绪，airui 版本 " .. tostring(airui.version()))
end)
