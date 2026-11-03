--[[
@module  conf
@summary ROAST LAB 咖啡烘焙工坊 - 板级与业务参数
@version 1.0
@date    2026.10.30
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51
]]
return {
    W = 1024,
    H = 600,

    name    = "ROAST LAB 咖啡烘焙工坊",
    brand   = "ROAST LAB",
    slogan  = "智能曲线烘焙 · 批次管理",
    version = "1.0.0",

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 84,
        min     = 10,
    },

    -- GT911：与 wpl_drying_room / factory 的 eng_8607_10i_v0.lua 一致
    -- I2C1 在 main.power_on 里配置（400kHz、中断模式），这里只放 tp.init 参数
    touch = {
        port    = 1,
        pin_rst = 14,
        pin_int = 51,
        debug   = true,   -- 串口打印每次触摸坐标，定位完改成 false
    },

    -- hzfont 按字号逐个加载，字号清单见 theme.SZ
    font = {
        size       = 16,
        cache_size = 1024,
        antialias  = 1,
    },

    sim = {
        interval_ms = 500,   -- 采样周期
        dt_s        = 6,     -- 每次采样推进的烘焙秒数（演示加速）
        history_n   = 120,   -- 曲线采样点数（120 x 6s = 12 分钟）
        curve_div   = 2,     -- 每 2 次采样重绘一次曲线，降低绘制压力
        ambient     = 25.5,  -- 室温 / 生豆初始温度
        cool_target = 36,    -- 冷却目标温度
        max_t       = 720,   -- 曲线横轴最大时长（秒）
    },

    roast = {
        heat_default = 78,   -- 火力 %
        air_default  = 46,   -- 风门 %
        drum_default = 62,   -- 滚筒转速 rpm
        crack_gap    = 24,   -- 一爆到二爆的温升差（°C）
        hint = {
            ror_high   = 28,   -- 升温过快阈值 °C/min
            et_high    = 245,  -- 炉温偏高阈值
            air_low    = 12,   -- 排风不足阈值
            heat_low   = 22,   -- 火力过低阈值
        },
    },

    -- ===== 烘焙度色阶（按出豆豆温判定）=====
    levels = {
        { max = 190, name = "未发展", color = 0xCBB896 },
        { max = 200, name = "极浅烘", color = 0xD8B583 },
        { max = 208, name = "浅烘",   color = 0xC79862 },
        { max = 216, name = "中烘",   color = 0xA66D3C },
        { max = 226, name = "中深烘", color = 0x7A4623 },
        { max = 999, name = "深烘",   color = 0x4A2814 },
    },

    -- ===== 豆种档案 =====
    -- crack：一爆参考豆温  drop_min/max：推荐出豆豆温
    -- kind：豆形剪影  heat/air/drum：推荐烤炉参数
    beans = {
        {
            name = "耶加雪菲", en = "YIRGACHEFFE",
            origin = "埃塞俄比亚 · 科契尔", process = "水洗", altitude = "1900-2200m",
            flavor = "柑橘 / 茉莉 / 蜂蜜", level_hint = "浅烘",
            crack = 197, drop_min = 195, drop_max = 203, minutes = "9~11",
            heat = 78, air = 56, drum = 66, color = 0xD9A05B, kind = "long",
        },
        {
            name = "瑰夏", en = "GEISHA",
            origin = "巴拿马 · 波奎特", process = "日晒", altitude = "1600-1800m",
            flavor = "茉莉 / 蜜桃 / 荔枝", level_hint = "浅烘",
            crack = 195, drop_min = 193, drop_max = 201, minutes = "9~10",
            heat = 72, air = 62, drum = 64, color = 0xE3B36A, kind = "pea",
        },
        {
            name = "哥伦比亚", en = "COLOMBIA",
            origin = "哥伦比亚 · 惠兰", process = "水洗", altitude = "1700-1900m",
            flavor = "焦糖 / 坚果 / 柑橘", level_hint = "中烘",
            crack = 200, drop_min = 205, drop_max = 213, minutes = "10~12",
            heat = 80, air = 45, drum = 60, color = 0xC98B4B, kind = "round",
        },
        {
            name = "巴西喜拉多", en = "CERRADO",
            origin = "巴西 · 米纳斯", process = "半日晒", altitude = "1000-1200m",
            flavor = "可可 / 榛果 / 红糖", level_hint = "中烘",
            crack = 199, drop_min = 208, drop_max = 216, minutes = "11~13",
            heat = 82, air = 40, drum = 58, color = 0xB87A42, kind = "round",
        },
        {
            name = "曼特宁", en = "MANDHELING",
            origin = "印尼 · 苏门答腊", process = "湿刨", altitude = "1200-1500m",
            flavor = "草本 / 黑巧 / 雪松", level_hint = "中深烘",
            crack = 202, drop_min = 215, drop_max = 225, minutes = "12~14",
            heat = 84, air = 38, drum = 56, color = 0x8C5B33, kind = "flat",
        },
        {
            name = "云南保山", en = "YUNNAN",
            origin = "中国 · 云南保山", process = "水洗", altitude = "1400-1700m",
            flavor = "红糖 / 烤坚果 / 乌梅", level_hint = "中烘",
            crack = 198, drop_min = 206, drop_max = 214, minutes = "10~12",
            heat = 79, air = 48, drum = 62, color = 0xA9713C, kind = "long",
        },
    },

    -- ===== 历史曲线档案（演示数据，用于对比）=====
    archives = {
        { name = "耶加雪菲 #A17", date = "10-26", bean = 1, drop = 201.4, dur = 570,  score = 92 },
        { name = "哥伦比亚 #A16", date = "10-24", bean = 3, drop = 211.6, dur = 660,  score = 86 },
        { name = "曼特宁 #A15",   date = "10-22", bean = 5, drop = 219.8, dur = 780,  score = 79 },
    },
}
