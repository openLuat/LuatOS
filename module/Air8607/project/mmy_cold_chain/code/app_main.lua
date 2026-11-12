--[[
@module  app_main
@summary 冷链温控中枢 - 应用入口（硬件初始化 + 启动编排）
@version 1.0
@date    2026.11.08
@board   Air8607 + 10 寸 1024x600 RGB 屏 + GT911 触摸

require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()   —— 背光 PWM3 先给 0、LCD 供电使能、I2C1（触摸用）；
2、exd.setup()  —— 显示初始化（复位 + RGB 时序 + 帧缓冲）；
3、airui 初始化 —— init + hzfont 字体加载（必须给 cache_size，否则中文渲染掉字）；
4、ui.build()   —— 数据引擎 + 整块面板；
5、touch_init() —— GT911 绑定（必须早于主循环，否则前几百毫秒点不动）；
6、backlight_on() —— 首帧画完再点亮背光，用户看到的是"直接亮起"；
7、voice.init()  —— 语音后端探测（独立任务，失败不影响面板）。

=== 上电顺序为什么这么排 ===
背光必须在电源与显示都稳定之后才给：先亮背光再折腾 RGB 时序，会在屏上留下
一段白屏或雪花，现场装到柜子上以后没人会去复位，这个印象会留很久。
]]

local exd = require "exd_air8607_rgb"
local ui = require "ui_main"
local voice = require "voice"

local SCREEN_W, SCREEN_H = 1024, 600

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

    -- 注意：失败时第二个返回值是错误字符串，成功时才是参数表，所以判空后再取字段
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("app_main", "显示初始化失败", info)
        return
    end
    if type(info) ~= "table" then info = {} end
    log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)

    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    -- hzfont 是矢量字库：给一个基准字号 + 足够大的字形缓存，
    -- 本工程用到 12~28 共 6 档字号，缓存给小了会频繁重建字形
    airui.font_load({ type = "hzfont", size = 16, cache_size = 4096, antialias = 1 })

    ui.build()

    touch_init()

    sys.taskInit(function()
        ui.run()
    end)

    -- 首帧画完再开背光
    sys.wait(220)
    backlight_on()
    log.info("app_main", "冷链温控中枢已就绪，airui 版本 " .. tostring(airui.version()))

    -- 语音单独一个任务：探测后端 + 配 DAC/PA 要 wait 几十毫秒，放主流程里会拖慢首帧
    sys.taskInit(function()
        sys.wait(400)
        if not voice.init() then
            log.warn("app_main", "无语音能力，面板按静音模式运行（右下角会标出来）")
        end
    end)
end)
