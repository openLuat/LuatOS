--[[
  ui_theme.lua  UI 主题出口：配色引用 + 屏幕几何 + 坐标/字号换算 + 字号阶梯
  本项目设计画布 = 实际屏幕 = 1024x600（kx = ky = 1），表盘保持正圆。
]]

local cfg = require "app_config"
local M = {}

M.C = cfg.C              -- 配色（引用，主题切换时原地覆盖，引用不变）
M.L = cfg.LAYOUT         -- 布局尺寸
M.SIZES = cfg.SIZES      -- 字号阶梯

-- 实机屏
M.SW, M.SH = cfg.HW.screen.w, cfg.HW.screen.h
M.PANEL_W, M.PANEL_H = cfg.HW.screen.panel_w, cfg.HW.screen.panel_h
-- 设计画布（= 实机，避免圆被非等比缩放压扁）
M.DW, M.DH = M.SW, M.SH

M.kx = M.SW / M.DW       -- 1.0
M.ky = M.SH / M.DH       -- 1.0

local function rnd(v) return math.floor(v + 0.5) end

function M.sx(v) return rnd(v * M.kx) end
function M.sy(v) return rnd(v * M.ky) end

-- 字号：hzfont 下限 16、上限 255
function M.sf(v)
  local s = rnd((v or 16) * M.kx)
  if s < 16 then s = 16 end
  if s > 255 then s = 255 end
  return s
end

-- 页面区（全屏单页）
M.PX, M.PY = M.L.px, M.L.py
M.PW, M.PH = M.L.pw, M.L.ph

-- 驾驶模式强调色（1 ECO / 2 NORMAL / 3 SPORT），运行期取当前主题值
M.MODE_COLOR_KEY = { "cyan", "violet", "magenta" }

function M.accent(i)
  local k = M.MODE_COLOR_KEY[i or 2]
  return M.C[k] or M.C.violet
end

return M
