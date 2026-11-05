--[[
@module  conf
@summary AeroDeck 机坪运行指挥大屏 - 板级与业务参数
@version 1.0
@date    2026.11.05
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51
]]
return {
    W = 1024,
    H = 600,

    name    = "AeroDeck 机坪运行指挥",
    brand   = "AERODECK",
    slogan  = "机坪运行指挥 · 夜航值守",
    version = "1.0.0",

    airport = {
        name   = "HZ 北机坪",
        term   = "T2",
        runway = "18L / 36R",
        shift  = "夜班 20:00 - 08:00",
    },

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 80,
        min     = 10,
    },

    -- GT911：与 factory/config/eng_8607_10i_v0.lua 对齐
    touch = {
        port       = 1,          -- I2C1（SCL=GPIO39 / SDA=GPIO38）
        pin_rst    = 14,         -- TP_RST
        pin_int    = 51,         -- TP_INT = WAKEUP
        gpio_reset = nil,        -- 本板由 tp.init 处理复位
        polling    = true,       -- 中断驱动 I2C 易"仅触摸时报错"，轮询可根治
        debug      = true,       -- 打印触摸坐标，区分"驱动没数据"和"UI 不响应"
    },

    -- hzfont 只按已加载字号出字，界面上用到的字号必须全部载入（见 theme.SZ）
    font = {
        size       = 16,
        cache_size = 1024,
        antialias  = 1,
    },

    sim = {
        interval_ms = 1500,   -- 采样/推理周期
        history     = 48,     -- 每项气象参数保留样本数
        min_per_tick = 2,     -- 每次采样推进的机坪"分钟"（让航班状态可见地推进）
        start_min   = 20 * 60 + 12,  -- 演示起始时刻：20:12
    },

    anim = {
        frame_ms = 110,   -- 雷达扫描 / 航班滑行帧
        blink_ms = 22,    -- 告警灯闪烁分频（frame 计数）
    },

    -- ===== 保障节点（顺序即流程，index 表示已完成个数）=====
    nodes = {
        { key = "bridge", name = "靠桥",   tag = "ONB", note = "廊桥对接、轮挡放置" },
        { key = "deboard", name = "下客",  tag = "DEB", note = "旅客下机、清点人数" },
        { key = "clean",  name = "保洁",   tag = "CLN", note = "客舱清洁、更换头片" },
        { key = "cater",  name = "配餐",   tag = "CAT", note = "餐车对接、冷藏补货" },
        { key = "fuel",   name = "加油",   tag = "FUE", note = "加注航油、签署油单" },
        { key = "bag",    name = "装行李", tag = "BAG", note = "腹舱装载、复核重量" },
        { key = "board",  name = "登机",   tag = "BRD", note = "旅客登机、核对登机牌" },
        { key = "push",   name = "关舱推出", tag = "PUS", note = "关舱门、拖车推出" },
    },

    -- ===== 机位（ang 为雷达方位角，rad 为 0~1 归一化半径）=====
    stands = {
        { id = "A01", wide = false, ang = 205, rad = 0.72 },
        { id = "A02", wide = false, ang = 216, rad = 0.55 },
        { id = "A03", wide = false, ang = 228, rad = 0.72 },
        { id = "A04", wide = false, ang = 240, rad = 0.55 },
        { id = "A05", wide = false, ang = 252, rad = 0.72 },
        { id = "A06", wide = false, ang = 264, rad = 0.55 },
        { id = "A07", wide = false, ang = 276, rad = 0.72 },
        { id = "A08", wide = true,  ang = 292, rad = 0.55 },
        { id = "A09", wide = false, ang = 306, rad = 0.72 },
        { id = "A10", wide = true,  ang = 320, rad = 0.55 },
        { id = "A11", wide = false, ang = 334, rad = 0.72 },
        { id = "A12", wide = true,  ang = 348, rad = 0.55 },
    },

    -- ===== 航班（演示航班时刻表）=====
    -- node: 已完成的保障节点数量 0~8；delay: 当前延误分钟
    flights = {
        { cs = "CZ3841", airline = "南方航空", type = "A320", gate = "A03", std = "20:35",
          pax = 148, bags = 126, fuel = 86, node = 6, delay = 0,  deice = false },
        { cs = "MU5102", airline = "东方航空", type = "B738", gate = "A05", std = "20:40",
          pax = 162, bags = 143, fuel = 72, node = 5, delay = 6,  deice = false },
        { cs = "HU7821", airline = "海南航空", type = "A333", gate = "A08", std = "20:45",
          pax = 268, bags = 232, fuel = 64, node = 3, delay = 12, deice = true  },
        { cs = "CA1301", airline = "中国国航", type = "B738", gate = "A02", std = "20:55",
          pax = 155, bags = 138, fuel = 55, node = 2, delay = 0,  deice = false },
        { cs = "MF8312", airline = "厦门航空", type = "A320", gate = "A06", std = "21:05",
          pax = 141, bags = 118, fuel = 48, node = 7, delay = 0,  deice = false },
        { cs = "3U8821", airline = "四川航空", type = "A319", gate = "A09", std = "21:15",
          pax = 122, bags = 104, fuel = 40, node = 1, delay = 0,  deice = false },
        { cs = "ZH9012", airline = "深圳航空", type = "B738", gate = "A11", std = "21:25",
          pax = 158, bags = 131, fuel = 33, node = 0, delay = 0,  deice = false },
        { cs = "GJ8806", airline = "长龙航空", type = "A320", gate = "A04", std = "21:40",
          pax = 136, bags = 112, fuel = 28, node = 0, delay = 0,  deice = false },
    },

    -- ===== 跑道气象阈值 =====
    wx = {
        vis = { min = 200, max = 5000, lo = 800, hi = 3000 },      -- 能见度 m
        wind = { min = 0, max = 25, lo = 12, hi = 10 },             -- 风速 m/s（lo 为告警值）
        rvr = { min = 150, max = 2000, lo = 550, hi = 1400 },       -- 跑道视程 m
        temp = { min = -20, max = 25, lo = 0, hi = 8 },             -- 机坪温度 ℃（低于 lo 需除冰）
        gust = { min = 0, max = 20 },                               -- 阵风 m/s
        -- 跑道状态：影响刹车效应与除冰需求
        states = {
            { key = "dry",  name = "干跑道", mu = 0.62, deice = 0 },
            { key = "wet",  name = "湿跑道", mu = 0.42, deice = 0 },
            { key = "slush", name = "雪浆",  mu = 0.28, deice = 2 },
            { key = "ice",  name = "结冰",   mu = 0.16, deice = 3 },
        },
        -- 风向扇区（跑道 18 端进近）
        sectors = {
            { name = "北风", from = 315, to = 45 },
            { name = "东风", from = 45,  to = 135 },
            { name = "南风", from = 135, to = 225 },
            { name = "西风", from = 225, to = 315 },
        },
    },

    -- ===== 机坪资源 =====
    resources = {
        { key = "deice",  name = "除冰车",   icon = "deice", total = 2, used = 1 },
        { key = "fuel",   name = "加油车",   icon = "fuel",  total = 3, used = 2 },
        { key = "bus",    name = "摆渡车",   icon = "bus",   total = 4, used = 2 },
        { key = "bag",    name = "行李拖车", icon = "bag",   total = 6, used = 4 },
    },

    -- ===== 演示事件（按 tick 注入，让画面有起伏）=====
    events = {
        { after = 6,   level = "warn",   text = "北风加大，A08 宽体机除冰排队" },
        { after = 14,  level = "danger", text = "能见度跌破 800m，启动低能见运行" },
        { after = 24,  level = "warn",   text = "MU5102 配餐延误 6 分钟" },
        { after = 34,  level = "ok",     text = "能见度回升，解除低能见运行" },
    },
}
