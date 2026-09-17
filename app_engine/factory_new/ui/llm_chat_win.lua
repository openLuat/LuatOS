--[[
@module  llm_chat_win
@summary AI 聊天助手窗口（UI层 - WebSocket 模式）
@version 3.0
@date    2026.08.26
@author  江访

消息协议:
订阅: OPEN_AI_CHAT_WIN       → 创建聊天窗口
订阅: AI_CHAT_TOKEN(token)   → 流式 token 到达
订阅: AI_CHAT_REPLY_DONE     → 回复完成
订阅: AI_CHAT_REPLY_ERROR    → 回复出错
订阅: AI_CHAT_STATUS(msg)    → 状态文本
订阅: AI_CHAT_TTS_STATUS     → TTS 开关状态
订阅: AI_CHAT_CONNECTED      → 已连接
订阅: AI_CHAT_DISCONNECTED   → 已断开
订阅: FACTORY_REC_READY      → 音频初始化结果
订阅: FACTORY_REC_STATE      → 录音状态变更
订阅: FACTORY_REC_DONE       → 录音完成
发布: AI_CHAT_SEND(text)     → 发送文本
发布: AI_CHAT_CLEAR          → 清空对话
发布: AI_CHAT_TTS_TOGGLE     → 切换 TTS
发布: AI_CHAT_TTS_PLAY(text) → 直接播报（测试用）
发布: FACTORY_REC_SETUP      → 初始化音频
发布: FACTORY_REC_START      → 开始录音
发布: FACTORY_REC_STOP       → 停止录音
发布: FACTORY_REC_RESET      → 清理音频
]]

local window_id = nil
local main_container = nil
local screen_w, screen_h = 480, 800
local margin = 12

-- 消息区（滚动容器 + label）
local msg_scroll = nil
local msg_labels = {}   -- { {label=widget, text=str, type="user"|"ai"|"status"}, ... }
local msg_y_offset = 0  -- 当前消息区 Y 偏移量

-- 输入区
local textarea = nil
local keyboard = nil
local send_btn = nil
local tts_btn = nil
local voice_btn = nil
local status_label = nil
local title_status = nil

-- 状态
local current_reply_text = ""
local reply_row = -1
local is_generating = false
local tts_on = true
local rec_state = "idle"
local ws_connected = false

-- 颜色
-- TabOS 深色玻璃态调色板（原浅色常量 → 主题令牌）
local theme = require "ui_theme"

-- 主题令牌动态代理：换主题后自动取到新色值
-- （写成 local X = theme.C.y 会在 require 时固化，换肤不生效）
local CLR = theme.live()

local function update_screen_size()
    local r = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if r == 0 or r == 180 then screen_w, screen_h = pw, ph
    else screen_w, screen_h = ph, pw end
    margin = theme.page_margin()
end

-- ==================== 消息区（滚动容器 + 按行 label） ====================

local LINE_H = 0  -- 在 build_ui 中初始化

local function split_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then  -- 跳过空行
            lines[#lines + 1] = line
        end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

local function scroll_to_bottom()
    if msg_scroll then pcall(msg_scroll.scroll_to_bottom, msg_scroll) end
end

-- 追加一条消息，返回 entry = { cards = {...}, type = str, text = str }
local function append_msg(text, msg_type)
    if not msg_scroll then return nil end
    local d = _G.density_scale or 1.0
    local pad = math.floor(6 * d)
    local card_w = screen_w - 2 * margin
    local label_w = card_w - 2 * pad
    local bg = msg_type == "user" and CLR.bubble_user or msg_type == "ai" and CLR.panel_hi or CLR.bg
    local fg = msg_type == "user" and CLR.white or msg_type == "ai" and CLR.t1 or CLR.t2
    local prefix = msg_type == "user" and "【我】" or msg_type == "ai" and "【AI】" or ""
    local lines = split_lines(prefix .. text)
    local cards = {}
    for i, line in ipairs(lines) do
        local h = LINE_H + math.floor(6 * d)
        -- 用户消息右对齐，其余左对齐
        local cx = msg_type == "user" and (screen_w - margin - card_w) or margin
        local card = airui.container({
            parent = msg_scroll, x = cx, y = msg_y_offset, w = card_w, h = h,
            color = bg, radius = theme.r("xs"),
        })
        local label = airui.label({
            parent = card, x = pad, y = math.floor(3 * d), w = label_w, h = LINE_H,
            text = line, font_size = theme.fs("caption"),
            color = fg, align = airui.TEXT_ALIGN_LEFT,
        })
        msg_y_offset = msg_y_offset + h
        cards[#cards + 1] = { card = card, label = label }
    end
    msg_y_offset = msg_y_offset + math.floor(4 * d)
    local entry = { cards = cards, text = text, type = msg_type }
    msg_labels[#msg_labels + 1] = entry
    scroll_to_bottom()
    return entry
end

-- 更新最后一条消息（流式）
local function update_last_msg(text)
    local entry = msg_labels[#msg_labels]
    if not entry then return end
    entry.text = text
    local d = _G.density_scale or 1.0
    local pad = math.floor(6 * d)
    local card_w = screen_w - 2 * margin
    local label_w = card_w - 2 * pad
    local fg = entry.type == "user" and CLR.white or entry.type == "ai" and CLR.t1 or CLR.t2
    local bg = entry.type == "user" and CLR.bubble_user or entry.type == "ai" and CLR.panel_hi or CLR.bg
    local prefix = entry.type == "user" and "【我】" or entry.type == "ai" and "【AI】" or ""
    local cx = entry.type == "user" and (screen_w - margin - card_w) or margin
    local lines = split_lines(prefix .. text)
    local h = LINE_H + math.floor(6 * d)
    -- 复用已有的卡片，多余则销毁，不足则补
    local old = entry.cards
    for i = 1, math.max(#lines, #old) do
        if i <= #lines and i <= #old then
            pcall(old[i].label.set_text, old[i].label, lines[i])
        elseif i <= #lines then
            local card = airui.container({
                parent = msg_scroll, x = cx, y = 0, w = card_w, h = h,
                color = bg, radius = theme.r("xs"),
            })
            local label = airui.label({
                parent = card, x = pad, y = math.floor(3 * d), w = label_w, h = LINE_H,
                text = lines[i], font_size = theme.fs("caption"),
                color = fg, align = airui.TEXT_ALIGN_LEFT,
            })
            old[#old + 1] = { card = card, label = label }
        else
            pcall(old[i].card.destroy, old[i].card)
            old[i] = nil
        end
    end
    -- 重算所有消息的 Y 偏移
    msg_y_offset = 0
    for _, e in ipairs(msg_labels) do
        for _, c in ipairs(e.cards) do
            pcall(c.card.set_pos, c.card, e.type == "user" and (screen_w - margin - card_w) or margin, msg_y_offset)
            msg_y_offset = msg_y_offset + h + math.floor(4 * d)
        end
    end
    scroll_to_bottom()
end

-- ==================== 按钮状态 ====================

local function set_btn_style(btn, bg, fg)
    if btn then btn:set_style({ bg_color = bg, text_color = fg }) end
end

local function update_send_btn()
    if not send_btn then return end
    if is_generating then
        send_btn:set_disabled(true); send_btn:set_text("生成中...")
        set_btn_style(send_btn, CLR.line_soft, CLR.t2)
    else
        send_btn:set_disabled(false); send_btn:set_text("发送")
        set_btn_style(send_btn, CLR.primary, CLR.white)
    end
end

local function update_tts_btn()
    if not tts_btn then return end
    if tts_on then
        tts_btn:set_text("语音开")
        set_btn_style(tts_btn, CLR.green, CLR.white)
    else
        tts_btn:set_text("语音关")
        set_btn_style(tts_btn, CLR.line_soft, CLR.t2)
    end
end

local function update_voice_btn()
    if not voice_btn then return end
    if rec_state == "recording" then
        voice_btn:set_text("停止")
        set_btn_style(voice_btn, CLR.rose, CLR.white)
    else
        voice_btn:set_text("录音")
        set_btn_style(voice_btn, CLR.primary, CLR.white)
    end
end

local function update_title_status()
    if not title_status then return end
    if ws_connected then
        title_status:set_text("已连接")
        title_status:set_color(CLR.green)
    else
        title_status:set_text("未连接")
        title_status:set_color(CLR.rose)
    end
end

-- ==================== 事件回调 ====================

local function on_token(token)
    if not token or token == "" then return end
    current_reply_text = current_reply_text .. token
    update_last_msg(current_reply_text)
end

local function on_reply_done(text)
    is_generating = false
    if #current_reply_text > 0 then
        update_last_msg(current_reply_text)
    end
    current_reply_text = ""; reply_row = -1
    update_send_btn()
    if status_label then
        status_label:set_text(ws_connected and "已连接" or "")
    end
end

local function on_reply_error(msg)
    if is_generating and #current_reply_text > 0 then
        update_last_msg(current_reply_text .. "\n[中断]")
    elseif not is_generating then
        -- 正常结束后收到的错误通知：忽略
    else
        append_msg(tostring(msg or ""), "status")
    end
    is_generating = false; current_reply_text = ""; reply_row = -1
    update_send_btn()
end

local function on_status(msg) if status_label then status_label:set_text(msg or "") end end

local function on_tts_status(enabled) tts_on = enabled; update_tts_btn() end

local function on_connected() ws_connected = true; update_title_status() end

local function on_disconnected() ws_connected = false; update_title_status() end

local function on_rec_ready(ok, msg)
    if not ok then append_msg("录音初始化失败: " .. tostring(msg or ""), "status") end
end

local function on_rec_state(data)
    if data and data.state then rec_state = data.state; update_voice_btn() end
end

local function on_rec_done(data)
    rec_state = "idle"; update_voice_btn()
    if data and data.size and data.size > 0 and data.path then
        sys.publish("AI_CHAT_STT", data.path)
    end
end

local function on_stt_result(text)
    if text and text ~= "" then
        if textarea then textarea:set_text(text) end
        append_msg("语音识别完成", "status")
    else
        append_msg("语音识别无结果", "status")
    end
end

-- ==================== 发送 ====================

local function do_send()
    if is_generating then return end
    if not textarea then return end
    local text = textarea:get_text() or ""
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    append_msg(text, "user")
    textarea:set_text("")
    append_msg("...", "ai")
    reply_row = #msg_labels
    is_generating = true; current_reply_text = ""
    update_send_btn()
    sys.publish("AI_CHAT_SEND", text)
end

local function toggle_recording()
    if rec_state == "recording" then sys.publish("FACTORY_REC_STOP")
    else sys.publish("FACTORY_REC_START") end
end

-- ==================== UI 构建 ====================

local function build_ui()
    update_screen_size()
    local d = _G.density_scale or 1.0
    --[[行高必须 >= 字号 + 3：hzfont 的 line_height 固定为 size + extra_leading(3)，
    原来 LINE_H = 14 配 theme.fs("caption")=14 的字号，文字比盒子高 3px，
    每行都会画到盒外（压到下一条消息上）。]]
    LINE_H = theme.fs("caption") + 3  -- 每行 label 高度
    local tb_h = math.floor(48 * d)
    local tb_y = math.floor(4 * d)
    local input_area_h = math.floor(90 * d)
    local status_h = math.floor(22 * d)

main_container = theme.page_bg(airui.screen, screen_w, screen_h)

    -- 标题栏：统一组件（玻璃底 + 返回键 + 标题 + 右侧连接状态）
    -- 原来是自己画的 main 色实心条，返回键又是 main 底 main 字，实机上几乎看不见
    local bar, th, _ttl, tstatus = theme.header(main_container, {
        x = margin, y = margin, w = screen_w - 2 * margin, h = tb_h,
        title = "AI 助手",
        on_back = function() if window_id then exwin.close(window_id) end end,
        right = "未连接",
        right_w = math.floor(64 * d),
        right_color = CLR.rose,
    })
    title_status = tstatus
    tb_h = margin + th   -- 内容区从标题栏下方 + 页边距开始

    -- 消息区（滚动容器）
    local msg_area_h = screen_h - tb_h - input_area_h - status_h
    msg_scroll = airui.container({
        parent = main_container, x = margin, y = tb_h, w = screen_w - 2 * margin, h = msg_area_h,
        color = CLR.surface, color_opacity = 0, scrollable = true,
    })
    msg_labels = {}; msg_y_offset = math.floor(4 * d)
    append_msg("连接 LuatOS 后台中...", "status")

    -- 状态栏
    local status_y = tb_h + msg_area_h
    status_label = airui.label({ parent = main_container, x = 0, y = status_y, w = screen_w, h = status_h,
        text = "", font_size = theme.fs("micro"), color = CLR.t2, align = airui.TEXT_ALIGN_CENTER })

    -- 输入区
    local input_y = status_y + status_h
    local input_area = airui.container({ parent = main_container, x = 0, y = input_y, w = screen_w, h = input_area_h, color = CLR.surface, color_opacity = theme.OPA.glass, border_color = CLR.stroke, border_width = 1 })

    pcall(function()
        keyboard = airui.keyboard({ x = 0, y = -math.floor(20 * d), w = screen_w, h = math.floor(180 * d),
            mode = "text", auto_hide = true, preview = true, on_commit = function(self) self:hide() end })
    end)

    local send_w = math.floor(48 * d)
    local gap = math.floor(4 * d)
    local ta_w = screen_w - 2 * margin - send_w - gap
    local ta_h = math.floor(36 * d)
    local ta_y = math.floor(6 * d)

    textarea = theme.input({ parent = input_area, x = margin, y = ta_y, w = ta_w, h = ta_h,
        text = "", placeholder = "输入消息...", font_size = theme.fs("label"), max_len = 500, keyboard = keyboard })

    send_btn = airui.button({ parent = input_area, x = margin + ta_w + gap, y = ta_y, w = send_w, h = ta_h,
        text = "发送", font_size = theme.fs("caption"),
        style = { bg_color = CLR.primary, text_color = CLR.white, border_width = 0, radius = theme.r("xs") },
        on_click = function() if keyboard then keyboard:hide() end; do_send() end })

    -- 第二行按钮：语音开 | 录音 | 清空
    local btn2_y = ta_y + ta_h + math.floor(4 * d)
    local btn2_h = math.floor(28 * d)
    local row_w = screen_w - 2 * margin
    local btn3_w = math.floor((row_w - 2 * gap) / 3)

    tts_btn = airui.button({ parent = input_area, x = margin, y = btn2_y, w = btn3_w, h = btn2_h,
        text = "语音开", font_size = theme.fs("micro"),
        style = { bg_color = CLR.primary, text_color = CLR.white, border_width = 0, radius = theme.r("xs") },
        on_click = function() sys.publish("AI_CHAT_TTS_TOGGLE") end })

    voice_btn = airui.button({ parent = input_area, x = margin + btn3_w + gap, y = btn2_y, w = btn3_w, h = btn2_h,
        text = "录音", font_size = theme.fs("micro"),
        style = { bg_color = CLR.primary, text_color = CLR.white, border_width = 0, radius = theme.r("xs") },
        on_click = function() toggle_recording() end })

    airui.button({ parent = input_area, x = margin + 2 * (btn3_w + gap), y = btn2_y, w = btn3_w, h = btn2_h,
        text = "清空", font_size = theme.fs("micro"),
        style = { bg_color = CLR.line_soft, text_color = CLR.t2, border_width = 0, radius = theme.r("xs") },
        on_click = function()
            sys.publish("AI_CHAT_CLEAR")
            if msg_scroll then msg_scroll:destroy() end
            msg_scroll = airui.container({
                parent = main_container, x = 0, y = tb_h, w = screen_w, h = msg_area_h,
                color = CLR.surface, color_opacity = 0, scrollable = true,
            })
            msg_labels = {}; msg_y_offset = math.floor(4 * d)
            append_msg("会话已清空", "status")
        end })

    update_send_btn(); update_tts_btn(); update_voice_btn(); update_title_status()
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    build_ui()
    is_generating = false; current_reply_text = ""; reply_row = -1; rec_state = "idle"
    sys.subscribe("AI_CHAT_TOKEN", on_token)
    sys.subscribe("AI_CHAT_REPLY_DONE", on_reply_done)
    sys.subscribe("AI_CHAT_REPLY_ERROR", on_reply_error)
    sys.subscribe("AI_CHAT_STATUS", on_status)
    sys.subscribe("AI_CHAT_TTS_STATUS", on_tts_status)
    sys.subscribe("AI_CHAT_CONNECTED", on_connected)
    sys.subscribe("AI_CHAT_DISCONNECTED", on_disconnected)
    sys.subscribe("FACTORY_REC_READY", on_rec_ready)
    sys.subscribe("FACTORY_REC_STATE", on_rec_state)
    sys.subscribe("FACTORY_REC_DONE", on_rec_done)
    sys.subscribe("AI_CHAT_STT_RESULT", on_stt_result)
    sys.publish("FACTORY_REC_SETUP")
end

local function on_destroy()
    sys.publish("AI_CHAT_CLOSE")
    sys.unsubscribe("AI_CHAT_TOKEN", on_token)
    sys.unsubscribe("AI_CHAT_REPLY_DONE", on_reply_done)
    sys.unsubscribe("AI_CHAT_REPLY_ERROR", on_reply_error)
    sys.unsubscribe("AI_CHAT_STATUS", on_status)
    sys.unsubscribe("AI_CHAT_TTS_STATUS", on_tts_status)
    sys.unsubscribe("AI_CHAT_CONNECTED", on_connected)
    sys.unsubscribe("AI_CHAT_DISCONNECTED", on_disconnected)
    sys.unsubscribe("FACTORY_REC_READY", on_rec_ready)
    sys.unsubscribe("FACTORY_REC_STATE", on_rec_state)
    sys.unsubscribe("FACTORY_REC_DONE", on_rec_done)
    sys.unsubscribe("AI_CHAT_STT_RESULT", on_stt_result)
    sys.publish("FACTORY_REC_RESET")
    sys.publish("AI_CHAT_DEINIT")
    if keyboard then pcall(keyboard.destroy, keyboard); keyboard = nil end
    if main_container then main_container:destroy(); main_container = nil end
    msg_scroll = nil; msg_labels = {}; msg_y_offset = 0
    textarea = nil; send_btn = nil; tts_btn = nil; voice_btn = nil
    status_label = nil; title_status = nil
    is_generating = false; current_reply_text = ""; reply_row = -1; rec_state = "idle"
    window_id = nil
end

-- 换肤：打脏标记，等本页重新回到前台时重建（换肤当下本页在窗口栈下层，不打扰栈顺序）
local mark_theme_dirty, take_theme_dirty = theme.dirty_flag()
sys.subscribe("UI_THEME_CHANGED", mark_theme_dirty)

local function ongf()
    if take_theme_dirty() then
        local keep_id = window_id
        on_destroy()
        on_create()
        window_id = keep_id
    end
end
local function onlf() end

local function open_handler()
    window_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_get_focus = ongf, on_lose_focus = onlf })
    sys.publish("AI_CHAT_OPEN")
end

sys.subscribe("OPEN_AI_CHAT_WIN", open_handler)
