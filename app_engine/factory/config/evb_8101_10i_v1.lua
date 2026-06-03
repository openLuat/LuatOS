--[[
@module  config.evb_8101_10i_v1
@summary Air8101核心板 10.1寸1024x600 RGB屏(HX8282) 配置文件
@version 1.2
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air8101_10inch1_1024x600_000_V010",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air8101",                                  -- 主控芯片: WiFi(exnetif) + RGB屏
    baseboard = "Air8101核心板V1.0",                   -- 底板型号

    -- ===== 引脚功能复用（填引脚号，不填 GPIO 号） =====
    pins = {
        { pin = 11, func = "I2C1_SDA"  },  -- I2C1 数据线（触摸通信）
        { pin = 12, func = "I2C1_SCL"  },  -- I2C1 时钟线
        { pin = 14, func = "PWM1"      },  -- PWM1: 背光调光
        { pin = 72, func = "SPI0_CLK"  },  -- SPI0 时钟（存储设备）
        { pin = 71, func = "SPI0_MOSI" },  -- SPI0 主机输出
        { pin = 6,  func = "SPI0_MISO" },  -- SPI0 主机输入
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 10.1寸 1024×600（四合一芯片，无需 SPI 初始化引脚）
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,          -- RGB 接口
                pin_rst = 38,            -- 复位引脚
                pin_pwr = 29,            -- 背光供电 GPIO
                direction = 0,           -- 0° 方向
                w = 1024,                -- 水平分辨率
                h = 600,                 -- 竖直分辨率
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 10.0,          -- 10.1寸屏
            font = {
                size = 20,               -- 高分屏用 20 号字
                path = "/MiSans_gb2312.ttf",  -- 外部 ttf 字体（Air8101 从文件系统加载）
                global = true,           -- 注册为全局字体
            },
            backlight = {
                pwm_ch = 1,              -- PWM 通道 1
                pwm_freq = 10000,        -- 10kHz（RGB 屏推荐）
            },
        },
        -- 触摸: GT911 I2C 端口1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 28,            -- 复位引脚
                pin_int = 7,             -- 中断引脚
                int_type = tp.FALLING,   -- 下降沿触发（大屏推荐）
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi（exnetif 模式）
        sd_card = true,                  -- 启用 SD/TF 卡（需配 storage.sd_card）
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
    },

    -- ===== 存储设备: SD/TF 卡 =====
    storage = {
        sd_card = {
            spi_id = 0,                  -- SPI 接口 ID
            pin_cs = 32,                 -- 片选 CS 引脚
            speed = 40000000,            -- SPI 时钟频率 Hz
        },
    },
}
