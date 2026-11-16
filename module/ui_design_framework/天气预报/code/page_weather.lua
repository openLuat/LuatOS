-- page_weather.lua  双页版天气预报
-- 页面1（当前天气）：固定顶栏 + 一屏内容（无页面滚动）：
--   hero → 每小时预报(9个指标tab + 图表/列表切换 + 日期条 + 图表)
-- 页面2（天气详细信息）：12 卡独立页面，顶栏按钮互相切换
-- 交互：点城市名弹下拉选城市 / 点日期卡切换 / tab与图表列表切换 /
--       概览"体感温度"开关叠加附加线 / 顶栏月亮切换深浅主题
-- 踩坑（重要）：LVGL 点击回调里直接销毁被点控件所在子树（rebuild 销毁锚点）
--       有 use-after-free 风险且错误被 pcall 吞掉，表现为"点了没反应"。
--       所有 on_click 一律 defer() 延迟 30ms 到事件外执行，并防抖合并重建。
-- 踩坑：动态区子控件挂在锚点容器下（销毁锚点=整块销毁），
--       坐标全部相对锚点；绝不读 airui 对象句柄的 .w/.h
local sys   = require "sys"
local exwin = require "exwin"
local theme = require "theme"
local mock  = require "mock"

-- 页面间共享：详细信息构建器（页面1定义，页面2复用）+ 挂载父容器
local build_detail_shared
local DETAIL_PARENT

theme.make_page(1, "天气预报", function(root, cx, cy, cw, ch, rerender)
    local C = theme.C
    local W, H = theme.W, theme.H

    ----------------------------------------------------------------
    -- 指标 tab 元数据（与 preview.html 的 9 个 tab 一致）
    ----------------------------------------------------------------
    -- tab 元数据（html 同款行为）：
    --   sw/swkey  图表附加线开关（体感温度/阵风/露点/温度）
    --   fill      面积图渐变填充（概览/湿度/气压/可见度/体感温度，html 同款）
    --   arrows    风速 tab 的小时风向箭头行
    --   bar_r     圆角柱半径（云量胶囊柱）
    --   legend    图表底部图例（彩色圆点+文字）
    local TABS = {
        { name = "概览",     ulabel = "温度(°C)",     color = C.yellow, type = "line", ymin = -15, ymax = 30, icons = true,
          sw = "体感温度", swkey = "feel_on", fill = true },
        { name = "降水",     ulabel = "降水(0.1mm)",  color = C.blue,   type = "bar",  ymin = 0,   ymax = 120,
          legend = { { "雨", C.blue }, { "阵雨", C.cyan }, { "雨/雪", 0xAFC8E8 } } },
        { name = "风速",     ulabel = "风速(km/h)",   color = C.cyan,   type = "line", ymin = 0,   ymax = 60,
          sw = "阵风", swkey = "gust_on", arrows = true,
          legend = { { "风速", C.cyan }, { "阵风", C.blue } } },
        { name = "湿度",     ulabel = "湿度(%)",      color = C.blue,   type = "line", ymin = 0,   ymax = 100,
          sw = "露点", swkey = "dew_on", fill = true,
          legend = { { "湿度", C.blue }, { "露点", C.cyan } } },
        { name = "云量",     ulabel = "云量(%)",      color = C.accent, type = "bar",  ymin = 0,   ymax = 100,
          bar_r = 12,
          legend = { { "晴朗", 0x3D6FD0 }, { "大部晴朗", 0x5AA7FF }, { "局部多云", 0x8FC3F5 }, { "多云", 0xC8DCF5 } } },
        { name = "气压",     ulabel = "气压(hPa)",    color = C.purple, type = "line", ymin = 980, ymax = 1040, fill = true,
          legend = { { "气压", C.purple } } },
        { name = "紫外线",   ulabel = "紫外线指数",   color = 0xF08A3C, type = "bar",  ymin = 0,   ymax = 10,
          legend = { { "极端", C.red }, { "非常高", 0xE0563C }, { "高", 0xF08A3C }, { "中等", C.yellow }, { "低", C.green } } },
        { name = "可见度",   ulabel = "可见度(公里)", color = C.green,  type = "line", ymin = 0,   ymax = 30, fill = true,
          legend = { { "可见度", C.green } } },
        { name = "体感温度", ulabel = "体感温度(°C)", color = C.yellow, type = "line", ymin = -15, ymax = 35, fill = true,
          sw = "温度", swkey = "ftemp_on",
          legend = { { "体感温度", C.yellow }, { "温度", C.orange } } },
    }
    -- 图标种类 → 天气描述（列表卡用，html 同款文案）
    local ICON_TEXT = {
        sun = "晴朗", moon = "夜间晴朗", cloud = "多云",
        partly = "局部晴朗", rain = "降雨", thunder = "雷阵雨",
    }
    local TIPS = {
        ["晴"]     = "今天天气晴朗，适合外出。",
        ["多云"]   = "局部晴朗，偶有阳光。",
        ["阴"]     = "天色阴沉，注意保暖。",
        ["小雨"]   = "预计今天有降雨，出门请带伞。",
        ["阵雨"]   = "午后有阵雨，出门请带伞。",
        ["雷阵雨"] = "午后有雷阵雨，注意防雷。",
    }
    local DIRS  = { "东北风", "东风", "东南风", "南风" }
    local CHIPS = { "空气质量", "风速", "湿度", "能见度", "气压", "露点" }

    local SX, SW = 8, W - 16          -- 内容区左右边距
    local scroll                  -- 可滚动内容区
    local h_time                  -- 顶栏时间
    local chip_lbls = {}          -- hero 指标条（live 刷新）
    local dyn = {}                -- 动态区锚点容器 {hero, hourly, detail}
    local detail_y = 600          -- 详细信息起始 y（随图表/列表视图变化）
    local rebuild                 -- 前置声明（按钮闭包引用；必须 local）
    local open_city_popup, close_popup  -- 城市下拉弹层（前置声明）

    ----------------------------------------------------------------
    -- 点击延迟 + 重建防抖：LVGL 回调里销毁被点控件子树不安全，
    -- 统一延迟 30ms 到事件外执行；30ms 内的重复点击合并为一次重建
    ----------------------------------------------------------------
    local rb_pending = false
    local function defer(fn) sys.timerStart(fn, 30) end
    local function rebuild_soon()
        if rb_pending then return end
        rb_pending = true
        sys.timerStart(function()
            rb_pending = false
            pcall(rebuild)
        end, 30)
    end

    ----------------------------------------------------------------
    -- 固定顶栏：标题 + 时间 + 提问胶囊 + 主题切换按钮（月亮/太阳）
    ----------------------------------------------------------------
    airui.label({ parent = root, x = 16, y = 10, w = 130, h = 24,
        text = "当前天气", color = C.text, font_size = 16 })
    h_time = airui.label({ parent = root, x = 150, y = 12, w = 90, h = 22,
        text = "--:--", color = C.sub, font_size = 16 })
    -- 详细信息改为独立页面（滑动卡顿优化：主页面不再构建 12 张详情卡），
    -- 顶部按钮切换（原"上下滑动到详情区"已移除）
    airui.button({ parent = root, x = 256, y = 7, w = 130, h = 30,
        text = "详细信息", font_size = 16,
        style = { bg_color = C.deep, text_color = C.text,
            border_color = C.border, border_width = 1, radius = 15, pad = 0 },
        on_click = function()
            sys.timerStart(function() theme.open_page(2) end, 30)
        end })
    -- 深色显示月亮、浅色显示太阳（html 🌙/☀️ 同款）；点击切换主题
    local tbtn = airui.button({ parent = root, x = W - 48, y = 5, w = 40, h = 34,
        text = "", font_size = 16,
        style = { bg_color = C.bg, text_color = C.text,
            border_width = 0, radius = 8, pad = 0 },
        on_click = function()
            theme.toggle_theme()
            -- 踩坑：事件回调里销毁整棵树有风险，延迟到事件外重建
            sys.timerStart(rerender, 30)
        end })
    pcall(function()
        theme.wicon(tbtn, 6, 3, 28, (theme.cur == "dark") and "moon" or "sun", C.bg)
    end)

    -- 内容区：不滚动（一屏显示完；布局总高按 600 屏压缩，详见 build_chart_body）
    scroll = airui.container({ parent = root, x = 0, y = 44,
        w = W, h = H - 44, color = C.bg })

    ----------------------------------------------------------------
    -- 城市下拉弹层（html 同款：全屏蒙版 + "我的位置" + 城市条目）
    ----------------------------------------------------------------
    local popup = nil
    close_popup = function()
        if popup then
            local p = popup
            popup = nil
            pcall(p.destroy, p)
        end
    end
    open_city_popup = function()
        close_popup()
        -- 蒙版：全屏透明容器，点空白处关闭（先创建 = 在下层）
        popup = airui.container({ parent = root, x = 0, y = 0, w = W, h = H,
            color = C.bg, color_opacity = 0, on_click = function()
                defer(close_popup)
            end })
        -- 面板（后创建 = 在上层）
        local mx, my, mw = SX + 4, 102, 280
        local mh = 32 + #mock.CITIES * 56 + 8
        airui.container({ parent = popup, x = mx, y = my, w = mw, h = mh,
            color = C.deep, radius = 10,
            border_color = C.border, border_width = 1 })
        airui.label({ parent = popup, x = mx + 14, y = my + 7, w = 140, h = 20,
            text = "我的位置", color = C.sub, font_size = 16 })
        for i, city in ipairs(mock.CITIES) do
            local iy = my + 32 + (i - 1) * 56
            local sel = (i == mock.S.city)
            airui.button({ parent = popup, x = mx + 8, y = iy, w = mw - 16, h = 52,
                text = "", font_size = 16,
                style = { bg_color = sel and C.card or C.deep,
                    text_color = C.text,
                    border_color = sel and C.accent or C.deep,
                    border_width = sel and 2 or 0, radius = 8, pad = 0 },
                on_click = function()
                    mock.S.city = i
                    defer(function()
                        close_popup()
                        rebuild()
                    end)
                end })
            airui.label({ parent = popup, x = mx + 18, y = iy + 5, w = 160, h = 22,
                text = city.name, color = C.text, font_size = 16 })
            airui.label({ parent = popup, x = mx + 18, y = iy + 27, w = 190, h = 20,
                text = city.prov .. "," .. city.name, color = C.sub, font_size = 16 })
            theme.wicon(popup, mx + mw - 100, iy + 13, 26,
                mock.icon_of(mock.cond(i, 2)), C.deep)
            airui.label({ parent = popup, x = mx + mw - 68, y = iy + 13, w = 56, h = 26,
                text = mock.cur_temp(i, 2) .. "°", color = C.text, font_size = 16,
                align = airui.TEXT_ALIGN_RIGHT })
        end
    end

    ----------------------------------------------------------------
    -- ① 当前天气 Hero 卡（挂在 dyn.hero 锚点下，坐标相对锚点）
    ----------------------------------------------------------------
    local function build_hero()
        local s = airui.container({ parent = dyn.hero, x = SX, y = 8,
            w = SW, h = 156, color = C.card_soft,
            border_color = C.border, border_width = 1, radius = 8 })
        -- html 同款布局（无装饰角标）：城市名 / 大图标+大字温度 /
        -- 右侧天气名+体感 / 提示语 / 底部指标条；全卡字号≥16

        local city  = mock.CITIES[mock.S.city]
        local cond  = mock.cond(mock.S.city, mock.S.day)
        local hl    = mock.hilo(mock.S.city, mock.S.day)
        local temp  = mock.cur_temp(mock.S.city, mock.S.day)

        -- 城市名（点击弹出城市下拉，html 同款）
        -- 踩坑：hzfont 字库里没有 ⌄ 字形，会渲染成方框——下拉箭头用 shape 画
        airui.button({ parent = s, x = 14, y = 6, w = 280, h = 28,
            text = city.prov .. "," .. city.name, font_size = 16,
            style = { bg_color = C.card_soft, text_color = C.sub,
                border_width = 0, radius = 8, pad = 0 },
            on_click = function() defer(open_city_popup) end })
        pcall(function()
            -- 下拉箭头放按钮右端（按钮 x14 w280 → 右缘 294）
            airui.shape({ parent = s, x = 276, y = 15, w = 10, h = 10, items = {
                { type = "line", x1 = 1, y1 = 3, x2 = 5, y2 = 7,
                  color = C.sub, width = 2 },
                { type = "line", x1 = 5, y1 = 7, x2 = 9, y2 = 3,
                  color = C.sub, width = 2 } } })
        end)
        -- 踩坑：温度大字 y 必须 > 城市名底边（y6+28），否则大字号上沿与城市名重叠
        -- 图标与温度大字垂直居中对齐（html 同款）
        theme.wicon(s, 14, 48, 56, mock.icon_of(cond), C.card_soft)
        airui.label({ parent = s, x = 86, y = 40, w = 190, h = 64,
            text = tostring(temp) .. "°C", color = C.text, font_size = 56 })
        airui.label({ parent = s, x = 286, y = 48, w = 180, h = 32,
            text = cond, color = C.text, font_size = 26 })
        airui.label({ parent = s, x = 286, y = 82, w = 220, h = 22,
            text = "体感温度 " .. (temp + 1) .. "°",
            color = C.sub, font_size = 16 })
        airui.label({ parent = s, x = 14, y = 104, w = 700, h = 20,
            text = (TIPS[cond] or "") .. "最低气温 " .. hl.lo .. "°。",
            color = C.sub, font_size = 16 })
        -- 指标条（html 同款两段式：名称灰 + 数值白）
        -- 踩坑：6 列宽 = (卡宽-28)/6=163，用 167 会超卡右边框；
        --       行底 y=124+20=144，距底边框 156 留 12px，不再压线
        local namew = { 64, 32, 32, 48, 32, 32 }  -- 名称宽（16号汉字16px/个）
        local colw = math.floor((SW - 28) / 6)
        for i, name in ipairs(CHIPS) do
            local cx = 14 + (i - 1) * colw
            airui.label({ parent = s, x = cx, y = 124, w = namew[i] + 8, h = 20,
                text = name, color = C.sub, font_size = 16 })
            chip_lbls[i] = airui.label({ parent = s,
                x = cx + namew[i] + 6, y = 124, w = colw - namew[i] - 12, h = 20,
                text = "--", color = C.text, font_size = 16 })
        end
    end

    local function update_chips()
        local ci = mock.S.city
        local hl = mock.hilo(ci, mock.S.day)
        local windv = mock.rint("wind_" .. ci, 2, 12, 1)
        local vals = {
            tostring(mock.rint("aqi_" .. ci, 40, 110, 2)),
            DIRS[(ci - 1) % 4 + 1] .. " " .. (windv < 6 and 2 or windv < 10 and 3 or 4) .. "级",
            mock.rint("hum_" .. ci, 60, 98, 2) .. "%",
            mock.fmt(mock.next("vis_" .. ci, 1, 15, 0.5)) .. "公里",
            mock.rint("pres_" .. ci, 1000, 1028, 1) .. "hPa",
            (hl.lo - 1) .. "°",
        }
        for i, _ in ipairs(CHIPS) do
            if chip_lbls[i] then
                chip_lbls[i]:set_text(vals[i])
            end
        end
    end

    ----------------------------------------------------------------
    -- 开关控件（html .sw 同款：胶囊 + 滑块）
    ----------------------------------------------------------------
    local function mkswitch(parent, x, y, on, on_click)
        local sw = airui.container({ parent = parent, x = x, y = y,
            w = 56, h = 26, color = on and C.accent or C.border,
            radius = 13, on_click = on_click })
        pcall(function()
            airui.shape({ parent = sw, x = on and 30 or 2, y = 1, w = 24, h = 24,
                items = { { type = "circle", cx = 12, cy = 12, r = 10,
                    color = 0xFFFFFF, width = 1, fill = true,
                    fill_color = 0xFFFFFF, fill_opacity = 255 } } })
        end)
    end

    ----------------------------------------------------------------
    -- ② 每小时预报（挂在 dyn.hourly 锚点下；锚点 y=172 对齐滚动区）
    ----------------------------------------------------------------
    -- 非"概览" tab 的日期卡内容（html 同款：指标数值 + 概率/等级 + 小滑条）
    local function tab_dayval(tab, ci, i)
        local k = ci .. "_" .. i .. "_"
        local r = mock.rint(k .. "knob", 10, 90, 3) / 100
        local name = tab.name
        if name == "降水" then
            local acc = 0
            for _, v in ipairs(mock.hourly(ci, i, 2)) do acc = acc + v end
            local prob = mock.rint(k .. "prob", 20, 90, 3)
            return { v1 = string.format("%.2f", acc / 10) .. " 毫米",
                v3 = prob .. "%", icon = "drop", knob = r }
        elseif name == "风速" then
            local avg = mock.rint(k .. "wa", 8, 22, 1)
            local gust = avg + mock.rint(k .. "wg", 6, 14, 1)
            return { v1 = avg .. " 公里", v2 = gust .. " 公里",
                v3 = "阵风 " .. gust .. " 公里", knob = r }
        elseif name == "湿度" then
            local h1 = mock.rint(k .. "h1", 70, 98, 2)
            return { v1 = h1 .. "%",
                v2 = (h1 - mock.rint(k .. "h2", 10, 25, 1)) .. "%", knob = r }
        elseif name == "云量" then
            return { v1 = mock.rint(k .. "c1", 55, 95, 3) .. "%",
                v2 = mock.rint(k .. "c2", 25, 60, 3) .. "%",
                icon = "cloud", v3 = "", knob = r }
        elseif name == "气压" then
            local p1 = mock.rint(k .. "p1", 1005, 1028, 1)
            return { v1 = p1 .. " hPa",
                v2 = (p1 - mock.rint(k .. "p2", 5, 15, 1)) .. " hPa", knob = r }
        elseif name == "紫外线" then
            local uv = mock.rint(k .. "uv", 1, 8, 1)
            local lvl = uv <= 2 and "低" or uv <= 5 and "中等" or "高"
            local lc = uv <= 2 and C.green or uv <= 5 and C.yellow or 0xF08A3C
            return { v1 = tostring(uv), v3 = lvl, v3col = lc,
                knob = r, knobcol = lc }
        elseif name == "可见度" then
            local d1 = mock.next(k .. "d1", 5, 20, 0.1)
            return { v1 = mock.fmt(d1) .. " 公里",
                v2 = mock.fmt(mock.next(k .. "d2", 1, d1 - 1, 0.1)) .. " 公里",
                v3 = d1 >= 15 and "非常好" or d1 >= 8 and "优" or "良好",
                knob = r }
        else  -- 体感温度
            local hi = mock.rint(k .. "fh", 16, 30, 1)
            return { v1 = hi .. "°",
                v2 = (hi - mock.rint(k .. "fl", 4, 10, 1)) .. "°", knob = r }
        end
    end

    -- 雨滴小图标（降水 tab / 降水日期卡用，html 同款单滴水珠）
    local function draw_droplet(parent, cx, cy, col)
        pcall(function()
            airui.shape({ parent = parent, x = cx - 6, y = cy - 9, w = 12, h = 18,
                items = {
                    { type = "line", x1 = 6, y1 = 1, x2 = 3, y2 = 6,
                      color = col, width = 2 },
                    { type = "line", x1 = 6, y1 = 1, x2 = 9, y2 = 6,
                      color = col, width = 2 },
                    { type = "circle", cx = 6, cy = 10, r = 5, color = col,
                      width = 1, fill = true, fill_color = col, fill_opacity = 255 },
                } })
        end)
    end

    -- 风向小箭头（风速 tab 的小时行，html 同款；ang 单位度）
    local function draw_arrow(parent, cx, cy, ang, col)
        pcall(function()
            local a = math.rad(ang)
            local dx, dy = math.cos(a), math.sin(a)
            local r3, r4 = dx * 3 - dy * 4, dy * 3 + dx * 4
            local l3, l4 = dx * 3 + dy * 4, dy * 3 - dx * 4
            airui.shape({ parent = parent, x = cx - 10, y = cy - 10, w = 20, h = 20,
                items = {
                    { type = "line", x1 = math.floor(10 - dx * 8 + 0.5),
                      y1 = math.floor(10 - dy * 8 + 0.5),
                      x2 = math.floor(10 + dx * 8 + 0.5),
                      y2 = math.floor(10 + dy * 8 + 0.5), color = col, width = 2 },
                    { type = "line", x1 = math.floor(10 + dx * 8 + 0.5),
                      y1 = math.floor(10 + dy * 8 + 0.5),
                      x2 = math.floor(10 + r3 + 0.5), y2 = math.floor(10 + r4 + 0.5),
                      color = col, width = 2 },
                    { type = "line", x1 = math.floor(10 + dx * 8 + 0.5),
                      y1 = math.floor(10 + dy * 8 + 0.5),
                      x2 = math.floor(10 + l3 + 0.5), y2 = math.floor(10 + l4 + 0.5),
                      color = col, width = 2 },
                } })
        end)
    end

    -- 日期条（图表/列表视图共用；概览=天气图标+高低温，
    -- 其他 tab=该指标数值+概率/等级+右侧小滑条，html 同款）
    local function build_daystrip(ci, y0)
        local tab = TABS[mock.S.tab]
        local n, gap = #mock.DAYS, 8
        local bw = math.floor((SW - gap * (n - 1)) / n)
        for i, day in ipairs(mock.DAYS) do
            local bx = (i - 1) * (bw + gap)
            local on = (i == mock.S.day)
            airui.button({ parent = dyn.hourly, x = SX + bx, y = y0,
                w = bw, h = 84, text = "", font_size = 16,
                style = { bg_color = on and C.accent or C.panel,
                    text_color = C.text,
                    border_color = on and C.accent or C.border,
                    border_width = 1, radius = 8, pad = 0 },
                on_click = function()
                    if mock.S.day ~= i then
                        mock.S.day = i
                        rebuild_soon()
                    end
                end })
            local tcol = on and C.on_accent or C.text
            local scol = on and C.on_accent or C.sub
            airui.label({ parent = dyn.hourly, x = SX + bx + 10, y = y0 + 4,
                w = bw - 20, h = 20, text = tostring(day.d) .. "  " .. day.w,
                color = tcol, font_size = 16 })
            if tab.icons then
                -- 概览：天气图标 + 最高/最低温
                local hl = mock.hilo(ci, i)
                theme.wicon(dyn.hourly, SX + bx + 10, y0 + 26, 26,
                    mock.hicon(ci, i, 2), on and C.accent or C.panel)
                airui.label({ parent = dyn.hourly, x = SX + bx + 46, y = y0 + 26,
                    w = bw - 56, h = 20, text = hl.hi .. "°",
                    color = tcol, font_size = 16 })
                airui.label({ parent = dyn.hourly, x = SX + bx + 46, y = y0 + 46,
                    w = bw - 56, h = 18, text = "/ " .. hl.lo .. "°",
                    color = scol, font_size = 16 })
            else
                -- 其他 tab：数值 + 概率/等级 + 右侧滑条（84 高卡内三行收拢）
                local v = tab_dayval(tab, ci, i)
                airui.label({ parent = dyn.hourly, x = SX + bx + 10, y = y0 + 24,
                    w = bw - 40, h = 20, text = v.v1, color = tcol, font_size = 16 })
                if v.v2 then
                    airui.label({ parent = dyn.hourly, x = SX + bx + 10, y = y0 + 44,
                        w = bw - 40, h = 18, text = v.v2, color = scol, font_size = 16 })
                end
                if v.v3 and v.v3 ~= "" then
                    if v.icon == "drop" then
                        draw_droplet(dyn.hourly, SX + bx + 16, y0 + 72, C.blue)
                    elseif v.icon then
                        theme.wicon(dyn.hourly, SX + bx + 10, y0 + 62, 16,
                            v.icon, on and C.accent or C.panel)
                        airui.label({ parent = dyn.hourly, x = SX + bx + 30, y = y0 + 62,
                            w = bw - 40, h = 18, text = v.v3,
                            color = v.v3col or scol, font_size = 16 })
                    else
                        airui.label({ parent = dyn.hourly, x = SX + bx + 10, y = y0 + 62,
                            w = bw - 30, h = 18, text = v.v3,
                            color = v.v3col or scol, font_size = 16 })
                    end
                end
                pcall(function()
                    local sx0, sy0 = SX + bx + bw - 22, y0 + 16
                    local ky = 8 + math.floor((v.knob or 0.5) * 48)
                    -- html 同款：旋钮以上浅色、以下整段深色（C.slider_lo 按主题派生，够深）
                    airui.shape({ parent = dyn.hourly, x = sx0, y = sy0, w = 12, h = 64,
                        items = {
                            { type = "rect", x = 2, y = 0, w = 8, h = ky,
                              radius = 4, color = C.border, width = 1,
                              fill = true, fill_color = C.border, fill_opacity = 255 },
                            { type = "rect", x = 2, y = ky, w = 8, h = 64 - ky,
                              radius = 4, color = C.slider_lo, width = 1,
                              fill = true, fill_color = C.slider_lo, fill_opacity = 255 },
                            { type = "circle", cx = 6, cy = ky, r = 5,
                              color = v.knobcol or tab.color, width = 1,
                              fill = true, fill_color = v.knobcol or tab.color,
                              fill_opacity = 255 } } })
                end)
            end
        end
    end

    local function build_chart_body(ci, di, y0)
        local tab = TABS[mock.S.tab]
        -- 图表贴锚点底：chh = 390-(y0+92)，日期条压矮后开关行打开也放得下
        -- （概览/体感 222 高，其余 258 高；不超出 → 默认可滚标志不触发）
        local chh = 390 - (y0 + 92)
        local ca = airui.container({ parent = dyn.hourly, x = SX, y = y0 + 92,
            w = SW, h = chh, color = C.card, radius = 8 })
        local top = 6
        local ok, err = pcall(function()
            if tab.icons then
                -- 概览：小时图标行 + 温度数字行（html 同款）
                for i = 1, 12 do
                    local cxx = math.floor(SW * (i - 0.5) / 12)
                    theme.wicon(ca, cxx - 12, 6, 24, mock.hicon(ci, di, i), C.card)
                    airui.label({ parent = ca, x = cxx - 32, y = 32, w = 64, h = 20,
                        text = tostring(mock.hourly(ci, di, 1)[i]) .. "°",
                        color = C.text, font_size = 16,
                        align = airui.TEXT_ALIGN_CENTER })
                end
                top = 58
            elseif tab.arrows then
                -- 风速：小时风向箭头行（html 同款，不再是天气图标）
                local angs = { ["东风"] = 0, ["东南风"] = -45, ["南风"] = -90, ["东北风"] = 45 }
                for i = 1, 12 do
                    local cxx = math.floor(SW * (i - 0.5) / 12)
                    draw_arrow(ca, cxx, 18, angs[DIRS[(ci + i) % 4 + 1]] or 0, C.sub)
                end
                top = 40
            end
            local chrt = theme.chart(ca, { x = 4, y = top,
                w = SW - 8, h = chh - top - 4 },
                { type = tab.type, y_min = tab.ymin, y_max = tab.ymax,
                  points = 12, ulabel = tab.ulabel, color = tab.color,
                  cats = mock.HOURS,
                  -- 阵风打开时主序列也变面积（html 同款双层渐变面积图）
                  fill = (tab.fill == true)
                      or (tab.swkey == "gust_on" and mock.S.gust_on == true),
                  bar_radius = tab.bar_r })
            theme.set_chart(chrt, mock.hourly(ci, di, mock.S.tab))
            -- 附加线（html 同款开关：概览体感/风速阵风/湿度露点/体感温度温度）
            local winds = mock.hourly(ci, di, 3)
            if tab.swkey == "gust_on" and mock.S.gust_on then
                pcall(function()
                    local g = {}
                    for i = 1, 12 do g[i] = winds[i] + 6 + (i % 3) * 2 end
                    chrt:add_series({ color = C.blue, name = "阵风", fill = true })
                    chrt:set_values(2, g)
                end)
            elseif tab.swkey == "dew_on" and mock.S.dew_on then
                pcall(function()
                    local hums = mock.hourly(ci, di, 4)
                    local temps = mock.hourly(ci, di, 1)
                    local d = {}
                    for i = 1, 12 do
                        local v = temps[i] - math.floor((100 - hums[i]) / 5 + 0.5)
                        if v < -10 then v = -10 end
                        d[i] = v
                    end
                    chrt:add_series({ color = C.cyan, name = "露点", fill = false })
                    chrt:set_values(2, d)
                end)
            elseif tab.swkey == "ftemp_on" and mock.S.ftemp_on then
                pcall(function()
                    chrt:add_series({ color = C.orange, name = "温度", fill = false })
                    chrt:set_values(2, mock.hourly(ci, di, 1))
                end)
            elseif tab.icons and mock.S.feel_on then
                pcall(function()
                    chrt:add_series({ color = C.orange, name = "体感", fill = false })
                    chrt:set_values(2, mock.hourly(ci, di, 9))
                end)
            end
        end)
        if not ok then
            log.error("page", "chart build failed: " .. tostring(err)
                .. "\n" .. tostring(debug.traceback()))
        end
        return y0 + 104 + chh + 14   -- 返回锚点内局部 y（详细信息起点）
    end

    local function build_list_body(ci, di, y0)
        -- 列表视图：横向滑动的小时卡片（html 同款，scrollable=true 横向拖拽）
        -- 高度 232：锚点贴底 390，列表 y=y0+114，不得超出（否则整页又能滑）
        local lh = 232
        local ls = airui.container({ parent = dyn.hourly, x = SX, y = y0 + 10,
            w = SW, h = lh, color = C.card, radius = 8, scrollable = true })
        local temps = mock.hourly(ci, di, 1)
        local feels = mock.hourly(ci, di, 9)
        local precs = mock.hourly(ci, di, 2)
        local winds = mock.hourly(ci, di, 3)
        local now = tostring(os.date("%H:%M"))
        for i = 1, 12 do
            local bx = (i - 1) * 128
            local kind = mock.hicon(ci, di, i)
            airui.container({ parent = ls, x = bx + 5, y = 10,
                w = 118, h = lh - 40,
                color = C.card_soft, border_color = C.border,
                border_width = 1, radius = 8 })
            airui.label({ parent = ls, x = bx + 13, y = 12, w = 100, h = 20,
                text = (i == 1) and now or mock.HOURS[i],
                color = C.sub, font_size = 16 })
            theme.wicon(ls, bx + 13, 32, 28, kind, C.panel)
            airui.label({ parent = ls, x = bx + 13, y = 62, w = 100, h = 26,
                text = temps[i] .. "°", color = C.text, font_size = 26 })
            airui.label({ parent = ls, x = bx + 13, y = 92, w = 100, h = 20,
                text = ICON_TEXT[kind] or "多云",
                color = C.text, font_size = 16 })
            airui.label({ parent = ls, x = bx + 13, y = 114, w = 100, h = 20,
                text = "体感 " .. feels[i] .. "°", color = C.sub, font_size = 16 })
            airui.label({ parent = ls, x = bx + 13, y = 138, w = 100, h = 20,
                text = "降水 " .. math.floor(precs[i] / 12) .. "%",
                color = C.sub, font_size = 16 })
            airui.label({ parent = ls, x = bx + 13, y = 162, w = 100, h = 20,
                text = "风速 " .. winds[i] .. "公里", color = C.sub, font_size = 16 })
        end
        return y0 + 10 + lh + 14
    end

    local function build_hourly()
        local ci, di = mock.S.city, mock.S.day
        -- 标题行：每小时预报 + 9 tab + 图表/列表
        local hd = airui.container({ parent = dyn.hourly, x = SX, y = 0,
            w = SW, h = 34, color = C.bg })
        airui.label({ parent = hd, x = 0, y = 6, w = 110, h = 24,
            text = "每小时预报", color = C.text, font_size = 16 })
        local widths = { 64, 64, 64, 64, 64, 64, 76, 76, 88 }
        local tx = 118
        for i, t in ipairs(TABS) do
            local on = (i == mock.S.tab)
            airui.button({ parent = hd, x = tx, y = 3, w = widths[i], h = 28,
                text = t.name, font_size = 16,
                style = { bg_color = on and C.accent or C.deep,
                    text_color = on and C.on_accent or C.text,
                    border_color = on and C.accent or C.border,
                    border_width = 1, radius = 14, pad = 0 },
                on_click = function()
                    if mock.S.tab ~= i then
                        mock.S.tab = i
                        mock.S.view = "图表"   -- 切 tab 回到图表视图（html 行为）
                        rebuild_soon()
                    end
                end })
            tx = tx + widths[i] + 6
        end
        -- 图表/列表 切换（右对齐，html 同款胶囊）
        for i, name in ipairs({ "图表", "列表" }) do
            local on = (mock.S.view == name)
            airui.button({ parent = hd, x = SW - (2 - i) * 78 - 80, y = 3,
                w = 72, h = 28, text = name, font_size = 16,
                style = { bg_color = on and C.accent or C.deep,
                    text_color = on and C.on_accent or C.text,
                    border_color = on and C.accent or C.border,
                    border_width = 1, radius = 14, pad = 0 },
                on_click = function()
                    if mock.S.view ~= name then
                        mock.S.view = name
                        rebuild_soon()
                    end
                end })
        end
        -- 主体：图表（日期条+图表）或 列表
        -- 踩坑：mock.S.view 存的是中文键"图表"/"列表"，分支判断必须用同一个值，
        --       之前写成 == "list" 导致点列表只有标题变、主体还是图表
        local is_list = (mock.S.view == "列表")
        local y0 = 40
        local curt = TABS[mock.S.tab]
        -- 图表附加线开关行（html 同款：概览体感温度/风速阵风/湿度露点/体感温度温度）
        if curt.sw and not is_list then
            airui.label({ parent = dyn.hourly, x = SW - 160, y = 44,
                w = 92, h = 22, text = curt.sw, color = C.sub, font_size = 16,
                align = airui.TEXT_ALIGN_RIGHT })
            mkswitch(dyn.hourly, SW - 60, 42, mock.S[curt.swkey] == true, function()
                mock.S[curt.swkey] = not mock.S[curt.swkey]
                rebuild_soon()
            end)
            y0 = 76
        end
        -- 日期条两种视图都显示（html 同款）
        build_daystrip(ci, y0)
        if is_list then
            detail_y = 172 + build_list_body(ci, di, y0 + 104)
        else
            detail_y = 172 + build_chart_body(ci, di, y0)
        end
    end

    ----------------------------------------------------------------
    -- ③ 天气详细信息（挂在 dyn.detail 锚点下，12 卡带 html 同款小图形）
    ----------------------------------------------------------------
    local function dcard(s, px, py, pw, ph, name)
        airui.container({ parent = s, x = px, y = py, w = pw, h = ph,
            color = C.card_soft,
            border_color = C.border, border_width = 1, radius = 8 })
        -- 性能：详情卡不再画装饰角标（brackets），滑动重绘量减少
        airui.label({ parent = s, x = px + 10, y = py + 8, w = pw - 20, h = 20,
            text = name, color = C.sub, font_size = 16 })
    end

    local function build_detail()
        local ci, di = mock.S.city, mock.S.day
        local hl    = mock.hilo(ci, di)
        local cond  = mock.cond(ci, di)
        local temps = mock.hourly(ci, di, 1)
        local feels = mock.hourly(ci, di, 9)
        local hums  = mock.hourly(ci, di, 4)
        local key   = ci .. "_" .. di .. "_"
        local wind  = mock.rint(key .. "wind", 3, 15, 1)
        local hum   = mock.rint(key .. "hum", 55, 98, 2)
        local uv    = mock.rint(key .. "uv", 1, 8, 1)
        local aqi   = mock.rint(key .. "aqi", 40, 110, 2)
        local pres  = mock.rint(key .. "pres", 1000, 1028, 1)
        local vis   = mock.next(key .. "vis", 1, 15, 0.5)
        local prec  = mock.next(key .. "prec", 0, 14, 1)
        local temp  = mock.cur_temp(ci, di)

        local s = airui.container({ parent = DETAIL_PARENT or dyn.detail,
            x = SX, y = 0, w = SW, h = 552, color = C.bg })
        airui.label({ parent = s, x = 0, y = 0, w = 200, h = 26,
            text = "天气详细信息", color = C.text, font_size = 16 })
        airui.label({ parent = s, x = 210, y = 4, w = 300, h = 22,
            text = "11月" .. mock.DAYS[di].d .. "日 " .. mock.DAYS[di].w,
            color = C.sub, font_size = 16 })

        -- 卡高 166：3 行 36+3*166+2*8=550 ≤ 556，详情页一屏放下不滚动
        local pw, ph, gap = 246, 166, 8
        local function cell(i)
            local col = (i - 1) % 4
            local row = math.floor((i - 1) / 4)
            return col * (pw + gap), 36 + row * (ph + gap)
        end

        -- 1 温度：迷你曲线 + 大数值
        do
            local px, py = cell(1)
            dcard(s, px, py, pw, ph, "温度")
            theme.spark(s, px + 14, py + 30, 218, 44, C.green, temps, hl.lo - 3, hl.hi + 3)
            airui.label({ parent = s, x = px + 14, y = py + 78, w = 120, h = 32,
                text = temp .. "°", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 130, y = py + 84, w = 100, h = 22,
                text = "稳定", color = C.green, font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "感觉保持当前温度 " .. temp .. "°。",
                color = C.sub, font_size = 16 })
        end
        -- 2 体感温度：蓝色曲线
        do
            local px, py = cell(2)
            dcard(s, px, py, pw, ph, "体感温度")
            theme.spark(s, px + 14, py + 30, 218, 44, C.blue, feels, hl.lo - 2, hl.hi + 4)
            airui.label({ parent = s, x = px + 14, y = py + 78, w = 120, h = 32,
                text = feels[2] .. "°", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 130, y = py + 84, w = 100, h = 22,
                text = "舒适", color = C.green, font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "感觉比实际温度更" .. (feels[2] > temp and "暖和" or "凉爽") .. "。",
                color = C.sub, font_size = 16 })
        end
        -- 3 云量：深色大圆 + 四朵云 + 居中文字
        do
            local px, py = cell(3)
            dcard(s, px, py, pw, ph, "云量")
            local ccx, ccy = px + 62, py + 66
            pcall(function()
                airui.shape({ parent = s, x = ccx - 46, y = ccy - 46, w = 92, h = 92,
                    items = { { type = "circle", cx = 46, cy = 46, r = 45,
                        color = 0x101A30, width = 1,
                        fill = true, fill_color = 0x101A30, fill_opacity = 255 } } })
                theme.wicon(s, ccx - 34, ccy - 32, 26, "cloud", 0x101A30)
                theme.wicon(s, ccx + 4,  ccy - 36, 24, "cloud", 0x101A30)
                theme.wicon(s, ccx - 36, ccy + 2,  24, "cloud", 0x101A30)
                theme.wicon(s, ccx + 2,  ccy + 4,  26, "cloud", 0x101A30)
            end)
            airui.label({ parent = s, x = ccx - 30, y = ccy - 10, w = 60, h = 20,
                text = cond, color = C.text, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = s, x = px + 124, y = py + 46, w = 110, h = 32,
                text = mock.rint(key .. "cloud", 40, 100, 3) .. "%",
                color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "云量较高，下午早些时更多云。", color = C.sub, font_size = 16 })
        end
        -- 4 降水：深色大圆 + 雨云
        do
            local px, py = cell(4)
            dcard(s, px, py, pw, ph, "降水")
            local ccx, ccy = px + 62, py + 66
            pcall(function()
                airui.shape({ parent = s, x = ccx - 46, y = ccy - 46, w = 92, h = 92,
                    items = { { type = "circle", cx = 46, cy = 46, r = 45,
                        color = 0x101A30, width = 1,
                        fill = true, fill_color = 0x101A30, fill_opacity = 255 } } })
                theme.wicon(s, ccx - 22, ccy - 34, 44, "rain", 0x101A30)
            end)
            airui.label({ parent = s, x = ccx - 30, y = ccy + 14, w = 60, h = 20,
                text = "降雨", color = C.text, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = s, x = px + 124, y = py + 46, w = 110, h = 32,
                text = mock.fmt(prec) .. "毫米", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "预计未来 24 小时，大约 1.5 小时后开始降雨。",
                color = C.sub, font_size = 16 })
        end
        -- 5 风速：罗盘 + 数值
        do
            local px, py = cell(5)
            dcard(s, px, py, pw, ph, "风速")
            local ccx, ccy = px + 56, py + 68
            pcall(function()
                airui.shape({ parent = s, x = ccx - 44, y = ccy - 44, w = 88, h = 88,
                    items = {
                        { type = "circle", cx = 44, cy = 44, r = 42,
                          color = C.border, width = 2, fill = false },
                        { type = "line", x1 = 44, y1 = 44, x2 = 44, y2 = 16,
                          color = C.accent, width = 3 },
                        { type = "line", x1 = 44, y1 = 16, x2 = 38, y2 = 26,
                          color = C.accent, width = 3 },
                        { type = "line", x1 = 44, y1 = 16, x2 = 50, y2 = 26,
                          color = C.accent, width = 3 },
                    } })
            end)
            airui.label({ parent = s, x = ccx - 12, y = ccy - 46, w = 24, h = 18,
                text = "北", color = C.sub, font_size = 16, align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = s, x = ccx - 12, y = ccy + 30, w = 24, h = 18,
                text = "南", color = C.sub, font_size = 16, align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = s, x = ccx - 56, y = ccy - 9, w = 24, h = 18,
                text = "西", color = C.sub, font_size = 16, align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = s, x = ccx + 32, y = ccy - 9, w = 24, h = 18,
                text = "东", color = C.sub, font_size = 16, align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = s, x = px + 112, y = py + 28, w = 120, h = 20,
                text = "来自 " .. DIRS[(ci - 1) % 4 + 1], color = C.sub, font_size = 16 })
            airui.label({ parent = s, x = px + 112, y = py + 52, w = 130, h = 32,
                text = wind .. " 公里/时", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 112, y = py + 88, w = 130, h = 20,
                text = (wind + 3) .. " 公里/时 阵风", color = C.sub, font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "风力: " .. (wind < 6 and "2 (轻风)" or wind < 10 and "3 (微风)" or "4 (和风)")
                    .. "，预计保持平均风速 " .. (wind - 2) .. " 公里/时。",
                color = C.sub, font_size = 16 })
        end
        -- 6 湿度：迷你柱状 + 数值
        do
            local px, py = cell(6)
            dcard(s, px, py, pw, ph, "湿度")
            local ok, err = pcall(function()
                local vals = {}
                for i = 1, 8 do vals[i] = hums[i] end
                local mini = theme.chart(s, { x = px + 12, y = py + 30,
                    w = 116, h = 56 },
                    { type = "bar", y_max = 100, points = 8,
                      color = C.blue, ylab = false, hdiv = 2, vdiv = 0 })
                theme.set_chart(mini, vals)
            end)
            if not ok then
                log.error("page", "hum mini chart: " .. tostring(err))
            end
            airui.label({ parent = s, x = px + 140, y = py + 42, w = 100, h = 32,
                text = hum .. "%", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 140, y = py + 78, w = 100, h = 20,
                text = "露点 " .. (hl.lo - 1) .. "°", color = C.sub, font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "相对湿度 " .. hum .. "%。持续潮湿。", color = C.sub, font_size = 16 })
        end
        -- 7 紫外线：多色珠链圆环
        do
            local px, py = cell(7)
            dcard(s, px, py, pw, ph, "紫外线")
            pcall(function()
                theme.ring(s, px + 62, py + 62, 30, {
                    { f = 3, color = C.green },
                    { f = 3, color = C.yellow },
                    { f = 2, color = 0xF08A3C },
                    { f = 1.5, color = C.red },
                })
            end)
            airui.label({ parent = s, x = px + 124, y = py + 38, w = 110, h = 32,
                text = tostring(uv), color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 124, y = py + 72, w = 110, h = 22,
                text = uv <= 2 and "低" or uv <= 5 and "中等" or "高",
                color = uv <= 2 and C.green or uv <= 5 and C.yellow or C.red,
                font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "白天的最高紫外线强度较低。", color = C.sub, font_size = 16 })
        end
        -- 8 空气质量指数：橙色进度圆环
        do
            local px, py = cell(8)
            dcard(s, px, py, pw, ph, "空气质量指数")
            pcall(function()
                local frac = math.min(aqi / 150, 1)
                theme.ring(s, px + 62, py + 62, 30, {
                    { f = frac, color = 0xF5A623 },
                    { f = 1 - frac + 0.001, color = C.border },
                })
            end)
            airui.label({ parent = s, x = px + 124, y = py + 38, w = 110, h = 32,
                text = tostring(aqi), color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 124, y = py + 72, w = 110, h = 22,
                text = aqi <= 80 and "良" or "轻度污染",
                color = aqi <= 80 and C.green or C.yellow, font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "空气质量有恶化趋势。主要污染物: PM2.5。",
                color = C.sub, font_size = 16 })
        end
        -- 9 能见度：绿色珠条 + 数值
        do
            local px, py = cell(9)
            dcard(s, px, py, pw, ph, "能见度")
            pcall(function()
                local rows = { 11, 9, 8, 6, 5 }
                for r = 1, 5 do
                    local items = {}
                    for k = 0, rows[r] - 1 do
                        items[#items + 1] = { type = "circle",
                            cx = 6 + k * 12, cy = 4, r = 4,
                            color = C.green, width = 1,
                            fill = true, fill_color = C.green, fill_opacity = 255 }
                    end
                    airui.shape({ parent = s, x = px + 14, y = py + 28 + (r - 1) * 12,
                        w = 150, h = 8, items = items })
                end
            end)
            airui.label({ parent = s, x = px + 14, y = py + 90, w = 160, h = 32,
                text = mock.fmt(vis) .. "公里", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 160, y = py + 96, w = 80, h = 22,
                text = "良好", color = C.green, font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 122, w = pw - 28, h = 36,
                text = "预计明天的能见度与今天的相似。", color = C.sub, font_size = 16 })
        end
        -- 10 气压：紫色曲线
        do
            local px, py = cell(10)
            dcard(s, px, py, pw, ph, "气压")
            theme.spark(s, px + 14, py + 30, 218, 40, C.purple,
                mock.hourly(ci, di, 6), 980, 1040)
            airui.label({ parent = s, x = px + 14, y = py + 74, w = 180, h = 32,
                text = pres .. " hPa", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 150, y = py + 80, w = 90, h = 22,
                text = "缓慢上升", color = C.yellow, font_size = 16 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "预计在未来两到三个小时内将缓慢上升。",
                color = C.sub, font_size = 16 })
        end
        -- 11 太阳：弧线 + 日出日落
        do
            local px, py = cell(11)
            dcard(s, px, py, pw, ph, "太阳")
            pcall(function()
                airui.shape({ parent = s, x = px + 14, y = py + 28, w = 218, h = 48,
                    items = {
                        { type = "line", x1 = 0,   y1 = 42, x2 = 50,  y2 = 16, color = C.yellow, width = 3 },
                        { type = "line", x1 = 50,  y1 = 16, x2 = 109, y2 = 6,  color = C.yellow, width = 3 },
                        { type = "line", x1 = 109, y1 = 6,  x2 = 168, y2 = 16, color = C.yellow, width = 3 },
                        { type = "line", x1 = 168, y1 = 16, x2 = 218, y2 = 42, color = C.yellow, width = 3 },
                        { type = "circle", cx = 80, cy = 12, r = 5,
                          color = C.yellow, width = 1, fill = true,
                          fill_color = C.yellow, fill_opacity = 255 },
                        { type = "circle", cx = 150, cy = 15, r = 5,
                          color = C.border, width = 1, fill = true,
                          fill_color = C.border, fill_opacity = 255 },
                    } })
            end)
            airui.label({ parent = s, x = px + 14, y = py + 78, w = 180, h = 32,
                text = "06:18", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "日出 06:18   日落 16:56", color = C.sub, font_size = 16 })
        end
        -- 12 月相：半月盘
        do
            local px, py = cell(12)
            dcard(s, px, py, pw, ph, "月相")
            pcall(function()
                airui.shape({ parent = s, x = px + 26, y = py + 32, w = 78, h = 78,
                    items = {
                        { type = "circle", cx = 39, cy = 39, r = 32,
                          color = C.yellow, width = 1,
                          fill = true, fill_color = C.yellow, fill_opacity = 255 },
                        { type = "circle", cx = 53, cy = 39, r = 28,
                          color = 0x1B2745, width = 1,
                          fill = true, fill_color = 0x1B2745, fill_opacity = 255 },
                    } })
            end)
            airui.label({ parent = s, x = px + 134, y = py + 52, w = 100, h = 32,
                text = "月相", color = C.text, font_size = 26 })
            airui.label({ parent = s, x = px + 14, y = py + 116, w = pw - 28, h = 36,
                text = "亏凸月", color = C.sub, font_size = 16 })
        end
    end

    ----------------------------------------------------------------
    -- ④ 重建（城市/日期/tab/视图/开关 切换统一入口）
    --    只在 defer/rebuild_soon（事件外）调用；三段各自挂在锚点容器下
    ----------------------------------------------------------------
    rebuild = function()
        close_popup()
        build_detail_shared = build_detail   -- 供页面2复用（顶部按钮切换）
        pcall(function()
            if dyn.hero   then dyn.hero:destroy()   dyn.hero   = nil end
            if dyn.hourly then dyn.hourly:destroy() dyn.hourly = nil end
            for i = 1, #chip_lbls do chip_lbls[i] = nil end
        end)
        dyn.hero = airui.container({ parent = scroll, x = 0, y = 0,
            w = W, h = 164, color = C.bg })
        pcall(function() build_hero() end)
        -- 踩坑：airui 容器走 lv_obj_create，LVGL 默认带可滚动标志，
        --       scrollable 参数从未生效——内容超出容器 1px 就能滑。
        --       锚点严格贴底（164+390=554 ≤ 556），内容不超出 → 彻底无滚动
        dyn.hourly = airui.container({ parent = scroll, x = 0, y = 164,
            w = W, h = 390, color = C.bg })
        pcall(function() build_hourly() end)
        -- 详细信息 12 卡已拆到页面2，主页面到此为止（滚动距离减半）
    end

    rebuild()
    update_chips()

    -- 1.5s 刷新：顶栏时间 + hero 指标条 live 微动
    return function()
        pcall(function()
            local t = os.date("%H:%M")
            if t then h_time:set_text(t) end
        end)
        pcall(update_chips)
    end
end, { no_nav = true })

--------------------------------------------------------------------
-- 页面2：天气详细信息（独立页面，顶栏"返回"切回主页面）
-- 滑动卡顿优化：12 张详情卡从主页面长滚动里拆出，主页面控件数减半
--------------------------------------------------------------------
theme.make_page(2, "天气详细信息", function(root, cx, cy, cw, ch, rerender)
    local C = theme.C
    local W, H = theme.W, theme.H

    local function defer(fn) sys.timerStart(fn, 30) end

    -- 顶栏：返回 + 标题 + 主题切换（与主页面顶栏同款风格）
    airui.button({ parent = root, x = 8, y = 7, w = 100, h = 30,
        text = "返回", font_size = 16,
        style = { bg_color = C.deep, text_color = C.text,
            border_color = C.border, border_width = 1, radius = 15, pad = 0 },
        on_click = function()
            defer(function() theme.open_page(1) end)
        end })
    airui.label({ parent = root, x = 130, y = 10, w = 200, h = 24,
        text = "天气详细信息", color = C.text, font_size = 16 })
    local tbtn = airui.button({ parent = root, x = W - 48, y = 5, w = 40, h = 34,
        text = "", font_size = 16,
        style = { bg_color = C.bg, text_color = C.text,
            border_width = 0, radius = 8, pad = 0 },
        on_click = function()
            theme.toggle_theme()
            sys.timerStart(rerender, 30)
        end })
    pcall(function()
        theme.wicon(tbtn, 6, 3, 28, (theme.cur == "dark") and "moon" or "sun", C.bg)
    end)

    -- 详情区（12 卡压进一屏：36+3*166+2*8=550 ≤ 556，不再滚动）
    local scroll = airui.container({ parent = root, x = 0, y = 44,
        w = W, h = H - 44, color = C.bg })
    DETAIL_PARENT = airui.container({ parent = scroll, x = 0, y = 0,
        w = W, h = 552, color = C.bg })
    if build_detail_shared then
        pcall(build_detail_shared)
    end
    -- 详情页数据跟随主页面当前城市/日期（mock.S），无需刷新定时器
end, { no_nav = true })
