--[[
@module  board_pins
@summary Air8101B V3.0 开发板（EVB_Air8101 V3.0）管脚分配表 —— 全工程唯一来源
@version 1.0
@date    2026.10.15
@usage
管脚来源：EVB_Air8101 开发板 V3.0 原理图（11 页，网络标号）
命名说明：本文件不能叫 pins.lua —— pins 是 LuatOS 核心库（pinmux）名，
         同名会导致 require 拿到核心库而不是本表。
约定：
1. 本表只描述"开发板硬件怎么接的"，不含任何业务逻辑；
2. 所有供电/使能脚的拉高顺序与延时见 board_init.lua；
3. 标 TODO 的项待真机确认后再定稿，禁止猜测填值。
]]

return {
    -- ===== 串口 =====
    -- 产测指令口由 config_*.lua 的 factory.uart_id 指定（默认 UART1）
    uart = {
        -- 调试/日志/下载串口，CH340 Type-C
        dbg = { id = 0, rx = 10, tx = 11 },            -- U0RX / U0TX
        -- 4G 从机 Air780ER2，AirLink UART 模式；产测口默认也是这一路
        -- UART1 引脚（依据官方 demo/sensor/bl0939/readme.md，与内核日志
        -- `uart(1) tx pin: 0, rx pin: 1` 一致）：
        --   pad 12 = GPIO0 = U1TXD   ← 板子发送
        --   pad 11 = GPIO1 = U1RXD   ← 板子接收
        -- 外接 USB-TTL 测 UART1 时必须关掉 VBAT_4G（否则 780ER2 会驱动同一对线）
        g4 = { id = 1, tx = 12, rx = 11 },             -- 4G_UART1_TXD / RXD
        -- RS485（SP3485EEN）
        rs485 = { id = 2, rx = 30, tx = 31, dir = 37 },-- U2RX / U2TX / 485_RE_DE
    },

    -- ===== 供电与使能（全部需要软件拉高）=====
    pwr = {
        lcd_en   = 55,   -- LCD_EN     屏幕供电使能
        sd_en    = 50,   -- SD_EN
        nand_en  = 48,   -- NAND_EN
        lan_en   = 53,   -- LAN_EN
        rs485_en = 52,   -- 485_EN
        uvc_en   = 29,   -- UVC_EN     摄像头供电（驱动前需先断电复位）
        audio_pa = 27,   -- PA_EN      speaker 功放使能
        g4_rst   = 51,   -- 4G_RST
    },

    -- ===== 显示（RGB 接口）=====
    lcd = {
        port     = "RGB",
        en       = 55,   -- LCD_EN
        rst      = 5,    -- LCD_RST
        backlight = nil, -- PWM1/BL：开发板背光走 PWM1，pin_pwr 取值待真机确认（TODO）
        -- RGB 数据线 DCLK/DISP/DE/HSYNC/VSYNC = GPIO14/15/16/17/18，
        -- 由底层 RGB 控制器固定映射，Lua 侧无需逐根声明
    },

    -- ===== I2C1 总线（触摸 IC 与排针共用同一条）=====
    -- Air8101 默认把 I2C1 放在 pad 12/11 = GPIO0/GPIO1，而这两个脚在开发板上
    -- 是 UART1（780ER2 / 产测串口），必须在 board_init 里切到下面这组：
    --   pad 7  = GPIO38 = I2C1_SCL  (DVP_D6/I2C1SCL)
    --   pad 69 = GPIO39 = I2C1_SDA  (DVP_D7/I2C1SDA)
    -- 板上引出的 I2C 排针就是 I2C1，GT911 触摸也挂在这条总线上。
    -- 因此 I2C_SCAN# 的判定基准 = 必须扫到 GT911（0x5D 或 0x14，由 INT 上电电平决定），
    -- 传感器地址是可选附加项；业务模式下传感器与触摸共享总线，轮询间隔不宜过短。
    -- 这条总线上的从机：0x5D/0x14 GT911 触摸、0x44/0x45 SHT30/31 温湿度、0x1A AGS02MA 空气质量。
    i2c1 = {
        pad_scl = 7,
        pad_sda = 69,
    },
    tp = {
        model = "gt911",
        i2c_id = 1, scl = 38, sda = 39,  -- I2C1_SCL / I2C1_SDA（注意：不是软件 I2C）
        rst = 28, int = 7,               -- TP_RST / TP_INT
        addr_list = { 0x5D, 0x14 },      -- GT911 两个可能地址，供 I2C_SCAN# 判定
    },

    -- ===== SPI0 总线（CH390H 以太网 + SPI NAND 分时复用）=====
    -- Air8101 默认把 SPI0 放在 GPIO14/15/16/17，而 V3.0 开发板上那四个脚是
    -- LCD 的 DCLK/DISP/DE/HSYNC，必须在 board_init 里做 pinmux 切到下面这组
    -- （pins.setup 的第一个参数是 pad 编号，对应原理图模组 pin 脚号）：
    --   pad 72 = GPIO33 = SPI0_CLK   (DVP_D1/SPI0CLK)
    --   pad 71 = GPIO35 = SPI0_MOSI  (DVP_D3/SPI0MOSI)
    --   pad 6  = GPIO36 = SPI0_MISO  (DVP_D4/SPI0MISO)
    -- 两个设备必须同时初始化并各自拉高 CS，否则总线电平混乱
    spi0 = {
        pad_clk  = 72,
        pad_mosi = 71,
        pad_miso = 6,
        cs_lan   = 34,   -- SPI0_CS0 → CH390H
        cs_nand  = 49,   -- SPI0_CS1 → SPI NAND
        eth_int  = 9,    -- ETH_INT 以太网中断
    },

    -- ===== RS485（UART2 + SP3485 收发器）=====
    -- 引脚对应（原理图网络名 + /luadb/pins_air8101b.json 的 pad↔GPIO 表）：
    --   pad 73 = GPIO31 = U2TX      ← 注意是 pad73，不是 74（pad74 是 GPIO29 = UVC_EN）
    --   pad 3  = GPIO30 = U2RX
    --   pad 70 = GPIO37 = 485_RE_DE（收发方向，高=发送 低=接收）
    --   GPIO52          = 485_EN（收发器供电使能，pad46）
    --
    -- 方向脚两种用法（官方 demo module/Air8101/demo/uart/485_uart.lua）：
    --   uart.setup(2, baud, 8, 1, uart.NONE, uart.LSB, 1024, 37, 0, 20000)
    -- 第 8/9/10 参数 = 方向脚 / 接收电平 / 方向切换延时(µs)。
    -- 少第 10 个参数自动换向不生效，DE 一直停在接收态，帧发不出去。
    --
    -- ⚠️ 【实测坑，2026-10-18】本板 485 端子的 A/B 极性与常见设备（USB-485 转换器、
    -- 常规 Modbus 从机模块）**相反**。照丝印 A→A / B→B 接线时：
    --   · 板子发出去的帧在 USB-485 上显示为 FA FD FF FF FF F7 85 6D FF 这类乱码
    --     （字节数相同、内容全乱，0x55 这类位对称字节反而正常 —— 典型极性反接特征）
    --   · 对端回包解不出来，表现为"TX 正常、RX 恒 0 字节"
    -- 解决：把 A/B 对调一次即可（对调后 USB-485 上能收到干净的
    --       01 01 00 00 00 04 3D C9）。产测工装因为极性与本板一致，所以没暴露这个问题。
    rs485 = {
        -- pad_tx / pad_rx 只作说明用（UART 的 TX/RX 由内核 uart.setup 按 GPIO 号配置），
        -- 实际 pinmux 只用到 pad_dir。
        pad_tx  = 73,    -- pad73 = GPIO31 = U2TX（旧版本误写 74，74 是 GPIO29=UVC_EN）
        pad_rx  = 3,     -- pad3  = GPIO30 = U2RX
        pad_dir = 70,    -- pad70 = GPIO37 = 485_RE_DE
    },

    -- ===== SD 卡（SDIO 专用接口）=====
    sd = {
        en = 50,         -- SD_EN
        -- SDIO_CLK/CMD/D0/D1/D2/D3 走 SDIO 专用 pad，无需声明
    },

    -- ===== 音频 =====
    audio = {
        pa_en = 27,      -- PA_EN
    },

    -- ===== 摄像头（UVC / USB HOST）=====
    cam = {
        en = 29,         -- UVC_EN
    },

    -- ===== 硬件按键（不可编程，仅供说明）=====
    key = {
        reset  = "RESET_AIR8101",  -- 8101_RST
        boot4g = "USB_BOOT",       -- BOOT_4G 4G 下载模式
        rst4g  = "4G_RESET",       -- 4G_RESET
    },
}
