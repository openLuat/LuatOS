--[[
@module  config.evb_1601_7i_v12
@summary Air1601 EVB 7寸1024x600 RGB屏(HX8282) + PWM背光 + SD卡 + 4G + WiFi + 以太网 配置文件
@version 1.0
@date    2026.07.24
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

与 V011 的差异:
1. 总供电 GPIO58
2. WiFi 使用 AirLink SPI2 (CS=GPIO4, RDY=GPIO13), WiFi_EN=GPIO12, WIFI_IRQ=GPIO2, WAKEUP=GPIO0
3. 4G 使用 AirLink UART2 (4G_EN=GPIO42, 4G_RST=GPIO65, 4G_IRQ=GPIO2)
4. 以太网 SPI1/CS=GPIO14, LAN_EN=GPIO52, LAN_INT=GPIO1
5. SD 卡 SPI1/CS=GPIO8, SD_EN=GPIO56
6. LCD_EN=GPIO57, LED 背光=PWM3
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air1601_7inch_1024x600_000_V012",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1601",                                   -- 主控芯片: RGB屏 + WiFi(airlink) + 4G(airlink)
    baseboard = "Air1601 EVB V012",                     -- 底板型号

    -- ===== 引脚功能复用（Air1601 无特殊复用需求，留空）=====
    pins = {
        -- { pin = 32, func = "I2C1_SDA"  },  -- I2C1 数据线（触摸通信）
        -- { pin = 33, func = "I2C1_SCL"  },  -- I2C1 时钟线
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位
    power_on = {
        -- 总供电 (高电平有效)
        { pin = 58, dir = 0, level = 1 },

        -- WiFi 模组(6205) 上电 (AirLink SPI2, EN=GPIO12, 低电平有效)
        { pin = 12, dir = 0, level = 1, delay = 50  },  -- 拉高 50ms


        -- 4G 模组(Air780ER) 上电复位 (UART2, EN=GPIO42, RST=GPIO65)
        { pin = 42, dir = 0, level = 1, delay = 50  },  -- 拉高 EN 使能
        { pin = 65, dir = 0, level = 0, delay = 100 },  -- 拉低 RST 复位
        { pin = 65, dir = 0, level = 1, delay = 1000 }, -- 拉高 RST 释放，等待模块启动

        -- 8311 使能 与触摸共用I2C1(8311_EN=GPIO43)
        { pin = 43, dir = 0, level = 1 },

        -- 以太网 CH390 使能 (LAN_EN=GPIO52)
        { pin = 52, dir = 0, level = 1 },

        -- SD 卡使能 (SD_EN=GPIO56)
        { pin = 56, dir = 0, level = 1 },

        -- LCD 使能 (LCD_EN=GPIO57)
        { pin = 57, dir = 0, level = 1 },

    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 7寸 1024×600（四合一芯片，无需 SPI 初始化引脚）
        -- 背光: PWM3 调光（支持亮度调节）
        -- LCD_EN: GPIO57 控制 LCD 供电
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,          -- RGB 接口
                pin_rst = 15,            -- 复位引脚
                pin_pwr = 57,            -- LCD 供电使能 GPIO57 (LCD_EN)
                direction = 0,           -- 0° 方向
                w = 1024,                -- 水平分辨率
                h = 600,                 -- 竖直分辨率
                hbp = 140,               -- 水平后沿
                hspw = 20,               -- 水平同步脉宽
                hfp = 160,               -- 水平前沿
                vbp = 20,                -- 垂直后沿
                vspw = 3,                -- 垂直同步脉宽
                vfp = 12,                -- 垂直前沿
                bus_speed = 50 * 1000 * 1000,  -- RGB 总线时钟 50MHz
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 7.0,           -- 7寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,              -- LED 背光 PWM3（支持亮度调节）
                pwm_freq = 1000,         -- PWM 频率 1KHz
            },
        },
        -- 触摸: GT911 I2C 端口1，大屏带尺寸参数
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 3,             -- 复位引脚
                pin_int = 51,            -- 中断引脚
                int_type = tp.FALLING,   -- 下降沿触发（大屏推荐）
                w = 1024,                -- 触摸面板宽度
                h = 600,                 -- 触摸面板高度
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi（AirLink SPI2，6205 模组）
        net_4g = true,                   -- 启用 4G（AirLink UART2，Air780ER 模组）
        ethernet = true,                 -- 启用 SPI 以太网（CH390，SPI1）
        sd_card = true,                  -- 启用 SD/TF 卡（SPI1，CS=GPIO8）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- AirLink SPI WiFi（6205 模组，使用 SPI2）+ AirLink UART 4G（Air780ER，使用 UART2）
    -- SPI2 + UART2 互不冲突，可同时开启
    network = {

        -- ===== 最高优先级：以太网 =====
        { type = "eth_spi", chip = "CH390",
          spi_id = 1, cs_pin = 14,
          irq_pin = 1,          -- LAN_INT = GPIO1
          pwr_pin = 52 },       -- LAN_EN = GPIO52（已在 power_on 处理，此处冗余以防遗漏）

        -- ===== 第二优先级：WiFi（AirLink SPI2） =====
        { type = "wifi_airlink_spi",
          spi_id = 2,           -- SPI2
          cs_pin = 4,           -- CS = GPIO4
          rdy_pin = 13,         -- AirLink_RDY = GPIO13
          speed = 20 * 1000000, -- 20MHz
        },

        -- ===== 第三优先级：4G（AirLink UART2） =====
        { type = "4g_airlink_uart",
          uart_id = 2,          -- UART2
          baud = 2000000,       -- 2Mbps
          adapter = socket.LWIP_GP_GW,
        },

    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_4g_icon = true,             -- 桌面顶栏 4G 信号图标
        show_ethernet_settings = true,   -- 设置页以太网设置入口
        show_storage_settings = true,    -- 设置页存储空间入口
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,                  -- SPI 接口 ID（与以太网共用 SPI1，CS 不同）
            pin_cs = 8,                  -- 片选 CS 引脚 GPIO8
            speed = 40000000,            -- SPI 时钟频率 Hz（高速卡推荐 20MHz+）
        },
    },

    -- ===== 注意: WIFI_IRQ / AirLink_WAKEUP 配置 =====
    -- IRQ 和 WAKEUP 引脚需在 net_manager 初始化前通过 airlink API 单独配置：
    --
    --   airlink.config(airlink.CONF_SPI_IRQ, 2)       -- WIFI_IRQ = GPIO2
    --   airlink.irqmode(true, 2, 2)
    --   airlink.wakeupIrqmode(true, 0, 0, luat_gpio.RISING)  -- WAKEUP = GPIO0
    --
    -- 注: WIFI_IRQ 与 4G_IRQ 共用 GPIO2，UART 模式不需要 IRQ，无冲突
}
