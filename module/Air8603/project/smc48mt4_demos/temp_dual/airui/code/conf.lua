--[[
@module  conf
@summary 双路温度监控 · 全局配置（Air8603W1 / 10寸 1024x600 / RS485 Modbus RTU 主机）
@version 1.0.0
@date    2026.11.16

=== 通信说明 ===
主控模组做 Modbus RTU 主机，SMC-48MT-4 做从站。
从站地址 204（0xCC），19200 / 8N1，功能码 03，纯只读。

读 4x 6700 起 4 个寄存器：
    6700/6701 = CH1（浮点，CDAB 字序）
    6702/6703 = CH2（浮点，CDAB 字序）

=== 量纲（2026-11-16 实测）===
读出来直接是摄氏度，因为 PLC 侧「外设配置」里 AD 最大值填的是 50。
若以后把 AD 最大值改成 100（扩量程），把 scale.val_max 改 100、raw_max 改 50 即可。

=== 硬件要点 ===
1. GPIO64 = 485 收发芯片供电，必须拉高；漏掉它串口能打开但总线上没有波形；
2. GPIO65 = UART1 的 485 方向脚（DE），交给 uart.setup 的 pin485 自动换向；
3. LCD 是 RGB 10 寸 1024×600，时序用 1024×600 生态实测组；
4. 板载 Air153D 看门狗，不喂狗约 12 分钟重启。
]]

local conf = {}

-- ===== 屏幕 =====
conf.W, conf.H = 1024, 600

-- ===== 板级 =====
conf.board = {
    -- 上电时序：{ 引脚, 电平, 延时ms }
    power_on = {
        { 12, 1 },        -- 5V_EN
        { 56, 1, 100 },   -- 9V_EN
        { 44, 1 },        -- 12V_EN
        { 52, 1 },        -- 5VOUT_EN
        { 72, 0, 20 },    -- 网络模组 RST
        { 74, 1 },        -- SD_EN
        { 73, 0 },        -- AUDIOPA_EN 关功放
        { 64, 1 },        -- 485_EN 总供电（关键）
        { 65, 0 },        -- 485_EN1 = DE，空闲接收态
    },
    lcd = {
        interface = "rgb",
        pin_rst   = 15,
        w         = 1024,
        h         = 600,
        hbp       = 140,
        hspw      = 20,
        hfp       = 160,
        vbp       = 20,
        vspw      = 3,
        vfp       = 12,
        bus_speed = 50 * 1000 * 1000,
    },
    tp = {
        port     = 1,
        pin_rst  = 14,
        pin_int  = 51,
        w        = 1024,
        h        = 600,
    },
    backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
    font = { size = 18, cache_size = 4096, antialias = 1 },
    wdt_pin = 57,
    -- 音频：内置 DAC + HT6873 功放（AUDIOPA_EN = GPIO73，高电平使能）
    audio = {
        model       = "dac",
        audio_mode  = "new",   -- 102 固件走 audio_v2，TTS 才出声
        pa_ctrl     = 73,
        pa_on_level = 1,
        pa_delay    = 10,      -- 起播后延迟拉高 PA，防 POP
        dac_delay   = 6,
        play_vol    = 30,
    },
}

-- ===== 串口（UART1 = 隔离 485）=====
conf.uart = {
    id             = 1,
    baud           = 19200,
    databits       = 8,
    stopbits       = 1,
    parity         = uart.None,
    de_pin         = 65,      -- 485 方向脚，pin485 交给平台自动换向
    de_rx_level    = 0,       -- 接收态低电平
    rs485_delay_us = 3000,    -- 19200 下一位 52us，3000us 约 57 位；太小会切掉应答末尾
}

-- ===== Modbus 从站 =====
conf.plc = {
    slave   = 204,      -- 0xCC
    reg     = 6700,     -- 起始寄存器
    count   = 4,        -- 读 4 个（两路浮点各占 2 个）
    timeout = 500,      -- 单帧响应超时 ms
}

-- ===== 量程换算 =====
-- 读到的浮点已经是摄氏度，所以 raw 与 val 是 1:1；
-- 保留这层是为了以后改 AD 最大值时只动这里。
conf.scale = {
    raw_min = 0.0,
    raw_max = 50.0,     -- PLC 侧 AD 最大值
    val_min = 0.0,
    val_max = 50.0,     -- 对应温度上限
    unit    = "℃",
    dec     = 2,
    -- CDAB：控制器发的是低字在前，解析时要交换
    word_swap = true,
}

-- ===== 两路通道 =====
conf.chs = {
    { key = "ch1", name = "测点一", color = 0x5AA9F0,
      warn = 35.0, alarm = 45.0, offset = 0.0 },
    { key = "ch2", name = "测点二", color = 0xF0A52E,
      warn = 35.0, alarm = 45.0, offset = 0.0 },
}

-- ===== 采集与趋势 =====
conf.poll_ms   = 500      -- 轮询周期
conf.sample_ms = 5000     -- 曲线采样周期（5s × 720 = 1 小时）
conf.trend     = { cap = 720, y_min = 20, y_max = 50 }
conf.offline_retry = 3    -- 连续失败几次判离线

-- ===== 报警 =====
conf.alarm = {
    hysteresis = 0.0,   -- 回差 ℃，默认 0（可设 0~5）
    delay_s    = 3,     -- 确认延时 秒
    max        = 8,     -- 记录条数
    raw_fault  = 1.0,   -- 读数低于此值判断线
    -- 语音播报
    speech         = true,   -- 总开关
    speech_gap     = 30000,  -- 报警持续时的重复播报间隔 ms（0 = 只播一次）
    speech_timeout = 15000,  -- 单条播报超时 ms
    -- 开机自检：true 时启动后立刻播一句，用来验证 DAC/功放/TTS 是否正常
    -- 正常使用请保持 false，否则每次开机都会响一声
    speech_selftest = false,
}

-- 是否打印收发报文（每帧一行，形如 TX[CC 03 ...] RX[CC 03 08 ...]）
-- 调试时开，稳定运行后可以关掉，否则 500ms 一帧会刷满日志
conf.log_frames = true

-- ===== 存储 =====
conf.store_ns = "tmon"

return conf
