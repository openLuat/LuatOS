--[[
@module  conf
@summary Air8607A 伺服驱动器「脉冲 + 方向」触摸屏控制 —— 参数配置
@version 2.0
@date    2026.11.03
@board   Air8607A（主控 Air1603）+ 10.1 寸 RGB 1024x600 + GT911 触摸

本轮只做「手动控制」：屏幕上调占空比 / 脉冲周期 / 脉冲个数、点按钮起停，
方向脚直接在界面上输出高电平或低电平，不再自动跑测试流程，也不接 485。

硬件接线（中间加 6N137 四路光耦隔离模块，共阴极接法）：
  Air8607A GND             → 模块 信号输入负（共阴极参考地，GPIO 高电平点亮 LED）
  Air8607A GPIO65(PWM1)    → 模块 信号输入1         模块 信号输出1 → 驱动器 PULSE-
  Air8607A GPIO9(SPI1_CLK) → 模块 信号输入2         模块 信号输出2 → 驱动器 SIGN-
  驱动器控制电源 +Vdc → 模块 信号电源正(输出侧)     0V/COM → 模块 供电电源负
  PULSE+ / SIGN+ 各串 2k 电阻后接 +Vdc（2k 串在驱动器侧）
  ※ 输入侧只借 8607A 的 GND 做参考，不接 3.3V；输出侧用驱动器控制电源，两侧严禁共地

驱动器需要先确认的参数（面板设置）：
  Pn001 = 0      位置控制模式
  Pn006 = 0/1    位置模式方向取反
  Pn007 = 3      外部脉冲指令形式 = 符号(方向)+脉冲
  Pn008 = 10000  电机旋转 1 圈的指令脉冲数
]]
local M = {}

-- ==================== 屏幕 ====================
M.screen = {
    w = 1024,
    h = 600,
    rotation = 0,
    pin_rst = 15,        -- LCD 复位/显示使能
    pin_pwr = 17,        -- LCD 供电使能（低有效）
    backlight_pwm = 3,   -- 背光 PWM3（GPIO13）
    backlight_freq = 1000,
    backlight_duty = 100,
    tp = { port = 1, pin_rst = 14, pin_int = 51 },
    font_sizes = { 16, 20, 26 }, -- 界面用到的字号必须都在这里（hzfont 最小 16）
}

-- ==================== 脉冲输出：PWM1 / GPIO65 ====================
M.pulse = {
    pwm_ch           = 1,     -- PWM1 通道（本板引到 GPIO65）
    duty_default     = 50,    -- 默认占空比 %
    duty_min         = 1,
    duty_max         = 99,

    period_us_min    = 5,     -- 一个脉冲的周期下限 5us（200kHz）
    period_us_max    = 2000,  -- 上限 2000us（500Hz）
    period_us_default = 100,  -- 默认 100us = 10kHz（10000脉冲/圈 => 60rpm）

    -- 脉冲输出只走 pwm.setup/start/stop 三个接口。
    -- 脉冲个数通过 pwm.setup 第 4 个参数（pnum）下发给硬件：
    --   个数 = 0 → 持续输出；个数 > 0 → PWM 外设发满自动停，无任何软件定时器。

    -- 停止（以及上电后未启动）时，让 PWM 以这个频率输出 0% 占空比 = 常量电平：
    -- 引脚始终由 PWM 外设持有，既不产生边沿，也不会悬空被 RGB 总线干扰。
    -- 注意：不要改成 gpio.setup(65) 拉低——实测那样做之后 pwm.start 抢不回引脚，
    -- 表现为"日志正常、示波器没有任何波形"。
    park_freq = 100,

    -- 若某平台 PWM 通道需要显式复用到管脚，把 GPIO65 所在物理管脚号填这里
    pin              = nil,
    pin_func         = "PWM1",
    gpio             = 65,    -- 仅注释用（PWM 脚由外设接管，不需要 gpio.setup）
}

-- ==================== 方向输出：SPI1_CLK / PIN50 / GPIO9 ====================
M.dir = {
    gpio     = 9,        -- gpio.setup/gpio.set 使用的 GPIO 编号
    pin      = nil,      -- AIR1603 V1028 无 air1603 管脚表，pins.setup 不可用，默认 nil
    pin_func = "GPIO9",
}

-- ==================== 机械换算（只用于界面显示 rpm） ====================
M.servo = {
    pulses_per_rev = 10000, -- 必须与驱动器 Pn008 一致
}

-- ==================== 界面初始值 / 步进 ====================
M.ui = {
    count_default    = 10000,   -- 默认目标脉冲数（恒为正，方向由 GPIO9 决定）
    count_max        = 1000000, -- 目标脉冲数上限，发满即自动停止
    duty_step        = 5,       -- 占空比 +/- 步进
    period_step      = 5,       -- 周期 +/- 步进 us
    refresh_ms       = 200,     -- 状态刷新周期
}

-- ==================== RS485 / Modbus（本轮不用，留给 servo_modbus.lua）====================
M.mb = {
    enable         = false,
    uart_id        = 1,
    baud           = 9600,
    parity         = "none",
    stop_bits      = 1,
    slave          = 1,
    timeout        = 300,
    hi_word_first  = true,
    rs485_dir_gpio = nil,
    rs485_rx_level = 0,
}

return M
