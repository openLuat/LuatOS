--[[
@module  icon
@summary 全部用 airui.shape 图元现画的可爱图标（不依赖图片资源）
@version 1.0
@date    2026.10.28

约定：所有函数返回 airui.shape 的 items 数组，坐标以 (w, h) 为画布，
      调用方用 theme.shape{ x, y, w, h, items = icon.xxx(...) } 挂上去。
可复用图元预算：单个图标 4~12 个图元，远低于 350/帧 的上限。
]]
local M = {}

local DARK  = 0x4A3B33
local PINK  = 0xFF9BB8
local CREAM = 0xFFF6E9
local BEAK  = 0xFFB03A

local function circle(cx, cy, r, col)
    return { type = "circle", cx = cx, cy = cy, r = r, fill = true, fill_color = col, fill_opacity = 255 }
end
local function ellipse(cx, cy, rx, ry, col)
    return { type = "ellipse", cx = cx, cy = cy, rx = rx, ry = ry, fill = true, fill_color = col, fill_opacity = 255 }
end
local function rrect(x, y, w, h, r, col)
    return { type = "rect", x = x, y = y, w = w, h = h, radius = r, fill = true, fill_color = col, fill_opacity = 255 }
end
local function line(x1, y1, x2, y2, col, w, round)
    return {
        type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        color = col, width = w or 1,
        round_start = round and true or false,
        round_end = round and true or false,
    }
end

--------------------------------------------------------------------
-- 宠物头像：chick 小鸡 / cat 小猫 / rabbit 兔子 / bear 小熊 / hamster 仓鼠
--------------------------------------------------------------------
function M.pet(kind, w, h, col)
    local s = math.min(w, h)
    local r = s * 0.30
    local it = {}
    if kind == "cat" then
        local cy = h * 0.56
        local cx = w / 2
        it[#it + 1] = ellipse(cx - r * 0.66, cy - r * 0.86, r * 0.30, r * 0.42, col)
        it[#it + 1] = ellipse(cx + r * 0.66, cy - r * 0.86, r * 0.30, r * 0.42, col)
        it[#it + 1] = circle(cx, cy, r, col)
        it[#it + 1] = circle(cx - r * 0.33, cy - r * 0.06, r * 0.12, DARK)
        it[#it + 1] = circle(cx + r * 0.33, cy - r * 0.06, r * 0.12, DARK)
        it[#it + 1] = ellipse(cx, cy + r * 0.30, r * 0.12, r * 0.09, PINK)
        it[#it + 1] = line(cx - r * 0.42, cy + r * 0.34, cx - r * 0.95, cy + r * 0.26, DARK, 1)
        it[#it + 1] = line(cx + r * 0.42, cy + r * 0.34, cx + r * 0.95, cy + r * 0.26, DARK, 1)
        it[#it + 1] = line(cx - r * 0.42, cy + r * 0.48, cx - r * 0.95, cy + r * 0.56, DARK, 1)
        it[#it + 1] = line(cx + r * 0.42, cy + r * 0.48, cx + r * 0.95, cy + r * 0.56, DARK, 1)
    elseif kind == "rabbit" then
        local cx, cy = w / 2, h * 0.64
        local ey = cy - r * 1.16
        it[#it + 1] = ellipse(cx - r * 0.40, ey, r * 0.20, r * 0.52, col)
        it[#it + 1] = ellipse(cx + r * 0.40, ey, r * 0.20, r * 0.52, col)
        it[#it + 1] = ellipse(cx - r * 0.40, ey, r * 0.09, r * 0.30, PINK)
        it[#it + 1] = ellipse(cx + r * 0.40, ey, r * 0.09, r * 0.30, PINK)
        it[#it + 1] = circle(cx, cy, r, col)
        it[#it + 1] = circle(cx - r * 0.32, cy - r * 0.08, r * 0.12, DARK)
        it[#it + 1] = circle(cx + r * 0.32, cy - r * 0.08, r * 0.12, DARK)
        it[#it + 1] = ellipse(cx, cy + r * 0.28, r * 0.11, r * 0.08, PINK)
        it[#it + 1] = line(cx, cy + r * 0.38, cx, cy + r * 0.52, DARK, 1)
        it[#it + 1] = circle(cx - r * 0.60, cy + r * 0.28, r * 0.16, PINK)
        it[#it + 1] = circle(cx + r * 0.60, cy + r * 0.28, r * 0.16, PINK)
    elseif kind == "bear" then
        local cx, cy = w / 2, h * 0.58
        it[#it + 1] = circle(cx - r * 0.74, cy - r * 0.70, r * 0.34, col)
        it[#it + 1] = circle(cx + r * 0.74, cy - r * 0.70, r * 0.34, col)
        it[#it + 1] = circle(cx, cy, r, col)
        it[#it + 1] = ellipse(cx, cy + r * 0.32, r * 0.36, r * 0.28, CREAM)
        it[#it + 1] = circle(cx - r * 0.32, cy - r * 0.12, r * 0.11, DARK)
        it[#it + 1] = circle(cx + r * 0.32, cy - r * 0.12, r * 0.11, DARK)
        it[#it + 1] = ellipse(cx, cy + r * 0.22, r * 0.13, r * 0.10, DARK)
        it[#it + 1] = line(cx, cy + r * 0.30, cx, cy + r * 0.42, DARK, 1)
    elseif kind == "hamster" then
        local cx, cy = w / 2, h * 0.58
        it[#it + 1] = circle(cx - r * 0.58, cy - r * 0.82, r * 0.24, col)
        it[#it + 1] = circle(cx + r * 0.58, cy - r * 0.82, r * 0.24, col)
        it[#it + 1] = ellipse(cx, cy, r * 1.02, r * 0.94, col)
        it[#it + 1] = circle(cx - r * 0.34, cy - r * 0.10, r * 0.12, DARK)
        it[#it + 1] = circle(cx + r * 0.34, cy - r * 0.10, r * 0.12, DARK)
        it[#it + 1] = circle(cx - r * 0.58, cy + r * 0.30, r * 0.18, PINK)
        it[#it + 1] = circle(cx + r * 0.58, cy + r * 0.30, r * 0.18, PINK)
        it[#it + 1] = ellipse(cx, cy + r * 0.26, r * 0.10, r * 0.07, DARK)
    else -- chick 小鸡
        local cx, cy = w / 2, h * 0.52
        it[#it + 1] = ellipse(cx, cy + r * 0.78, r * 0.78, r * 0.60, col)
        it[#it + 1] = circle(cx, cy - r * 0.20, r * 0.80, col)
        it[#it + 1] = circle(cx - r * 0.30, cy - r * 0.30, r * 0.11, DARK)
        it[#it + 1] = circle(cx + r * 0.30, cy - r * 0.30, r * 0.11, DARK)
        it[#it + 1] = ellipse(cx, cy - r * 0.02, r * 0.16, r * 0.11, BEAK)
        it[#it + 1] = line(cx - r * 0.26, cy + r * 1.34, cx - r * 0.26, cy + r * 1.50, BEAK, 2, true)
        it[#it + 1] = line(cx + r * 0.26, cy + r * 1.34, cx + r * 0.26, cy + r * 1.50, BEAK, 2, true)
        it[#it + 1] = circle(cx - r * 0.62, cy + r * 0.90, r * 0.16, BEAK)
    end
    return it
end

--------------------------------------------------------------------
-- 指标图标：t 温度 / h 湿度 / g 有毒气体
--------------------------------------------------------------------
function M.metric(kind, w, h, col)
    local s = math.min(w, h)
    local cx, cy = w / 2, h / 2
    local R = s * 0.32
    local it = {}
    if kind == "t" then
        it[#it + 1] = rrect(cx - s * 0.10, cy - R * 1.30, s * 0.20, R * 1.95, s * 0.10, col)
        it[#it + 1] = circle(cx, cy + R * 0.92, R * 0.50, col)
        it[#it + 1] = circle(cx, cy + R * 0.92, R * 0.24, CREAM)
        it[#it + 1] = line(cx + s * 0.15, cy - R * 0.62, cx + s * 0.30, cy - R * 0.62, col, 2, true)
        it[#it + 1] = line(cx + s * 0.15, cy - R * 0.08, cx + s * 0.26, cy - R * 0.08, col, 2, true)
    elseif kind == "h" then
        it[#it + 1] = ellipse(cx, cy - R * 0.50, R * 0.50, R * 0.72, col)
        it[#it + 1] = circle(cx, cy + R * 0.42, R * 0.62, col)
        it[#it + 1] = circle(cx - R * 0.18, cy + R * 0.32, R * 0.16, CREAM)
    else -- 云朵 = 气体
        it[#it + 1] = circle(cx - R * 0.58, cy + R * 0.34, R * 0.46, col)
        it[#it + 1] = circle(cx + R * 0.52, cy + R * 0.36, R * 0.40, col)
        it[#it + 1] = circle(cx - R * 0.04, cy - R * 0.20, R * 0.60, col)
        it[#it + 1] = rrect(cx - R * 0.96, cy + R * 0.30, R * 1.92, R * 0.54, R * 0.27, col)
    end
    return it
end

--------------------------------------------------------------------
-- 设备图标：warm 暖风 / cool 冷风 / light 灯光
--------------------------------------------------------------------
function M.ctrl(kind, w, h, col)
    local s = math.min(w, h)
    local cx, cy = w / 2, h / 2
    local R = s * 0.30
    local it = {}
    if kind == "warm" then
        it[#it + 1] = circle(cx, cy, R * 0.55, col)
        for i = 0, 7 do
            local a = i * math.pi / 4
            local x1 = cx + math.cos(a) * R * 0.85
            local y1 = cy + math.sin(a) * R * 0.85
            local x2 = cx + math.cos(a) * R * 1.25
            local y2 = cy + math.sin(a) * R * 1.25
            it[#it + 1] = line(x1, y1, x2, y2, col, 2, true)
        end
    elseif kind == "cool" then
        for i = 0, 2 do
            local a = i * math.pi / 3
            local dx, dy = math.cos(a) * R * 1.15, math.sin(a) * R * 1.15
            it[#it + 1] = line(cx - dx, cy - dy, cx + dx, cy + dy, col, 2, true)
        end
        for i = 0, 5 do
            local a = i * math.pi / 3 + math.pi / 6
            it[#it + 1] = circle(cx + math.cos(a) * R * 1.15, cy + math.sin(a) * R * 1.15, R * 0.12, col)
        end
    elseif kind == "light" then
        it[#it + 1] = circle(cx, cy - R * 0.38, R * 0.62, col)
        it[#it + 1] = rrect(cx - R * 0.26, cy + R * 0.20, R * 0.52, R * 0.34, R * 0.12, col)
        it[#it + 1] = line(cx - R * 0.52, cy - R * 0.38, cx - R * 0.98, cy - R * 0.60, col, 2, true)
        it[#it + 1] = line(cx + R * 0.52, cy - R * 0.38, cx + R * 0.98, cy - R * 0.60, col, 2, true)
        it[#it + 1] = line(cx - R * 0.30, cy - R * 1.05, cx - R * 0.10, cy - R * 1.35, col, 2, true)
    end
    return it
end

return M
