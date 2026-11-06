--[[
@module  conf
@summary SkyLift 雪山索道运营大屏 - 板级与业务参数
@version 1.0
@date    2026.11.06
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51
]]
return {
    W = 1024,
    H = 600,

    name    = "SkyLift 雪山索道",
    brand   = "SKYLIFT",
    slogan  = "云脊雪场 · 索道运营中枢",
    version = "1.0.0",

    resort = {
        name     = "云脊雪场",
        site     = "北坡 · 2 号沟",
        altitude = 1820,      -- 雪场基准海拔（m）
        top      = 2480,      -- 上站海拔（m）
        drop     = 620,       -- 垂直落差（m）
        opened   = "2019.12", -- 开业时间，用于计算运营年限
        slopes   = 9,         -- 雪道总数
    },

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 80,
        min     = 10,
    },

    -- GT911：与 factory/config/eng_8607_10i_v0.lua 对齐
    touch = {
        port    = 1,          -- I2C1（SCL=GPIO39 / SDA=GPIO38）
        pin_rst = 14,         -- TP_RST
        pin_int = 51,         -- TP_INT = WAKEUP
    },

    -- hzfont 按字号逐个加载（字号清单见 theme.SZ）
    font = {
        size       = 16,
        cache_size = 1024,
        antialias  = 1,
    },

    sim = {
        interval_ms = 1000,   -- 采样周期
        history     = 48,     -- 每条曲线保留的样本数
        min_per_tick = 2,     -- 每次采样推进的“雪场分钟”
        guest_per_min_max = 42, -- 客流高峰时的到客率（人/分钟）
    },

    anim = {
        frame_ms = 110,       -- 缆车 / 雪粒动画帧
        slow_ms  = 440,       -- 天空 / 雪雾 / 山体慢刷新帧
    },

    -- ===== 索道线路 =====
    -- cabins: 动画里同时在线的缆车数（也用于运力估算）
    lifts = {
        { key = "a", name = "A 主索道", type = "8 人吊厢", short = "A",
          cabins = 5, seats = 8, length = 1840, towers = 14,
          speed = 5.0, max_speed = 6.0, bottom = 1860, top = 2480, color = 0x4FE3D8 },
        { key = "b", name = "B 中级道", type = "6 人吊椅", short = "B",
          cabins = 4, seats = 6, length = 1120, towers = 9,
          speed = 3.6, max_speed = 5.0, bottom = 1880, top = 2160, color = 0x8FB8FF },
        { key = "c", name = "C 初级魔毯", type = "魔毯", short = "C",
          cabins = 1, seats = 1, length = 260, towers = 0,
          speed = 1.2, max_speed = 1.6, bottom = 1850, top = 1884, color = 0xFFC24B },
    },

    -- ===== 雪道 =====
    slopes = {
        { key = "beginner", name = "新手道",  level = "初级", len = 420,  grad = 8,  target = 55, groom = "07:10" },
        { key = "mid",      name = "云杉道",  level = "中级", len = 980,  grad = 18, target = 70, groom = "06:40" },
        { key = "expert",   name = "断崖道",  level = "高级", len = 1450, grad = 32, target = 85, groom = "06:10" },
        { key = "trail",    name = "林间野雪", level = "越野", len = 2100, grad = 26, target = 40, groom = "不压雪" },
    },

    -- ===== 造雪机 =====
    guns = {
        { key = "g1", name = "1 号造雪机", sector = "新手道", x = "上站平台", rate = 14 },
        { key = "g2", name = "2 号造雪机", sector = "云杉道", x = "中段 6 塔", rate = 18 },
        { key = "g3", name = "3 号造雪机", sector = "断崖道", x = "上段 12 塔", rate = 16 },
    },

    -- ===== 设备 =====
    devices = {
        { key = "drive",   name = "主驱动",   icon = "drive",   on = true,  note = "变频主电机 380V",  w = 185 },
        { key = "backup",  name = "备用电机", icon = "motor",   on = false, note = "柴油应急驱动",      w = 0 },
        { key = "gun",     name = "造雪系统", icon = "gun",     on = true,  note = "3 台风机造雪机",    w = 96 },
        { key = "heater",  name = "除冰加热", icon = "heater",  on = true,  note = "轮组 / 抱索器加热", w = 34 },
        { key = "light",   name = "夜间照明", icon = "light",   on = false, note = "沿线 46 盏 LED",     w = 52 },
        { key = "speaker", name = "广播系统", icon = "speaker", on = true,  note = "站台 / 雪道分区",   w = 8 },
    },

    -- ===== 机械体检项 =====
    -- lo/hi 为关注区间，超出即告警
    health = {
        { key = "mtemp",  name = "主电机温度", unit = "℃",  dec = 1, base = 58.0, jitter = 0.35, lo = 30, hi = 78, dhi = 88 },
        { key = "oil",    name = "减速机油压", unit = "bar", dec = 2, base = 3.20, jitter = 0.02, lo = 2.60, hi = 4.00, dlo = 2.20 },
        { key = "rope",   name = "钢绳张力",   unit = "kN",  dec = 1, base = 242.0, jitter = 1.2, lo = 210, hi = 280, dhi = 310 },
        { key = "brake",  name = "制动间隙",   unit = "mm",  dec = 2, base = 1.40, jitter = 0.01, lo = 0.80, hi = 2.00, dhi = 2.60 },
        { key = "hydro",  name = "液压油温",   unit = "℃",  dec = 1, base = 42.0, jitter = 0.30, lo = 25, hi = 65, dhi = 75 },
    },

    -- 主页体检项顺序（其余在设置页）
    home_health = { "mtemp", "rope", "oil" },

    weather = {
        base_temp = -6.4,     -- 站台气温
        base_wind = 4.2,      -- 风速 m/s
        base_hum  = 72,       -- 相对湿度 %
        base_vis  = 12.0,     -- 能见度 km
        wind_warn = 12,       -- 降速阈值
        wind_stop = 18,       -- 停运阈值
    },

    -- 定时注入的“事件”，让演示有起伏
    events = {
        { after = 22,  text = "山脊阵风 14.6 m/s，索道自动降速", level = "warn" },
        { after = 46,  text = "周末客流高峰，A 线站台排队超过 180 人", level = "warn" },
        { after = 84,  text = "2 号造雪机水压不足，自动停机", level = "danger", gun = "g2", off = true },
        { after = 128, text = "断崖道雪深低于警戒线，已限制开放", level = "warn" },
        { after = 168, text = "夜间压雪完成，雪道雪面恢复", level = "ok", groom = true },
    },
}
