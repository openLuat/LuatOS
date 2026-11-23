--[[
@module  net_settings_win
@summary 网络设置页：列出 config.network 的全部网络，支持开关切换与互斥确认
@version 1.0
@date    2026.10.29
@author  江访

消息协议（订阅/发布）:
订阅: OPEN_NET_WIN             → 打开网络设置页
订阅: NET_STATUS_CHANGED      → 刷新状态文案与开关
发布: OPEN_NET_DETAIL_WIN(id) → 打开网络详情页
]]

require "net_detail_win"
local theme = require "ui_theme"
local net_manager = require "net_manager"

local CLR = theme.live()

-- 状态码到界面文案
local STATUS_TEXT = {
    OFF            = "已关闭",
    CONNECTED      = "已连接",
    CONNECTING     = "连接中",
    DISCONNECTED   = "未连接",
    PENDING_REBOOT = "待重启生效",
}

-- 网络分组到图标底色
local GROUP_TINT = {
    eth  = 0x4C8DFF,
    wifi = 0x22C7A9,
    ["4g"] = 0xA78BFA,
}

local window_id = nil
local main_container = nil
local list_box = nil
local hint_box = nil
local list_w = 460
local page_w, page_h = 480, 800
local rows = {}
local names = {}
local pending = nil

--[[状态码换算成界面文案]]
local function status_text_of(status)
    return STATUS_TEXT[status] or STATUS_TEXT.DISCONNECTED
end

--[[状态码换算成文字颜色]]
local function status_color_of(status)
    if status == "CONNECTED" then return theme.SEM.success end
    if status == "PENDING_REBOOT" then return theme.C.amber end
    if status == "OFF" then return CLR.t3 end
    return CLR.t2
end

--[[按网络 id 查显示名]]
local function name_of(id)
    return names[id] or tostring(id or "")
end

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

--[[状态角标：优先级 N / 已关闭 / 需重启]]
local function build_state_chip(parent, x, y, item, index)
    local text
    if item.status == "OFF" then
        text = "已关闭"
    elseif item.status == "PENDING_REBOOT" then
        text = "需重启"
    else
        text = "优先级 " .. tostring(index)
    end
    local color, tcolor
    if item.status == "PENDING_REBOOT" then
        color, tcolor = theme.C.amber, theme.C.amber_light
    elseif item.status == "OFF" then
        color, tcolor = theme.C.surface, CLR.t3
    else
        color, tcolor = theme.C.surface, CLR.t2
    end
    return theme.chip(parent, {
        x = x, y = y, w = theme.dp(110), h = theme.dp(24),
        color = color, opa = theme.OPA.fill,
        text = text, text_color = tcolor,
    })
end

--[[无可用网络提示条显隐]]
local function update_hint()
    if not hint_box then return end
    if net_manager.has_active_network() then
        hint_box:hide()
    else
        hint_box:open()
    end
end

--[[只刷新状态文案、状态角标与开关，不重建页面]]
local function refresh_status()
    if not main_container then return end
    for _, item in ipairs(net_manager.list_networks()) do
        local row = rows[item.id]
        if row then
            row.item = item
            if row.status_label then
                row.status_label:set_text(status_text_of(item.status))
                row.status_label:set_color(status_color_of(item.status))
            end
            if row.chip then
                row.chip:destroy()
                row.chip = build_state_chip(row.card, row.chip_x, row.chip_y, item, row.index)
            end
            if row.sw and not row.pending then
                revert_switch(row.sw, item.enabled)
            end
        end
    end
    update_hint()
end

--[[互斥确认弹窗按钮回调]]
local function on_mutex_action(dlg, btn_label)
    if dlg then dlg:destroy() end
    local p = pending
    pending = nil
    if not p then return end
    if p.row then p.row.pending = nil end
    if btn_label == "确定并重启" then
        net_manager.set_net_enabled(p.id, true)
        if p.sw then p.sw:set_state(true) end
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
    if btn_label == "立即重启" then do_reboot() end
end

--[[互斥确认弹窗：写明关什么、开什么、要重启]]
local function show_mutex_prompt(preview, item)
    local list = {}
    for _, other in ipairs(preview.will_disable or {}) do
        list[#list + 1] = name_of(other)
    end
    if #list == 0 then list[1] = "其他 airlink 网络" end
    local mw, mh = msgbox_size()
    airui.msgbox({
        parent = main_container,
        w = mw, h = mh,
        title = "切换网络需要重启",
        text = string.format("打开%s将关闭%s，需要重启设备切换，是否继续？",
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
        title = "开关需重启生效",
        text = string.format("%s开关需重启设备后生效，是否立即重启？", item.name or ""),
        buttons = { "稍后重启", "立即重启" },
        on_action = on_switch_action,
    })
end

--[[开关点击处理：先预演，再按互斥等级走弹窗或在线生效]]
local function on_switch_change(handle, row)
    local item = row.item
    local enable = handle:get_state()
    local prev = item.enabled
    local preview = net_manager.preview_toggle(item.id, enable)
    if not preview.ok then
        revert_switch(handle, prev)
        return
    end
    if preview.reason == "airlink_mutex" then
        pending = { id = item.id, enable = enable, prev = prev, sw = handle, row = row }
        row.pending = true
        show_mutex_prompt(preview, item)
        return
    end
    if preview.reason == "airlink_switch" then
        net_manager.set_net_enabled(item.id, enable)
        item.enabled = enable
        pending = { id = item.id, enable = enable, prev = prev, sw = handle, row = row }
        row.pending = true
        show_switch_prompt(item)
        return
    end
    net_manager.set_net_enabled(item.id, enable)
    item.enabled = enable
end

--[[单张网络卡片]]
local function build_row(item, index)
    local card_h = theme.dp(84)
    local pad_in = theme.dp(12)
    local row = { id = item.id, item = item, index = index }
    rows[item.id] = row

    local card = theme.card(list_box, {
        x = 0, y = (index - 1) * (card_h + theme.dp(10)), w = list_w, h = card_h,
        on_click = function() sys.publish("OPEN_NET_DETAIL_WIN", item.id) end,
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
        tint = GROUP_TINT[item.group] or theme.C.primary,
        icon = icon_ok and item.icon or nil,
    })

    local sw_w, sw_h = theme.dp(52), theme.dp(30)
    local sw_x = list_w - pad_in - sw_w
    local status_w = theme.dp(104)
    local status_x = sw_x - theme.dp(8) - status_w
    local tx = pad_in + icon_size + theme.dp(12)
    local tw = status_x - tx - theme.dp(10)
    if tw < theme.dp(60) then tw = theme.dp(60) end

    local fs_name = theme.fs("body")
    local fs_sub = theme.fs("label")
    theme.label(card, {
        x = tx, y = theme.dp(6), w = tw, h = fs_name + 8,
        text = theme.fit_text(item.name or "", tw, fs_name), px_size = fs_name,
        color = CLR.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    theme.label(card, {
        x = tx, y = theme.dp(6) + fs_name + 8, w = tw, h = fs_sub + 8,
        text = theme.fit_text(item.detail or "", tw, fs_sub), px_size = fs_sub,
        color = CLR.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    row.status_label = theme.label(card, {
        x = status_x, y = theme.dp(6), w = status_w, h = fs_sub + 8,
        text = status_text_of(item.status), px_size = fs_sub,
        color = status_color_of(item.status), align = airui.TEXT_ALIGN_RIGHT,
    })

    row.chip_x = tx
    row.chip_y = card_h - theme.dp(28)
    row.chip = build_state_chip(card, row.chip_x, row.chip_y, item, index)

    row.sw = theme.switch({
        parent = card,
        x = sw_x, y = math.floor((card_h - sw_h) / 2),
        w = sw_w, h = sw_h,
        checked = item.enabled and true or false,
        color = theme.C.primary,
        on_change = function(handle) on_switch_change(handle, row) end,
    })
end

--[[重建网络卡片列表]]
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
            text = "该机型未配置网络", px_size = theme.fs("label"),
            color = CLR.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end
    for i, item in ipairs(list) do
        names[item.id] = item.name
        build_row(item, i)
    end
end

local function build_ui()
    local list = net_manager.list_networks()
    local ctx = theme.page({
        title = "网络设置",
        sub = "按优先级排序 | 点击网络进详情",
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

    hint_box = theme.card(main_container, {
        x = ctx.x, y = ctx.y + list_h + gap, w = ctx.w, h = hint_h,
        color = theme.C.amber, opa = theme.OPA.fill,
        border = theme.C.amber, border_w = 1,
    })
    theme.label(hint_box, {
        x = theme.dp(12), y = theme.dp(8), w = ctx.w - theme.dp(24), h = hint_h - theme.dp(16),
        text = "当前未启用任何网络，云端上报、时间同步等联网功能将不可用",
        px_size = theme.fs("label"), color = CLR.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    update_hint()
    rebuild_list(list)
end

local function on_net_status_changed()
    refresh_status()
end

local function on_create()
    build_ui()
    sys.subscribe("NET_STATUS_CHANGED", on_net_status_changed)
end

local function on_destroy()
    sys.unsubscribe("NET_STATUS_CHANGED", on_net_status_changed)
    pending = nil
    if main_container then main_container:destroy(); main_container = nil end
    list_box = nil
    hint_box = nil
    rows = {}
    names = {}
    window_id = nil
end

local function on_get_focus()
    refresh_status()
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

sys.subscribe("OPEN_NET_WIN", open)
