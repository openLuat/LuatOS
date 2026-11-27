-- 厂测桌面：左栏菜单 + 时钟 + 主题。
local theme = require "ui_theme"
local board = require "air8801_board"
local touch = require "air8801_touch"
local window_id, root, rail, active
local lights = {}
local time_label, date_label, clock_label
local time, date, weekday = "--:--", "--", "--"
local mark_theme_dirty, take_theme_dirty = theme.dirty_flag()

local entries = {
    {"设置", "SETTINGS", "settings"},
    {"文件管理", "FILE_MANAGER", "file"},
    {"功能测试", "OTHER_FUNC", "other_func"},
}

local function select_menu(menu)
    active = menu
    for key, light in pairs(lights) do light:set_hidden(key ~= (active or "HOME")) end
end

local function open_menu(menu)
    local leaf = exwin.children_of(window_id)[1]
    if active == menu and leaf then
        exwin.close_children_of(leaf)
        return
    end
    exwin.begin_menu_switch(window_id)
    select_menu(menu)
    sys.publish("OPEN_" .. menu .. "_WIN")
end

local function go_home()
    exwin.close_children_of(window_id)
end

local function refresh_clock(new_time, new_date, new_weekday)
    time, date, weekday = new_time or time, new_date or date, new_weekday or weekday
    if time_label then time_label:set_text(time) end
    if clock_label then clock_label:set_text(time) end
    if date_label then date_label:set_text(weekday .. " | " .. date) end
end

--[[触摸校准：标定页是直接画在 airui.screen 上的全屏 panel，不是 exwin 窗口，
所以它不进 entries、不参与左栏选中态。电容屏没有标定概念，整项不显示。
标定一旦开始必须点完四个十字（tp.calibration 没有取消接口），所以先确认再进。]]
local function open_calibration()
    if not (touch.resistive() and touch.ready()) then return end
    airui.msgbox({
        title = "触摸校准",
        text = "将用四点重新标定并覆盖现有系数。\n开始后必须依次按住四个十字并松手，中途无法退出。",
        buttons = {"取消", "开始"},
        on_action = function(dialog, chosen)
            dialog:destroy()
            if chosen ~= "开始" then return end
            local ok, reason = require("air8801_touch_cal").open()
            if not ok then log.warn("idle_win", "CAL_START_FAILED", reason) end
        end,
    })
end

local function build_rail()
    local rw, h = theme.shell.rail_w, screen_h
    if rail then rail:destroy() end
    lights = {}
    rail = theme.box(root, {x = 0, y = 0, w = rw, h = h, color = theme.C.rail_bg, opa = theme.OPA.rail})
    local pad, bs = theme.page_margin(), math.min(44, rw // 2)
    local brand = theme.card(rail, {x = (rw - bs) // 2, y = pad, w = bs, h = bs,
        color = theme.C.amber, opa = 255, border_w = 0})
    theme.image(brand, {icon = "brand", x = bs // 4, y = bs // 4, w = bs // 2, h = bs // 2})
    local ih, iw, gap = theme.dp(52), rw * 4 // 5, theme.dp(6)
    local function rail_item(name, key, icon, y, on_click)
        -- 所有左栏项统一在点击瞬间"嘀"一声，做成出厂演示的触感反馈
        local item = theme.card(rail, {x = (rw - iw) // 2, y = y, w = iw, h = ih, opa = 0,
            border_w = 0, on_click = function()
                board.beep(30)
                on_click()
            end})
        lights[key] = theme.box(item, {x = 0, y = 0, w = iw, h = ih, color = theme.C.amber,
            opa = theme.OPA.rail_active, radius = theme.R.md})
        local isz = ih * 36 // 100
        theme.image(item, {icon = icon, x = (iw - isz) // 2, y = ih * 18 // 100, w = isz, h = isz})
        local ty = ih * 56 // 100
        theme.label(item, {x = 0, y = ty, w = iw, h = ih - ty, text = name, px_size = theme.fs("caption"),
            color = theme.C.t2, align = airui.TEXT_ALIGN_CENTER})
    end
    for i, entry in ipairs(entries) do
        local name, key, icon = table.unpack(entry)
        rail_item(name, key, icon, pad * 2 + bs + (i - 1) * (ih + gap), function() open_menu(key) end)
    end
    -- 电阻屏才有标定概念，电容屏整项不出现，避免点了只回 NOT_RESISTIVE
    if touch.resistive() then
        rail_item("触摸校准", "CAL", "mouse", pad * 2 + bs + #entries * (ih + gap), open_calibration)
    end
    rail_item("桌面", "HOME", "desktop", h - pad - ih, go_home)
    select_menu(active)
end

local function build()
    local w, h = screen_w, screen_h
    local pad = theme.page_margin()
    local rw = math.max(80, math.min(w * 18 // 100, theme.dp(104)))
    theme.shell.enabled, theme.shell.rail_w = true, rw
    root = theme.page_bg(airui.screen, w, h, 0, 0)
    theme.bind_root(root, {keep_visible = true})
    build_rail()

    local x, cw = rw + pad, w - rw - 2 * pad
    local status_h = theme.dp(30)
    local chip_name = _G.project_config.name
    theme.label(root, {x = x, y = pad, w = cw - theme.dp(70), h = status_h,
        text = chip_name .. "  |  " .. VERSION, color = theme.C.t2})
    time_label = theme.label(root, {x = x + cw - theme.dp(70), y = pad, w = theme.dp(70), h = status_h,
        align = airui.TEXT_ALIGN_RIGHT})

    local cy, ch = pad + status_h + pad, theme.dp(128)
    local clock = theme.card(root, {x = x, y = cy, w = cw, h = ch})
    clock_label = theme.label(clock, {x = pad, y = pad, w = cw - 2 * pad, h = theme.dp(68), px_size = theme.dp(54)})
    date_label = theme.label(clock, {x = pad, y = theme.dp(82), w = cw - 2 * pad, h = theme.dp(27), color = theme.C.t2})
    refresh_clock()

    local y = cy + ch + pad
    local card = theme.card(root, {x = x, y = y, w = cw, h = h - y - pad})
    theme.section(card, {x = pad, y = pad, w = cw - 2 * pad, h = theme.dp(24), text = "出厂检测", color = theme.C.t2})
    theme.row(card, {x = pad, y = pad + theme.dp(33), w = cw - 2 * pad, h = theme.dp(65),
        icon = "other_func", text = "功能测试", sub = "蜂鸣器、存储与触摸校准",
        bg = theme.C.surface, opa = theme.OPA.fill, border = theme.C.stroke,
        on_click = function() open_menu("OTHER_FUNC") end})
end

local function destroy_root()
    if root then root:destroy() end
    root, rail, time_label, clock_label, date_label = nil, nil, nil, nil, nil
    lights = {}
end

local function open()
    if window_id then return end
    window_id = exwin.open({
        owner = false,
        on_create = function()
            build()
            sys.subscribe("STATUS_TIME_UPDATED", refresh_clock)
            sys.publish("REQUEST_STATUS_REFRESH")
        end,
        on_get_focus = function()
            active = nil
            if take_theme_dirty() then
                destroy_root()
                build()
            else
                select_menu(nil)
            end
        end,
        on_destroy = function()
            sys.unsubscribe("STATUS_TIME_UPDATED", refresh_clock)
            destroy_root()
            window_id, active = nil, nil
            theme.shell.host_id = nil
        end,
    })
    theme.shell.host_id = window_id
end

sys.subscribe("UI_THEME_CHANGED", function()
    mark_theme_dirty()
    if root then
        sys.timerStart(function()
            if root then build_rail() end
        end, 40)
    end
end)
sys.subscribe("OPEN_IDLE_WIN", open)

