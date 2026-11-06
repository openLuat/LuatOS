--[[
@module  net_detail_win
@summary 网络详情页：单个网络的类型、状态与开关，WiFi 组可跳转连接管理
@version 1.0
@date    2026.10.29
@author  江访

消息协议（订阅/发布）:
订阅: OPEN_NET_DETAIL_WIN(id)  → 打开网络详情页，id 为网络类型名
订阅: NET_STATUS_CHANGED      → 刷新状态文案与开关
发布: OPEN_WIFI_WIN           → 打开 WiFi 连接管理
]]

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

local window_id = nil
local main_container = nil
local page_w, page_h = 480, 800
local cur_id = nil
local cur_item = nil
local names = {}
local sw_handle = nil
local status_value = nil
local wifi_btn = nil
local wifi_hint = nil
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

--[[按 id 取网络信息]]
local function find_net(id)
    for _, item in ipairs(net_manager.list_networks()) do
        if item.id == id then return item end
    end
    return nil
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

--[[返回按钮回调：出栈回到网络设置页]]
local function on_back()
    exwin.close(window_id)
end

--[[提示弹窗按钮回调]]
local function on_prompt_dismiss(dlg)
    if dlg then dlg:destroy() end
end

--[[WiFi 连接管理按钮回调：网络已关闭时只弹提示]]
local function on_wifi_click()
    if cur_item and cur_item.enabled then
        sys.publish("OPEN_WIFI_WIN")
        return
    end
    local mw, mh = msgbox_size()
    airui.msgbox({
        parent = main_container,
        w = mw, h = mh,
        title = "WiFi 连接管理",
        text = "请先在网络设置中开启该网络",
        buttons = { "确定" },
        on_action = on_prompt_dismiss,
    })
end

--[[只刷新状态文案与开关，不重建页面]]
local function refresh_status()
    if not main_container then return end
    local item = find_net(cur_id)
    if not item then return end
    cur_item = item
    if status_value then
        status_value:set_text(status_text_of(item.status))
        status_value:set_color(status_color_of(item.status))
    end
    if sw_handle and not pending then
        revert_switch(sw_handle, item.enabled)
    end
end

--[[互斥确认弹窗按钮回调]]
local function on_mutex_action(dlg, btn_label)
    if dlg then dlg:destroy() end
    local p = pending
    pending = nil
    if not p then return end
    if btn_label == "确定并重启" then
        net_manager.set_net_enabled(p.id, true)
        if sw_handle then sw_handle:set_state(true) end
        do_reboot()
    else
        revert_switch(sw_handle, p.prev)
    end
end

--[[重启确认弹窗按钮回调]]
local function on_switch_action(dlg, btn_label)
    if dlg then dlg:destroy() end
    pending = nil
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
local function on_switch_change(handle)
    local item = cur_item
    if not item then return end
    local enable = handle:get_state()
    local prev = item.enabled
    local preview = net_manager.preview_toggle(item.id, enable)
    if not preview.ok then
        revert_switch(handle, prev)
        return
    end
    if preview.reason == "airlink_mutex" then
        pending = { id = item.id, enable = enable, prev = prev }
        show_mutex_prompt(preview, item)
        return
    end
    if preview.reason == "airlink_switch" then
        net_manager.set_net_enabled(item.id, enable)
        item.enabled = enable
        pending = { id = item.id, enable = enable, prev = prev }
        show_switch_prompt(item)
        return
    end
    net_manager.set_net_enabled(item.id, enable)
    item.enabled = enable
end

--[[信息行：标签 + 数值]]
local function add_info_row(parent, y, w, row_h, label, value)
    local row, value_label = theme.kv_row(parent, {
        x = 0, y = y, w = w, h = row_h,
        label = label, value = value,
        label_w = math.floor(w * 0.46),
        label_color = CLR.t2, value_color = CLR.t1,
    })
    return row, value_label
end

local function build_ui()
    local item = find_net(cur_id)
    cur_item = item
    for _, it in ipairs(net_manager.list_networks()) do
        names[it.id] = it.name
    end

    local ctx = theme.page({
        title = (item and item.name) or "网络详情",
        sub = (item and item.detail) or "",
        on_back = on_back,
    })
    main_container = ctx.base
    page_w, page_h = ctx.sw, ctx.sh

    local x, w = ctx.x, ctx.w
    local y = ctx.y
    local back_h = theme.dp(48)
    local back_y = ctx.y + ctx.h - back_h

    if not item then
        theme.label(main_container, {
            x = x, y = y, w = w, h = theme.fs("label") + 8,
            text = "未找到该网络", px_size = theme.fs("label"),
            color = CLR.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    else
        local row_h = theme.dp(40)
        local info_h = theme.dp(16) + row_h * 4
        local info = theme.card(main_container, { x = x, y = y, w = w, h = info_h })
        local kv = {
            { "网络类型", item.id },
            { "是否 airlink", item.is_airlink and "是" or "否" },
            { "当前状态", status_text_of(item.status) },
            { "是否需要重启生效", item.is_airlink and "需要重启生效" or "在线即时生效" },
        }
        for i, r in ipairs(kv) do
            local ry = theme.dp(8) + (i - 1) * row_h
            local _, value_label = add_info_row(info, ry, w - 2, row_h, r[1], r[2])
            if i == 3 then status_value = value_label end
            if i < #kv then
                theme.divider(info, { x = theme.dp(14), y = ry + row_h - 1, w = w - theme.dp(28) })
            end
        end
        y = y + info_h + theme.dp(12)

        local sw_card_h = theme.dp(64)
        local sw_card = theme.card(main_container, { x = x, y = y, w = w, h = sw_card_h })
        local fs_name = theme.fs("body")
        local fs_sub = theme.fs("label")
        theme.label(sw_card, {
            x = theme.dp(14), y = theme.dp(6), w = w - theme.dp(160), h = fs_name + 8,
            text = "网络开关", px_size = fs_name, color = CLR.t1,
            align = airui.TEXT_ALIGN_LEFT,
        })
        theme.label(sw_card, {
            x = theme.dp(14), y = theme.dp(6) + fs_name + 8, w = w - theme.dp(160), h = fs_sub + 8,
            text = item.enabled and "已开启" or "已关闭", px_size = fs_sub, color = CLR.t2,
            align = airui.TEXT_ALIGN_LEFT,
        })
        local sw_w, sw_h = theme.dp(56), theme.dp(32)
        sw_handle = theme.switch({
            parent = sw_card,
            x = w - theme.dp(14) - sw_w, y = math.floor((sw_card_h - sw_h) / 2),
            w = sw_w, h = sw_h,
            checked = item.enabled and true or false,
            color = theme.C.primary,
            on_change = on_switch_change,
        })
        y = y + sw_card_h + theme.dp(12)

        if item.group == "wifi" then
            local btn_h = theme.dp(48)
            if item.enabled then
                wifi_btn = theme.button(main_container, {
                    x = x, y = y, w = w, h = btn_h,
                    text = "WiFi 连接管理", size = theme.F.body,
                    on_click = on_wifi_click,
                })
            else
                wifi_btn = theme.ghost_button(main_container, {
                    x = x, y = y, w = w, h = btn_h,
                    text = "WiFi 连接管理", size = theme.F.body,
                    fg = CLR.t3, bg_opa = theme.OPA.off,
                    on_click = on_wifi_click,
                })
                wifi_hint = theme.label(main_container, {
                    x = x, y = y + btn_h + theme.dp(6), w = w, h = fs_sub + 8,
                    text = "请先在网络设置中开启该网络", px_size = fs_sub,
                    color = theme.C.amber, align = airui.TEXT_ALIGN_CENTER,
                })
            end
        end
    end

    theme.button(main_container, {
        x = x, y = back_y, w = w, h = back_h,
        text = "返回", size = theme.F.body,
        on_click = on_back,
    })
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
    sw_handle = nil
    status_value = nil
    wifi_btn = nil
    wifi_hint = nil
    cur_item = nil
    names = {}
    window_id = nil
end

local function on_get_focus()
    refresh_status()
end

local function on_lose_focus() end

local function open(id)
    if type(id) == "string" and id ~= "" then cur_id = id end
    if exwin.is_active(window_id) then
        if main_container then main_container:destroy(); main_container = nil end
        sw_handle = nil
        status_value = nil
        wifi_btn = nil
        wifi_hint = nil
        build_ui()
        return
    end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_NET_DETAIL_WIN", open)
