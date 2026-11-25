--[[
@module  settings_usb_win
@summary 外设模式页：UVC 摄像头与 USB 键鼠二选一（互斥，切换后重启生效）
@version 1.0
@date    2026.11.03
@author  江访

消息协议（订阅/发布）:
订阅: OPEN_USB_MODE_WIN   → 打开外设模式页
订阅: USB_MODE_CHANGED    → 模式写入后刷新开关与角标
]]

local theme = require "ui_theme"
local usb_mode = require "usb_mode"

local CLR = theme.live()

local window_id = nil
local main_container = nil
local list_box = nil
local list_w = 460
local page_w, page_h = 480, 800
local rows = {}
local names = {}
local pending = nil

--[[把开关拨回指定状态]]
local function revert_switch(handle, value)
    if handle then handle:set_state(value and true or false) end
end

--[[延时重启，给弹窗销毁留出时间]]
local function do_reboot()
    sys.timerStart(rtos.reboot, 500)
end

--[[弹窗尺寸]]
local function msgbox_size()
    local w = math.floor(page_w * 0.86)
    local h = math.floor(page_h * 0.34)
    local min_h = theme.dp(150)
    if h < min_h then h = min_h end
    return w, h
end

--[[返回按钮回调]]
local function on_back()
    exwin.close(window_id)
end

--[[模式角标：使用中 / 未启用]]
local function build_state_chip(parent, x, y, item)
    local color, tcolor
    if item.enabled then
        color, tcolor = theme.C.surface, theme.SEM.success
    else
        color, tcolor = theme.C.surface, CLR.t3
    end
    return theme.chip(parent, {
        x = x, y = y, w = theme.dp(104), h = theme.dp(24),
        color = color, opa = theme.OPA.fill,
        text = item.enabled and "使用中" or "未启用",
        text_color = tcolor,
    })
end

--[[只刷新开关与角标，不重建页面]]
local function refresh_rows()
    if not main_container then return end
    for _, item in ipairs(usb_mode.list(_G.project_config or {})) do
        local row = rows[item.id]
        if row then
            row.item = item
            if row.chip then
                row.chip:destroy()
                row.chip = build_state_chip(row.card, row.chip_x, row.chip_y, item)
            end
            if row.sw and not row.pending then
                revert_switch(row.sw, item.enabled)
            end
        end
    end
end

--[[互斥确认弹窗按钮回调]]
local function on_mutex_action(dlg, btn_label)
    if dlg then dlg:destroy() end
    local p = pending
    pending = nil
    if not p then return end
    if p.row then p.row.pending = nil end
    if btn_label == "确定并重启" then
        usb_mode.set_enabled(p.id, true)
        if p.sw then p.sw:set_state(true) end
        refresh_rows()
        do_reboot()
    else
        revert_switch(p.sw, p.prev)
    end
end

--[[重启确认弹窗按钮回调]]
local function on_switch_action(dlg, btn_label)
    if dlg then dlg:destroy() end
    local p = pending
    pending = nil
    if not p then return end
    if p.row then p.row.pending = nil end
    if btn_label == "立即重启" then do_reboot() else refresh_rows() end
end

--[[保留一项提示弹窗按钮回调]]
local function on_last_action(dlg)
    if dlg then dlg:destroy() end
end

--[[互斥确认弹窗：写明开什么、关什么、要重启]]
local function show_mutex_prompt(preview, item)
    local list = {}
    for _, other in ipairs(preview.will_disable or {}) do
        list[#list + 1] = names[other] or tostring(other or "")
    end
    if #list == 0 then list[1] = "另一项外设" end
    local mw, mh = msgbox_size()
    airui.msgbox({
        parent = main_container,
        w = mw, h = mh,
        title = "切换外设模式需要重启",
        text = string.format("打开%s将关闭%s，两者共用 USB Host，需要重启设备切换，是否继续？",
            item.name or "", table.concat(list, "、")),
        buttons = { "取消", "确定并重启" },
        on_action = on_mutex_action,
    })
end

--[[重启确认弹窗：开关已写入，只问要不要立刻重启]]
local function show_switch_prompt(item)
    local mw, mh = msgbox_size()
    airui.msgbox({
        parent = main_container,
        w = mw, h = mh,
        title = "模式需重启生效",
        text = string.format("%s模式需重启设备后生效，是否立即重启？", item.name or ""),
        buttons = { "稍后重启", "立即重启" },
        on_action = on_switch_action,
    })
end

--[[保留一项提示：USB 摄像头与 USB 键鼠至少开一个]]
local function show_last_one_prompt()
    local mw, mh = msgbox_size()
    airui.msgbox({
        parent = main_container,
        w = mw, h = mh,
        title = "提示",
        text = "UVC 摄像头与 USB 键鼠两者互斥，但至少保留一项开启",
        buttons = { "确定" },
        on_action = on_last_action,
    })
end

--[[开关点击处理：先预演，再按互斥等级走弹窗或在线生效]]
local function on_switch_change(handle, row)
    local item = row.item
    local enable = handle:get_state()
    local prev = item.enabled
    local preview = usb_mode.preview_toggle(item.id, enable)
    if not preview.ok then
        revert_switch(handle, prev)
        if preview.reason == "last_one" then show_last_one_prompt() end
        return
    end
    if not preview.need_reboot then
        revert_switch(handle, prev)
        return
    end
    if preview.reason == "usb_mutex" then
        pending = { id = item.id, enable = enable, prev = prev, sw = handle, row = row }
        row.pending = true
        show_mutex_prompt(preview, item)
        return
    end
    usb_mode.set_enabled(item.id, enable)
    item.enabled = enable
    pending = { id = item.id, enable = enable, prev = prev, sw = handle, row = row }
    row.pending = true
    show_switch_prompt(item)
end

--[[单张外设模式卡片]]
local function build_row(item, index)
    local card_h = theme.dp(92)
    local pad_in = theme.dp(12)
    local row = { id = item.id, item = item, index = index }
    rows[item.id] = row
    names[item.id] = item.name

    local card = theme.card(list_box, {
        x = 0, y = (index - 1) * (card_h + theme.dp(10)), w = list_w, h = card_h,
    })
    row.card = card

    local icon_size = theme.dp(40)
    local icon_ok = false
    if item.icon and item.icon ~= "" then
        local _, ok = theme.icon(item.icon)
        icon_ok = (ok == true)
    end
    theme.iconbox(card, {
        x = pad_in, y = math.floor((card_h - icon_size) / 2),
        size = icon_size, radius = theme.R.sm,
        tint = item.enabled and theme.C.primary or theme.C.stroke,
        icon = icon_ok and item.icon or nil,
    })

    local sw_w, sw_h = theme.dp(52), theme.dp(30)
    local sw_x = list_w - pad_in - sw_w
    local chip_w = theme.dp(104)
    local chip_x = sw_x - theme.dp(8) - chip_w
    local tx = pad_in + icon_size + theme.dp(12)
    local tw = chip_x - tx - theme.dp(10)
    if tw < theme.dp(60) then tw = theme.dp(60) end

    local fs_name = theme.fs("body")
    local fs_sub = theme.fs("label")
    theme.label(card, {
        x = tx, y = theme.dp(10), w = tw, h = fs_name + 8,
        text = theme.fit_text(item.name or "", tw, fs_name), px_size = fs_name,
        color = CLR.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    theme.label(card, {
        x = tx, y = theme.dp(10) + fs_name + 8, w = tw, h = fs_sub + 8,
        text = theme.fit_text(item.detail or "", tw, fs_sub), px_size = fs_sub,
        color = CLR.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    row.chip_x = chip_x
    row.chip_y = math.floor((card_h - theme.dp(24)) / 2)
    row.chip = build_state_chip(card, row.chip_x, row.chip_y, item)

    row.sw = theme.switch({
        parent = card,
        x = sw_x, y = math.floor((card_h - sw_h) / 2),
        w = sw_w, h = sw_h,
        checked = item.enabled and true or false,
        color = theme.C.primary,
        on_change = function(handle) on_switch_change(handle, row) end,
    })
end

--[[重建外设模式卡片列表]]
local function rebuild_list(list)
    for _, row in pairs(rows) do
        if row.card then row.card:destroy() end
    end
    rows = {}
    names = {}
    if not list_box then return end
    if not list or #list == 0 then
        theme.label(list_box, {
            x = 0, y = theme.dp(12), w = list_w, h = theme.fs("label") + 8,
            text = "该机型未配置 UVC 摄像头与 USB 键鼠", px_size = theme.fs("label"),
            color = CLR.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end
    for i, item in ipairs(list) do
        build_row(item, i)
    end
end

local function build_ui()
    local list = usb_mode.list(_G.project_config or {})
    local ctx = theme.page({
        title = "外设模式",
        sub = "UVC 摄像头与 USB 键鼠二选一 | 切换后重启生效",
        on_back = on_back,
    })
    main_container = ctx.base
    page_w, page_h = ctx.sw, ctx.sh

    local hint_h = theme.dp(62)
    local gap = theme.dp(10)
    local list_h = ctx.h - hint_h - gap
    if list_h < theme.dp(80) then list_h = theme.dp(80) end

    list_w = ctx.w
    list_box = theme.box(main_container, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = list_h,
        color = theme.C.black, opa = 0, scrollable = true,
    })

    local hint_box = theme.card(main_container, {
        x = ctx.x, y = ctx.y + list_h + gap, w = ctx.w, h = hint_h,
        color = theme.C.amber, opa = theme.OPA.fill,
        border = theme.C.amber, border_w = 1,
    })
    theme.label(hint_box, {
        x = theme.dp(12), y = theme.dp(8), w = ctx.w - theme.dp(24), h = hint_h - theme.dp(16),
        text = "两者共用同一个 USB Host 与供电轨，同一时刻只能使用一项",
        px_size = theme.fs("label"), color = CLR.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    rebuild_list(list)
end

local function on_usb_mode_changed()
    refresh_rows()
end

local function on_create()
    build_ui()
    sys.subscribe("USB_MODE_CHANGED", on_usb_mode_changed)
end

local function on_destroy()
    sys.unsubscribe("USB_MODE_CHANGED", on_usb_mode_changed)
    pending = nil
    if main_container then main_container:destroy(); main_container = nil end
    list_box = nil
    rows = {}
    names = {}
    window_id = nil
end

local function on_get_focus()
    refresh_rows()
end

local function on_lose_focus() end

local function open()
    if not exwin.is_active(window_id) then
        window_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end

sys.subscribe("OPEN_USB_MODE_WIN", open)
