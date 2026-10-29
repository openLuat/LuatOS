--[[
@module  ui_settings
@summary 设置页：观测站点（经纬度/预设）、显示参数、背光与夜视、关于
@version 1.0
@date    2026.10.28
]]
local conf  = require("conf")
local theme = require("theme")
local data  = require("star_data")

local C = theme.C
local W, H = conf.W, conf.H

-- 国内几个经典观测地
local SITES = {
    { name = "青海 · 冷湖",   lat = 38.60, lon = 93.30,  bortle = 2 },
    { name = "西藏 · 阿里",   lat = 32.32, lon = 80.10,  bortle = 1 },
    { name = "河北 · 兴隆",   lat = 40.40, lon = 117.58, bortle = 3 },
    { name = "云南 · 丽江",   lat = 26.70, lon = 100.03, bortle = 3 },
    { name = "四川 · 稻城",   lat = 29.03, lon = 100.30, bortle = 2 },
}

local build = function(app)
    local page = { arg = nil }
    local st = app.state
    local root = airui.container({
        parent = app.root, x = 0, y = 0, w = W, h = H, color = C.bg1, radius = 0,
    })
    page.root = root
    theme.gradient(root, 0, 0, W, H, C.bg2, C.bg1, 10)

    app.header(root, "设置", "观测站点 · 显示参数 · 夜间模式")
    app.nav(root, "settings")

    -- ==================== 卡 1：站点 ====================
    local c1 = theme.card(root, 108, 76, 440, 244, C.panel, 14)
    theme.accent_bar(c1, 18, 16, 40, C.cyan)
    theme.label(c1, 18, 28, 300, 24, "观测站点", 18, C.ink)
    local site_lb = theme.label(c1, 18, 54, 400, 20, conf.site.name, 14, C.cyan)

    -- 说明：airui.slider 的 min/max/value 只接受整数，
    -- 所以经纬度用 0.1° 为单位放大 10 倍，星等极限放大 10 倍
    theme.label(c1, 18, 88, 60, 16, "纬度", 12, C.ink3)
    local lat_val = theme.label(c1, 320, 88, 100, 16, "", 12, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    local sl_lat = theme.slider(c1, 18, 110, 400, 10, -600, 600,
        math.floor(conf.site.lat * 10 + 0.5), C.cyan, nil)

    theme.label(c1, 18, 138, 60, 16, "经度", 12, C.ink3)
    local lon_val = theme.label(c1, 320, 138, 100, 16, "", 12, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    local sl_lon = theme.slider(c1, 18, 160, 400, 10, -1800, 1800,
        math.floor(conf.site.lon * 10 + 0.5), C.violet, nil)

    theme.hline(c1, 18, 190, 400, C.line)
    theme.label(c1, 18, 200, 120, 18, "海拔", 12, C.ink3)
    theme.label(c1, 18, 220, 200, 18,
        string.format("%d m   ·   波特尔 %d 级", conf.site.elev, conf.site.bortle),
        13, C.ink2)
    local hz = 90 - math.abs(conf.site.lat)
    theme.label(c1, 240, 200, 180, 18, "天赤道最高", 12, C.ink3, airui.TEXT_ALIGN_RIGHT)
    local hz_lb = theme.label(c1, 240, 220, 180, 18, string.format("%.0f°", hz), 13,
        C.ink2, airui.TEXT_ALIGN_RIGHT)

    -- ==================== 卡 2：显示 ====================
    local c2 = theme.card(root, 108, 332, 440, 256, C.panel, 14)
    theme.accent_bar(c2, 18, 16, 40, C.violet)
    theme.label(c2, 18, 28, 300, 24, "显示与舒适度", 18, C.ink)

    theme.label(c2, 18, 70, 160, 16, "星等极限", 12, C.ink3)
    local mag_val = theme.label(c2, 300, 70, 100, 16, "", 12, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    local sl_mag = theme.slider(c2, 18, 92, 400, 10, 10, 50,
        math.floor(st.mag_limit * 10 + 0.5), C.cyan, nil)

    theme.label(c2, 18, 120, 160, 16, "背光亮度", 12, C.ink3)
    local bl_val = theme.label(c2, 300, 120, 100, 16, "", 12, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    local sl_bl = theme.slider(c2, 18, 142, 400, 10, 8, 100, conf.backlight.default,
        C.amber, nil)

    local line_btn = theme.button(c2, 18, 180, 190, 40, "", 15, C.panel3, C.ink,
        function() end, 10)
    local night_btn = theme.button(c2, 228, 180, 190, 40, "", 15, C.panel3, C.ink,
        function() end, 10)

    local function sync_toggles()
        line_btn:set_text(st.lines and "星座连线：开" or "星座连线：关")
        line_btn:set_style({
            bg_color = theme.tint(st.lines and 0x14324A or C.panel3), bg_opa = 255,
            text_color = theme.tint(st.lines and C.cyan or C.ink3),
            radius = 10, border_width = 1, border_color = theme.tint(C.line2),
        })
        night_btn:set_text(theme.night and "夜视红光：开" or "夜视红光：关")
        night_btn:set_style({
            bg_color = theme.tint(theme.night and 0x4A1010 or C.panel3), bg_opa = 255,
            text_color = theme.tint(theme.night and C.red or C.ink3),
            radius = 10, border_width = 1, border_color = theme.tint(C.line2),
        })
    end

    line_btn:set_on_click(function()
        st.lines = not st.lines
        sync_toggles()
        app.toast(st.lines and "已显示星座连线" or "已隐藏星座连线")
    end)

    night_btn:set_on_click(function()
        theme.night = not theme.night
        sync_toggles()
        app.go("settings")
        app.toast(theme.night and "夜视红光已开启（保护暗适应）" or "已退出夜视模式")
    end)

    -- ==================== 卡 3：站点预设 ====================
    local c3 = theme.card(root, 564, 76, 448, 272, C.panel, 14)
    theme.accent_bar(c3, 18, 16, 40, C.amber)
    theme.label(c3, 18, 28, 300, 24, "快速切换观测地", 18, C.ink)
    theme.label(c3, 18, 54, 400, 18, "点击即应用，星图会立即重算", 12, C.ink3)

    for i, s in ipairs(SITES) do
        local y = 78 + (i - 1) * 38
        local on = (math.abs(s.lat - conf.site.lat) < 0.01 and
                    math.abs(s.lon - conf.site.lon) < 0.01)
        local b = theme.button(c3, 18, y, 412, 32,
            string.format("%s    %.2f°N  %.2f°E", s.name, s.lat, s.lon), 14,
            on and 0x16324A or C.panel2, on and C.cyan or C.ink2, function() end, 8)
        local ss = s
        b:set_on_click(function()
            conf.site.name = ss.name
            conf.site.lat = ss.lat
            conf.site.lon = ss.lon
            conf.site.bortle = ss.bortle
            app.go("settings")
            app.toast("观测地已切换到 " .. ss.name)
        end)
    end

    -- ==================== 卡 4：关于 ====================
    local c4 = theme.card(root, 564, 364, 448, 224, C.panel, 14)
    theme.accent_bar(c4, 18, 16, 40, C.green)
    theme.label(c4, 18, 28, 300, 24, "关于本机", 18, C.ink)

    local info = {
        { "产品", conf.name .. " v" .. conf.version },
        { "硬件", "Air8607 · 10.1 寸 1024x600 RGB" },
        { "星表", string.format("%d 颗亮星 · %d 条星座连线",
            data.count, #data.lines) },
        { "天体", "梅西耶/NGC 精选 14 个" },
        { "算法", "J2000 赤道坐标 · 方位等距投影" },
    }
    for i, kv in ipairs(info) do
        local y = 64 + (i - 1) * 26
        theme.label(c4, 18, y, 84, 18, kv[1], 12, C.ink3)
        theme.label(c4, 104, y, 326, 18, kv[2], 13, C.ink2)
    end

    theme.button(c4, 18, 178, 200, 34, "返回星图", 14, C.cyan, 0x061019,
        function() app.go("sky") end, 8)
    theme.ghost_button(c4, 230, 178, 200, 34, "重置仿真时间", 14, C.ink2,
        function()
            local now = os.time()
            if now and now > 1600000000 then
                st.t = now
            end
            app.toast("时间已重置为系统时间")
        end)

    -- ==================== 刷新 ====================
    local bl_applied = conf.backlight.default
    local frame = 0
    page.tick = function()
        frame = frame + 1
        if frame % 3 ~= 1 then return end

        if sl_lat then
            local v = sl_lat:get_value() / 10
            if math.abs(v - conf.site.lat) > 0.05 then
                conf.site.lat = v
                conf.site.name = "自定义站点"
                site_lb:set_text(conf.site.name)
                hz_lb:set_text(string.format("%.0f°", 90 - math.abs(v)))
            end
            lat_val:set_text(string.format("%.1f°", v))
        end
        if sl_lon then
            local v = sl_lon:get_value() / 10
            if math.abs(v - conf.site.lon) > 0.05 then
                conf.site.lon = v
                conf.site.name = "自定义站点"
                site_lb:set_text(conf.site.name)
            end
            lon_val:set_text(string.format("%.1f°", v))
        end
        if sl_mag then
            local v = sl_mag:get_value() / 10
            st.mag_limit = v
            mag_val:set_text(string.format("%.1f 等", st.mag_limit))
        end
        if sl_bl then
            local v = math.floor(sl_bl:get_value())
            bl_val:set_text(string.format("%d%%", v))
            if math.abs(v - bl_applied) >= 2 then
                bl_applied = v
                pcall(function() pwm.setDuty(conf.backlight.pwm_ch, v) end)
            end
        end
    end

    page.touch = nil
    sync_toggles()
    lat_val:set_text(string.format("%.2f°", conf.site.lat))
    lon_val:set_text(string.format("%.2f°", conf.site.lon))
    mag_val:set_text(string.format("%.1f 等", st.mag_limit))
    bl_val:set_text(string.format("%d%%", conf.backlight.default))

    return page
end

return build
