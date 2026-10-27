--[[
@module  conf
@summary ReefOS 珊瑚礁生态缸大屏 - 板级与业务参数
@version 1.0
@date    2026.10.27
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51
]]
return {
    W = 1024,
    H = 600,

    name    = "ReefOS 珊瑚礁生态缸",
    brand   = "REEFOS",
    slogan  = "珊瑚礁生态缸 · 智能管家",
    version = "1.0.0",

    tank = {
        name   = "混养缸",
        volume = 900,      -- 主缸水体（L）
        site   = "客厅 · 东墙",
        start  = "2024.03", -- 开缸时间，用于计算缸龄
    },

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 82,
        min     = 10,
    },

    -- GT911：与 factory/config/eng_8607_10i_v0.lua 对齐
    touch = {
        port       = 1,          -- I2C1（SCL=GPIO39 / SDA=GPIO38）
        pin_rst    = 14,         -- TP_RST
        pin_int    = 51,         -- TP_INT = WAKEUP
        gpio_reset = nil,        -- 部分底板需要先把 RST 拉低再放开，本板由 tp.init 处理
        polling    = true,       -- 坐标在 TP 中断里突发读，中断驱动 I2C 易"仅触摸时报错"，轮询可根治
        debug      = true,       -- 打印触摸坐标，定位"驱动没数据"还是"UI 不响应"
    },

    -- hzfont 按字号逐个加载（字号清单见 theme.SZ），cache_size 是每个字号的字形缓存上限：
    -- 整屏用到的汉字有限，1024 已足够，六档字号合计不至于吃穿真机的 LVGL 堆
    font = {
        size       = 16,
        cache_size = 1024,
        antialias  = 1,
    },

    sim = {
        interval_ms = 1200,   -- 采样周期
        history     = 48,     -- 每项参数保留的样本数
        min_per_tick = 3,     -- 每次采样推进的水体“分钟”（自动喂食/换水周期用）
        feed_interval_min = 120,  -- 自动喂食间隔（水体分钟）
        water_interval_min = 4320, -- 建议换水间隔（水体分钟，3 天）
    },

    anim = {
        frame_ms = 130,   -- 生态缸动画帧（鱼/气泡）
        sway_ms  = 520,   -- 珊瑚/水面波光重建帧
    },

    -- ===== 光谱通道 =====
    spectrum = {
        channels = {
            { key = "blue",  name = "蓝",  color = 0x2E7BFF, hint = "珊瑚显色 / 光合作用" },
            { key = "white", name = "白",  color = 0xDFF6FF, hint = "观感亮度 / 生长" },
            { key = "uv",    name = "UV",  color = 0x9A6BFF, hint = "荧光蛋白激发" },
        },
        presets = {
            { name = "晨曦",  blue = 62, white = 28, uv = 45, note = "柔蓝渐亮，模拟日出" },
            { name = "正午",  blue = 55, white = 88, uv = 40, note = "全光谱高亮，生长期" },
            { name = "黄昏",  blue = 78, white = 34, uv = 62, note = "偏蓝暖收，促发色" },
            { name = "月光",  blue = 18, white = 4,  uv = 30, note = "夜间蓝光，观察夜行生物" },
            { name = "荧光",  blue = 30, white = 6,  uv = 96, note = "纯 UV 激发，珊瑚荧光" },
        },
        -- 默认值（全光谱）
        default = { blue = 55, white = 70, uv = 40 },
    },

    -- ===== 设备 =====
    devices = {
        { key = "pump",    name = "主循环泵", icon = "pump",    on = true,  note = "底缸循环 3200L/h" },
        { key = "wave",    name = "造浪泵",   icon = "wave",    on = true,  note = "交替浪 60%" },
        { key = "skimmer", name = "蛋白分离", icon = "skimmer", on = true,  note = "去除有机氮" },
        { key = "heater",  name = "加热棒",   icon = "heater",  on = true,  note = "目标 25.5℃" },
        { key = "chiller", name = "冷水机",   icon = "chiller", on = false, note = "目标 26.5℃" },
        { key = "uv",      name = "UV 杀菌",  icon = "uv",      on = false, note = "夜间 4 小时" },
    },

    -- ===== 生物库（不同生物类型的水质推荐窗口）=====
    bio = {
        { name = "SPS 硬珊瑚", temp = "25.0~26.5℃", sal = "1.025~1.026", kh = "7.5~8.5",  ca = "420~450", note = "需高光高流，Kh 波动小于 0.3/天" },
        { name = "LPS 软体珊瑚", temp = "25.0~27.0℃", sal = "1.024~1.026", kh = "8.0~9.5",  ca = "400~440", note = "忌强流直吹，可耐受轻度营养盐" },
        { name = "软珊瑚/海葵", temp = "24.5~27.0℃", sal = "1.023~1.026", kh = "8.0~11.0", ca = "380~430", note = "耐受度高，注意别被造浪打伤" },
        { name = "海水观赏鱼",  temp = "24.5~27.5℃", sal = "1.020~1.026", kh = "7.0~10.0", ca = "380~450", note = "盐度波动小于 0.002/天，检疫期单独养" },
    },

    -- ===== 水质参数定义 =====
    -- scale: 滑块整数 -> 实际值的换算倍率（滑块只支持整数）
    -- lo/hi: 正常区间；dlo/dhi: 报警门限
    metrics = {
        {
            key = "temp", name = "水温", unit = "℃", dec = 1, scale = 10,
            min = 18, max = 32, lo = 24.5, hi = 27.0, dlo = 23.0, dhi = 28.5,
            base = 25.6, jitter = 0.06,
            tip = "礁缸最稳的温度是 25~26℃，日波动控制在 ±0.5℃。升温过快会让珊瑚白化。",
        },
        {
            key = "sal", name = "盐度", unit = "SG", dec = 3, scale = 1000,
            min = 1.010, max = 1.040, lo = 1.024, hi = 1.026, dlo = 1.020, dhi = 1.030,
            base = 1.0250, jitter = 0.00008,
            tip = "比重 1.025 是天然海水水平。蒸发只会让盐度上升，务必用 RO 水补水而不是海水。",
        },
        {
            key = "ph", name = "pH", unit = "", dec = 2, scale = 100,
            min = 7.40, max = 8.80, lo = 7.90, hi = 8.40, dlo = 7.60, dhi = 8.60,
            base = 8.15, jitter = 0.008,
            tip = "白天光合作用消耗 CO₂，pH 会自然升高；夜里回落 0.1~0.2 属于正常节律。",
        },
        {
            key = "kh", name = "KH 碱度", unit = "dKH", dec = 1, scale = 10,
            min = 4.0, max = 15.0, lo = 7.5, hi = 9.5, dlo = 6.5, dhi = 11.0,
            base = 8.3, jitter = 0.03,
            tip = "KH 是珊瑚钙化的第一道门槛。用滴定泵少量多次补充，一天内波动别超过 0.3。",
        },
        {
            key = "ca", name = "钙", unit = "ppm", dec = 0, scale = 1,
            min = 300, max = 520, lo = 400, hi = 450, dlo = 360, dhi = 480,
            base = 422, jitter = 0.8,
            tip = "钙与 KH 要同步补：只补 KH 会让钙沉淀，只补钙会把碱度拉低。",
        },
        {
            key = "mg", name = "镁", unit = "ppm", dec = 0, scale = 1,
            min = 1100, max = 1500, lo = 1250, hi = 1400, dlo = 1150, dhi = 1450,
            base = 1330, jitter = 1.2,
            tip = "镁保持在 1300 上下，才能让钙和碱度稳定共存，否则两者会互相打架。",
        },
        {
            key = "no3", name = "硝酸盐", unit = "ppm", dec = 1, scale = 10,
            min = 0, max = 50, lo = 0.5, hi = 10.0, dlo = nil, dhi = 25.0,
            base = 2.4, jitter = 0.05,
            tip = "混养缸保持 2~5ppm 硝酸盐，SPS 缸追求更低。数值升高先查喂食量和分离器。",
        },
        {
            key = "po4", name = "磷酸盐", unit = "ppm", dec = 2, scale = 100,
            min = 0, max = 1.0, lo = 0.01, hi = 0.10, dlo = nil, dhi = 0.30,
            base = 0.035, jitter = 0.0015,
            tip = "磷酸盐超过 0.1ppm 容易爆藻并抑制钙化，用吸附剂或换水压下来。",
        },
    },

    -- 主页展示的参数顺序（其余在详情页切换查看）
    home_metrics = { "temp", "sal", "ph", "kh", "ca", "no3" },

    -- 鱼群档案（主页动画角色的名字与颜色）
    fishes = {
        { name = "小丑鱼",  color = 0xFF8A4B, size = 1.00, speed = 0.9 },
        { name = "蓝倒吊",  color = 0x4FA8FF, size = 1.15, speed = 0.7 },
        { name = "黄高鳍",  color = 0xFFD166, size = 0.85, speed = 1.1 },
    },

    -- 定时注入的“事件”，让演示有起伏
    events = {
        { after = 26, key = "temp",  delta = 1.9,  text = "加热棒回差过大，水温上升" },
        { after = 58, key = "sal",   delta = 0.0032, text = "连续蒸发未补水，盐度偏高" },
        { after = 92, key = "no3",   delta = 9.0,  text = "过量投喂，硝酸盐抬升" },
        { after = 124, key = "kh",   delta = -2.4, text = "滴定液见底，碱度下滑" },
    },
}
