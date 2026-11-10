--[[
@module  sip_test_win
@summary 功能测试-SIP通话 窗口：完全移植自 SIP_APP 的 1024x600 侧栏话机界面
@version 3.0
@date    2026.11.04
@description
五个页面：联系人 / 通话记录 / 聊天 / 我的 / 音频自检；通话时全屏通话覆盖层。
布局、文案、交互与参考工程 ui/app_main.lua 一致；通过等比缩放层适配工厂窗口尺寸。
]]

local exwin = require "exwin"
local base_kit = require "ui_kit"
-- 通话/账号/消息内核整套使用同事原版 SIP_APP（sip_phone/*），UI 仍走本文件缩放层
local raw_app = require "sph_sip_app"
local net = require "sph_net_app"
local store = require "sph_store"
local audio = require "sph_audio_app"
local diag = require "sph_audio_diag"

-- ==================== app 适配层：同事 SIP_APP -> 参考话机 UI 语义 ====================
-- 同事内核状态: idle/connecting/ready/dialing/incoming/answering/talking/ending
-- 参考 UI 状态: idle/connecting/registered/dialing/incoming/talking/ending
local app = {}
local function norm_state(raw)
    if raw == "ready" then return "registered" end
    return raw
end
function app.status()
    local s = raw_app.status()
    local st = norm_state(s.state)
    return {
        state = st,
        registered = s.registered == true and st == "registered",
        peer = s.peer, number = s.peer,
        direction = s.direction, duration = s.duration, muted = s.muted == true,
        user = s.user, unread = store.unread_total(),
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

local kit = {}
kit.C = base_kit.C

function kit.box(parent, o)
    o = o or {}
    return base_kit.box(parent, {
        x = SX(o.x), y = SY(o.y), w = SX(o.w), h = SY(o.h),
        color = o.color, opacity = o.opacity, radius = SX(o.radius),
        border = o.border, border_color = o.border_color, border_width = o.border_width,
        on_click = o.on_click, on_long_press = o.on_long_press,
        scroll = o.scroll, clip = o.clip,
    })
end
function kit.label(parent, o)
    o = o or {}
    return base_kit.label(parent, {
        x = SX(o.x), y = SY(o.y), w = SX(o.w), h = SY(o.h),
        text = o.text, size = SF(o.size), color = o.color,
        align = o.align, on_click = o.on_click,
    })
end
function kit.card(parent, o)
    o = o or {}
    o.color = o.color or base_kit.C.card
    o.radius = o.radius or 18
    if o.border == nil then o.border = true end
    o.border_color = o.border_color or base_kit.C.line_soft
    return kit.box(parent, o)
end
function kit.btn(parent, o)
    o = o or {}
    local C = base_kit.C
    local kind = o.kind or "primary"
    local bg, fg, bcol, bw, pressed
    if kind == "primary" then bg, fg, pressed = C.brand, C.white, C.brand_deep
    elseif kind == "green" then bg, fg, pressed = C.green, C.white, C.green_deep
    elseif kind == "red" then bg, fg, pressed = C.red, C.white, C.red_deep
    elseif kind == "ghost" then bg, fg, bcol, bw, pressed = C.white, C.brand, C.brand_line, 1, C.brand_soft
    elseif kind == "soft" then bg, fg, pressed = C.brand_soft, C.brand, C.brand_line
    elseif kind == "plain" then bg, fg, pressed = C.card_soft, C.text2, C.brand_soft
    else bg, fg, pressed = C.bg_warm, C.text, C.brand_soft end
    return airui.button({
        parent = parent,
        x = SX(o.x), y = SY(o.y), w = SX(o.w), h = SY(o.h),
        text = o.text or "", font_size = SF(o.size),
        style = {
            bg_color = bg, bg_opa = 255, text_color = fg,
            border_color = bcol or bg, border_width = bw or 0,
            radius = SX(o.radius or 14), pad = o.pad or 2,
            pressed_bg_color = pressed,
            pressed_text_color = (kind == "ghost") and C.brand or fg,
        },
        on_click = o.on_click,
    })
end
function kit.avatar(parent, o)
    o = o or {}
    -- 坐标/直径均按参考基准缩放；通话层传的是实际像素（sxk=1 时一致）
    local d = SX(o.size or 56)
    local fs = SF(o.font_size or base_kit.FS.h3)
    local box = kit.box(parent, { x = o.x, y = o.y, w = d, h = d, color = o.color or base_kit.C.brand, radius = math.floor(d / 2) })
    if not box then return nil end
    kit.label(box, { x = 0, y = math.floor((d - fs) / 2) - 2, w = d, h = fs + 4,
        text = o.text, size = o.font_size or base_kit.FS.h3, color = base_kit.C.white, align = airui.TEXT_ALIGN_CENTER })
    return box
end
function kit.input(parent, o)
    o = o or {}
    local wrap = kit.box(parent, { x = o.x, y = o.y, w = o.w, h = o.h, color = base_kit.C.white, radius = o.radius or 12,
        border = true, border_color = o.border_color or base_kit.C.brand_line })
    if not wrap then return nil end
    local th = SY(o.h) or SF(46)
    local ta = airui.textarea({
        parent = wrap,
        x = SX(8), y = math.max(2, math.floor((th - SF(o.size or 18) - 8) / 2)),
        w = SX(o.w or 200) - SX(16), h = SF(o.size or 18) + 10,
        text = o.text or "", placeholder = o.placeholder or "",
        max_len = o.max_len or 64, mode = o.password and "password" or "normal",
        font_size = SF(o.size or 18), align = airui.TEXT_ALIGN_LEFT,
        on_text_change = o.on_change,
        style = { bg_color = base_kit.C.white, text_color = base_kit.C.text, radius = 0 },
    })
    return ta
end
function kit.grad(parent, x, y, w, h, c1, c2, steps)
    return base_kit.grad(parent, SX(x), SY(y), SX(w), SY(h), c1, c2, steps)
end
function kit.destroy(obj) base_kit.destroy(obj) end
function kit.ellipsis(s, n) return base_kit.ellipsis(s, n) end
function kit.first_char(s) return base_kit.first_char(s) end

local C = kit.C
local M = {}

local root, host, clock_label, page_title
local page, selected_peer, panel, keyboard, call_layer, call_timer
local call_layer_state, call_sub   -- 通话层当前状态与副标题标签，用于同状态只改文字不重建
local toast_box, toast_timer, started
local page_scroll, diag_label, profile_status, diag_timer
local dial_number = ""
local drafts = {}
local nav_page
local text_cache = setmetatable({}, { __mode = "k" })
local RECORDS_VISIBLE = 10
local W, H, LEFT, TOP = RW, RH, 176, 64
local PW, PH = W - LEFT - 24, H - TOP - 24
local render, render_call, refresh_status
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
    if not root then return end
    if toast_timer then sys.timerStop(toast_timer) end
    kit.destroy(toast_box)
    toast_box = kit.box(root, { x = 210, y = 12, w = 600, h = 42, color = is_error and C.red or C.dark1, radius = 14 })
    label(toast_box, 14, 7, 572, tostring(text), 18, C.white)
    toast_timer = sys.timerStart(function() kit.destroy(toast_box); toast_box = nil; toast_timer = nil end, 3000)
end

local function close_panel()
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
                native = assert(airui.keyboard({ parent = parent, x = SX(0), y = SY(376), w = SX(RW), h = SY(224), mode = "pinyin_26",
                    auto_hide = false, preview = false, font_size = SF(20), bg_color = C.white, on_commit = commit }), "AirUI keyboard unavailable")
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
        if on_save(s) ~= false then close_panel(); render() end
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
        if fn() ~= false then close_panel(); render() end
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
        sys.timerStart(ask_name, 10)
    end, { max_len = 64, hint = "填写 SIP 账号或分机号" })
end

local function empty(parent, text, width) label(parent, 22, 40, (width or PW) - 44, text, 22, C.text3, 70) end
local function row(parent, y, title, subtitle, w)
    local r = kit.card(parent, { x = 0, y = y, w = w, h = 88, radius = 16 })
    label(r, 16, 12, w - 36, kit.ellipsis(title, 23), 21)
    label(r, 16, 48, w - 36, kit.ellipsis(subtitle, 38), 16, C.text3)
    return r
end

page_contacts = function()
    local list_w = PW - 330
    label(host, 0, 0, list_w - 140, "联系人", 28)
    button(host, list_w - 130, 0, 120, "新增", function() contact_editor() end, "ghost", 40)
    local list = kit.box(host, { x = 0, y = 54, w = list_w, h = PH - 54, scroll = true })
    local items = store.get_contacts()
    if #items == 0 then empty(list, "还没有联系人\n右侧输入号码，或点击新增", list_w) end
    for i, c in ipairs(items) do
        row(list, (i - 1) * 142, c.name ~= "" and c.name or c.num, c.num, list_w - 12)
        button(list, 8, (i - 1) * 142 + 92, 100, "拨号", function() call(c.num) end, "green", 40)
        button(list, 118, (i - 1) * 142 + 92, 100, "编辑", function() contact_editor(c) end, "soft", 40)
        button(list, 228, (i - 1) * 142 + 92, 100, "删除", function()
            confirm("删除联系人 " .. store.display(c.num) .. "？", function() return success(store.del_contact(c.num)) end)
        end, "plain", 40)
    end
    local pad = kit.card(host, { x = list_w + 12, y = 0, w = 318, h = PH, radius = 22 })
    label(pad, 18, 16, 282, "拨号盘", 22)
    local display = label(pad, 18, 54, 282, dial_number ~= "" and dial_number or "请输入号码", 28, C.brand, 44)
    local function update() set_text(display, dial_number ~= "" and dial_number or "请输入号码") end
    local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
    for i, k in ipairs(keys) do
        button(pad, 16 + ((i - 1) % 3) * 98, 112 + math.floor((i - 1) / 3) * 62, 90, k, function()
            if #dial_number < 32 then dial_number = dial_number .. k; update() end
        end, "soft", 54)
    end
    button(pad, 16, 364, 90, "删除", function() dial_number = dial_number:sub(1, -2); update() end, "plain", 40)
    button(pad, 114, 364, 90, "清空", function() dial_number = ""; update() end, "plain", 40)
    button(pad, 212, 364, 90, "保存", function() contact_editor({ num = dial_number }) end, "ghost", 40)
    button(pad, 16, 420, 286, "拨号", function() call(dial_number) end, "green", 64)
end

page_records = function()
    label(host, 0, 0, 560, "通话记录 · 最近 10 条", 28)
    button(host, PW - 140, 0, 140, "清空记录", function()
        confirm("清空全部通话记录？", function() return success(store.clear_calls()) end)
    end, "ghost", 40)
    local list = kit.box(host, { x = 0, y = 56, w = PW, h = PH - 56, scroll = true })
    local items = store.get_calls()
    if #items == 0 then empty(list, "暂无通话记录") end
    local titles = { missed = "未接来电", answered = "已接来电", received = "已接来电", dialed = "已拨电话", rejected = "已拒接", ended = "通话结束" }
    for i = 1, math.min(#items, RECORDS_VISIBLE) do
        local c = items[i]
        local result = c.result or c.type
        row(list, (i - 1) * 100, store.display(c.num),
            (titles[result] or result) .. " · " .. store.fmt_time(c.ts) .. " · " .. store.fmt_dur(c.dur), PW - 12)
        button(list, PW - 150, (i - 1) * 100 + 22, 120, "回拨", function() call(c.num) end, "green")
    end
end

local function new_chat()
    edit("新建聊天：SIP 账号", "", function(num)
        if num == "" then M.toast("请输入对方账号", true); return false end
        selected_peer = num; page = "chats"
    end, { max_len = 64, hint = "对端和 SIP 服务器需支持 MESSAGE 文本消息" })
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
    sys.timerStart(function()
        if started and page == "chats" and page_scroll == messages then
            pcall(function() messages:scroll(0, y + 100) end)
        end
    end, 80)
end

page_profile = function()
    local a = store.get_acct()
    local s = app.status()
    label(host, 0, 0, 500, "我的", 28)
    local left = kit.card(host, { x = 0, y = 54, w = 390, h = PH - 54 })
    local online = s.state == "registered"
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
    label(left, 22, 246, 346, "账号配置", 21)
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

    local right = kit.card(host, { x = 410, y = 54, w = PW - 410, h = PH - 54 })
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
    local ccounts = store.counts()
    label(right, 22, 352, PW - 454,
        string.format("联系人 %d · 通话记录 %d 条 · 会话 %d 个\n未读消息 %d 条\n数据保存在设备 fskv 分区，恢复出厂前请先记录账号",
            ccounts.contacts, ccounts.calls, ccounts.threads, ccounts.unread), 17, C.text2, 92)
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
        confirm("删除全部联系人？", function() return success(store.clear_contacts()) end)
    end, "red", 46)
end

-- 音频自检：完全照抄参考工程 ui/app_main.lua 的 diag_text + diagnostic。
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
    label(host, 0, 0, 760, "音频自检 · 先确认声音，再验证 SIP", 28)
    label(host, 0, 45, 776, "UART6 / Air1103 → C237 → HT6873；R253 由 MUTE 控制功放", 17, C.text3)
    local box = kit.card(host, { x = 0, y = 85, w = PW, h = 245 })
    diag_label = label(box, 20, 15, PW - 40, diag_text(), 19, C.text, 220)
    button(host, 0, 350, 236, "1. 播放测试音", function() local ok, err = diag.start("tone"); success(ok, err) end, "soft", 56)
    button(host, 250, 350, 250, "2. 录音 3 秒并回放", function() local ok, err = diag.start("record"); success(ok, err) end, "soft", 56)
    button(host, 514, 350, 282, "完整自检", function() local ok, err = diag.start("all"); success(ok, err) end, "primary", 56)
    label(host, 0, 421, 796, "请确认：测试音清晰、录音回放能听清自己，测试期间触摸仍正常。", 18, C.text2)
    button(host, 0, 460, 340, "我已听到两项清晰声音", function()
        local ok, err = diag.confirm(true)
        if success(ok, err) then M.toast("音频已人工确认"); M.open(store.has_acct() and "contacts" or "profile") end
    end, "green", 48)
    button(host, 356, 460, 196, "声音异常 / 未通过", function()
        local ok, err = diag.confirm(false)
        if success(ok, err) then M.toast("请检查 SPK、C237、功放 SD 和喇叭输出", true); render() end
    end, "plain", 48)
    button(host, 568, 460, 228, "账号设置 / 聊天", function() M.open(store.has_acct() and "chats" or "profile") end, "ghost", 48)
end

-- ==================== 侧栏壳层 ====================
local nav_items = {
    { id = "contacts", name = "联系人" },
    { id = "records", name = "通话记录" },
    { id = "chats", name = "聊天" },
    { id = "profile", name = "我的" },
    { id = "diag", name = "音频自检" },
}
local nav_labels = {}

build_shell = function()
    -- 背景（坐标全部为参考 1024x600，经缩放层映射）
    kit.box(root, { x = 0, y = 0, w = RW, h = RH, color = C.bg_warm })
    -- 顶部导航条
    kit.box(root, { x = 0, y = 0, w = RW, h = 56, color = C.dark1 })
    page_title = label(root, LEFT + 12, 16, 300, "SIP 网络电话", 20, C.white, 30)
    clock_label = label(root, RW - 190, 16, 178, "", 17, C.white, 28)

    -- 侧栏
    kit.box(root, { x = 0, y = 0, w = LEFT, h = RH, color = C.white })
    label(root, 18, 20, LEFT - 30, "SIP 话机", 24, C.brand, 34)
    nav_labels = {}
    for i, it in ipairs(nav_items) do
        local y = 78 + (i - 1) * 64
        local active = it.id == page
        local holder = kit.box(root, { x = 12, y = y, w = LEFT - 24, h = 52, radius = 12,
            color = active and C.brand_soft or C.white,
            on_click = function() M.open(it.id) end })
        label(holder, 18, 13, LEFT - 60, it.name, 20, active and C.brand or C.text2, 28)
    end
    top_status = label(root, 18, RH - 60, LEFT - 32, "", 15, C.text3, 46)
end

-- 重建壳层（导航高亮随当前页变化）并重建内容
local function rebuild_all()
    if not started then return end
    profile_status, diag_label, page_scroll = nil, nil, nil
    kit.destroy(host)
    build_shell()
    host = kit.box(root, { x = LEFT, y = TOP, w = PW, h = PH })
    if host and page == "contacts" then page_contacts()
    elseif host and page == "records" then page_records()
    elseif host and page == "chats" then page_chats()
    elseif host and page == "profile" then page_profile()
    elseif host and page == "diag" then page_diag()
    end
end

-- ==================== 渲染 ====================
render = function(id)
    if not started or (busy() and id ~= nil) then return end
    if id and id ~= page then return end
    -- profile_status / diag_label / page_scroll 都挂在 host 内，
    -- 销毁 host 前必须清引用，否则状态事件再对其 set_text 会报
    -- "access destroyed airui.label"。
    profile_status, diag_label, page_scroll = nil, nil, nil
    kit.destroy(host)
    host = kit.box(root, { x = LEFT, y = TOP, w = PW, h = PH })
    if not host then return end
    if page == "contacts" then page_contacts()
    elseif page == "records" then page_records()
    elseif page == "chats" then page_chats()
    elseif page == "profile" then page_profile()
    elseif page == "diag" then page_diag()
    end
end

function M.open(id, peer)
    if busy() then return end
    local changed = not (page == id and selected_peer == peer)
    close_panel(); page = id; selected_peer = peer
    if changed then rebuild_all() else render() end
    refresh_status()
end
M.replace = M.open

-- ==================== 状态文字 ====================
local call_state_text = {
    idle = "空闲", connecting = "注册中", netwait = "等待网络", registered = "已注册",
    incoming = "来电中", answering = "接听中", talking = "通话中", dialing = "拨号中",
    ending = "挂断中", stopped = "未登录", error = "异常",
}

refresh_status = function()
    if not started then return end
    local s = app.status()
    set_text(top_status, (call_state_text[s.state] or s.state or "") .. "\n" .. kit.ellipsis(s.user or store.get_acct().user, 14))
    if profile_status then set_text(profile_status, s.user_text or s.text or "") end
end

-- ==================== 全屏通话层 ====================
local call_started_at
local function hhmmss(t)
    t = math.max(0, math.floor(t or 0))
    return string.format("%02d:%02d:%02d", math.floor(t / 3600), math.floor(t % 3600 / 60), t % 60)
end

show_call_layer = function()
    local s = app.status()
    -- 同一通话状态内的文字变化（"正在呼叫" → "对方响铃中"）只更新标签，不重建整屏。
    -- 每次重建都要销毁并重新创建整棵 LVGL 组件树（24 段渐变、头像、多个标签和按钮），
    -- 那是几十到上百毫秒的分配；而回铃音靠 10ms 一拍的协程喂 UART，一旦 Lua 被按住，
    -- 下行队列立刻被掏空，驱动用静音帧补位，听感就是一阵断续的"电报声"。
    if call_layer and call_layer_state == s.state then
        if call_sub then set_text(call_sub, s.user_text or s.text or "") end
        return
    end
    kit.destroy(call_layer)
    call_layer_state = s.state
    call_layer = kit.box(root, { x = 0, y = 0, w = RW, h = RH, color = C.dark2 })
    kit.grad(call_layer, 0, 0, RW, 280, C.dark2, C.dark1, 24)
    local peer = s.peer or s.number or ""
    kit.avatar(call_layer, { x = RW / 2 - 60, y = 90, size = 120, text = kit.first_char(store.display(peer)), font_size = 42 })
    local name = label(call_layer, 0, 234, RW, store.display(peer), 34, C.white, 46)
    if name.set_align then pcall(function() name:set_align(airui.TEXT_ALIGN_CENTER) end) end
    local sub = label(call_layer, 0, 288, RW, s.user_text or s.text or "", 20, C.white_dark, 32)
    if sub.set_align then pcall(function() sub:set_align(airui.TEXT_ALIGN_CENTER) end) end
    call_sub = sub
    local timer = label(call_layer, 0, 330, RW, "00:00:00", 26, C.brand, 38)
    if timer.set_align then pcall(function() timer:set_align(airui.TEXT_ALIGN_CENTER) end) end

    local bw, bh, gap = 190, 64, 28
    local total = bw * 2 + gap
    local bx = (RW - total) / 2
    if s.state == "incoming" then
        button(call_layer, bx, 430, bw, "拒接", function() success(app.hangup()) end, "red", bh)
        button(call_layer, bx + bw + gap, 430, bw, "接听", function() success(app.accept()) end, "green", bh)
    else
        button(call_layer, bx, 430, bw, s.muted and "取消静音" or "静音", function()
            success(app.toggle_mute()); render_call()
        end, "soft", bh)
        button(call_layer, bx + bw + gap, 430, bw, "挂断", function() success(app.hangup()) end, "red", bh)
    end

    if call_timer then sys.timerStop(call_timer) end
    call_started_at = s.connected_at or (os.time() - (s.duration or 0))
    local last_clock
    call_timer = sys.timerLoopStart(function()
        if not started then
            sys.timerStop(call_timer); call_timer = nil
            return
        end
        -- 500ms 只取一次状态：原来 busy() 里一次、这里再一次，通话中白跑两遍
        local st = app.status()
        if not call_states[st.state] then
            sys.timerStop(call_timer); call_timer = nil
            kit.destroy(call_layer); call_layer = nil
            call_layer_state, call_sub = nil, nil
            render()
            return
        end
        if st.state == "talking" then
            -- 秒数没变就不 set_text：每次 set_text 都会触发控件重绘，
            -- 500ms 一刷等于每秒白刷两次全屏，通话界面自己也在抢音频的调度时间
            local text = hhmmss(os.time() - call_started_at)
            if text ~= last_clock then
                last_clock = text
                set_text(timer, text)
            end
        end
    end, 500)
end
render_call = show_call_layer

function M.suspend_keyboard_if_active()
    if keyboard and not suspended then
        keyboard:hide(); suspended = true
        sys.timerStart(function() if suspended then keyboard:show(); suspended = false end end, 200)
    end
end

-- ==================== 时钟 ====================
local function tick_clock()
    local t = os.localtime and os.localtime(os.time()) or os.date("*t")
    set_text(clock_label, string.format("%02d:%02d", t.hour or 0, t.min or 0))
end
local clock_timer, window_id

-- ==================== 窗口生命周期 ====================
local on_state
local function on_create()
    -- 取工厂内容区实际画布尺寸；所有页面坐标仍以参考 1024x600 书写，
    -- 由 SX/SY 统一缩放到实际 W/H，因此 LEFT/TOP/PW/PH 保持参考值不变。
    local cw, ch = screen_w or RW, screen_h or RH
    local theme = require "ui_theme"
    cw, ch = theme.content_fit(cw, ch)
    W, H = cw, ch
    sxk = W / RW; syk = H / RH
    LEFT, TOP = 176, 64
    PW, PH = RW - LEFT - 24, RH - TOP - 24

    root = theme.page_bg(airui.screen, W, H)
    build_shell()
    page = "contacts"
    started = true
    render()
    refresh_status()
    tick_clock()
    clock_timer = sys.timerLoopStart(tick_clock, 1000 * 10)
    -- 自检页实时刷新帧数/帧率/峰值（照抄参考工程 1s 刷新节奏）
    -- 但【录音/回放进行中一律不刷】：这段文本近 300 字，set_text 会让 LVGL 重排并整块
    -- 重绘一次；而 Air1103 的下行是 Lua 10ms 一拍喂 UART，芯片内部 DAC 缓冲只有约 60ms，
    -- 一次几十毫秒的整块重绘就足够把它掏空 —— 表现就是"回放卡"。录音期间同样会丢 MIC 帧。
    -- 自检过程中的阶段变化仍由 AUDIO_DIAG 事件驱动刷新，信息不会缺。
    diag_timer = sys.timerLoopStart(function()
        if not (started and page == "diag" and diag_label) then return end
        local d = diag.status()
        if d.busy then return end
        set_text(diag_label, diag_text(d))
    end, 1000)

    -- 订阅 app 状态：非通话变化刷新导航/状态；进入通话拉起全屏层
    on_state = function()
        if not started then return end
        refresh_status()
        local s = app.status()
        if call_states[s.state] then
            show_call_layer()
        else
            if call_layer then
                if call_timer then sys.timerStop(call_timer); call_timer = nil end
                kit.destroy(call_layer); call_layer = nil
                call_layer_state, call_sub = nil, nil
            end
            render()
        end
    end
    -- 同事内核发布 SIP_STATE / SIP_ERROR（不是工厂旧的 SIP_TEST_*）
    sys.subscribe("SIP_STATE", on_state)
    sys.subscribe("SIP_ERROR", function(t) M.toast(t, true) end)
    sys.subscribe("SIP_MSG", function() if started then refresh_status() end end)
    -- 音频自检进度（sph_audio_diag 发布 AUDIO_DIAG），刷新自检页状态文本
    sys.subscribe("AUDIO_DIAG", function() if started and diag_label then set_text(diag_label, diag_text()) end end)

    -- 先确保存储 + 网络检测就绪（工厂 net_manager 已组网，这里只读状态）；
    -- 再 init 同事内核：内部 recover_messages，并按 auto_register 自动注册。
    -- 每步之间必须让出 CPU：4G 走 airlink(UART3) 桥接，mobile.*/socket.* 是同步 RPC，
    -- 在等响应期间如果 Lua 主任务被 store/audio 初始化按住几百毫秒，
    -- 内核会直接报 "airlink.rpc rpc yield timeout" 甚至总线错误死机。
    sys.taskInit(function()
        -- 进来先让一拍：上面 build_shell/render 是一次不让出的同步过程，
        -- 若此刻有 airlink RPC 在等响应，立刻再压 store/audio 初始化就会把它拖超时。
        sys.wait(100)
        pcall(store.init)
        sys.wait(50)
        pcall(net.init)
        sys.wait(50)
        -- 必须先初始化 Air1103/UART6：audio.init 内部会把 exaudio.sip_voip_start/stop
        -- 挂到通话桥 M.start/M.stop_bridge；否则通话建立时音频桥不存在。
        pcall(audio.init)
        sys.wait(50)
        pcall(raw_app.init)
    end)
end

local function on_destroy()
    sys.unsubscribe("SIP_STATE", on_state)
    sys.unsubscribe("SIP_ERROR")
    sys.unsubscribe("SIP_MSG")
    sys.unsubscribe("AUDIO_DIAG")
    if call_timer then sys.timerStop(call_timer) end
    if toast_timer then sys.timerStop(toast_timer) end
    if clock_timer then sys.timerStop(clock_timer) end
    if diag_timer then sys.timerStop(diag_timer) end
    if root then root:destroy() end
    root, started = nil, false
    call_layer, call_layer_state, call_sub = nil, nil, nil
    call_timer, clock_timer, diag_timer, window_id = nil, nil, nil, nil
    -- 独立协程回收：挂断通话→注销 SIP→停止音频/释放 Air1103,UART6。
    -- 幂等，失败不影响关窗；避免和工厂其它音频/网络测试抢资源。
    sys.taskInit(function()
        pcall(raw_app.hangup)
        pcall(raw_app.logout)
        pcall(audio.stop)
    end)
end

sys.subscribe("OPEN_SIP_TEST_WIN", function()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
end)

return M
