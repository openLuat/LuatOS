--[[
@module  audio_test_win
@summary 录音播放测试页（Air1103 等语音芯片：录音 / 停止 / 播放 + 测试日志）
@version 1.0
@date    2026.10.26
@author  江访
@usage
订阅: OPEN_AUDIO_TEST_WIN(id)        -- id 只是入口来源，页面固定测 hw.audio 这一路音频
发布: OTHER_FUNC_SET(id, true)       -- 上电并初始化音频（进页面自动做一次）
发布: OTHER_FUNC_GET                 -- 拉一次音频打开状态
发布: AUDIO_REC_START(id, seconds)   -- 录音 seconds 秒
发布: AUDIO_REC_STOP(id)             -- 提前结束录音
发布: AUDIO_PLAY_START(id)           -- 回放最近一次录音
发布: AUDIO_PLAY_STOP(id)            -- 停止回放
订阅: AUDIO_ACTION_RESULT(id, action, ok, err) -- 动作回执
订阅: AUDIO_TEST_STATE(id, state, info)        -- 驱动状态迁移
订阅: OTHER_FUNC_STATUS / OTHER_FUNC_CHANGED(list) -- 音频打开状态

页面自上而下：
  状态卡  芯片 / 串口 / 录音格式 + 当前状态描述
  录音时长  3 / 5 / 10 / 20 秒里选一个（超过 hw.audio.max_record_time 的选项不显示）
  操作    开始录音 / 播放 / 停止（空闲态禁用「停止」，录音或播放中禁用「录音」「播放」）
  测试日志  动作与结果流水（最新在上）+「清空」

录音与播放互斥，同一时刻只有一件事在跑，所以「停止」一个按钮就够，不用区分停录音还是停播放。
驱动那边同样做了互斥判断，重复点被拒时把原因回给本页弹提示。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local pad = 15

-- 日志只留最近 MAX_KEEP 条，超出丢最旧的
local MAX_KEEP = 100
-- 可选录音时长（秒），超过硬件上限的项不显示
local DURATIONS = { 3, 5, 10, 20 }

-- 测试页只测 hw.audio 这一路音频，记录它的 id 与硬件配置
local audio_id = nil
local audio_cfg = nil
local seconds = 5

local state_label = nil
local state_w = 0
local cur_state = "idle"  -- 驱动状态码，决定哪几个操作按钮可用
local dur_btns = {}   -- { {sec=, btn=}, ... }
local act_btns = {}   -- { rec=, play=, stop= }

local entries = {}    -- { {ts=, text=}, ... }
local log_labels = {} -- 固定行池，只改文字不增删控件
local log_w = 0

-- ==================== 基础工具 ====================

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

-- theme 包装对象 / airui 对象的方法都用 pcall 兜着调，控件已销毁时不至于炸
local function safe_call(obj, method, a1, a2)
    if obj == nil then return end
    local ok, fn = pcall(function() return obj[method] end)
    if not ok or type(fn) ~= "function" then return end
    pcall(fn, obj, a1, a2)
end

-- 提示弹窗（标题 + 一句说明 + 单个确定按钮）
local function show_tip(text)
    airui.msgbox({
        title = "提示", text = text, buttons = { "确定" },
        on_action = function(self) self:hide() end,
    })
end

-- 驱动状态码 → 屏幕上的中文
local STATE_TEXT = {
    idle      = "空闲",
    recording = "录音中",
    playing   = "播放中",
    error     = "异常",
}

-- 动作名 → 日志里的动词
local ACTION_TEXT = {
    record_start = "录音",
    record_stop  = "停止录音",
    play_start   = "播放",
    play_stop    = "停止播放",
}

-- ==================== 测试日志 ====================

-- 只画可见行：最新一条贴顶（日志(最新在上)），省去滚动定位
local function render_log()
    local n = #log_labels
    local total = #entries
    for i = 1, n do
        local e = entries[total - i + 1]
        local lab = log_labels[i]
        if lab and not lab:is_destroyed() then
            if e then
                lab:set_text(theme.fit_text(string.format("%s %s", e.ts, e.text),
                                            log_w, theme.fs("caption")))
            else
                lab:set_text("")
            end
        end
    end
end

local function append_entry(text)
    entries[#entries + 1] = { ts = os.date("%H:%M:%S"), text = tostring(text or "") }
    while #entries > MAX_KEEP do table.remove(entries, 1) end
    render_log()
end

local function clear_log()
    entries = {}
    render_log()
end

-- ==================== 状态与选项 ====================

-- 刷新状态卡文字
local function set_state_text(text)
    safe_call(state_label, "set_text", theme.fit_text(tostring(text or ""), state_w, theme.fs("body")))
end

-- 刷新录音时长选项的点亮态（当前选中的那个用强调色，连按压态一起换）
-- 样式走 button:set_style 的部分覆盖，只覆盖底色/描边/文字/按压态四个字段
local function refresh_dur_btns()
    for i = 1, #dur_btns do
        local d = dur_btns[i]
        local on = (d.sec == seconds)
        safe_call(d.btn, "set_style", {
            bg_color        = on and theme.C.amber or theme.C.surface,
            border_color    = on and theme.C.amber or theme.C.stroke,
            text_color      = on and theme.C.on_amber or theme.C.t1,
            pressed_bg_color = on and theme.C.amber_deep or theme.C.surface,
            pressed_text_color = on and theme.C.on_amber or theme.C.t1,
        })
    end
end

-- 按当前状态禁用不可点的按钮：录音/播放只在空闲态可用，停止只在录音或播放时可用
local function refresh_action_btns()
    local busy = (cur_state == "recording" or cur_state == "playing")
    safe_call(act_btns.rec,  "set_disabled", busy)
    safe_call(act_btns.play, "set_disabled", busy)
    safe_call(act_btns.stop, "set_disabled", not busy)
end

-- 可选时长：硬件上限以下的那几档，上限不够时只留上限这一档
local function duration_options()
    local max_t = tonumber(audio_cfg and audio_cfg.max_record_time) or 30
    local out = {}
    for i = 1, #DURATIONS do
        if DURATIONS[i] <= max_t then out[#out + 1] = DURATIONS[i] end
    end
    if #out == 0 then out[1] = max_t end
    return out
end

-- 默认选中：config 的 record_seconds 落在可选档里就选它，否则取最接近的一档
local function default_seconds(opts)
    local want = tonumber(seconds) or 5
    local best, best_gap = opts[1], math.huge
    for i = 1, #opts do
        local gap = math.abs(opts[i] - want)
        if gap < best_gap then best, best_gap = opts[i], gap end
    end
    return best
end

-- ==================== 硬件信息 ====================

-- 从 config.peripherals 取 audio 条目，与 config.hw.audio 一起构成页面信息
local function collect_audio()
    audio_id = nil
    audio_cfg = (_G.project_config or {}).hw and (_G.project_config or {}).hw.audio
    local list = (_G.project_config or {}).peripherals
    if type(list) ~= "table" then return end
    for i, p in ipairs(list) do
        if p and p.type == "audio" and p.id then
            audio_id = p.id
            seconds = tonumber(p.record_seconds) or 5
            return
        end
    end
end

-- 状态卡第一行：芯片 | 串口 | 录音格式
local function hw_summary()
    local ac = audio_cfg or {}
    local parts = { tostring(ac.model or "?") }
    if ac.uart_id then parts[#parts + 1] = "UART" .. tostring(ac.uart_id) end
    parts[#parts + 1] = "录音 " .. tostring(ac.record_format or "AMR_NB")
    -- 分隔符用 ASCII 的 "|"：内置字库不含 "·"(U+00B7)
    return table.concat(parts, " | ")
end

-- ==================== 动作 ====================

local function do_record()
    if not audio_id then return end
    sys.publish("AUDIO_REC_START", audio_id, seconds)
end

local function do_play()
    if not audio_id then return end
    sys.publish("AUDIO_PLAY_START", audio_id)
end

-- 录音与播放只有一件事在跑，一个停止按钮通吃
local function do_stop()
    if not audio_id then return end
    sys.publish("AUDIO_REC_STOP", audio_id)
    sys.publish("AUDIO_PLAY_STOP", audio_id)
end

-- ==================== 事件 ====================

-- 驱动状态迁移
local function on_test_state(id, state, info)
    if id ~= audio_id then return end
    cur_state = tostring(state or "idle")
    refresh_action_btns()
    local text = STATE_TEXT[state] or tostring(state or "")
    if info and info ~= "" then text = text .. " | " .. tostring(info) end
    set_state_text(text)
    append_entry(text)
end

-- 动作回执：失败要把原因摆出来，现场才知道是没初始化还是没录音文件
local function on_action_result(id, action, ok, err)
    if id ~= audio_id then return end
    local verb = ACTION_TEXT[action] or tostring(action or "")
    if ok then
        append_entry(verb .. " 已提交")
    else
        local msg = verb .. " 失败：" .. tostring(err or "未知原因")
        append_entry(msg)
        show_tip(msg)
    end
end

-- 音频打开状态回填（进页面自动初始化的那次结果）
local function on_status(list)
    if type(list) ~= "table" then return end
    for _, s in ipairs(list) do
        if s and s.id == audio_id then
            local st = s.info and s.info ~= "" and s.info or (s.enabled and "已打开" or "未打开")
            set_state_text(st)
            return
        end
    end
end

-- ==================== 界面 ====================

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)

    local card_w = sw - 2 * pad
    local _, th = theme.header(main_container, {
        x = pad, y = pad, w = card_w,
        title = "录音播放测试",
        sub = "对麦克风说话，录完回放听效果",
        on_back = function() exwin.close(window_id) end,
    })

    local gap = theme.dp(8)
    local y = pad + th + gap

    -- ===== 状态卡 =====
    local bw = 1
    local pad_in = theme.dp(12)
    local fs_name = theme.fs("body")
    local fs_sub = theme.fs("micro")
    local info_h = fs_name + theme.dp(4)
    local sub_h = fs_sub + theme.dp(4)
    -- 三行文字的占位：行1 info_h + 行距 dp(4) + 行2 info_h + 行距 dp(10) + 行3 sub_h
    local card_h = pad_in + info_h + theme.dp(4) + info_h + theme.dp(10) + sub_h + pad_in

    local card = theme.card(main_container, {
        x = pad, y = y, w = card_w, h = card_h, border_w = bw,
    })
    local inner_w = card_w - 2 * bw - 2 * pad_in

    theme.label(card, {
        x = pad_in, y = pad_in, w = inner_w, h = info_h,
        text = theme.fit_text(hw_summary(), inner_w, fs_name),
        px_size = fs_name, color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    state_w = inner_w
    state_label = theme.label(card, {
        x = pad_in, y = pad_in + info_h + theme.dp(4), w = inner_w, h = info_h,
        text = "读取中...", px_size = fs_name,
        color = theme.C.amber_light, align = airui.TEXT_ALIGN_LEFT,
    })

    theme.label(card, {
        x = pad_in, y = pad_in + info_h + theme.dp(4) + info_h + theme.dp(10),
        w = inner_w, h = sub_h,
        text = "录音互斥：录音中不能播放，播放中不能录音",
        px_size = fs_sub, color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })
    y = y + card_h + gap

    -- ===== 录音时长 =====
    local opts = duration_options()
    seconds = default_seconds(opts)

    local lab_w = theme.dp(80)
    local btn_h = theme.dp(36)
    theme.label(main_container, {
        x = pad, y = y, w = lab_w, h = btn_h,
        text = "录音时长", px_size = fs_sub,
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    local dur_gap = theme.dp(8)
    local dur_w = math.floor((card_w - lab_w - (#opts - 1) * dur_gap) / #opts)
    dur_btns = {}
    for i, sec in ipairs(opts) do
        local d = { sec = sec }
        d.btn = theme.ghost_button(main_container, {
            x = pad + lab_w + (i - 1) * (dur_w + dur_gap), y = y,
            w = dur_w, h = btn_h,
            text = tostring(sec) .. "秒", size = 12,
            on_click = function()
                seconds = d.sec
                refresh_dur_btns()
                append_entry("录音时长设为 " .. tostring(d.sec) .. " 秒")
            end,
        })
        dur_btns[i] = d
    end
    refresh_dur_btns()
    y = y + btn_h + gap

    -- ===== 操作按钮 =====
    local act_h = theme.dp(44)
    local act_gap = theme.dp(10)
    local act_w = math.floor((card_w - 2 * act_gap) / 3)

    act_btns = {}
    act_btns.rec = theme.button(main_container, {
        x = pad, y = y, w = act_w, h = act_h,
        text = "开始录音", size = 13, on_click = do_record,
    })
    act_btns.play = theme.ghost_button(main_container, {
        x = pad + act_w + act_gap, y = y, w = act_w, h = act_h,
        text = "播放", size = 13, on_click = do_play,
    })
    act_btns.stop = theme.ghost_button(main_container, {
        x = pad + 2 * (act_w + act_gap), y = y, w = act_w, h = act_h,
        text = "停止", size = 13,
        fg = theme.SEM.danger, border = theme.SEM.danger, on_click = do_stop,
    })
    refresh_action_btns()
    y = y + act_h + gap
    -- ===== 测试日志（最新在上）+ 清空 =====
    local head_h = theme.dp(36)
    local clear_w = theme.dp(72)
    theme.label(main_container, {
        x = pad, y = y, w = card_w - clear_w - gap, h = head_h,
        text = "测试日志(最新在上)", px_size = theme.fs("caption"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })
    theme.ghost_button(main_container, {
        x = pad + card_w - clear_w, y = y, w = clear_w, h = head_h,
        text = "清空", size = 12, fg = theme.SEM.danger, border = theme.SEM.danger,
        on_click = function() clear_log() end,
    })
    y = y + head_h + gap

    local log_h = sh - y - pad
    local line_h = theme.fs("caption") + theme.dp(4)
    if log_h < line_h then log_h = line_h end
    local lines = math.floor(log_h / line_h)
    if lines < 1 then lines = 1 end

    theme.box(main_container, {
        x = pad, y = y, w = card_w, h = lines * line_h,
        color = theme.C.black, opa = 255,
        radius = theme.R.md, border = theme.C.stroke, border_w = 1,
    })

    log_w = card_w - theme.dp(16)
    log_labels = {}
    for i = 1, lines do
        log_labels[i] = theme.label(main_container, {
            x = pad + theme.dp(8), y = y + (i - 1) * line_h,
            w = log_w, h = line_h,
            text = "", px_size = theme.fs("caption"),
            color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
        })
    end
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    collect_audio()
    build_ui()
    sys.subscribe("AUDIO_TEST_STATE", on_test_state)
    sys.subscribe("AUDIO_ACTION_RESULT", on_action_result)
    sys.subscribe("OTHER_FUNC_STATUS", on_status)
    sys.subscribe("OTHER_FUNC_CHANGED", on_status)

    if not audio_id then
        set_state_text("本机型未配置音频")
        append_entry("本机型未配置音频（config.peripherals 无 type=audio 条目）")
        return
    end
    if not audio_cfg then
        set_state_text("未配置 hw.audio")
        append_entry("未配置 hw.audio，无法初始化音频")
        return
    end
    clear_log()
    append_entry(hw_summary() .. " | 录音时长 " .. tostring(seconds) .. " 秒")
    -- 进页面即上电初始化，省得每次录音前还要手动开一次开关
    sys.publish("OTHER_FUNC_SET", audio_id, true)
    sys.publish("OTHER_FUNC_GET")
end

local function on_destroy()
    sys.unsubscribe("AUDIO_TEST_STATE", on_test_state)
    sys.unsubscribe("AUDIO_ACTION_RESULT", on_action_result)
    sys.unsubscribe("OTHER_FUNC_STATUS", on_status)
    sys.unsubscribe("OTHER_FUNC_CHANGED", on_status)
    if main_container then main_container:destroy(); main_container = nil end
    state_label = nil
    dur_btns = {}
    act_btns = {}
    log_labels = {}
    entries = {}
    cur_state = "idle"
    audio_id = nil
    audio_cfg = nil
end

local function on_get_focus() end
local function on_lose_focus() end

-- 入口事件带的 id 只说明是从哪一行进来的，页面固定测 hw.audio 这一路音频
local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_AUDIO_TEST_WIN", open_handler)
