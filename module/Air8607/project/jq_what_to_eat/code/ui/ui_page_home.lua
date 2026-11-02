--[[
@module  ui_page_home
@summary 今天吃什么 - 页面二：家常菜（三环 80 选 5：荤 40 选 2 / 素 30 选 2 / 汤 10 选 1）
@version 1.0
@date    2026.10.26
@usage
点「开始配餐」后光带连续停靠 5 次（荤1 → 素1 → 荤2 → 素2 → 汤），每停一次右侧多一张卡片；
5 张卡片只显示类别 + 菜名，点某张卡片在下方详情区显示它的菜谱要点（详情区高度固定，
不做动态伸缩——airui 的 container/label 都没有 set_size，尺寸只能在创建时定死）。

右侧面板（页面内坐标）：
  y  24..54   「今日配餐」+ 右上角进度 n/5
  y  72..384  5 张 324x56 卡片（间距 8），左端 6px 类别色条
  y 400..500  奶油详情区：菜谱要点
]]

local T = require "ui_theme"
local D = require "ui_draw"
local F = require "foods"
local Wheel = require "ui_wheel"

local C = T.c
local M = {}

local wheel, lb_prog, lb_detail, cards, tips, ctx
local busy = false
local picked = 0

-- 五个位置：类别决定取样池、色条颜色与环号
local SLOTS = {
    { kind = "meat", cat = "荤菜", ring = 1, color = C.meat_d, pool = "meat" },
    { kind = "veg",  cat = "素菜", ring = 2, color = C.veg_d,  pool = "veg" },
    { kind = "meat", cat = "荤菜", ring = 1, color = C.meat_d, pool = "meat" },
    { kind = "veg",  cat = "素菜", ring = 2, color = C.veg_d,  pool = "veg" },
    { kind = "soup", cat = "汤",   ring = 3, color = C.soup_d, pool = "soup" },
}

function M.build(box, c)
    ctx = c
    local P = T.panel
    local x0 = P.x + P.pad
    local CW = P.w - P.pad * 2

    D.box(box, P.x, P.y, P.w, P.h, { color = C.card, radius = P.radius, border = C.line, border_w = 1 })

    D.label_mid(box, x0, P.y + 30, 220, "今日配餐", T.f.mid, C.ink)
    lb_prog = D.label_mid(box, x0 + CW - 96, P.y + 30, 96, "0/5", T.f.card, C.mute, D.ALIGN_RIGHT)

    -- 5 张卡片
    cards = {}
    tips = {}
    for i = 1, 5 do
        local slot = SLOTS[i]
        local cy = P.y + 72 + (i - 1) * 64
        local card = D.box(box, x0, cy, CW, 56, {
            color = C.tint, radius = 14, border = C.line, border_w = 1,
            on_click = function() M.pick(i) end,
        })
        local bar = D.box(card, 0, 0, 6, 56, { color = slot.color, radius = 3 })
        local cat = D.label_mid(card, 18, 16, 90, slot.cat, T.f.mini, slot.color)
        local name = D.label_mid(card, 18, 38, 240, "待转", T.f.card, C.faint)
        local hint = D.label_mid(card, CW - 76, 38, 58, "", T.f.mini, C.faint, D.ALIGN_RIGHT)
        -- bar 只是为了占住 z 序，避免被 GC 掉句柄；不需要再用它
        cards[i] = { box = card, cat = cat, name = name, hint = hint, bar = bar }
        tips[i] = nil
    end

    -- 详情区
    D.box(box, x0, P.y + 390, CW, 100, { color = C.cream, radius = 16 })
    D.label_mid(box, x0 + 14, P.y + 406, CW - 28, "菜谱要点", T.f.mini, C.mute)
    lb_detail = D.label(box, x0 + 14, P.y + 418, CW - 28, 66,
        "配好五道菜后，点任意一道看做法。", T.f.small, C.sub)

    wheel = Wheel.new({
        parent = box,
        rings = T.rings.home,
        button_text = "开始配餐",
        on_button = function() M.start() end,
    })
    M.wheel = wheel -- 供离屏预览 / 现场调试拿到句柄
end

-- ==================== 卡片 / 详情 ====================

local function show_detail(i)
    local slot = SLOTS[i]
    if not tips[i] then return end
    lb_detail:set_text(tips[i])
    for k = 1, 5 do
        local c = cards[k]
        if k == i then
            c.box:set_color(C.cream)
            c.box:set_border_color(C.accent, 2)
        else
            c.box:set_color(C.tint)
            c.box:set_border_color(C.line, 1)
        end
    end
    picked = i
    log.info("page.home", "查看做法", slot.cat, cards[i].name:get_text())
end

function M.pick(i)
    if busy then return end
    show_detail(i)
end

local function fill_slot(i, name, tip)
    tips[i] = tip
    cards[i].name:set_text(name)
    cards[i].name:set_color(C.ink)
    cards[i].hint:set_text("做法")
    cards[i].box:set_color(C.tint)
    cards[i].box:set_border_color(C.line, 1)
end

local function clear_slots()
    tips = {}
    picked = 0
    for i = 1, 5 do
        cards[i].name:set_text("待转")
        cards[i].name:set_color(C.faint)
        cards[i].hint:set_text("")
        cards[i].box:set_color(C.tint)
        cards[i].box:set_border_color(C.line, 1)
    end
    lb_prog:set_text("0/5")
    lb_detail:set_text("配好五道菜后，点任意一道看做法。")
end

-- ==================== 开一轮 ====================

local function spin_body()
    local t0 = D.now_ms()
    -- 先定好 5 道（荤 2 / 素 2 / 汤 1，各类内部不重复），再让光带依次停到它们身上
    local meat = D.sample(#F.meat, 2)
    local veg = D.sample(#F.veg, 2)
    local soup = D.sample(#F.soup, 1)
    local plan = {
        { ring = 1, sector = meat[1], pick = F.meat[meat[1]] },
        { ring = 2, sector = veg[1], pick = F.veg[veg[1]] },
        { ring = 1, sector = meat[2], pick = F.meat[meat[2]] },
        { ring = 2, sector = veg[2], pick = F.veg[veg[2]] },
        { ring = 3, sector = soup[1], pick = F.soup[soup[1]] },
    }

    clear_slots()
    wheel:reset_hits()
    wheel:set_button("配餐中", true)

    for i = 1, #plan do
        local step = plan[i]
        wheel:spin_to(step.ring, step.sector, { duration = T.spin.home_ms, turns = T.spin.home_turns })
        wheel:mark_hit(step.ring, step.sector)
        fill_slot(i, step.pick.name, step.pick.tip)
        lb_prog:set_text(string.format("%d/5", i))
        if i == 1 then show_detail(1) end
        if i < #plan then sys.wait(T.spin.home_hold) end
        log.info("page.home", "第", i, "道", SLOTS[i].cat, step.pick.name)
    end

    wheel:set_button("再配一次", false)
    log.info("page.home", "配餐完成，5 道菜，耗时", D.now_ms() - t0, "ms")
end

-- 配餐任务：正常结束与异常结束都复位 busy，避免一次异常锁死页签
local function spin_task()
    local ok, err = pcall(spin_body)
    busy = false
    if ctx and ctx.set_busy then ctx.set_busy(false) end
    if not ok then
        log.error("page.home", "配餐异常", tostring(err))
        if wheel then pcall(wheel.set_button, wheel, "开始配餐", false) end
    end
end

function M.start()
    if busy or not wheel then return end
    busy = true
    if ctx and ctx.set_busy then ctx.set_busy(true) end
    sys.taskInit(spin_task)
end

return M
