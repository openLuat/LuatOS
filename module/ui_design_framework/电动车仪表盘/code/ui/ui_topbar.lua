--[[
  ui_topbar.lua  顶栏：LIVE 呼吸点 + 模式胶囊（点击循环切换） + 日期 + 时钟 + 主题按钮
  主题切换 / 模式切换的回调都由 ui.lua 注入，切换后主题整体重建，模式只换色不重建。
]]

local cfg  = require "app_config"
local sim  = require "app_sim"
local util = require "app_util"
local T    = require "ui_theme"
local W    = require "ui_widget"
local ico  = require "ui_icon"

local C  = T.C
local L  = T.L
local SZ = T.SIZES

local DOT_S = cfg.ANIM.dot_ms / 1000

local M = {}

local WEEK = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }

local R = {}
local t_dot, dot_on = 0, true
local t_clock, last_clock, last_date = 0, "", ""

-- 时钟 / 日期（提前声明：build 里要立即刷一次）
local refresh_clock

function M.build(parent, theme, on_toggle, on_mode)
  -- 左：LIVE 呼吸点 + 文本
  R.dot = W.shape(parent, L.mx, 20, 10, 10, {
    { type = "circle", cx = 5, cy = 5, r = 4,
      fill = true, fill_color = C.magenta, color = C.magenta, opacity = 0 },
  })
  R.live = W.label(parent, L.mx + 18, 14, 64, 22, "实时", SZ.micro,
    C.magenta, airui.TEXT_ALIGN_LEFT)

  -- 中：模式胶囊（点击循环 经济 → 标准 → 运动）；no_glint = 26px 小胶囊不要顶部高光线
  R.chip = W.card(parent, 474, 14, 76, 26, 13, on_mode, 1, true)
  R.chipLb = W.label(R.chip, 0, 1, 74, 22, "标准", SZ.micro,
    C.violet, airui.TEXT_ALIGN_CENTER)

  -- 右：日期 + 时钟 + 主题按钮
  R.date = W.label(parent, 660, 16, 136, 22, "", SZ.micro,
    C.textMute, airui.TEXT_ALIGN_RIGHT)
  R.clock = W.label(parent, 832, 10, 108, 30, "00:00", SZ.value,
    C.text, airui.TEXT_ALIGN_RIGHT)

  local btn = W.card(parent, 952, 10, 44, 44, 22, on_toggle, 1, true)
  R.btn = btn
  -- 按钮比卡片"实体"一点：底色白 + 更高 opa（18/184），描边走预混实色
  btn:set_color(C.btnBg, C.btnBgOpa or 255)
  btn:set_border_color(C.btnEdge, 1)
  if theme == "light" then
    R.icon = W.shape(btn, 9, 9, 24, 24, ico.moon(C.btnIcon, C.btnBg))
  else
    R.icon = W.shape(btn, 9, 9, 24, 24, ico.sun(C.btnIcon))
  end

  t_dot, dot_on = 0, true
  t_clock, last_clock, last_date = 0, "", ""
  M.set_mode(sim.mode)
  refresh_clock()
end

-- 模式胶囊换文案 + 换色
function M.set_mode(i)
  local md = sim.MODES[i] or sim.MODES[2]
  local col = T.accent(i)
  if R.chipLb ~= nil then
    W.st(R.chipLb, md.cn or md.name)
    R.chipLb:set_color(col)
  end
  if R.chip ~= nil then R.chip:set_border_color(col, 1) end
end

function refresh_clock()
  local t = os.date("*t")
  local s = util.pad2(t.hour) .. ":" .. util.pad2(t.min)
  if s ~= last_clock then
    last_clock = s
    W.st(R.clock, s)
  end
  local d = util.pad2(t.month) .. "/" .. util.pad2(t.day) .. "  " .. (WEEK[t.wday] or "")
  if d ~= last_date then
    last_date = d
    W.st(R.date, d)
  end
end

function M.render(dt)
  -- LIVE 呼吸：0.75s 翻转一次（模拟 CSS 1.5s pulse）
  t_dot = t_dot + dt
  if t_dot >= DOT_S then
    t_dot = t_dot - DOT_S
    dot_on = not dot_on
    if R.dot ~= nil then
      local opa = dot_on and 255 or 70
      R.dot:set_items({
        { type = "circle", cx = 5, cy = 5, r = 4, fill = true,
          fill_color = C.magenta, color = C.magenta, opacity = 0,
          fill_opacity = opa },
      })
    end
  end

  t_clock = t_clock + dt
  if t_clock >= 1.0 then
    t_clock = t_clock - 1.0
    refresh_clock()
  end
end

return M
