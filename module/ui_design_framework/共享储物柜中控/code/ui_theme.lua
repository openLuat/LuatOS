--[[
@module  ui_theme
@summary 共享储物柜中控 - 设计令牌（色板 / 字号 / 圆角 / 屏幕基准）
@note    屏幕基准 1024×600（Air8607 10.1" 与 Air8601 7" 同为 1024×600）。
         色值与 docs/共享储物柜中控UI.html 的 :root / [data-theme=dark] 一一对应。
         HTML 的渐变、投影、动效在 RGB565 上无法逐像素还原，用纯色 + 分层矩形近似；
         字号做了一档合并（11~14px 的中文提到 16），因为 hzfont 是点阵，小字号会糊。
]]
local M = {}

M.W, M.H = 1024, 600

-- 屏幕分区（与 HTML 的 .bar 64 / .stage 480 / .foot 56 一致）
M.LAYOUT = {
    bar_h  = 64,
    body_y = 64,
    body_h = 480,
    foot_y = 544,
    foot_h = 56,
    pad    = 40,     -- .bar / .stage 的左右 padding
}

-- ==================== 色板（亮 / 暗两套） ====================
-- 两套的键必须完全一致：set_mode 是原地覆盖 M.c 的键值、不换表本身（T1），
-- 因为各页面在 require 时就已 `local C = T.c` 捕获了这张表的引用，换表等于让它们永远看旧色。
local LIGHT = {
    bg      = 0xFFF7F1,   -- --bg
    ink     = 0x16120F,   -- --ink
    ink2    = 0x7A7168,   -- --ink2
    ink3    = 0xB7AEA5,   -- --ink3
    line    = 0xEDE3D9,   -- --line
    line2   = 0xDCCFC2,   -- --line2
    card    = 0xFFFFFF,   -- --card
    white   = 0xFFFFFF,
    hi      = 0xFFFFFF,   -- --hi    悬停/高亮底
    press   = 0xFDF6EF,   -- --press 按下底

    orange  = 0xFF6B2C,   -- --orange
    orange_d= 0xF03A17,   -- --orange-d
    orange_l= 0xFFF3EC,   -- --orange-l
    teal    = 0x0FC2A5,   -- --teal
    teal_d  = 0x00967E,   -- --teal-d
    teal_l  = 0xEAFBF6,   -- --teal-l

    mute_bg = 0xF7F0E9,   -- --mute-bg
    mute_ln = 0xF0E7DE,   -- --mute-line
    cab     = 0xD3C6B8,   -- --cab 规格柜格图标

    ok      = 0x11A47F,
    err     = 0xD8402F,
}

-- 暗色：只换色值，不动结构与几何。
-- 两张入口卡仍是高饱和品牌色（HTML 里也没反相），
-- "橙=取、青=存"是一米内识别入口的锚点，不能丢。
local DARK = {
    bg      = 0x16120F,
    ink     = 0xF4EEE8,
    ink2    = 0xA79C91,
    ink3    = 0x7A6F66,   -- 比亮色提亮一档：RGB565 抖动 + 16 号小字容易糊成灰片（T11）
    line    = 0x332C25,
    line2   = 0x453B32,
    card    = 0x211C18,
    white   = 0xFFFFFF,
    hi      = 0x2A241F,
    press   = 0x332B25,

    orange  = 0xFF7F45,
    orange_d= 0xFF5A2B,
    orange_l= 0x3A2015,
    teal    = 0x1FD9B8,
    teal_d  = 0x00B098,
    teal_l  = 0x122A26,

    mute_bg = 0x26211C,
    mute_ln = 0x312A24,
    cab     = 0x6B6059,

    ok      = 0x2FD6AE,
    err     = 0xFF6B5A,
}

M.c = {}
M.mode = "light"

local function apply(src)
    for k, v in pairs(src) do M.c[k] = v end
end
apply(LIGHT)

M.MODES = { light = LIGHT, dark = DARK }

function M.set_mode(mode)
    M.mode = (mode == "dark") and "dark" or "light"
    apply(M.MODES[M.mode])
    return M.mode
end

function M.toggle()
    return M.set_mode(M.mode == "dark" and "light" or "dark")
end

-- 主题落盘（T9）：重启后保持上次选择。固件没开 fskv 时静默跳过，不影响启动。
function M.load_mode()
    local ok, v = pcall(function()
        if fskv and fskv.init then fskv.init() end
        return fskv.get("ui_mode")
    end)
    if ok and (v == "dark" or v == "light") then M.set_mode(v) end
    return M.mode
end

function M.save_mode()
    pcall(function() fskv.set("ui_mode", M.mode) end)
end

-- 字号档（hzfont 行高 = 字号 + 3）
-- HTML 用了 10.5~72 共十余档，这里合并到 10 档，兼顾观感与 flash：
--   13 只给纯 ASCII 小标签（PICK UP / 余6格 的数字），中文一律不小于 16。
M.f = {
    hero   = 72,   -- 首页卡标题
    h1     = 38,   -- 页面标题
    h2     = 32,   -- 结果屏标题
    h3     = 26,   -- 开门屏标题 / 规格名 / 键位 / 价格
    body   = 22,   -- 正文 / 时钟
    sub    = 18,   -- 说明 / 主次按钮
    small  = 16,   -- 最小中文
    mono   = 13,   -- ASCII 小标签
    num_xl = 102,  -- 开门屏大柜号
    num_m  = 44,   -- 取件码位
}

-- 界面实际用到的字号档（去重升序）。hzfont 每档一个实例，main.lua 启动时按这张表一次载齐；
-- 新增字号必须同时加进这里，否则该档会回退到主题点阵字库，中文渲染成方框。
M.f.sizes = { 13, 16, 18, 22, 26, 32, 38, 44, 72, 102 }

M.r = {
    card = 28,   -- .card 圆角
    box  = 22,   -- .spec 圆角
    key  = 20,   -- .key 圆角
    btn  = 18,   -- .done-btn 圆角
    tag  = 14,   -- .tagline 圆角
    chip = 9,    -- .tick 勾徽标
    pill = 100,  -- 胶囊（取足够大即恒为半圆）
}

return M
