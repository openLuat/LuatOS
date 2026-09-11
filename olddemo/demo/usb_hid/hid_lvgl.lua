-- Lua creates the real screen; USB HID still enters LVGL through the C input adapter.
local ui = {}
local clicks = 0

ui.background = airui.container({
    x = 0,
    y = 0,
    w = 1024,
    h = 600,
    color = 0xF0F4F8
})
ui.title = airui.label({
    x = 24,
    y = 16,
    w = 960,
    h = 40,
    font_size = 28,
    color = 0x17324D,
    text = "USB 鼠标 / 键盘测试"
})
ui.help = airui.label({
    x = 24,
    y = 62,
    w = 976,
    h = 56,
    font_size = 20,
    color = 0x425466,
    text = "输入 abc、Shift+A、Backspace；Tab 切换焦点，Enter 点击按钮。\n移动鼠标，点击按钮；在右侧列表上滚动滚轮。"
})

-- Create the textarea first so the default keyboard group initially focuses it.
ui.textarea = airui.textarea({
    x = 24,
    y = 138,
    w = 540,
    h = 132,
    max_len = 64,
    text = "",
    placeholder = "请在这里输入",
    font_size = 24,
    on_text_change = function(self)
        local text = self:get_text()
        log.info("hid_lvgl", "TEXT", text)
        if ui.echo then
            ui.echo:set_text("输入内容：" .. text)
        end
    end
})
ui.echo = airui.label({
    x = 24,
    y = 284,
    w = 540,
    h = 80,
    font_size = 22,
    color = 0x17324D,
    text = "输入内容："
})
ui.button = airui.button({
    x = 24,
    y = 384,
    w = 540,
    h = 92,
    text = "点击测试",
    font_size = 26,
    style = {
        bg_color = 0x1976D2,
        text_color = 0xFFFFFF,
        focus_outline_color = 0xFF9800,
        focus_outline_width = 4
    },
    on_click = function()
        clicks = clicks + 1
        ui.counter:set_text("点击次数：" .. clicks)
        log.info("hid_lvgl", "CLICKED", clicks)
    end
})
ui.counter = airui.label({
    x = 24,
    y = 504,
    w = 540,
    h = 44,
    font_size = 24,
    color = 0x17324D,
    text = "点击次数：0"
})

local rows = {}
for i = 1, 24 do
    rows[i] = {string.format("滚动测试 %02d", i)}
end
ui.list = airui.table({
    x = 600,
    y = 138,
    w = 400,
    h = 410,
    rows = #rows,
    cols = 1,
    data = rows,
    col_width = {380},
    row_height = 48,
    on_click = function(_, row, col, value)
        log.info("hid_lvgl", "ROW", row, col, value)
    end
})
ui.footer = airui.label({
    x = 24,
    y = 564,
    w = 976,
    h = 30,
    font_size = 18,
    color = 0x425466,
    text = "黑色白边圆点为鼠标光标；滚动列表不应增加左侧点击次数。"
})

log.info("hid_lvgl", "HID_LUA_LVGL_READY", lcd.getSize())
return ui
