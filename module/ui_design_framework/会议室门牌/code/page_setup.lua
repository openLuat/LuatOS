--[[
@module  page_setup
@summary 会议室门牌 · 门牌设置页（会议室名称 + 离线手动校时，均需管理员密码）
@version 1.0.0
@note 1) 名称只能从预设列表里选：门牌没有中文输入法，硬做中文编辑体验更差；
         预设列表在 app_state.M.room_names 里改。
      2) 名称与校时是「一次保存」：改完点保存，密码通过才同时生效并写 fskv。
      3) 校时会同时写硬件 RTC（若有）和软件基准，见 clock.lua。
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

local PAGE, ROOT

local sel_name = 1                              -- 选中的名称下标
local Y, MO, D, H, MI                       -- 待保存的年月日时分
local pwd = ""
local ui = {}
local name_chips = {}

-- ==================== 小工具 ====================
local function days_in(y, mo)
    if mo == 2 then
        local leap = (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
        return leap and 29 or 28
    end
    if mo == 4 or mo == 6 or mo == 9 or mo == 11 then return 30 end
    return 31
end

local function refresh_pwd()
    if pwd == "" then
        W.set(ui.pwd_lbl, "(未输入)")
        W.color(ui.pwd_lbl, C.text_dim)
    else
        W.set(ui.pwd_lbl, string.rep("*", #pwd))
        W.color(ui.pwd_lbl, C.text)
    end
    if pwd == "" then
        W.set(ui.hint, "输入管理员密码后点「保存设置」")
        W.color(ui.hint, C.text_sub)
    elseif pwd == S.admin_pwd then
        W.set(ui.hint, "密码正确，可以保存")
        W.color(ui.hint, C.ok)
    else
        W.set(ui.hint, "密码错误")
        W.color(ui.hint, C.danger)
    end
end

local function refresh_time_labels()
    W.set(ui.st_year, tostring(Y))
    W.set(ui.st_mon, MO .. " 月")
    W.set(ui.st_day, D .. " 日")
    W.set(ui.st_hour, string.format("%02d", H))
    W.set(ui.st_min, string.format("%02d", MI))
    local wd = S.weekday_of(Y, MO, D)
    W.set(ui.preview, string.format("%02d-%02d %s %02d:%02d", MO, D,
        S.day_names[wd] or "", H, MI))
end

local function clamp_day()
    local maxd = days_in(Y, MO)
    if D > maxd then D = maxd end
    if D < 1 then D = 1 end
end

local function select_name(i)
    sel_name = i
    for k, c in ipairs(name_chips) do c.set_active(k == i) end
end

-- ==================== 步进器 ====================
local function stepper(parent, x, y, w, h, on_minus, on_plus)
    local track = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(track, C.tile, G.tile_opa)
    local function key(px, text, cb)
        local box = airui.container({ parent = track, x = px, y = 4, w = 44, h = h - 8,
            color = C.btn_bg, radius = 10, border_width = 0 })
        W.glass(box, C.btn_bg, 210)
        W.text_mid(track, { text = text, x = px, y = 4, w = 44, h = h - 8, size = 20,
            color = C.text, align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(track, { x = px, y = 4, w = 44, h = h - 8, radius = 10,
            target = box, tx = px, ty = 4, on_click = cb })
    end
    key(4, "-", on_minus)
    key(w - 48, "+", on_plus)
    return W.text_mid(track, { text = "", x = 50, y = 0, w = w - 100, h = h,
        size = 20, color = C.text, align = airui.TEXT_ALIGN_CENTER })
end

-- ==================== 布局 ====================
local function build_topbar()
    local g = W.glass_card({ parent = ROOT, x = TOP.x, y = TOP.y, w = TOP.w, h = TOP.h })
    local p = g.card
    W.text_mid(p, { text = "门牌设置", x = 18, y = 6, w = 300, h = 32, size = 24, color = C.text })
    W.text_mid(p, { text = "会议室名称 / 离线校时 · 修改需要管理员密码", x = 18, y = 38,
        w = 480, h = 20, size = T.f.mini, color = C.text_dim })
    R.theme_chip(p, { x = 700, y = 14, w = 86, h = 36 })
    W.chip(p, { x = 796, y = 14, w = 170, h = 36, text = "返回门牌",
        off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
        on_click = function() R.go("home") end })
end

local function build_left()
    local g = W.glass_card({ parent = ROOT, x = LC.x, y = LC.y, w = LC.w, h = LC.h })
    local p = g.card
    W.text_mid(p, { text = "管理员验证", x = 14, y = 12, w = 180, h = 20,
        size = T.f.mini, color = C.text_dim })
    W.text_mid(p, { text = "管理员密码", x = 14, y = 40, w = 140, h = 20,
        size = T.f.mini, color = C.text_sub })

    local box = airui.container({ parent = p, x = 14, y = 62, w = 268, h = 44,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(box, C.tile, G.tile_opa)
    ui.pwd_lbl = W.text_mid(box, { text = "", x = 8, y = 0, w = 252, h = 44,
        size = 22, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })

    ui.hint = W.text_mid(p, { text = "输入管理员密码后点「保存设置」", x = 14, y = 112,
        w = 268, h = 20, size = T.f.mini, color = C.text_sub })

    ui.numpad = W.numpad(p, { x = 14, y = 146, w = 268, h = 334, gap = 10,
        on_key = function(k)
            if k == "清空" then
                pwd = ""
            elseif k == "退格" then
                if #pwd > 0 then pwd = pwd:sub(1, #pwd - 1) end
            else
                if #pwd < 8 then pwd = pwd .. k end
            end
            refresh_pwd()
        end })
    return g
end

local function build_right()
    local g = W.glass_card({ parent = ROOT, x = RC.x, y = RC.y, w = RC.w, h = RC.h })
    local p = g.card
    W.text_mid(p, { text = "会议室与时间", x = 14, y = 12, w = 200, h = 20,
        size = T.f.mini, color = C.text_dim })

    -- 会议室名称
    W.text_mid(p, { text = "会议室名称", x = 14, y = 40, w = 200, h = 20,
        size = T.f.mini, color = C.text_sub })
    -- 4 列 x 2 行 = 8 个预设位；预设多于 8 个时后面的不画，避免 chip 叠在一起
    for i, name in ipairs(S.room_names) do
        if i > 8 then break end
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        name_chips[i] = W.chip(p, { x = 14 + col * 162, y = 62 + row * 40, w = 152, h = 36,
            text = name, size = T.f.mini,
            off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
            on_click = function() select_name(i) end })
    end

    -- 日期
    W.text_mid(p, { text = "日期（离线手动校准）", x = 14, y = 150, w = 400, h = 20,
        size = T.f.mini, color = C.text_sub })
    ui.st_year = stepper(p, 14, 172, 204, 44,
        function() if Y > 2024 then Y = Y - 1 clamp_day() refresh_time_labels() end end,
        function() if Y < 2035 then Y = Y + 1 clamp_day() refresh_time_labels() end end)
    ui.st_mon = stepper(p, 232, 172, 204, 44,
        function() MO = (MO > 1) and (MO - 1) or 12 clamp_day() refresh_time_labels() end,
        function() MO = (MO < 12) and (MO + 1) or 1 clamp_day() refresh_time_labels() end)
    ui.st_day = stepper(p, 450, 172, 204, 44,
        function() if D > 1 then D = D - 1 refresh_time_labels() end end,
        function() if D < days_in(Y, MO) then D = D + 1 refresh_time_labels() end end)

    -- 时间
    W.text_mid(p, { text = "时间（1 分钟一档）", x = 14, y = 222, w = 400, h = 20,
        size = T.f.mini, color = C.text_sub })
    ui.st_hour = stepper(p, 14, 244, 204, 44,
        function() H = (H > 0) and (H - 1) or 23 refresh_time_labels() end,
        function() H = (H < 23) and (H + 1) or 0 refresh_time_labels() end)
    ui.st_min = stepper(p, 232, 244, 204, 44,
        function() MI = (MI > 0) and (MI - 1) or 59 refresh_time_labels() end,
        function() MI = (MI < 59) and (MI + 1) or 0 refresh_time_labels() end)

    local pv = airui.container({ parent = p, x = 450, y = 244, w = 204, h = 44,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(pv, C.tile, G.tile_opa)
    ui.preview = W.text_mid(pv, { text = "", x = 6, y = 0, w = 192, h = 44,
        size = T.f.mini, color = C.pri, align = airui.TEXT_ALIGN_CENTER })

    -- 说明
    W.text_mid(p, { text = "说明：名称与时间修改需要管理员密码（默认 8888）", x = 14, y = 300,
        w = 644, h = 20, size = T.f.mini, color = C.text_dim })
    W.text_mid(p, { text = "离线时用步进器手动校准，会同时写入硬件 RTC 与本地基准", x = 14, y = 326,
        w = 644, h = 20, size = T.f.mini, color = C.text_dim })
    W.text_mid(p, { text = "设置项存 fskv，掉电重启后保持；名称预设可在 app_state.lua 里增删", x = 14,
        y = 352, w = 644, h = 20, size = T.f.mini, color = C.text_dim })
    W.text_mid(p, { text = "当前时钟：" .. S.clock_text() .. " · " .. S.time_source(),
        x = 14, y = 378, w = 644, h = 20, size = T.f.mini,
        color = S.synced and C.ok or C.warn })

    -- 按钮
    W.button(p, { x = 14, y = 440, w = 180, h = 44, text = "取消", size = T.f.body,
        color = C.tile, opa = G.tile_opa, tcolor = C.text_sub,
        on_click = function() R.go("home") end })
    W.button(p, { x = 206, y = 440, w = 464, h = 44, text = "保存设置", size = T.f.body,
        color = C.pri, tcolor = C.on_accent, on_click = function() M.save() end })
    return g
end

-- ==================== 保存 ====================
function M.save()
    if pwd == "" then
        R.toast("请输入管理员密码")
        return
    end
    if pwd ~= S.admin_pwd then
        R.toast("管理员密码错误")
        pwd = ""
        refresh_pwd()
        return
    end
    S.set_room_name(S.room_names[sel_name])
    local ok, msg = S.set_time(Y, MO, D, H, MI)
    if not ok then
        R.toast(msg or "校时失败")
        return
    end
    R.go_toast("home", nil, "设置已保存")
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
    ui = {}
    name_chips = {}
end

function M.create()
    M.destroy()
    S.refresh()

    -- 带出当前值（当前名称不在预设里时退回第一项）
    sel_name = 1
    for i, name in ipairs(S.room_names) do
        if name == S.room.name then sel_name = i break end
    end
    Y = S.year or 2026
    MO = S.mon
    D = S.day
    H = S.hour
    MI = S.min
    pwd = ""

    PAGE = airui.container({ parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, border_width = 0 })
    ROOT = PAGE

    build_topbar()
    build_left()
    build_right()
    select_name(sel_name)
    refresh_pwd()
    refresh_time_labels()
    log.info("page_setup", "设置页已创建", S.room.name)
end

return M
