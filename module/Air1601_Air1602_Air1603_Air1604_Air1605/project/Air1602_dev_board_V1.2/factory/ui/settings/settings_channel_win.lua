--[[
@module  settings_channel_win
@summary UART3 口复用配置页（4G / WiFi / GNSS / 蓝牙 四选一）
@version 1.0
@date    2026.10.26
@author  江访
@usage
订阅: OPEN_CHANNEL_WIN → 打开本页

页面结构：

  说明卡（UART3 共用关系 + 四选语义）
  四个单选行（点击即选中，选中行高亮）
  「保存配置」+「立即重启」两个按钮
  底部状态行（当前生效 / 已保存待重启）

=== 为什么必须重启 ===

4G 与 WiFi 都是开机建网卡（airlink.init + exnetdrv + exnetif 一次性初始化），
运行期重建会把在线的模组踢下线，所以本页只负责「存下来」，生效交给重启。
GNSS / 蓝牙不涉及网卡，重启后进对应测试页即可用。

=== 状态行的三种文案 ===

  已保存 == 开机时的值  → 「当前生效：4G」
  已保存 != 开机时的值  → 「已保存：WiFi，重启后生效（当前生效 4G）」

按钮点击直接调 settings_channel_app 的同步接口（set/get），不绕消息队列；
CHANNEL_* 消息仍保留给其它模块使用。
]]

local theme = require "ui_theme"
local channel = require "settings_channel_app"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800

local boot_mode = nil     -- 本次开机实际生效的模式（进页面时定格，保存后不跟着变）
local saved_mode = nil    -- fskv 里当前保存的值
local pending_mode = nil  -- 界面上选中的值

local status_label = nil
local build_ui = nil

-- ==================== 基础 ====================

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
end

local function set_status(text, color)
    if status_label and not status_label:is_destroyed() then
        status_label:set_text(text)
        if color then status_label:set_color(color) end
    end
end

--[[状态行文案：区分「已生效」与「已保存待重启」]]
local function status_text()
    if saved_mode and boot_mode and saved_mode ~= boot_mode then
        return true, string.format("已保存：%s，重启后生效（当前生效 %s）",
            channel.label(saved_mode), channel.label(boot_mode))
    end
    return false, "当前生效：" .. channel.label(boot_mode)
end

local function rebuild()
    if main_container then main_container:destroy(); main_container = nil end
    status_label = nil
    if build_ui then build_ui() end
end

-- ==================== 动作 ====================

local function do_select(mode)
    if pending_mode == mode then return end
    pending_mode = mode
    rebuild()
end

local function do_save()
    if pending_mode == saved_mode then
        set_status("与已保存配置一致，无需保存", theme.C.t2)
        return
    end
    local ok, err = channel.set(pending_mode)
    if ok then
        saved_mode = pending_mode
        rebuild()   -- 状态行在 build_ui 里按 saved/boot 的差异自动给出
    else
        set_status("保存失败：" .. tostring(err), theme.SEM.danger)
    end
end

local function do_reboot()
    log.info("settings_channel", "用户点击立即重启")
    pcall(rtos.reboot)
end

-- ==================== 界面 ====================

build_ui = function()
    update_screen_size()

    local ctx = theme.page({
        title = "UART3 口复用",
        sub = "4G / WiFi / GNSS / 蓝牙 四选一",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    local pad = ctx.pad
    local w = ctx.w
    local y = ctx.y

    local inner_pad = theme.dp(12)
    local fs_note = theme.fs("micro")

    -- ---------- 说明卡 ----------
    local notes = {
        "UART3 为 4G / WiFi / GNSS / 蓝牙 共用的串口",
        "同一时刻只能有一路占用，保存后需重启生效",
        "WiFi(6205) 支持 UART3 / SPI2 双接法：选 WiFi 走 UART3，选 GNSS / 蓝牙 自动改走 SPI2",
        "选 4G 时 WiFi 关闭（4G 与 6205 同为 airlink 从机，只能跑一路）",
    }
    local note_lh = fs_note + theme.dp(4)
    local note_h = theme.dp(10) * 2 + note_lh * #notes + theme.dp(2)
    local note_card = theme.card(main_container, { x = ctx.x, y = y, w = w, h = note_h })
    for i, line in ipairs(notes) do
        theme.label(note_card, {
            x = inner_pad, y = theme.dp(10) + (i - 1) * note_lh,
            w = w - 2 * inner_pad - 2, h = note_lh,
            text = line, px_size = fs_note, color = theme.C.t3,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end
    y = y + note_h + pad

    -- ---------- 底部固定区（按钮 + 状态行）----------
    local btn_h = theme.dp(40)
    local fs_btn = 13
    local status_h = fs_note + theme.dp(6)
    local bottom_h = btn_h + theme.dp(8) + status_h
    local bottom_y = ctx.y + ctx.h - bottom_h

    -- ---------- 四个通道行 ----------
    local gap = theme.dp(8)
    local list_bottom = bottom_y - pad
    local avail = list_bottom - y
    local row_h = math.floor((avail - gap * (#channel.MODES - 1)) / #channel.MODES)
    row_h = math.max(theme.dp(48), math.min(theme.dp(64), row_h))

    for _, m in ipairs(channel.MODES) do
        local on = (pending_mode == m)
        local right = nil
        if m == boot_mode then
            right = "生效中"
        elseif on then
            right = "已选"
        end
        theme.row(main_container, {
            x = ctx.x, y = y, w = w, h = row_h,
            text = channel.label(m), sub = channel.DESC[m],
            right = right, right_w = theme.dp(56),
            px_size = theme.fs("body"), sub_px = fs_note, right_px = fs_note,
            bg = on and theme.C.amber or theme.C.surface,
            opa = on and 48 or theme.OPA.glass,
            border = on and theme.C.amber or theme.C.stroke,
            text_color = on and theme.C.amber_light or theme.C.t1,
            right_color = (m == boot_mode) and theme.SEM.success or theme.C.t3,
            on_click = function() do_select(m) end,
        })
        y = y + row_h + gap
    end

    -- ---------- 按钮 ----------
    local rb_w = theme.dp(120)
    local save_w = w - rb_w - theme.dp(10)

    theme.button(main_container, {
        x = ctx.x, y = bottom_y, w = save_w, h = btn_h,
        text = "保存配置", size = fs_btn,
        on_click = function() do_save() end,
    })
    theme.ghost_button(main_container, {
        x = ctx.x + save_w + theme.dp(10), y = bottom_y, w = rb_w, h = btn_h,
        text = "立即重启", size = fs_btn,
        fg = theme.C.amber, border = theme.C.amber,
        on_click = function() do_reboot() end,
    })

    -- ---------- 状态行 ----------
    local pending_reboot, text = status_text()
    status_label = theme.label(main_container, {
        x = ctx.x, y = bottom_y + btn_h + theme.dp(8),
        w = w, h = status_h,
        text = text, px_size = fs_note,
        color = pending_reboot and theme.C.amber_light or theme.C.t2,
        align = airui.TEXT_ALIGN_LEFT,
    })
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    saved_mode = channel.get()
    boot_mode = saved_mode
    pending_mode = saved_mode
    build_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    status_label = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_CHANNEL_WIN", open_handler)
