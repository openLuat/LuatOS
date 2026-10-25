--[[
@module  conf
@summary 烘干室智能控制大屏 - 板级与业务参数
@version 1.0
@date    2026.10.24
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51
]]
return {
    W = 1024,
    H = 600,

    name    = "烘干室智能控制",
    version = "1.0.0",

    backlight = {
        pwm_ch = 3,
        freq   = 1000,
        default = 80,
        min    = 10,
    },

    font = {
        size       = 16,
        cache_size = 4096,
        antialias  = 1,
    },

    -- ===== 坚果烘干库（不同种类适用的温度/时长）=====
    -- kind 决定 UI 里的坚果剪影：walnut 核桃 / almond 杏仁 / cashew 腰果 /
    -- hazel 榛子 / peanut 花生 / pistachio 开心果
    nuts = {
        { name = "核桃",   temp_min = 55, temp_max = 60, hours = 36, color = 0xB98A57, kind = "walnut" },
        { name = "杏仁",   temp_min = 50, temp_max = 55, hours = 18, color = 0xE2B57F, kind = "almond" },
        { name = "腰果",   temp_min = 50, temp_max = 55, hours = 10, color = 0xF0D9A8, kind = "cashew" },
        { name = "榛子",   temp_min = 45, temp_max = 50, hours = 16, color = 0x9A6B3F, kind = "hazel" },
        { name = "花生",   temp_min = 45, temp_max = 50, hours = 10, color = 0xD9A066, kind = "peanut" },
        { name = "开心果", temp_min = 50, temp_max = 55, hours = 14, color = 0x8FBF6A, kind = "pistachio" },
    },

    sim = {
        interval_ms = 1200,
        history_n   = 60,           -- 波形采样点数（越多折线越细密）
        dry_minutes_per_tick = 6,   -- 演示加速：每个刷新周期算 6 分钟烘干时间
        room_temp   = 25,           -- 停机后回落的室温
    },

    alarm = {
        max_log       = 20,
        anomaly_ticks = 20,
        anomaly_every = 45,
    },
}
