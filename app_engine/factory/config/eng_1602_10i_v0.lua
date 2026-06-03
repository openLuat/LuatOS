--[[
@module  config.eng_1602_10i_v0
@summary Air1602引擎主机 10.1寸1024x600 RGB屏 配置文件
@version 1.2
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air1602_10inch1_1024x600_001_V000",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1602",                                     -- 主控芯片: RGB屏 + WiFi(airlink)
    baseboard = "合宙引擎AIR1602 V001",                   -- 底板型号

    -- ===== 引脚功能复用（无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: WiFi 模组复位 =====
    -- Air1602 airlink WiFi 模组: GPIO55 拉低→延时→拉高（高电平有效）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50  },  -- 拉低 50ms 复位
        { pin = 55, dir = 0, level = 1, delay = 120 },  -- 拉高 120ms 使能
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 10.1寸 1024×600（四合一芯片，无需 SPI 初始化引脚）
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,          -- RGB 接口
                pin_rst = 15,            -- 复位引脚
                direction = 0,           -- 0° 方向
                w = 1024,                -- 水平分辨率
                h = 600,                 -- 竖直分辨率
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 10.0,          -- 10.1寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,              -- PWM 通道 3
                pwm_freq = 1000,         -- 1kHz
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
                gpio_reset = 3,          -- 额外复位 GPIO（Air1602 常用）
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi
        buzzer = true,                   -- 启用蜂鸣器（触摸反馈音）
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_buzzer_settings = true,     -- 设置页蜂鸣器开关 ← 配 buzzer 时打开
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
    },
}
