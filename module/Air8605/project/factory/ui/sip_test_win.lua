local memdiag = require "sip_mem_diag"
local handoff = require "factory_handoff"
--[[
@module  sip_test_win
@summary 功能测试-SIP通话：factory 主题、底部导航和可选音频自检
@version 3.0
@date    2026.11.04
@description
五个页面：联系人 / 通话记录 / 聊天 / 我的 / 音频自检；通话时全屏通话覆盖层。
复用 factory 主题与内容区；自检可跳过，四项导航固定在底部。
]]

local exwin = require "exwin"
local base_kit = require "ui_kit"
local theme = require "ui_theme"
-- 通话/账号/消息内核整套使用同事原版 SIP_APP（sip_phone/*），UI 仍走本文件缩放层
local raw_app = require "sph_sip_app"
local net = require "sph_net_app"
local store = require "sph_store"
local audio = require "sph_audio_app"
-- 服务端通话记录与账号在线状态取数口（设备网关 HTTPS + RSA），取不到时页面退回本地记录
local api = require "sph_sip_api"
handoff.bind_sip(raw_app, audio)
local diag = require "sph_audio_diag"
local perf = require "audio_perf"

-- ==================== app 适配层：同事 SIP_APP -> 参考话机 UI 语义 ====================
-- 同事内核状态: idle/connecting/ready/dialing/incoming/answering/talking/ending
-- 参考 UI 状态: idle/connecting/registered/dialing/incoming/talking/ending
local app = {}
local function norm_state(raw)
    if raw == "ready" then return "registered" end
    return raw
end
function app.status(snapshot)
    local s = snapshot or raw_app.status(true)
    local st = norm_state(s.state)
    return {
        state = st,
        registered = s.registered == true,
        registration_state = s.registration_state, registration_error = s.registration_error,
        peer = s.peer, number = s.peer,
        direction = s.direction, duration = s.duration, muted = s.muted == true,
        user = s.user,
        text = s.detail or s.text or "",
        user_text = s.registered and ("账号 " .. tostring(s.user or "")) or (s.detail or ""),
        connected_at = s.duration and (os.time() - s.duration) or nil,
    }
end
function app.login(acct) return raw_app.login(acct or store.get_acct()) end
function app.logout() return raw_app.logout() end
function app.dial(n) return raw_app.dial(n) end
function app.accept() return raw_app.answer() end
function app.hangup() return raw_app.hangup() end
function app.send_message(n, t) return raw_app.send_message(n, t) end
function app.toggle_mute()
    local cur = raw_app.status().muted == true
    return raw_app.set_mute(not cur)
end
app.set_mute = function(on) return raw_app.set_mute(on) end

local RW, RH = 1024, 600
local sxk, syk = 1, 1
local function SX(v) return math.floor((v or 0) * sxk + 0.5) end
local function SY(v) return math.floor((v or 0) * syk + 0.5) end
local function SF(v) return math.max(10, math.floor((v or 18) * math.min(sxk, syk) + 0.5)) end

local window_callback
local kit = {}
-- 旧页面颜色语义映射到 factory 当前主题，不改共享 ui_kit。
local color_keys = {
    brand="amber", brand2="amber_light", brand_deep="amber_deep",
    brand_soft="selected", brand_line="stroke_hi", bg="bg", bg_warm="bg",
    card="panel", card_soft="input_bg", text="t1", text2="t2", text3="t3",
    white="panel", white_dark="t2", line="stroke", line_soft="stroke_soft",
    green="green", green_deep="green_deep", red="rose", red_deep="rose_deep",
    blue="cyan", dark1="bg_top", dark2="bg", dark3="bg",
}
kit.C = setmetatable({}, {__index=function(_, key) return theme.C[color_keys[key] or key] end})

--[[父容器为空时一律不建控件

airui 的 container/label 收到 parent = nil 会退化成挂在屏幕根上：控件照画，
但不在任何页面容器里，于是 (a) kit.destroy(host) 删不掉它们，旧图层留在屏幕上成残影，
(b) 坐标变成整屏坐标，列表行直接盖到顶部状态栏。宁可返回 nil 让调用方显式失败。]]
local function need_parent(kind, parent)
    if parent then return true end
    log.error("sip_ui", kind .. " skipped: parent is nil")
    return false
end

function kit.box(parent, o)
    o = o or {}
    if not need_parent("box", parent) then return nil end
    return theme.box(parent, {
        x = SX(o.x), y = SY(o.y), w = SX(o.w), h = SY(o.h),
        color = o.color, opa = o.opacity, radius = o.radius or 0,
        border = o.border and (o.border_color or theme.C.stroke) or nil, border_w = o.border_width,
        on_click = window_callback(o.on_click), on_long_press = window_callback(o.on_long_press),
        scrollable = o.scroll, clip_corner = o.clip ~= false,
    })
end
function kit.label(parent, o)
    o = o or {}
    if not need_parent("label", parent) then return nil end
    return theme.label(parent, {
        x = SX(o.x), y = SY(o.y), w = SX(o.w), h = SY(o.h),
        text = o.text, px_size = SF(o.size), color = o.color,
        align = o.align, on_click = window_callback(o.on_click),
    })
end
function kit.card(parent, o)
    o = o or {}
    if not need_parent("card", parent) then return nil end
    return theme.card(parent, {
        x=SX(o.x), y=SY(o.y), w=SX(o.w), h=SY(o.h),
        color=o.color, opa=o.color and 255 or nil, radius=o.radius or theme.R.lg,
        scrollable=o.scroll, clip_corner=true, on_click=window_callback(o.on_click), on_long_press=window_callback(o.on_long_press),
    })
end
function kit.btn(parent, o)
    o = o or {}
    if not need_parent("button", parent) then return nil end
    local C = kit.C
    local kind = o.kind or "primary"
    local bg, fg, bcol, bw, pressed
    if kind == "primary" then bg, fg, pressed = C.brand, C.white, C.brand_deep
    elseif kind == "green" then bg, fg, pressed = C.green, C.white, C.green_deep
    elseif kind == "red" then bg, fg, pressed = C.red, C.white, C.red_deep
    elseif kind == "ghost" then bg, fg, bcol, bw, pressed = C.white, C.brand, C.brand_line, 1, C.brand_soft
    elseif kind == "soft" then bg, fg, pressed = C.brand_soft, C.brand, C.brand_line
    elseif kind == "plain" then bg, fg, pressed = C.card_soft, C.text2, C.brand_soft
    else bg, fg, pressed = C.bg_warm, C.text, C.brand_soft end
    if kind == "primary" or kind == "green" or kind == "red" then fg = theme.ink(bg) end
    return theme.button(parent, {
        x=SX(o.x), y=SY(o.y), w=SX(o.w), h=SY(o.h), text=o.text or "",
        size=SF(o.size)/(theme.dp(100)/100), bg=bg, fg=fg,
        border=bcol or bg, border_w=bw or 0, radius=o.radius or theme.R.md,
        pressed=pressed, on_click=window_callback(o.on_click),
    })
end
function kit.avatar(parent, o)
    o = o or {}
    -- 坐标/直径均按参考基准缩放；通话层传的是实际像素（sxk=1 时一致）
    local d = o.size or 56
    local fs = o.font_size or base_kit.FS.h3
    local box = kit.box(parent, { x = o.x, y = o.y, w = d, h = d, color = o.color or kit.C.brand, radius = math.floor(d / 2) })
    if not box then return nil end
    kit.label(box, { x = 0, y = math.floor((d - fs) / 2) - 2, w = d, h = fs + 4,
        text = o.text, size = o.font_size or base_kit.FS.h3, color = theme.ink(o.color or kit.C.brand), align = airui.TEXT_ALIGN_CENTER })
    return box
end
function kit.input(parent, o)
    o = o or {}
    local wrap = kit.box(parent, { x = o.x, y = o.y, w = o.w, h = o.h, color = kit.C.white, radius = o.radius or 12,
        border = true, border_color = o.border_color or kit.C.brand_line })
    if not wrap then return nil end
    local th = SY(o.h) or SF(46)
    local ta = airui.textarea({
        parent = wrap,
        x = SX(8), y = math.max(2, math.floor((th - SF(o.size or 18) - 8) / 2)),
        w = SX(o.w or 200) - SX(16), h = SF(o.size or 18) + 10,
        text = o.text or "", placeholder = o.placeholder or "",
        max_len = o.max_len or 64, mode = o.password and "password" or "normal",
        font_size = SF(o.size or 18), align = airui.TEXT_ALIGN_LEFT,
        on_text_change = window_callback(o.on_change),
        style = { bg_color = kit.C.white, text_color = kit.C.text, radius = 0 },
    })
    return ta
end
function kit.grad(parent, x, y, w, h, c1, c2, steps)
    return base_kit.grad(parent, SX(x), SY(y), SX(w), SY(h), c1, c2, steps)
end
function kit.destroy(obj)
    -- base_kit.destroy 内部 pcall 吞错：控件没删掉时旧图层会留在屏幕上，
    -- 玻璃卡片半透明，残影直接透出来。这里把失败显式记下来，便于定位。
    if not obj then return end
    local ok, err = pcall(obj.destroy, obj)
    if not ok then log.warn("sip_ui", "destroy failed", tostring(err)) end
end
function kit.ellipsis(s, n) return base_kit.ellipsis(s, n) end
function kit.first_char(s) return base_kit.first_char(s) end

local C = kit.C
local M = {}

local root, host, shell, clock_label, page_title, status_dot, status_color
local page, selected_peer, panel, keyboard, call_layer, call_timer
local call_name, call_clock, call_left, call_right, call_peer
local clock_timer, window_id
local call_left_disabled, call_right_disabled
local status_cache = {}
local call_layer_state, call_sub   -- 通话层当前状态与副标题标签，用于同状态只改文字不重建
local toast_box, toast_timer, started
local page_scroll, diag_label, profile_status, diag_timer
local lifecycle = 0
local closing = false
local timers, subscriptions = {}, {}
local return_timer
local function alive(session)
    return session == lifecycle and not closing and root ~= nil
end
window_callback = function(fn)
    if not fn then return nil end
    local session = lifecycle
    return function(...)
        if alive(session) then return fn(...) end
    end
end
-- 毫秒时钟（与 audio_perf 同一套取法）：只用来量入口几段同步过程的耗时
local function ms_now()
    if mcu and mcu.ticks2 then
        local s, us = mcu.ticks2(0)
        return s * 1000 + (us or 0) / 1000
    end
    return os.time() * 1000
end
local function window_timer(fn, delay, repeating)
    local owned = timers
    local id
    local callback = window_callback(fn)
    local function tick(...)
        if not repeating then owned[id] = nil end
        return callback(...)
    end
    id = (repeating and sys.timerLoopStart or sys.timerStart)(tick, delay)
    if id then owned[id] = true end
    return id
end
local function stop_window_timer(id)
    if not id then return end
    sys.timerStop(id)
    timers[id] = nil
end
local function subscribe(event, fn)
    local callback = window_callback(fn)
    subscriptions[event] = callback
    sys.subscribe(event, callback)
end
local function cleanup(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log.warn("sip_ui", "cleanup failed", name, tostring(err)) end
    return ok
end
local dial_number = ""
local drafts = {}
local text_cache = setmetatable({}, { __mode = "k" })
local RECORDS_VISIBLE = 10
local W, H, LEFT, TOP = RW, RH, 20, 84
local NAV_H = 64
local PW, PH = RW - 40, RH - TOP - NAV_H - 16
local render, render_call, refresh_status, request_render
-- 建树代次：整页重建会递增，前一次 render 留下的分拍回调据此作废
local render_seq = 0
local page_contacts, page_records, page_chats, page_profile, page_diag
local build_shell, show_call_layer, input_keyboard, edit, confirm, contact_editor
local top_status, suspended
-- 归一化后的通话态集合
local call_states = { incoming = true, dialing = true, talking = true, answering = true, ending = true }
local function busy() return call_states[app.status().state] == true end

local function label(parent, x, y, w, text, size, color, h)
    return kit.label(parent, { x = x, y = y, w = w, h = h or ((size or 20) + 10), text = text or "", size = size or 20, color = color or C.text })
end
local function button(parent, x, y, w, text, fn, kind, h)
    return kit.btn(parent, { x = x, y = y, w = w, h = h or 46, text = text, on_click = fn, kind = kind or "primary", size = 18 })
end
local function set_text(obj, text)
    text = text or ""
    if obj and text_cache[obj] ~= text then
        -- 控件可能已被 render/切页销毁；底层访问会抛
        -- "access destroyed airui.xxx"，这里静默放弃本次更新。
        local ok = pcall(function() obj:set_text(text) end)
        if ok then text_cache[obj] = text else text_cache[obj] = nil end
    end
end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function success(ok, err)
    if not ok then M.toast(err or "操作失败，请检查日志", true); return false end
    return true
end
local function change_volume(value)
    if not success(audio.set_volume(value)) then return false end
    local saved, why = store.set_vol(value)
    return success(saved ~= nil and saved ~= false, why)
end

function M.toast(text, is_error)
    if not root or closing then return end
    local measured = perf.begin("ui")
    if toast_timer then stop_window_timer(toast_timer) end
    kit.destroy(toast_box)
    toast_box = kit.box(root, { x = 210, y = 12, w = 600, h = 42, color = is_error and C.red or C.dark1, radius = 14 })
    label(toast_box, 14, 7, 572, tostring(text), 18, is_error and theme.ink(C.red) or C.text)
    toast_timer = window_timer(function() kit.destroy(toast_box); toast_box = nil; toast_timer = nil end, 3000)
    perf.finish("ui", measured)
end

local function close_panel()
    suspended = false
    if keyboard then kit.destroy(keyboard); keyboard = nil end
    kit.destroy(panel); panel = nil
end

-- 固定固件原生键盘附带 IME；账号/密码用纯 ASCII 按键。中文/ASCII 共享同一 textarea。
input_keyboard = function(parent, target, options, commit)
    local native, ascii, mode
    local upper = false
    local api = {}
    local function append(text)
        local current = target:get_text()
        if (utf8.len(current) or #current) + #text > (options.max_len or 128) then return end
        target:set_text(current .. text)
    end
    local function erase()
        local value = target:get_text(); local offset = utf8.offset(value, -1)
        if offset then target:set_text(value:sub(1, offset - 1)) end
    end
    local function paint_ascii()
        kit.destroy(ascii)
        ascii = kit.box(parent, { x = 0, y = 376, w = RW, h = 224, color = C.white })
        local rows = mode == "special" and { "1234567890", "!@#$%^&*()", "-_=+[]{}:;", "'\"/\\,.-<>|" }
            or { "1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm@.-" }
        for r, chars in ipairs(rows) do
            for i = 1, #chars do
                local key = chars:sub(i, i); if upper then key = key:upper() end
                button(ascii, 12 + (i - 1) * 91, (r - 1) * 43 + 4, 84, key, function() append(key) end, "plain", 38)
            end
        end
        button(ascii, 12, 177, 135, upper and "小写" or "大写", function() upper = not upper; paint_ascii() end, "soft", 40)
        button(ascii, 159, 177, 135, mode == "special" and "字母" or "符号", function()
            mode = mode == "special" and "text" or "special"; paint_ascii()
        end, "soft", 40)
        button(ascii, 306, 177, 278, "空格", function() append(" ") end, "plain", 40)
        button(ascii, 596, 177, 170, "删除", erase, "soft", 40)
        button(ascii, 778, 177, 234, "完成", commit, "primary", 40)
    end
    function api:set_layout(value)
        mode = value
        if native then native:hide() end
        if ascii then ascii:hide() end
        if value == "pinyin_26" and options.chinese then
            if not native then
                native = assert(theme.keyboard({ parent = parent, x = 0, y = 0, w = SX(RW), h = SY(224), mode = "pinyin_26",
                    auto_hide = false, preview = false, font_size = SF(20), bg_color = C.white, on_commit = window_callback(commit) }), "AirUI keyboard unavailable")
                target:attach_keyboard(native); native:set_target(target)
            end
            native:set_layout("pinyin_26"); native:show()
        else
            kit.destroy(native); native = nil
            paint_ascii()
        end
    end
    function api:hide() if native then native:hide() end; if ascii then ascii:hide() end end
    function api:show() if mode == "pinyin_26" and native then native:show() elseif ascii then ascii:show() end end
    function api:destroy() kit.destroy(native); kit.destroy(ascii); native = nil; ascii = nil end
    api:set_layout(options.chinese and "pinyin_26" or "text")
    return api
end

-- 编辑面板固定上部，键盘预留底部 224px；保存按钮不跟随滚动。
edit = function(title, value, on_save, options)
    if busy() then return M.toast("通话结束后再编辑", true) end
    close_panel(); options = options or {}
    panel = kit.box(root, { x = 0, y = 0, w = RW, h = RH, color = 0x000000, opacity = 130 })
    local card = kit.card(panel, { x = 100, y = 20, w = 824, h = 300, radius = 24 })
    label(card, 24, 20, 770, title, 26)
    label(card, 24, 59, 770, options.hint or "输入后点击保存，中文可切换拼音键盘", 16, C.text3)
    local value_ref
    value_ref = kit.input(card, { x = 24, y = 92, w = 776, h = 66, text = value or "", password = options.password,
        max_len = options.max_len or 128, size = 24, on_change = function() if value_ref and options.on_change then options.on_change(value_ref:get_text()) end end })
    local function save()
        local s = value_ref:get_text()
        if options.trim ~= false then s = trim(s) end
        if on_save(s) ~= false then close_panel(); request_render() end
    end
    button(card, 24, 218, 130, "取消", close_panel, "plain")
    button(card, 650, 218, 150, options.submit or "保存", save)
    keyboard = input_keyboard(panel, value_ref, options, save)
    if options.chinese then
        button(card, 176, 218, 130, "中文拼音", function() keyboard:set_layout("pinyin_26"); keyboard:show() end, "soft")
    end
    button(card, 326, 218, 118, "英文", function() keyboard:set_layout("text"); keyboard:show() end, "soft")
    button(card, 458, 218, 118, "数字符号", function() keyboard:set_layout("special"); keyboard:show() end, "soft")
end

confirm = function(title, fn)
    close_panel()
    panel = kit.box(root, { x = 0, y = 0, w = RW, h = RH, color = 0x000000, opacity = 130 })
    local c = kit.card(panel, { x = 252, y = 190, w = 520, h = 210 })
    label(c, 28, 30, 464, title, 22, C.text, 72)
    button(c, 28, 132, 190, "取消", close_panel, "plain")
    button(c, 302, 132, 190, "确认", function()
        if fn() ~= false then close_panel(); request_render() end
    end, "red")
end

local function call(num)
    success(app.dial(num))
end

contact_editor = function(contact)
    contact = contact or {}
    local original = contact.name ~= nil and contact.num or nil
    local current = { name = contact.name or "", num = contact.num or dial_number }
    local function ask_name()
        edit(original and "编辑联系人备注" or "联系人备注", current.name, function(name)
            current.name = name ~= "" and name or current.num
            if not success(store.save_contact(current.name, current.num)) then return false end
            M.toast("联系人已保存")
        end, { chinese = true, max_len = 48 })
    end
    if contact.is_default then ask_name(); return end
    if original then
        close_panel()
        panel = kit.box(root, { x = 0, y = 0, w = RW, h = RH, color = 0x000000, opacity = 130 })
        local card = kit.card(panel, { x = 252, y = 150, w = 520, h = 280 })
        label(card, 28, 24, 464, store.display(original), 24)
        label(card, 28, 64, 464, original, 20, C.text3)
        button(card, 28, 112, 220, "修改备注", ask_name, "soft")
        button(card, 272, 112, 220, "修改号码", function()
            edit("修改联系人号码", original, function(num)
                if not success(store.update_contact(original, current.name, num)) then return false end
                M.toast("号码已更新")
            end, { max_len = 64, hint = "已有通话和消息记录仍按原号码保留" })
        end, "soft")
        button(card, 28, 196, 464, "返回", close_panel, "plain")
        return
    end
    edit("新增联系人：SIP 号码", current.num, function(num)
        if num == "" then M.toast("请输入号码", true); return false end
        current.num = num
        window_timer(ask_name, 10)
    end, { max_len = 64, hint = "填写 SIP 账号或分机号" })
end

local function empty(parent, text, width) label(parent, 22, 40, (width or PW) - 44, text, 22, C.text3, 70) end
local function row(parent, y, title, subtitle, w, reserved, dot)
    local text_w = w - 36 - (reserved or 0)
    local r = kit.card(parent, { x = 0, y = y, w = w, h = 88, radius = 16 })
    if not r then return nil end
    label(r, 16, 12, text_w, kit.ellipsis(title, 23), 21)
    local sx = 16
    if dot then
        -- 在线状态灯：只有网关返回了状态才着色，未知状态留空心灰环
        kit.box(r, { x = 16, y = 54, w = 12, h = 12, radius = 6, color = dot,
            border = true, border_color = 0x999999, border_width = 1 })
        sx = 36
    end
    label(r, sx, 48, text_w - (sx - 16), kit.ellipsis(subtitle, 38), 16, C.text3)
    return r
end

-- ==================== 联系人在线状态（设备网关 /accounts/status） ====================
-- 每次进联系人页只查一次：查完置 presence_state，回包 render() 不会再发起第二次请求。
local PRESENCE_COLOR = { online = C.green, ringing = C.brand, in_call = C.blue, offline = 0x999999 }
local presence_names = { online = "在线", ringing = "响铃", in_call = "通话中", offline = "离线" }
local presence_cache, presence_state, presence_error, presence_updated = {}, nil, nil, nil

-- 文案压在一行内：theme.label 默认自动换行、行高 = 字号 + 3，
-- 一旦换出第二行就会溢出盒子，直接压到下面的列表行上。
local function presence_caption()
    if presence_state == nil or presence_state == "loading" then return "正在查询在线状态" end
    if presence_error then return kit.ellipsis("查询失败:" .. tostring(presence_error), 15) end
    return presence_updated and ("在线 " .. os.date("%H:%M:%S", presence_updated)) or "尚无在线状态"
end

local function load_presence(items)
    if presence_state ~= nil then return end
    if not items or #items == 0 then presence_state = "empty"; return end
    local numbers = {}
    for _, c in ipairs(items) do numbers[#numbers + 1] = c.num end
    local account = api.account()
    presence_state = "loading"
    sys.taskInit(function()
        local ok, data, err = pcall(api.statuses, numbers, account)
        if not ok then data, err = nil, tostring(data) end
        if data then
            presence_cache, presence_error, presence_updated = data, nil, os.time()
            presence_state = "ok"
        else
            presence_error = err or "网络不可用"
            presence_state = "err"
        end
        if page == "contacts" and not closing then request_render() end
    end)
end

page_contacts = function()
    local list_w = PW - 330
    label(host, 0, 0, list_w - 140, "联系人", 28)
    button(host, list_w - 130, 0, 120, "新增", function() contact_editor() end, "ghost", 40)
    local legend = { { "在线", C.green }, { "响铃", C.brand }, { "通话中", C.blue }, { "离线", 0x999999 }, { "未获取", C.white } }
    for i, item in ipairs(legend) do
        local x = (i - 1) * 82
        kit.box(host, { x = x, y = 42, w = 10, h = 10, radius = 5, color = item[2], border = true, border_color = 0x999999 })
        label(host, x + 15, 36, 62, item[1], 15, C.text2, 22)
    end
    label(host, 418, 36, math.max(120, list_w - 418), presence_caption(), 15, C.text2, 22)
    -- 列表区：滚动容器建不出来时退回不可滚动版本，避免整批行挂到屏幕根上
    local list = kit.box(host, { x = 0, y = 68, w = list_w, h = PH - 68, scroll = true })
        or kit.box(host, { x = 0, y = 68, w = list_w, h = PH - 68 })
    if not list then
        label(host, 0, 72, list_w, "联系人列表创建失败", 20, C.red)
        return
    end
    local items = store.get_contacts()
    if store.read_failed("contacts") then
        label(list,0,0,list_w,"联系人读取失败",20)
        button(list,0,48,120,"重试",function() request_render() end,"soft")
        return
    end
    load_presence(items)
    if #items == 0 then empty(list, "还没有联系人\n右侧输入号码，或点击新增", list_w) end
    for i, c in ipairs(items) do
        local p = presence_cache[c.num]
        local state_text = p and presence_names[p.status]
        row(list, (i - 1) * 142,
            (c.name ~= "" and c.name or c.num) .. (c.is_default and " · 默认" or ""),
            c.num .. (state_text and (" · " .. state_text) or ""),
            list_w - 12, 0, p and PRESENCE_COLOR[p.status])
        button(list, 8, (i - 1) * 142 + 92, 100, "拨号", function() call(c.num) end, "green", 40)
        button(list, 118, (i - 1) * 142 + 92, 100, "编辑", function() contact_editor(c) end, "soft", 40)
        if not c.is_default then button(list, 228, (i - 1) * 142 + 92, 100, "删除", function()
            confirm("删除联系人 " .. (c.name~="" and c.name or c.num) .. "？", function() return success(store.del_contact(c.num)) end)
        end, "plain", 40) end
    end
    local pad = kit.card(host, { x = list_w + 12, y = 0, w = 318, h = PH, radius = 22 })
    if not pad then return end
    label(pad, 18, 16, 282, "拨号盘", 22)
    local display = label(pad, 18, 54, 282, dial_number ~= "" and dial_number or "请输入号码", 28, C.brand, 44)
    local function update() set_text(display, dial_number ~= "" and dial_number or "请输入号码") end
    -- 所有按键根据可用高度布局，拨号键始终在卡片内，不依赖滚动露出。
    local key_top, key_gap = 102, 8
    local dial_h, action_h, bottom = 48, 34, 12
    local dial_y = PH - bottom - dial_h
    local action_y = dial_y - key_gap - action_h
    local key_h = math.floor((action_y - key_gap - key_top - 3 * key_gap) / 4)
    local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
    for i, k in ipairs(keys) do
        button(pad, 16 + ((i - 1) % 3) * 98, key_top + math.floor((i - 1) / 3) * (key_h + key_gap), 90, k, function()
            if #dial_number < 32 then dial_number = dial_number .. k; update() end
        end, "soft", key_h)
    end
    button(pad, 16, action_y, 90, "删除", function() dial_number = dial_number:sub(1, -2); update() end, "plain", action_h)
    button(pad, 114, action_y, 90, "清空", function() dial_number = ""; update() end, "plain", action_h)
    button(pad, 212, action_y, 90, "保存", function() contact_editor({ num = dial_number }) end, "ghost", action_h)
    button(pad, 16, dial_y, 286, "拨号", function() call(dial_number) end, "green", dial_h)
end

local record_page = 1
-- 服务端通话记录（设备网关 /calls，每页 20 条）。
-- record_state 与 presence_state 同一套语义：nil=待取 / ok=有数据 / err=退回本地记录。
local RECORDS_PAGE_SIZE = 20
local records_data, record_state, record_error = nil, nil, nil

-- 同 presence_caption：一律压一行，盒高只给一行的量，换行会溢出压到下面的记录行
local function record_caption(total)
    local text
    if record_state == nil or record_state == "loading" then text = "正在查询服务端通话记录…"
    elseif record_state == "err" then
        text = "服务端记录不可用：" .. tostring(record_error or "网络不可用") .. "，以下为本地记录"
    else
        local pages = math.max(1, math.ceil((tonumber(total) or 0) / RECORDS_PAGE_SIZE))
        text = "第 " .. record_page .. " / " .. pages .. " 页 · 共 " .. tostring(total or 0) .. " 条 · 服务端记录"
    end
    return kit.ellipsis(text, 46)
end

local function load_records(force)
    if not force and record_state ~= nil then return end
    record_state = "loading"
    local want, account = record_page, api.account()
    sys.taskInit(function()
        local ok, data, err = pcall(api.calls, want, account, force == true)
        if not ok then data, err = nil, tostring(data) end
        if want ~= record_page then return end -- 期间翻了页，这包作废
        if data then
            records_data, record_error, record_state = data, nil, "ok"
        else
            records_data, record_error, record_state = nil, err or "网络不可用", "err"
        end
        if page == "records" and not closing then request_render() end
    end)
end

local function server_rows(list, data)
    local function num(v) return (tostring(v or ""):gsub("^sip:", ""):match("^[^@]+") or tostring(v or "")) end
    local mine = num(api.account())
    if #data.calls == 0 then empty(list, "暂无通话记录") end
    for i, c in ipairs(data.calls) do
        local y = (i - 1) * 100
        local out = num(c.caller) == mine
        local peer = num(out and c.callee or c.caller)
        local dur = tonumber(c.billsec) or tonumber(c.durationSec)
        local t = type(c.startTime) == "string" and c.startTime:sub(1, 19):gsub("T", " ") or "时间未知"
        local detail = (out and "呼出" or "呼入") .. " / " .. (c.answered == true and "已接通" or "未接通") ..
            " / " .. t .. " / " .. (dur and store.fmt_dur(math.max(0, dur)) or "--")
        row(list, y, peer, detail, PW - 12, 150)
        button(list, PW - 150, y + 22, 120, "回拨", function() call(peer) end, "green")
    end
end

page_records = function()
    label(host,0,0,PW-470,"通话记录",28)
    button(host,PW-460,0,140,"刷新",function() load_records(true) end,"ghost",40)
    button(host,PW-300,0,148,"新增联系人",function() contact_editor() end,"soft",40)
    button(host,PW-140,0,140,"清空记录",function()
        confirm("清空全部本地通话记录？",function() return success(store.clear_calls()) end)
    end,"ghost",40)
    load_records()
    local server_mode = (record_state == "ok" and records_data ~= nil)
    local list=kit.box(host,{x=0,y=92,w=PW,h=server_mode and (PH-150) or (PH-100),scroll=true})
        or kit.box(host,{x=0,y=92,w=PW,h=server_mode and (PH-150) or (PH-100)})
    if not list then
        label(host,0,96,PW,"通话记录列表创建失败",20,C.red)
        return
    end
    if server_mode then
        label(host,0,48,PW,record_caption(records_data.total),20)
        server_rows(list, records_data)
        local total = tonumber(records_data.total) or 0
        button(host,PW-264,PH-46,120,"上一页",function()
            if record_page <= 1 then return end
            record_page=record_page-1;records_data=nil;record_state=nil;request_render()
        end,"ghost",40)
        button(host,PW-132,PH-46,120,"下一页",function()
            if record_page * RECORDS_PAGE_SIZE >= total then return end
            record_page=record_page+1;records_data=nil;record_state=nil;request_render()
        end,"ghost",40)
        return
    end
    if store.read_failed("calls") then
        label(host,0,64,PW,"记录读取失败，原数据未清空",22)
        button(host,0,110,160,"重试",function() request_render() end,"soft")
        return
    end
    label(host,0,48,PW,record_caption(),20)
    local items=store.get_calls()
    if #items==0 then empty(list,"暂无通话记录") end
    for i=1,math.min(5,#items) do
        local c=items[i];local y=(i-1)*100
        local detail=(c.dir=="out" and "呼出" or "呼入").." / "..store.fmt_time(c.ts).." / "..store.fmt_dur(c.dur)
        row(list,y,c.num or "",detail,PW-12,150)
        button(list,PW-150,y+22,120,"回拨",function() call(c.num) end,"green")
    end
end

local function new_chat()
    if busy() then return end
    close_panel()
    panel = kit.box(root, {x=0,y=0,w=RW,h=RH,color=theme.C.scrim,opacity=130})
    local card = kit.card(panel, {x=152,y=48,w=720,h=504})
    label(card, 24, 20, 672, "新建聊天 / 选择联系人", 26)
    button(card, 24, 78, 220, "手动输入账号", function()
        edit("新建聊天：SIP 账号", "", function(num)
            if num == "" then M.toast("请输入对方账号", true); return false end
            selected_peer = num; page = "chats"
        end, {max_len=64,hint="对端和 SIP 服务器需支持 MESSAGE 文本消息"})
    end, "soft", 44)
    button(card, 548, 78, 148, "取消", close_panel, "plain", 44)
    local list = kit.box(card, {x=24,y=140,w=672,h=340,scroll=true})
    local contacts = store.get_contacts()
    if #contacts == 0 then label(list, 12, 24, 648, "暂无联系人，可手动输入账号", 20, C.text2) end
    for i,c in ipairs(contacts) do
        local title = c.name ~= "" and (c.name .. " / " .. c.num) or c.num
        if c.is_default then title = "默认 / " .. title end
        button(list, 0, (i-1)*66, 656, title, function() M.open("chats",c.num) end, "plain", 56)
    end
end
local msg_names = { pending = "发送中", sending = "发送中", sent = "服务端接受", accepted = "服务端接受", failed = "发送失败", unknown = "结果未知", recv = "收到" }
local function compose()
    if not selected_peer then return new_chat() end
    local peer = selected_peer
    edit("发送给 " .. store.display(peer), drafts[peer] or "", function(text)
        if text == "" then M.toast("消息不能为空", true); return false end
        if not success(app.send_message(peer, text)) then return false end
        drafts[peer] = ""
    end, { chinese = true, max_len = 256, trim = false, submit = "发送", hint = "文本 MESSAGE · 发送成功表示服务器接受，不代表对方已读",
        on_change = function(v) drafts[peer] = v end })
end

page_chats = function()
    local lw = 270
    label(host, 0, 0, 200, "聊天", 28)
    button(host, PW - 140, 0, 140, "新建聊天", new_chat, "ghost", 40)
    local list = kit.box(host, { x = 0, y = 56, w = lw, h = PH - 56, scroll = true })
    local threads = store.threads()
    if #threads == 0 then label(list, 12, 30, lw - 24, "暂无聊天\n点击新建聊天开始", 20, C.text3, 80) end
    for i, t in ipairs(threads) do
        local r = kit.card(list, { x = 0, y = (i - 1) * 105, w = lw - 10, h = 96, color = t.num == selected_peer and C.brand_soft or C.white,
            on_click = function() M.open("chats", t.num) end })
        label(r, 14, 12, lw - 38, kit.ellipsis(store.display(t.num), 12), 20)
        label(r, 14, 43, lw - 38, kit.ellipsis(t.last or "", 16), 16, C.text3)
        label(r, 14, 69, lw - 38, (t.unread or 0) > 0 and (tostring(t.unread) .. " 条未读") or store.fmt_time(t.ts), 14, C.brand)
    end
    if not selected_peer then
        label(host, lw + 32, 160, PW - lw - 50, "选择会话，或新建聊天", 25, C.text3)
        return
    end
    local peer = selected_peer
    store.mark_read(peer)
    local x = lw + 14; local width = PW - x
    label(host, x, 56, width - 140, kit.ellipsis(store.display(peer), 20), 22)
    button(host, PW - 116, 52, 116, "删除会话", function()
        confirm("删除该会话的本地记录？", function()
            if not success(store.delete_thread(peer)) then return false end
            drafts[peer] = nil; selected_peer = nil
        end)
    end, "plain", 36)
    local messages = kit.box(host, { x = x, y = 102, w = width, h = PH - 174, scroll = true })
    page_scroll = messages
    local y = 0
    for _, m in ipairs(store.thread_msgs(peer)) do
        local lines = 0
        for line in ((m.text or "") .. "\n"):gmatch("(.-)\n") do
            local chars = utf8.len(line) or #line
            lines = lines + math.max(1, math.ceil(chars / 20))
        end
        local bh = math.max(94, lines * 25 + 56)
        local outgoing = m.dir == "out"
        local r = kit.card(messages, { x = outgoing and 34 or 0, y = y, w = width - 46, h = bh, color = outgoing and C.brand_soft or C.white })
        label(r, 14, 10, width - 74, m.text, 18, C.text, bh - 45)
        label(r, 14, bh - 30, width - 100, store.fmt_time(m.ts) .. " · " .. (msg_names[m.status] or m.status or "收到"), 14, C.text3)
        if outgoing and m.status == "failed" then
            button(r, width - 140, bh - 36, 80, "重试", function()
                confirm("原消息可能已到达，仍要重新发送？", function()
                    local ok, err
                    if app.retry_message and m.id then ok, err = app.retry_message(m.id) else ok, err = app.send_message(peer, m.text) end
                    return success(ok, err)
                end)
            end, "ghost", 30)
        end
        y = y + bh + 12
    end
    if y == 0 then label(messages, 16, 24, width - 40, "还没有消息", 20, C.text3) end
    button(host, x, PH - 58, 118, "拨号", function() call(peer) end, "green", 48)
    button(host, x + 132, PH - 58, width - 132, "写消息", compose, "primary", 48)
    window_timer(function()
        if started and page == "chats" and page_scroll == messages then
            pcall(function() messages:scroll(0, y + 100) end)
        end
    end, 80)
end

page_profile = function()
    local a = store.get_acct()
    local s = app.status()
    label(host, 0, 0, 500, "我的", 28)
    local left = kit.card(host, { x = 0, y = 54, w = 390, h = PH - 54, scroll = true })
    local online = s.registered
    kit.avatar(left, { x = 22, y = 24, size = 74, text = kit.first_char(online and s.user or a.user), font_size = 28 })
    label(left, 112, 28, 256, online and kit.ellipsis(s.user, 14) or "未登录", 23, C.text, 34)
    label(left, 112, 64, 256, kit.ellipsis(a.server, 22), 16, C.text3)
    local status_line = kit.label(left, { x = 22, y = 116, w = 346, h = 44, text = s.user_text or s.text or "", size = 18, color = C.brand })
    profile_status = status_line
    button(left, 22, 178, 158, online and "注销" or "保存并登录", function()
        if online then success(app.logout()) else
            -- 登录前确保账号已落盘
            store.save_acct(a)
            success(app.login(a))
        end
    end, online and "red" or "green", 50)
    button(left, 196, 178, 158, "重新注册", function()
        store.save_acct(a); success(app.login(a))
    end, "ghost", 50)
    button(left, 22, 240, 332, "音频自检", function() M.open("diag") end, "soft", 36)
    local function info_item(y, name, value, on_edit, hint)
        local r = kit.box(left, { x = 22, y = y, w = 346, h = 60, color = C.card_soft, radius = 12,
            on_click = on_edit and function()
                edit(hint or name, value, function(text)
                    a = store.get_acct(); local next_value
                    if name == "server" then next_value = text
                    elseif name == "user" then next_value = text
                    elseif name == "port" then next_value = math.floor(tonumber(text) or 0)
                    else next_value = text end
                    a[name] = next_value
                    store.save_acct(a)
                    M.toast("已保存，下次登录生效")
                end, { max_len = name == "password" and 64 or 128, password = name == "password",
                    hint = on_edit })
            end or nil })
        label(r, 12, 6, 200, hint or name, 15, C.text3)
        label(r, 12, 30, 250, kit.ellipsis(tostring(value), 20), 18)
        if on_edit then label(r, 310, 20, 26, "编辑", 14, C.brand) end
    end
    info_item(284, "server", a.server, "服务器支持域名或 IP；注册地址 server:port", "服务器")
    info_item(352, "port", a.port, "端口为空时默认 5060", "端口")
    info_item(420, "user", a.user, "一般填写 SIP 账号", "用户名")

    local right = kit.card(host, { x = 410, y = 54, w = PW - 410, h = PH - 54, scroll = true })
    label(right, 22, 20, 300, "安全与网络", 21)
    local sec = kit.box(right, { x = 22, y = 58, w = PW - 454, h = 60, color = C.card_soft, radius = 12,
        on_click = function()
            edit("密码", a.password, function(text)
                a = store.get_acct(); a.password = text; store.save_acct(a)
                M.toast("密码已保存")
            end, { max_len = 64, password = true, hint = "密码仅保存在本机，默认 123456" })
        end })
    label(sec, 12, 6, 200, "密码", 15, C.text3)
    label(sec, 12, 30, 250, "已设置，点击修改", 18)
    label(sec, (PW - 454) - 36, 20, 26, "编辑", 14, C.brand)

    local transport = { udp = "UDP", tcp = "TCP", tls = "TLS" }
    local tr = kit.box(right, { x = 22, y = 126, w = PW - 454, h = 60, color = C.card_soft, radius = 12,
        on_click = function()
            edit("传输协议：udp / tcp", a.transport, function(text)
                local t = trim(text):lower()
                if t ~= "udp" and t ~= "tcp" then M.toast("仅支持 udp 或 tcp", true); return false end
                a = store.get_acct(); a.transport = t; store.save_acct(a)
                M.toast("传输协议已保存")
            end, { max_len = 8, hint = "演示账号通常使用 UDP，端口 8910" })
        end })
    label(tr, 12, 6, 200, "传输协议", 15, C.text3)
    label(tr, 12, 30, 250, transport[a.transport] or a.transport, 18)
    label(tr, (PW - 454) - 36, 20, 26, "编辑", 14, C.brand)

    label(right, 22, 210, 300, "音量 " .. tostring(store.get_vol()), 21)
    local vol = store.get_vol()
    button(right, 22, 246, 70, "-", function() change_volume(math.max(0, store.get_vol() - 5)) end, "soft", 44)
    local bar = kit.box(right, { x = 104, y = 256, w = PW - 580, h = 24, color = C.card_soft, radius = 12 })
    kit.box(bar, { x = 0, y = 0, w = math.floor((PW - 580) * store.get_vol() / 100), h = 24, color = C.brand, radius = 12 })
    button(right, PW - 466, 246, 70, "+", function() change_volume(math.min(100, store.get_vol() + 5)) end, "soft", 44)

    label(right, 22, 318, 300, "本地信息", 21)
    label(right, 22, 352, PW - 454,
        "本地只保留最近5条通话记录和5条聊天消息。\n完整通话历史由服务端提供，联网后在「通话记录」页查询。",17,C.text2,92)
    button(right, 22, 456, 150, "清空通话记录", function()
        confirm("清空全部通话记录？", function() return success(store.clear_calls()) end)
    end, "plain", 46)
    button(right, 182, 456, 150, "清空消息", function()
        confirm("清空全部聊天消息？", function() return success(store.clear_messages()) end)
    end, "plain", 46)
    button(right, 22, 516, 150, "恢复默认账号", function()
        confirm("用设备默认 SIP 账号覆盖当前配置？", function() return success(store.reset_acct()) end)
    end, "soft", 46)
    button(right, 182, 516, 150, "清空联系人", function()
        confirm("删除手动联系人？默认联系人仍保留。", function() return success(store.clear_contacts()) end)
    end, "red", 46)
end

-- 音频自检为可选入口，数据检测与人工听音确认分开。
local function diag_text(d)
    d = d or diag.status()
    local hardware = audio.diagnostics and audio.diagnostics() or {}
    local prefix = _G.is_pc and "PC 界面预览：没有 Air1103，无法进行硬件音频验收\n" or ""
    if hardware.fault or hardware.error then prefix = prefix .. "音频提示：" .. tostring(hardware.fault or hardware.error) .. "\n" end
    return prefix .. (d.busy and "正在检测：" or "当前状态：") .. tostring(d.stage or "等待音频初始化") ..
        "\n" .. tostring(d.detail or "") .. (d.error and ("\n错误：" .. tostring(d.error)) or "") ..
        "\nMIC 帧数 " .. tostring(d.frames or 0) .. "   帧率 " .. tostring(d.fps or 0) .. "/s   PCM " .. tostring(d.mic_rate or "待检测") ..
        "\n峰值 " .. tostring(d.peak or 0) .. "   串口接收 " .. tostring(d.rx_bytes or 0) .. " 字节" ..
        "\n测试音：" .. (d.tone_complete and "完成" or "未完成") .. "   录音回放：" .. (d.record_complete and "完成" or "未完成") ..
        "\n数据链路：" .. (d.data_ready and "正常" or "待验证") .. "   声音：" .. (d.confirmed and "已人工确认" or "待人工听音确认")
end

page_diag = function()
    --[[这一页分五拍建，每拍之间让出一帧

    实测整页一次同步过程 386ms（日志 boot body），是触摸帧环（16 帧）预算的两倍多：
    这段时间里 lv_timer_handler 不跑，读不到触摸，帧环一溢出就走
    lv_indev_reset + lv_indev_wait_release 把整段按压丢掉。
    拆成五拍后每拍只建一小组控件，并各自打出耗时 —— 下一次日志能直接指认
    是哪一拍、哪一个控件在吃时间（现在只知道慢在 render 里，不知道慢在谁身上）。

    live() 是 stale 检查：任何一拍开跑前先确认这棵控件树还是当前那次 render 的。
    期间若又触发了一次整页重建，render_seq 已经变了，旧拍直接作废，
    不会在新建的树上补控件。]]
    local seq = render_seq
    local function live()
        return seq == render_seq and started and not closing and host ~= nil
    end
    local d = diag.status()
    local t = ms_now()
    label(host, 0, 0, PW, "音频自检", 28)
    log.info("sip_ui", "diag p1", math.floor(ms_now() - t), "ms")
    window_timer(function()
        if not live() then return end
        local t2 = ms_now()
        label(host, 0, 40, PW, "完整自检先恢复音频链路，再播放测试音并录音回放；也可跳过。", 18, C.text2)
        local box = kit.card(host, { x=0, y=78, w=PW, h=235 })
        log.info("sip_ui", "diag p2", math.floor(ms_now() - t2), "ms")
        window_timer(function()
            if not live() then return end
            local t3 = ms_now()
            diag_label = label(box, 20, 12, PW-40, diag_text(d), 18, C.text, 214)
            log.info("sip_ui", "diag p3", math.floor(ms_now() - t3), "ms")
        end, 1)
    end, 1)
    local function diag_button(...)
        local obj = button(...)
        obj:set_disabled(d.busy == true)
        return obj
    end
    local function idle_action(fn)
        return function()
            if diag.status().busy then return end
            fn()
        end
    end
    window_timer(function()
        if not live() then return end
        local t4 = ms_now()
        diag_button(host, 0, 326, 230, d.busy and "自检进行中…" or "完整自检", idle_action(function()
            local ok, err = diag.start("all"); success(ok, err)
        end), d.busy and "plain" or "primary", 46)
        diag_button(host, 246, 326, 230, "我已听到清晰声音", idle_action(function()
            local ok, err = diag.confirm(true)
            if success(ok, err) then M.open("contacts") end
        end), d.busy and "plain" or "green", 46)
        diag_button(host, 492, 326, 230, "声音异常 / 未通过", idle_action(function()
            local ok, err = diag.confirm(false)
            if success(ok, err) then M.toast("请检查麦克风、喇叭及音频接线", true); request_render() end
        end), "plain", 46)
        diag_button(host, 738, 326, PW-738, "跳过", idle_action(function() M.open("contacts") end), d.busy and "plain" or "ghost", 46)
        log.info("sip_ui", "diag p4", math.floor(ms_now() - t4), "ms")
    end, 1)
    window_timer(function()
        if not live() then return end
        local t5 = ms_now()
        label(host, 0, 386, PW, "跳过不会记录自检通过；通话仍需音频硬件就绪。", 17, C.text2)
        log.info("sip_ui", "diag p5", math.floor(ms_now() - t5), "ms")
    end, 1)
end

-- 顶栏、内容区、底栏相互独立，重建时先释放旧壳层。
local nav_items = {
    { id="contacts", name="联系人" }, { id="records", name="通话记录" },
    { id="chats", name="聊天" }, { id="profile", name="我的" },
}
build_shell = function()
    PH = RH - TOP - (page == "diag" and 0 or NAV_H) - 16
    kit.destroy(shell)
    shell = kit.box(root, { x=0, y=0, w=RW, h=RH })
    kit.card(shell, { x=12, y=4, w=RW-24, h=70 })
    status_dot = nil; status_color = nil
    button(shell, 20, 18, 76, "返回", function()
        if diag.status().busy then M.toast("请等待音频自检结束后返回"); return end
        if return_timer then return end
        local id = window_id
        return_timer = window_timer(function()
            return_timer = nil
            if id and id == window_id then exwin.close(id) end
        end, 1)
    end, "plain", 42)
    top_status = kit.label(shell, { x=124, y=14, w=208, h=56, text="", size=17, color=C.text2,
        on_click=function()
            local d=audio.diagnostics()
            if not d.ready or d.error or d.fault then M.open("diag"); return end
            local s=app.status()
            if s.registration_state == "failed" then
                airui.msgbox({ title="注册失败", text=s.registration_error or "未知原因", buttons={"确定"},
                    on_action=function(self) self:hide() end })
            end
        end })
    page_title = kit.label(shell, { x=338, y=24, w=348, h=34, text="", size=22, align=airui.TEXT_ALIGN_CENTER })
    clock_label = kit.label(shell, { x=RW-124, y=24, w=100, h=34, text="", size=20, align=airui.TEXT_ALIGN_RIGHT })
    if page == "diag" then return end
    kit.card(shell, { x=12, y=RH-NAV_H, w=RW-24, h=NAV_H-4 })
    local iw = (RW-48)/4
    for i, it in ipairs(nav_items) do
        button(shell, 24+(i-1)*iw, RH-NAV_H+8, iw-8, it.name,
            function() M.open(it.id) end, page==it.id and "primary" or "plain", NAV_H-20)
    end
end
local function rebuild_all()
    if not started then return end
    build_shell()
    render()
end

-- ==================== 渲染 ====================
render = function(id)
    if not started or call_layer or (busy() and id ~= nil) then return end
    if id and id ~= page then return end
    -- profile_status / diag_label / page_scroll 都挂在 host 内，
    -- 销毁 host 前必须清引用，否则状态事件再对其 set_text 会报
    -- "access destroyed airui.label"。
    profile_status, diag_label, page_scroll = nil, nil, nil
    render_seq = render_seq + 1
    local t_host = ms_now()
    memdiag.mark("ui.host","DESTROY_BEGIN",page)
    kit.destroy(host)
    memdiag.mark("ui.host","DESTROY_END",page)
    -- page 容器不滚动：airui 的 container 不裁剪越界子控件，一旦被滚动，
    -- 列表行会翻出容器盖到顶部状态栏上（截图里第一行压住「返回」就是这么来的）。
    host = kit.box(root, { x = LEFT, y = TOP, w = PW, h = PH })
    log.info("sip_ui", "render host", math.floor(ms_now() - t_host), "ms")
    if not host then return end
    if page == "contacts" then page_contacts()
    elseif page == "records" then page_records()
    elseif page == "chats" then page_chats()
    elseif page == "profile" then page_profile()
    elseif page == "diag" then page_diag()
    end
end

render = memdiag.wrap("ui.render", render)

--[[整页重建统一走这里，不在回调里直接 render()

render() 会 kit.destroy(host) 再整棵重建。下面三类触发点都可能落在同一个调用栈里：
状态回包、自检阶段变化、按钮点击分页。逐次销毁重建有两个后果：
  · LVGL 的控件删除与重画追不上，屏幕上叠出上一帧（玻璃卡片半透明，残影直接透出来）
  · 点击回调正在执行时把它所属的按钮销毁，airui 的事件派发就断在半路，表现为"点不动"
所以合并到下一拍只做一次，并且弹窗/通话层/自检进行中一律不重建。
force 只给自检状态翻转用：按钮的禁用态和"自检进行中…"文案都在控件树里，
busy 变化那一拍必须重建，否则界面停在旧状态。]]
local render_pending = false
request_render = function(force)
    if render_pending or not started or closing then return end
    render_pending = true
    window_timer(function()
        render_pending = false
        if not started or closing then return end
        if panel or call_layer then return end
        if not force and diag.status().busy then return end
        render()
    end, 1)
end

--[[切页同样不在点击回调里同步重建

M.open 是被导航键、自检按钮的 on_click 直接调的，而 rebuild_all() 会 kit.destroy(shell)
—— shell 里就是刚被点的那颗按钮。airui 的事件派发正走到这颗按钮的回调中段，它所属的
控件树被删掉，派发链就断在半路：这一次点击之后按钮看起来"点不动"，要再点一次才恢复。
所以切页也合并到下一拍，并且重建后补一次 refresh_status（新 label 是空的）。]]
local rebuild_pending = false
local function request_rebuild()
    if rebuild_pending or not started or closing then return end
    rebuild_pending = true
    window_timer(function()
        rebuild_pending = false
        if not started or closing then return end
        if panel or call_layer then return end
        rebuild_all()
        refresh_status()
    end, 1)
end

function M.open(id, peer)
    if not started or closing then return end
    if busy() or diag.status().busy then return end
    local changed = not (page == id and selected_peer == peer)
    memdiag.mark("ui.open","TARGET",id)
    close_panel(); page = id; selected_peer = peer
    if changed then
        record_page=1;records_data=nil;record_state=nil;presence_state=nil
        request_rebuild()
    else
        refresh_status()
    end
end
M.open = memdiag.wrap("ui.open", M.open)
M.replace = M.open

-- ==================== 状态文字 ====================
local call_state_text = {
    idle = "空闲", connecting = "注册中", netwait = "等待网络", registered = "已注册",
    incoming = "来电中", answering = "接听中", talking = "通话中", dialing = "拨号中",
    ending = "挂断中", stopped = "未登录", error = "异常",
}

local registration_names = {registered="注册成功", registering="注册中", failed="注册失败", idle="未注册"}
refresh_status = function(snapshot)
    if not started or call_layer then return end
    -- 首屏建树已推迟一拍（见 on_create）；shell 没建出来前 top_status 还是 nil，
    -- 下面 set_pos/set_text 都会打在空引用上，先跳过这一拍。
    if not shell then return end
    local measured = perf.begin("ui")
    local s = snapshot or app.status()
    local rs = s.registration_state or "idle"
    local detail = rs == "failed" and (s.registration_error or "未知原因") or ""
    local full = (registration_names[rs] or "未注册") .. (detail ~= "" and ("：" .. detail) or "")
    local color = rs == "registered" and C.green or rs == "registering" and 0xF59E0B or rs == "failed" and C.red or C.text3
    local d = audio.diagnostics()
    if d.initializing then full="音频初始化中";color=0xF59E0B
    elseif diag.status().busy then full="音频自检中";color=0xF59E0B
    elseif not d.ready or d.error or d.fault then
        full="请重新进行音频自检";color=C.red
    end
    -- 字号受主题最小值约束，用真实像素计算文本块与圆灯的共同中心。
    local fs = math.max(theme.FONT_MIN, SF(17))
    local width = SX(208)
    local center_y = SY(38)
    if status_cache.obj ~= top_status or status_cache.text ~= full or
        status_cache.font ~= fs or status_cache.width ~= width or status_cache.center ~= center_y then
        local lines = theme.text_width(full, fs) > width and 2 or 1
        local line_h = fs + 3
        top_status:set_pos(SX(124), math.floor(center_y - lines * line_h / 2))
        set_text(top_status, theme.fit_text(full, width, fs, 2))
        status_cache.obj, status_cache.text = top_status, full
        status_cache.font, status_cache.width, status_cache.center = fs, width, center_y
    end
    if status_color ~= color then
        kit.destroy(status_dot)
        local diameter = math.max(8, math.floor(math.min(SX(12), SY(12))))
        status_dot = airui.container({parent=shell, x=SX(104), y=math.floor(center_y-diameter/2), w=diameter, h=diameter,
            radius=diameter, color=color, scrollable=false})
        status_color = color
    end
    set_text(page_title, store.get_acct().user or "未配置账号")
    local t = os.date("*t")
    set_text(clock_label, string.format("%02d:%02d", t.hour, t.min))
    if profile_status then set_text(profile_status, s.user_text or s.text or "") end
    perf.finish("ui", measured)
end

-- ==================== 全屏通话层 ====================
local function hhmmss(t)
    t = math.max(0, math.floor(t or 0))
    return string.format("%02d:%02d:%02d", math.floor(t / 3600), math.floor(t % 3600 / 60), t % 60)
end

show_call_layer = function(snapshot)
    if not started then return end
    local measured = perf.begin("ui")
    local s = snapshot or app.status()
    -- 一次通话只创建一棵轻量控件树；振铃/接通/静音仅更新文字。
    -- 避免在回铃音启动和 airlink RPC 处理时分配渐变条带并反复重建全屏。
    if not call_layer then
        log.info("sip_ui", "open call screen", s.state)
        close_panel()
        call_left_disabled, call_right_disabled = nil, nil
        call_layer = kit.box(root, { x=0, y=0, w=RW, h=RH, color=C.bg })
        call_name = kit.label(call_layer, { x=40, y=150, w=RW-80, h=52, text="", size=34, align=airui.TEXT_ALIGN_CENTER })
        call_sub = kit.label(call_layer, { x=40, y=230, w=RW-80, h=60, text="", size=22, color=C.text2, align=airui.TEXT_ALIGN_CENTER })
        call_clock = kit.label(call_layer, { x=40, y=310, w=RW-80, h=42, text="00:00:00", size=28, color=C.brand, align=airui.TEXT_ALIGN_CENTER })
        call_left = button(call_layer, 308, 430, 190, "", function()
            if call_layer_state == "incoming" then success(app.hangup())
            elseif call_layer_state == "talking" then success(app.toggle_mute()); render_call() end
        end, "plain", 64)
        call_right = button(call_layer, 526, 430, 190, "", function()
            if call_layer_state == "incoming" then success(app.accept()) else success(app.hangup()) end
        end, "primary", 64)
        if call_timer then stop_window_timer(call_timer) end
        call_timer = window_timer(function()
            if not started or not call_layer or call_layer_state ~= "talking" then return end
            local measured = perf.begin("ui")
            local duration = raw_app.call_duration() or 0
            set_text(call_clock, hhmmss(duration))
            perf.finish("ui", measured)
        end, 1000, true)
    end
    local peer = s.peer or s.number or ""
    if call_peer ~= peer then
        call_peer = peer
        set_text(call_name, store.display(peer))
    end
    if call_layer_state ~= s.state then log.info("sip_ui", "call state", s.state) end
    call_layer_state = s.state
    set_text(call_sub, (s.text ~= "" and s.text) or call_state_text[s.state] or "")
    set_text(call_clock, hhmmss(s.duration or 0))
    set_text(call_left, s.state == "incoming" and "拒接" or (s.muted and "取消静音" or "静音"))
    local left_disabled = s.state ~= "incoming" and s.state ~= "talking"
    if call_left_disabled ~= left_disabled then
        call_left:set_disabled(left_disabled); call_left_disabled = left_disabled
    end
    set_text(call_right, s.state == "incoming" and "接听" or "挂断")
    local right_disabled = s.state == "ending"
    if call_right_disabled ~= right_disabled then
        call_right:set_disabled(right_disabled); call_right_disabled = right_disabled
    end
    perf.finish("ui", measured)
end
render_call = show_call_layer

function M.suspend_keyboard_if_active()
    if keyboard and not suspended then
        keyboard:hide(); suspended = true
        local target = keyboard
        window_timer(function()
            if suspended and keyboard == target then target:show(); suspended = false end
        end, 200)
    end
end

-- ==================== 时钟 ====================
local function tick_clock()
    if not started or call_layer then return end
    if started then
        local d=audio.diagnostics()
        log.info("sip_health", "rx-drain-v2", "lua_kb", math.floor(collectgarbage("count")),
            "owner", d.owner or "idle", "rx_read", d.rx_read_bytes or 0,
            "rx_discard", d.rx_discard_bytes or 0, "mic_frames", d.frames or 0)
    end
    local t = os.localtime and os.localtime(os.time()) or os.date("*t")
    set_text(clock_label, string.format("%02d:%02d", t.hour or 0, t.min or 0))
end
-- ==================== 窗口生命周期 ====================
local on_state
local function on_audio_state() refresh_status() end
local function on_audio_error(reason)
    if call_layer then
        M.toast("音频故障：" .. tostring(reason or "请重新进行音频自检"), true)
    else refresh_status() end
end
local function on_create()
    lifecycle = lifecycle + 1
    local session = lifecycle
    -- 取工厂内容区实际画布尺寸；所有页面坐标仍以参考 1024x600 书写，
    -- 由 SX/SY 统一缩放到实际 W/H，因此 LEFT/TOP/PW/PH 保持参考值不变。
    local cw, ch = screen_w or RW, screen_h or RH
    local theme = require "ui_theme"
    cw, ch = theme.content_fit(cw, ch)
    W, H = cw, ch
    sxk = W / RW; syk = H / RH
    LEFT, TOP = 20, 84
    PW, PH = RW - 40, RH - TOP - NAV_H - 16

    root = theme.page_bg(airui.screen, W, H)
    page = "diag"
    started = true
    --[[首屏建树分三拍，每拍之间让出一帧

    build_shell + render 是六十来个 airui 控件的一次不让出同步过程。它压在「SIP 通话」
    那一格点击回调的调用栈里（handoff 队列首任务、store/网络初始化之前），LVGL 的触摸派发
    一路被按住：触摸帧环只有 16 帧，读取方一被按住就溢出，溢出会走
    lv_indev_reset + lv_indev_wait_release 把整段按压丢掉，
    表现就是"点了 SIP 通话界面还在刷、但摸不动"。
    原来只往后挪一拍不够：1ms 定时器与 lv_timer_handler 之间没有让出保证，
    六十个控件仍是一口气建完。这里拆成 壳层 / 内容 / 状态 三拍。]]
    local boot_t0 = ms_now()
    local boot_stage = 0
    local function boot_tick()
        boot_stage = boot_stage + 1
        if not started or closing or not root then return end
        if boot_stage == 1 then
            local t = ms_now()
            build_shell()
            log.info("sip_ui", "boot shell", math.floor(ms_now() - t), "ms")
        elseif boot_stage == 2 then
            local t = ms_now()
            render()
            log.info("sip_ui", "boot body", math.floor(ms_now() - t), "ms")
        else
            refresh_status()
            tick_clock()
            clock_timer = window_timer(tick_clock, 1000 * 10, true)
            log.info("sip_ui", "boot ready", math.floor(ms_now() - boot_t0), "ms")
            return
        end
        window_timer(boot_tick, 1)
    end
    window_timer(boot_tick, 1)
    -- 自检页实时刷新帧数/帧率/峰值（照抄参考工程 1s 刷新节奏）
    -- 但【录音/回放进行中一律不刷】：这段文本近 300 字，set_text 会让 LVGL 重排并整块
    -- 重绘一次；而 Air1103 的下行是 Lua 10ms 一拍喂 UART，芯片内部 DAC 缓冲只有约 60ms，
    -- 一次几十毫秒的整块重绘就足够把它掏空 —— 表现就是"回放卡"。录音期间同样会丢 MIC 帧。
    -- 自检过程中的阶段变化仍由 AUDIO_DIAG 事件驱动刷新，信息不会缺。
    diag_timer = window_timer(function()
        if call_layer then return end
        if started then refresh_status() end
        if not (started and page == "diag" and diag_label) then return end
        local d = diag.status()
        if d.busy then return end
        set_text(diag_label, diag_text(d))
    end, 1000, true)

    -- 订阅 app 状态：非通话变化刷新导航/状态；进入通话拉起全屏层
    on_state = function(snapshot)
        if not started then return end
        local s = app.status(snapshot)
        if call_states[s.state] then
            show_call_layer(s)
        else
            if call_layer then
                if call_timer then stop_window_timer(call_timer); call_timer = nil end
                kit.destroy(call_layer); call_layer = nil
                call_layer_state, call_sub, call_peer = nil, nil, nil
                call_name, call_clock, call_left, call_right = nil, nil, nil, nil
                call_left_disabled, call_right_disabled = nil, nil
                -- 通话只遮挡底页：挂断保留联系人输入、聊天位置和自检控件，
                -- 仅通话记录需要重建以显示刚结束的通话。
                if page == "records" and not panel then request_render() end

            end
            refresh_status(s)
        end
    end
    -- 同事内核发布 SIP_STATE / SIP_ERROR（不是工厂旧的 SIP_TEST_*）
    on_state = memdiag.wrap("ui.SIP_STATE",on_state)
    subscribe("SIP_STATE", on_state)
    subscribe("SIP_STORE_CHANGED",function(key)
        if not started or closing or panel or call_layer or diag.status().busy then return end
        -- 服务端记录/在线状态都要重新取，否则新写入的通话和联系人查不到
        if key=="calls" then records_data=nil;record_state=nil end
        if key=="contacts" or key=="default_contact" then presence_cache={};presence_state=nil end
        if (key=="calls" and page=="records") or
           ((key=="contacts" or key=="default_contact") and (page=="contacts" or page=="records")) then request_render() end
    end)
    subscribe("SIP_ERROR", function(t) M.toast(t, true); refresh_status() end)
    subscribe("AUDIO_ERROR", on_audio_error)
    subscribe("AUDIO_READY", on_audio_state)
    subscribe("SIP_MSG", function() if started then refresh_status() end end)
    -- 音频自检进度（sph_audio_diag 发布 AUDIO_DIAG），刷新自检页状态文本
    local last_diag_busy = false
    subscribe("AUDIO_DIAG", function()
        if call_layer then return end
        refresh_status()
        if not started or page ~= "diag" then return end
        local d = diag.status()
        if last_diag_busy ~= d.busy then
            last_diag_busy = d.busy; request_render(true)
        elseif diag_label then set_text(diag_label, diag_text(d)) end
    end)

    -- 先确保存储 + 网络检测就绪（工厂 net_manager 已组网，这里只读状态）；
    -- 再 init 同事内核：内部 recover_messages，并按 auto_register 自动注册。
    -- 每步之间必须让出 CPU：4G 走 airlink(UART3) 桥接，mobile.*/socket.* 是同步 RPC，
    -- 在等响应期间如果 Lua 主任务被 store/audio 初始化按住几百毫秒，
    -- 内核会直接报 "airlink.rpc rpc yield timeout" 甚至总线错误死机。
    handoff.enqueue(function()
        -- 进来先让一拍：上面 build_shell/render 是一次不让出的同步过程，
        -- 若此刻有 airlink RPC 在等响应，立刻再压 store/audio 初始化就会把它拖超时。
        sys.wait(100)
        if session ~= lifecycle then return end
        pcall(store.init)
        sys.wait(50)
        if session ~= lifecycle then return end
        pcall(net.init)
        sys.wait(50)
        -- 必须先初始化 Air1103/UART6：audio.init 内部会把 exaudio.sip_voip_start/stop
        -- 挂到通话桥 M.start/M.stop_bridge；否则通话建立时音频桥不存在。
        if session ~= lifecycle then return end
        local ok, ready, err = pcall(audio.init)
        if not ok or not ready then
            error("SIP 音频初始化失败: " .. tostring(ok and err or ready))
        end
        sys.wait(50)
        if session ~= lifecycle then return end
        pcall(raw_app.init)
        if not alive(session) then return end
        refresh_status()
        if not panel then request_render() end
    end)
end

local function on_destroy()
    if closing or (not root and not window_id) then return end
    -- Invalidate callbacks before cancelling diagnostics or publishing SIP changes.
    closing = true
    lifecycle = lifecycle + 1
    started = false
    window_id = nil
    local old_root, old_keyboard, old_panel = root, keyboard, panel
    root, keyboard, panel = nil, nil, nil
    local old_subscriptions, old_timers = subscriptions, timers
    subscriptions, timers = {}, {}
    for event, callback in pairs(old_subscriptions) do
        cleanup("unsubscribe " .. event, sys.unsubscribe, event, callback)
    end
    for id in pairs(old_timers) do cleanup("timer", sys.timerStop, id) end
    cleanup("cancel diagnostic", diag.cancel)
    -- Each operation is independent: a broken keyboard must not strand the page.
    if old_keyboard then cleanup("keyboard", kit.destroy, old_keyboard) end
    if old_panel then cleanup("panel", kit.destroy, old_panel) end
    if old_root then
        if not cleanup("root", function() old_root:destroy() end) then
            cleanup("hide failed root", function() old_root:hide() end)
        end
    end
    host, shell, clock_label, page_title = nil, nil, nil, nil
    page_scroll, diag_label, profile_status, top_status = nil, nil, nil, nil
    status_dot, status_color, toast_box = nil, nil, nil
    call_layer, call_layer_state, call_sub, call_peer = nil, nil, nil, nil
    call_name, call_clock, call_left, call_right = nil, nil, nil, nil
    call_timer, clock_timer, diag_timer, toast_timer, return_timer = nil, nil, nil, nil, nil
    suspended, on_state = false, nil
    status_cache = {}
    call_left_disabled, call_right_disabled = nil, nil
    text_cache = setmetatable({}, { __mode = "k" })
    -- UI removal is synchronous; network/audio shutdown may yield in its own task.
    handoff.enqueue(function()
        cleanup("hangup", raw_app.hangup)
        cleanup("logout", raw_app.logout, true)
        handoff.leave("sip")
        closing = false
    end)
end

sys.subscribe("OPEN_SIP_TEST_WIN", function()
    -- 自检：SIP 通话只在接了 Air1103 的型号上开（Air8605M / Air8605W），门槛见 app/sip/sip_gate.lua。
    -- 桌面入口已按它藏掉，这里防的是别处误发 OPEN_SIP_TEST_WIN 把没有语音通路的板子拉起来。
    local gate = require "sip_gate"
    if not gate.ok() then
        log.warn("sip_test_win", "本机型未开 SIP 通话，忽略开窗", gate.reason())
        return
    end
    handoff.enqueue(function()
    if window_id or closing then return end
    -- 先让一拍：sys.taskInit 会立刻把新协程跑到第一个 yield，而这一格任务在让出之前
    -- 全是同步的（页面清理、sip.logout、other_func_app.stop_all），
    -- 点击回调还没返回就被按住十几秒 —— 就是"点了 SIP 通话先卡住"。
    -- 让出一拍先放行触摸派发，再做收尾。
    sys.wait(50)
    if window_id or closing then return end
    -- keep_audio：本页下一步就是 audio.init 重建同一条 Air1103 通路，
    -- 这里不拆音频，省掉一次完整的 exaudio.setup（重开 UART6 + 重配 audio_v2）
    local t_prepare = ms_now()
    handoff.prepare("sip", { keep_audio = true })
    log.info("sip_ui", "handoff.prepare", math.floor(ms_now() - t_prepare), "ms")
    sys.wait(50)
    if window_id or closing then return end
    local t_open = ms_now()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = memdiag.wrap("ui.destroy",on_destroy),
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
    log.info("sip_ui", "exwin.open", math.floor(ms_now() - t_open), "ms")
    -- 通话历史压缩是文件 I/O，挪到开窗之后：挡在 exwin.open 前面只会让窗口晚出来，
    -- 而且压缩失败不该把窗口一起吞掉。
    local compacted, why = store.compact_history()
    if not compacted then log.warn("sip_test_win", "compact_history failed", tostring(why)) end
    end)
end)

return M
