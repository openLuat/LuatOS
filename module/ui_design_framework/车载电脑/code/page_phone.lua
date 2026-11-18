--[[
@module page_phone
@summary 手机投屏页：居中手机壳（刘海/状态栏/地图卡/底部工具条）
布局与 preview.html 对应：phone 296×536 圆角 40，mapcard 280 高
]]

local theme = require "theme"
local _ln, _ci, _rc = theme._ln, theme._ci, theme._rc
local W, H = theme.W, theme.H

theme.make_page("phone", function(root, M)
    local C = theme.C
    local db = theme.debounce()

    local pw, ph = 296, 536
    local px = math.floor((W - pw) / 2)
    local py = math.floor((H - ph) / 2) - 4
    airui.container({ parent = root, x = px, y = py, w = pw, h = ph,
        color = theme.blend(0x14304F, 0x050D18, 0.5), radius = 40,
        border_color = theme.blend(0x78AAF0, C.bg, 0.30), border_width = 1 })
    local ix, iy = px + 10, py + 10
    local iw, ih = pw - 20, ph - 20
    airui.container({ parent = root, x = ix, y = iy, w = iw, h = ih,
        color = 0x050D18, radius = 32 })
    -- 刘海
    airui.container({ parent = root, x = px + math.floor((pw - 96) / 2), y = py + 10,
        w = 96, h = 20, color = 0x03070D, radius = 0 })
    airui.container({ parent = root, x = px + math.floor((pw - 96) / 2), y = py + 30,
        w = 96, h = 2, color = 0x03070D, radius = 0 })

    -- 状态栏
    airui.label({ parent = root, x = ix + 16, y = iy + 8, w = 60, h = 22,
        text = "9:41", color = C.name, font_size = 16 })
    theme.icon(root, ix + iw - 66, iy + 10, 15, "wifi", C.name)
    theme.icon(root, ix + iw - 42, iy + 10, 15, "battery", C.name)

    -- 标题
    airui.label({ parent = root, x = ix, y = iy + 38, w = iw, h = 24,
        text = "地图", color = C.text, font_size = 17, align = airui.TEXT_ALIGN_CENTER })

    -- 地图卡：高度铺到工具条上方（原来固定 280，卡底到工具条空 100px）
    local mcx, mcy = ix + 14, iy + 70
    local mcw = iw - 28
    local mch = iy + ih - 16 - 52 - 20 - mcy
    airui.container({ parent = root, x = mcx, y = mcy, w = mcw, h = mch,
        color = theme.blend(0x08131F, 0x040A14, 0.5), radius = 14 })
    -- 光晕：半径 130 的圆会顶到画布外（负坐标 → 巨大色块 + 容器滚动），改用画布内矩形
    theme.shapes(root, mcx, mcy, mcw, mch, {
        { type = "rect", x = 0, y = 0, w = mcw, h = 150,
          color = theme.blend(0x1E5CA0, 0x040A14, 0.45), width = 1, radius = 14,
          fill = true, fill_color = theme.blend(0x1E5CA0, 0x040A14, 0.45),
          fill_opacity = 255 },
    })
    local fx, fy = mcw / 280, mch / 280
    -- 坐标映射 + 夹取到画布内
    local function P(x, y)
        local ax, ay = math.floor(x * fx), math.floor(y * fy)
        if ax < 1 then ax = 1 elseif ax > mcw - 2 then ax = mcw - 2 end
        if ay < 1 then ay = 1 elseif ay > mch - 2 then ay = mch - 2 end
        return ax, ay
    end
    -- 踩坑：P() 返回两个值，作为非末尾实参只保留第一个，
    -- _ln(t, P(a), P(b), col, w) 会把颜色当坐标 → 画出贯穿全屏的巨型线段
    local function L(items, x1, y1, x2, y2, col, wid)
        local ax, ay = P(x1, y1)
        local bx, by = P(x2, y2)
        _ln(items, ax, ay, bx, by, col, wid)
    end
    local grid = {}
    local gcol = theme.blend(0x123A5E, 0x040A14, 0.6)
    local mcol = theme.blend(0x1B4E78, 0x040A14, 0.6)
    L(grid, 0, 210, 290, 120, gcol, 1)
    L(grid, 0, 150, 290, 60, gcol, 1)
    L(grid, 60, 290, 60, 0, gcol, 1)
    L(grid, 150, 290, 150, 0, gcol, 1)
    L(grid, 240, 290, 240, 0, gcol, 1)
    L(grid, 0, 190, 290, 100, mcol, 3)
    L(grid, 60, 0, 60, 290, mcol, 3)
    theme.shapes(root, mcx, mcy, mcw, mch, grid)
    local rt = {}
    L(rt, 78, 280, 78, 150, C.cyan, 6)
    L(rt, 78, 150, 168, 96, C.cyan, 6)
    L(rt, 168, 96, 168, 20, C.cyan, 6)
    theme.shapes(root, mcx, mcy, mcw, mch, rt)
    local dx, dy = P(78, 150)
    local dx2, dy2 = P(168, 96)
    theme.shapes(root, mcx, mcy, mcw, mch, {
        { type = "circle", cx = dx, cy = dy, r = 7, color = C.cyan, width = 3,
          fill = true, fill_color = 0x062033, fill_opacity = 255 },
        { type = "circle", cx = dx2, cy = dy2, r = 11,
          color = theme.blend(0x2E7DFF, 0x040A14, 0.35),
          width = 1, fill = true, fill_color = theme.blend(0x2E7DFF, 0x040A14, 0.35),
          fill_opacity = 255 },
        { type = "circle", cx = dx2, cy = dy2, r = 5, color = C.bright, width = 1,
          fill = true, fill_color = C.bright, fill_opacity = 255 },
    })
    -- 地图信息：贴卡片下沿（卡高现在跟着剩余空间走，不能再写死 208/228）
    theme.icon(root, mcx + 12, mcy + mch - 72, 14, "nav", C.blue2)
    airui.label({ parent = root, x = mcx + 30, y = mcy + mch - 76, w = mcw - 42, h = 20,
        text = "当前目的地：" .. MOCK.phone.dest, color = C.text, font_size = 16 })
    airui.label({ parent = root, x = mcx + 12, y = mcy + mch - 52, w = mcw - 24, h = 20,
        text = MOCK.phone.info, color = C.sub, font_size = 16 })

    -- 底部工具条（52 高胶囊）
    local pbx, pby = ix + 14, iy + ih - 16 - 52
    airui.container({ parent = root, x = pbx, y = pby, w = iw - 28, h = 52,
        color = C.float, radius = 26, border_color = C.line, border_width = 1 })
    -- 图标 kind 必须是 theme.icon 支持的名字（locate/fav 没有字形，会画不出来）
    local tools = { { "search", "搜索" }, { "nav", "重新定位" },
                    { "heart", "收藏路线" }, { "expand", "全屏地图" } }
    for i, k in ipairs(tools) do
        local kx = pbx + math.floor((iw - 28) / 4 * (i - 1) + (iw - 28) / 8) - 10
        theme.icon(root, kx, pby + 16, 20, k[1], C.icon)
        local b = airui.container({ parent = root, x = kx - 12, y = pby + 4, w = 44, h = 44,
            color = C.bg, color_opacity = 1 })
        local tip = k[2]
        b:set_on_click(function() db(function() theme.toast(tip) end) end)
    end
end)
