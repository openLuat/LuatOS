--[[
@module  ui_detail
@summary 单台宠物恒温箱详情：三指标曲线 + 阈值设置 + 设备开关
@version 1.0
@date    2026.10.28

布局（1024x600）：
  顶栏    0..72     返回 + 头像 + 名称 + 房间 + 报警胶囊 + 静音 + 时钟
  曲线区  84..284   温度 / 湿度 / 有毒气体 三张卡（含阈值带与虚线）
  设置区  296..548  左：阈值 -/+ 步进  右：暖风 / 冷风 / 灯光
  底栏    556..576  提示
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

local PW = 316          -- 曲线卡宽
local PX = { 22, 353, 684 }
local PY = 84
local PH = 200

local root = nil
local app_ref = nil
local dev_id = nil
local panels = nil
local th_rows = nil
local tiles = nil
local alarm_box, lbl_alarm, lbl_mute = nil, nil, nil
local lbl_clock, lbl_date, lbl_name = nil, nil, nil

--------------------------------------------------------------------
-- 曲线图元
--------------------------------------------------------------------
local function chart_items(hist, w, h, lo, hi, col)
    local n = #hist
    if n < 2 then return {} end

    local mn, mx = lo, hi
    for i = 1, n do
        local v = hist[i]
        if v < mn then mn = v end
        if v > mx then mx = v end
    end
    local span = mx - mn
    if span < 0.001 then span = 1 end
    mn, mx = mn - span * 0.16, mx + span * 0.16

    local pad = 4
    local area = h - pad * 2
    local function px(i) return pad + (w - pad * 2) * (i - 1) / (n - 1) end
    local function py(v)
        local k = (v - mn) / (mx - mn)
        if k < 0 then k = 0 elseif k > 1 then k = 1 end
        return pad + area * (1 - k)
    end

    local items = {}
    local y_hi, y_lo = py(hi), py(lo)
    if y_lo > y_hi then
        items[#items + 1] = { type = "rect", x = 0, y = y_hi, w = w, h = y_lo - y_hi,
                              radius = 8, fill = true, fill_color = col, fill_opacity = 26 }
    end
    items[#items + 1] = { type = "line", x1 = 0, y1 = y_hi, x2 = w, y2 = y_hi,
                          color = col, width = 1, opacity = 120, dash_width = 5, dash_gap = 4 }
    items[#items + 1] = { type = "line", x1 = 0, y1 = y_lo, x2 = w, y2 = y_lo,
                          color = col, width = 1, opacity = 120, dash_width = 5, dash_gap = 4 }

    for i = 1, n - 1 do
        items[#items + 1] = { type = "line",
                              x1 = px(i), y1 = py(hist[i]),
                              x2 = px(i + 1), y2 = py(hist[i + 1]),
                              color = col, width = 2 }
    end
    items[#items + 1] = { type = "circle", cx = px(n), cy = py(hist[n]), r = 3,
                          fill = true, fill_color = col }
    return items
end

local function style_tile(obj, name_lbl, st_lbl, on, col)
    if obj then
        obj:set_color(on and col or C.tile)
        obj:set_border_color(on and col or C.line, on and 4 or 2)
    end
    if name_lbl then name_lbl:set_color(on and C.white or C.ink) end
    if st_lbl then
        st_lbl:set_text(on and "已开启" or "已关闭")
        st_lbl:set_color(on and C.white or C.ink3)
    end
end

--------------------------------------------------------------------
-- 顶栏
--------------------------------------------------------------------
local function build_topbar(d)
    theme.box(root, 0, 0, SW, 72, C.bar, 0)
    theme.box(root, 0, 70, SW, 2, C.line, 0)

    theme.tint_button(root, 18, 18, 92, 36, "< 返回", 15, C.card2, C.ink2, function()
        theme.defer(function() if app_ref then app_ref.close_detail() end end)
    end, 18)

    theme.shape({ parent = root, x = 126, y = 12, w = 48, h = 48,
                  items = icon.pet(d.pet, 48, 48, store.PET_COLOR[d.pet] or C.butter) })
    lbl_name = theme.label(root, 184, 10, 220, 36, d.name, 24, C.ink)
    theme.label(root, 186, 46, 300, 18,
        "位于 " .. store.room_name(d.room) .. " | 恒温箱实时监测", 12, C.ink3)

    -- 改名
    theme.tint_button(root, 414, 18, 78, 36, "改名", 14, C.pink2, C.pink, function()
        theme.defer(function()
            ui_dialog.rename_device(app_ref, dev_id, function() M.refresh() end)
        end)
    end, 18)

    alarm_box = theme.box(root, 592, 18, 174, 36, C.mint2, 18)
    lbl_alarm = theme.label_mid(alarm_box, 0, 0, 174, 36, "一切正常", 14, C.mint, airui.TEXT_ALIGN_CENTER)

    lbl_mute = theme.tint_button(root, 776, 18, 88, 36, "静音", 14, C.card2, C.ink2, function()
        theme.defer(function()
            alarm.set_muted(not alarm.muted())
            if app_ref then app_ref.toast(alarm.muted() and "警报音已静音" or "警报音已开启") end
            M.refresh()
        end)
    end, 18)

    lbl_clock = theme.label(root, 872, 8, 132, 28, "", 19, C.ink, airui.TEXT_ALIGN_RIGHT)
    lbl_date = theme.label(root, 872, 38, 132, 18, "", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)
end

--------------------------------------------------------------------
-- 曲线卡
--------------------------------------------------------------------
local function build_panel(d, key, x)
    local box = theme.card(root, x, PY, PW, PH, C.card, 22, C.line, 2)
    local p = { box = box }

    theme.shape({ parent = box, x = 16, y = 12, w = 22, h = 22,
                  items = icon.metric(key, 22, 22, theme.MCOL[key]) })
    theme.label(box, 44, 12, 120, 20, store.NAME[key], 15, C.ink2)

    p.st_box = theme.box(box, PW - 100, 12, 84, 24, C.mint2, 12)
    p.st = theme.label_mid(p.st_box, 0, 0, 84, 24, "正常", 12, C.mint, airui.TEXT_ALIGN_CENTER)

    p.val = theme.label(box, 16, 38, 120, 46, "--", 34, theme.MCOL[key])
    p.unit = theme.label(box, 108, 56, 50, 18, store.UNIT[key], 13, C.ink3)
    p.rng = theme.label(box, 16, 86, PW - 32, 16, "", 12, C.ink3)
    p.chart = theme.shape({ parent = box, x = 16, y = 106, w = PW - 32, h = 78, items = {} })

    return p
end

--------------------------------------------------------------------
-- 阈值设置卡
--------------------------------------------------------------------
local function build_threshold(d)
    local box = theme.card(root, 22, 296, 640, 252, C.card, 22, C.line, 2)
    theme.label(box, 18, 12, 200, 22, "阈值设置", 16, C.ink)
    theme.label(box, 300, 14, 322, 16, "点 - / + 调整，超限立即报警", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)

    th_rows = {}
    local rows = { { key = "t", y = 54 }, { key = "h", y = 120 }, { key = "g", y = 186 } }

    for _, r in ipairs(rows) do
        local key, y = r.key, r.y
        local row = { key = key }

        theme.label(box, 18, y + 12, 80, 20, store.NAME[key], 15, C.ink)

        local function mk_group(tag_x, which, tag)
            theme.label(box, tag_x, y + 13, 44, 18, tag, 11, C.ink3)
            local minus = theme.step_button(box, tag_x + 44, y, 40, "-", 20, function()
                theme.defer(function()
                    store.step_th(d, key, which, -1)
                    M.refresh()
                end)
            end)
            local lbl = theme.label_mid(box, tag_x + 88, y, 80, 40, "", 17, C.ink, airui.TEXT_ALIGN_CENTER)
            theme.step_button(box, tag_x + 168, y, 40, "+", 20, function()
                theme.defer(function()
                    store.step_th(d, key, which, 1)
                    M.refresh()
                end)
            end)
            return lbl
        end

        if key == "g" then
            row.hi = mk_group(104, "hi", "上限")
            theme.label(box, 336, y + 13, 280, 18, "有毒气体只设报警上限", 11, C.ink3)
        else
            row.lo = mk_group(104, "lo", "下限")
            row.hi = mk_group(336, "hi", "上限")
        end

        th_rows[key] = row
    end
end

--------------------------------------------------------------------
-- 设备控制卡
--------------------------------------------------------------------
local function build_devices(d)
    local box = theme.card(root, 678, 296, 324, 252, C.card, 22, C.line, 2)
    theme.label(box, 18, 12, 200, 22, "设备控制", 16, C.ink)

    tiles = {}
    local defs = {
        { key = "warm",  text = "暖风", col = C.coral },
        { key = "cool",  text = "冷风", col = C.sky },
        { key = "light", text = "灯光", col = C.butter },
    }
    for i, it in ipairs(defs) do
        local x = 18 + (i - 1) * 100
        local tile = theme.card(box, x, 52, 88, 124, C.card2, 20, C.line, 2)
        theme.shape({ parent = tile, x = 22, y = 14, w = 44, h = 44,
                      items = icon.ctrl(it.key, 44, 44, it.col) })
        local name = theme.label_mid(tile, 0, 64, 88, 20, it.text, 13, C.ink, airui.TEXT_ALIGN_CENTER)
        local st = theme.label_mid(tile, 0, 86, 88, 18, "已关闭", 11, C.ink3, airui.TEXT_ALIGN_CENTER)

        theme.hot(tile, 0, 0, 88, 124, function()
            theme.defer(function()
                local dd = store.get(dev_id)
                if not dd then return end
                local on = store.toggle(dd, it.key)
                if app_ref then app_ref.toast(dd.name .. " " .. it.text .. (on and " 已开启" or " 已关闭")) end
                M.refresh()
            end)
        end)

        tiles[it.key] = { box = tile, name = name, st = st, col = it.col }
    end

    theme.label(box, 18, 190, 288, 18, "任一参数越界立即鸣音报警", 11, C.ink3)
    theme.tint_button(box, 18, 212, 288, 30, "试听警报音", 13, C.pink2, C.pink, function()
        theme.defer(function()
            if not app_ref then return end
            if not alarm.ready() then
                app_ref.toast("音频不可用：" .. alarm.backend())
                return
            end
            local ok = alarm.play()
            app_ref.toast(ok and "正在试听警报音" or "播放失败，检查 alarm.wav")
        end)
    end, 15)
end

--------------------------------------------------------------------
-- 构建
--------------------------------------------------------------------
function M.build(app, id)
    app_ref = app or app_ref
    M.destroy()

    local d = store.get(id)
    if not d then
        -- 兜底：设备不存在时不要留白屏，直接回主页
        dev_id = nil
        log.warn("ui_detail", "设备不存在", tostring(id))
        if app_ref then app_ref.show_home() end
        return
    end
    dev_id = id

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 14)

    build_topbar(d)

    panels = {}
    panels.t = build_panel(d, "t", PX[1])
    panels.h = build_panel(d, "h", PX[2])
    panels.g = build_panel(d, "g", PX[3])

    build_threshold(d)
    build_devices(d)

    theme.label(root, 22, 556, 980, 18, "提示：温度 / 湿度为上下限双阈值，有毒气体为单一报警上限，修改后立即生效。",
        11, C.ink3)

    M.refresh()
end

--------------------------------------------------------------------
-- 刷新
--------------------------------------------------------------------
function M.refresh()
    if not root then return end
    local d = store.get(dev_id)
    if not d then
        if app_ref then app_ref.close_detail() end
        return
    end

    if lbl_clock then lbl_clock:set_text(theme.clock_text()) end
    if lbl_date then lbl_date:set_text(theme.date_text()) end
    if lbl_name then lbl_name:set_text(d.name) end

    local n = store.alarm_devices()
    if lbl_alarm then
        lbl_alarm:set_text(d.st.any and "本箱报警中" or (n > 0 and (n .. " 台报警") or "一切正常"))
        lbl_alarm:set_color((d.st.any or n > 0) and C.red or C.mint)
        alarm_box:set_color((d.st.any or n > 0) and C.red2 or C.mint2)
    end
    if lbl_mute then lbl_mute:set_text(alarm.muted() and "已静音" or "静音") end

    for _, key in ipairs(store.ORDER) do
        local p = panels[key]
        local v = (key == "t") and d.temp or (key == "h") and d.hum or d.gas
        local bad = (key == "t") and d.st.t or (key == "h") and d.st.h or d.st.g

        p.val:set_text(store.fmt(key, v))
        p.val:set_color(bad and C.red or theme.MCOL[key])
        p.rng:set_text(store.th_range_text(d, key))
        p.rng:set_color(bad and C.red or C.ink3)
        p.st:set_text(bad and "报警" or "正常")
        p.st:set_color(bad and C.red or C.mint)
        p.st_box:set_color(bad and C.red2 or C.mint2)

        -- 报警指标卡整块描红
        if p.bad ~= bad then
            p.bad = bad
            p.box:set_color(bad and C.redbg or C.card)
            p.box:set_border_color(bad and C.red or C.line, bad and 3 or 2)
        end

        local lo, hi
        if key == "g" then lo, hi = 0, d.th.g_hi
        elseif key == "t" then lo, hi = d.th.t_lo, d.th.t_hi
        else lo, hi = d.th.h_lo, d.th.h_hi end
        theme.set_items(p.chart, chart_items(d.hist[key], PW - 32, 78, lo, hi,
            bad and C.red or theme.MCOL[key]))
    end

    if th_rows then
        for _, key in ipairs(store.ORDER) do
            local row = th_rows[key]
            if row then
                if row.lo then row.lo:set_text(store.fmt(key, d.th[key .. "_lo"])) end
                if row.hi then row.hi:set_text(store.fmt(key, d.th[key .. "_hi"])) end
            end
        end
    end

    if tiles then
        for key, t in pairs(tiles) do
            style_tile(t.box, t.name, t.st, d.dev[key], t.col)
        end
    end
end

function M.destroy()
    panels, th_rows, tiles = nil, nil, nil
    alarm_box, lbl_alarm, lbl_mute = nil, nil, nil
    lbl_clock, lbl_date, lbl_name = nil, nil, nil
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    dev_id = nil
end

return M
