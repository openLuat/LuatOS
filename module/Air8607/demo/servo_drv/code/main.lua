--[[
@module  main
@summary Air8607A 伺服「脉冲 + 方向」触摸屏手动控制（10.1 寸 1024x600）
@version 2.0
@date    2026.11.03
@board   Air8607A（Air1603）+ 10.1 寸 RGB 1024x600 + GT911 触摸

【功能】
  屏幕上手动控制：
    - 方向脚 GPIO9：直接输出高电平 / 低电平
    - 脉冲 PWM1(GPIO65)：固定 1kHz / 50%，脉冲个数由右侧键盘输入（0 = 连续输出），
      点击"PWM启动"按个数输出（pnum 由硬件计数，发满自停）；运行期间不允许再次启动，
      必须先点"PWM停止"（停止为 0% 占空比重配，不调 pwm.stop——它会释放引脚导致
      RGB 总线串出假脉冲）
    - 右侧实时显示频率、转速估算、已运行时间

【接线】6N137 光耦隔离模块（共阴极接法）
  Air8607A GND             → 模块 信号输入负
  Air8607A GPIO65(PWM1)    → 模块 信号输入1    模块 信号输出1 → 驱动器 PULSE-
  Air8607A GPIO9(SPI1_CLK) → 模块 信号输入2    模块 信号输出2 → 驱动器 SIGN-
  驱动器控制电源 +Vdc → 模块 信号电源正(输出侧)   0V/COM → 模块 供电电源负
  PULSE+ / SIGN+ 各串 2k 接 +Vdc；两侧电源不共地

【启动顺序】
  供电/背光压灭 → 显示初始化 → airui 初始化 + 字体 → servo_pulse 初始化 →
  搭界面 → 触摸初始化 → 状态刷新任务 → 点亮背光
]]
PROJECT = "servo_ui"
VERSION = "2.0.0"



local conf = require "conf"
local exd = require "exd_air8607_rgb"
local pulse = require "servo_pulse"
local ui = require "ui"

local S = conf.screen

-- ==================== 上电时序 ====================
local function power_on()
    -- 背光 PWM 先给 0 占空比，UI 就绪后再点亮，避免上电花屏
    log.info("main", string.format("call pwm.setup(%d, %d, %d) -- 背光: 通道, 频率Hz, 占空比%%",
        S.backlight_pwm, S.backlight_freq, 0))
    pwm.setup(S.backlight_pwm, S.backlight_freq, 0)
    log.info("main", string.format("call pwm.start(%d) -- 背光通道", S.backlight_pwm))
    pwm.start(S.backlight_pwm)

    gpio.setup(S.pin_pwr, 0)   -- LCD 供电使能（低有效）
    gpio.setup(S.pin_rst, 1)   -- LCD 复位/显示使能

    pcall(i2c.setup, 1, i2c.FAST) -- GT911 走 I2C1
    sys.wait(100)
end

local function backlight_on()
    log.info("main", string.format("call pwm.setup(%d, %d, %d) -- 背光: 通道, 频率Hz, 占空比%%",
        S.backlight_pwm, S.backlight_freq, S.backlight_duty))
    if pwm.setup(S.backlight_pwm, S.backlight_freq, S.backlight_duty) then
        log.info("main", string.format("call pwm.start(%d) -- 背光通道", S.backlight_pwm))
        pwm.start(S.backlight_pwm)
        log.info("main", "背光已点亮")
    else
        log.error("main", "背光 PWM 初始化失败，请确认 PWM 通道")
    end
end

-- ==================== 触摸 ====================
local function touch_init()
    local dev = tp.init("gt911", {
        port = S.tp.port,
        pin_rst = S.tp.pin_rst,
        pin_int = S.tp.pin_int,
        int_type = tp.FALLING,
        w = S.w,
        h = S.h,
    })
    if dev then
        airui.device_bind_touch(dev)
        log.info("main", "GT911 触摸初始化完成")
        return true
    end
    log.error("main", "触摸初始化失败，按钮将无法点击")
    return false
end

-- ==================== 主流程 ====================
sys.taskInit(function()
    power_on()

    -- 先把脉冲脚/方向脚压成确定的低电平，再做显示初始化：
    -- 显示一启动，50MHz 的 RGB 总线就是强干扰源，脉冲脚悬空时容易被串成假脉冲
    local okp, err = pcall(pulse.init)
    if not okp then
        log.error("main", "脉冲/方向初始化失败", tostring(err))
    end

    local ok, info = exd.setup({ pin_rst = S.pin_rst })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)
    if info.backend ~= "display" then
        log.warn("main", "固件缺少 display 核心库（当前走旧 lcd 后端），建议升级 Air1603 V1028")
    end

    if not airui.init(S.w, S.h) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(S.rotation or 0)
    -- 界面用到的字号必须逐个加载，漏了不会报错，只会渲染出方框
    for _, sz in ipairs(S.font_sizes) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 1024, antialias = 1 })
    end

    ui.build()
    touch_init()
    ui.run()

    backlight_on()
    log.info("main", "伺服手动控制界面已就绪")
end)



-- 加载 PWM 应用模块
-- require "pwm_app"

sys.run()
