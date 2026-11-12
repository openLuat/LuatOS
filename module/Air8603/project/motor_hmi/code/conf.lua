--[[
@module  conf
@summary 电机 HMI 全局配置（Air8603W1 / 10寸 1024x600 / RS485 Modbus RTU 主站）
@version 1.0.0
@date    2026.11.12

=== 被控设备 ===
台达 VFD-M 系列变频器（VFD015M21A，固件 v3.09 以上）
通讯：RS485 / Modbus RTU / 9600 8N1 / 站号 1

变频器侧必须与下面一致（缺一不可）：
    P88 = 01     站号
    P89 = 01     9600 bps
    P92 = 06     Modbus RTU 8,N,1
    P157 = 01    Modbus
    P01 = 03     运转指令由 RS485
    P00 = 00     频率由面板数字设定（P14），本 HMI 只做启停
    P91 = 2.0    通讯超时 2s（HMI 必须持续轮询，否则变频器自动停车）

=== 为什么 P91 必须配合轮询 ===
P91 是变频器的断线保护：超过设定时间收不到任何合法帧就报 Cu 并停车。
本 HMI 以 conf.poll_ms 周期轮询，天然满足它的心跳要求；
一旦 HMI 死机或线缆脱落，变频器会在 2 秒内自行停车，这是设计上的安全兜底。

=== 多电机预留 ===
conf.motors 是数组。当前只填 1 台，后续加台数只需在数组里追加条目，
并把各台变频器的 P88 设成不同的站号即可，界面与逻辑无需改动。
]]
local conf = {}

-- ===== 屏幕 =====
conf.W, conf.H = 1024, 600

-- ===== 板级（Air8603W1 底板，与 melsec_hmi 相同）=====
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
        { 73, 0 },        -- AUDIOPA_EN 关功放
        { 64, 1 },        -- 485_EN 总供电
        { 65, 0 },        -- 485_EN1 = DE，空闲低电平（接收态）
    },
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
    tp = {
        port     = 1,
        pin_rst  = 14,
        pin_int  = 51,
        w        = 1024,
        h        = 600,
    },
    backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
    font = { size = 18, cache_size = 4096, antialias = 1 },
    wdt_pin = 57,        -- Air153D 外部看门狗，不喂狗约 12 分钟重启
}

-- ===== 串口（RS485，Modbus RTU 主站）=====
conf.uart = {
    id             = 1,
    baud           = 9600,
    databits       = 8,
    stopbits       = 1,
    parity         = 0,     -- 8N1：无校验（对应变频器 P92 = 06）
    de_pin         = 65,    -- RS485 方向脚，交给 uart.setup 自动换向
    de_rx_level    = 0,     -- 接收方向电平
    rs485_delay_us = 2000,  -- 换向延迟：9600 下一位 104us，2ms 足够出完停止位
}

-- ===== Modbus =====
conf.modbus = {
    timeout = 500,          -- 单帧响应超时 ms
}

-- ===== 寄存器（台达 VFD-M）=====
-- 2100H~2104H 连续，一次读 5 个寄存器就能拿到全部状态，最省总线
conf.regs = {
    run      = 0x2000,      -- 写：运转命令（位域）
    freq     = 0x2001,      -- 写：频率命令 0.01Hz（本 HMI 不使用）
    reset    = 0x2002,      -- 写：Bit1 = 复位
    fault    = 0x2100,      -- 读：故障码
    state    = 0x2101,      -- 读：状态位
    freq_cmd = 0x2102,      -- 读：频率指令 0.01Hz
    freq_out = 0x2103,      -- 读：输出频率 0.01Hz
    current  = 0x2104,      -- 读：输出电流 0.1A（本机型测不到小电流，仅参考）
}

-- 2000H 位域取值
conf.cmd = {
    stop     = 0x0001,      -- Bit0~1 = 01B 停止
    run_fwd  = 0x0012,      -- Bit0~1 = 10B 启动 + Bit4~5 = 01B 正转
    run_rev  = 0x0022,      -- Bit0~1 = 10B 启动 + Bit4~5 = 10B 反转
    reset    = 0x0002,      -- 2002H 写 2 = 故障复位
}

-- 2101H 状态位
conf.st = {
    run_bit = 12,           -- 1 = 运转中
    fwd_bit = 3,            -- 1 = 正转
    rev_bit = 4,            -- 1 = 反转
}

-- ===== 电机列表（多台预留）=====
-- station 必须与变频器 P88 一致；freq_hz 仅用于显示额定值
conf.motors = {
    { key = "m1", name = "1 号电机", station = 1, freq_hz = 50.0 },
}

-- ===== 轮询 =====
conf.poll_ms = 500          -- 必须 < 变频器 P91（2s），否则会误报 Cu
conf.offline_retry = 3      -- 连续失败多少次判离线

-- ===== 顺序启动 =====
-- 多台电机依次启动时，相邻两台之间的间隔
conf.seq = {
    gap_s   = 2,            -- 出厂默认 2 秒
    gap_min = 0,
    gap_max = 60,
}

-- ===== 报警 =====
conf.alarm = {
    max = 8,                -- 记录条数
    popup = true,           -- 新报警自动弹窗
}

-- ===== 故障码文本（v3.09，实测 13 = Cu 通讯超时）=====
conf.faults = {
    [0]  = "正常",
    [1]  = "过电流 OC",
    [2]  = "过电压 OU",
    [3]  = "过热 OH",
    [4]  = "变频器过载 OL",
    [5]  = "电机过载 OL1",
    [6]  = "外部异常 EF",
    [7]  = "EEPROM 异常 CF1",
    [8]  = "电流采样异常 Ad",
    [9]  = "驱动锁存异常 LC",
    [10] = "加速过流 OCA",
    [11] = "减速过流 OCd",
    [13] = "通讯超时 Cu",
    [14] = "运行中欠压 Lu",
    [16] = "输出缺相 PH2",
    [17] = "外部中断 bb",
    [18] = "自学习失败 EA",
    [19] = "复位次数超限 CL",
}

-- 过载类故障码：用于「任意电机过载」的判定
conf.overload_codes = { [4] = true, [5] = true }

-- ===== 存储 =====
conf.store_ns = "motor"

return conf
