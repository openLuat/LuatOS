--[[
@module page_task
@summary 最近任务页：左列 4 张缩略卡 + 右侧首页缩略大图
布局与 preview.html 对应：task-list 208 宽 / task-main 弹性
]]

local theme = require "theme"
local _rc, _ln, _ci = theme._rc, theme._ln, theme._ci
local W, H, TOP = theme.W, theme.H, theme.TOP_H

theme.make_page("task", function(root, M)
    local C = theme.C
    local db = theme.debounce()

    theme.topbar(root, "back", false)

    local BY, BH = TOP + 2, H - TOP - 14
    local LX, LW = 16, 208
    local RX, RW = 16 + 208 + 16, W - 32 - 208 - 16

    ----------------------------------------------------------------
    -- 左列缩略卡（4 张）
    ----------------------------------------------------------------
    local th = math.floor((BH - 3 * 10) / 4)
    for i, t in ipairs(MOCK.tasks) do
        local yy = BY + (i - 1) * (th + 10)
        airui.container({ parent = root, x = LX, y = yy, w = LW, h = th,
            color = theme.blend(0x12243C, 0x060E1A, 0.5), radius = 10,
            border_color = C.line, border_width = 1 })
        -- 缩略内容（200x96 视图等比缩放）
        local fx, fy = LW / 200, th / 96
        local it = {}
        _rc(it, 0, 0, math.floor(200 * fx), math.floor(96 * fy), 0x081524, 0)
        if i == 1 then          -- 车辆数据
            _rc(it, math.floor(42 * fx), math.floor(62 * fy),
                math.floor(116 * fx), math.floor(16 * fy), 0xC21E33, 3)
            _rc(it, 18, math.floor(66 * fy), 44, math.floor(18 * fy), 0x122C48, 3)
            _rc(it, 70, math.floor(66 * fy), 44, math.floor(18 * fy), 0x122C48, 3)
            _rc(it, 122, math.floor(66 * fy), 60, math.floor(18 * fy), 0x122C48, 3)
        elseif i == 2 then      -- 应用APP
            for r = 0, 1 do
                for c2 = 0, 3 do
                    _rc(it, math.floor(16 + c2 * 44) , math.floor(14 + r * 38),
                        math.floor(34 * fx), math.floor(30 * fy), 0x1B6FD8, 5)
                end
            end
        elseif i == 3 then      -- 音乐
            _rc(it, 12, math.floor(14 * fy), 80, math.floor(30 * fy), 0x0F9D6B, 5)
            _rc(it, 100, math.floor(14 * fy), 80, math.floor(30 * fy), 0x1E6BE0, 5)
            _rc(it, 12, math.floor(52 * fy), 80, math.floor(30 * fy), 0x7A3BE8, 5)
            _rc(it, 100, math.floor(52 * fy), 80, math.floor(30 * fy), 0xE23B5C, 5)
        else                    -- 车辆设置
            _rc(it, 12, math.floor(12 * fy), 60, math.floor(72 * fy), 0x0E2238, 5)
            for r = 0, 3 do
                _rc(it, 84, math.floor((14 + r * 18) * fy), 100,
                    math.floor(12 * fy), 0x1E4B7A, 4)
            end
        end
        theme.shapes(root, LX, yy, LW, th, it)
        -- 底部名称条
        airui.container({ parent = root, x = LX + 1, y = yy + th - 26, w = LW - 2, h = 25,
            color = C.shadow, color_opacity = 180 })
        airui.label({ parent = root, x = LX, y = yy + th - 23, w = LW, h = 20,
            text = t.name, color = C.name, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
        local b = airui.container({ parent = root, x = LX, y = yy, w = LW, h = th,
            color = C.bg, color_opacity = 1, radius = 10 })
        local dest = t.go
        b:set_on_click(function() db(function() theme.go_defer(dest) end) end)
    end

    ----------------------------------------------------------------
    -- 右侧首页缩略大图（640x470 视图）
    ----------------------------------------------------------------
    airui.container({ parent = root, x = RX, y = BY, w = RW, h = BH,
        color = theme.blend(0x07121F, 0x040A14, 0.5), radius = 12,
        border_color = C.line, border_width = 1 })
    local fx, fy = RW / 640, BH / 470
    local function P(x, y)
        local ax, ay = math.floor(x * fx), math.floor(y * fy)
        if ax < 0 then ax = 0 elseif ax > RW - 2 then ax = RW - 2 end
        if ay < 0 then ay = 0 elseif ay > BH - 2 then ay = BH - 2 end
        return ax, ay
    end
    -- 踩坑：P() 返回两个值，直接塞进非末尾实参会只保留第一个，
    -- 后续参数整体错位（颜色被当成坐标）→ 画出巨型色块。
    local function R(items, x, y, w, h, col, rad)
        local ax, ay = P(x, y)
        _rc(items, ax, ay, math.floor(w * fx), math.floor(h * fy), col, rad)
    end
    local function L(items, x1, y1, x2, y2, col, wid)
        local ax, ay = P(x1, y1)
        local bx, by = P(x2, y2)
        _ln(items, ax, ay, bx, by, col, wid)
    end
    local it = {}
    R(it, 8, 8, 624, 40, 0x0B1B2E, 8)
    R(it, 8, 56, 380, 404, 0x08182B, 10)
    R(it, 398, 56, 112, 196, 0x0B1B2E, 10)
    R(it, 398, 262, 112, 198, 0x0B1B2E, 10)
    R(it, 518, 56, 114, 404, 0x0B1B2E, 10)
    R(it, 8, 440, 624, 22, 0x0E2238, 8)
    theme.shapes(root, RX, BY, RW, BH, it)
    -- 路线
    local rt = {}
    L(rt, 80, 430, 80, 240, C.cyan, 5)
    L(rt, 80, 240, 220, 140, C.cyan, 5)
    L(rt, 220, 140, 220, 60, C.cyan, 5)
    theme.shapes(root, RX, BY, RW, BH, rt)
    -- 顶栏文字 + 转向提示
    airui.label({ parent = root, x = RX + math.floor(20 * fx), y = BY + math.floor(18 * fy),
        w = 200, h = 22, text = "Joel Stokes", color = C.sub, font_size = 16 })
    airui.label({ parent = root, x = RX + math.floor(300 * fx), y = BY + math.floor(18 * fy),
        w = 200, h = 22, text = "BYD DiLink", color = C.title, font_size = 16 })
    airui.label({ parent = root, x = RX + math.floor(40 * fx), y = BY + math.floor(150 * fy),
        w = 200, h = 44, text = "300m", color = 0xFFFFFF, font_size = 34 })
    airui.label({ parent = root, x = RX + math.floor(40 * fx), y = BY + math.floor(192 * fy),
        w = 160, h = 22, text = "向左转", color = C.sub, font_size = 16 })
end)
