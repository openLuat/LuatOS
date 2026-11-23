--[[
@module  wallpaper
@summary 会议室门牌 · 屏幕级背景（1024x600 实景照片 + 纱层 + 兜底柔光）
@version 1.0.0
@note 1) 背景挂在 airui.screen 上、只建一次：页面整页重建（切主题）时不会重复解码照片
         （一帧 1024x600 JPEG 解码约 1.2MB RGB565，反复解码会明显掉帧）。
      2) 页面根容器是透明的，背景从页面后面透出来；卡片靠 G.card_opa 半透明 + 2px 描边 + 投影
         与背景区分，纱层 G.veil 负责压掉照片高光、保证文字对比度。
      3) 照片缺失/解码失败时退回「纯色 + 四团柔光」，界面不会黑屏或报错。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local C, G = T.c, T.glass
local M = {}

local SW, SH = T.screen.w, T.screen.h
local base, veil, photo
local orbs = {}

-- 兜底柔光：只在照片不可用时生效
local ORBS = {
    { x = 0,   y = 0,   w = 360, h = 220, r = 110, key = "glow1", k = 1.0 },
    { x = 664, y = 0,   w = 360, h = 260, r = 120, key = "glow2", k = 1.0 },
    { x = 640, y = 360, w = 384, h = 240, r = 110, key = "glow3", k = 0.9 },
    { x = 0,   y = 360, w = 300, h = 240, r = 120, key = "glow4", k = 0.85 },
}

local function build_orbs()
    orbs = {}
    for i, o in ipairs(ORBS) do
        local obj = airui.container({ parent = base, x = o.x, y = o.y, w = o.w, h = o.h,
            color = G[o.key], radius = o.r, border_width = 0 })
        orbs[i] = { obj = obj, key = o.key, k = o.k }
    end
end

local function paint_orbs()
    for _, o in ipairs(orbs) do
        W.glass(o.obj, G[o.key], math.floor(G.bg_glow_opa * o.k))
    end
end

function M.build()
    base = airui.container({ parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
        color = G.bg, radius = 0, border_width = 0 })
    W.glass(base, G.bg, 255)

    local path = T.bg_path()
    if path then
        local ok, obj = pcall(function()
            return airui.image({ parent = base, x = 0, y = 0, w = SW, h = SH,
                src = path, fit = "cover" })
        end)
        if ok and obj then
            photo = obj
            log.info("wallpaper", "背景照片已加载", path)
        else
            log.warn("wallpaper", "背景照片加载失败，改用柔光兜底")
        end
    end
    if not photo then build_orbs() end

    -- 纱层：照片之上、所有页面之下
    veil = airui.container({ parent = base, x = 0, y = 0, w = SW, h = SH,
        color = G.veil, radius = 0, border_width = 0 })
    M.apply()
    return M
end

-- 切主题时只换颜色，不动照片（不重新解码）
function M.apply()
    if not base then return end
    W.glass(base, G.bg, 255)
    if veil then W.glass(veil, G.veil, G.veil_opa) end
    paint_orbs()
end

function M.has_photo()
    return photo ~= nil
end

return M
