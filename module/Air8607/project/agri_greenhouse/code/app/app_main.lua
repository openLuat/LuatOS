--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 业务模块加载 + 启动编排
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、加载业务模块 mock_data（传感器模拟数据源）；
2、power_on()   —— 供电/背光 PWM3 占空比 0/I2C 引脚配置；
3、exd.setup()  —— 显示初始化（扩展库：复位 + RGB 时序 + 帧缓冲）；
4、airui 初始化 —— init + 字体加载 + 旋转；
5、ui_main.build() 进入大屏 UI 界面，touch_init() 触摸绑定，backlight_on() 点亮背光；
6、时钟每秒刷新、传感器数据每 5 秒模拟刷新（定时器在模块加载时启动）。
]]

-- 业务模块加载：传感器模拟数据源
local data = require "mock_data"
-- 加载 10寸 RGB 显示IC初始化扩展库
local exd = require "exd_air8607_rgb"
-- UI 主入口
local ui = require "ui_main"

local SCREEN_W, SCREEN_H = 1024, 600

-- 供电、背光 PWM3 上电占空比 0 与 I2C 引脚配置
local function power_on()
    -- 背光 PWM3 上电占空比 0（UI 就绪后再点亮，防花屏）
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    -- LCD 供电使能（低有效，先关闭）
    gpio.setup(17, 0)
    -- LCD 显示使能/复位脚拉高
    gpio.setup(15, 1)
    -- GT911 触摸 I2C1 总线
    i2c.setup(1, i2c.FAST)
    sys.wait(100)   -- 等供电稳定
end

-- 背光点亮（PWM3 调光）
local function backlight_on()
    if pwm.setup(3, 1000, 100) then
        pwm.start(3)
        log.info("app_main", "背光已点亮")
    else
        log.error("app_main", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

-- GT911 触摸初始化 + airui 绑定（绑定后 UI 按钮即可点击）
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

-- 大屏主任务：初始化显示与触摸后进入 UI 界面
sys.taskInit(function()
    -- 1、供电与引脚配置
    power_on()

    -- 2、显示初始化（扩展库仅做显示IC初始化：复位 + RGB 时序 + 帧缓冲）
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("app_main", "显示初始化失败", info)
        return
    end
    log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、AirUI 初始化：分辨率 + 字体 + 旋转
    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    airui.font_load({ type = "hzfont", size = 16, cache_size = 2048, antialias = 1 })

    -- 4、进入大屏 UI 界面
    ui.build()
    ui.tick_clock()

    -- 5、触摸初始化 + airui 绑定
    touch_init()

    -- 6、界面就绪后点亮背光
    backlight_on()
    log.info("app_main", "农业大棚智能控制大屏已就绪")
end)

-- 时钟每秒刷新
sys.timerLoopStart(function()
    ui.tick_clock()
end, 1000)

-- 传感器数据模拟刷新（真机替换为真实采集回调后调用 ui.refresh_all 即可）
sys.timerLoopStart(function()
    data.simulate()
    ui.refresh_all()
end, 5000)
