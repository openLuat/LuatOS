--[[
@module  settings_time_win
@summary 系统时间校准子页面（TabOS 深色玻璃态）
@version 1.0
@date    2026.10.22
@author  江访
@usage
订阅: OPEN_TIME_WIN
发布: TIME_GET / TIME_SET(year,mon,day,hour,min,sec)
订阅: TIME_VALUE(t) / TIME_CHANGED(ts) / TIME_SET_RESULT(ok, err)

页面提供年/月/日/时/分/秒六行加减调节，点数值可直接输入，底部「保存」写入系统时钟。
联网后 NTP 会自动校时。
]]

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container = nil
local edit_win = nil
local value_input = nil
local soft_keyboard = nil

local sw, sh = 480, 800
local pad = 15

-- 六个时间字段的显示定义（lo/hi 为取值区间）
local FIELDS = {
    { key = "year", label = "年", fmt = "%04d", lo = 2000, hi = 2099 },
    { key = "mon",  label = "月", fmt = "%02d", lo = 1, hi = 12 },
    { key = "day",  label = "日", fmt = "%02d", lo = 1, hi = 31 },
    { key = "hour", label = "时", fmt = "%02d", lo = 0, hi = 23 },
    { key = "min",  label = "分", fmt = "%02d", lo = 0, hi = 59 },
    { key = "sec",  label = "秒", fmt = "%02d", lo = 0, hi = 59 },
}
local FIELD_BY_KEY = {}
for _, f in ipairs(FIELDS) do FIELD_BY_KEY[f.key] = f end

-- 当前编辑值与数值标签
local values = {}
local value_labels = {}

local open_edit_win

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

-- 清理软键盘并置空弹窗引用（删窗体走 close_edit_dialog 或 C 侧关闭回调）
local function cleanup_edit_dialog()
    local kb = soft_keyboard
    soft_keyboard = nil
    if kb and not kb:is_destroyed() then
        pcall(kb.hide, kb)
        pcall(kb.destroy, kb)
    end
    edit_win = nil
    value_input = nil
end

-- 关闭编辑弹窗（取消/确定/失焦/页面销毁统一入口，各步容错互不影响）
local function close_edit_dialog()
    local win = edit_win
    cleanup_edit_dialog()
    if win and not win:is_destroyed() then
        pcall(win.close, win)
    end
end

--[[
@function clamp_field
@summary 把字段值夹取到合法区间
@param key 字段名
@param v 待夹取的值
@return number 夹取后的值
]]
local function clamp_field(key, v)
    local f = FIELD_BY_KEY[key]
    if not f or not f.lo then return v end
    if v < f.lo then return f.lo end
    if v > f.hi then return f.hi end
    return v
end

--[[
@function set_field
@summary 夹取并写入字段值，同步刷新数值标签
@param key 字段名
@param v 字段值
]]
local function set_field(key, v)
    local f = FIELD_BY_KEY[key]
    if not f then return end
    v = clamp_field(key, tonumber(v) or (values[key] or 0))
    values[key] = v
    local lab = value_labels[key]
    if lab and not lab:is_destroyed() then
        lab:set_text(string.format(f.fmt, v))
    end
end

--[[
@function apply_time
@summary 用一张时间表回填六个字段（兼容 mon / month 两种月份字段名）
@param t { year,mon,day,hour,min,sec }
]]
local function apply_time(t)
    if not t then return end
    set_field("year", t.year)
    set_field("mon", t.mon or t.month)
    set_field("day", t.day)
    set_field("hour", t.hour)
    set_field("min", t.min)
    set_field("sec", t.sec)
end

--[[
@function init_values
@summary 进页面时用当前系统时间回填字段，越界值按区间夹取
]]
local function init_values()
    local t = os.date("*t")
    value_labels = {}
    set_field("year", t.year)
    set_field("mon", t.month)
    set_field("day", t.day)
    set_field("hour", t.hour)
    set_field("min", t.min)
    set_field("sec", t.sec)
end

-- 提示弹窗（标题 + 一句说明 + 单个确定按钮）
local function show_tip(text)
    airui.msgbox({
        title = "提示", text = text, buttons = { "确定" },
        on_action = function(self) self:hide() end,
    })
end

--[[时间字段调节行：字段名 | [-] 数值 [+]。
数值区域整体可点，点开直接输入弹窗。]]
local function build_field_row(parent, x, y, w, h, f)
    local row = theme.box(parent, {
        x = x, y = y, w = w, h = h, color = theme.C.black, opa = 0,
    })

    local pad2 = theme.dp(12)
    local gap2 = theme.dp(8)
    local lw = theme.dp(40)
    local btn_w = theme.dp(52)
    local right_w = 2 * btn_w + gap2
    local btn_h = h - 2 * theme.dp(6)
    if btn_h < theme.dp(28) then btn_h = theme.dp(28) end
    local btn_y = math.floor((h - btn_h) / 2)

    local x1 = pad2 + lw + gap2
    local val_w = w - x1 - pad2 - right_w - gap2
    if val_w < theme.dp(60) then val_w = theme.dp(60) end

    local fs = theme.fs("h3")
    local lh = fs + 3
    local ty = math.floor((h - lh) / 2)
    if ty < 0 then ty = 0 end

    theme.label(row, {
        x = pad2, y = ty, w = lw, h = lh,
        text = f.label, px_size = fs, color = theme.C.t2,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 数值区（可点直接输入，数值标签挂在它下面）
    local val_box = theme.box(row, {
        x = x1, y = 0, w = val_w, h = h, color = theme.C.black, opa = 0,
        on_click = function() open_edit_win(f) end,
    })

    value_labels[f.key] = theme.label(val_box, {
        x = 0, y = ty, w = val_w, h = lh,
        text = string.format(f.fmt, values[f.key] or 0),
        px_size = fs, color = theme.C.t1, align = airui.TEXT_ALIGN_CENTER,
    })

    theme.ghost_button(row, {
        x = x1 + val_w + gap2, y = btn_y, w = btn_w, h = btn_h,
        text = "-", size = 20,
        on_click = function() set_field(f.key, (values[f.key] or 0) - 1) end,
    })
    theme.ghost_button(row, {
        x = x1 + val_w + gap2 + btn_w + gap2, y = btn_y, w = btn_w, h = btn_h,
        text = "+", size = 20,
        on_click = function() set_field(f.key, (values[f.key] or 0) + 1) end,
    })
    return row
end

--[[直接输入弹窗：软键盘弹起后定位避开键盘占据的屏幕底部区域，
按钮贴内容区底边，放不下时贴顶显示。]]
function open_edit_win(f)
    close_edit_dialog()

    local header_h = theme.dp(48)
    local radius   = theme.r("md")
    local epad     = math.max(theme.dp(18), radius)
    local win_w = math.min(math.floor(sw * 0.84), theme.dp(560))
    if win_w < theme.dp(220) then win_w = sw - theme.dp(20) end

    local input_h = theme.dp(56)
    local btn_h   = theme.dp(44)

    local content_h = epad + input_h + theme.dp(20) + btn_h + epad
    local win_h = header_h + content_h
    local btn_y = content_h - epad - btn_h

    --[[键盘 + 输入预览条 + 拼音候选栏占据的屏幕底部高度，
    按键盘高再留 dp(96) 余量。弹窗底边不得进入该区域。]]
    local kb_stack_h = math.floor(200 * (_G.density_scale or 1.0)) + theme.dp(96)
    local win_x = math.floor((sw - win_w) / 2)
    local win_y = math.floor((sh - win_h) / 2)
    if win_y + win_h > sh - kb_stack_h then
        win_y = sh - kb_stack_h - win_h
    end
    if win_y < theme.dp(8) then win_y = theme.dp(8) end

    soft_keyboard = theme.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = sw, h = math.floor(200 * (_G.density_scale or 1.0)),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    edit_win = airui.win({
        parent = main_container,
        title = "设置" .. f.label,
        x = win_x, y = win_y,
        w = win_w, h = win_h,
        close_btn = false,
        style = {
            bg_color = theme.C.dialog,
            header_bg_color = theme.C.panel_hi,
            content_bg_color = theme.C.dialog,
            title_text_color = theme.C.t1,
            radius = radius,
            title_align = airui.TEXT_ALIGN_CENTER,
            header_height = header_h,
            content_pad = 0,
        },
        on_close = function(self)
            cleanup_edit_dialog()
        end
    })

    value_input = theme.input({
        parent = edit_win,
        x = epad, y = epad,
        w = win_w - 2 * epad, h = input_h,
        text = string.format(f.fmt, values[f.key] or 0),
        placeholder = "请输入" .. f.label,
        max_len = 4,
        mode = "text",
        px_size = theme.fs("h3"),
        keyboard = soft_keyboard,
    })

    local btn_w = math.floor((win_w - 3 * epad) / 2)
    if btn_w < theme.dp(60) then btn_w = theme.dp(60) end

    theme.ghost_button(edit_win, {
        x = epad, y = btn_y, w = btn_w, h = btn_h,
        text = "取消", size = 14,
        on_click = function() close_edit_dialog() end,
    })
    theme.button(edit_win, {
        x = epad * 2 + btn_w, y = btn_y, w = btn_w, h = btn_h,
        text = "确定", size = 14,
        bg = theme.C.primary, fg = theme.C.on_primary,
        on_click = function()
            local raw = value_input and value_input:get_text() or ""
            if soft_keyboard then pcall(soft_keyboard.hide, soft_keyboard) end
            local v = tonumber(raw)
            if not v then
                show_tip("请输入数字")
                return
            end
            set_field(f.key, v)
            close_edit_dialog()
        end,
    })
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)
    local _, th = titlebar.create(main_container, "设置当前时间", sw,
        function() exwin.close(window_id) end, "手动校准系统时钟")

    local y = pad + th + pad
    local card_w = sw - 2 * pad
    local avail = screen_h - y - pad

    -- 内容区可滚动：矮横屏（800×480）等分不足时向下滚，六行始终完整可调
    local body = theme.box(main_container, {
        x = pad, y = y, w = card_w, h = avail,
        color = theme.C.black, opa = 0, scrollable = true,
    })

    local gap = theme.dp(10)
    local save_h = theme.dp(44)
    local fs_note = theme.fs("micro")
    local note_h = fs_note + 3
    local bw = 1

    -- 六行等分剩余高度，每行高度夹在 dp(36)~dp(64)
    local row_h = math.floor((avail - save_h - note_h - 2 * gap - 2 * bw) / #FIELDS)
    if row_h < theme.dp(36) then row_h = theme.dp(36) end
    if row_h > theme.dp(64) then row_h = theme.dp(64) end

    local total_h = row_h * #FIELDS
    local card = theme.card(body, {
        x = 0, y = 0, w = card_w, h = total_h + 2 * bw, border_w = bw,
    })

    local inner_w = card_w - 2 * bw
    for i, f in ipairs(FIELDS) do
        local cy = (i - 1) * row_h
        build_field_row(card, 0, cy, inner_w, row_h, f)
        if i < #FIELDS then
            theme.divider(card, { x = theme.dp(12), y = cy + row_h, w = inner_w - 2 * theme.dp(12) })
        end
    end

    local btn_w = math.floor(card_w * 0.5)
    theme.button(body, {
        x = math.floor((card_w - btn_w) / 2), y = total_h + 2 * bw + gap,
        w = btn_w, h = save_h,
        text = "保存", size = 16,
        bg = theme.C.primary, fg = theme.C.on_primary,
        on_click = function()
            sys.publish("TIME_SET", values.year, values.mon, values.day,
                        values.hour, values.min, values.sec)
        end,
    })

    theme.label(body, {
        x = 0, y = total_h + 2 * bw + gap + save_h + gap,
        w = card_w, h = note_h,
        text = "联网后 NTP 会自动校时", px_size = fs_note,
        color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
    })
end

--[[
@function on_time_changed
@summary 系统时钟写入成功后按新时间刷新六个字段
@param ts Unix 时间戳
]]
local function on_time_changed(ts)
    apply_time(os.date("*t", tonumber(ts) or nil))
end

--[[
@function on_set_result
@summary 写入结果回执，失败时给出错误原因
@param ok 是否成功
@param err 失败原因
]]
local function on_set_result(ok, err)
    if ok then
        show_tip("时间已保存")
    else
        show_tip(err or "时间设置失败")
    end
end

local function on_create()
    init_values()
    build_ui()
    sys.subscribe("TIME_VALUE", apply_time)
    sys.subscribe("TIME_CHANGED", on_time_changed)
    sys.subscribe("TIME_SET_RESULT", on_set_result)
    sys.publish("TIME_GET")
end

local function on_destroy()
    sys.unsubscribe("TIME_VALUE", apply_time)
    sys.unsubscribe("TIME_CHANGED", on_time_changed)
    sys.unsubscribe("TIME_SET_RESULT", on_set_result)
    close_edit_dialog()
    if main_container then main_container:destroy(); main_container = nil end
    value_labels = {}
end

local function on_get_focus() end

local function on_lose_focus()
    close_edit_dialog()
end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_TIME_WIN", open_handler)
