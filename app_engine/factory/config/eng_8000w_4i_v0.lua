--[[
@module  config.eng_8000w_4i_v0
@summary 合宙引擎主机 Air8000W 4寸SPI屏 配置文件
@version 1.2
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8000W_4inch_320x480_000_V000",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air8000W",                                  -- 主控芯片: 4G + WiFi(exnetif) + SPI屏
    baseboard = "合宙引擎主机8000W_V000",                -- 底板型号

    -- ===== 引脚功能复用 =====
    pins = {
        { pin = 31, func = "PWM0" },  -- PWM0: 背光调光
        { pin = 35, func = "PWM4" },  -- PWM4: 蜂鸣器
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST7796 SPI 4寸 320×480
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,      -- SPI 端口 0
                pin_rst = 36,            -- 复位引脚
                pin_pwr = 28,            -- 背光供电 GPIO
                direction = 0,           -- 0° 方向
                w = 320,                 -- 水平分辨率
                h = 480,                 -- 竖直分辨率
            },
            need_buffer = false,         -- SPI 屏不需要帧缓冲，直刷更快
            screen_size = 4.0,           -- 4寸屏
            font = { size = 14 },        -- 低分屏用 14 号字
            backlight = {
                pwm_ch = 0,              -- PWM 通道 0
                pwm_freq = 1000,         -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口0
        tp = {
            model = "tp_gt911",
            params = {
                port = 0,                -- I2C 端口 0
                pin_rst = 26,            -- 复位引脚
                pin_int = gpio.WAKEUP0,  -- 中断引脚（Air8000 系列用唤醒引脚）
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        net_4g = true,                   -- 启用 4G 蜂窝网络（Air8000W 内置 4G）
        wifi = true,                     -- 启用 WiFi（exnetif 模式）
        buzzer = true,                   -- 启用蜂鸣器（触摸反馈音）
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,             -- 桌面顶栏 4G 图标 ← 配 net_4g 时打开
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标 ← 配 wifi 时打开
        show_buzzer_settings = true,     -- 设置页蜂鸣器开关 ← 配 buzzer 时打开
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
    },
}
