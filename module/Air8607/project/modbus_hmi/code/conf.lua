--[[
@module  conf
@summary Modbus 工业中控大屏 - 板级参数与通信/业务配置
@version 1.0.0
@date    2026.10.25
@board   Air8607（Air1603）+ AirLCD_1090（9寸 RGB 1024x600 / JD9165BA / GT911）

硬件说明：
  AirLCD_1090 = RGB 接口、1024x600、驱动 IC JD9165BA、触摸 GT911、亮度 500cd/m²
  与 eng_8607_10i_v0.lua 的时序参数一致（1024x600 生态实测组）：
    hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @ 50MHz
  LCD 复位 pin_rst = 15（LCD_DISP）   LCD 供电 pin_pwr = 17
  背光 PWM3       触摸 I2C1（pin_rst=14 / pin_int=51）
]]
return {
    W = 1024,
    H = 600,

    name    = "Modbus 中控大屏",
    version = "1.0.0",
    subtitle = "MODBUS SCADA HMI · Air8607",

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 85,
        min     = 10,
    },

    font = {
        size       = 16,
        cache_size = 4096,
        antialias  = 1,
    },

    -- ===== 通信参数 =====
    -- transport: "sim"（内置虚拟从站，PC/无总线时默认）/ "rtu"（RS485）/ "tcp"（Modbus TCP）
    comm = {
        transport = "sim",

        rtu = {
            uart_id        = 1,
            baud           = 9600,
            databits       = 8,
            parity         = "none",   -- none / even / odd
            stopbits       = 1,
            rs485_de_pin   = 0,        -- 0 = 不控制 DE（模块自带收发切换 / 已外接自动换向）
            rs485_de_level = 1,        -- 发送时的 DE 电平
        },

        tcp = {
            ip   = "192.168.1.100",
            port = 502,
        },

        timeout_ms       = 800,   -- 单帧响应超时
        retry            = 2,     -- 失败重试次数
        poll_interval_ms = 1000,  -- 每轮轮询之间的间隔
        offline_after    = 3,     -- 连续失败多少轮判定离线
        inter_frame_ms   = 30,    -- 帧间间隔（RS485 方向切换需要）
    },

    -- ===== 内置从站模拟 =====
    sim = {
        history_n      = 80,      -- 每条曲线的采样点数
        baud_for_delay = 9600,    -- sim 传输按该波特率折算响应延迟，让时序更真实
        inject_fault   = true,    -- 自动注入通信故障（超时/CRC 错），用于演示报警链路
        fault_every    = 45,      -- 每 N 轮注入一次
        fault_rounds   = 4,       -- 单次故障持续轮数
    },

    alarm = {
        max_log = 80,
    },
}
