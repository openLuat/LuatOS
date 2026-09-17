--[[
@module  settings_about_win
@summary 关于设备子页面（TabOS 主题化）
@version 3.0
@date    2026.09.16
@author  江访

=== 消息协议 ===
订阅: OPEN_ABOUT_WIN             -> 打开本页
发布: ABOUT_DEVICE_GET_INFO      -> 请求设备信息（型号 / ID / 版本 / 内核）
发布: CONFIG_GET_DEVICE_NAME     -> 请求设备名称
订阅: ABOUT_DEVICE_INFO(info)    -> { device_name, model, unique_id, version, kernel }
订阅: CONFIG_DEVICE_NAME_VALUE(name)

=== v3.0 重写解决的两件事 ===
1) 文字溢出容器
   原实现把几何量写死成「XX * density_scale」并散在四个函数里，而 LVGL 的 label
   默认是自动换行（LV_LABEL_LONG_WRAP）—— 行高不够时文字会自己撑破盒子、溢出到
   卡片外面（内核版本那段最长，最明显）。现在：
     · 行高由「字号 + 3」（hzfont 行高）+ 估算行数算出来，不再拍数值；
     · 键在上、值在下且占满整行宽（原来值是挤在右侧 60% 的窄列里）；
     · 值文本按可用宽度做「截断 + ...」兜底，无论上报多长都不会溢出。
2) 方框套方框不好看
   原来是「带描边的大卡 -> 里面每一小行再各自带描边」，双层边框 + 大量留白。
   现在整组只有一个卡片，行与行之间用 1px 主题分隔线（theme.divider）。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil
local edit_win = nil
local name_input = nil
local soft_keyboard = nil

local sw, sh = 480, 800
local product_name = "合宙引擎主机"

-- 字段 -> 值标签的更新函数（行是在 build_info_list 里建的，这里存闭包）
local value_setters = {}
-- 字段 -> 当前显示值（点「设备名称」时作为输入框初值，避免拿到截断后的文本）
local current_values = {}

--[[可展示的信息行。lines = 该值最多占几行（决定行高与截断预算）]]
local ITEMS = {
    { key = "设备名称", field = "device_name", hint = "点此修改", lines = 1, placeholder = "--" },
    { key = "设备型号", field = "model",       lines = 1, placeholder = "--" },
    { key = "设备 ID",  field = "unique_id",   lines = 1, placeholder = "--" },
    { key = "软件版本", field = "version",     lines = 1, placeholder = "--" },
    { key = "内核版本", field = "kernel",      lines = 2, placeholder = "--" },
}

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
end

--[[按「可用宽度 x 行数」截断文本，超长补 ASCII 的 "..."。
不用省略号 U+2026：内置 hzfont 没有这个字形，会渲染成方框。]]
local function fit_value(text, w, px, lines)
    text = tostring(text or "")
    if text == "" then return "--" end
    local budget = w * lines
    if theme.text_width(text, px) <= budget then return text end
    local keep = px * 3 + px          -- 给 "..." 和一点余量
    local cut = #text
    while cut > 1 and theme.text_width(string.sub(text, 1, cut), px) > budget - keep do
        cut = cut - 1
    end
    -- 不要切在多字节字符中间（UTF-8 续字节 0x80~0xBF）
    while cut > 1 do
        local b = string.byte(text, cut)
        if b and b >= 0x80 and b < 0xC0 then cut = cut - 1 else break end
    end
    return string.sub(text, 1, cut) .. "..."
end

--[[信息行卡片：单个卡片 + 行间分隔线，没有嵌套边框]]
local function build_info_list(parent, x, y, w)
    local pad      = theme.dp(14)
    local fs_key   = theme.fs("micro")     -- 12
    local fs_val   = theme.fs("label")     -- 16
    local key_lh   = fs_key + 3            -- hzfont 行高 = 字号 + 3
    local val_lh   = fs_val + 3
    local gap      = theme.dp(4)
    local value_w  = w - pad * 2

    -- 先算总高：每行 = 上下内边距 + 键行 + 间隙 + 值行*行数
    local total_h = 0
    for i, it in ipairs(ITEMS) do
        it.row_h = pad * 2 + key_lh + gap + val_lh * (it.lines or 1)
        total_h = total_h + it.row_h + (i < #ITEMS and 1 or 0)
    end

    local card = theme.card(parent, { x = x, y = y, w = w, h = total_h })

    local cy = 0
    for i, it in ipairs(ITEMS) do
        local row = theme.box(card, {
            x = 0, y = cy, w = w, h = it.row_h,
            color = theme.C.black, opa = 0,
            on_click = it.on_click,
        })

        theme.label(row, {
            x = pad, y = pad, w = value_w, h = key_lh,
            text = it.key, px_size = fs_key,
            color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
        })
        if it.hint then
            theme.label(row, {
                x = pad, y = pad, w = value_w, h = key_lh,
                text = it.hint, px_size = fs_key,
                color = theme.C.primary, align = airui.TEXT_ALIGN_RIGHT,
            })
        end

        local value_label = theme.label(row, {
            x = pad, y = pad + key_lh + gap, w = value_w,
            h = val_lh * (it.lines or 1),
            text = it.placeholder, px_size = fs_val,
            color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
        })
        local lines = it.lines or 1
        value_setters[it.field] = function(text)
            current_values[it.field] = tostring(text or "")
            if value_label and not value_label:is_destroyed() then
                value_label:set_text(fit_value(text, value_w, fs_val, lines))
            end
        end

        if i < #ITEMS then
            theme.divider(card, { x = pad, y = cy + it.row_h, w = value_w })
        end
        cy = cy + it.row_h + 1
    end

    return card, total_h
end

--[[更改设备名称弹窗：配色全部走令牌（原先把标题色写死成纯白，
浅色主题下白字压白底直接看不见）]]
local function create_edit_win(device_name)
    local pad = theme.dp(18)
    local win_w = math.min(math.floor(sw * 0.84), theme.dp(560))
    local win_h = math.min(theme.dp(224), sh - theme.dp(40))
    if win_w < theme.dp(220) then win_w = sw - theme.dp(20) end

    soft_keyboard = theme.keyboard({
        parent = main_container,
        x = 0, y = -theme.dp(20),
        w = sw, h = theme.dp(260),
        mode = "text",
        auto_hide = true,
        on_commit = function(self) self:hide() end,
    })

    edit_win = airui.win({
        parent = main_container,
        title = "更改设备名称",
        w = win_w, h = win_h,
        close_btn = false,
        auto_center = true,
        style = {
            bg_color = theme.C.dialog,
            header_bg_color = theme.C.panel_hi,
            content_bg_color = theme.C.dialog,
            title_text_color = theme.C.t1,
            radius = theme.r("md"),
            title_align = airui.TEXT_ALIGN_CENTER,
            header_height = theme.dp(48),
        },
        on_close = function(self)
            log.info("settings_about", "编辑窗口已关闭")
            if soft_keyboard then
                soft_keyboard:destroy()
                soft_keyboard = nil
            end
            edit_win = nil
        end
    })

    local function close_all()
        if soft_keyboard then
            soft_keyboard:hide()
            soft_keyboard:destroy()
            soft_keyboard = nil
        end
        if edit_win then edit_win:close() end
    end

    name_input = theme.input({
        parent = edit_win,
        x = pad, y = theme.dp(64),
        w = win_w - 2 * pad, h = theme.dp(56),
        text = device_name or "",
        placeholder = "请输入设备名称",
        max_len = 32,
        mode = "text",
        px_size = theme.fs("h3"),
        keyboard = soft_keyboard,
    })

    local btn_h = theme.dp(44)
    local btn_y = win_h - pad - btn_h
    local btn_w = math.floor((win_w - 3 * pad) / 2)
    if btn_w < theme.dp(60) then btn_w = theme.dp(60) end

    theme.ghost_button(edit_win, {
        x = pad, y = btn_y, w = btn_w, h = btn_h,
        text = "取消", size = 14,
        on_click = function() close_all() end,
    })
    theme.button(edit_win, {
        x = pad * 2 + btn_w, y = btn_y, w = btn_w, h = btn_h,
        text = "保存", size = 14,
        bg = theme.C.primary, fg = theme.C.on_primary,
        on_click = function()
            local new_name = name_input and name_input:get_text() or ""
            if new_name and #new_name > 0 then
                if value_setters.device_name then value_setters.device_name(new_name) end
                sys.publish("CONFIG_SET_DEVICE_NAME", new_name)
                close_all()
                airui.msgbox({
                    title = "提示", text = "设备名称已保存", buttons = {"确定"},
                    on_action = function(self) self:hide() end,
                })
            else
                airui.msgbox({
                    title = "提示", text = "设备名称不能为空", buttons = {"确定"},
                    on_action = function(self) self:hide() end,
                })
            end
        end,
    })
end

local function build_ui()
    update_screen_size()

    local cfg_chip = (_G.project_config and _G.project_config.chip) or ""
    local suffix = cfg_chip:gsub("^Air", "")
    product_name = (suffix ~= "") and ("合宙引擎主机" .. suffix) or "合宙引擎主机"

    local ctx = theme.page({
        title = "关于设备",
        sub = "设备型号、唯一 ID 与版本信息",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base

    -- 内容区可滚动：小屏上（600 高）信息行较多时不会被裁掉
    local body = theme.box(ctx.base, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = ctx.h,
        color = theme.C.black, opa = 0, scrollable = true,
    })

    ITEMS[1].on_click = function()
        create_edit_win(current_values.device_name or product_name)
    end

    local _, card_h = build_info_list(body, 0, 0, ctx.w)

    -- 底部说明：剩余空间不够就不画，避免在小屏上被裁成半行
    local fs_note = theme.fs("micro")
    local note_y = card_h + theme.dp(10)
    if note_y + (fs_note + 3) <= ctx.h then
        theme.label(body, {
            x = 0, y = note_y, w = ctx.w, h = fs_note + 3,
            text = "设备名称可点击修改；其余信息由系统上报",
            px_size = fs_note, color = theme.C.t3,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
end

local function on_device_info(info)
    if not info then return end
    if info.device_name and value_setters.device_name then value_setters.device_name(info.device_name) end
    if info.model and value_setters.model then value_setters.model(info.model) end
    if info.unique_id and value_setters.unique_id then value_setters.unique_id(info.unique_id) end
    if info.version and value_setters.version then value_setters.version(info.version) end
    if info.kernel and value_setters.kernel then value_setters.kernel(info.kernel) end
    log.info("settings_about", "UI更新设备信息")
end

local function on_device_name(device_name)
    if value_setters.device_name then value_setters.device_name(device_name) end
    log.info("settings_about", "更新设备名称", device_name)
end

local function on_create()
    value_setters = {}
    current_values = {}
    build_ui()
    sys.publish("ABOUT_DEVICE_GET_INFO")
    sys.publish("CONFIG_GET_DEVICE_NAME")
    sys.subscribe("ABOUT_DEVICE_INFO", on_device_info)
    sys.subscribe("CONFIG_DEVICE_NAME_VALUE", on_device_name)
end

local function on_destroy()
    sys.unsubscribe("ABOUT_DEVICE_INFO", on_device_info)
    sys.unsubscribe("CONFIG_DEVICE_NAME_VALUE", on_device_name)
    if soft_keyboard then
        soft_keyboard:destroy()
        soft_keyboard = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    edit_win = nil
    name_input = nil
    value_setters = {}
    current_values = {}
end

local function on_get_focus() end

local function on_lose_focus()
    if soft_keyboard then
        soft_keyboard:hide()
        soft_keyboard:destroy()
        soft_keyboard = nil
    end
    if edit_win then edit_win:close() end
end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_ABOUT_WIN", open_handler)
