--[[
@module  conf
@summary 星河一号 · 发射指挥中心 - 板级参数与任务时序数据
@version 1.0
@date    2026.11.04
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51
  功放使能 AUDIOPA_EN = GPIO73（高有效）
]]
return {
    W = 1024,
    H = 600,

    name    = "星河一号 · 发射指挥中心",
    en_name = "MMY MISSION CONTROL",
    version = "1.0.0",

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 84,
    },

    font = {
        size       = 16,
        cache_size = 4096,
        antialias  = 1,
    },

    -- ===== 任务参数 =====
    mission = {
        vehicle    = "星河一号",
        vehicle_en = "GALAXY-1",
        payload    = "通信试验卫星 · 1.2t",
        pad        = "LC-39A",
        window     = "01:20",
        flight_speed = 6,      -- 飞行段任务时间压缩倍数（1 秒 = 6 秒任务时间）
        standby_t  = -180,     -- 待命时显示的倒计时读数
        count_from = -10,      -- 终端倒计时起点
        orbit_t    = 260,      -- 入轨时刻（任务时间，秒）
        check_gap  = 0.40,     -- 自检每一项的间隔（秒）
        check_hold = 0.9,      -- 自检完成后停留多久开始倒计时
        auto_idle  = 6,        -- 待命静置多久自动演示
        auto_after = 9,        -- 入轨/中止后停留多久自动重来
        orbit_alt  = 200,      -- 入轨高度 km
        orbit_vel  = 3400,     -- 入轨速度 m/s（演示用）
    },

    -- ===== 起飞前系统自检项（8 项）=====
    checks = {
        "一级增压", "航电总线", "液压舵机", "遥测链路",
        "塔架撤收", "气象窗口", "测控跟踪", "逃逸系统",
    },

    -- ===== 飞行时序（任务时间秒）=====
    events = {
        { t = -10, name = "终端倒计时",  key = "terminal" },
        { t = -3,  name = "主发动机点火", key = "ignition" },
        { t = 0,   name = "起飞",        key = "liftoff"  },
        { t = 12,  name = "程序转弯",    key = "pitch"    },
        { t = 58,  name = "通过最大动压", key = "maxq"     },
        { t = 150, name = "一级分离",    key = "sep1"     },
        { t = 152, name = "二级点火",    key = "ignite2"  },
        { t = 175, name = "整流罩分离",  key = "fairing"  },
        { t = 230, name = "二级关机",    key = "seco"     },
        { t = 260, name = "载荷入轨",    key = "orbit"    },
    },

    -- ===== 遥测关键帧（任务时间, 高度 km, 速度 m/s）=====
    telemetry = {
        {   0,   0.0,    0 },
        {   8,   0.15,   42 },
        {  20,   1.2,   140 },
        {  40,   5.5,   320 },
        {  58,  12.0,   460 },
        {  80,  24.0,   700 },
        { 110,  42.0,   980 },
        { 150,  68.0,  1650 },
        { 160,  78.0,  1750 },
        { 200, 120.0,  2400 },
        { 230, 165.0,  2900 },
        { 260, 200.0,  3400 },
    },

    -- ===== 刷新节流（毫秒）=====
    tick = {
        loop_ms  = 33,     -- 主循环
        pad_ms   = 66,     -- 发射台动态层（约 15fps）
        chart_ms = 200,    -- 弹道曲线 5Hz
        gauge_ms = 250,    -- 余量条 4Hz
        text_ms  = 120,    -- 文字
    },

    toast = { ms = 2200 },
}
