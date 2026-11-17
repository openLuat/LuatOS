--[[
  ui_icon.lua  图标图元（shape items，24x24 坐标空间，纯描边/填充，不含文字）
  注意：AirUI 的 circle/rect 图元在 fill = true 时仍会画描边，描边默认白 1px，
  所以所有实心圆一律显式给 color = 填充色 + opacity = 0，否则真机上一圈白线。
]]

local M = {}

-- 转向灯（stroke 箭头）。dir = "l" 左 / "r" 右
function M.turn(dir, color)
  local seg
  if dir == "r" then
    seg = {
      { 20, 12, 12, 5 }, { 12, 5, 12, 9 }, { 12, 9, 4, 9 },
      { 4, 9, 4, 15 },   { 4, 15, 12, 15 }, { 12, 15, 12, 19 },
      { 12, 19, 20, 12 },
    }
  else
    seg = {
      { 4, 12, 12, 5 }, { 12, 5, 12, 9 }, { 12, 9, 20, 9 },
      { 20, 9, 20, 15 }, { 20, 15, 12, 15 }, { 12, 15, 12, 19 },
      { 12, 19, 4, 12 },
    }
  end
  local items = {}
  for _, s in ipairs(seg) do
    items[#items + 1] = { type = "line", x1 = s[1], y1 = s[2], x2 = s[3], y2 = s[4],
      width = 2, color = color, round_start = true, round_end = true }
  end
  return items
end

-- 远光灯（上半圆灯罩 + 底部横线 + 3 条向下光束）
function M.high(color)
  return {
    { type = "arc", cx = 12, cy = 12, r = 7, start_angle = 180, end_angle = 360,
      width = 2, color = color, rounded = true },
    { type = "line", x1 = 5, y1 = 12, x2 = 19, y2 = 12, width = 2, color = color,
      round_start = true, round_end = true },
    { type = "line", x1 = 9, y1 = 13, x2 = 9, y2 = 18, width = 2, color = color,
      round_end = true },
    { type = "line", x1 = 12, y1 = 13, x2 = 12, y2 = 20, width = 2, color = color,
      round_end = true },
    { type = "line", x1 = 15, y1 = 13, x2 = 15, y2 = 18, width = 2, color = color,
      round_end = true },
  }
end

-- 电池（机身 + 正极凸台 + 内部三格电量）
function M.batt(color)
  return {
    { type = "rect", x = 3, y = 7, w = 15, h = 10, radius = 2, width = 2, color = color },
    { type = "rect", x = 19, y = 10, w = 2, h = 4, radius = 1, width = 2, color = color },
    { type = "rect", x = 6, y = 10, w = 3, h = 4, radius = 1, width = 2, color = color },
    { type = "rect", x = 10, y = 10, w = 3, h = 4, radius = 1, width = 2, color = color },
    { type = "rect", x = 14, y = 10, w = 3, h = 4, radius = 1, width = 2, color = color },
  }
end

-- 太阳（暗色主题 → 点它切到亮色）
function M.sun(color)
  local rays = {
    { 12, 2, 12, 5 }, { 12, 19, 12, 22 },
    { 2, 12, 5, 12 }, { 19, 12, 22, 12 },
    { 5, 5, 7, 7 }, { 17, 17, 19, 19 },
    { 19, 5, 17, 7 }, { 5, 19, 7, 17 },
  }
  local items = {
    { type = "circle", cx = 12, cy = 12, r = 4, width = 2, color = color },
  }
  for _, r in ipairs(rays) do
    items[#items + 1] = { type = "line", x1 = r[1], y1 = r[2], x2 = r[3], y2 = r[4],
      width = 2, color = color, round_end = true }
  end
  return items
end

-- 月亮（亮色主题 → 点它切到暗色）。月牙 = 实心圆 + 偏置背景色圆"切"出缺口
function M.moon(color, bg)
  return {
    { type = "circle", cx = 12, cy = 12, r = 8, fill = true,
      fill_color = color, color = color, opacity = 0 },
    { type = "circle", cx = 15, cy = 9, r = 7, fill = true,
      fill_color = bg, color = bg, opacity = 0 },
  }
end

-- 图元等比缩放（几何字段乘 k 后取整；C 层 lua_tointeger 会把小数读成 0，必须取整）
function M.scale(items, k)
  k = k or 1
  local out = {}
  local function g(v) return math.floor(v * k + 0.5) end
  for i, it in ipairs(items or {}) do
    local o = {}
    for key, v in pairs(it) do o[key] = v end
    if o.x1 ~= nil then o.x1, o.y1 = g(o.x1), g(o.y1) end
    if o.x2 ~= nil then o.x2, o.y2 = g(o.x2), g(o.y2) end
    if o.cx ~= nil then o.cx, o.cy = g(o.cx), g(o.cy) end
    if o.x ~= nil then o.x, o.y = g(o.x), g(o.y) end
    if o.w ~= nil then o.w = g(o.w) end
    if o.h ~= nil then o.h = g(o.h) end
    if o.r ~= nil then o.r = math.max(1, g(o.r)) end
    if o.width ~= nil then o.width = math.max(1, g(o.width)) end
    out[i] = o
  end
  return out
end

return M
