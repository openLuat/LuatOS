--[[
@module  overlay
@summary 地图覆盖层：把地理点投影成控件局部像素，裁剪后用 airui.shape 画图标和折线
@version 1.0
@date    2026.10.28
@usage
airui.map v0.1.0 没有原生 marker/polyline，本模块用一个铺满地图控件的
airui.shape（透明、可点击穿透）做覆盖层：
  - geo_to_screen 已返回"相对 map 控件左上角"的局部像素；
  - shape 控件与 map 控件同位置同尺寸，图元坐标也是相对 shape 左上角，二者直接对应；
  - shape 图元坐标是 int16，且只画可见范围内的点，超出视口的线段做包围盒裁剪，
    既防溢出又省绘制。
绘制数据由调用方（poi/route/track/guide）通过 begin/add_*/commit 提供。
]]

local M = {}

-- 视口外扩余量（像素）。shape 会按控件边界裁剪，只留约一个图标的边
M.MARGIN = 16

-- 投影兼容：geo_to_screen 可能返回多返回值，也可能返回 table
local function project(map, lon, lat)
    local x, y = map:geo_to_screen(lon, lat)
    if type(x) == "table" then
        return x.x, x.y
    end
    return x, y
end
M.project = project

--[[
创建覆盖层。必须在 map 之后创建，参数 rect 为 map 控件的 x/y/w/h。
@param map userdata airui.map 实例
@param rect table {x=,y=,w=,h=}
@return table overlay 实例
]]
function M.create(map, rect)
    local self = setmetatable({}, { __index = M })
    self.map = map
    self.rect = rect
    self.w, self.h = rect.w, rect.h
    self.items = {}
    -- 透明、不拦截触摸（click=false），仅用于绘制
    self.shape = airui.shape({
        x = rect.x, y = rect.y, w = rect.w, h = rect.h,
        items = {},
        click = false,
    })
    return self
end

-- 开始一帧
function M.begin(self)
    self.items = {}
end

-- 提交并刷新
function M.commit(self)
    if not self.shape or self.shape:is_destroyed() then
        return
    end
    self.shape:set_items(self.items)
end

function M.destroy(self)
    if self.shape and not self.shape:is_destroyed() then
        self.shape:destroy()
    end
    self.shape = nil
end

-- 点是否在（含余量的）可见范围内
function M.visible(self, x, y)
    local m = M.MARGIN
    return x >= -m and x <= self.rect.w + m
        and y >= -m and y <= self.rect.h + m
end

-- Cohen–Sutherland 风格的包围盒裁剪，把线段裁进 [-MARGIN, w+MARGIN]
-- 返回 true 以及裁剪后的 x1,y1,x2,y2
function M.clip_segment(self, x1, y1, x2, y2)
    local m = M.MARGIN
    local xmin, xmax = -m, self.rect.w + m
    local ymin, ymax = -m, self.rect.h + m

    local function code(x, y)
        local c = 0
        if x < xmin then c = c + 1 elseif x > xmax then c = c + 2 end
        if y < ymin then c = c + 4 elseif y > ymax then c = c + 8 end
        return c
    end

    local c1, c2 = code(x1, y1), code(x2, y2)
    for _ = 1, 16 do
        if (c1 | c2) == 0 then
            return true, x1, y1, x2, y2 -- 完全在内
        elseif (c1 & c2) ~= 0 then
            return false -- 完全同侧在外
        else
            local c = c1 ~= 0 and c1 or c2
            local nx, ny
            if (c & 8) ~= 0 then
                nx = x1 + (x2 - x1) * (ymax - y1) / (y2 - y1)
                ny = ymax
            elseif (c & 4) ~= 0 then
                nx = x1 + (x2 - x1) * (ymin - y1) / (y2 - y1)
                ny = ymin
            elseif (c & 2) ~= 0 then
                ny = y1 + (y2 - y1) * (xmax - x1) / (x2 - x1)
                nx = xmax
            elseif (c & 1) ~= 0 then
                ny = y1 + (y2 - y1) * (xmin - x1) / (x2 - x1)
                nx = xmin
            end
            if c == c1 then
                x1, y1, c1 = nx, ny, code(nx, ny)
            else
                x2, y2, c2 = nx, ny, code(nx, ny)
            end
        end
    end
    return false
end

-- 投影一个地理点
function M.to_screen(self, lon, lat)
    return project(self.map, lon, lat)
end

--[[
画一条折线（路线/轨迹）。points 是 {{lon=,lat=},...}，会逐段裁剪。
@param points table 地理点数组
@param color number 线颜色
@param width number 线宽
@param dash_w number 虚线实段（0 为实线）
@param dash_gap number 虚区间隔
]]
function M.add_polyline(self, points, color, width, dash_w, dash_gap)
    if not points or #points < 2 then
        return
    end
    local prev_lon, prev_lat = points[1].lon, points[1].lat
    local px, py = project(self.map, prev_lon, prev_lat)
    for i = 2, #points do
        local lon, lat = points[i].lon, points[i].lat
        local nx, ny = project(self.map, lon, lat)
        local ok, x1, y1, x2, y2 = self:clip_segment(px, py, nx, ny)
        if ok then
            local item = {
                type = "line",
                x1 = math.floor(x1 + 0.5), y1 = math.floor(y1 + 0.5),
                x2 = math.floor(x2 + 0.5), y2 = math.floor(y2 + 0.5),
                color = color, width = width,
                round_start = true, round_end = true,
            }
            if dash_w and dash_w > 0 then
                item.dash_width = dash_w
                item.dash_gap = dash_gap or dash_w
            end
            self.items[#self.items + 1] = item
        end
        px, py = nx, ny
        prev_lon, prev_lat = lon, lat
    end
end

--[[
画实心圆点标记
@param x number 局部像素
@param y number
@param r number 半径
@param color number
@param border number 描边色（可选）
]]
function M.add_dot(self, x, y, r, color, border)
    if not self:visible(x, y) then
        return
    end
    self.items[#self.items + 1] = {
        type = "circle", cx = math.floor(x + 0.5), cy = math.floor(y + 0.5),
        r = r, fill = true, fill_color = color,
        color = border or color, width = border and 2 or 0,
    }
end

--[[
画一个"水滴/图钉"风格标记：外圈 + 内点
@param x number
@param y number
@param color number
@param active boolean 是否高亮（更大）
]]
function M.add_pin(self, x, y, color, active)
    if not self:visible(x, y) then
        return
    end
    local r = active and 12 or 9
    -- 外圈白底
    self.items[#self.items + 1] = {
        type = "circle", cx = math.floor(x + 0.5), cy = math.floor(y + 0.5),
        r = r, fill = true, fill_color = 0xFFFFFF, color = 0xFFFFFF, width = 1,
    }
    -- 内芯
    self.items[#self.items + 1] = {
        type = "circle", cx = math.floor(x + 0.5), cy = math.floor(y + 0.5),
        r = r - 3, fill = true, fill_color = color, color = color, width = 0,
    }
end

--[[
画一个指向方位角的三角箭头（用于目的地引导）
@param x number 屏幕中心
@param y number
@param heading number 指向角度（度，屏幕坐标：北=上，顺时针）
@param color number
]]
function M.add_arrow(self, x, y, heading, color)
    -- airui.shape 没有三角图元，用从中心指向 heading 的圆头粗线 + 顶端圆点表示
    local rad = heading * math.pi / 180
    -- 屏幕坐标系 y 向下；北(heading=0) 朝上即 y 负方向
    local ex = x + math.sin(rad) * 34
    local ey = y - math.cos(rad) * 34
    self.items[#self.items + 1] = {
        type = "line", x1 = math.floor(x + 0.5), y1 = math.floor(y + 0.5),
        x2 = math.floor(ex + 0.5), y2 = math.floor(ey + 0.5),
        color = color, width = 8, round_start = true, round_end = true,
    }
    self.items[#self.items + 1] = {
        type = "circle", cx = math.floor(ex + 0.5), cy = math.floor(ey + 0.5),
        r = 6, fill = true, fill_color = color, color = color, width = 0,
    }
end

--[[
画比例尺（左下角一条线 + 端竖线）
@param px number 起点 x（局部坐标）
@param py number 起点 y
@param len number 像素长度
@param color number
]]
function M.add_scale_bar(self, px, py, len, color)
    self.items[#self.items + 1] = {
        type = "line", x1 = px, y1 = py, x2 = px + len, y2 = py,
        color = color, width = 3,
    }
    self.items[#self.items + 1] = {
        type = "line", x1 = px, y1 = py - 5, x2 = px, y2 = py + 5,
        color = color, width = 3,
    }
    self.items[#self.items + 1] = {
        type = "line", x1 = px + len, y1 = py - 5, x2 = px + len, y2 = py + 5,
        color = color, width = 3,
    }
end

return M
