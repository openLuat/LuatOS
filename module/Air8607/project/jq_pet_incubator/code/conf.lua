--[[
@module  conf
@summary 宠物恒温箱 - 板级与业务参数
@version 1.0
@date    2026.10.28
@board   Air8607（Air1603）+ 10.1 寸 RGB 1024x600（免序列）+ GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15       LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）         触摸 I2C1（400kHz）pin_rst=14 pin_int=51
  功放使能 GPIO73（exaudio pa_ctrl）
]]
return {
    W = 1024,
    H = 600,

    name    = "宠物恒温箱",
    version = "1.0.0",

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 82,
        min     = 10,
    },

    font = {
        size       = 16,
        cache_size = 4096,
        antialias  = 1,
    },

    -- 报警音频：exaudio 走内置 DAC + HT6873 功放
    audio = {
        model       = "dac",
        pa_ctrl     = 73,
        pa_on_level = 1,
        vol         = 40,
        file        = "/luadb/alarm.wav",
        repeat_ms   = 2600,      -- 连续报警时的重复间隔
    },

    sim = {
        interval_ms   = 1000,    -- 数据刷新周期
        history_n     = 30,      -- 曲线采样点数
        anomaly_every = 24,      -- 每隔多少个 tick 注入一次异常（演示报警）
        anomaly_ticks = 14,      -- 异常持续时间
        tolerance     = 0.02,    -- 阈值判定的浮点容差
    },

    -- 阈值可调范围与默认值
    limits = {
        temp = { min = 10, max = 45, step = 0.5, dec = 1, def_low = 26.0, def_high = 30.0 },
        hum  = { min = 10, max = 95, step = 1,   dec = 0, def_low = 45,   def_high = 65   },
        gas  = { min = 0,  max = 50, step = 0.5, dec = 1, def_high = 5.0                  },
    },

    max_devices = 12,

    presets = {
        pets  = { "小米", "豆豆", "球球", "布丁", "奶糖", "团子", "年糕", "芝麻" },
        rooms = { "宠物房", "客厅", "阳台", "幼崽房", "隔离房", "阳光房" },
    },
}
