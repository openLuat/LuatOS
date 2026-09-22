--[[
@module  config.pc_default
@summary PC模拟器默认配置文件（当 PROJECT 无对应配置时回退）
@version 2.0
@date    2026.09.21
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]

-- ============================================================================
-- ⚠️ 加载期安全兜底（本文件必须能在【真机】上安全加载完成）
--
-- 本文件名义上是"PC 模拟器回退配置"，但 core/platform_loader.lua 头部那段
-- 【编译清单】里的 require("pc_default") / require("eng_xxx") 是给编译系统做
-- 静态分析用的，注释写着"运行时无害"—— 实际上它们在真机上也【真的会执行】。
-- 所以本文件的顶层代码必须能在真机固件上安全跑完，否则直接打挂 main 协程。
--
-- 本工程统一走 display 库的 RGB 驱动（hw.lcd.model = "lcd_display_rgb"），
-- 不再依赖 SPI 屏专用的 C 库 lcd（lcd 随 core 提供，仓库里没有
-- script/libs/lcd.lua）。历史教训：早期这里写的是 SPI 屏驱动（ST7796）且顶层引用
-- lcd.HWID_0，在未注册 lcd 库的 core 上启动即崩：
--     pc_default.luac:-1: attempt to index a nil value (field 'lcd')
--     Lua VM exit!! reboot in 15000ms
-- 而 .luac 是 strip 编译的（无行号/无 upvalue 名），该错误会伪装成"某个表的
-- lcd 字段是 nil"，极易把排查方向带偏。
--
-- 结论：本文件（及所有 config）顶层禁止直接索引【可选 C 库】（lcd 等）；
--       必须用到的运行时全局一律用 rawget(_G, ...) 兜底取值。
-- ============================================================================
-- 运行时可选全局的兜底取值（PC 模拟器/真机都安全）
local gpio = rawget(_G, "gpio") or { WAKEUP0 = 0 }

return {
    -- ===== 顶层信息 =====
    name = "PC",         -- PC 模拟器
    chip = "PC",         -- 虚拟芯片
    baseboard = "PC",

    -- ===== 引脚功能复用（模拟器无真实引脚）=====
    pins = {},

    -- ===== 硬件配置（模拟器虚拟硬件）=====
    hw = {
        -- 屏幕: 与真机板型统一，走 display 库 RGB 驱动
        -- （PC 模拟器下 lcd_display_rgb.init 检测到 rtos.bsp()=="PC" 会跳过
        --   display.init，避免与 AirUI 的 SDL2 窗口重复；分辨率由 AirUI 决定）
        lcd = {
            model = "lcd_display_rgb",   -- 本工程统一 RGB 驱动（内部走 display.init）
            params = {
                interface = "rgb",       -- RGB 接口
                pin_rst = 36,            -- 复位引脚（模拟器无实际接线）
                w = 320,                 -- 水平分辨率
                h = 480,                 -- 竖直分辨率
                -- RGB 时序（hbp/hspw/hfp/vbp/vspw/vfp/bus_speed）由真机板型 config 提供
            },
            need_buffer = false,         -- 模拟器不启用帧缓冲（与 platform_loader 的 PC 内联配置一致）
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
