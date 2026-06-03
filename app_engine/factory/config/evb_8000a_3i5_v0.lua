--[[
@module  config.evb_8000a_3i5_v0
@summary Air8000A trunkey 开发板 3.5寸480x320 SPI屏 配置文件
@version 1.1
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air8000A_3inch5_480x320_000_V020",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air8000",                                 -- 主控芯片: 4G + WiFi + GPS + SPI屏（兼容 Air8000A/D）
    baseboard = "Air8000A trunkey 开发板 V020",       -- 底板型号

    -- ===== 引脚功能复用 =====
    pins = {
        { pin = 31, func = "PWM0" },  -- PWM0: 背光调光
        { pin = 35, func = "PWM4" },  -- PWM4
    },

    -- ===== GPIO 上电时序: LCD供电 + TP I2C上拉 =====
    -- 最后一步 delay=100ms 等待外设稳定后再初始化
    power_on = {
        { pin = 141, dir = 0, level = 1              },  -- LCD 供电开
        { pin = 147, dir = 1, level = 1              },  -- TP I2C SDA 上拉
        { pin = 164, dir = 1, level = 1              },  -- TP I2C SCL 上拉
        { pin = 17,  dir = 1, level = 1              },
        { pin = 16,  dir = 1, level = 1, delay = 100 }, -- 最后一步等 100ms 稳定
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST7796 SPI 3.5寸 480×320 横屏
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,       -- SPI 端口 0
                pin_rst = 36,            -- 复位引脚
                direction = 1,           -- 90° 旋转（横屏）
                w = 480,                 -- 水平分辨率
                h = 320,                 -- 竖直分辨率
                xoffset = 0,             -- X 像素偏移
                yoffset = 0,             -- Y 像素偏移
                bus_speed = 80000000,    -- SPI 时钟 80MHz
            },
            need_buffer = false,         -- SPI 屏不需要帧缓冲，直刷更快
            screen_size = 3.5,           -- 3.5寸屏
            font = { size = 14 },        -- 低分屏用 14 号字
            backlight = {
                pwm_ch = 0,              -- PWM 通道 0
                pwm_freq = 1000,         -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口0，不复位
        tp = {
            model = "tp_gt911",
            params = {
                port = 0,                -- I2C 端口 0
                pin_rst = 0xff,          -- 0xff 表示不复位（底板无需复位引脚）
                pin_int = gpio.WAKEUP0,  -- 唤醒引脚用作中断
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
                pwr_delay = 100,         -- I2C 上电后等待 100ms
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        net_4g = true,                   -- 启用 4G 蜂窝网络（Air8000A 内置 4G）
        wifi = true,                     -- 启用 WiFi
        sd_card = true,                  -- 启用 SD/TF 卡（需配 storage.sd_card）
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,             -- 桌面顶栏 4G 图标 ← 配 net_4g 时打开
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标 ← 配 wifi 时打开
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
    },

    -- ===== 存储设备: SD/TF 卡 =====
    storage = {
        sd_card = {
            spi_id = 1,                  -- SPI 接口 ID
            pin_cs = 20,                 -- 片选 CS 引脚
            speed = 40000000,            -- SPI 时钟频率 Hz
        },
    },
}
