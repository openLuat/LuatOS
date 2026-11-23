--[[
  ui_indicators.lua  左右指示灯卡片（各 3 行）

  左卡：左转向（绿·闪）/ 远光灯（青）/ ABS 刹车辅助（琥珀·文字徽标）
  右卡：右转向（绿·闪）/ 电池（琥珀）/ TCS 防滑（品红·文字徽标）

  明暗：亮态用主题色，暗态用 cfg.dim_hex 压暗（AirUI 容器透明度不带子控件，
  所以指示灯不靠父容器 alpha 做明暗，而是直接换两套色值）。
  每行底板是一块透明 container，亮起时 set_color(accent, 28) 做发光底。
]]

local cfg  = require "app_config"
local sim  = require "app_sim"
local T    = require "ui_theme"
local W    = require "ui_widget"
local ico  = require "ui_icon"

local C  = T.C
local L  = T.L
local SZ = T.SIZES

local M = {}

local ICON_W = 30
local IK     = ICON_W / 24          -- 图标放大系数
local TXT_W  = 40                   -- 文字徽标（ABS / TCS）：30 宽装不下三个大写字母，LVGL 会折行顶出底板
local ROW_W  = 202
local ROW_H  = 44
local ROW_X  = 14
local ROWS_Y = { 2, 53, 104 }       -- 2 + 44 = 46，53 + 44 = 97，104 + 44 = 148 ≤ 150

-- 暗态图标亮度系数。0.26 时线框图形和 16 号字母在深底上只剩轮廓残影，
-- 实机看不清哪一行对应哪个功能；0.45 能认出形状又不至于和亮态混淆
-- （亮态还有满色 + 发光底 + 文字恒白，区分仍在 3 倍以上对比度差）。
local DIM_K = 0.45

-- blink = true 的行在亮起时跟随 sim.blink 做 1Hz 闪烁（转向灯专用）
local LEFT = {
  { id = "left", kind = "turn", dir = "l", key = "green", name = "左转向", blink = true },
  { id = "high", kind = "high",             key = "cyan",  name = "远光灯" },
  { id = "abs",  kind = "text", label = "ABS", key = "amber", name = "刹车辅助" },
}
local RIGHT = {
  { id = "right", kind = "turn", dir = "r", key = "green", name = "右转向", blink = true },
  { id = "batt",  kind = "batt",             key = "amber", name = "电池" },
  { id = "tcs",   kind = "text", label = "TCS", key = "magenta", name = "防滑" },
}

local R = { list = {} }

local function icon_items(cf, color)
  if cf.kind == "turn" then return ico.turn(cf.dir, color) end
  if cf.kind == "high" then return ico.high(color) end
  if cf.kind == "batt" then return ico.batt(color) end
  return nil
end

local function make_row(parent, cf, y)
  local row = W.group(parent, ROW_X, y, ROW_W, ROW_H, nil, 12)
  local icon
  if cf.kind == "text" then
    icon = W.label(row, 0, 10, TXT_W, 24, cf.label, SZ.micro,
      C[cf.key], airui.TEXT_ALIGN_CENTER)
  else
    icon = W.shape(row, 0, 7, ICON_W, ICON_W,
      ico.scale(icon_items(cf, C[cf.key]), IK))
  end
  -- 说明文字恒用纯白：原先暗态 textDim 0x8F88AD 在深底 #07060E 上，16 号中文
  -- 只有约 4:1 对比度，实机反馈「熄灯时看不清是哪一行」。亮/灭仍靠图标颜色
  -- （满色 vs 26%）和底板发光区分，文字不再参与明暗。
  local lb = W.label(row, 38, 11, 160, 22, cf.name, SZ.micro,
    C.text, airui.TEXT_ALIGN_LEFT)
  return { row = row, icon = icon, lb = lb, cf = cf, last = nil }
end

function M.build(parent)
  R.list = {}
  local lc = W.card(parent, L.left_x, L.card_y1, L.col_w, L.card_h1, 14)
  local rc = W.card(parent, L.right_x, L.card_y1, L.col_w, L.card_h1, 14)
  for i = 1, 3 do
    R.list[#R.list + 1] = make_row(lc, LEFT[i], ROWS_Y[i])
    R.list[#R.list + 1] = make_row(rc, RIGHT[i], ROWS_Y[i])
  end
end

local acc = 1   -- 首帧立即刷一次（初值给满）

function M.render(dt)
  local th = cfg.ANIM.ind_ms / 1000
  acc = acc + (dt or 0)
  if acc < th then return end
  -- 减阈值、保留余数。原先是 acc = 0，把周期量化成整帧（100ms → 4 帧 133ms），
  -- 与 sim.blink 的 500ms 不再是 5:1，转向灯每次闪的时长就不一样了。
  acc = acc - th
  for _, e in ipairs(R.list) do
    local lit = sim.ind[e.cf.id] or false
    if e.cf.blink and lit then lit = sim.blink end   -- 转向灯：仅激活时 1Hz 闪烁
    if lit ~= e.last then
      e.last = lit
      local bright = C[e.cf.key]
      local col = lit and bright or cfg.dim_hex(bright, DIM_K)
      if e.cf.kind == "text" then
        e.icon:set_color(col)
      else
        e.icon:set_items(ico.scale(icon_items(e.cf, col), IK))
      end
      e.row:set_color(bright, lit and 28 or 0)       -- 发光底（0 = 全透明）
      -- 说明文字恒白（build 时已设），这里不再随 lit 改色，省一次 set_color
    end
  end
end

return M
