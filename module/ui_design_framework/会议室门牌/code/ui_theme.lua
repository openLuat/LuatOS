--[[
@module  ui_theme
@summary 会议室门牌 · 深色/浅色双主题设计令牌（运行中可切 + fskv 记忆，默认浅色）
@version 1.1.0
@usage  改外观只动这一个文件。颜色 0xRRGGBB，透明度 0-255（越小越透明）。
        运行中切换：T.set_mode("light") / T.set_mode("dark")，
        原地覆盖 M.c / M.glass / M.dept 的字段并写 fskv，页面 destroy + create 原地重建。

        两套主题的层叠关系完全一致，差别只在「底色 + 载体色 + 高亮色」：
          dark ：近纯黑底 + 半透明深蓝灰卡片 + 电光蓝高亮（部门色块用亮色低透明叠在暗卡上）
          light：浅雾白底 + 半透明白卡 + 深蓝高亮（部门色块直接用浅色底 tint）

        背景是一张 1024x600 的实景照片（img/bg_tower.jpg，东方明珠），
        卡片全部半透明压在照片上，靠 2px 描边 + 投影保证「卡片与背景可分辨」；
        照片前还盖一层 G.veil 纱层，用来压掉天空高光、把文字对比度拉回可读区间。

        注意：M.c / M.glass / M.dept 是常驻表，apply 只做「原地覆盖字段」，
        不能写成 M.c = t.c —— 页面在 require 时已把这三张表的引用存进 local，
        换引用会让那些 local 永远停在旧主题。
]]
local M = {}

-- ---------- 当前外观：默认浅色，fskv 只做「上次选择」的覆盖 ----------
M.mode = "light"                                 -- "dark" / "light"
if fskv then
    pcall(function()
        if fskv.init then fskv.init() end
        local m = fskv.get("ui_door_mode")
        log.info("ui_theme", "读取外观偏好", m)
        if m == "dark" or m == "light" then M.mode = m end
    end)
end

-- ==================== 色板 ====================
local P = {}

-- ---------- 深色：近纯黑底 + 深蓝灰卡片 ----------
P.dark = {
    c = {
        text = 0xE9F0FA, text_sub = 0x9BAAC1, text_dim = 0x7C8CA6,
        card = 0x18212F, panel = 0x141C29, cardtop = 0x1E2838,
        tile = 0x223047, track = 0x1A2534, hl = 0xFFFFFF,
        edge = 0x2A3A52, divider = 0x2E3E55, shadow = 0x000000,
        pri = 0x5AA9FF, pri_deep = 0x2F7FE0, on_accent = 0x07111E,
        ok = 0x34D399, warn = 0xFBBF24, danger = 0xF87171,
        btn_bg = 0x24405E,
        chip_off = 0x223047, chip_off_t = 0x9BAAC1,
        deep = 0x0A111C, soft = 0x2A3A52,
    },
    glass = {
        bg = 0x0A121F,                           -- 照片加载失败时的兜底底色
        veil = 0x050A14, veil_opa = 138,         -- 压在照片上的暗纱，把白天的天空压暗
        glow1 = 0x1D4ED8, glow2 = 0x0EA5E9, glow3 = 0x7C3AED, glow4 = 0x0E9F6E,
        bg_glow_opa = 28,
        -- 卡片一律半透明：能看见照片，但仍能读出文字
        card_opa = 164, tile_opa = 182, panel_opa = 168, topbar_opa = 170,
        shadow_opa = 170, shadow_off = 4,
        hl_opa = 26, hl_sweep_opa = 110,
        card_edge = 2,
        inset_opa = 184, track_opa = 130,
        block_opa = 88,                          -- 部门色块：亮色底叠在暗卡上
        sel_opa = 34,                            -- 选中日期列整列高亮
        row_opa = 22,                            -- 当前时间段整行高亮
    },
    -- 顺序与 app_state.M.depts 一一对应（1 研发 / 2 市场 / 3 人事 / 4 财务 / 5 总经办 / 6 客服）
    dept = {
        { accent = 0x60A5FA, tint = 0x2563EB, text = 0xDCEAFF },
        { accent = 0x34D399, tint = 0x0E9F6E, text = 0xD6FBEB },
        { accent = 0xFBBF24, tint = 0xB45309, text = 0xFFF3D6 },
        { accent = 0xA78BFA, tint = 0x6D28D9, text = 0xEDE6FF },
        { accent = 0xF87171, tint = 0xB91C1C, text = 0xFFE1E1 },
        { accent = 0x22D3EE, tint = 0x0E7490, text = 0xCFFAFE },
    },
}

-- ---------- 浅色：灰蓝纸底 + 纯白不透明卡 ----------
P.light = {
    c = {
        text = 0x0E1B2E, text_sub = 0x4A5B73, text_dim = 0x6B7C93,
        card = 0xFFFFFF, panel = 0xFFFFFF, cardtop = 0xFFFFFF,
        tile = 0xE9F0F9, track = 0xDDE8F5, hl = 0xFFFFFF,
        edge = 0xB7C7DB, divider = 0xCEDCEA, shadow = 0x3C5570,
        pri = 0x1D63D6, pri_deep = 0x134BA8, on_accent = 0xFFFFFF,
        ok = 0x0E9F6E, warn = 0xB45309, danger = 0xD92E43,
        btn_bg = 0x1D63D6,
        chip_off = 0xE9F0F9, chip_off_t = 0x4A5B73,
        deep = 0xE9F0F9, soft = 0xB7C7DB,
    },
    glass = {
        bg = 0xE8F1FB,                           -- 照片加载失败时的兜底底色
        veil = 0xF3F8FF, veil_opa = 92,          -- 压在照片上的亮纱，把画面提亮成清爽的浅色底
        glow1 = 0xAFC8F0, glow2 = 0x9BD8F2, glow3 = 0xC8BBF2, glow4 = 0xA8E6CF,
        bg_glow_opa = 66,
        -- 卡片一律半透明白：照片从卡片后面透出来，描边 + 投影负责「卡片轮廓可分辨」
        card_opa = 178, tile_opa = 190, panel_opa = 182, topbar_opa = 184,
        shadow_opa = 78, shadow_off = 5,
        hl_opa = 0, hl_sweep_opa = 0,            -- 白卡上不加顶部反光条（白叠白 = 塑料亮边）
        card_edge = 2,
        inset_opa = 196, track_opa = 225,
        block_opa = 190,                         -- 浅色部门块也留一点通透感
        sel_opa = 40,                            -- 选中日期列整列高亮
        row_opa = 26,                            -- 当前时间段整行高亮
    },
    dept = {
        { accent = 0x2563EB, tint = 0xDBEAFE, text = 0x1E40AF },
        { accent = 0x0E9F6E, tint = 0xD1FAE5, text = 0x065F46 },
        { accent = 0xB45309, tint = 0xFEF3C7, text = 0x92400E },
        { accent = 0x7C3AED, tint = 0xEDE9FE, text = 0x5B21B6 },
        { accent = 0xDC2626, tint = 0xFEE2E2, text = 0x991B1B },
        { accent = 0x0E7490, tint = 0xCFFAFE, text = 0x155E75 },
    },
}

-- 生效当前外观：原地覆盖，不换引用
M.c, M.glass, M.dept = {}, {}, {}

local function copy_tokens(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
end

-- dept 是数组表，逐项原地覆盖，保证页面里缓存的 T.dept 引用一直有效
function M.apply(mode)
    M.mode = (mode == "light") and "light" or "dark"
    local t = P[M.mode]
    copy_tokens(M.c, t.c)
    copy_tokens(M.glass, t.glass)
    for i = 1, #t.dept do
        if not M.dept[i] then M.dept[i] = {} end
        copy_tokens(M.dept[i], t.dept[i])
    end
end

local function save()
    if not fskv then return end
    pcall(function()
        fskv.set("ui_door_mode", M.mode)
        log.info("ui_theme", "保存外观偏好", M.mode)
    end)
end

function M.set_mode(mode)
    M.apply(mode)
    save()
end

M.apply(M.mode)

-- ==================== 背景照片 ====================
-- 仓库里放的是 1024x600 的基线 JPEG（不是原 PNG）：
-- 硬件 JPEG 解一帧要 ~1.2MB RGB565 缓冲，原图 1637x961 解出来是 3MB 级别，真机会 OOM；
-- LVGL 的 fit="cover" 是绘制时缩放，控件多大都要按原图尺寸解码，所以必须在仓库里先定尺寸。
M.bg_image = "bg_tower.jpg"
local bg_dir

-- 图片目录探测：Luatools 下载后工程在 /luadb，也兼容直接丢在根目录的情况
function M.bg_path()
    if bg_dir == nil then
        bg_dir = false
        for _, d in ipairs({ "/luadb/img/", "/luadb/", "/img/", "/" }) do
            local ok, ex = pcall(function() return io.exists(d .. M.bg_image) end)
            if ok and ex then
                bg_dir = d
                break
            end
        end
        log.info("ui_theme", "背景照片目录", bg_dir)
    end
    if not bg_dir then return nil end
    return bg_dir .. M.bg_image
end

-- ==================== 固定参数 ====================
M.r = { card = 20, panel = 12, chip = 18, btn = 12 }
-- 字号：最小 16 号（验收要求），门牌远看需要大字号
M.f = { big = 40, h1 = 26, h2 = 22, body = 18, sub = 16, mini = 16 }

-- 微动：默认全即时（不建逐帧定时器）。真机上逐帧 Lua 定时器会被其他任务抢占，
-- 点击后排队还会出现「松手了还在动」的拖尾，交互反馈一律一帧到位。
M.motion = {
    enabled = true,
    instant = true,
    press_dy = 2,
}

M.screen = { w = 1024, h = 600 }

return M
