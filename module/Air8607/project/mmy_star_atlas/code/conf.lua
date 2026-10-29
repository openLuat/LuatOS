--[[
@module  conf
@summary 星野观测台 - 板级与业务参数
@version 1.0
@date    2026.10.28
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51
]]
return {
    W = 1024,
    H = 600,

    name    = "星野观测台",
    en_name = "STAR ATLAS",
    version = "1.0.0",

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 82,
        min     = 8,
    },

    font = {
        size       = 16,
        cache_size = 4096,
        antialias  = 1,
    },

    -- ===== 观测站点（可触摸修改，范围见 settings）=====
    site = {
        name    = "青海 · 冷湖",
        bortle  = 2,              -- 波特尔暗天等级 1..9
        lat     = 38.60,
        lon     = 93.30,
        elev    = 2780,
        tz      = 8,              -- 时区（小时）
    },

    -- ===== 时间流速（星图演示用；1 = 真实时间）=====
    time = {
        speeds   = { 1, 60, 300, 1800, 7200 },   -- 倍率档位
        default  = 3,                            -- 默认 300x
        start_hour = 20,                         -- 仿真起始当地时间（若系统时间不可信）
    },

    sky = {
        mag_limit   = 3.2,     -- 星等极限（可调 1.0 ~ 5.0）
        radius      = 232,     -- 星图半径（像素）
        refresh_ms  = 120,     -- 星图重绘周期
        labels      = true,    -- 星座名标注
        lines       = true,    -- 星座连线
    },

    session = {
        max_queue = 6,
    },

    toast = { ms = 2200 },
}
