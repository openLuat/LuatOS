-- 公交车投币系统状态机：
--   home    : 一级主菜单，只居中显示当前票价
--   menu    : 二级页面，选择车辆编号/票价单价/满胆预警
--   edit    : 三级页面，下键换位，上键改数
--   confirm : 取消返回时的“是否保存”弹窗
local M = {}
M.__index = M

function M.format(key, value)
    if key == "vehicle" then
        return string.format("%05d", value)
    elseif key == "fare" then
        return string.format("%03d.%02d", math.floor(value / 100), value % 100)
    end
    return string.format("%04d.%02d", math.floor(value / 100), value % 100)
end

local function digits_to_value(item, digits)
    local value = 0
    for i = 1, item.digits do
        value = value * 10 + digits[i]
    end
    return value
end

function M.new(config, store)
    local self = setmetatable({
        config = config,
        store = store,
        items = config.items,
        selected = 1,
        screen = "home",
        edit_index = nil,
        digits = {},
        cursor = 1,
        dialog_choice = 2,
        status = { text = "主菜单 · 按确认进入参数设置", kind = "info" }
    }, M)

    store.init()
    local values = {}
    for _, item in ipairs(config.items) do
        local saved = store.load_number("bus_" .. item.key, config.defaults[item.key])
        values[item.key] = math.floor(saved + 0.5)
    end
    self.values = values
    return self
end

function M:edit_item()
    return self.items[self.edit_index]
end

function M:enter_home()
    self.screen = "home"
    self.status = { text = "主菜单 · 按确认进入参数设置", kind = "info" }
end

function M:enter_menu()
    self.screen = "menu"
    self.status = { text = "参数设置 · 上 / 下选择功能", kind = "info" }
end

function M:select(delta)
    self.selected = ((self.selected - 1 + delta) % #self.items) + 1
    local item = self.items[self.selected]
    self.status = {
        text = "已选择「" .. item.title .. "」· 按确认进入",
        kind = "info"
    }
end

function M:enter_edit(index)
    self.selected = index or self.selected
    self.edit_index = self.selected
    self.screen = "edit"
    self.cursor = 1
    self.digits = {}
    local item = self:edit_item()
    for i = 1, item.digits do self.digits[i] = 0 end
    self.status = {
        text = "编辑中 · 下键换位，上键改数",
        kind = "warn"
    }
end

function M:adjust_digit()
    self.digits[self.cursor] = (self.digits[self.cursor] + 1) % 10
    self.status = {
        text = string.format("第 %d 位 = %d", self.cursor, self.digits[self.cursor]),
        kind = "warn"
    }
end

function M:next_digit()
    local item = self:edit_item()
    self.cursor = self.cursor % item.digits + 1
    self.status = {
        text = string.format("第 %d / %d 位", self.cursor, item.digits),
        kind = "info"
    }
end

function M:digits_text()
    local item = self:edit_item()
    local text = ""
    for i = 1, item.digits do
        text = text .. tostring(self.digits[i])
        if item.decimal > 0 and i == item.digits - item.decimal then
            text = text .. "."
        end
    end
    return text
end

function M:save_current()
    local item = self:edit_item()
    local value = digits_to_value(item, self.digits)
    self.values[item.key] = value
    self.store.save_number("bus_" .. item.key, value)
    self.edit_index = nil
    self.screen = "menu"
    self.status = {
        text = "已保存 · " .. item.title .. " " .. M.format(item.key, value),
        kind = "ok"
    }
end

function M:discard_current()
    local item = self:edit_item()
    self.edit_index = nil
    self.screen = "menu"
    self.status = {
        text = "已取消 · " .. item.title .. " 未保存",
        kind = "info"
    }
end

function M:toggle_dialog()
    self.dialog_choice = self.dialog_choice == 1 and 2 or 1
end

function M:up()
    if self.screen == "menu" then
        self:select(-1)
    elseif self.screen == "edit" then
        self:adjust_digit()
    elseif self.screen == "confirm" then
        self:toggle_dialog()
    end
end

function M:down()
    if self.screen == "menu" then
        self:select(1)
    elseif self.screen == "edit" then
        self:next_digit()
    elseif self.screen == "confirm" then
        self:toggle_dialog()
    end
end

function M:confirm()
    if self.screen == "home" then
        self:enter_menu()
    elseif self.screen == "menu" then
        self:enter_edit(self.selected)
    elseif self.screen == "edit" then
        self:save_current()
    elseif self.dialog_choice == 1 then
        self:save_current()
    else
        self:discard_current()
    end
end

function M:cancel()
    if self.screen == "edit" then
        self.screen = "confirm"
        self.dialog_choice = 2
        self.status = { text = "是否保存设置？", kind = "warn" }
    elseif self.screen == "confirm" then
        self:discard_current()
    elseif self.screen == "menu" then
        self:enter_home()
        self.status = { text = "已返回主菜单", kind = "info" }
    else
        self.status = { text = "已在一级主菜单", kind = "info" }
    end
end

-- 二级页面点击某一项时直接进入三级编辑页面。
function M:open_item(index)
    if self.screen == "menu" then
        self:enter_edit(index)
        return true
    end
    return false
end

-- 弹窗中点击选项时直接执行选择。
function M:choose_dialog(choice)
    if self.screen == "confirm" then
        self.dialog_choice = choice
        self:confirm()
        return true
    end
    return false
end

function M:snapshot()
    local item = self.edit_index and self.items[self.edit_index] or nil
    local digit_texts = {}
    if item then
        for i = 1, item.digits do digit_texts[i] = tostring(self.digits[i]) end
    end

    return {
        screen = self.screen,
        selected = self.selected,
        edit_index = self.edit_index,
        title = item and item.title or nil,
        page_title = item and item.title or (self.screen == "home" and "运行概览" or "参数设置"),
        desc = item and item.desc or nil,
        unit = item and item.unit or nil,
        digit_count = item and item.digits or 0,
        decimal = item and item.decimal or 0,
        cursor = self.cursor,
        digit_texts = digit_texts,
        preview_text = item and self:digits_text() or "",
        saved_text = item and M.format(item.key, self.values[item.key]) or "",
        vehicle_text = M.format("vehicle", self.values.vehicle),
        fare_text = M.format("fare", self.values.fare),
        warning_text = M.format("warning", self.values.warning),
        dialog_choice = self.dialog_choice,
        status_text = self.status.text,
        status_kind = self.status.kind
    }
end

return M
