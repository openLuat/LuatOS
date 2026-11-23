-- Air8606 接口复用设置，选项卡显示本次启动与下次启动的配置。
local theme = require "ui_theme"
local mux = require "air8606_mux"

local window_id, ctx, content
local active, saved, draft
local group_index
local reboot_queued = false
local render

local function show_message(title, detail)
    airui.msgbox({
        parent = ctx.base,
        w = math.min(ctx.w, theme.dp(520)),
        h = theme.dp(180),
        title = title, text = detail, buttons = { "确定" },
        on_action = function(dlg) dlg:destroy() end,
    })
end

local function save_selection()
    local ok, err = mux.save(draft)
    if not ok then
        show_message("配置保存失败", err)
        return false
    end
    active, saved = mux.state()
    return true
end

local function on_save()
    if not reboot_queued and save_selection() then render() end
end

local function on_reboot()
    if reboot_queued or not save_selection() then return end
    if mux.same(active, saved) then return end
    reboot_queued = sys.timerStart(rtos.reboot, 300) ~= nil
    render()
    if not reboot_queued then
        show_message("重启未启动", "配置已保存，请再点一次「立即重启」。")
    end
end

local function build_option(parent, group, option, y, w, h)
    local key, value = group.key, option.id
    local selected = draft[key] == value
    local card = theme.card(parent, {
        x = 0, y = y, w = w, h = h,
        opa = selected and theme.OPA.fill_hi or theme.OPA.glass,
        border = selected and theme.C.amber or theme.C.stroke,
        on_click = function()
            if reboot_queued or draft[key] == value then return end
            draft[key] = value
            render()
        end,
    })
    local p = theme.dp(14)
    local fs = theme.fs("body")
    local mark, mark_color
    if active[key] == value then
        mark, mark_color = "生效中", theme.SEM.success
    elseif saved[key] == value then
        mark, mark_color = "待重启", theme.C.amber
    elseif selected then
        mark, mark_color = "已选择", theme.C.amber
    end
    theme.label(card, {
        x = p, y = theme.dp(9), w = w - 2 * p - theme.dp(88), h = fs + 6,
        text = option.title, px_size = fs, color = theme.C.t1,
    })
    theme.label(card, {
        x = p, y = theme.dp(14) + fs, w = w - 2 * p, h = h - theme.dp(20) - fs,
        text = option.detail, px_size = theme.fs("label"), color = theme.C.t2,
    })
    if mark then
        theme.label(card, {
            x = w - p - theme.dp(86), y = theme.dp(11), w = theme.dp(86), h = fs + 6,
            text = mark, px_size = theme.fs("label"), color = mark_color,
            align = airui.TEXT_ALIGN_RIGHT,
        })
    end
end

render = function()
    if content then content:destroy() end
    local w, h = ctx.w, ctx.h
    content = theme.box(ctx.base, { x = ctx.x, y = ctx.y, w = w, h = h, opa = 0 })
    local groups = mux.groups
    local group = groups[group_index]
    local gap = theme.dp(8)
    local tab_h = theme.dp(40)
    local tab_w = math.floor((w - (#groups - 1) * gap) / #groups)
    for i, tab in ipairs(groups) do
        local button = i == group_index and theme.button or theme.ghost_button
        button(content, {
            x = (i - 1) * (tab_w + gap), y = 0, w = tab_w, h = tab_h,
            text = tab.title, size = theme.F.body,
            on_click = function()
                if i == group_index then return end
                group_index = i
                render()
            end,
        })
    end

    local footer_h = theme.dp(74)
    local list_y = tab_h + gap
    local list = theme.box(content, {
        x = 0, y = list_y, w = w, h = math.max(1, h - list_y - footer_h),
        opa = 0, scrollable = true,
    })
    local hint_h = theme.dp(w >= 600 and 56 or 78)
    local hint = theme.card(list, { x = 0, y = 0, w = w, h = hint_h })
    theme.label(hint, {
        x = theme.dp(14), y = theme.dp(10), w = w - theme.dp(28), h = hint_h - theme.dp(16),
        text = group.hint, px_size = theme.fs("label"), color = theme.C.t2,
    })
    local option_h = theme.dp(w >= 600 and 72 or 86)
    for i, option in ipairs(group.options) do
        build_option(list, group, option, hint_h + gap + (i - 1) * (option_h + gap), w, option_h)
    end

    local dirty = not mux.same(draft, saved)
    local pending = not mux.same(active, saved)
    local status = dirty and "有改动未保存" or (pending and "已保存，重启后生效" or "当前配置已生效")
    if reboot_queued then status = "正在重启" end
    local footer_y = h - footer_h + gap
    local button_h = theme.dp(42)
    local save_w = math.floor(w * 0.68)
    local save_button = dirty and not reboot_queued and theme.button or theme.ghost_button
    save_button(content, {
        x = 0, y = footer_y, w = save_w, h = button_h,
        text = "保存配置", size = theme.F.body,
        on_click = dirty and not reboot_queued and on_save or nil,
    })
    theme.ghost_button(content, {
        x = save_w + gap, y = footer_y, w = w - save_w - gap, h = button_h,
        text = dirty and "保存并重启" or "立即重启", size = theme.F.body,
        fg = (dirty or pending) and theme.C.t1 or theme.C.t3,
        on_click = (dirty or pending) and not reboot_queued and on_reboot or nil,
    })
    theme.label(content, {
        x = 0, y = footer_y + button_h + theme.dp(4), w = w, h = theme.dp(20),
        text = status, px_size = theme.fs("label"), color = theme.C.t2,
    })
end

local function open(key)
    local index = 1
    for i, group in ipairs(mux.groups) do
        if group.key == key then
            index = i
            break
        end
    end
    group_index = index
    if exwin.is_active(window_id) then
        render()
        return
    end
    window_id = exwin.open({
        on_create = function()
            active, saved = mux.state()
            draft = {}
            for name, value in pairs(saved) do draft[name] = value end
            ctx = theme.page({
                title = "接口复用",
                sub = "按板上接线选择用途，保存后重启生效",
                on_back = function() exwin.close(window_id) end,
            })
            render()
        end,
        on_destroy = function()
            ctx.base:destroy()
            ctx, content, window_id = nil, nil, nil
        end,
    })
end

sys.subscribe("OPEN_AIR8606_MUX_WIN", open)
