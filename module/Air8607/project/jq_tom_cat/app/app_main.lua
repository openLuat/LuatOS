--[[
@module  app_main
@summary 汤姆猫 - 应用主入口（硬件初始化 + 启动编排）
@version 1.0
@date    2026.10.25
@author  蒋骞

=== 启动顺序（顺序本身是需求） ===
1、power_on()      背光 PWM3 占空比先归零 / LCD 供电 / 复位脚 / I2C1 400kHz
2、exd.setup()     显示初始化：复位 + RGB 时序 + 帧缓冲（display 优先，lcd 兜底）
3、airui.init()    1024x600 + hzfont 字库 + 旋转 0
4、voice.init()    音频通路一次性 setup + 音量 + 保持上电（本地 TTS 就绪即点即说）
5、ui_main.build() 搭界面：静态层画一次，动态层出首帧
6、touch_init()    GT911 初始化 + AirUI 绑定（必须早于动画任务，否则点不动）
7、ui_main.run()   主循环（taskInit 起来，不阻塞后续）
8、backlight_on()  界面就绪后才点亮背光，防上电花屏

引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15      LCD 供电 pin_pwr = 17（低有效）
  背光 PWM3 (GPIO13)         GT911: I2C1 400kHz, pin_rst = 14, pin_int = 51
  喇叭 DAC + HT6873 功放（AUDIOPA_EN = GPIO73，由 voice.lua 交给 exaudio 管）
]]
local T = require "theme"
local exd = require "exd_air8607_rgb"
local voice = require "voice"
local ui_main = require "ui_main"

local SW, SH = T.screen.w, T.screen.h

local function is_pc()
    return rtos and rtos.bsp and rtos.bsp() == "PC"
end

-- ==================== 供电与背光 ====================
local function power_on()
    if is_pc() then return end
    -- 背光先关：界面搭好再点亮，避免上电花屏
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    gpio.setup(17, 0)     -- LCD 供电使能（低有效）
    gpio.setup(15, 1)     -- 显示使能 / 复位脚
    i2c.setup(1, i2c.FAST)
    sys.wait(100)
end

local function backlight_on()
    if is_pc() then return end
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
    if is_pc() then
        -- PC 模拟器用 SDL 鼠标事件，不需要 GT911
        log.info("app_main", "PC 模拟器，跳过触摸初始化")
        return true
    end
    if not (tp and tp.init) then
        log.error("app_main", "固件缺少 tp 库，触摸不可用")
        return false
    end
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
    log.error("app_main", "GT911 初始化失败，请核对触摸接线")
    return false
end

-- ==================== 主任务 ====================
sys.taskInit(function()
    local ok, err = pcall(function()
        power_on()

        local dok, info = exd.setup({ pin_rst = 15 })
        if not dok then
            error("显示初始化失败: " .. tostring(info))
        end
        log.info("app_main", "显示初始化完成", tostring(info.backend),
            tostring(info.w) .. "x" .. tostring(info.h))

        assert(airui and airui.init and airui.shape, "固件缺少 AirUI 核心库（LUAT_USE_AIRUI）")
        assert(airui.init(SW, SH), "airui.init 失败")
        airui.set_rotation(0)

        -- 界面用到的字号一次载齐（theme.fonts 是唯一事实来源）
        for _, sz in ipairs(T.fonts) do
            airui.font_load({ type = "hzfont", size = sz, cache_size = 2048, antialias = 1 })
        end

        voice.init()       -- 音频通路一次配好并保持上电（无 TTS 固件自动静音）
        ui_main.build()
        touch_init()       -- 必须早于动画任务绑定

        sys.taskInit(ui_main.run)
        backlight_on()

        log.info("app_main", "汤姆猫已就绪  airui " .. tostring(airui.version and airui.version()))
    end)
    if not ok then
        log.error("app_main", "启动失败", err)
        backlight_on()     -- 即使失败也点亮背光，方便看错误画面
    end
end)
