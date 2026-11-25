--[[
@module  settings_report_win
@summary 数据上报设置页（AirCloud 通用上报 · 开关 / 周期 / 状态 / 字段清单）
@version 1.0.0
@date    2026.09.21
@author  江访
@usage
订阅: OPEN_AIRCLOUD_WIN → 打开本页
发布: AIRCLOUD_SET_ENABLE(bool)  / AIRCLOUD_SET_CYCLE(number)
      AIRCLOUD_REPORT_NOW        / AIRCLOUD_GET_STATUS
订阅: AIRCLOUD_STATUS_RESP(table)  → 刷新界面
      AIRCLOUD_REPORT_RESULT(table) → 刷新"最近一次上报"
      AIRCLOUD_ENABLE_CHANGED(bool) → 同步开关显示

门控: features.aircloud（与 app_main 里 aircloud_app 的门控条件一致）
]]

local theme = require "ui_theme"

local window_id, main_container
local enable_switch, cycle_slider, cycle_label
local status_rows = {}

local CYCLE_MIN = 5
local CYCLE_MAX = 3600
local DEFAULT_CYCLE = 180
local cycle_value = DEFAULT_CYCLE

--[[秒数 → 人类可读（60 的倍数显示分钟）]]
local function fmt_cycle(sec)
    if not sec then return "--" end
    if sec >= 3600 and sec % 3600 == 0 then return string.format("%d 小时", sec / 3600) end
    if sec >= 60 and sec % 60 == 0 then return string.format("%d 分钟", sec / 60) end
    if sec >= 60 then return string.format("%d 分 %d 秒", math.floor(sec / 60), sec % 60) end
    return string.format("%d 秒", sec)
end

--[[时间戳 → HH:MM:SS，无 NTP 时退回系统秒数]]
local function fmt_time(ts)
    if not ts or ts == 0 then return "从未上报" end
    local ok, s = pcall(os.date, "%H:%M:%S", ts)
    if ok and s then return s end
    return tostring(ts)
end

local function set_cycle_label(seconds)
    cycle_value = seconds
    cycle_label:set_text("上报周期：" .. fmt_cycle(seconds))
end

local function on_enable_changed(on)
    if enable_switch then enable_switch:set_state(on) end
end

local function refresh_status(st)
    if type(st) ~= "table" or not main_container then return end
    if st.cycle then
        -- 云端可设置更长的周期。滑块停在端点，显示和提交仍保留实际值。
        cycle_slider:set_value(math.max(CYCLE_MIN, math.min(CYCLE_MAX, st.cycle)))
        set_cycle_label(st.cycle)
    end
    if st.enabled ~= nil then on_enable_changed(st.enabled) end

    for key, label in pairs(status_rows) do
        local value = st[key]
        if value ~= nil then
            if key == "connected" then
                value = value and "已连接" or "未连接"
            elseif key == "authenticated" then
                value = value and "已鉴权" or "未鉴权"
            elseif key == "last_time" then
                value = fmt_time(value)
            elseif key == "last_ok" then
                if value then
                    value = "成功"
                elseif st.last_err and st.last_err ~= "" then
                    value = st.last_err
                else
                    value = st.last_time == 0 and "--" or "失败"
                end
            end
            label:set_text(tostring(value))
        end
    end
end

local function on_report_result(res)
    if type(res) == "table" then
        refresh_status({ last_ok = res.success, last_err = res.err,
            last_time = res.time, last_count = res.count or 0 })
    end
end

local function query_status()
    sys.publish("AIRCLOUD_GET_STATUS")
end

local function build_ui()
    local ctx = theme.page({
        title = "数据上报", sub = "AirCloud 云端上报设置",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    local body = theme.box(ctx.base, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = ctx.h,
        color = theme.C.black, opa = 0, scrollable = true,
    })
    local w, pad = ctx.w, ctx.pad
    local wide = w >= theme.dp(720)
    local inner_w = w - 2 * pad
    local caption_px = math.max(theme.FONT_MIN, theme.fs("caption"))
    local line_h = caption_px + theme.dp(6)
    local content_y = pad + line_h + theme.dp(6)

    local function section_card(x, y, width, height, title)
        local card = theme.card(body, { x = x, y = y, w = width, h = height })
        theme.section(card, { x = pad, y = pad, w = width - 2 * pad, h = line_h,
            text = title, color = theme.C.t2 })
        return card
    end

    -- 周期和提交按钮放在同一卡片；滑块上下都给拨钮留出空间。
    local switch_w, switch_h = theme.dp(46), theme.dp(26)
    local label_y = content_y + switch_h + theme.dp(8)
    local action_y = label_y + line_h + theme.dp(6)
    local button_h, slider_h = theme.dp(40), theme.dp(24)
    local button_w = wide and theme.dp(196) or inner_w
    local button_x = w - pad - button_w
    local button_y = wide and action_y or action_y + button_h + theme.dp(6)
    local control_h = button_y + button_h + pad
    local control = section_card(0, 0, w, control_h, "上报控制")
    theme.label(control, {
        x = pad, y = content_y, w = inner_w - switch_w - pad, h = switch_h,
        text = "启用数据上报", size = theme.F.body,
    })
    enable_switch = theme.switch(control, {
        x = w - pad - switch_w, y = content_y, w = switch_w, h = switch_h,
        checked = true,
        on_change = function(handle)
            sys.publish("AIRCLOUD_SET_ENABLE", handle:get_state())
        end,
    })
    cycle_label = theme.label(control, { x = pad, y = label_y, w = inner_w, h = line_h,
        text = "上报周期：" .. fmt_cycle(cycle_value), px_size = caption_px, color = theme.C.t2 })
    cycle_slider = theme.slider(control, {
        x = pad, y = action_y + math.floor((button_h - slider_h) / 2),
        w = wide and (inner_w - button_w - pad) or inner_w, h = slider_h,
        min = CYCLE_MIN, max = CYCLE_MAX, value = cycle_value,
        track = theme.C.track, color = theme.SEM.info,
        on_change = function(slider) set_cycle_label(slider:get_value()) end,
    })
    theme.button(control, {
        x = button_x, y = button_y, w = button_w, h = button_h,
        text = "应用周期并立即上报",
        on_click = function()
            sys.publish("AIRCLOUD_SET_CYCLE", cycle_value)
            sys.publish("AIRCLOUD_REPORT_NOW")
        end,
    })

    local fields = {
        { key = "device_id",     label = "设备ID", initial = "读取中" },
        { key = "connected",     label = "连接状态" },
        { key = "authenticated", label = "云端鉴权" },
        { key = "last_ok",       label = "最近一次" },
        { key = "last_time",     label = "上报时间" },
        { key = "last_count",    label = "上报字段数" },
        { key = "boot_count",    label = "开机次数" },
    }
    local detail_y = control_h + pad
    local status_w = wide and math.floor((w - pad) / 2) or w
    local row_h = math.max(theme.dp(34), line_h + theme.dp(6))
    local status_h = content_y + #fields * row_h + pad
    local status = section_card(0, detail_y, status_w, status_h, "运行状态")
    local row_w = status_w - 2 * pad
    for i, field in ipairs(fields) do
        local _, label = theme.kv_row(status, {
            x = pad, y = content_y + (i - 1) * row_h, w = row_w, h = row_h, pad = 0,
            label = field.label, value = field.initial or "--", size = "body",
            label_w = theme.text_width(field.label, theme.fs("body")) + theme.dp(10),
            opa = 0, label_color = theme.C.t2, value_color = theme.C.t1,
        })
        status_rows[field.key] = label
    end

    -- 横屏两列都从控制卡下方开始；窄屏按顺序纵向滚动，标题栏固定。
    local list_x = wide and (status_w + pad) or 0
    local list_y = wide and detail_y or (detail_y + status_h + pad)
    local list_w = w - list_x
    local text_w = list_w - 2 * pad
    local field_names = {
        "- 设备ID / 固件版本",
        "- 4G 信号强度 / 网络类型 / SIM卡",
        "- CPU 温度（ADC）",
        "- 经纬度（LBS 基站定位）",
        "- 电池电量 / 电压",
        "- 开机原因 / 次数 / 内存占用",
        "- WiFi 信号强度",
    }
    local hint = "云端可下发 cycle:N 改周期 / backlight:N 调背光"
    local field_h = line_h + theme.dp(3)
    local hint_y = content_y + #field_names * field_h + theme.dp(4)
    local hint_h = line_h * theme.text_lines(hint, text_w, caption_px)
    local list = section_card(list_x, list_y, list_w, hint_y + hint_h + pad, "采集字段（有接口才上报）")
    for i, name in ipairs(field_names) do
        theme.label(list, { x = pad, y = content_y + (i - 1) * field_h, w = text_w, h = field_h,
            text = name, px_size = caption_px, color = theme.C.t2 })
    end
    theme.label(list, { x = pad, y = hint_y, w = text_w, h = hint_h,
        text = hint, px_size = caption_px, color = theme.C.t3 })
end

local function on_create()
    build_ui()
    sys.subscribe("AIRCLOUD_STATUS_RESP", refresh_status)
    sys.subscribe("AIRCLOUD_REPORT_RESULT", on_report_result)
    sys.subscribe("AIRCLOUD_ENABLE_CHANGED", on_enable_changed)
    query_status()
end

local function on_destroy()
    sys.unsubscribe("AIRCLOUD_STATUS_RESP", refresh_status)
    sys.unsubscribe("AIRCLOUD_REPORT_RESULT", on_report_result)
    sys.unsubscribe("AIRCLOUD_ENABLE_CHANGED", on_enable_changed)
    if main_container then main_container:destroy() end
    main_container, window_id = nil, nil
    enable_switch, cycle_slider, cycle_label = nil, nil, nil
    status_rows = {}
    cycle_value = DEFAULT_CYCLE
end

local function open_handler()
    local fe = (_G.project_config or {}).features or {}
    if not fe.aircloud then
        log.warn("settings_aircloud", "features.aircloud 未开启，忽略打开请求")
        return
    end
    if window_id then return end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = query_status,
    })
end

sys.subscribe("OPEN_AIRCLOUD_WIN", open_handler)
