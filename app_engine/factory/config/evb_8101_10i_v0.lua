--[[
@module  config.evb_8101_10i_v0
@summary Air8101 EVB 10寸1024x600 RGB屏(HX8282) + AirLCD_1100 配置文件
@version 1.1
@date    2026.06.18
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air8101_AirLCD_1100_000_V020",    -- 项目命名: {类型}_{芯片}_{型号}_{版本}
    chip = "Air8101",                                 -- 主控芯片: WiFi(exnetif) + RGB屏
    baseboard = "EVB_Air8101 开发板 V2.0", -- 底板型号

    -- ===== 引脚功能复用（填引脚号，不填 GPIO 号）=====
    pins = {
        { pin = 11, func = "I2C1_SDA"  },  -- I2C1 数据线（触摸通信）
        { pin = 12, func = "I2C1_SCL"  },  -- I2C1 时钟线
        { pin = 14, func = "PWM1"      },  -- PWM1: 背光调光
        { pin = 72, func = "SPI0_CLK"  },  -- SPI0 时钟（SD + NAND 共用）
        { pin = 71, func = "SPI0_MOSI" },  -- SPI0 主机输出
        { pin = 6,  func = "SPI0_MISO" },  -- SPI0 主机输入
    },

    -- ===== GPIO 上电时序: 外设供电使能 + SPI CS 初始化 =====
    -- SPI0 由 SD 卡 + NAND Flash + 以太网(CH390H) 共用
    -- power_on 阶段先打开所有供电，再将所有 CS 引脚初始化为高电平（SPI 空闲态）
    -- 各驱动初始化时各自接管自己的 CS 引脚
    power_on = {
        { pin = 55, dir = 0, level = 1 },  -- LCD_EN = GPIO55 拉高，LCD 供电
        { pin = 48, dir = 0, level = 1 },  -- NAND_FLASH_EN = GPIO48 拉高，NAND 供电
        { pin = 50, dir = 0, level = 1 },  -- SD_EN = GPIO50 拉高，SD 卡供电
        { pin = 53, dir = 0, level = 1 },  -- LAN_EN = GPIO53 拉高，以太网供电
        -- SPI0 总线 CS 脚全部拉高（空闲态），各驱动在 SPI 事务中自行控制
        { pin = 32, dir = 0, level = 1 },  -- SPI0_CS1 = GPIO32 拉高（SD 卡片选）
        { pin = 49, dir = 0, level = 1 },  -- SPI0_CS2 = GPIO49 拉高（NAND Flash 片选）
        { pin = 34, dir = 0, level = 1 },  -- SPI0_CS0 = GPIO34 拉高（以太网 CH390H 片选）
        { pin = 52, dir = 0, level = 1 },  -- MODBUS_EN
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 10寸 1024×600（AirLCD_1100 模组，四合一芯片无需 SPI 初始化引脚）
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,          -- RGB 接口
                pin_rst = 38,            -- 复位引脚 GPIO38
                direction = 0,           -- 0° 方向
                w = 1024,                -- 水平分辨率
                h = 600,                 -- 竖直分辨率
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 10.0,          -- 10寸屏
            font = {
                size = 20,               -- 高分屏用 20 号字
                path = "/MiSans_gb2312.ttf",  -- 外部 ttf 字体（Air8101 从文件系统加载）
                global = true,           -- 注册为全局字体
            },
            backlight = {
                pwm_ch = 1,              -- PWM 通道 1（pin14 复用为 PWM1）
                pwm_freq = 10000,        -- 10kHz（RGB 屏推荐）
            },
        },
        -- 触摸: GT911 I2C 端口1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 28,            -- 复位引脚 GPIO28
                pin_int = 7,             -- 中断引脚 GPIO7
                int_type = tp.FALLING,   -- 下降沿触发（大屏推荐）
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi（exnetif 模式）
        ethernet = true,                 -- 启用 SPI 以太网（CH390H，SPI0_CS0=GPIO34）
        -- sd_card = true,                  -- 启用 SD/TF 卡（需配 storage.sd_card）
        -- nand_flash = true,               -- 启用 NAND Flash（需配 storage.nand_flash）
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
        show_ethernet_settings = true,   -- 设置页以太网设置入口
    },

    -- ===== 存储设备: SD/TF 卡 + NAND Flash =====
    -- SPI0 共用总线，SD 片选 CS1=GPIO32，NAND 片选 CS2=GPIO49
    storage = {
        -- sd_card = {
        --     spi_id = 0,                  -- SPI0 总线
        --     pin_cs = 32,                 -- SPI0_CS1（共用 SPI0 接口）
        --     speed = 20000000,            -- SPI 时钟频率 Hz
        --     -- pin_pwr = 50,             -- 供电已由 power_on 的 SD_EN 处理，不重复配置
        -- },
        -- nand_flash = {
        --     spi_id = 0,                  -- SPI0 总线（与 SD 卡共用）
        --     pin_cs = 49,                 -- SPI0_CS2
        --     speed = 20000000,            -- SPI 时钟频率 Hz
        --     -- pin_pwr = 48,             -- 供电已由 power_on 的 NAND_FLASH_EN 处理，不重复配置
        -- },
    },

    -- ===== 以太网: SPI0 外挂 CH390H 芯片 =====
    ethernet = {
        spi_id = 0,                  -- SPI0 总线（与 SD、NAND 共用）
        pin_cs  = 34,                -- SPI0_CS0（以太网 CH390H 片选）
        pin_irq = 9,                 -- ETH_INT=GPIO9（CH390H 中断引脚）
        -- pin_pwr = 53,             -- 供电已由 power_on 的 LAN_EN 处理，不重复配置
    },
}