--[[
@module  app_main
@summary DIGITAL TWIN - 应用主入口：硬件初始化 + 启动编排
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚配置
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + hzfont 矢量字库 + 旋转
4、ui_main.build() 搭大屏（场景底图 + 六张玻璃面板 + 三维全息层 + 底栏）
5、touch_init()    GT911 初始化 + airui 绑定（必须早于动画任务）
6、ui_main.run()   30fps 主循环（默认进「孪生总览」，9 秒自动轮播）
7、backlight_on()  界面就绪后点亮背光，防花屏
]]

local T = require "theme"
local exd = require "exd_air8607_rgb"
local ui_main = require "ui_main"

local SCREEN_W, SCREEN_H = T.screen.w, T.screen.h

--[[PC 模拟器没有真实引脚
pwm / gpio 在 PC 上只是空实现，但 i2c.setup 会去加载 CH347 的 USB 驱动，
驱动在设备状态不稳时会直接把进程打崩（ACCESS_VIOLATION 0xC0000005）。
所以整段板级上电在 PC 上直接跳过——和 exd_air8607_rgb 里的处理一致。]]
local IS_PC = (rtos and rtos.bsp and rtos.bsp() == "PC")

-- ==================== 供电与背光 ====================
local function power_on()
    if IS_PC then return end
    -- 背光先关：UI 搭好再点亮，避免上电花屏
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    gpio.setup(17, 0)     -- LCD 供电使能（低有效）
    gpio.setup(15, 1)     -- 显示使能 / 复位脚
    i2c.setup(1, i2c.FAST)
    sys.wait(100)
end

local function backlight_on()
    if IS_PC then return end
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
    --[[界面用到的字号一次载齐（与 theme.font_sizes 一致）
    cache_size 从 2048 降到 512：整屏只有几百个不同汉字，2048 字形 × 6 个字号
    在真机上要吃掉 MB 级内存，而真机 LVGL 堆总共才 12MB（日志：内存使用 5827KB）。]]
    for _, sz in ipairs(T.font_sizes) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 512, antialias = 1 })
    end

    -- HUD 上「FPS 29/28」第二个数来自 airui.debug()，是 LVGL 真实刷新率
    airui.debug(true)

    ui_main.build()

    -- 触摸必须早于动画任务绑定，否则启动期与 LVGL 重绘撞车
    touch_init()

    sys.taskInit(function()
        ui_main.run()
    end)

    backlight_on()
    log.info("app_main", "数字孪生车间大屏已就绪，airui 版本 " .. tostring(airui.version()))
end)
