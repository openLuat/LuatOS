--[[
  ui.lua  UI 总入口：组装各组件 + 交互回调 + 主循环分级刷新

  交互（airui 的 on_click 只能在创建参数里传，所以回调统一在这里生成闭包下传）：
    · 顶栏模式胶囊 → 循环 ECO / NORMAL / SPORT
    · 左栏 MODE 三档胶囊 → 直接选档
    · 右栏 BATTERY 卡 → 模拟插枪/拔枪
    · 右上圆形按钮 → 明暗主题切换（延迟重建）
]]

local cfg      = require "app_config"
local state    = require "app_state"
local sim      = require "app_sim"
local W        = require "ui_widget"
local topbar   = require "ui_topbar"
local dial     = require "ui_dial"
local inds     = require "ui_indicators"
local cards    = require "ui_cards"
local bottom   = require "ui_bottom"
local backdrop = require "ui_backdrop"

local M = {}

local rebuilding = false

-- 模式切换：仿真 + 持久化 + 四处可视反馈（都不重建界面）
-- 背景色斑 / 底部氛围光 / 表盘雾光 与胶囊同色，整屏就一个色系
local function apply_mode(i)
  sim.set_mode(i)
  state.set_mode(i)
  cards.set_mode(i)
  topbar.set_mode(i)
  backdrop.set_mode()
  dial.set_mode()
end

local function on_mode(i)
  apply_mode(i)
end

local function on_mode_cycle()
  apply_mode(sim.mode % 3 + 1)
end

local function on_charge()
  sim.toggle_charge()
end

-- 主题切换：先切状态/配色，再延迟重建（等 on_click 回调栈返回，避免在回调里销毁对象）
local function on_toggle()
  local next_theme = (state.theme == "dark") and "light" or "dark"
  state.set_theme(next_theme)
  cfg.set_theme(next_theme)
  sys.taskInit(function()
    sys.wait(120)
    M.rebuild()
  end)
end

function M.build()
  local page = W.new_page()
  -- z 序就是创建顺序：色斑最先（卡片透出来的就是它），氛围光最后（盖在卡片上做染色）
  backdrop.build_orb(page)
  topbar.build(page, state.theme, on_toggle, on_mode_cycle)
  dial.build(page)
  inds.build(page)
  cards.build(page, on_mode, on_charge)
  bottom.build(page)
  backdrop.build_amb(page)
end

function M.rebuild()
  if rebuilding then return end
  rebuilding = true
  W.destroy_pages()
  M.build()
  rebuilding = false
end

-- 每帧（约 33ms）推进：仿真 → 各组件按自己的节奏刷新
function M.tick(dt)
  sim.tick(dt)
  topbar.render(dt)
  dial.render(dt)
  inds.render(dt)
  cards.render(dt)
  bottom.render()
end

return M
