--[[
@module  ui_home
@summary 主页：房间筛选胶囊 + 设备卡片墙（3x2）
@version 1.0
@date    2026.10.28

布局（1024x600）：
  顶栏    0..72      logo + 标题 + 报警胶囊 + 静音 + 时钟
  房间条  78..118    「全部 / 各房间 / + 房间」胶囊 + 「+ 添加宠物箱」
  卡片区  132..540   3 列 x 2 行，单卡 316x196
  底栏    546..592   最近报警 + 翻页
]]
local conf = require "conf"
local theme = require "theme"
local icon = require "icon"
local store = require "store"
local alarm = require "alarm"
local ui_dialog = require "ui_dialog"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local CARD_W, CARD_H = 316, 196
local GX = { 22, 353, 684 }
local GY = { 132, 344 }
local PER_PAGE = 6
local CHIP_MAX_X = 812

local root = nil
local app_ref = nil
local cards = {}

local cur_room = 0
local page = 1
local total_pages = 1

local alarm_box, lbl_alarm, lbl_mute = nil, nil, nil
local lbl_clock, lbl_date = nil, nil
local lbl_tip, lbl_page = nil, nil
local btn_prev, btn_next = nil, nil

--------------------------------------------------------------------
-- 小工具
--------------------------------------------------------------------
local function bar_items(v, lo, hi, w, col)
    local t = 0
    if hi and lo and hi > lo then t = (v - lo) / (hi - lo) end
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local fw = math.floor((w - 2) * t)
    if fw < 4 then fw = 4 end
    return {
        { type = "rect", x = 0, y = 1, w = w, h = 4, radius = 2, fill = true, fill_color = C.line },
        { type = "rect", x = 0, y = 1, w = fw, h = 4, radius = 2, fill = true, fill_color = col },
    }
end

-- 开关按钮：开启 = 实心彩底 + 白字「开」；关闭 = 浅底描边 + 灰字「关」
local function style_btn(btn, on, col)
    if not btn then return end
    btn:set_style({
        bg_color = on and col or C.tile,
        text_color = on and C.white or C.ink3,
        border_width = on and 0 or 2,
        border_color = on and col or C.line,
    })
end

local function sync_btn(st, key, btn, label, on, col)
    if st[key] == on then return end
    st[key] = on
    if not btn then return end
    btn:set_text(label .. (on and " 开" or " 关"))
    style_btn(btn, on, col)
end

--------------------------------------------------------------------
-- 顶栏
--------------------------------------------------------------------
local function build_topbar()
    theme.box(root, 0, 0, SW, 72, C.bar, 0)
    theme.box(root, 0, 70, SW, 2, C.line, 0)

    theme.shape({ parent = root, x = 18, y = 12, w = 48, h = 48, items = icon.pet("chick", 48, 48, C.butter) })
    theme.label(root, 76, 10, 320, 36, conf.name, 26, C.ink)
    theme.label(root, 78, 46, 380, 18, "多房间温湿度与有毒气体监控", 12, C.ink3)

    alarm_box = theme.box(root, 592, 18, 174, 36, C.mint2, 18)
    lbl_alarm = theme.label_mid(alarm_box, 0, 0, 174, 36, "全部正常", 14, C.mint, airui.TEXT_ALIGN_CENTER)

    -- 喇叭自检：确认音频通路与 alarm.wav 是否正常
    theme.tint_button(root, 470, 18, 100, 36, "试听警报", 13, C.card2, C.ink2, function()
        theme.defer(function()
            if not app_ref then return end
            if not alarm.ready() then
                app_ref.toast("音频不可用：" .. alarm.backend())
                return
            end
            local ok = alarm.play()
            app_ref.toast(ok and "正在试听警报音" or "播放失败，检查 alarm.wav")
        end)
    end, 18)

    lbl_mute = theme.tint_button(root, 776, 18, 88, 36, "静音", 14, C.card2, C.ink2, function()
        theme.defer(function() M.toggle_mute() end)
    end, 18)

    lbl_clock = theme.label(root, 872, 8, 132, 28, "", 19, C.ink, airui.TEXT_ALIGN_RIGHT)
    lbl_date = theme.label(root, 872, 38, 132, 18, "", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)
end

--------------------------------------------------------------------
-- 房间筛选胶囊
--------------------------------------------------------------------
local function chip(x, w, text, active, on_click)
    return theme.tint_button(root, x, 78, w, 40, text, 14,
        active and C.pink or C.card,
        active and C.white or C.ink2,
        on_click, 20,
        active and C.pink or C.line)
end

local function set_room(id)
    theme.defer(function()
        cur_room = id
        page = 1
        M.build(app_ref)
    end)
end

local function build_chips()
    local x = 22

    local function fits(w) return (x + w) <= CHIP_MAX_X end

    local w_all = theme.text_width("全部", 14) + 46
    if fits(w_all) then
        chip(x, w_all, "全部 " .. store.count(), cur_room == 0, function() set_room(0) end)
        x = x + w_all + 10
    end

    for _, r in ipairs(store.rooms()) do
        local w = theme.text_width(r.name, 14) + 40
        if fits(w) then
            local rid = r.id
            chip(x, w, r.name .. " " .. store.room_count(rid), cur_room == rid, function() set_room(rid) end)
            x = x + w + 10
        end
    end

    local w_new = theme.text_width("新房间", 14) + 50
    if fits(w_new) then
        chip(x, w_new, "+ 房间", false, function()
            theme.defer(function()
                ui_dialog.add_room(app_ref, function()
                    if app_ref then app_ref.reload_home() end
                end)
            end)
        end)
        x = x + w_new + 10
    end

    theme.button(root, 828, 78, 174, 40, "+ 添加宠物箱", 14, C.pink, C.white, function()
        theme.defer(function()
            ui_dialog.add_device(app_ref, function()
                if app_ref then app_ref.reload_home() end
            end)
        end)
    end, 20)
end

--------------------------------------------------------------------
-- 单张设备卡片
--------------------------------------------------------------------
local function open_detail(id)
    theme.defer(function()
        if app_ref then app_ref.open_detail(id) end
    end)
end

local function build_card(d, x, y)
    local id = d.id               -- 闭包里必须用这个局部变量，否则会取到全局 nil
    local h = { id = id, state = {} }
    local card = theme.card(root, x, y, CARD_W, CARD_H, C.card, 22, C.line, 2)
    h.card = card

    -- 顶部宠物色小条（横向内缩，避免顶到圆角外）
    theme.box(card, 26, 0, CARD_W - 52, 5, store.PET_COLOR[d.pet] or C.pink2, 2)

    theme.shape({ parent = card, x = 14, y = 10, w = 44, h = 44,
                  items = icon.pet(d.pet, 44, 44, store.PET_COLOR[d.pet] or C.butter) })

    h.name = theme.label(card, 66, 12, 142, 26, d.name, 19, C.ink)

    local rw = theme.text_width(store.room_name(d.room), 11) + 18
    if rw > 142 then rw = 142 end
    h.room_box = theme.box(card, 66, 40, rw, 18, C.pink2, 9)
    h.room = theme.label_mid(h.room_box, 0, 0, rw, 18, store.room_name(d.room), 11, C.pink, airui.TEXT_ALIGN_CENTER)

    h.st_box = theme.box(card, CARD_W - 102, 14, 88, 26, C.mint2, 13)
    h.st = theme.label_mid(h.st_box, 0, 0, 88, 26, "正常", 13, C.mint, airui.TEXT_ALIGN_CENTER)

    -- 三个指标
    local cells = { { key = "t", x = 16 }, { key = "h", x = 114 }, { key = "g", x = 212 } }
    h.cell = {}
    for _, c in ipairs(cells) do
        local key = c.key
        local cx = c.x
        theme.label(card, cx, 66, 88, 16, store.NAME[key], 11, C.ink3)
        local val = theme.label(card, cx, 82, 54, 28, "--", 22, theme.MCOL[key])
        local unit = theme.label(card, cx + 50, 92, 38, 16, store.UNIT[key], 11, C.ink3)
        local rng = theme.label(card, cx, 110, 88, 16, "", 11, C.ink3)
        local bar = theme.shape({ parent = card, x = cx, y = 128, w = 88, h = 6, items = {} })
        h.cell[key] = { val = val, unit = unit, rng = rng, bar = bar }
    end

    theme.box(card, 16, 142, CARD_W - 32, 2, C.line, 1)

    -- 设备开关
    local function mk(key, x0, text)
        return theme.button(card, x0, 152, 88, 34, text .. " 关", 14, C.tile, C.ink3, function()
            theme.defer(function()
                local dd = store.get(id)
                if not dd then return end
                local on = store.toggle(dd, key)
                M.refresh()
                if app_ref then
                    app_ref.toast(dd.name .. " " .. text .. (on and " 已开启" or " 已关闭"))
                end
            end)
        end, 17)
    end
    h.warm = mk("warm", 16, "暖风")
    h.cool = mk("cool", 114, "冷风")
    h.light = mk("light", 212, "灯光")
    h.col = { warm = C.coral, cool = C.sky, light = C.butter }

    -- 透明热区：点卡片上半部分进详情
    theme.hot(card, 0, 0, CARD_W, 142, function() open_detail(id) end)

    return h
end

local function build_cards()
    local list = store.list(cur_room)
    total_pages = math.max(1, math.ceil(#list / PER_PAGE))
    if page > total_pages then page = total_pages end
    if page < 1 then page = 1 end

    local base = (page - 1) * PER_PAGE
    for i = 1, PER_PAGE do
        local d = list[base + i]
        if d then
            local idx = i - 1
            local x = GX[(idx % 3) + 1]
            local y = GY[math.floor(idx / 3) + 1]
            cards[#cards + 1] = build_card(d, x, y)
        end
    end

    if #cards == 0 then
        local box = theme.card(root, 22, 132, SW - 44, 220, C.card, 22, C.line, 2)
        theme.shape({ parent = box, x = (SW - 44) / 2 - 36, y = 46, w = 72, h = 72,
                      items = icon.pet("rabbit", 72, 72, C.lilac) })
        theme.label_mid(box, 0, 132, SW - 44, 30, "这个房间还空着，点右上角添加一台宠物恒温箱吧", 16, C.ink3, airui.TEXT_ALIGN_CENTER)
    end
end

--------------------------------------------------------------------
-- 底栏
--------------------------------------------------------------------
local function build_bottom()
    lbl_tip = theme.label(root, 22, 552, 760, 20, "", 12, C.ink3)

    local function go(delta)
        theme.defer(function()
            local np = page + delta
            if np < 1 or np > total_pages then return end
            page = np
            M.build(app_ref)
        end)
    end

    -- 只有多页时才建翻页按钮（airui 的 button 没有 set_hidden，靠重建规避）
    if total_pages > 1 then
        btn_prev = theme.tint_button(root, 822, 546, 54, 34, "<", 16, C.card, C.ink2, function() go(-1) end, 17)
        lbl_page = theme.label_mid(root, 880, 546, 72, 34, page .. " / " .. total_pages, 14, C.ink2, airui.TEXT_ALIGN_CENTER)
        btn_next = theme.tint_button(root, 956, 546, 46, 34, ">", 16, C.card, C.ink2, function() go(1) end, 17)
    end
end

--------------------------------------------------------------------
-- 构建 / 刷新 / 销毁
--------------------------------------------------------------------
function M.build(app)
    app_ref = app or app_ref
    M.destroy()

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 14)

    build_topbar()
    build_chips()
    build_cards()
    build_bottom()
    M.refresh()
end

function M.toggle_mute()
    alarm.set_muted(not alarm.muted())
    if app_ref then app_ref.toast(alarm.muted() and "警报音已静音" or "警报音已开启") end
    M.refresh()
end

function M.refresh()
    if not root then return end

    if lbl_clock then lbl_clock:set_text(theme.clock_text()) end
    if lbl_date then lbl_date:set_text(theme.date_text()) end

    local n = store.alarm_devices()
    if lbl_alarm then
        lbl_alarm:set_text(n > 0 and (n .. " 台报警") or "全部正常")
        lbl_alarm:set_color(n > 0 and C.red or C.mint)
        alarm_box:set_color(n > 0 and C.red2 or C.mint2)
    end
    if lbl_mute then
        lbl_mute:set_text(alarm.muted() and "已静音" or "静音")
    end

    for _, c in ipairs(cards) do
        local d = store.get(c.id)
        if d then
            c.name:set_text(d.name)
            local rn = store.room_name(d.room)
            c.room:set_text(rn)

            local st = d.st
            c.st:set_text(st.any and "报警" or "正常")
            c.st:set_color(st.any and C.red or C.mint)
            c.st_box:set_color(st.any and C.red2 or C.mint2)

            for _, key in ipairs(store.ORDER) do
                local cell = c.cell[key]
                local v = (key == "t") and d.temp or (key == "h") and d.hum or d.gas
                local bad = (key == "t") and st.t or (key == "h") and st.h or st.g
                local col = bad and C.red or theme.MCOL[key]

                cell.val:set_text(store.fmt(key, v))
                cell.val:set_color(col)
                cell.unit:set_color(bad and C.red or C.ink3)
                cell.rng:set_text(store.th_range_short(d, key))
                cell.rng:set_color(bad and C.red or C.ink3)

                local lo, hi
                if key == "g" then lo, hi = 0, d.th.g_hi
                elseif key == "t" then lo, hi = d.th.t_lo, d.th.t_hi
                else lo, hi = d.th.h_lo, d.th.h_hi end
                theme.set_items(cell.bar, bar_items(v, lo, hi, 88, col))
            end

            -- 报警卡片：整块描红 + 淡红底，一眼看出是哪一台
            if c.any ~= st.any then
                c.any = st.any
                c.card:set_color(st.any and C.redbg or C.card)
                c.card:set_border_color(st.any and C.red or C.line, st.any and 3 or 2)
            end

            sync_btn(c.state, "warm", c.warm, "暖风", d.dev.warm, c.col.warm)
            sync_btn(c.state, "cool", c.cool, "冷风", d.dev.cool, c.col.cool)
            sync_btn(c.state, "light", c.light, "灯光", d.dev.light, c.col.light)
        end
    end

    if lbl_tip then
        local a = store.last_alarm()
        if a then
            lbl_tip:set_text("最近报警 " .. a.time .. "  " .. a.text)
            lbl_tip:set_color(C.red)
        else
            lbl_tip:set_text(string.format("共 %d 台设备 | %d 个房间 | 温湿度与有毒气体均在安全区间",
                store.count(), #store.rooms()))
            lbl_tip:set_color(C.ink3)
        end
    end

    if lbl_page then
        lbl_page:set_text(page .. " / " .. total_pages)
    end
end

function M.destroy()
    cards = {}
    alarm_box, lbl_alarm, lbl_mute = nil, nil, nil
    lbl_clock, lbl_date, lbl_tip, lbl_page = nil, nil, nil, nil
    btn_prev, btn_next = nil, nil
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
end

return M
