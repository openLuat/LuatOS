-- 广东铁路中控系统 · 1024 x 600
-- 一级页面：运行总览；二级页面：广州南站站场信号平面布置图。
-- 站场图全部用 container 绘制，不加载底图，只更新区段颜色、信号颜色和列车位置。
local UI = {}
UI.__index = UI

local C = {
    bg          = 0x07121A,
    top         = 0x0B1B26,
    side        = 0x091620,
    panel       = 0x0F202C,
    panel2      = 0x122733,
    row         = 0x0D1C27,
    row_sel     = 0x143241,
    border      = 0x203B4B,
    border_sel  = 0x2D7186,
    text        = 0xEAF5FB,
    soft        = 0xB9CBD6,
    muted       = 0x8AA3B5,
    dim         = 0x60798B,
    accent      = 0x39C6DA,
    green       = 0x35D6A0,
    green_bg    = 0x0D3229,
    green_border= 0x1D5A48,
    amber       = 0xF3B54A,
    amber_bg    = 0x3A2A12,
    amber_border= 0x6B4D1F,
    red         = 0xFF5D6C,
    red_bg      = 0x3A1620,
    red_border  = 0x7A2C3A,
    purple      = 0xA98EFF,
    cyan        = 0x39C6DA,
    blue        = 0x3C7BFF,
    pink        = 0xF06AA6,
    pink_bg     = 0x5A2440,
    pink_border = 0xA84370,
    map_bg      = 0x0B1721,
    logo_bg     = 0x123647
}

local MAP_W, MAP_H = 776, 394
-- 还原“中间站信号设备平面布置图”：5G / 3G / IG / IIG / 4G 五条股道。
local PLATFORM_X1, PLATFORM_X2 = 350, 450
local LEFT_ENTRY_X, RIGHT_EXIT_X = 40, 730
local CARD_Y, CARD_W, CARD_H = 302, 146, 44
local LINE_SIZE = 128
local LINE_CYAN = "/luadb/line_cyan_128.png"
local LINE_GREEN = "/luadb/line_green_128.png"
local DWELL_TIME, ARRIVE_TIME, DEPART_TIME = 30, 3, 4

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

local function round(v)
    return math.floor(v + 0.5)
end

-- 用一张 128×128 的透明线段贴图绘制任意角度的股道；只缓存两张小图，
-- 不加载站场底图，内存占用远低于整屏图片。
local function line_image(parent, x1, y1, x2, y2, src, hidden)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 2 then return nil, 0 end
    local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    local rotation = round(math.atan(dy, dx) * 1800 / math.pi) % 3600
    if rotation < 0 then rotation = rotation + 3600 end
    local zoom = round(length / LINE_SIZE * 256)
    if zoom < 1 then zoom = 1 end
    local image = airui.image({
        parent = parent,
        x = round(cx - LINE_SIZE / 2), y = round(cy - LINE_SIZE / 2),
        w = LINE_SIZE, h = LINE_SIZE,
        src = src, fit = "center",
        pivot = { x = LINE_SIZE / 2, y = LINE_SIZE / 2 },
        zoom = zoom, rotation = rotation
    })
    image:set_pivot(LINE_SIZE / 2, LINE_SIZE / 2)
    image:set_rotation(rotation)
    image:set_zoom(zoom)
    if hidden then image:set_opacity(0) end
    return image, length
end

local function hline(parent, x1, x2, y, color, thickness, hidden)
    local h = thickness or 3
    local line = box(parent, x1, round(y - h / 2), x2 - x1, h, color, 1)
    if hidden then line:set_hidden(true) end
    return line
end

local function node(parent, x, y, size, color)
    return box(parent, round(x - size / 2), round(y - size / 2), size, size, color,
        math.floor(size / 2))
end

local function seg(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return {
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        length = math.sqrt(dx * dx + dy * dy)
    }
end

local function path_length(path)
    local total = 0
    for _, s in ipairs(path) do total = total + s.length end
    return total
end

local function point_on_path(path, distance)
    if distance <= 0 then
        local first = path[1]
        return first.x1, first.y1
    end
    for _, s in ipairs(path) do
        if distance <= s.length then
            local t = s.length > 0 and distance / s.length or 0
            return s.x1 + (s.x2 - s.x1) * t, s.y1 + (s.y2 - s.y1) * t
        end
        distance = distance - s.length
    end
    local last = path[#path]
    return last.x2, last.y2
end

local function reverse_path(path)
    local out = {}
    for i = #path, 1, -1 do
        local s = path[i]
        out[#out + 1] = seg(s.x2, s.y2, s.x1, s.y1)
    end
    return out
end

local function draw_green_path(parent, path)
    local overlays = {}
    for _, s in ipairs(path) do
        if s.y1 == s.y2 then
            overlays[#overlays + 1] = {
                box = hline(parent, s.x1, s.x2, s.y1, C.green, 3, true)
            }
        else
            overlays[#overlays + 1] = {
                image = line_image(parent, s.x1, s.y1, s.x2, s.y2, LINE_GREEN, true)
            }
        end
    end
    return overlays
end

local function set_path_visible(path, visible)
    for _, item in ipairs(path) do
        if item.image then
            item.image:set_opacity(visible and 255 or 0)
        else
            item.box:set_hidden(not visible)
        end
    end
end

function UI.new(model, data, config)
    -- 每次启动随机生成列车方向和站台初始状态。
    if math.randomseed and os and os.time then
        pcall(math.randomseed, os.time())
    end
    local self = setmetatable({
        model = model,
        data = data,
        config = config,
        cache = {},
        page = "home",
        nav_style = {},
        train_row_style = {},
        line_bar_style = {},
        platforms = {},
        _train_serial = 1000,
        _yard_time = nil
    }, UI)
    self:_build()
    self:_update_nav()
    return self
end

function UI:_build()
    self.main = box(nil, 0, 0, self.config.width, self.config.height, C.bg)

    -- 顶部栏
    box(self.main, 0, 0, 1024, 76, C.top)
    box(self.main, 0, 75, 1024, 1, C.border)
    box(self.main, 28, 16, 44, 44, C.logo_bg, 12, C.border)
    label(self.main, 28, 24, 44, 28, "铁", 22, C.accent, airui.TEXT_ALIGN_CENTER)
    label(self.main, 88, 9, 520, 40, "广东铁路中控系统", 28, C.text)
    label(self.main, 90, 47, 520, 16, "GUANGDONG RAILWAY CONTROL CENTER  /  AIR8601",
        12, C.muted)
    self.clock_label = label(self.main, 724, 12, 130, 30, "10:42:00", 22, C.text,
        airui.TEXT_ALIGN_RIGHT)
    label(self.main, 724, 44, 130, 16, self.config.simulated_date, 12, C.muted,
        airui.TEXT_ALIGN_RIGHT)
    self.status_pill = box(self.main, 880, 22, 116, 32, C.green_bg, 16, C.green_border)
    self.status_dot = box(self.main, 892, 34, 8, 8, C.green, 4)
    self.status_text = label(self.main, 908, 29, 80, 18, "调度正常", 12, C.green)

    -- 左侧导航
    box(self.main, 0, 76, 196, 524, C.side)
    box(self.main, 195, 76, 1, 524, C.border)
    label(self.main, 24, 94, 140, 16, "功能导航", 12, C.muted)
    self.navs = {
        home = self:_nav_item("home", "01", "运行总览", "实时运行数据", 118),
        map = self:_nav_item("map", "02", "站场图", "信号平面布置", 188)
    }
    box(self.main, 24, 270, 148, 1, C.border)
    label(self.main, 24, 288, 148, 16, "实时状态", 12, C.muted)
    label(self.main, 24, 316, 96, 18, "在线列车", 12, C.muted)
    self.side_online = label(self.main, 118, 310, 54, 26, "0", 20, C.text,
        airui.TEXT_ALIGN_RIGHT)
    label(self.main, 24, 348, 96, 18, "线路占用", 12, C.muted)
    self.side_occ = label(self.main, 118, 342, 54, 26, "0%", 20, C.amber,
        airui.TEXT_ALIGN_RIGHT)
    label(self.main, 24, 380, 96, 18, "当前告警", 12, C.muted)
    self.side_alerts = label(self.main, 118, 374, 54, 26, "0", 20, C.red,
        airui.TEXT_ALIGN_RIGHT)
    label(self.main, 24, 412, 96, 18, "今日客流", 12, C.muted)
    self.side_flow = label(self.main, 108, 408, 64, 22, "0.0万", 16, C.green,
        airui.TEXT_ALIGN_RIGHT)

    local mode_card = box(self.main, 14, 454, 168, 66, C.panel, 10, C.border)
    label(mode_card, 14, 10, 140, 16, "调度模式", 12, C.muted)
    label(mode_card, 14, 34, 140, 20, "自动 · 正常", 14, C.green)
    label(self.main, 24, 542, 148, 16, "模拟数据 · 仅界面演示", 12, C.dim)

    -- 一级页面：运行总览
    self.home_page = box(self.main, 196, 76, 828, 524, C.bg)
    label(self.home_page, 28, 16, 360, 30, "运行总览", 24, C.text)
    label(self.home_page, 28, 48, 560, 18,
        "广东铁路实时运行监控 · 模拟数据自动刷新", 12, C.muted)
    label(self.home_page, 560, 18, 248, 18, "刷新周期 120 ms", 12, C.dim,
        airui.TEXT_ALIGN_RIGHT)

    local metric_titles = { "在线列车", "准点率", "平均速度", "线路占用" }
    local metric_units = { "列", "%", "km/h", "%" }
    self.metrics = {}
    for i = 1, 4 do
        local x = 20 + (i - 1) * 202
        local card = box(self.home_page, x, 76, 186, 96, C.panel, 12, C.border)
        box(card, 0, 0, 186, 4, i == 1 and C.accent or (i == 2 and C.green or (i == 3 and C.amber or C.purple)), 2)
        label(card, 16, 12, 120, 16, metric_titles[i], 12, C.muted)
        self.metrics[i] = label(card, 16, 32, 104, 40, "0", 28,
            i == 1 and C.text or (i == 2 and C.green or (i == 3 and C.amber or C.purple)))
        label(card, 122, 48, 52, 18, metric_units[i], 12, C.muted,
            airui.TEXT_ALIGN_RIGHT)
    end

    local train_panel = box(self.home_page, 20, 190, 480, 210, C.panel, 12, C.border)
    label(train_panel, 18, 12, 240, 20, "列车运行", 16, C.text)
    label(train_panel, 330, 14, 130, 16, "实时位置", 12, C.dim,
        airui.TEXT_ALIGN_RIGHT)
    self.train_rows = {}
    for i = 1, 4 do
        local y = 44 + (i - 1) * 38
        local id = label(train_panel, 18, y, 64, 24, "", 15, C.accent)
        local route = label(train_panel, 86, y + 2, 190, 20, "", 12, C.soft)
        local status = label(train_panel, 280, y + 2, 84, 20, "", 12, C.green)
        local speed = label(train_panel, 370, y, 90, 24, "", 13, C.text,
            airui.TEXT_ALIGN_RIGHT)
        if i < 4 then box(train_panel, 18, y + 31, 444, 1, C.border) end
        self.train_rows[i] = { id = id, route = route, status = status, speed = speed }
    end

    local load_panel = box(self.home_page, 516, 190, 296, 210, C.panel, 12, C.border)
    label(load_panel, 18, 12, 200, 20, "线路负载", 16, C.text)
    self.line_rows = {}
    for i = 1, 5 do
        local y = 46 + (i - 1) * 32
        local name = label(load_panel, 18, y, 90, 18, "", 12, C.soft)
        local segments = {}
        for j = 1, 10 do
            segments[j] = box(load_panel, 110 + (j - 1) * 11, y + 5, 8, 8, C.row, 2)
        end
        local percent = label(load_panel, 226, y, 52, 18, "0%", 12, C.muted,
            airui.TEXT_ALIGN_RIGHT)
        self.line_rows[i] = { name = name, segments = segments, percent = percent }
    end

    local alert_panel = box(self.home_page, 20, 412, 792, 76, C.panel, 12, C.border)
    box(alert_panel, 0, 0, 5, 76, C.red, 2)
    label(alert_panel, 18, 10, 200, 18, "实时告警", 14, C.text)
    self.alert_count = label(alert_panel, 690, 10, 84, 18, "0 条", 12, C.red,
        airui.TEXT_ALIGN_RIGHT)
    self.alert1 = label(alert_panel, 18, 34, 756, 16, "", 12, C.amber)
    self.alert2 = label(alert_panel, 18, 54, 756, 16, "", 12, C.muted)

    -- 二级页面：还原中间站五股道信号平面布置图，并叠加站台管理/列车指引
    self.map_page = box(self.main, 196, 76, 828, 524, C.bg)
    label(self.map_page, 28, 16, 620, 30, "中间站信号设备平面布置图", 24, C.text)
    label(self.map_page, 28, 48, 760, 18,
        "北京方面 / 广州方面 · 5 股道 · 5 站台 · 列车到发指引 · 停站 30 秒", 12, C.muted)

    box(self.map_page, 28, 73, 18, 4, C.green, 2)
    label(self.map_page, 52, 66, 82, 16, "有车/进路", 12, C.muted)
    box(self.map_page, 150, 73, 18, 4, C.red, 2)
    label(self.map_page, 174, 66, 66, 16, "空闲站台", 12, C.muted)
    box(self.map_page, 258, 73, 18, 4, C.cyan, 2)
    label(self.map_page, 282, 66, 50, 16, "到发线", 12, C.muted)
    box(self.map_page, 350, 70, 16, 10, C.pink, 3)
    label(self.map_page, 372, 66, 40, 16, "列车", 12, C.muted)
    box(self.map_page, 420, 71, 8, 8, C.blue, 4)
    label(self.map_page, 434, 66, 50, 16, "道岔", 12, C.muted)
    box(self.map_page, 494, 71, 8, 8, C.red, 4)
    label(self.map_page, 508, 66, 50, 16, "信号", 12, C.muted)
    label(self.map_page, 636, 66, 160, 16,
        string.format("刷新周期 %d ms", self.config.frame_ms), 12, C.dim,
        airui.TEXT_ALIGN_RIGHT)

    local map_card = box(self.map_page, 20, 96, 792, 410, C.panel, 14, C.border)
    self.map_view = box(map_card, 8, 8, MAP_W, MAP_H, C.map_bg, 10, C.border)
    self:_build_yard()

    self.home_page:set_hidden(false)
    self.map_page:set_hidden(true)
    self:_update_yard()
end

function UI:_nav_item(page, index, title, subtitle, y)
    local item = box(self.main, 14, y, 168, 60, C.row, 10, C.border)
    item:set_on_click(function() self:_switch(page) end)
    local accent = box(item, 0, 0, 4, 60, C.accent, 2)
    local idx = label(item, 18, 18, 30, 24, index, 14, C.dim)
    local title_label = label(item, 54, 12, 100, 22, title, 16, C.text)
    local sub_label = label(item, 54, 34, 100, 16, subtitle, 12, C.muted)
    accent:set_hidden(true)
    idx:set_on_click(function() self:_switch(page) end)
    title_label:set_on_click(function() self:_switch(page) end)
    sub_label:set_on_click(function() self:_switch(page) end)
    return { box = item, accent = accent, index = idx, title = title_label, sub = sub_label }
end

function UI:_update_nav()
    for page, nav in pairs(self.navs) do
        local selected = page == self.page
        if self.nav_style[page] ~= selected then
            nav.box:set_color(selected and C.row_sel or C.row)
            nav.box:set_border_color(selected and C.border_sel or C.border, 1)
            nav.accent:set_hidden(not selected)
            nav.index:set_color(selected and C.accent or C.dim)
            nav.title:set_color(selected and C.text or C.soft)
            nav.sub:set_color(selected and C.accent or C.muted)
            self.nav_style[page] = selected
        end
    end
end

function UI:_switch(page)
    if page == self.page then return end
    self.page = page
    self.home_page:set_hidden(page ~= "home")
    self.map_page:set_hidden(page ~= "map")
    self:_update_nav()
    self:render(self.model:snapshot())
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

function UI:_build_yard()
    local view = self.map_view

    label(view, 8, 8, 120, 14, "← 北京方面", 10, C.cyan)
    label(view, 240, 8, 296, 16, "5 股道 · 5 站台 · 到发指引", 12, C.soft,
        airui.TEXT_ALIGN_CENTER)
    label(view, 640, 8, 128, 14, "广州方面 →", 10, C.cyan,
        airui.TEXT_ALIGN_RIGHT)

    -- 正线和到发线
    hline(view, 40, 730, 160, C.cyan, 3)   -- IG
    hline(view, 40, 730, 200, C.cyan, 3)   -- IIG
    hline(view, 240, 560, 110, C.cyan, 3)  -- 3G
    hline(view, 330, 470, 70, C.cyan, 3)   -- 5G
    hline(view, 230, 520, 240, C.cyan, 3)  -- 4G

    -- 道岔连接线
    line_image(view, 200, 160, 240, 110, LINE_CYAN)
    line_image(view, 560, 110, 600, 160, LINE_CYAN)
    line_image(view, 300, 110, 330, 70, LINE_CYAN)
    line_image(view, 470, 70, 500, 110, LINE_CYAN)
    line_image(view, 190, 200, 230, 240, LINE_CYAN)
    line_image(view, 520, 240, 560, 200, LINE_CYAN)
    line_image(view, 80, 160, 130, 200, LINE_CYAN)
    line_image(view, 640, 160, 690, 200, LINE_CYAN)

    local defs = {
        { name = "5G", y = 70, left = {
            seg(40, 160, 200, 160), seg(200, 160, 240, 110),
            seg(240, 110, 300, 110), seg(300, 110, 330, 70),
            seg(330, 70, 350, 70)
        }, right = {
            seg(450, 70, 470, 70), seg(470, 70, 500, 110),
            seg(500, 110, 560, 110), seg(560, 110, 600, 160),
            seg(600, 160, 730, 160)
        } },
        { name = "3G", y = 110, left = {
            seg(40, 160, 200, 160), seg(200, 160, 240, 110),
            seg(240, 110, 350, 110)
        }, right = {
            seg(450, 110, 560, 110), seg(560, 110, 600, 160),
            seg(600, 160, 730, 160)
        } },
        { name = "IG", y = 160, left = {
            seg(40, 160, 350, 160)
        }, right = {
            seg(450, 160, 730, 160)
        } },
        { name = "IIG", y = 200, left = {
            seg(40, 200, 350, 200)
        }, right = {
            seg(450, 200, 730, 200)
        } },
        { name = "4G", y = 240, left = {
            seg(40, 200, 190, 200), seg(190, 200, 230, 240),
            seg(230, 240, 350, 240)
        }, right = {
            seg(450, 240, 520, 240), seg(520, 240, 560, 200),
            seg(560, 200, 730, 200)
        } }
    }

    -- 站台对象：左进路（入口 -> 站台）和右进路（站台 -> 出口）各保留一份绿色高亮。
    self.platforms = {}
    for i, def in ipairs(defs) do
        local p = {
            index = i, name = def.name, y = def.y,
            left_path = def.left, right_path = def.right,
            phase = "empty", dwell = 0, next_arrival = 0,
            arrive_timer = 0, depart_timer = 0, dir = 1,
            route_active = false, train_id = nil,
            arrival_path = nil, departure_path = nil,
            arrival_len = 0, departure_len = 0,
            green_side = 0, state = nil, card_state = nil,
            card_id_cache = nil, card_dir_cache = nil,
            badge_shown = false, badge_text_cache = nil,
            marker_shown = false
        }
        p.left_green = draw_green_path(view, p.left_path)
        p.right_green = draw_green_path(view, p.right_path)

        p.track_label = label(view, 300, def.y - 18, 36, 14, def.name, 10, C.soft)
        p.badge = box(view, PLATFORM_X1, def.y - 8, PLATFORM_X2 - PLATFORM_X1,
            16, C.pink_bg, 3, C.pink_border)
        p.badge_text = label(p.badge, 0, 1, PLATFORM_X2 - PLATFORM_X1, 14, "",
            10, C.bg, airui.TEXT_ALIGN_CENTER)
        p.badge:set_hidden(true)

        local cx = 8 + (i - 1) * 152
        p.card = box(view, cx, CARD_Y, CARD_W, CARD_H, C.red_bg, 6, C.red)
        p.card_title = label(p.card, 10, 5, 120, 14, def.name .. " 站台", 11, C.text)
        p.card_dot = box(p.card, 10, 27, 6, 6, C.red, 3)
        p.card_status = label(p.card, 22, 22, 76, 14, "空闲", 10, C.red)
        p.card_dir = label(p.card, 100, 22, 38, 14, "—", 10, C.muted,
            airui.TEXT_ALIGN_RIGHT)
        self.platforms[i] = p
    end

    -- 道岔节点
    local joints = {
        { 200, 160 }, { 240, 110 }, { 300, 110 }, { 330, 70 },
        { 470, 70 }, { 500, 110 }, { 560, 110 }, { 600, 160 },
        { 190, 200 }, { 230, 240 }, { 520, 240 }, { 560, 200 },
        { 80, 160 }, { 130, 200 }, { 640, 160 }, { 690, 200 }
    }
    for _, j in ipairs(joints) do node(view, j[1], j[2], 5, C.blue) end

    -- 信号机
    local function signal(x, y, text)
        box(view, x - 3, y - 3, 6, 6, C.red, 3)
        label(view, x - 13, y - 17, 26, 12, text, 9, C.red,
            airui.TEXT_ALIGN_CENTER)
    end
    signal(75, 160, "X")
    signal(470, 70, "X5")
    signal(528, 110, "X3")
    signal(580, 160, "XI")
    signal(275, 240, "XII")
    signal(720, 200, "S")
    label(view, 245, 204, 30, 12, "SII", 9, C.red)
    label(view, 245, 250, 30, 12, "S4", 9, C.red)

    -- 区段号和道岔号
    label(view, 105, 145, 70, 14, "3-9DG", 9, C.dim)
    label(view, 90, 210, 70, 14, "1-5DG", 9, C.dim)
    label(view, 620, 145, 70, 14, "4-10DG", 9, C.dim)
    label(view, 585, 210, 70, 14, "2-6DG", 9, C.dim)

    local switches = {
        { 100, 180, "3" }, { 220, 140, "7" }, { 245, 96, "9" },
        { 360, 40, "14" }, { 480, 90, "12" }, { 580, 96, "10" },
        { 600, 140, "8" }, { 655, 120, "4" }, { 675, 180, "2" },
        { 55, 215, "1" }, { 210, 225, "5" }, { 540, 225, "6" }
    }
    for _, s in ipairs(switches) do
        label(view, s[1], s[2], 24, 12, s[3], 9, C.dim)
    end

    -- 站房
    box(view, 320, 264, 140, 24, C.panel2, 4, C.border)
    label(view, 320, 268, 140, 14, "站房", 10, C.muted,
        airui.TEXT_ALIGN_CENTER)

    -- 列车色块最后创建，保证显示在进路之上。
    for _, p in ipairs(self.platforms) do
        p.marker = box(view, 0, 0, 18, 8, C.pink, 3, C.pink_border)
        p.marker:set_hidden(true)
    end

    self:_init_platforms()

    box(view, 16, 352, 744, 1, C.border)
    self.yard_status = label(view, 16, 364, 520, 16, "", 11, C.soft)
    label(view, 536, 364, 224, 16, "绿色=有车/出站进路 · 红色=空闲", 10, C.dim,
        airui.TEXT_ALIGN_RIGHT)
end

function UI:_next_train_id()
    self._train_serial = self._train_serial + 1
    if self._train_serial > 9999 then self._train_serial = 1001 end
    return string.format("G%04d", self._train_serial)
end

function UI:_init_platforms()
    -- 初始 3 个站台有车、2 个空闲，再随机打乱。
    local flags = {}
    for i = 1, 5 do flags[i] = i <= 3 end
    for i = 5, 2, -1 do
        local j = math.random(i)
        flags[i], flags[j] = flags[j], flags[i]
    end

    for i, p in ipairs(self.platforms) do
        local occupied = flags[i]
        p.phase = occupied and "dwell" or "empty"
        p.dwell = occupied and (10 + math.random() * 20) or 0
        p.arrive_timer = 0
        p.depart_timer = 0
        p.next_arrival = occupied and 0 or (3 + math.random() * 10)
        p.dir = math.random(2) == 1 and 1 or -1
        p.route_active = occupied and true or false
        p.train_id = occupied and self:_next_train_id() or nil
        p.arrival_path = nil
        p.arrival_len = 0
        p.departure_path = occupied and
            (p.dir == 1 and p.right_path or reverse_path(p.left_path)) or nil
        p.departure_len = p.departure_path and path_length(p.departure_path) or 0
        p.green_side = 0
        p.state = nil
        p.card_state = nil
        p.card_id_cache = nil
        p.card_dir_cache = nil
        p.badge_shown = false
        p.badge_text_cache = nil
        p.marker_shown = false
    end
end

function UI:_step_platforms(dt)
    if dt <= 0 then return end
    for _, p in ipairs(self.platforms) do
        if p.phase == "dwell" then
            p.dwell = p.dwell - dt
            if p.dwell <= 0 then
                p.phase = "depart"
                p.depart_timer = DEPART_TIME
                p.route_active = true
            end
        elseif p.phase == "arrive" then
            p.arrive_timer = p.arrive_timer - dt
            if p.arrive_timer <= 0 then
                p.phase = "dwell"
                p.dwell = DWELL_TIME
                p.route_active = true
                p.arrival_path = nil
                p.arrival_len = 0
                p.departure_path = p.dir == 1 and p.right_path or
                    reverse_path(p.left_path)
                p.departure_len = path_length(p.departure_path)
            end
        elseif p.phase == "depart" then
            p.depart_timer = p.depart_timer - dt
            if p.depart_timer <= 0 then
                p.phase = "empty"
                p.route_active = false
                p.next_arrival = 6 + math.random() * 10
                p.train_id = nil
                p.arrival_path = nil
                p.arrival_len = 0
                p.departure_path = nil
                p.departure_len = 0
            end
        else
            p.next_arrival = p.next_arrival - dt
            if p.next_arrival <= 0 then
                p.phase = "arrive"
                p.arrive_timer = ARRIVE_TIME
                p.dir = math.random(2) == 1 and 1 or -1
                p.route_active = false
                p.train_id = self:_next_train_id()
                p.arrival_path = p.dir == 1 and p.left_path or
                    reverse_path(p.right_path)
                p.arrival_len = path_length(p.arrival_path)
                p.departure_path = nil
                p.departure_len = 0
            end
        end
    end
end

function UI:_update_yard()
    local occupied_count = 0

    for _, p in ipairs(self.platforms) do
        local occupied = p.phase == "dwell"
        if occupied then occupied_count = occupied_count + 1 end
        local color = occupied and C.green or C.red

        if p.card_state ~= occupied then
            p.card:set_color(occupied and C.green_bg or C.red_bg)
            p.card:set_border_color(color, 1)
            p.card_dot:set_color(color)
            p.card_status:set_color(color)
            p.card_state = occupied
            p.card_id_cache = nil
        end
        local card_text = occupied and (p.train_id or "") or "空闲"
        if p.card_id_cache ~= card_text then
            p.card_status:set_text(card_text)
            p.card_id_cache = card_text
        end
        local dir_text = occupied and (p.dir == 1 and "京→广" or "广→京") or "—"
        if p.card_dir_cache ~= dir_text then
            p.card_dir:set_text(dir_text)
            p.card_dir_cache = dir_text
        end

        if p.badge_shown ~= occupied then
            p.badge:set_hidden(not occupied)
            p.badge_shown = occupied
        end
        if occupied and p.badge_text_cache ~= p.train_id then
            p.badge_text:set_text(p.train_id or "")
            p.badge_text_cache = p.train_id
        end

        -- 进站时高亮入口 -> 站台，停站/出站时高亮站台 -> 出口。
        local side = 0
        if p.phase == "arrive" then
            side = p.dir == 1 and 1 or 2
        elseif p.route_active then
            side = p.dir == 1 and 2 or 1
        end
        if side == 0 then
            if p.green_side ~= 0 then
                set_path_visible(p.left_green, false)
                set_path_visible(p.right_green, false)
                p.green_side = 0
            end
        elseif p.green_side ~= side then
            set_path_visible(p.left_green, side == 1)
            set_path_visible(p.right_green, side == 2)
            p.green_side = side
        end

        local moving = p.phase == "arrive" or p.phase == "depart"
        if moving then
            if not p.marker_shown then
                p.marker:set_hidden(false)
                p.marker_shown = true
            end
            local path = p.phase == "arrive" and p.arrival_path or p.departure_path
            local length = p.phase == "arrive" and p.arrival_len or p.departure_len
            local timer = p.phase == "arrive" and p.arrive_timer or p.depart_timer
            local duration = p.phase == "arrive" and ARRIVE_TIME or DEPART_TIME
            if path and length > 0 then
                local q = 1 - timer / duration
                if q < 0 then q = 0 elseif q > 1 then q = 1 end
                local x, y = point_on_path(path, q * length)
                p.marker:set_pos(round(x - 9), round(y - 4))
            end
        elseif p.marker_shown then
            p.marker:set_hidden(true)
            p.marker_shown = false
        end
    end

    local status = string.format("有车 %d/%d · 空闲 %d/%d · 停站 30 秒",
        occupied_count, #self.platforms,
        #self.platforms - occupied_count, #self.platforms)
    if self.yard_status_text ~= status then
        self.yard_status:set_text(status)
        self.yard_status_text = status
    end
end

function UI:render(s)
    local now = self.model.time
    local dt = self._yard_time and (now - self._yard_time) or 0
    self._yard_time = now
    if dt < 0 then dt = 0 elseif dt > 0.5 then dt = 0.5 end
    self:_step_platforms(dt)

    self:_text("clock", self.clock_label, s.clock)
    self:_text("side_online", self.side_online, tostring(s.online))
    self:_text("side_occ", self.side_occ, string.format("%d%%", math.floor(s.occupancy + 0.5)))
    self:_text("side_alerts", self.side_alerts, tostring(s.alerts_count))
    self:_text("side_flow", self.side_flow, string.format("%.1f万", s.passenger))

    local status_kind = s.alerts_count >= 5 and "alert"
        or (s.alerts_count >= 3 and "warn" or "ok")
    if self.cache.status_kind ~= status_kind then
        local bg = status_kind == "alert" and C.red_bg
            or (status_kind == "warn" and C.amber_bg or C.green_bg)
        local border = status_kind == "alert" and C.red_border
            or (status_kind == "warn" and C.amber_border or C.green_border)
        local color = status_kind == "alert" and C.red
            or (status_kind == "warn" and C.amber or C.green)
        self.status_pill:set_color(bg)
        self.status_pill:set_border_color(border, 1)
        self.status_dot:set_color(color)
        self.status_text:set_color(color)
        self.cache.status_kind = status_kind
    end
    self:_text("status_text", self.status_text,
        status_kind == "alert" and "告警关注"
        or (status_kind == "warn" and "运行关注" or "调度正常"))

    if self.page == "home" then
        -- 总览指标
        local metric_values = {
            tostring(s.online),
            string.format("%.1f", s.on_time),
            tostring(math.floor(s.avg_speed + 0.5)),
            tostring(math.floor(s.occupancy + 0.5))
        }
        for i, value in ipairs(metric_values) do
            self:_text("metric_" .. i, self.metrics[i], value)
        end
        self:_color("metric_on_time", self.metrics[2],
            s.on_time >= 90 and C.green or (s.on_time >= 80 and C.amber or C.red))

    -- 告警列车优先展示，便于和准点率、告警面板对应。
    local ordered = {}
    for _, train in ipairs(s.trains) do
        if train.delay > 0 then ordered[#ordered + 1] = train end
    end
    for _, train in ipairs(s.trains) do
        if train.delay == 0 then ordered[#ordered + 1] = train end
    end

    for i, row in ipairs(self.train_rows) do
        local train = ordered[i]
        if train then
            self:_text("train_id_" .. i, row.id, train.id)
            self:_text("train_route_" .. i, row.route,
                train.from_name .. " → " .. train.to_name)
            self:_text("train_status_" .. i, row.status,
                train.delay > 0 and ("晚点 " .. train.delay .. " 分") or "正点")
            self:_color("train_status_color_" .. i, row.status,
                train.delay > 0 and C.amber or C.green)
            self:_text("train_speed_" .. i, row.speed,
                tostring(train.speed_display) .. " km/h")
        else
            self:_text("train_id_" .. i, row.id, "")
            self:_text("train_route_" .. i, row.route, "")
            self:_text("train_status_" .. i, row.status, "")
            self:_text("train_speed_" .. i, row.speed, "")
        end
    end

    for i, row in ipairs(self.line_rows) do
        local load = s.line_loads[i]
        if load then
            self:_text("line_name_" .. i, row.name, load.name)
            self:_text("line_pct_" .. i, row.percent, string.format("%d%%", load.percent))
            local filled = math.ceil(load.percent / 10)
            local color = load.level == "high" and C.red
                or (load.level == "mid" and C.amber or C.green)
            for j, segment in ipairs(row.segments) do
                local on = j <= filled
                local key = "line_bar_" .. i .. "_" .. j
                local value = on and color or C.row
                if self.line_bar_style[key] ~= value then
                    segment:set_color(value)
                    self.line_bar_style[key] = value
                end
            end
        else
            self:_text("line_name_" .. i, row.name, "")
            self:_text("line_pct_" .. i, row.percent, "")
            for j, segment in ipairs(row.segments) do
                segment:set_color(C.row)
            end
        end
    end

        self:_text("alert_count", self.alert_count, tostring(s.alerts_count) .. " 条")
        self:_text("alert1", self.alert1, s.alerts[1] or "全网运行平稳")
        self:_text("alert2", self.alert2, s.alerts[2] or "")
    end

    if self.page == "map" then
        self:_update_yard()
    end
end

return UI
