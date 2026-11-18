-- 设置首页嵌入式设备信息卡，复用设备信息事件和名称编辑弹窗。
local theme = require "ui_theme"

local main_container = nil
local edit_win = nil
local name_input = nil
local soft_keyboard = nil

local sw, sh = 480, 800

-- 字段 -> 值标签的更新函数（行是在 build_info_list 里建的，这里存闭包）
local value_setters = {}
-- 字段 -> 当前显示值（点「设备名称」时作为输入框初值，避免拿到截断后的文本）
local current_values = {}

-- 清理软键盘并置空弹窗引用（不负责删窗体；删窗体走 close_edit_dialog 或 C 侧关闭回调）
local function cleanup_edit_dialog()
    local kb = soft_keyboard
    soft_keyboard = nil
    if kb and not kb:is_destroyed() then
        pcall(kb.hide, kb)
        pcall(kb.destroy, kb)
    end
    edit_win = nil
    name_input = nil
end

-- 关闭编辑弹窗（取消/保存/失焦/页面销毁统一入口，各步容错互不影响）
local function close_edit_dialog()
    local win = edit_win
    cleanup_edit_dialog()
    if win and not win:is_destroyed() then
        pcall(win.close, win)
    end
end

--[[可展示的信息行。lines = 该值最多占几行（决定行高与截断预算）]]
local ITEMS = {
    { key = "设备名称", field = "device_name", hint = "点此修改", lines = 1, placeholder = "--" },
    { key = "设备型号", field = "model",       lines = 2, placeholder = "--" },
    { key = "设备ID",   field = "unique_id",   lines = 2, placeholder = "--" },
    { key = "固件版本", field = "version",     lines = 1, placeholder = "--" },
    { key = "内核版本", field = "kernel",      lines = 2, placeholder = "--" },
    { key = "主控芯片", field = "chip",        lines = 1, placeholder = "--" },
    { key = "屏幕分辨率", field = "resolution", lines = 1, placeholder = "--" },
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

--[[信息行卡片：单个卡片 + 行间分隔线，没有嵌套边框

尺寸契约（LVGL 内容区 = 外框 - 2x描边，pad=0）：theme.card 自带 1px 描边，
子组件坐标原点已经内移到描边内侧，行宽必须用 (w - 2)，行堆叠总高也要比卡片
外高少 2。以前直接按外框 w x total_h 铺满，右/下各撑出 2px —— 容器天生带
LV_OBJ_FLAG_SCROLLABLE，超出就画滚动条，这张圆角卡片上便多出一对「滑块」
（用户报的「没考虑容器倒角 -> 出现滑块」就是它）。]]
local function build_info_list(parent, x, y, w, h)
    local bw       = 1                     -- theme.card 默认描边宽度
    local inner_w  = w - 2 * bw            -- 卡片内容区宽
    local pad      = theme.dp(14)
    local fs_key   = math.max(theme.FONT_MIN, theme.fs("micro"))
    local fs_val   = math.max(theme.FONT_MIN, theme.fs("label"))
    local key_lh   = fs_key + 3            -- hzfont 行高 = 字号 + 3
    local val_lh   = fs_val + 3
    local key_w    = theme.text_width("屏幕分辨率", fs_key)
    local value_x  = pad + key_w + theme.dp(12)
    local value_w  = inner_w - pad - value_x

    -- 先算总高：每行 = 上下内边距 + 键行 + 间隙 + 值行*行数
    local total_h = pad * 2
    for i, it in ipairs(ITEMS) do
        it.row_h = theme.dp(8) * 2 + val_lh * (it.lines or 1)
        total_h = total_h + it.row_h + (i < #ITEMS and 1 or 0)
    end

    -- 填满可用高度，富余空间均分到各行；高度不足时由外层容器滚动。
    local card_h = math.max(h or 0, total_h + 2 * bw)
    local extra = card_h - total_h - 2 * bw
    local card = theme.card(parent, { x = x, y = y, w = w, h = card_h, border_w = bw })

    local cy = pad
    for i, it in ipairs(ITEMS) do
        local row_h = it.row_h + math.floor(extra * i / #ITEMS) - math.floor(extra * (i - 1) / #ITEMS)
        local row = theme.box(card, {
            x = 0, y = cy, w = inner_w, h = row_h,
            color = theme.C.black, opa = 0,
            on_click = it.on_click,
        })

        theme.label(row, {
            x = pad, y = math.floor((row_h - key_lh) / 2),
            w = key_w, h = key_lh,
            text = it.key, px_size = fs_key,
            color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
        })
        local value_label
        local lines = it.lines or 1
        local function set_value(text)
            current_values[it.field] = tostring(text or "")
            local display_text = fit_value(text, value_w, fs_val, lines)
            local shown_lines = math.min(lines, theme.text_lines(display_text, value_w, fs_val))
            local value_h = val_lh * shown_lines
            -- Label 没有垂直对齐属性，按实际行数居中创建，避免单行值顶在两行框上方。
            if value_label and not value_label:is_destroyed() then value_label:destroy() end
            value_label = theme.label(row, {
                x = value_x, y = math.floor((row_h - value_h) / 2), w = value_w, h = value_h,
                text = display_text, px_size = fs_val,
                color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
            })
        end
        value_setters[it.field] = set_value
        set_value(it.placeholder)

        if i < #ITEMS then
            theme.divider(card, { x = pad, y = cy + row_h, w = inner_w - 2 * pad })
        end
        cy = cy + row_h + 1
    end

    return card, card_h
end

--[[更改设备名称弹窗：配色全部走令牌（原先把标题色写死成纯白，
浅色主题下白字压白底直接看不见）

v3.1 尺寸重排（与 settings_auto_win 的弹窗口径一致）：
1) 标题栏要占掉弹窗高度：airui.win 的内容区 = win_h - header_height，win_h 是
   「标题栏 + 内容」的总高。以前拿 win_h(224) 当内容高来排输入框/按钮，按钮
   (y + 44) 正好探出内容区 48px（ = 标题栏高），看上去就是「没考虑标题栏、
   按钮飞出弹窗」。现在 win_h = header_h + content_h，按钮按真实内容高贴底排。
2) style 加 content_pad = 0：子元素相对内容区 (0,0) 摆放（不传时有默认内边距，
   实际可用区还要再缩一圈），边距全部自己掌控。
3) 倒角安全边距：内容边距不小于弹窗圆角 radius，按钮/输入框的方角就不会被
   弹窗圆角切进内容里，圆角边缘不再难看。]]
local function create_edit_win(device_name)
    local header_h = theme.dp(48)
    local radius   = theme.r("md")
    local pad      = math.max(theme.dp(18), radius)   -- 倒角安全边距
    local win_w = math.min(math.floor(sw * 0.84), theme.dp(560))
    if win_w < theme.dp(220) then win_w = sw - theme.dp(20) end

    local input_h = theme.dp(56)
    local btn_h   = theme.dp(44)

    --[[内容区高度 = 上边距 + 输入框 + 间距 + 按钮 + 下边距；弹窗总高再加上标题栏。
    最低支持 480×800 / 800×480，该尺寸恒放得下 —— 针对小屏机型的压缩兜底已随
    小屏支持一并移除。按钮贴内容区底边（下边距 = pad，倒角安全），输入框顶对齐。]]
    local content_h = pad + input_h + theme.dp(20) + btn_h + pad
    local win_h = header_h + content_h
    local btn_y = content_h - pad - btn_h

    --[[弹窗定位：按钮贴内容区底边，整窗必须避开软键盘弹起占住的屏幕底部区域
    （键盘 + 输入预览条 + 拼音候选栏，按键盘高再留 dp(96) 余量）。原来用
    auto_center 垂直居中，键盘弹出后正好盖住取消/保存，点击落到按键上，
    弹窗无法关闭。放不下时贴顶显示（按钮在上沿，键盘只能盖到窗体下沿）。]]
    local kb_stack_h = math.floor(200 * (_G.density_scale or 1.0)) + theme.dp(96)
    local win_x = math.floor((sw - win_w) / 2)
    local win_y = math.floor((sh - win_h) / 2)
    if win_y + win_h > sh - kb_stack_h then
        win_y = sh - kb_stack_h - win_h
    end
    if win_y < theme.dp(8) then win_y = theme.dp(8) end

    --[[键盘统一规范（与 wifi 密码键盘一致）：
        parent 必须是「宽 = 内容区宽」的本页根容器 —— 拼音候选栏与输入预览框
        都由 C 侧建在键盘的父对象上、宽度取父宽的 100%（整屏宽就会左右超出键盘）；
        挂在屏幕根上还会变成「整屏底部居中」，与内容区错开且不随页面销毁。
        y 固定 0（相对父容器底部居中），高度统一 dp(200)，全部带 preview 输入预览条。]]
    soft_keyboard = theme.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = sw, h = math.floor(200 * _G.density_scale),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    edit_win = airui.win({
        parent = main_container,
        title = "更改设备名称",
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
            log.info("settings_about", "编辑窗口已关闭")
            cleanup_edit_dialog()
        end
    })

    -- 以下子元素均相对内容区 (0,0) 布局（content_pad = 0）
    name_input = theme.input({
        parent = edit_win,
        x = pad, y = pad,
        w = win_w - 2 * pad, h = input_h,
        text = device_name or "",
        placeholder = "请输入设备名称",
        max_len = 32,
        mode = "text",
        px_size = theme.fs("h3"),
        keyboard = soft_keyboard,
    })

    local btn_w = math.floor((win_w - 3 * pad) / 2)
    if btn_w < theme.dp(60) then btn_w = theme.dp(60) end

    theme.ghost_button(edit_win, {
        x = pad, y = btn_y, w = btn_w, h = btn_h,
        text = "取消", size = 14,
        on_click = function() close_edit_dialog() end,
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
                close_edit_dialog()
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

local function on_device_info(info)
    if not info then return end
    if info.device_name and value_setters.device_name then value_setters.device_name(info.device_name) end
    if info.model and value_setters.model then value_setters.model(info.model) end
    if info.unique_id and value_setters.unique_id then value_setters.unique_id(info.unique_id) end
    if info.kernel and value_setters.kernel then value_setters.kernel(info.kernel) end
    if info.version and value_setters.version then value_setters.version(info.version) end
    if info.chip and value_setters.chip then value_setters.chip(info.chip) end
    if info.resolution and value_setters.resolution then value_setters.resolution(info.resolution) end
    log.info("settings_about", "UI更新设备信息")
end

local function on_device_name(device_name)
    if value_setters.device_name then value_setters.device_name(device_name) end
    log.info("settings_about", "更新设备名称", device_name)
end

local M = {}
function M.mount(root, x, y, w, h, parent)
    main_container = root
    update_screen_size()
    value_setters = {}
    current_values = {}
    ITEMS[1].on_click = function() create_edit_win(current_values.device_name or "") end
    local host = parent or root
    if h then
        host = theme.box(host, {
            x = x, y = y, w = w, h = h,
            color = theme.C.black, opa = 0, scrollable = true,
        })
        x, y = 0, 0
    end
    local _, card_h = build_info_list(host, x, y, w, h)
    local cfg = _G.project_config or {}
    on_device_info({
        device_name = "合宙引擎主机" .. (cfg.chip or ""):gsub("^Air", ""),
        model = cfg.name or "--", chip = cfg.chip or "--",
        resolution = string.format("%d × %d", screen_w or 480, screen_h or 800),
    })
    sys.subscribe("ABOUT_DEVICE_INFO", on_device_info)
    sys.subscribe("CONFIG_DEVICE_NAME_VALUE", on_device_name)
    sys.publish("ABOUT_DEVICE_GET_INFO")
    sys.publish("CONFIG_GET_DEVICE_NAME")
    return card_h
end

function M.unmount()
    sys.unsubscribe("ABOUT_DEVICE_INFO", on_device_info)
    sys.unsubscribe("CONFIG_DEVICE_NAME_VALUE", on_device_name)
    close_edit_dialog()
    main_container = nil
    value_setters = {}
    current_values = {}
end
M.close_editor = close_edit_dialog
return M
