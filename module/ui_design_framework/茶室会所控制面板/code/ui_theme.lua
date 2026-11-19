--[[
主题令牌：暖夜 / 宣纸
T1：色板表本身不换引用，切主题只做键值原地覆盖（ui_widget 与各页面都持有 T.c）
T11：夜间 dim 各提亮一档，按 7:1 而不是 4.5:1 定；RGB565 抖动下 16 号小字掉得厉害
]]

local CFG = require "app_config"

local T = {}

T.FONT = CFG.FONT
T.mode = "night"

T.c = {}
for k in pairs({
    bg = 1, rail = 1, rail_on = 1, scrim = 1, text = 1, dim = 1, faint = 1,
    gold = 1, gold_dim = 1, celadon = 1, seal = 1, seal_txt = 1,
    line = 1, card_line = 1, panel = 1, seg_off = 1, track = 1, knob = 1,
    mask = 1, on_gold = 1, btn = 1, btn_on = 1, chip = 1, chip_on = 1, mark = 1,
    hl = 1, card = 1, card_in = 1,
}) do
    T.c[k] = 0xFFFFFF
end

local PAL = {
    night = {
        bg        = 0x0A0806,  -- 兜底底色，被背景图盖住
        rail      = 0x120D08,
        rail_on   = 0x2A2015,
        scrim     = 0x080604,
        text      = 0xF1E6D3,
        dim       = 0xBCAC91,
        faint     = 0x7A6C5A,
        gold      = 0xE2B979,
        gold_dim  = 0xA8895A,
        celadon   = 0x8FAE9B,
        seal      = 0xA8492F,
        seal_txt  = 0xF6E7D8,
        line      = 0x5C4C33,
        card_line = 0x6E5C42,
        panel     = 0x161009,
        seg_off   = 0x4A4032,
        track     = 0x2C251B,
        knob      = 0xFDF6E9,
        mask      = 0x050403,
        on_gold   = 0x231A0E,
        btn       = 0x1B140C,
        btn_on    = 0x3A2C18,
        chip      = 0x1D150D,
        chip_on   = 0x4A3719,
        mark      = 0x6B563A,
        hl        = 0xF1E6D3,  -- 按压水膜：夜色下提亮
        card      = 0x1B140C,  -- 夜间卡片底（与 btn 同色，照片模式下被子图盖住）
        card_in   = 0x161009,  -- 纸面卡内层（夜间不用）
    },
    paper = {
        bg        = 0xEFE6D6,
        rail      = 0xFBF6EC,
        rail_on   = 0xEADCC2,
        scrim     = 0xF6EEE0,
        text      = 0x2C241B,
        dim       = 0x6B5C49,
        faint     = 0x9A8A74,
        gold      = 0x8A6134,
        gold_dim  = 0x6E4E28,
        celadon   = 0x4E6B57,
        seal      = 0xA8492F,
        seal_txt  = 0xFFF6E8,
        line      = 0xB9A788,
        card_line = 0xC9B99B,
        panel     = 0xFBF6EC,
        seg_off   = 0xC3B49B,
        track     = 0xD8CCB8,
        knob      = 0xFFFDF7,
        mask      = 0x1B1410,
        on_gold   = 0xFFF8EC,
        btn       = 0xF3E9D6,
        btn_on    = 0xE7D3AE,
        chip      = 0xF0E6D2,
        chip_on   = 0xDFC99E,
        mark      = 0xC2AE8C,
        hl        = 0x2C241B,  -- 纸面上用水墨压深，白色膜看不见
        card      = 0xF3E9D6,  -- 纸面卡外框（1px 边线用 card_line 实心块表达）
        card_in   = 0xFFFDF7,  -- 纸面卡内层：比背景亮一档，靠明度差立起来
    },
}

-- 原地覆盖，不换表引用（T1）
function T.apply(mode)
    local p = PAL[mode] or PAL.night
    for k, v in pairs(p) do T.c[k] = v end
    T.mode = (PAL[mode] and mode) or "night"
end

--- 当前是否纸面主题（页面建卡时要按它分支：两套素材、两套字色）
function T.is_paper()
    return T.mode == "paper"
end

--[[
背景图：两套主题各一张，互不染色。

两版都必须是"自家的照片"：
  上一版宣纸是把夜景去饱和 + 提亮 + 叠 70~84% 暖白纱硬凑出来的，
  结果整屏一层灰雾——既没有夜色层次，也没有纸面干净。
  现在 bg_paper 是单独生成的晨光茶室，只做轻微提亮就够，
  与暗调夜图不共享任何处理链路。
]]
function T.bg_img()
    -- JPG 而不是 PNG：Air1603 硬件 PNG 解码不吃多 IDAT 块，
    -- PIL 存 512x300 的背景必然分块 → 真机整块空白（见 make_assets.py 顶部说明）
    if T.mode == "paper" then return "/luadb/bg_paper.jpg" end
    return "/luadb/bg_night.jpg"
end

T.apply("night")

return T
