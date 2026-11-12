--[[
@module  conf
@summary U盘FOTA升级(有UI界面版) 全局配置 —— 三板通用唯一入口
@version 1.0
@date    2026.11.11
@author  谌程
@usage
-- 适用模块：Air8603系列(W1~W5/M1~M5)、Air8605系列（同为Air160x平台，Lua API一致）
-- 屏幕均为 RGB 10寸 1024x600 + GT911 电容触摸（I2C1）
--
-- 换板子：只改 M.board 一行，两块板的触摸/上电时序差异全部关在下面的 PROFILES 表里
-- （TP_RST 14/72 两脚 lcd_tp.lua 会自动探测，即使板型选错也能摸，但仍建议选对）
-- 参数来源（仓库实测工程，非猜测）：
--   air8603 : module/Air8603/factory/config/eng_8603w1_10i_v0.lua（10个型号配置一致）
--   air8605 : module/Air8605/project/jq_weather_clock/code/conf.lua
--
-- 注意1：Air8603 配置文件头部注释写 TP_RST=GPIO72，但其 hw.tp（产测固件实际使用的值）
--        在全部10个型号配置里均为 pin_rst=14，以 hw.tp 为准取 GPIO14；
--        如个别批次触摸无反应，把 touch.pin_rst 改成 72 再试。
-- 注意2：hzfont 矢量字库每个字号都要 font_load，界面用到的字号必须全在 font_sizes 里
--        （漏了不报错，只会渲染成方框；最小16）
]]

local M = {}

-- ==================== 目标板选择 ====================
M.board = "air8603"   -- "air8603" | "air8605"

-- ==================== 各板 profile ====================
local PROFILES = {
    air8603 = {
        screen = {
            w = 1024, h = 600,
            pin_rst = 15,          -- LCD_DISP = PIN80 = GPIO15（显示使能）
            pin_pwr = nil,         -- 屏供电走 power_on 供电轨，无独立使能脚
            backlight = { pwm_ch = 3, freq = 1000, duty = 100 },
            rgb = { hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12, pclk_hz = 50 * 1000 * 1000 },
        },
        touch = { port = 1, pin_rst = 14, pin_int = 51 },  -- TP_RST=GPIO14(见文件头注意1) TP_INT=GPIO51
        power_on = {
            { pin = 12, level = 1 },              -- 5V_EN
            { pin = 56, level = 1, delay = 100 }, -- 9V_EN 等100ms就绪
            { pin = 44, level = 1 },              -- 12V_EN
            { pin = 52, level = 1 },              -- 5VOUT_EN
            { pin = 74, level = 1 },              -- SD_EN
            { pin = 58, level = 1, delay = 200 }, -- UVC_EN(U盘座供电) 拉高后200ms就绪
        },
        -- 板载 Air153D 外部硬件看门狗(喂狗脚 GPIO57 经NPN接WTDOG)；
        -- 上电即计时，不喂狗会周期性硬件复位，务必保持 enable=true
        hw = { ext_wdt_enable = true, ext_wdt_pin = 57 },
    },
    air8605 = {
        screen = {
            w = 1024, h = 600,
            pin_rst = 15,          -- LCD_DISP = GPIO15
            pin_pwr = nil,
            backlight = { pwm_ch = 3, freq = 1000, duty = 100 },
            rgb = { hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12, pclk_hz = 50 * 1000 * 1000 },
        },
        touch = { port = 1, pin_rst = 72, pin_int = 51 },  -- TP_RST=GPIO72 TP_INT=GPIO51(jq_weather_clock实测)
        power_on = {
            { pin = 44, level = 1 },              -- 12V_EN
            { pin = 12, level = 1 },              -- 5V_EN
            { pin = 56, level = 1 },              -- 9V_EN
            { pin = 74, level = 1 },              -- SD_EN
            { pin = 64, level = 1, delay = 50 },  -- 4G_RESET 拉高50ms
            { pin = 64, level = 0, delay = 120 }, -- 再拉低120ms完成复位
        },
        -- 8605 同样板载 Air153D 外部硬狗(官方文档原理图第11页, 出厂固件watchdog_app已喂)；
        -- 喂狗脚与8603一致为 GPIO57(见 Air8605/project/factory/app/common/watchdog_app.lua)
        hw = { ext_wdt_enable = true, ext_wdt_pin = 57 },
    },
}

local P = PROFILES[M.board]
if not P then
    error("conf.lua: 未知板型 " .. tostring(M.board) .. ", 可选: air8603/air8605")
end

-- ==================== 合并到顶层（业务代码只用顶层字段）====================
M.screen    = P.screen
M.touch     = P.touch
M.power_on  = P.power_on
M.hw        = P.hw or { ext_wdt_enable = false, ext_wdt_pin = nil }

-- 界面用到的字号必须全部在这里（hzfont 最小16，每个字号一份字体实例，别多加）
M.font_sizes = { 16, 20, 22, 26, 40 }

-- ==================== USB / U盘 ====================
M.usb = {
    id        = 0,          -- USB总线号，只有1条USB线填0
    pwr_pin   = 58,         -- U盘座供电使能(UVC_EN)：8603/8605均已实测GPIO58；自研板按原理图改
    mount     = "/udisk",   -- U盘挂载点
    suffix    = ".bin",     -- 只显示U盘根目录下该后缀的文件
    max_files = 30,         -- 列表最多展示条数（防止按钮过多占内存）
    block     = 4096,       -- 每次读入并写入fota分区的大小, 不应超过4K
    wait_timeout = 0,       -- UI版常驻主机模式等U盘, 不设超时(0=无限等)
}

-- ==================== 界面配色 / 布局 ====================
M.ui = {
    bg         = 0x0E1116,  -- 全屏背景
    panel      = 0x171D24,  -- 卡片/顶栏
    panel2     = 0x212933,
    row        = 0x1D2733,  -- 列表普通行
    row_sel    = 0x1B3A5C,  -- 列表选中行
    ink        = 0xE6EDF3,  -- 主文字
    ink2       = 0xA3B1BF,  -- 次文字
    ink3       = 0x6C7A88,  -- 弱提示
    accent     = 0x2F81F7,  -- 强调蓝(确认按钮/进度条/选中角标)
    ok         = 0x3FB950,
    warn       = 0xD29922,
    danger     = 0xF85149,
}

return M
