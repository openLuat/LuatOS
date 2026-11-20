--[[
@module  page_input
@summary 会议室门牌 · 文本输入页（词库键盘：姓名 / 主题 / 部门 / 英文数字，可翻页）
@version 1.0.0
@usage
  R.go("input", {
      field = "owner",            -- 回填键：owner / topic / dept1..dept5
      title = "输入负责人",
      value = 当前值,
      max   = 8,                  -- 最多几个字
      cat   = "name",             -- 默认分类：name / topic / dept / ascii
      back  = { page = "booking", args = 回预约页用的原参数 },
  })
  确定 → 写 S.handoff[field] → 回到 back.page；返回/取消 → 直接回 back.page 不改值。

@note 门牌没有中文输入法，又不能让预约只能选预设，折中成「词库键盘」：
      点词条即插入，可退格/清空，英文数字页还能输工号、缩写、房间号。
      词库在 app_state.M.words，增删词条不用改这个页面。
      键盘整体宽 640px，落在 676px 的右侧卡片内，不会超出「预约信息」那一栏的宽度。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local R = require "router"
local C, G = T.c, T.glass
local M = {}

local SW, SH = T.screen.w, T.screen.h
local TOP = { x = 18,  y = 14, w = 988, h = 64 }
local LC  = { x = 18,  y = 90, w = 300, h = 494 }
local RC  = { x = 330, y = 90, w = 676, h = 494 }

-- 键盘网格：8 列 × 5 行 = 40 个词位，总宽 640（≤ 676）
local KX, KY, KCOLS, KROWS, KW, KH, KGX, KGY = 14, 92, 8, 5, 73, 46, 8, 8
local PAGE_SIZE = KCOLS * KROWS

local CATS = {
    { key = "name",  label = "姓名" },
    { key = "topic", label = "主题" },
    { key = "dept",  label = "部门" },
    { key = "ascii", label = "英文数字" },
}

local PAGE, ROOT
local cfg, text, cat, page = nil, "", "name", 1
local ui, slots, cat_chips = {}, {}, {}

-- 按「字数」算而不是字节数：中文一个字 3 字节，直接用 # 会把一个汉字当三个字
local function clen(s)
    if utf8 and utf8.len then
        local n = utf8.len(s)
        if n then return n end
    end
    return #s
end

-- 退格删掉最后一个「字」（中文 3 字节，ASCII 1 字节）
local function pop_char(s)
    if s == "" then return s end
    if utf8 and utf8.offset then
        local st = utf8.offset(s, -1)
        if st then return s:sub(1, st - 1) end
    end
    return s:sub(1, #s - 1)
end

-- ==================== 状态刷新 ====================
local function refresh_text()
    if #text == 0 then
        W.set(ui.content, "(空)")
        W.color(ui.content, C.text_dim)
    else
        -- 22 号字下 248px 宽最多放 10 个汉字，超出的按字截断（label 不会自己截断）
        W.set(ui.content, W.clip(text, 10))
        W.color(ui.content, C.text)
    end
    W.set(ui.count, string.format("共 %d 字 · 最多 %d 字", clen(text), cfg.max or 8))
end

local function render_keys()
    local words = S.words[cat] or {}
    local total = math.max(1, math.ceil(#words / PAGE_SIZE))
    if page > total then page = total end
    if page < 1 then page = 1 end
    local base = (page - 1) * PAGE_SIZE

    for i = 1, PAGE_SIZE do
        local slot = slots[i]
        local word = words[base + i]
        slot.text = word
        if word then
            W.glass(slot.box, C.tile, G.tile_opa)
            W.set(slot.lbl, word)
            W.color(slot.lbl, C.text)
            slot.hit.set_disabled(false)
        else
            W.glass(slot.box, C.tile, 0)
            W.set(slot.lbl, "")
            slot.hit.set_disabled(true)
        end
    end

    for _, c in ipairs(cat_chips) do c.btn.set_active(c.key == cat) end
    W.set(ui.pageno, string.format("第 %d / %d 页", page, total))
    W.set(ui.hint, string.format("共 %d 个词条 · 点词条插入到当前内容", #words))
end

local function goto_cat(key)
    cat, page = key, 1
    render_keys()
end

local function append(word)
    if not word or word == "" then return end
    local max = cfg.max or 8
    if clen(text) + clen(word) > max then
        R.toast("最多 " .. max .. " 个字")
        return
    end
    text = text .. word
    refresh_text()
end

-- ==================== 布局 ====================
local function build_topbar()
    local g = W.glass_card({ parent = ROOT, x = TOP.x, y = TOP.y, w = TOP.w, h = TOP.h })
    local p = g.card
    W.text_mid(p, { text = cfg.title or "输入", x = 18, y = 6, w = 320, h = 32,
        size = 24, color = C.text })
    W.text_mid(p, { text = "词库键盘 · 点词条插入，可退格 / 清空", x = 18, y = 38, w = 480, h = 20,
        size = T.f.mini, color = C.text_dim })
    R.theme_chip(p, { x = 700, y = 14, w = 86, h = 36 })
    W.chip(p, { x = 796, y = 14, w = 170, h = 36, text = "返回（不改）",
        off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
        on_click = function() M.back() end })
end

local function build_left()
    local g = W.glass_card({ parent = ROOT, x = LC.x, y = LC.y, w = LC.w, h = LC.h })
    local p = g.card
    W.text_mid(p, { text = "当前内容", x = 14, y = 12, w = 180, h = 20,
        size = T.f.mini, color = C.text_dim })

    local box = airui.container({ parent = p, x = 14, y = 40, w = 268, h = 64,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(box, C.tile, G.tile_opa)
    ui.content = W.text_mid(box, { text = "", x = 10, y = 0, w = 248, h = 64,
        size = 22, color = C.text, align = airui.TEXT_ALIGN_LEFT })

    ui.count = W.text_mid(p, { text = "", x = 14, y = 112, w = 268, h = 20,
        size = T.f.mini, color = C.text_dim })

    W.button(p, { x = 14, y = 146, w = 128, h = 52, text = "退格", size = T.f.body,
        color = C.btn_bg, tcolor = C.text,
        on_click = function()
            text = pop_char(text)
            refresh_text()
        end })
    W.button(p, { x = 154, y = 146, w = 128, h = 52, text = "清空", size = T.f.body,
        color = C.btn_bg, tcolor = C.text,
        on_click = function()
            text = ""
            refresh_text()
        end })
    W.button(p, { x = 14, y = 212, w = 268, h = 56, text = "确定", size = T.f.h2,
        color = C.pri, tcolor = C.on_accent, on_click = function() M.confirm() end })
    W.button(p, { x = 14, y = 280, w = 268, h = 48, text = "取消", size = T.f.body,
        color = C.tile, opa = G.tile_opa, tcolor = C.text_sub,
        on_click = function() M.back() end })

    W.text_mid(p, { text = "词语都在 app_state.M.words 里", x = 14, y = 344, w = 268, h = 20,
        size = T.f.mini, color = C.text_dim })
    W.text_mid(p, { text = "英文数字页可输工号 / 缩写", x = 14, y = 370, w = 268, h = 20,
        size = T.f.mini, color = C.text_dim })
    W.text_mid(p, { text = "「确定」后自动回到上一页", x = 14, y = 396, w = 268, h = 20,
        size = T.f.mini, color = C.text_dim })
    return g
end

local function build_right()
    local g = W.glass_card({ parent = ROOT, x = RC.x, y = RC.y, w = RC.w, h = RC.h })
    local p = g.card
    W.text_mid(p, { text = "输入键盘", x = 14, y = 12, w = 180, h = 20,
        size = T.f.mini, color = C.text_dim })

    -- 分类
    for i, c in ipairs(CATS) do
        local x = 14 + (i - 1) * 162
        local chip = W.chip(p, { x = x, y = 40, w = 152, h = 38, text = c.label,
            size = T.f.mini,
            off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
            on_click = function() goto_cat(c.key) end })
        cat_chips[i] = { key = c.key, btn = chip }
    end

    -- 词位网格
    for i = 1, PAGE_SIZE do
        local col, row = (i - 1) % KCOLS, math.floor((i - 1) / KCOLS)
        local x = KX + col * (KW + KGX)
        local y = KY + row * (KH + KGY)
        local box = airui.container({ parent = p, x = x, y = y, w = KW, h = KH,
            color = C.tile, radius = 10, border_width = 0 })
        W.glass(box, C.tile, 0)
        local lbl = W.text_mid(p, { text = "", x = x, y = y, w = KW, h = KH,
            size = T.f.mini, color = C.text, align = airui.TEXT_ALIGN_CENTER })
        local slot = { box = box, lbl = lbl, text = nil }
        slot.hit = W.press_layer(p, { x = x, y = y, w = KW, h = KH, radius = 10,
            target = box, tx = x, ty = y, glow = 40,
            on_click = function() append(slot.text) end })
        slots[i] = slot
    end

    -- 翻页
    W.chip(p, { x = 14, y = 366, w = 120, h = 36, text = "上一页",
        off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
        on_click = function()
            local n = math.max(1, math.ceil(#(S.words[cat] or {}) / PAGE_SIZE))
            page = (page > 1) and (page - 1) or n
            render_keys()
        end })
    ui.pageno = W.text_mid(p, { text = "", x = 146, y = 366, w = 380, h = 36,
        size = T.f.mini, color = C.text_sub, align = airui.TEXT_ALIGN_CENTER })
    W.chip(p, { x = 526, y = 366, w = 120, h = 36, text = "下一页",
        off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
        on_click = function()
            local n = math.max(1, math.ceil(#(S.words[cat] or {}) / PAGE_SIZE))
            page = (page < n) and (page + 1) or 1
            render_keys()
        end })

    ui.hint = W.text_mid(p, { text = "", x = 14, y = 412, w = 644, h = 20,
        size = T.f.mini, color = C.text_dim })
    return g
end

-- ==================== 动作 ====================
function M.back()
    R.go(cfg.back.page, cfg.back.args)
end

function M.confirm()
    if #text == 0 then
        R.toast("内容不能为空")
        return
    end
    S.handoff[cfg.field] = text
    R.go(cfg.back.page, cfg.back.args)
end

-- ==================== 生命周期 ====================
function M.root()
    return PAGE
end

function M.destroy()
    if PAGE then
        pcall(function() PAGE:destroy() end)
        PAGE = nil
    end
    ROOT = nil
    ui, slots, cat_chips = {}, {}, {}
end

function M.create(args)
    cfg = args or {}
    if not cfg.back then cfg = { back = { page = "home", args = nil }, field = "unused" } end
    M.destroy()
    S.refresh()

    text = cfg.value or ""
    cat = cfg.cat or "name"
    if not S.words[cat] then cat = "name" end
    page = 1

    PAGE = airui.container({ parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, border_width = 0 })
    ROOT = PAGE

    build_topbar()
    build_left()
    build_right()
    render_keys()
    refresh_text()
    log.info("page_input", "输入页已创建", cfg.field, text)
end

return M
