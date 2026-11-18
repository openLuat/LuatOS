--[[
@module page_nav
@summary 导航页：全宽地图 + 右侧音乐/车辆卡 + 底部 dock
布局与 preview.html 对应：nav-map 708 宽 / nav-side 272 宽 / dockbar 58 高
]]

local theme = require "theme"
local _ln, _ci, _rc = theme._ln, theme._ci, theme._rc
local W, H, TOP = theme.W, theme.H, theme.TOP_H

theme.make_page("nav", function(root, M)
    local C = theme.C
    local db = theme.debounce()
    local go = theme.go_defer

    local MAPX, MAPW = 16, W - 32 - 272 - 12
    local SIDEW = 272
    local SIDEX = MAPX + MAPW + 12
    local BODYY = TOP + 2
    -- 内容区一直铺到 dock 上方 4px（原来留 10px，底部看起来「缺一块」）
    local BODYH = H - BODYY - (theme.DOCK_H + 12 + 4)

    ----------------------------------------------------------------
    -- 地图区
    ----------------------------------------------------------------
    local mp = { x = MAPX, y = BODYY, w = MAPW, h = BODYH }
    airui.container({ parent = root, x = mp.x, y = mp.y, w = mp.w, h = mp.h,
        color = C.card2, radius = 14, border_color = C.line, border_width = 1 })
    -- SVG 640×430 → 地图实际尺寸的缩放
    local fx, fy = mp.w / 640, mp.h / 430
    local function P(x, y) return mp.x + x * fx, mp.y + y * fy end

    -- 坐标映射 + 边界夹取（踩坑：超出画布的图元会被画到画布外，
    -- 表现为巨大色块，同时让父容器出现滚动、把 dock 顶出屏幕）
    -- 注意：图元坐标必须是「相对画布」的，而 P() 返回的是屏幕绝对坐标。
    -- 原来 pc() 直接返回绝对坐标，再交给定位在 (mp.x,mp.y) 的 shape 容器，
    -- 等于偏移加了两次 —— 路网/路线/定位点全被画到地图外，
    -- 地图区只剩一层深色底，看起来就是「下方一大片黑色空白」。
    local function pc(x, y)
        local axp, ayp = P(x, y)
        axp = axp - mp.x
        ayp = ayp - mp.y
        if axp < 2 then axp = 2 elseif axp > mp.w - 3 then axp = mp.w - 3 end
        if ayp < 2 then ayp = 2 elseif ayp > mp.h - 3 then ayp = mp.h - 3 end
        return math.floor(axp), math.floor(ayp)
    end
    local function L(items, x1, y1, x2, y2, col, wid)
        local axp, ayp = pc(x1, y1)
        local bxp, byp = pc(x2, y2)
        _ln(items, axp, ayp, bxp, byp, col, wid)
    end

    -- 底色（光晕改为画布内的柔和矩形，不再用超大圆）
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, {
        { type = "rect", x = 0, y = 0, w = mp.w - 2, h = mp.h - 2, color = C.page,
          width = 1, radius = 14, fill = true, fill_color = 0x081522, fill_opacity = 255 },
        { type = "rect", x = 10, y = 10, w = mp.w - 140, h = math.floor(mp.h * 0.52),
          color = theme.blend(0x1E5CA0, 0x081522, 0.20), width = 1, radius = 14,
          fill = true, fill_color = theme.blend(0x1E5CA0, 0x081522, 0.20),
          fill_opacity = 255 },
    })
    -- 细路网
    local grid = {}
    local gcol = theme.blend(0x123A5E, 0x081522, 0.5)
    L(grid, -20, 340, 660, 210, gcol, 1)
    L(grid, -20, 250, 660, 120, gcol, 1)
    L(grid, -20, 160, 660, 30,  gcol, 1)
    L(grid, 90, 440, 90, -10,   gcol, 1)
    L(grid, 230, 440, 230, -10, gcol, 1)
    L(grid, 370, 440, 370, -10, gcol, 1)
    L(grid, 510, 440, 510, -10, gcol, 1)
    L(grid, -20, 430, 660, 300, gcol, 1)
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, grid)
    -- 主干道
    local main = {}
    local mcol = theme.blend(0x1B4E78, 0x081522, 0.55)
    L(main, -20, 300, 660, 170, mcol, 4)
    L(main, 230, -10, 230, 440, mcol, 4)
    L(main, -20, 200, 660, 60,  mcol, 4)
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, main)
    -- 路线：流动虚线（对照原型 .nav-map path{stroke-dasharray:10 6; animation:routeFlow}）
    -- 三段各占一个 shape：整条线和一次性塞进去会超过「单 shape ≤30 图元」
    local ROUTE = {
        { 120, 470, 120, 250, 0x35D6E8 },
        { 120, 250, 300, 130, theme.blend(0x35D6E8, 0x2E7DFF, 0.5) },
        { 300, 130, 300, 10,   0x2E7DFF },
    }
    local DASH, GAPW = 12, 8
    local PERIOD = DASH + GAPW
    local route_shp = {}
    for i = 1, #ROUTE do
        route_shp[i] = airui.shape({ parent = root, x = mp.x, y = mp.y,
            w = mp.w, h = mp.h, items = {} })
    end
    local phase = 0
    local function route_draw()
        for i, seg in ipairs(ROUTE) do
            local ax, ay = pc(seg[1], seg[2])
            local bx, by = pc(seg[3], seg[4])
            local dx, dy = bx - ax, by - ay
            local len = math.sqrt(dx * dx + dy * dy)
            local it = {}
            if len > 1 then
                local ux, uy = dx / len, dy / len
                local t = -(phase % PERIOD)      -- 负偏移 = 虚线朝终点方向跑
                while t < len and #it < 28 do
                    local s0 = math.max(0, t)
                    local s1 = math.min(len, t + DASH)
                    if s1 - s0 > 0.5 then
                        _ln(it, math.floor(ax + ux * s0), math.floor(ay + uy * s0),
                                math.floor(ax + ux * s1), math.floor(ay + uy * s1),
                                seg[5], 7)
                    end
                    t = t + PERIOD
                end
            end
            pcall(function() route_shp[i]:set_items(it) end)
        end
    end
    route_draw()
    -- 120ms 一帧、每帧走 5px ≈ 42px/s（原型是 88px / 2.4s ≈ 37px/s）
    M.loop(function()
        phase = (phase + 5) % PERIOD
        route_draw()
    end, 120)
    local px0, py0 = P(120, 250)
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, {
        { type = "circle", cx = math.floor(px0 - mp.x), cy = math.floor(py0 - mp.y),
          r = 9, color = C.cyan, width = 3, fill = true,
          fill_color = 0x062033, fill_opacity = 255 },
    })
    local dx, dy = P(300, 130)
    theme.shapes(root, mp.x, mp.y, mp.w, mp.h, {
        { type = "circle", cx = math.floor(dx - mp.x), cy = math.floor(dy - mp.y),
          r = 16, color = theme.blend(0x2E7DFF, 0x081522, 0.3), width = 1,
          fill = true, fill_color = theme.blend(0x2E7DFF, 0x081522, 0.3),
          fill_opacity = 255 },
        { type = "circle", cx = math.floor(dx - mp.x), cy = math.floor(dy - mp.y),
          r = 7, color = C.bright, width = 1, fill = true,
          fill_color = C.bright, fill_opacity = 255 },
    })

    -- 顶部：返回键
    -- 右侧那排 search / locate / fav / more 小图标已按用户要求去掉：
    -- 24px 里用 2px 细线画星形/放大镜，只会糊成几团，和原型的干净图标差很远
    -- 定位十字图标 + 目的地文字也已按用户要求去掉，只保留返回键
    local ny = mp.y + 12
    theme.shapes(root, mp.x + 12, ny - 2, 30, 30, {
        { type = "circle", cx = 15, cy = 15, r = 14, color = C.line, width = 1,
          fill = true, fill_color = C.float, fill_opacity = 255 } })
    theme.icon(root, mp.x + 18, ny + 4, 18, "left", C.bright)
    theme.click(root, mp.x + 12, ny - 2, 30, 30, function() theme.back_defer() end, 15)

    -- 左上转向卡（24,96）
    theme.icon(root, mp.x + 24, mp.y + 96, 46, "left", C.bright, 3)
    airui.label({ parent = root, x = mp.x + 82, y = mp.y + 92, w = 140, h = 36,
        text = "300m", color = 0xFFFFFF, font_size = 34 })
    airui.label({ parent = root, x = mp.x + 82, y = mp.y + 130, w = 140, h = 20,
        text = MOCK.nav.turn_sub, color = C.sub, font_size = 16 })

    -- 地图上的语音球 + 「小迪去公司路况怎么样」气泡已按用户要求去掉

    -- 底部：天气卡 + 近期使用的APP
    -- 离地图底 12px 会让这两张卡与右侧车辆卡底部差 12px，看起来「底部缺一块」；改到 4px 铺满
    local fy = mp.y + mp.h - 4 - 76
    local wc = { x = mp.x + 14, y = fy, w = 214, h = 76 }
    airui.container({ parent = root, x = wc.x, y = wc.y, w = wc.w, h = wc.h,
        color = C.float, radius = 12, border_color = C.line, border_width = 1 })
    airui.label({ parent = root, x = wc.x + 12, y = wc.y + 8, w = wc.w - 24, h = 20,
        text = MOCK.weather.nav_city, color = C.title, font_size = 16 })
    airui.label({ parent = root, x = wc.x + 12, y = wc.y + 28, w = 44, h = 24,
        text = tostring(MOCK.weather.nav_temp), color = C.text, font_size = 22 })
    airui.label({ parent = root, x = wc.x + 52, y = wc.y + 32, w = 90, h = 20,
        text = "°C " .. MOCK.weather.nav_cond, color = C.sub, font_size = 16 })
    airui.label({ parent = root, x = wc.x + 12, y = wc.y + 54, w = wc.w - 24, h = 18,
        text = "降雨量 1 · 湿度 60% · 3级", color = C.dim, font_size = 16 })
    local wcb = airui.container({ parent = root, x = wc.x, y = wc.y, w = wc.w, h = wc.h,
        color = C.bg, color_opacity = 1, radius = 12 })
    wcb:set_on_click(function() db(function() go("weather") end) end)

    local rc = { x = wc.x + wc.w + 12, y = fy,
        w = mp.x + mp.w - 14 - (wc.x + wc.w + 12), h = 76 }
    airui.container({ parent = root, x = rc.x, y = rc.y, w = rc.w, h = rc.h,
        color = C.float, radius = 12, border_color = C.line, border_width = 1 })
    airui.label({ parent = root, x = rc.x + 12, y = rc.y + 8, w = rc.w - 24, h = 20,
        text = "近期使用的APP", color = C.sub, font_size = 16 })
    local recents = {
        { name = "nav",   c1 = 0x34D399, c2 = 0x0B5B45, kind = "nav" },
        { name = "music", c1 = 0x22C4E0, c2 = 0x0B5C86, kind = "music" },
        { name = "car",   c1 = 0x2E7DFF, c2 = 0x123C8A, kind = "car" },
        { name = "voice", c1 = 0xF5A623, c2 = 0x7A4306, kind = "mic" },
    }
    for i, r in ipairs(recents) do
        local ix = rc.x + 12 + (i - 1) * 52
        airui.shape({ parent = root, x = ix, y = rc.y + 30, w = 40, h = 40, items = {
            { type = "circle", cx = 20, cy = 20, r = 19,
              color = theme.blend(r.c1, r.c2, 0.35), width = 1,
              fill = true, fill_color = theme.blend(r.c1, r.c2, 0.55),
              fill_opacity = 255 } } })
        theme.icon(root, ix + 10, rc.y + 40, 20, r.kind, C.bright)
        local b = airui.container({ parent = root, x = ix, y = rc.y + 30, w = 40, h = 40,
            color = C.bg, color_opacity = 1 })
        b:set_on_click(function() db(function() go(r.name) end) end)
    end

    ----------------------------------------------------------------
    -- 右侧栏 272 宽：音乐卡 278 高 + 车辆卡
    ----------------------------------------------------------------
    local mc = { x = SIDEX, y = BODYY, w = SIDEW, h = 278 }
    theme.card(root, mc)
    theme.card_head(root, mc, "音乐", "更多", C.sub)
    local mbtn = airui.container({ parent = root, x = mc.x, y = mc.y,
        w = mc.w, h = mc.h, color = C.bg, color_opacity = 1, radius = 14 })
    mbtn:set_on_click(function() db(function() go("music") end) end)

    local cv = MOCK.mu_song().cv_bg
    airui.container({ parent = root, x = mc.x + 12, y = mc.y + 30, w = 74, h = 74,
        color = cv, radius = 8 })
    -- 封面山形剪影（照 svg 96×96 的 path 采样，顶边有起伏，且坐标全在 74×74 画布内）
    local dk = theme.blend(0x000000, cv, 0.35)
    local cf = 74 / 96
    theme.shapes(root, mc.x + 12, mc.y + 30, 74, 74, {
        { type = "rect", x = 0, y = math.floor(52 * cf), w = 74,
          h = math.ceil(74 - 52 * cf), color = dk, width = 1, radius = 0,
          fill = true, fill_color = dk, fill_opacity = 255 },
    })
    local wv = {}
    for _, s in ipairs({ { 0, 62, 16, 53 }, { 16, 53, 32, 65 }, { 32, 65, 48, 57 },
                         { 48, 57, 72, 47 }, { 72, 47, 96, 52 } }) do
        _ln(wv, math.floor(s[1] * cf), math.floor(s[2] * cf),
                 math.floor(s[3] * cf), math.floor(s[4] * cf), dk, 4)
    end
    theme.shapes(root, mc.x + 12, mc.y + 30, 74, 74, wv)
    airui.label({ parent = root, x = mc.x + 18, y = mc.y + 36, w = 60, h = 18,
        text = MOCK.mu_song().title, color = C.bright, font_size = 16 })
    local dx0 = mc.x + 12 + 74 + 10
    local mtitle = airui.label({ parent = root, x = dx0, y = mc.y + 32, w = mc.w - 98,
        h = 20, text = MOCK.mu_song().title, color = C.text, font_size = 17 })
    local martist = airui.label({ parent = root, x = dx0, y = mc.y + 54, w = mc.w - 98,
        h = 18, text = MOCK.mu_song().artist, color = C.sub, font_size = 16 })
    local prog1, mcur
    pcall(function()
        -- 旋钮实际直径 = 控件高 + 主题给 KNOB part 的 pad_all*2。
        -- lv_theme_default 里 KNOB 是 pad_all = DPX(6)，position_knob() 把这块
        -- pad 往 coords 外面加，所以 h=12 时白块是 12+6+6 = 24px，看着还是个大
        -- 方块（用户反馈「拖动图标有点大」）。airui 的 style.pad 只设 MAIN part，
        -- 改不了 KNOB 的 pad，只能靠压 h 来缩旋钮：
        -- h=6 → 旋钮 18px；pad=1 → 轨道 6-2 = 4px 粗；
        -- radius 给 9（> 轨道半高），轨道两头是圆头，旋钮就成 18px 正圆
        prog1 = airui.slider({ parent = root, x = dx0, y = mc.y + 74,
            w = mc.w - 98, h = 6,
            min = 0, max = math.max(1, MOCK.mu_dur()), value = MOCK.music.pos,
            style = { bg_color = C.track, bg_opa = 255,
                indicator_color = C.blue, knob_color = C.knob,
                radius = 9, pad = 1 },
            on_change = function(self)
                local v
                if type(self) == "number" then
                    v = self
                else
                    pcall(function() v = self:get_value() end)
                end
                if type(v) ~= "number" then return end
                MOCK.mu_seek(v)
                pcall(function() mcur:set_text(MOCK.mmss(MOCK.music.pos)) end)
            end })
        if not prog1 then
            -- 老固件没有 slider 时退回自绘进度条（只显示、不可拖）
            prog1 = theme.progress(root, { x = dx0, y = mc.y + 78, w = mc.w - 98, h = 4 })
        end
    end)
    mcur = airui.label({ parent = root, x = dx0, y = mc.y + 88, w = 60, h = 18,
        text = "00:00", color = C.dim, font_size = 16 })
    local mdur = airui.label({ parent = root, x = dx0 + mc.w - 158, y = mc.y + 88,
        w = 60, h = 18, text = MOCK.mmss(MOCK.mu_dur()), color = C.dim, font_size = 16,
        align = airui.TEXT_ALIGN_RIGHT })
    -- 播放控制（卡宽 272，播放键中心在 +144；上一首 / 下一首原来距中心 58 / 48，
    -- 一左一右不对称又偏散 → 两侧各距中心 42px，三个键凑成一簇）
    local pcy = mc.y + 116
    theme.icon(root, mc.x + 92, pcy, 20, "prev", C.icon)
    airui.shape({ parent = root, x = mc.x + 128, y = pcy - 6, w = 32, h = 32, items = {
        { type = "circle", cx = 16, cy = 16, r = 15, color = C.blue2, width = 1,
          fill = true, fill_color = C.sel, fill_opacity = 255 } } })
    local pp = airui.shape({ parent = root, x = mc.x + 136, y = pcy + 2, w = 16, h = 16,
        items = {} })
    local function pp_set(playing)
        if playing then
            pp:set_items({
                { type = "rect", x = 3, y = 2, w = 3, h = 12, color = C.bright, width = 1,
                  radius = 1, fill = true, fill_color = C.bright, fill_opacity = 255 },
                { type = "rect", x = 10, y = 2, w = 3, h = 12, color = C.bright, width = 1,
                  radius = 1, fill = true, fill_color = C.bright, fill_opacity = 255 },
            })
        else
            pp:set_items({
                { type = "line", x1 = 3, y1 = 1, x2 = 14, y2 = 8, color = C.bright, width = 3 },
                { type = "line", x1 = 3, y1 = 15, x2 = 14, y2 = 8, color = C.bright, width = 3 },
                { type = "line", x1 = 3, y1 = 1, x2 = 3, y2 = 15, color = C.bright, width = 3 },
            })
        end
    end
    pp_set(MOCK.music.playing)
    theme.icon(root, mc.x + 176, pcy, 20, "next", C.icon)
    -- 热区统一走 theme.click：容器构造参数 on_click 在 AirUI 上不生效，
    -- 这里原来三个按钮全是空的（用户反馈「播放/下一首点不动」）。
    -- 上一首 / 下一首切换后必须重绘整页，否则封面、曲名、进度条都不变，
    -- 看着还是「没反应」；播放键只切图标，不必重绘。
    theme.click(root, mc.x + 78, pcy - 8, 40, 40, function()
        MOCK.mu_prev()
        theme.rerender_current()
    end, 12)
    theme.click(root, mc.x + 120, pcy - 8, 48, 40, function()
        MOCK.mu_toggle()
        pcall(function() pp_set(MOCK.music.playing) end)
    end, 12)
    theme.click(root, mc.x + 170, pcy - 8, 42, 40, function()
        MOCK.mu_next()
        theme.rerender_current()
    end, 12)
    -- 进度条点哪跳哪（分 10 段热区叠在轨道上）
    local pgw = mc.w - 98
    for k = 1, 10 do
        theme.click(root, dx0 + math.floor(pgw * (k - 1) / 10), mc.y + 70,
            math.ceil(pgw / 10), 20, function()
                MOCK.music.pos = math.floor(MOCK.mu_dur() * (k - 0.5) / 10)
                theme.rerender_current()
            end, 3)
    end
    -- 迷你列表（4 行；行距收到 29，卡内 152..265 刚好放得下，
    -- 原来 3 行、下面空一截，用户要求再加一首）
    local list_lbl = {}
    local NROW = math.min(4, #MOCK.music.list)
    for i = 1, NROW do
        local s = MOCK.music.list[i]
        local ly = mc.y + 152 + (i - 1) * 29
        -- 选中行的高亮底板只建「当前曲」这一行，且必须建在文字之前。
        -- 原来 3 行都先建底板再 hide，1.5s 刷新时用 li:open() 显示 —— 但
        -- container:open() 会 move_foreground，底板被提到同级文字之上，
        -- 当前歌那一行的歌名/时长就被蓝色底板整个盖住了
        -- （用户反馈「选中歌之后歌名看不见」）
        if i == MOCK.music.cur then
            airui.container({ parent = root, x = mc.x + 8, y = ly - 2,
                w = mc.w - 16, h = 28, color = C.sel, radius = 6 })
        end
        local t = airui.label({ parent = root, x = mc.x + 16, y = ly, w = 150, h = 18,
            text = s.title, color = C.sub, font_size = 16 })
        local d = airui.label({ parent = root, x = mc.x + mc.w - 76, y = ly, w = 60, h = 18,
            text = MOCK.mmss(s.dur), color = C.dim, font_size = 16,
            align = airui.TEXT_ALIGN_RIGHT })
        list_lbl[i] = { t = t, d = d }
        -- 选歌后必须重绘：否则列表高亮、封面、曲名都不会变（看起来「选不了歌」）
        theme.click(root, mc.x + 8, ly - 2, mc.w - 16, 28, function()
            MOCK.mu_pick(i)
            theme.rerender_current()
        end, 3)
    end

    -- 车辆卡
    local vc = { x = SIDEX, y = mc.y + 278 + 12, w = SIDEW, h = BODYH - 278 - 12 }
    theme.card(root, vc)
    theme.card_head(root, vc, "车辆", "四驱性能版", C.sub)
    local vbtn = airui.container({ parent = root, x = vc.x, y = vc.y,
        w = vc.w, h = vc.h, color = C.bg, color_opacity = 1, radius = 14 })
    vbtn:set_on_click(function() db(function() go("car") end) end)
    -- 小车：优先贴图（code/img/car_side_small.png 140×59 透明底，侧视，
    -- 车头朝左、四个轮子完整）。底边落在 cary+60，正好让开下面 cary+60 的「75%」
    local cary = vc.y + 30
    local car_small = theme.img("car_side_small.png")
    local car_ok = false
    if car_small then
        local im
        local ok = pcall(function()
            im = airui.image({ parent = root, src = car_small,
                x = vc.x + 66, y = cary + 1, w = 140, h = 59 })
        end)
        car_ok = ok and im ~= nil
    end
    if not car_ok then
        theme.shapes(root, vc.x + 36, cary, 200, 58, {
            -- 车身：x28..137 y29..52，等比压到 58 高
            { type = "rect", x = 28, y = 22, w = 109, h = 18, color = 0xC21E33, width = 1,
              radius = 8, fill = true, fill_color = 0xC21E33, fill_opacity = 255 },
            -- 车顶：只有中段，比车身窄，形成轿车轮廓
            { type = "rect", x = 57, y = 15, w = 50, h = 11, color = 0xC21E33, width = 1,
              radius = 4, fill = true, fill_color = 0xC21E33, fill_opacity = 255 },
            -- 前窗 / 后窗（SVG 里是两个梯形）
            { type = "rect", x = 62, y = 17, w = 20, h = 8, color = 0x7C1220, width = 1,
              radius = 2, fill = true, fill_color = 0x7C1220, fill_opacity = 220 },
            { type = "rect", x = 85, y = 17, w = 17, h = 8, color = 0x7C1220, width = 1,
              radius = 2, fill = true, fill_color = 0x7C1220, fill_opacity = 170 },
            -- 车轮必须落在车身（x 28..137）下方：原来 cx=146 已经超出车尾 9px，
            -- 看起来就是「车轮跑到车身外面/前面去了」
            { type = "circle", cx = 52, cy = 42, r = 6, color = 0x14161C, width = 1,
              fill = true, fill_color = 0x14161C, fill_opacity = 255 },
            { type = "circle", cx = 52, cy = 42, r = 3, color = 0x5E6874, width = 1,
              fill = true, fill_color = 0x5E6874, fill_opacity = 255 },
            { type = "circle", cx = 113, cy = 42, r = 6, color = 0x14161C, width = 1,
              fill = true, fill_color = 0x14161C, fill_opacity = 255 },
            { type = "circle", cx = 113, cy = 42, r = 3, color = 0x5E6874, width = 1,
              fill = true, fill_color = 0x5E6874, fill_opacity = 255 },
        })
    end
    airui.label({ parent = root, x = vc.x + 12, y = cary + 60, w = 70, h = 26,
        text = MOCK.car.ev .. "%", color = C.blue2, font_size = 24 })
    airui.label({ parent = root, x = vc.x + 76, y = cary + 66, w = 180, h = 20,
        text = "预计可行驶" .. MOCK.car.range .. "km", color = C.dim, font_size = 16 })
    -- 建的时候直接传 pct 一次成型：先建成 0 再 :set() 是第二次 set_items，
    -- 个别固件上会静默失败，表现就是这条电量进度条一直是空的（用户反馈「不动」）
    theme.progress(root, { x = vc.x + 12, y = cary + 88, w = vc.w - 24, h = 4,
        pct = (tonumber(MOCK.car.ev) or 0) / 100 })
    local rows = { { "车辆状态", MOCK.car.status }, { "平均电耗", MOCK.car.avg },
                   { "行驶总里程", MOCK.car.total } }
    for i, r in ipairs(rows) do
        local ry = cary + 94 + (i - 1) * 19
        airui.label({ parent = root, x = vc.x + 12, y = ry, w = 100, h = 18,
            text = r[1], color = C.sub, font_size = 16 })
        airui.label({ parent = root, x = vc.x + 112, y = ry, w = vc.w - 124, h = 18,
            text = r[2], color = C.name, font_size = 16,
            align = airui.TEXT_ALIGN_RIGHT })
    end

    ----------------------------------------------------------------
    -- 底部 dock
    ----------------------------------------------------------------
    theme.dockbar(root)

    ----------------------------------------------------------------
    -- 1.5s 刷新：音乐卡数据
    ----------------------------------------------------------------
    local shown_cur = MOCK.music.cur
    return function()
        MOCK.mu_tick()
        -- 一曲放完会自动切下一首，迷你列表的高亮行只能靠重建页面来摆正层级
        -- （open() 会盖住文字），所以 cur 一变就整页重绘一次
        if MOCK.music.cur ~= shown_cur then
            shown_cur = MOCK.music.cur
            pcall(theme.rerender_current)
            return
        end
        pcall(function()
            local s = MOCK.mu_song()
            mtitle:set_text(s.title)
            martist:set_text(s.artist)
            mcur:set_text(MOCK.mmss(MOCK.music.pos))
            mdur:set_text(MOCK.mmss(MOCK.mu_dur()))
            -- 进度：slider 与自绘进度条的接口不同；手指正在拖时
            -- （slider 值与数据差得多）不回写，避免把拖动打断
            if type(prog1) == "table" then
                prog1.set(MOCK.music.pos / math.max(1, MOCK.mu_dur()))
            elseif prog1 then
                local nv
                pcall(function() nv = prog1:get_value() end)
                if type(nv) ~= "number" or math.abs(nv - MOCK.music.pos) <= 2 then
                    pcall(function() prog1:set_value(MOCK.music.pos) end)
                end
            end
            pp_set(MOCK.music.playing)
            for i = 1, NROW do
                local e = list_lbl[i]
                local s2 = MOCK.music.list[i]
                if e and s2 then
                    e.t:set_text(s2.title)
                    e.t:set_color(i == MOCK.music.cur and C.text or C.sub)
                end
            end
        end)
    end
end)
