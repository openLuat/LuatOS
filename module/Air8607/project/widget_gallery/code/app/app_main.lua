--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚配置
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + hzfont 矢量字库 + 旋转
4、ui_main.build() 搭建橱窗界面（顶栏 HUD + 组件舞台 + 分组切换栏）
5、touch_init()    GT911 初始化 + airui 绑定（必须早于动画任务）
6、ui_main.run()   30fps 主循环（默认进「仪表」组，自动轮播可关）
7、backlight_on()  界面就绪后点亮背光，防花屏
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
    -- 界面用到的字号一次载齐：11/13/16/22/30/48/64（与 theme.font_sizes 一致）
    for _, sz in ipairs(T.font_sizes) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 2048, antialias = 1 })
    end

    --[[AirUI 内置性能统计
    HUD 上「FPS 29/28」的第二个数字来自 airui.debug()，它是 LVGL 真实的画面刷新率；
    第一个数字是本脚本的动画更新率。两者对比即可判断慢在哪：
      计算耗时高 + 两个 FPS 都低 -> 脚本侧吃亏
      计算耗时低 + LVGL FPS 低    -> 渲染/刷屏侧吃亏
    定位完可以改成 airui.debug(false) 减少串口输出。]]
    airui.debug(true)

    ui_main.build()

    -- 触摸必须早于动画任务绑定：
    -- 先起动画再绑定时，动画任务会抢在绑定完成前就开始每帧 set_items，
    -- 触摸绑定与 LVGL 重绘在启动期撞在一起，表现为"日志说初始化完成但点不动"。
    touch_init()

    sys.taskInit(function()
        ui_main.run()
    end)

    backlight_on()
    log.info("app_main", "大屏组件橱窗已就绪，airui 版本 " .. tostring(airui.version()))
end)
