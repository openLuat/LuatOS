--[[
@module  config.pc_default
@summary PC模拟器默认配置文件（当 PROJECT 无对应配置时回退）
@version 1.2
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "PC",         -- PC 模拟器
    chip = "PC",         -- 虚拟芯片
    baseboard = "PC",

    -- ===== 引脚功能复用（模拟器无真实引脚）=====
    pins = {},

    -- ===== 硬件配置（模拟器虚拟硬件）=====
    hw = {
        -- 屏幕: 模拟 ST7796 SPI 4寸 320×480
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,      -- SPI 端口 0
                pin_rst = 36,            -- 复位引脚
                direction = 0,           -- 0° 方向
                w = 320,                 -- 水平分辨率
                h = 480,                 -- 竖直分辨率
            },
            need_buffer = false,         -- SPI 屏不需要帧缓冲
            screen_size = 4.0,           -- 4寸屏
            font = { size = 14 },        -- 低分屏用 14 号字
            backlight = {
                pwm_ch = 0,              -- PWM 通道 0
                pwm_freq = 1000,         -- 1kHz
            },
        },
        -- 触摸: 模拟 GT911 I2C 端口0
        tp = {
            model = "tp_gt911",
            params = {
                port = 0,                -- I2C 端口 0
                pin_rst = 26,            -- 复位引脚
                pin_int = gpio.WAKEUP0,  -- 唤醒引脚用作中断
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    -- PC 模拟器: 仅以太网可用
    features = {
        ethernet = true,                 -- 启用以太网
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_ethernet_settings = true,   -- 设置页以太网入口（PC 有虚拟以太网）
        show_storage_settings = true,    -- 设置页存储空间入口
    },
}
