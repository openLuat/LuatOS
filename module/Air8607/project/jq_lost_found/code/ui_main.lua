--[[
@module  ui_main
@summary 失物招领公示主界面：顶栏 + 筛选栏 + 列表 + 详情 + 分页
@version 1.0
@date    2026.10.30

=== 布局（1024x600）===
顶栏      y 0..72     标题 + 时钟 + 公示中/已认领统计
筛选栏    y 72..144   两行：搜索框+类型(全部/拾得/遗失)+新增 / 状态(全部/公示中/已认领)+时间(全部/今天/近7天)
列表      x16..648    5 条卡片（分页）
详情      x660..1008  选中条目详情 + 操作按钮

对外接口：
  ui_main.build()     构建整屏
  ui_main.refresh()   数据/筛选变化后全量刷新
  ui_main.tick()      每秒刷新时钟
]]

local conf = require "conf"
local theme = require "theme"
local store = require "store"
local ui_form = require "ui_form"
local ui_claim = require "ui_claim"
local ui_input = require "ui_input"

local M = {}

local SW, SH = conf.W, conf.H
local C = theme.C
local PAGE_SIZE = conf.PAGE_SIZE

-- ==================== 状态 ====================
local filter = { keyword = "", kind = "all", time = "all", status = "all" }
local page = 1
local selected = nil          -- 选中条目 id
local list_cache = {}         -- 当前筛选结果

-- ==================== 控件句柄 ====================
local lb_clock, lb_date, lb_stat_open, lb_stat_done
local search_box, lb_search
local type_chips, time_chips, status_chips = {}, {}, {}
local cards = {}
local lb_page, lb_count
local detail_content, lb_d_empty
local lb_d_badge, lb_d_badge_lb, lb_d_name
local lb_d_time, lb_d_place, lb_d_contact, lb_d_status
local lb_d_claim, lb_done_note
local act_claim, act_delete

local WEEK = { "日", "一", "二", "三", "四", "五", "六" }

-- 前向声明：部分控件回调在函数定义前就引用它们
local refresh_chips, render_list, render_detail

-- ==================== 顶栏 ====================
local function build_header(parent)
    theme.box(parent, 0, 0, SW, 72, C.panel, 0)
    theme.box(parent, 0, 71, SW, 1, C.line, 0)

    -- logo 色块
    theme.box(parent, 16, 20, 32, 32, C.accent, 8)

    theme.label(parent, 56, 12, 320, 30, conf.TITLE, 26, C.ink)
    theme.label(parent, 56, 42, 360, 18, conf.SUBTITLE, 13, C.ink3)

    lb_clock = theme.label(parent, 620, 8, 184, 30, "--:--:--", 28, C.ink, airui.TEXT_ALIGN_RIGHT)
    lb_date = theme.label(parent, 620, 42, 184, 18, "等待校时", 14, C.ink3, airui.TEXT_ALIGN_RIGHT)

    lb_stat_open = theme.label(parent, 812, 10, 88, 28, "0", 24, C.open, airui.TEXT_ALIGN_CENTER)
    theme.label(parent, 812, 42, 88, 18, "公示中", 14, C.ink3, airui.TEXT_ALIGN_CENTER)

    lb_stat_done = theme.label(parent, 908, 10, 88, 28, "0", 24, C.done, airui.TEXT_ALIGN_CENTER)
    theme.label(parent, 908, 42, 88, 18, "已认领", 14, C.ink3, airui.TEXT_ALIGN_CENTER)
end

-- ==================== 筛选栏 ====================
local function open_search()
    ui_input.open({
        title = "搜索",
        initial = filter.keyword,
        on_done = function(t)
            filter.keyword = (t or ""):gsub("%s+", "")
            page = 1
            if filter.keyword == "" then
                lb_search:set_text("搜索物品名称…")
                lb_search:set_color(C.ink3)
            else
                lb_search:set_text(filter.keyword)
                lb_search:set_color(C.ink)
            end
            M.refresh()
        end,
    })
end

local function open_add()
    ui_form.open(function()
        page = 1
        M.refresh()
    end)
end

local function build_filter(parent)
    -- 两行筛选区
    theme.box(parent, 0, 72, SW, 72, C.panel, 0)
    theme.box(parent, 0, 143, SW, 1, C.line, 0)

    -- 第一行：搜索框 + 类型 + 新增
    search_box = airui.container({
        parent = parent, x = 16, y = 78, w = 240, h = 34,
        color = C.card2, radius = 17, border_color = C.line2, border_width = 1,
        on_click = function() open_search() end,
    })
    lb_search = theme.label(search_box, 36, 6, 196, 22, "搜索物品名称…", 15, C.ink3)

    local td = { { "all", "全部" }, { "found", "拾得" }, { "lost", "遗失" } }
    for i, d in ipairs(td) do
        type_chips[d[1]] = theme.chip(parent, 272 + (i - 1) * 88, 78, 80, 34, d[2], 16, function()
            filter.kind = d[1]
            page = 1
            refresh_chips()
            M.refresh()
        end)
    end

    theme.button(parent, 840, 74, 168, 38, "＋ 新增条目", 17, function() open_add() end, "primary")

    -- 第二行：状态 + 时间
    local sd = { { "all", "全部" }, { "open", "公示中" }, { "done", "已认领" } }
    for i, d in ipairs(sd) do
        status_chips[d[1]] = theme.chip(parent, 16 + (i - 1) * 120, 114, 112, 28, d[2], 14, function()
            filter.status = d[1]
            page = 1
            refresh_chips()
            M.refresh()
        end)
    end

    local tt = { { "all", "全部时间" }, { "today", "今天" }, { "week", "近7天" } }
    for i, d in ipairs(tt) do
        time_chips[d[1]] = theme.chip(parent, 500 + (i - 1) * 112, 114, 104, 28, d[2], 14, function()
            filter.time = d[1]
            page = 1
            refresh_chips()
            M.refresh()
        end)
    end
end

refresh_chips = function()
    for k, c in pairs(type_chips) do c:set_active(filter.kind == k) end
    for k, c in pairs(status_chips) do c:set_active(filter.status == k) end
    for k, c in pairs(time_chips) do c:set_active(filter.time == k) end
end

-- ==================== 列表卡片 ====================
local CARD_X, CARD_Y, CARD_W, CARD_H, CARD_GAP = 16, 150, 632, 76, 6

local function build_card_slot(i)
    local y = CARD_Y + (i - 1) * (CARD_H + CARD_GAP)
    local card = theme.card(nil, CARD_X, y, CARD_W, CARD_H, C.card, 12, C.line, 1)

    local bar = theme.box(card, 0, 18, 6, 44, C.found, 3)
    local badge = theme.box(card, 16, 12, 60, 26, C.found, 13)
    local badge_lb = theme.label(badge, 0, 3, 60, 20, "拾得", 14, 0xFFFFFF, airui.TEXT_ALIGN_CENTER)

    local lb_name = theme.label(card, 88, 10, 240, 28, "", 20, C.ink)
    local lb_time = theme.label(card, 88, 40, 200, 18, "", 14, C.ink2)
    local lb_place = theme.label(card, 300, 40, 230, 18, "", 14, C.ink2)
    local lb_contact = theme.label(card, 88, 58, 300, 16, "", 14, C.ink3)

    local chip = theme.box(card, 544, 12, 72, 26, C.open_soft, 13)
    local chip_lb = theme.label(chip, 0, 3, 72, 20, "公示中", 13, C.open, airui.TEXT_ALIGN_CENTER)

    -- 透明点击层覆盖整卡
    airui.button({
        parent = card, x = 0, y = 0, w = CARD_W, h = CARD_H,
        text = "",
        style = { bg_color = 0x000000, bg_opa = 0, radius = 12, border_width = 0 },
        on_click = function()
            selected = cards[i].item and cards[i].item.id or nil
            render_list()
            render_detail()
        end,
    })

    cards[i] = {
        card = card, bar = bar, badge = badge, badge_lb = badge_lb,
        lb_name = lb_name, lb_time = lb_time, lb_place = lb_place, lb_contact = lb_contact,
        chip = chip, chip_lb = chip_lb, item = nil,
    }
end

local function total_pages()
    return math.max(1, math.ceil(#list_cache / PAGE_SIZE))
end

render_list = function()
    local start = (page - 1) * PAGE_SIZE
    for i = 1, PAGE_SIZE do
        local slot = cards[i]
        local it = list_cache[start + i]
        slot.item = it
        if it then
            slot.card:set_hidden(false)
            local col = (it.kind == "found") and C.found or C.lost
            slot.bar:set_color(col, 255)
            slot.badge:set_color(col, 255)
            slot.badge_lb:set_text(it.kind == "found" and "拾得" or "遗失")
            slot.lb_name:set_text(it.name)
            slot.lb_time:set_text(it.time or "")
            slot.lb_place:set_text("地点：" .. (it.place ~= "" and it.place or "--"))
            -- 拾得人联系方式不公示，仅在详情页可见
            if it.kind == "found" then
                slot.lb_contact:set_text("联系：点详情查看")
                slot.lb_contact:set_color(C.ink3)
            else
                slot.lb_contact:set_text("联系：" .. it.contact)
                slot.lb_contact:set_color(C.ink3)
            end

            if it.status == "done" then
                slot.chip:set_color(C.done_soft, 255)
                slot.chip_lb:set_color(C.done)
                slot.chip_lb:set_text("已认领")
            else
                slot.chip:set_color(C.open_soft, 255)
                slot.chip_lb:set_color(C.open)
                slot.chip_lb:set_text("公示中")
            end

            local sel = (selected == it.id)
            pcall(slot.card.set_border_color, slot.card, sel and C.accent or C.line, sel and 2 or 1)
        else
            slot.card:set_hidden(true)
        end
    end

    lb_page:set_text(string.format("%d / %d", page, total_pages()))
    lb_count:set_text(string.format("共 %d 条", #list_cache))
end

-- ==================== 详情面板 ====================
local function build_detail(parent)
    local dx, dy, dw, dh = 660, 144, 348, 444
    theme.card(parent, dx, dy, dw, dh, C.card, 12, C.line, 1)
    theme.label(parent, dx + 16, dy + 14, 200, 26, "条目详情", 20, C.ink)
    theme.box(parent, dx + 16, dy + 48, dw - 32, 1, C.line, 0)

    detail_content = airui.container({
        parent = parent, x = dx, y = dy + 54, w = dw, h = dh - 54,
        color = 0x000000, color_opacity = 0, radius = 0, border_width = 0,
    })

    local dc = detail_content
    lb_d_badge = theme.box(dc, 16, 12, 64, 28, C.found, 14)
    lb_d_badge_lb = theme.label(lb_d_badge, 0, 4, 64, 20, "拾得", 14, 0xFFFFFF, airui.TEXT_ALIGN_CENTER)
    lb_d_name = theme.label(dc, 90, 16, 240, 24, "", 20, C.ink)

    local rows = { { "时间", 60 }, { "地点", 92 }, { "联系方式", 124 }, { "状态", 156 } }
    for _, r in ipairs(rows) do
        theme.label(dc, 16, r[2], 70, 20, r[1], 14, C.ink3)
        local v = theme.label(dc, 92, r[2], 240, 20, "", 15, C.ink)
        if r[1] == "时间" then lb_d_time = v
        elseif r[1] == "地点" then lb_d_place = v
        elseif r[1] == "联系方式" then lb_d_contact = v
        else lb_d_status = v end
    end

    lb_d_claim = theme.label(dc, 16, 190, 316, 20, "", 14, C.done)

    -- 操作按钮（airui.button 没有 set_hidden，用容器包裹做显隐）
    act_claim = airui.container({ parent = dc, x = 16, y = 224, w = 316, h = 48, color = 0x000000, color_opacity = 0, radius = 0, border_width = 0 })
    theme.button(act_claim, 0, 0, 316, 48, "凭身份证领取", 18, function()
        if selected then ui_claim.open(store.get(selected), function() M.refresh() end) end
    end, "lost")

    lb_done_note = theme.label(dc, 16, 236, 316, 24, "", 16, C.done, airui.TEXT_ALIGN_CENTER)

    act_delete = airui.container({ parent = dc, x = 16, y = 284, w = 316, h = 48, color = 0x000000, color_opacity = 0, radius = 0, border_width = 0 })
    theme.button(act_delete, 0, 0, 316, 48, "删除该条目", 18, function()
        if selected then
            local ok = store.remove(selected)
            if ok then
                selected = nil
                M.refresh()
            end
        end
    end, "danger")

    -- 空状态提示（叠加在详情内容之上）
    lb_d_empty = theme.label(parent, dx + 16, dy + 90, dw - 32, 30,
        "点击左侧条目查看详情", 18, C.ink3, airui.TEXT_ALIGN_CENTER)
end

render_detail = function()
    local it = store.get(selected)
    if not it then
        detail_content:set_hidden(true)
        lb_d_empty:set_text("点击左侧条目查看详情")
        return
    end

    detail_content:set_hidden(false)
    lb_d_empty:set_text("")

    local is_found = (it.kind == "found")
    local col = is_found and C.found or C.lost
    lb_d_badge:set_color(col, 255)
    lb_d_badge_lb:set_text(is_found and "拾得" or "遗失")
    lb_d_name:set_text(it.name)

    lb_d_time:set_text(it.time or "--")
    lb_d_place:set_text(it.place ~= "" and it.place or "--")
    lb_d_contact:set_text(it.contact)

    if it.status == "done" then
        lb_d_status:set_text("已完成")
        lb_d_status:set_color(C.done)
    else
        lb_d_status:set_text("公示中")
        lb_d_status:set_color(C.open)
    end

    local show_claim = (it.status == "open")
    act_claim:set_hidden(not show_claim)
    act_delete:set_hidden(false)

    if it.status == "done" then
        lb_d_claim:set_text(string.format("认领人 · 证件尾号 %s · 联系 %s",
            it.claimer_tail or "----", it.claimer_contact or "--"))
        lb_done_note:set_text("该条目已认领完成")
    else
        lb_d_claim:set_text("")
        lb_done_note:set_text("")
    end
end

-- ==================== 分页 ====================
local function build_pagination(parent)
    theme.button(parent, 16, 556, 96, 30, "上一页", 15, function()
        if page > 1 then page = page - 1; render_list() end
    end, "ghost")
    lb_page = theme.label(parent, 120, 558, 80, 26, "1 / 1", 16, C.ink, airui.TEXT_ALIGN_CENTER)
    theme.button(parent, 208, 556, 96, 30, "下一页", 15, function()
        if page < total_pages() then page = page + 1; render_list() end
    end, "ghost")
    lb_count = theme.label(parent, 330, 558, 302, 26, "共 0 条", 15, C.ink3, airui.TEXT_ALIGN_RIGHT)
end

-- ==================== 对外 ====================
function M.build()
    theme.gradient(nil, 0, 0, SW, SH, C.bg1, C.bg2, 16)

    build_header(nil)
    build_filter(nil)
    for i = 1, PAGE_SIZE do build_card_slot(i) end
    build_detail(nil)
    build_pagination(nil)

    refresh_chips()
    M.refresh()
end

function M.refresh()
    list_cache = store.query(filter)
    if page > total_pages() then page = total_pages() end
    if page < 1 then page = 1 end
    render_list()
    render_detail()

    local open, done = store.stats()
    lb_stat_open:set_text(tostring(open))
    lb_stat_done:set_text(tostring(done))
end

function M.tick()
    local t = os.date("*t")
    if t and t.year and t.year >= 2020 then
        lb_clock:set_text(string.format("%02d:%02d:%02d", t.hour, t.min, t.sec))
        lb_date:set_text(string.format("%04d-%02d-%02d 星期%s", t.year, t.month, t.day, WEEK[t.wday] or ""))
    else
        lb_clock:set_text("--:--:--")
        lb_date:set_text("等待校时")
    end
end

return M
