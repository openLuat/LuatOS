--[[
@module  conf
@summary 三菱 FX 温度监控大屏全局配置（Air8603W1 / 10寸 1024x600 / RS485 计算机链接）
@version 1.0.0
@date    2026.11.09

=== 通信 ===
三菱 FX 计算机链接协议格式 1：ASCII 帧（ENQ/STX/ETX + 和校验）。
纯只读：只采、只显示、只报警，不向 PLC 写任何数据。

=== PLC 侧要求（缺一不可）===
M8002 初始化（上电执行一次）：
    MOV H6087 D8120     ; 9600 / 8 数据位 / 偶校验 / 1 停止位 / 格式1 / 自动和校验
    MOV K0    D8121     ; 站号 0
梯形图常驻：
    RD3A K0 K0 D0       ; AD0 → D0（温度通道 1）
    RD3A K0 K1 D1       ; AD1 → D1（温度通道 2）

D8120 = H6087 逐位含义（b0 最低位）：
    b0      = 1    数据长度 8 位
    b1      = 1    有奇偶校验
    b2      = 1    偶校验（1 = 偶，0 = 奇）
    b3      = 0    停止位 1 位
    b7~b4   = 1000 波特率 9600（编码值，不是 9600 的二进制）
    b8      = 0    无报头（不附加 D8124 起的自定义字符串）
    b13     = 1    自动附加和校验
    b14     = 1    协议格式 1（ASCII、无报头无报尾）
    b15     = 0    不附加 CR

=== 量程（温度）===
AD 原始值 0~4000 对应 0~100.0℃：
    val = raw / 40    （1℃ = 40 个原始码）
现场若换成别的温度变送器（如 0~10V 对应 0~150℃），只改下面 conf.scale 的
val_max 一处即可，换算、曲线 Y 轴、阈值范围、语音播报全部跟着走。

=== 数据位说明 ===
本平台 uart 驱动的 7 数据位不生效，硬件始终按 8 位采样。
故统一用 8 数据位，PLC 侧 D8120 = H6087（b0=1 = 8 位），两边必须同步。
]]

local conf = {}

-- ===== 屏幕 =====
conf.W, conf.H = 1024, 600

-- ===== 板级（Air8603W1 底板）=====
conf.board = {
    -- 上电时序：{ 引脚, 电平, 延时ms }
    -- 顺序即依赖：电源轨 → 网络模组复位 → SD → 功放关断 → 485 总供电 → DE 停在接收态
    -- 注意 { 64, 1 }：485 收发芯片由 GPIO64 单独供电，漏掉它串口能打开但没有波形
    power_on = {
        { 12, 1 },        -- 5V_EN
        { 56, 1, 100 },   -- 9V_EN
        { 44, 1 },        -- 12V_EN
        { 52, 1 },        -- 5VOUT_EN
        { 72, 0, 20 },    -- 网络模组 RST
        { 74, 1 },        -- SD_EN
        { 73, 0 },        -- AUDIOPA_EN 关功放（HT6873 高有效）
        { 64, 1 },        -- 485_EN 总供电
        { 65, 0 },        -- 485_EN1 = DE，空闲低电平（接收态）
    },
    -- RGB 10寸 1024×600，免序列四合一
    lcd = {
        interface = "rgb",
        pin_rst   = 15,          -- LCD_DISP
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
    -- GT911 触摸
    tp = {
        port     = 1,
        pin_rst  = 14,
        pin_int  = 51,
        w        = 1024,
        h        = 600,
    },
    -- 背光 PWM3
    backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
    -- 字体：hzfont 内置字库
    font = { size = 18, cache_size = 4096, antialias = 1 },
    -- 外部看门狗 Air153D（不需要时置 false）
    wdt_pin = 57,
    -- 音频：内置 DAC + HT6873
    audio = {
        model       = "dac",
        audio_mode  = "new",
        pa_ctrl     = 73,
        pa_on_level = 1,
        pa_delay    = 10,
        dac_delay   = 6,
        play_vol    = 20,
    },
}

-- ===== 串口（RS485，三菱计算机链接）=====
-- Air8603W1：UART1 = 隔离 485，DE = GPIO65，接收态低电平
conf.uart = {
    id             = 1,
    baud           = 9600,
    databits       = 8,          -- 必须与 D8120 b0 = 1 一致
    stopbits       = 1,
    parity         = uart.Even,  -- 与 D8120 b2,b1 = 11 一致
    de_pin         = 65,         -- RS485 方向脚，作为 pin485 交给 uart.setup 自动换向
    de_rx_level    = 0,          -- 接收方向电平（DE 空闲拉低）
    -- 换向延迟（微秒）：最后一个字节移出移位寄存器后再等这么久才释放 DE。
    -- 9600 下一位 104us，2000us 约两位，足够让停止位出完、总线释放。
    rs485_delay_us = 2000,
}

-- ===== PLC 站参数 =====
conf.plc = {
    station = 0,      -- 站号，对应 D8121 = K0，帧里写 "00"
    plc_no  = 0xFF,   -- PLC 号，固定 0xFF
    wait    = 0,      -- 请求里的延时字符，0 = 不额外延时
    timeout = 800,    -- 单帧响应超时 ms
}

-- ===== 量程换算（温度）=====
conf.scale = {
    raw_min = 0,       -- 原始值下限
    raw_max = 4000,    -- 原始值上限
    val_min = 0.0,     -- 温度下限
    val_max = 100.0,   -- 温度上限（℃）
    unit    = "℃",
    dec     = 1,
}

-- ===== AD 通道点表（两路温度）=====
-- 三菱协议的软元件编号不能用 0x 表示，addr 是与 dev 组合的十进制编号。
-- 两路地址连续（D0/D1），一帧 WR 就能读回，减少总线占用。
conf.chs = {
    { key = "ad1", name = "温度 1", dev = "D", addr = 0, color = 0x22D3EE,
      warn = 70.0, alarm = 90.0 },
    { key = "ad2", name = "温度 2", dev = "D", addr = 1, color = 0x4C8DFF,
      warn = 70.0, alarm = 90.0 },
}

-- ===== 趋势 =====
conf.trend = {
    sample_ms = 2000,   -- 采样周期，比轮询慢一档，保证每个点都是新数据
    cap       = 300,    -- 每通道历史点数（300 × 2s = 10 分钟窗口）
    y_min     = 0,      -- 曲线 Y 轴下限（0.01℃，即 0.00℃）
    y_max     = 10000,  -- 曲线 Y 轴上限（0.01℃，即 100.00℃）
}

-- ===== 报警 =====
conf.alarm = {
    hysteresis = 1.0,   -- 回差（℃），恢复需低于阈值 - 回差
    max        = 8,     -- 报警记录条数
    popup      = true,  -- 新报警是否自动弹窗
    speech         = true,   -- 语音总开关
    speech_gap     = 10000,  -- 报警持续时的重复播报间隔 ms（0 = 只播一次）
    speech_timeout = 15000,  -- 单条播报超时 ms
}

-- ===== 轮询 =====
conf.poll_ms = 1000       -- 采集周期（1s 一次；温度变化慢，够用且总线占用低）
conf.offline_retry = 3    -- 连续失败多少次判离线

-- ===== 存储 key 前缀（fskv）=====
conf.store_ns = "melsec"

return conf
