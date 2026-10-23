--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排 + 动画任务
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()      —— 供电 / 背光 PWM3 占空比 0 / I2C 引脚配置；
2、exd.setup()     —— 显示初始化（复位 + RGB 时序 + 帧缓冲）；
3、airui.init()    —— 分辨率 + 字体 + 旋转 + 性能统计；
4、ui_main.build() —— 搭整屏：极光背景 + HUD + 舞台 + 4 个页面 + Dock；
5、touch_init()    —— GT911 触摸初始化 + airui 绑定（必须早于动画任务）；
6、ui_main.run()   —— 启动逐帧动画任务（33ms / 约 30fps），backlight_on() 点亮背光。
]]

-- 10 寸 RGB 显示 IC 初始化扩展库（与 airui_showcase / agri_greenhouse 共用同一份实现）
local exd = require "exd_air8607_rgb"
-- UI 主入口
local ui = require "ui_main"

local SCREEN_W, SCREEN_H = 1024, 600

-- ==================== 供电与背光 ====================
local function power_on()
    -- 背光 PWM3 上电占空比 0：UI 就绪后再点亮，避免花屏
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    -- LCD 供电使能（低有效，先关闭）
    gpio.setup(17, 0)
    -- LCD 显示使能 / 复位脚拉高
    gpio.setup(15, 1)
    -- GT911 触摸 I2C1 总线（400kHz，与已验证工程一致）
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

--[[GT911 触摸初始化 + airui 绑定
必须放在动画任务之前：如果先起逐帧刷新任务，触摸绑定会和 LVGL 重绘
在启动期撞在一起，表现为"日志说初始化完成但点不动"。
w/h 必须给，缺了会让 input 适配器以 EINVAL 静默拒绝。
]]
local function touch_init()
    local dev = tp.init("gt911", {
        port = 1,             -- I2C1
        pin_rst = 14,         -- TP_RESET
        pin_int = 51,         -- TP_INT
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
    -- 1、供电与引脚
    power_on()

    -- 2、显示初始化
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("app_main", "显示初始化失败", info)
        return
    end
    log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、AirUI 初始化（hzfont 矢量字库，12-255 任意字号）
    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    airui.font_load({ type = "hzfont", size = 16, cache_size = 2048, antialias = 1 })
    -- 打开内置性能统计：HUD 上 FPS 后面的 "LVxx" 就是 LVGL 真实画面刷新率，
    -- 与前面的脚本帧率对比即可判断瓶颈在脚本侧还是渲染侧
    airui.debug(true)

    -- 4、搭整屏
    ui.build()

    -- 5、触摸绑定（早于动画任务）
    touch_init()

    -- 6、逐帧动画任务
    sys.taskInit(function()
        ui.run()
    end)

    -- 7、点亮背光
    backlight_on()
    log.info("app_main", "AURORA UI 已就绪，airui 版本 " .. tostring(airui.version()))
end)
