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
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container = nil
local enable_switch = nil
local cycle_slider = nil
local cycle_label = nil
local status_rows = {}
local apply_btn = nil

local sw, sh = 480, 800
local pad = 15

local CYCLE_MIN = 5
local CYCLE_MAX = 3600
local cycle_value = 180        -- 滑块当前值（秒）

--[[设置页切碎周期时，滑块拖动过程可能产生大量中间值；
--   这里只在松手（on_change 只在值真变时触发，LVGL 拖拽会连续触发）
--   后由用户点「应用」才下发，避免频繁重启上报定时器。]]

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

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

--[[刷新状态行（由 AIRCLOUD_STATUS_RESP / AIRCLOUD_REPORT_RESULT 驱动）]]
local function refresh_status(st)
    if not st then return end
    if st.cycle and cycle_slider then
        cycle_value = st.cycle
        -- 滑块只覆盖 5~3600，超出范围时钳到端点，避免 set_value 越界
        local v = st.cycle
        if v < CYCLE_MIN then v = CYCLE_MIN end
        if v > CYCLE_MAX then v = CYCLE_MAX end
        cycle_slider:set_value(v)
        if cycle_label then
            cycle_label:set_text("上报周期：" .. fmt_cycle(st.cycle))
        end
    end
    if enable_switch and st.enabled ~= nil then
        enable_switch:set_state(st.enabled and true or false)
    end
    for key, row in pairs(status_rows) do
        local val = st[key]
        if val ~= nil and row.set_value then
            if key == "last_ok" then
                row:set_value(val and "成功" or "失败")
            elseif key == "last_time" then
                row:set_value(fmt_time(val))
            elseif key == "connected" then
                row:set_value(val and "已连接" or "未连接")
            else
                row:set_value(tostring(val))
            end
        end
    end
end

local function query_status()
    sys.publish("AIRCLOUD_GET_STATUS")
end

-- ==================== UI 构建 ====================

local function build_ui()
    update_screen_size()

    main_container = theme.page_bg(airui.screen, sw, sh)

    local _, th = titlebar.create(main_container, "数据上报", sw,
        function() exwin.close(window_id) end, "AirCloud 云端上报设置")

    local y = pad + th + pad
    local card_w = sw - 2 * pad

    -- ---------- 卡片1：上报开关 + 周期 ----------
    local card1_h = theme.dp(120)
    local card1 = theme.card(main_container, { x = pad, y = y, w = card_w, h = card1_h })

    theme.section(card1, { x = pad, y = theme.dp(10), w = card_w - 2 * pad,
        text = "上报控制", px_size = theme.fs("micro"), color = theme.C.t3 })

    -- 开关行
    local row_y = theme.dp(34)
    local row_h = theme.dp(40)
    local sw_handle = theme.switch(card1, {
        x = card_w - pad - theme.dp(52),
        y = row_y + math.floor((row_h - theme.dp(26)) / 2),
        checked = true,
        on_change = function(handle)
            local on = handle:get_state()
            sys.publish("AIRCLOUD_SET_ENABLE", on)
        end,
    })
    enable_switch = sw_handle

    theme.label(card1, {
        x = pad, y = row_y, w = card_w - 2 * pad - theme.dp(60), h = row_h,
        text = "启用数据上报", size = theme.F.body, color = theme.C.t1,
    })

    -- 周期标签
    local label_y = row_y + row_h + theme.dp(6)
    cycle_label = theme.label(card1, {
        x = pad, y = label_y, w = card_w - 2 * pad, h = theme.dp(22),
        text = "上报周期：" .. fmt_cycle(cycle_value),
        size = theme.F.caption, color = theme.C.t2,
    })

    -- 周期滑块（拖动只改本地显示，点下方「应用」才真正下发，避免频繁重启定时器）
    local sl_h = math.max(theme.dp(28), 28)
    cycle_slider = theme.slider(card1, {
        x = pad, y = label_y + theme.dp(24), w = card_w - 2 * pad, h = sl_h,
        min = CYCLE_MIN, max = CYCLE_MAX, value = cycle_value,
        track = theme.C.track, color = theme.SEM.info, knob_color = theme.C.knob,
        on_change = function(self)
            local v = self:get_value()
            cycle_value = v
            if cycle_label then
                cycle_label:set_text("上报周期：" .. fmt_cycle(v))
            end
        end,
    })

    y = y + card1_h + pad

    -- ---------- 卡片2：状态 ----------
    local cfg_ac = (_G.project_config or {}).aircloud or {}
    local fields = {
        { key = "connected",     label = "连接状态" },
        { key = "authenticated", label = "云端鉴权" },
        { key = "last_ok",       label = "最近一次" },
        { key = "last_time",     label = "上报时间" },
        { key = "last_count",    label = "上报字段数" },
        { key = "boot_count",    label = "开机次数" },
    }
    -- authenticated 用 已鉴权/未鉴权 文案
    local CARD2_ROWS = #fields + 1     -- +1 为设备ID
    local row_h2 = theme.dp(38)
    local card2_h = theme.dp(10) + theme.dp(24) + CARD2_ROWS * row_h2 + theme.dp(10)
    local card2 = theme.card(main_container, { x = pad, y = y, w = card_w, h = card2_h })

    theme.section(card2, { x = pad, y = theme.dp(10), w = card_w - 2 * pad,
        text = "运行状态", px_size = theme.fs("micro"), color = theme.C.t3 })

    local ry = theme.dp(10) + theme.dp(24)
    local function add_kv(label, key, value)
        local row, value_label = theme.kv_row(card2, {
            x = pad, y = ry, w = card_w - 2 * pad, h = row_h2,
            label = label, value = value or "--",
            size = theme.F.caption, label_w = math.floor(card_w * 0.42),
            label_color = theme.C.t2, value_color = theme.C.t1,
        })
        ry = ry + row_h2
        if key then status_rows[key] = value_label end
    end

    add_kv("设备ID", "device_id", "读取中")
    for _, f in ipairs(fields) do
        add_kv(f.label, f.key, "--")
    end

    y = y + card2_h + pad

    -- ---------- 卡片3：字段清单 + 操作按钮 ----------
    local card3_rows = 7
    local card3_h = theme.dp(10) + theme.dp(24) + card3_rows * theme.dp(26) + theme.dp(56)
    if y + card3_h > sh - pad then
        card3_h = math.max(theme.dp(120), sh - pad - y)
    end
    local card3 = theme.card(main_container, { x = pad, y = y, w = card_w, h = card3_h })

    theme.section(card3, { x = pad, y = theme.dp(10), w = card_w - 2 * pad,
        text = "采集字段（有接口才上报）", px_size = theme.fs("micro"), color = theme.C.t3 })

    local field_names = {
        "· 设备ID / 固件版本",
        "· 4G 信号强度 / 网络类型 / SIM卡",
        "· CPU 温度（ADC）",
        "· 经纬度（LBS 基站定位）",
        "· 电池电量 / 电压",
        "· 开机原因 / 次数 / 内存占用",
        "· WiFi 信号强度",
    }
    local fy = theme.dp(10) + theme.dp(24)
    for _, name in ipairs(field_names) do
        theme.label(card3, {
            x = pad, y = fy, w = card_w - 2 * pad, h = theme.dp(26),
            text = name, size = theme.F.caption, color = theme.C.t2,
        })
        fy = fy + theme.dp(26)
    end

    theme.label(card3, {
        x = pad, y = fy + theme.dp(2), w = card_w - 2 * pad, h = theme.dp(18),
        text = string.format("云端可下发 cycle:N 改周期 / backlight:N 调背光"),
        size = theme.fs("micro"), color = theme.C.t3,
    })

    apply_btn = theme.button(card3, {
        x = pad, y = card3_h - theme.dp(44), w = card_w - 2 * pad, h = theme.dp(34),
        text = "应用周期并立即上报",
        on_click = function()
            sys.publish("AIRCLOUD_SET_CYCLE", cycle_value)
            sys.publish("AIRCLOUD_REPORT_NOW")
            -- 结果稍后由 AIRCLOUD_REPORT_RESULT 回填
        end,
    })
end

-- ==================== 生命周期 ====================

local function on_create()
    build_ui()
    query_status()
    sys.subscribe("AIRCLOUD_STATUS_RESP", refresh_status)

    -- 上报结果回来时只更新"最近一次"两行，不整页重建
    sys.subscribe("AIRCLOUD_REPORT_RESULT", function(res)
        if type(res) ~= "table" then return end
        local ok_row = status_rows.last_ok
        local t_row  = status_rows.last_time
        local c_row  = status_rows.last_count
        if ok_row and ok_row.set_value then
            ok_row:set_value(res.success and "成功" or (res.err ~= "" and res.err or "失败"))
        end
        if t_row and t_row.set_value then t_row:set_value(fmt_time(res.time)) end
        if c_row and c_row.set_value then c_row:set_value(tostring(res.count or 0)) end
    end)

    sys.subscribe("AIRCLOUD_ENABLE_CHANGED", function(on)
        if enable_switch then enable_switch:set_state(on and true or false) end
    end)
end

local function on_destroy()
    sys.unsubscribe("AIRCLOUD_STATUS_RESP")
    sys.unsubscribe("AIRCLOUD_REPORT_RESULT")
    sys.unsubscribe("AIRCLOUD_ENABLE_CHANGED")
    enable_switch, cycle_slider, cycle_label, apply_btn = nil, nil, nil, nil
    status_rows = {}
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function on_get_focus()
    query_status()
end

local function open_handler()
    -- 与 app_main 里 aircloud_app 的门控条件保持一致
    local fe = (_G.project_config or {}).features or {}
    if not fe.aircloud then
        log.warn("settings_aircloud", "features.aircloud 未开启，忽略打开请求")
        return
    end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_AIRCLOUD_WIN", open_handler)
