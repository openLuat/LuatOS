--[[
  ui_bottom.lua  底部数据带：总里程 / 本次里程 / 平均速度 三栏
  一条 976x88 的玻璃卡片横贯底部，栏间 1px 竖分隔线，数值 34 号等宽感居中。
  内容区 = 976-2 x 88-2 = 974 x 86，三栏各 324，末栏 648+324 = 972 ≤ 974。

  原来 4 栏（RANGE/ODO/TRIP/AVG）里 RANGE 已挪到右列电量卡，
  剩 3 栏刚好够宽，数值不用挤。
]]

local sim  = require "app_sim"
local util = require "app_util"
local T    = require "ui_theme"
local W    = require "ui_widget"

local C  = T.C
local L  = T.L
local SZ = T.SIZES

local M = {}

local COL_W = 324
-- k = 显示精度的整数刻度（km 取整、km 一位小数 ×10），v = 格式化函数。
-- 只比 k：值没跨过刻度就不重新拼字符串——原先每帧都拼 3 个，
-- 30fps 下每秒 90 个临时串，全是 GC 的活。
local COLS = {
  { cap = "总里程 km",    k = function() return math.floor(sim.odo) end,
                          v = function() return util.fmt(sim.odo) end },
  { cap = "本次里程 km",  k = function() return math.floor(sim.trip * 10) end,
                          v = function() return util.one_dp(sim.trip) end },
  { cap = "平均速度 km/h", k = function() return math.floor(sim.avg) end,
                          v = function() return util.fmt(sim.avg) end },
}

local R = {}
local last_k = {}

function M.build(parent)
  local c = W.card(parent, L.mx, L.band_y, 976, L.band_h, 14)
  R.vals = {}
  last_k = {}          -- 重建后新控件停在 "--" 占位，游标不清空就不会重刷
  for i = 1, #COLS do
    local x = COL_W * (i - 1)
    W.label(c, x, 10, COL_W, 19, COLS[i].cap, SZ.micro, C.textMute, airui.TEXT_ALIGN_CENTER)
    R.vals[i] = W.label(c, x, 34, COL_W, 40, "--", SZ.big, C.text, airui.TEXT_ALIGN_CENTER)
    if i > 1 then
      W.vline(c, x, 12, 62, C.hairline)
    end
  end
end

function M.render()
  for i = 1, #COLS do
    local k = COLS[i].k()
    if k ~= last_k[i] then
      last_k[i] = k
      W.st(R.vals[i], COLS[i].v())
    end
  end
end

return M
