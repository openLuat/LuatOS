--[[
@module  ev_config
@summary 电车充电站实时状态大屏 - 全局配置（硬件 / 布局 / 配色 / 播报参数）
@version 1.0
@date    2026.10.23
@board   Air8607 + 10寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸 + 内置 DAC + HT6873 功放

=== 视觉取向：科技简洁风 ===
深空底色 + 少量青色光斑，卡片只保留 1px 细描边和一条状态色条，
不用渐变块、不用阴影堆叠。每个桩位用「一节电池」表达电量：
外壳 + 正极 + 5 段电量格，充电中逐段点亮并动态推进，一眼可读。
]]
local M = {}

-- ==================== 硬件 ====================
M.HW = {
    screen = {
        w = 1024, h = 600,
        pin_rst = 15,        -- LCD_DISP / 复位
        pin_pwr = 17,        -- LCD 供电使能（低有效）
        pwm_ch = 3,          -- 背光 PWM3 (GPIO13)
        pwm_freq = 1000,
        i2c_id = 1,          -- GT911 所在 I2C
    },
    tp = {
        model = "gt911",
        port = 1,
        pin_rst = 14,
        pin_int = 51,
    },
    -- Air8607 10寸板：芯片内置 DAC 播放，PA 为 HT6873，高电平使能
    audio = {
        model = "dac",
        pa_ctrl = 73,        -- AUDIOPA_EN = GPIO73
        pa_on_level = 1,
        dac_delay = 6,
        pa_delay = 10,
        volume = 30,         -- 0~100
    },
}

-- ==================== 业务参数 ====================
M.PILE_COUNT = 10
M.DEFAULT_INTERVAL_MIN = 10     -- 默认定时播报间隔（分钟）
M.MIN_INTERVAL_MIN = 1
M.MAX_INTERVAL_MIN = 99
M.QUICK_MINUTES = { 5, 10, 15, 30 }

-- 需求原文：XX号充电桩充电完成，请及时驶离，超时将产生费用
M.TTS_DONE_FMT = "%d号充电桩充电完成，请及时驶离，超时将产生费用"

-- 手动播报的常用短语（点击即填入输入框，摆脱中文输入法依赖）
M.QUICK_PHRASES = {
    "请勿占用充电车位",
    "充电已完成，请及时驶离",
    "本区域即将闭站，请尽快挪车",
    "感谢配合，祝您出行愉快",
}

-- ==================== 布局（1024x600） ====================
M.LAYOUT = {
    top_h = 68,
    -- 桩位卡片：5 列 x 2 行
    card_x = 21, card_y = 78,
    card_w = 186, card_h = 150,
    gap_x = 13, gap_y = 12,
    -- 底部控制区
    panel_x = 20, panel_y = 398,
    panel_w = 984, panel_h = 186,
    -- 电池图形（相对卡片）
    batt_x = 12, batt_y = 44, batt_w = 110, batt_h = 48,
}

-- ==================== 配色 ====================
M.C = {
    -- 底色 / 结构
    bg         = 0x070E18,   -- 全屏底色（深空）
    bg2        = 0x0A1524,   -- 底色下沿
    panel      = 0x0F1C2E,   -- 卡片 / 面板
    panel2     = 0x152740,   -- 次级面板 / 输入框
    line       = 0x1D3450,   -- 细描边
    line2      = 0x2A4A6E,   -- 重描边 / 电池外壳
    -- 文字
    text       = 0xDCE9F8,
    text2      = 0x8AA6C6,
    text3      = 0x55708F,
    white      = 0xFFFFFF,
    -- 状态：空闲
    slate      = 0x647B96,
    slate_soft = 0x18273A,
    slate_deep = 0x9DB3CB,
    -- 状态：充电中（科技青）
    cyan       = 0x2FD8F5,
    cyan_soft  = 0x10323F,
    cyan_deep  = 0x8DEEFF,
    -- 状态：充电完成（荧光绿）
    lime       = 0x3BE08A,
    lime_soft  = 0x0E3423,
    lime_deep  = 0x86F7BE,
    -- 强调 / 告警
    amber      = 0xFFB020,
    danger     = 0xFF6B5B,
}

-- 每个桩位默认车位编号（A-01 ~ A-10）
function M.bay_name(i)
    return string.format("A-%02d", i)
end

return M
