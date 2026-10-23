--[[
@module  ui_call
@summary 通话界面（1024x600）：呼出 / 来电接听 / 通话中控制
@version 1.2.2
@date    2026.10.21
@usage
  local pages = ui_call.create(root)
  ui_call.set_state(state, mode, peer)
  ui_call.set_timer(seconds)
  ui_call.set_media(muted, speaker, camera)
]]

local T    = require "ui_theme"
local call = require "call_mgr"

local M = {}

local voice_page, video_page
local v_name, v_status, v_timer
local d_status, d_timer
local mute_v, spk_v, mute_d, cam_d
local cam_tip

local v_active, v_ringing = {}, {}
local d_active, d_ringing = {}, {}

-- 脏检查缓存：重复的 set_* 会触发重排与局部刷新，值没变就跳过
local last_v_status, last_d_status, last_timer, last_peer
local last_ring
local last_muted, last_speaker, last_camera

local function box(parent, x, y, w, h, color, radius)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, radius = radius or 0,
    })
end

local function text(parent, str, x, y, w, h, size, color, align)
    return airui.label({
        parent = parent, text = str, x = x, y = y, w = w, h = h,
        font = "hzfont", font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 圆形控制键：外层容器（与页面同色，便于整组显隐）+ 圆形按钮 + 下方文字
-- @return wrapper, circle
local function ctl(parent, cx, cy, d, symbol, caption, bg, on_click)
    local bw = d + 44
    local wrapper = box(parent, cx - bw // 2, cy - d // 2 - 10, bw, d + 44, T.BG, 0)
    local c = box(wrapper, 22, 10, d, d, bg, d // 2)
    airui.label({
        parent = c, text = "", symbol = symbol, x = 0, y = 0, w = d, h = d,
        font = "hzfont", font_size = d * 5 // 12, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER,
    })
    text(wrapper, caption, 0, 10 + d + 6, bw, 18, 14, T.TEXT_SUB, airui.TEXT_ALIGN_CENTER)
    pcall(function() c:set_on_click(on_click) end)
    return wrapper, c
end

local function show_group(group, visible)
    for _, w in ipairs(group) do
        pcall(function() w:set_hidden(not visible) end)
    end
end

--- 创建两个通话页面
-- @param root 根容器
function M.create(root)
    local W, H = UI_W or 1024, UI_H or 600
    local cx = W // 2
    local pH = H - 88

    -- ===================== 语音通话页 =====================
    voice_page = airui.container({
        parent = root, x = 0, y = 88, w = W, h = pH, color = T.BG,
    })

    local avatar = box(voice_page, cx - 90, 46, 180, 180, T.ORANGE, 90)
    pcall(function() avatar:set_border_color(T.ORANGE_LT, 3) end)
    airui.label({
        parent = avatar, text = "", symbol = airui.SYMBOL_CALL,
        x = 0, y = 0, w = 180, h = 180,
        font = "hzfont", font_size = 78, color = T.DARK_TEXT, align = airui.TEXT_ALIGN_CENTER,
    })

    v_name   = text(voice_page, call.peer, 0, 252, W, 44, 32, T.TEXT, airui.TEXT_ALIGN_CENTER)
    v_status = text(voice_page, "正在呼叫…", 0, 306, W, 28, 19, T.ORANGE_LT, airui.TEXT_ALIGN_CENTER)
    v_timer  = text(voice_page, "00:00", 0, 340, W, 28, 22, T.TEXT_SUB, airui.TEXT_ALIGN_CENTER)

    local wm, bm = ctl(voice_page, cx - 160, 430, 96, airui.SYMBOL_MUTE, "静音", T.CARD_LT, function()
        call.toggle_mute()
    end)
    mute_v = bm

    local ws, bs = ctl(voice_page, cx, 430, 96, airui.SYMBOL_VOLUME_MAX, "免提", T.CARD_LT, function()
        call.toggle_speaker()
    end)
    spk_v = bs

    local wh, bh = ctl(voice_page, cx + 160, 430, 96, airui.SYMBOL_CLOSE, "挂断", T.RED, function()
        call.hangup()
    end)
    v_active = { wm, ws, wh }

    -- 来电：拒接 / 接听
    local wr, _ = ctl(voice_page, cx - 110, 430, 96, airui.SYMBOL_CLOSE, "拒接", T.RED, function()
        call.reject()
    end)
    local wa, _ = ctl(voice_page, cx + 110, 430, 96, airui.SYMBOL_CALL, "接听", T.GREEN, function()
        call.answer()
    end)
    v_ringing = { wr, wa }

    -- ===================== 视频通话页 =====================
    video_page = airui.container({
        parent = root, x = 0, y = 88, w = W, h = pH, color = T.BG,
    })

    local remote = box(video_page, 26, 14, W - 52, 334, 0x000000, 16)
    pcall(function() remote:set_border_color(T.LINE, 1) end)
    text(remote, "REMOTE", 18, 16, 120, 18, 13, T.TEXT_DIM)
    text(remote, "等待视频画面…", 0, 150, W - 52, 32, 19, T.TEXT_DIM, airui.TEXT_ALIGN_CENTER)

    local local_box = box(video_page, W - 236, 44, 204, 148, 0x15181C, 12)
    pcall(function() local_box:set_border_color(T.ORANGE, 2) end)
    cam_tip = text(local_box, "本地预览", 0, 60, 204, 26, 15, T.TEXT_SUB, airui.TEXT_ALIGN_CENTER)

    d_status = text(video_page, "正在呼叫…", 30, 368, 560, 32, 22, T.ORANGE_LT)
    d_timer  = text(video_page, "00:00", 30, 408, 220, 28, 18, T.TEXT_SUB)

    local wmd, bmd = ctl(video_page, W - 360, 420, 80, airui.SYMBOL_MUTE, "静音", T.CARD_LT, function()
        call.toggle_mute()
    end)
    mute_d = bmd

    local wcd, bcd = ctl(video_page, W - 240, 420, 80, airui.SYMBOL_VIDEO, "摄像头", T.CARD_LT, function()
        call.toggle_camera()
    end)
    cam_d = bcd

    local whd, _ = ctl(video_page, W - 120, 420, 80, airui.SYMBOL_CLOSE, "挂断", T.RED, function()
        call.hangup()
    end)
    d_active = { wmd, wcd, whd }

    local wrd, _ = ctl(video_page, W - 260, 420, 88, airui.SYMBOL_CLOSE, "拒接", T.RED, function()
        call.reject()
    end)
    local wad, _ = ctl(video_page, W - 130, 420, 88, airui.SYMBOL_CALL, "接听", T.GREEN, function()
        call.answer()
    end)
    d_ringing = { wrd, wad }

    -- 初始：显示通话中控制组，隐藏来电组
    show_group(v_active, true)
    show_group(d_active, true)
    show_group(v_ringing, false)
    show_group(d_ringing, false)

    voice_page:set_hidden(true)
    video_page:set_hidden(true)

    return { voice = voice_page, video = video_page }
end

--- 刷新通话状态
-- @param state dialing / ringing / connecting / talking / idle
-- @param mode voice / video
-- @param peer 对端名称
function M.set_state(state, mode, peer)
    local ring = (state == "ringing")

    if ring ~= last_ring then
        last_ring = ring
        show_group(v_active, not ring)
        show_group(d_active, not ring)
        show_group(v_ringing, ring)
        show_group(d_ringing, ring)
    end

    local s = "通话结束"
    if state == "dialing" then
        s = "正在呼叫…"
    elseif state == "ringing" then
        s = "微信来电"
    elseif state == "connecting" then
        s = "正在连接…"
    elseif state == "talking" then
        s = "通话中"
    end

    if v_status and s ~= last_v_status then
        last_v_status = s
        v_status:set_text(s)
    end
    local ds = (mode == "video" and "视频通话 · " or "语音通话 · ") .. s
    if d_status and ds ~= last_d_status then
        last_d_status = ds
        d_status:set_text(ds)
    end
    if peer and #peer > 0 and peer ~= last_peer then
        last_peer = peer
        if v_name then v_name:set_text(peer) end
    end

    if state ~= "talking" then
        M.set_timer(0)
    end
end

--- 刷新通话计时（值未变则不重绘）
function M.set_timer(sec)
    local s = call.fmt(sec or 0)
    if s == last_timer then return end
    last_timer = s
    if v_timer then v_timer:set_text(s) end
    if d_timer then d_timer:set_text(s) end
end

--- 刷新媒体开关状态（橙色 = 已启用）
function M.set_media(muted, speaker, camera)
    if muted ~= last_muted then
        last_muted = muted
        if mute_v then pcall(function() mute_v:set_color(muted and T.ORANGE or T.CARD_LT) end) end
        if mute_d then pcall(function() mute_d:set_color(muted and T.ORANGE or T.CARD_LT) end) end
    end
    if speaker ~= last_speaker then
        last_speaker = speaker
        if spk_v then pcall(function() spk_v:set_color(speaker and T.ORANGE or T.CARD_LT) end) end
    end
    if camera ~= last_camera then
        last_camera = camera
        if cam_d then pcall(function() cam_d:set_color(camera and T.ORANGE or T.CARD_LT) end) end
        if cam_tip then
            cam_tip:set_text(camera and "本地预览" or "摄像头已关闭")
            cam_tip:set_color(camera and T.TEXT_SUB or T.ORANGE_LT)
        end
    end
end

return M
