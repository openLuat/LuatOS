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

-- ============================================================================
-- ⚠️ 加载期安全兜底（本文件必须能在【真机】上安全加载完成）
-- 同 factory_new 版本：core/platform_loader.lua 的"编译清单"里的 require 在
-- 真机上也真的会执行，而真机固件不一定注册 SPI 用的 lcd 库（C 库，随 core）。
-- lcd 缺失时 `port = lcd.HWID_0` 抛 nil 索引 → main 协程挂 → Lua VM exit；
-- 且 .luac 被 strip，日志会伪装成 `(field 'lcd')` + 行号 -1。
-- ============================================================================
local lcd  = rawget(_G, "lcd")  or _G.lcd  or { HWID_0 = 0, RGB = 1 }
local gpio = rawget(_G, "gpio") or _G.gpio or { WAKEUP0 = 0 }

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

    -- ===== 统一网络配置（优先级从高到低）=====
    -- PC 模拟器没有真实网络，由 platform_loader 自行设置 ETH0 网卡
    -- network 段留空，表示无 exnetif 初始化需求

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_ethernet_settings = true,   -- 设置页以太网入口（PC 有虚拟以太网）
        show_storage_settings = true,    -- 设置页存储空间入口
    },
}
