-- 公交车投币系统 · 1024 x 600
-- 一级主菜单：只居中放大显示当前票价
-- 二级页面：车辆编号 / 票价单价 / 满胆预警三个按钮
-- 三级页面：下键换位，上键改数，确认保存，取消询问是否保存
local UI = {}
UI.__index = UI

local C = {
    bg           = 0x07121A,
    top          = 0x0B1B26,
    bottom       = 0x0A1721,
    panel        = 0x0F202C,
    panel2       = 0x122733,
    row          = 0x0D1C27,
    row_sel      = 0x143241,
    border       = 0x203B4B,
    border_sel   = 0x2D7186,
    text         = 0xEAF5FB,
    soft         = 0xB9CBD6,
    muted        = 0x8AA3B5,
    dim          = 0x60798B,
    accent       = 0x39C6DA,
    green        = 0x35D6A0,
    green_bg     = 0x0D3229,
    green_border = 0x1D5A48,
    amber        = 0xF3B54A,
    amber_bg     = 0x3A2A12,
    amber_border = 0x6B4D1F,
    red          = 0xE27282,
    logo_bg      = 0x123647
}

local CELL_W = 96
local CELL_H = 120
local CELL_GAP = 14
local DOT_W = 26

local function box(parent, x, y, w, h, color, radius, border, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opacity or 255,
        radius = radius or 0,
        border_color = border, border_width = border and 1 or 0
    })
end

local function label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font = "hzfont", font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT
    })
end

local KEY_STYLE = {
    up = {
        bg_color = 0x142B38, text_color = 0xD9E9F2,
        border_color = 0x2A4C5E, border_width = 1,
        radius = 12, pad = 0,
        pressed_bg_color = 0x1D3D4F, pressed_text_color = 0xFFFFFF
    },
    down = {
        bg_color = 0x142B38, text_color = 0xD9E9F2,
        border_color = 0x2A4C5E, border_width = 1,
        radius = 12, pad = 0,
        pressed_bg_color = 0x1D3D4F, pressed_text_color = 0xFFFFFF
    },
    confirm = {
        bg_color = 0x1FA97A, text_color = 0x051B13,
        border_width = 0, radius = 12, pad = 0,
        pressed_bg_color = 0x2BD296, pressed_text_color = 0x04120D
    },
    cancel = {
        bg_color = 0x8E3542, text_color = 0xFFE9EC,
        border_width = 0, radius = 12, pad = 0,
        pressed_bg_color = 0xB44554, pressed_text_color = 0xFFFFFF
    }
}

function UI.new(model, config)
    local self = setmetatable({
        model = model,
        config = config,
        cache = {},
        menu_style = {},
        cell_style = {},
        dialog_style = {}
    }, UI)
    self:_build()
    return self
end

function UI:_build()
    self.main = box(nil, 0, 0, self.config.width, self.config.height, C.bg)

    -- 顶部栏
    box(self.main, 0, 0, 1024, 92, C.top)
    box(self.main, 0, 91, 1024, 1, C.border)
    box(self.main, 40, 24, 44, 44, C.logo_bg, 12, C.border)
    label(self.main, 40, 32, 44, 28, "投", 22, C.accent, airui.TEXT_ALIGN_CENTER)
    label(self.main, 100, 15, 520, 42, "公交车投币系统", 30, C.text)
    label(self.main, 102, 56, 460, 18, "BUS FARE TERMINAL  /  AIR8601", 12, C.muted)

    box(self.main, 872, 30, 112, 32, C.green_bg, 16, C.green_border)
    box(self.main, 884, 42, 8, 8, C.green, 4)
    label(self.main, 900, 37, 74, 18, "系统正常", 13, C.green)

    -- 一级主菜单：只居中放大显示当前票价
    self.home_page = box(self.main, 0, 92, 1024, 384, C.bg)
    local fare_card = box(self.home_page, 112, 32, 800, 320, C.panel, 24, C.border)
    box(fare_card, 0, 0, 800, 5, C.amber, 2)
    label(fare_card, 0, 40, 800, 24, "当前票价", 18, C.muted,
        airui.TEXT_ALIGN_CENTER)
    self.home_fare = label(fare_card, 0, 96, 800, 140, "002.00", 96, C.amber,
        airui.TEXT_ALIGN_CENTER)
    label(fare_card, 0, 248, 800, 30, "元 / 人次", 22, C.muted,
        airui.TEXT_ALIGN_CENTER)

    -- 二级页面：三个设置按钮
    self.menu_page = box(self.main, 0, 92, 1024, 384, C.bg)
    label(self.menu_page, 40, 14, 300, 28, "参数设置", 22, C.text)
    label(self.menu_page, 40, 44, 700, 18,
        "上 / 下 选择 · 确认进入 · 取消返回主菜单", 12, C.muted)
    self.menu_rows = {}
    for i, item in ipairs(self.config.items) do
        local y = 74 + (i - 1) * 104
        local item_index = i
        local row = box(self.menu_page, 40, y, 944, 92, C.row, 14, C.border)
        local open = function() self:_open(item_index) end
        row:set_on_click(open)
        local accent = box(row, 0, 0, 5, 92, C.accent, 2)
        local index = label(row, 24, 28, 40, 34, string.format("%02d", i), 20, C.dim)
        local title = label(row, 76, 16, 400, 30, item.title, 23, C.text)
        local desc = label(row, 76, 50, 400, 18, item.desc, 13, C.muted)
        local value = label(row, 540, 12, 370, 40, "", 28, C.text,
            airui.TEXT_ALIGN_RIGHT)
        local unit = label(row, 540, 58, 370, 18, item.unit, 12, C.muted,
            airui.TEXT_ALIGN_RIGHT)
        index:set_on_click(open)
        title:set_on_click(open)
        desc:set_on_click(open)
        value:set_on_click(open)
        unit:set_on_click(open)
        accent:set_hidden(true)
        self.menu_rows[i] = {
            box = row, accent = accent, index = index,
            title = title, desc = desc, value = value, unit = unit
        }
    end

    -- 三级页面：位数编辑
    self.edit_page = box(self.main, 0, 92, 1024, 384, C.bg)
    self.edit_title = label(self.edit_page, 40, 20, 520, 36, "", 26, C.text)
    self.edit_desc = label(self.edit_page, 40, 58, 520, 18, "", 13, C.muted)
    self.saved_label = label(self.edit_page, 640, 22, 344, 18, "", 13, C.muted,
        airui.TEXT_ALIGN_RIGHT)

    self.cells = {}
    self.cell_labels = {}
    self.cell_bars = {}
    self.cell_pos = {}
    for i = 1, 6 do
        local cell = box(self.edit_page, 0, 104, CELL_W, CELL_H, C.row, 12, C.border)
        local bar = box(cell, 32, 8, 32, 4, C.accent, 2)
        local digit = label(cell, 0, 20, CELL_W, 82, "0", 62, C.text,
            airui.TEXT_ALIGN_CENTER)
        local pos = label(cell, 0, 102, CELL_W, 14, tostring(i), 12, C.dim,
            airui.TEXT_ALIGN_CENTER)
        bar:set_hidden(true)
        cell:set_hidden(true)
        self.cells[i] = cell
        self.cell_labels[i] = digit
        self.cell_bars[i] = bar
        self.cell_pos[i] = pos
    end
    self.dot = label(self.edit_page, 0, 136, DOT_W, 52, "", 48, C.muted,
        airui.TEXT_ALIGN_CENTER)

    self.position_label = label(self.edit_page, 40, 238, 320, 20, "", 14, C.text)
    self.preview_label = label(self.edit_page, 340, 234, 644, 28, "", 20, C.amber,
        airui.TEXT_ALIGN_RIGHT)
    box(self.edit_page, 40, 270, 944, 1, C.border)
    label(self.edit_page, 40, 288, 940, 18, "下键：切换位数（最后一位后回到第 1 位）",
        13, C.muted)
    label(self.edit_page, 40, 314, 940, 18, "上键：当前位数字 0-9 循环",
        13, C.muted)
    label(self.edit_page, 40, 340, 940, 18,
        "确认：保存并返回    取消：返回并询问是否保存", 13, C.muted)

    -- 底部独立按键栏
    box(self.main, 0, 476, 1024, 124, C.bottom)
    box(self.main, 0, 476, 1024, 1, C.border)
    self.status_label = label(self.main, 40, 488, 500, 16,
        "主菜单 · 按确认进入参数设置", 12, C.muted)
    self.key_hint = label(self.main, 560, 488, 424, 16,
        "确认进入参数设置", 12, C.muted, airui.TEXT_ALIGN_RIGHT)

    self.key_up = self:_key_button("up", "上", 40)
    self.key_down = self:_key_button("down", "下", 286)
    self.key_confirm = self:_key_button("confirm", "确认", 532)
    self.key_cancel = self:_key_button("cancel", "取消", 778)

    -- 取消时弹出“是否保存设置”
    self.modal = box(self.main, 0, 92, 1024, 384, 0x000000, 0, nil, 170)
    local panel = box(self.modal, 232, 16, 560, 320, C.panel, 18, C.border_sel)
    label(panel, 40, 24, 480, 36, "是否保存设置？", 26, C.text)
    label(panel, 40, 66, 480, 20, "取消返回前，请确认是否保存本次修改", 13, C.muted)
    self.dialog_value = label(panel, 40, 96, 480, 30, "", 20, C.amber)

    self.dialog_options = {}
    for i = 1, 2 do
        local y = 144 + (i - 1) * 62
        local option = box(panel, 40, y, 480, 52, C.row, 10, C.border)
        local choose = function() self:_dialog_click(i) end
        option:set_on_click(choose)
        local bar = box(option, 0, 0, 4, 52, C.accent, 2)
        local text = label(option, 20, 14, 440, 24,
            i == 1 and "保存并返回" or "不保存返回", 18, C.muted)
        text:set_on_click(choose)
        bar:set_hidden(true)
        self.dialog_options[i] = { box = option, bar = bar, text = text }
    end
    label(panel, 40, 272, 480, 18,
        "上 / 下 切换 · 确认选择 · 取消不保存返回", 12, C.muted,
        airui.TEXT_ALIGN_CENTER)
    self.modal:set_hidden(true)

    self.menu_page:set_hidden(true)
    self.edit_page:set_hidden(true)
end

function UI:_key_button(kind, text, x)
    return airui.button({
        parent = self.main,
        x = x, y = 512, w = 206, h = 68,
        text = text, font = "hzfont", font_size = 24,
        style = KEY_STYLE[kind],
        on_click = function() self:_key(kind) end
    })
end

function UI:_text(key, widget, value)
    if self.cache[key] ~= value then
        widget:set_text(value)
        self.cache[key] = value
    end
end

function UI:_color(key, widget, value)
    if self.cache[key] ~= value then
        widget:set_color(value)
        self.cache[key] = value
    end
end

function UI:_open(index)
    if self.model:open_item(index) then
        self:render(self.model:snapshot())
    end
end

function UI:_dialog_click(choice)
    if self.model:choose_dialog(choice) then
        self:render(self.model:snapshot())
    end
end

function UI:_key(kind)
    if kind == "up" then
        self.model:up()
    elseif kind == "down" then
        self.model:down()
    elseif kind == "confirm" then
        self.model:confirm()
    else
        self.model:cancel()
    end
    self:render(self.model:snapshot())
end

function UI:_render_edit(s)
    self:_text("edit_title", self.edit_title, s.title)
    self:_text("edit_desc", self.edit_desc, s.desc)
    self:_text("edit_saved", self.saved_label, "当前保存值 " .. s.saved_text)
    self:_text("edit_pos", self.position_label,
        string.format("第 %d / %d 位", s.cursor, s.digit_count))
    local preview = "新值  " .. s.preview_text
    if s.unit and s.unit ~= "" then preview = preview .. "  " .. s.unit end
    self:_text("edit_preview", self.preview_label, preview)

    local layout_key = s.digit_count .. ":" .. s.decimal
    if self.cache.edit_layout ~= layout_key then
        local n = s.digit_count
        local total = n * CELL_W + (n - 1) * CELL_GAP
        if s.decimal > 0 then total = total + DOT_W + CELL_GAP end
        local x = math.floor((1024 - total) / 2)
        local split = n - s.decimal
        for i = 1, 6 do
            if i > n then
                self.cells[i]:set_hidden(true)
            else
                if s.decimal > 0 and i == split + 1 then
                    self.dot:set_pos(x, 136)
                    x = x + DOT_W + CELL_GAP
                end
                self.cells[i]:set_pos(x, 104)
                self.cells[i]:set_hidden(false)
                x = x + CELL_W + CELL_GAP
            end
        end
        self.dot:set_text(s.decimal > 0 and "." or "")
        self.cache.edit_layout = layout_key
    end

    for i = 1, s.digit_count do
        self:_text("digit_" .. i, self.cell_labels[i], s.digit_texts[i] or "0")
        local active = (i == s.cursor)
        local style = active and "1" or "0"
        if self.cell_style[i] ~= style then
            self.cells[i]:set_color(active and C.row_sel or C.row)
            self.cells[i]:set_border_color(active and C.accent or C.border, active and 2 or 1)
            self.cell_bars[i]:set_hidden(not active)
            self.cell_labels[i]:set_color(active and C.text or C.soft)
            self.cell_pos[i]:set_color(active and C.accent or C.dim)
            self.cell_style[i] = style
        end
    end
end

function UI:render(s)
    if self.cache.screen ~= s.screen then
        self.home_page:set_hidden(s.screen ~= "home")
        self.menu_page:set_hidden(s.screen ~= "menu")
        self.edit_page:set_hidden(s.screen ~= "edit" and s.screen ~= "confirm")
        self.modal:set_hidden(s.screen ~= "confirm")
        self.cache.screen = s.screen
    end

    -- 一级主菜单数据
    self:_text("home_fare", self.home_fare, s.fare_text)

    -- 二级页面列表
    local menu_values = { s.vehicle_text, s.fare_text, s.warning_text }
    for i, row in ipairs(self.menu_rows) do
        self:_text("menu_value_" .. i, row.value, menu_values[i])
        local selected = (i == s.selected)
        local style = selected and "1" or "0"
        if self.menu_style[i] ~= style then
            row.box:set_color(selected and C.row_sel or C.row)
            row.box:set_border_color(selected and C.border_sel or C.border, 1)
            row.accent:set_hidden(not selected)
            row.index:set_color(selected and C.accent or C.dim)
            row.title:set_color(selected and C.text or C.soft)
            row.value:set_color(selected and C.text or C.soft)
            self.menu_style[i] = style
        end
    end

    if s.screen == "edit" or s.screen == "confirm" then
        self:_render_edit(s)
    end

    if s.screen == "confirm" then
        local unit = s.unit and s.unit ~= "" and ("  " .. s.unit) or ""
        self:_text("dialog_value", self.dialog_value, "新值  " .. s.preview_text .. unit)
        for i, option in ipairs(self.dialog_options) do
            local selected = (i == s.dialog_choice)
            if self.dialog_style[i] ~= selected then
                option.box:set_color(selected and C.row_sel or C.row)
                option.box:set_border_color(selected and C.accent or C.border,
                    selected and 2 or 1)
                option.bar:set_hidden(not selected)
                option.text:set_color(selected and C.text or C.muted)
                self.dialog_style[i] = selected
            end
        end
    end

    self:_text("status", self.status_label, s.status_text)
    self:_color("status_color", self.status_label,
        s.status_kind == "ok" and C.green
        or (s.status_kind == "warn" and C.amber or C.muted))

    local hint = "确认进入参数设置"
    if s.screen == "menu" then
        hint = "上 / 下 选择 · 确认进入 · 取消返回"
    elseif s.screen == "edit" then
        hint = "下 换位 · 上 改数 · 确认保存"
    elseif s.screen == "confirm" then
        hint = "上 / 下 切换 · 确认选择 · 取消不保存返回"
    end
    self:_text("key_hint", self.key_hint, hint)
end

return UI
