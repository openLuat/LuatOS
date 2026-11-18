--[[
@module page_ac
@summary 空调页：座椅角度刻度盘 / 双座椅 / 双区温度柱 / 底部功能圆钮
布局与 preview.html 对应：ac-head 44 / ac-main 426 / ac-bar 64
字体全部 ≥16（HTML 里刻度标注 13px，按要求提至 16px）
]]

local theme = require "theme"
local _ci, _ln, _rc = theme._ci, theme._ln, theme._rc
local W, H = theme.W, theme.H

theme.make_page("ac", function(root, M)
    local C = theme.C
    local db = theme.debounce()

    ----------------------------------------------------------------
    -- 头部 44：退出键 / 座椅档位 / 开关胶囊 / 风量档位 / 宫格按钮
    ----------------------------------------------------------------
    local hy = 8

    -- 退出键（左上角圆形返回）：走页面栈回上一页，栈空时才回首页。
    -- 不要硬编码 go("home")：从主页进空调、再从应用页进空调，返回目标不同。
    airui.shape({ parent = root, x = 16, y = 6, w = 28, h = 28, items = {
        { type = "circle", cx = 14, cy = 14, r = 13, color = C.line, width = 1,
          fill = true, fill_color = C.deep, fill_opacity = 255 } } })
    theme.icon(root, 22, 12, 16, "left", C.icon)
    theme.click(root, 12, 2, 36, 36, function()
        theme.back_defer("home")
    end, 14)

    local function grp(x, kind, key)
        -- 左箭头 / 图标 / 档位 / 右箭头
        theme.icon(root, x, hy + 12, 16, "left", C.icon)
        theme.icon(root, x + 24, hy + 12, 16, kind, C.icon)
        local lv = airui.label({ parent = root, x = x + 44, y = hy + 10, w = 22, h = 22,
            text = tostring(MOCK.ac[key]), color = C.name, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
        theme.icon(root, x + 70, hy + 12, 16, "right", C.icon)
        local bl = airui.container({ parent = root, x = x - 4, y = hy + 4, w = 24, h = 26,
            color = C.bg, color_opacity = 1 })
        local bl2 = airui.container({ parent = root, x = x + 66, y = hy + 4, w = 24, h = 26,
            color = C.bg, color_opacity = 1 })
        if key == "seat" then
            bl:set_on_click(function() db(function()
                MOCK.ac_seat_step(-1)
                theme.toast("座椅加热 " .. tostring(MOCK.ac.seat) .. " 档")
            end) end)
            bl2:set_on_click(function() db(function()
                MOCK.ac_seat_step(1)
                theme.toast("座椅加热 " .. tostring(MOCK.ac.seat) .. " 档")
            end) end)
        else
            bl:set_on_click(function() db(function()
                MOCK.ac_fan_step(-1)
                theme.toast("风量 " .. tostring(MOCK.ac.fan) .. " 档")
            end) end)
            bl2:set_on_click(function() db(function()
                MOCK.ac_fan_step(1)
                theme.toast("风量 " .. tostring(MOCK.ac.fan) .. " 档")
            end) end)
        end
        return lv
    end
    local seat_lv = grp(330, "seat", "seat")
    local fan_lv = grp(618, "fan", "fan")

    -- 开关胶囊（空调已启动 + 滑块圆点）
    airui.container({ parent = root, x = 442, y = hy + 6, w = 140, h = 32,
        color = C.float, radius = 16, border_color = C.line, border_width = 1 })
    local pill_lbl = airui.label({ parent = root, x = 454, y = hy + 12, w = 88, h = 22,
        text = MOCK.ac.on and "空调已启动" or "空调已关闭", color = C.name, font_size = 16 })
    local dot_shp = airui.shape({ parent = root, x = 548, y = hy + 15, w = 26, h = 14,
        items = {} })
    local function dot_set(on)
        dot_shp:set_items({
            { type = "rect", x = 0, y = 0, w = 26, h = 14, color = C.cyan, width = 1,
              radius = 7, fill = true,
              fill_color = on and C.cyan or theme.blend(C.cyan, C.float, 0.35),
              fill_opacity = 255 },
            { type = "circle", cx = on and 19 or 7, cy = 7, r = 6, color = C.bright,
              width = 1, fill = true, fill_color = C.bright, fill_opacity = 255 },
        })
    end
    dot_set(MOCK.ac.on)
    local pill_btn = airui.container({ parent = root, x = 442, y = hy + 6, w = 140, h = 32,
        color = C.bg, color_opacity = 1, radius = 16 })
    pill_btn:set_on_click(function()
        db(function()
            MOCK.ac_power()
            pcall(function()
                pill_lbl:set_text(MOCK.ac.on and "空调已启动" or "空调已关闭")
                pill_lbl:set_color(MOCK.ac.on and C.name or C.dim)
                dot_set(MOCK.ac.on)
            end)
        end)
    end)

    -- 右上宫格按钮
    airui.shape({ parent = root, x = W - 34, y = 6, w = 28, h = 28, items = {
        { type = "circle", cx = 14, cy = 14, r = 13, color = C.line, width = 1,
          fill = true, fill_color = C.deep, fill_opacity = 255 } } })
    theme.icon(root, W - 27, 13, 14, "grid", C.icon)
    local gb = airui.container({ parent = root, x = W - 34, y = 6, w = 28, h = 28,
        color = C.bg, color_opacity = 1 })
    gb:set_on_click(function() db(function() theme.go_defer("apps") end) end)

    ----------------------------------------------------------------
    -- 主区 426：刻度盘 / 双座椅 / 双区温度柱
    ----------------------------------------------------------------
    local mx, my = 16, 44
    -- 主区高度铺到底部功能条上方（原来固定 426，主区下沿到功能条之间空 58px）
    local mw, mh = W - 32, H - 44 - 80
    local cx, cy = W / 2, my + mh / 2        -- 512, 257
    local sc = { x = cx - 260, y = cy - 150 } -- 520x300 刻度盘

    -- 引导线 + 角度标注（.ac-guide / .ac-angle，坐标为 520x300 盘内相对值）
    local gcol = theme.blend(0xA0C8F0, C.page, 0.55)
    local guides = {}
    _ln(guides, 260, 268, 120, 96, gcol, 2)      -- 左斜线
    _ln(guides, 260, 268, 400, 96, gcol, 2)      -- 右斜线
    _ln(guides, 96, 190, 118, 156, gcol, 2)      -- 左弧段（近似）
    _ln(guides, 118, 156, 140, 126, gcol, 2)
    _ln(guides, 140, 126, 162, 94, gcol, 2)
    _ln(guides, 424, 190, 402, 156, gcol, 2)     -- 右弧段
    _ln(guides, 402, 156, 380, 126, gcol, 2)
    _ln(guides, 380, 126, 358, 94, gcol, 2)
    theme.shapes(root, sc.x, sc.y, 520, 300, guides)
    -- 角度标注不在这里建：座椅改贴图后面积比原来的 shape 大得多，
    -- 先建标签会被座椅整块盖住（用户反馈「把字挡住了」），
    -- 所以标签挪到 seat() 之后创建，保证永远在最上层
    local angs = {
        { 106, 268, "0°" }, { 120, 212, "30°" }, { 146, 152, "60°" },
        { 188, 112, "70°" }, { 214, 86, "90°" },
        { 382, 86, "90°" }, { 338, 112, "70°" }, { 306, 152, "60°" },
        { 352, 212, "30°" }, { 386, 268, "0°" },
    }

    -- 双座椅：优先贴图（code/img/seat_l.png、seat_r.png，280×295 透明底，
    -- 左右是两张不同的图而不是镜像——参考素材本身左右视角不同）。
    -- 图不存在/加载失败时回退到原来的 shape 拼图（240×278：椅背 + 棕色包覆 + 坐垫）
    local seat_src = { l = theme.img("seat_l.png"), r = theme.img("seat_r.png") }
    local function seat(side)
        local sy = cy - math.floor(278 * 0.46)
        local src = seat_src[side]
        if src then
            -- 贴图 214×320：两把椅子中心对称（cx-234 / cx+20），中间留 40px；
            -- 右椅是左椅水平翻转，椅面朝内；尺寸直接是最终显示尺寸
            local ix = (side == "l") and (cx - 234) or (cx + 20)
            local im
            local ok = pcall(function()
                im = airui.image({ parent = root, src = src, x = ix, y = cy - 160,
                    w = 214, h = 320 })
            end)
            if ok and im then return end
        end
        -- 回退：shape 拼图仍用原来的坐标（画布里自带留白）
        local sx = (side == "l") and (cx - 250) or (cx + 10)
        local g1, g2 = 0xC9D6E4, 0x7E8EA2      -- 灰色皮面
        local w1, w2 = 0x6B4A32, 0x3A2418      -- 棕色包覆
        local mid = theme.blend(g1, g2, 0.5)
        local items = {}
        if side == "l" then
            _rc(items, 52, 22, 60, 150, mid, 24)          -- 椅背
            _rc(items, 64, 36, 36, 120, w1, 16)           -- 棕色包覆
            _rc(items, 30, 140, 180, 80, mid, 26)         -- 坐垫
            _rc(items, 44, 156, 150, 50, w1, 16)
        else
            _rc(items, 128, 22, 60, 150, mid, 24)
            _rc(items, 140, 36, 36, 120, w1, 16)
            _rc(items, 30, 140, 180, 80, mid, 26)
            _rc(items, 46, 156, 150, 50, w1, 16)
        end
        items[#items + 1] = { type = "circle", cx = 120, cy = 252, r = 24,
            color = C.shadow, width = 1, fill = true,
            fill_color = C.shadow, fill_opacity = 255 }
        theme.shapes(root, sx, sy, 240, 278, items)
    end
    seat("l")
    seat("r")
    -- 角度标注最后建：座椅贴图是实心的，先建标签会被压在图下面看不见。
    -- 另外白边座椅上白字本来就看不清，先垫一层半透明暗底当"胶囊"
    local chips = {}
    for i, a in ipairs(angs) do
        chips[#chips + 1] = { type = "rect", x = a[1] - 10, y = a[2] - 11,
            w = 44, h = 21, color = C.page, width = 1, radius = 9,
            fill = true, fill_color = C.page, fill_opacity = 170 }
    end
    theme.shapes(root, sc.x, sc.y, 440, 300, chips)
    local ang_lbls = {}
    for i, a in ipairs(angs) do
        ang_lbls[i] = airui.label({ parent = root, x = sc.x + a[1] - 8,
            y = sc.y + a[2] - 10, w = 40, h = 18, text = a[3],
            color = theme.blend(0xBEDCFA, C.page, 0.75), font_size = 16 })
    end

    -- 双区温度柱（.tempcol l/r）
    local track_geom = {}
    local function tempcol(side)
        local x = (side == "l") and (mx + 8) or (W - 16 - 58 - 8)
        local top = my + 8
        local bot = my + mh - 10
        -- 温度胶囊
        local v = airui.container({ parent = root, x = x + 3, y = top, w = 52, h = 40,
            color = C.float, radius = 12, border_color = C.line, border_width = 1 })
        local vt = airui.label({ parent = root, x = x + 3, y = top + 6, w = 52, h = 28,
            text = MOCK.ac.temp[side] .. "°", color = C.text, font_size = 22,
            align = airui.TEXT_ALIGN_CENTER })
        -- 加号
        local pmy = top + 44
        local p1 = airui.label({ parent = root, x = x, y = pmy, w = 58, h = 28,
            text = "+", color = C.icon, font_size = 22, align = airui.TEXT_ALIGN_CENTER })
        -- 轨道（10 宽圆角）+ 填充（shape 就地更新高度）
        local tkx = x + math.floor((58 - 10) / 2)
        local tky = pmy + 34
        local tkh = bot - pmy - 34 - 42
        airui.container({ parent = root, x = tkx, y = tky, w = 10, h = tkh,
            color = C.track, radius = 5 })
        local fill = airui.shape({ parent = root, x = tkx, y = tky, w = 10, h = tkh,
            items = {} })
        -- 减号
        local pm2 = airui.label({ parent = root, x = x, y = bot - 34, w = 58, h = 28,
            text = "-", color = C.icon, font_size = 22, align = airui.TEXT_ALIGN_CENTER })
        track_geom[side] = { lbl = vt, fill = fill, h = tkh }
        local function setfill()
            local t = MOCK.ac.temp[side]
            local frac = (t - 16) / 14
            local fh = math.max(8, math.floor(tkh * frac))
            fill:set_items({ { type = "rect", x = 0, y = tkh - fh, w = 10, h = fh,
                color = C.cyan, width = 1, radius = 5,
                fill = true, fill_color = C.blue, fill_opacity = 255 } })
            vt:set_text(t .. "°")
        end
        setfill()
        -- 点击热区（覆盖 +/- 整列）
        local b1 = airui.container({ parent = root, x = x, y = pmy - 4, w = 58, h = 34,
            color = C.bg, color_opacity = 1 })
        b1:set_on_click(function()
            db(function() MOCK.ac_temp_step(side, 1) pcall(setfill) end)
        end)
        local b2 = airui.container({ parent = root, x = x, y = bot - 34, w = 58, h = 34,
            color = C.bg, color_opacity = 1 })
        b2:set_on_click(function()
            db(function() MOCK.ac_temp_step(side, -1) pcall(setfill) end)
        end)
    end
    tempcol("l")
    tempcol("r")

    ----------------------------------------------------------------
    -- 底栏 64：9 个功能圆钮 + 中央大温度钮
    ----------------------------------------------------------------
    local by = 528
    local defs = {
        { kind = "seatheat", t = "主驾座椅加热", on = false },
        { kind = "heater",   t = "高温除菌",   on = false },
        { kind = "car",      t = "内循环",     on = true },
        { kind = "fan",      t = "AUTO",      on = false },
        { kind = "BIG" },
        { kind = "sync",     t = "双区同步",   on = false },
        { kind = "seat",     t = "副驾座椅加热", on = false },
        { kind = "heater",   t = "座椅通风",   on = false },
        { kind = "car",      t = "外循环",     on = false },
        { kind = "home",     t = "返回首页",   on = false },
    }
    local n_circ = 9
    local total = n_circ * 46 + 58 + 9 * 10
    local bx0 = math.floor((W - total) / 2)
    local big_lbl
    local curx = bx0
    for i, d in ipairs(defs) do
        if d.kind == "BIG" then
            -- 大温度钮（58px，青色描边）：宽度不同，必须按实际宽度累加，否则与右邻重叠
            local bx = curx
            airui.shape({ parent = root, x = bx, y = by + 3, w = 58, h = 58, items = {
                { type = "circle", cx = 29, cy = 29, r = 28, color = C.cyan, width = 2,
                  fill = true, fill_color = C.float, fill_opacity = 255 } } })
            big_lbl = airui.label({ parent = root, x = bx, y = by + 21, w = 58, h = 24,
                text = MOCK.ac.temp.l .. "°", color = C.bright, font_size = 20,
                align = airui.TEXT_ALIGN_CENTER })
            local bb = airui.container({ parent = root, x = bx, y = by + 3, w = 58, h = 58,
                color = C.bg, color_opacity = 1 })
            bb:set_on_click(function()
                db(function()
                    MOCK.ac_temp_step("l", 1)
                    pcall(function() big_lbl:set_text(MOCK.ac.temp.l .. "°") end)
                    theme.toast("主驾温度 " .. MOCK.ac.temp.l .. "°")
                end)
            end)
            curx = curx + 58 + 10
        else
            local bx = curx
            local on = d.on
            local circ = airui.container({ parent = root, x = bx, y = by + 9, w = 46, h = 46,
                color = on and C.sel_str or C.float, radius = 23,
                border_color = on and C.blue2 or C.line, border_width = 1 })
            theme.icon(root, bx + 13, by + 21, 20, d.kind, on and C.bright or C.icon)
            local cb = airui.container({ parent = root, x = bx, y = by + 9, w = 46, h = 46,
                color = C.bg, color_opacity = 1 })
            local tip = d.t or ""
            if d.kind == "home" then
                cb:set_on_click(function() db(function() theme.go_defer("home") end) end)
            else
                cb:set_on_click(function()
                    db(function()
                        on = not on
                        pcall(function()
                            circ:set_color(on and C.sel_str or C.float)
                            circ:set_border_color(on and C.blue2 or C.line)
                        end)
                        if tip ~= "" then
                            theme.toast(tip .. (on and " 已开启" or " 已关闭"))
                        end
                    end)
                end)
            end
            curx = curx + 46 + 10
        end
    end

    -- 1.5s 刷新：档位数字
    return function()
        pcall(function()
            seat_lv:set_text(tostring(MOCK.ac.seat))
            fan_lv:set_text(tostring(MOCK.ac.fan))
        end)
    end
end)
