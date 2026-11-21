--[[
  ui_overview.lua  概览三卡 78..182，3×296 + 2×20 = 928
    卡1 当前模式：glow 左竖条 + 模式名 28 + 04 / 06
    卡2 能量档位：数字 28 + 5 段可点条
    卡3 本次时长：15:00 等宽 + 建议分钟 + 底部 10 段进度线

  卡内容区 294x102（bw=1），下面所有子控件按此收敛（G1）。
  卡内纵向：lab 12..31 / val 34..66 / sub 68..87 —— 三行不重叠，底留 15。

  颜色一律传令牌名，不传色值：日间 fill 与 glow 是同一个墨青，
  传色值的话重涂映射表分不开这两个角色（见 app_config 的说明）。
]]

local cfg = require "app_config"
local W = require "ui_widget"

local L = cfg.LAYOUT
local M = {}

local OV_W, OV_H = L.ov_w, L.ov_h      -- 296 x 104
local CW = OV_W - 2                     -- 294
local CH = OV_H - 2                     -- 102
local PADX = 22
local LV_MAX = 5
local PROG_SEG = 10

local function card(page, x)
  return W.box(page, x, L.ov_y, OV_W, OV_H,
    { color = "card", bw = 1, border = "line2", tag = "ovc" })
end

local function lab(c, text)
  W.label(c, PADX, 12, CW - PADX * 2, { text = text, size = 16, color = "ink3" })
end

function M.build(page, on_lv)
  local pad, gap = L.pad, L.ov_gap

  -- ---------- 卡1 当前模式 ----------
  local c1 = card(page, pad)
  -- 贯穿全高的竖条：从 1 开始（0 是 bw=1 的描边圈）
  -- 细长条用 glow：夜间 #4C8DFF 在 #0C1626 上够亮，#1D4ED8 会糊成一条黑缝
  W.bar(c1, 1, 1, 2, CH, "glow")
  lab(c1, "当前模式")
  local name = W.label(c1, PADX, 34, 160,
    { text = "射频紧致", size = 28, color = "ink", h = 32, tag = "ovName" })
  -- 页码右对齐：宽度按等宽格实算（写死 97 会留出 38px 空洞）
  local idx = W.num(c1, CW - PADX - W.num_w("99 / 99", 16), 68, "99 / 99", 16, "ink3")
  idx.set("04 / 06")

  -- ---------- 卡2 能量档位 ----------
  local c2 = card(page, pad + OV_W + gap)
  lab(c2, "能量档位")
  local lv = W.num(c2, PADX, 34, "9", 28, "ink")
  lv.set("5")

  local bars = {}
  local bx = PADX + 26
  for v = 1, LV_MAX do
    local hx = bx + (v - 1) * 31
    bars[v] = W.bar(c2, hx, 39 + 9, 26, 4, "line2")
    -- 热区最后盖住整格：细条也是 container（默认 CLICKABLE），
    -- 先建热区再塞细条会被细条截住点击，档位条就点不动
    W.press(c2, hx, 39, 26, 22, function()
      if on_lv then on_lv(v) end
    end, 0, "ovbar")
  end
  W.text_mid(c2, CW - PADX - 62, 39, 62, 22,
    { text = "共 5 档", size = 16, color = "ink3", align = airui.TEXT_ALIGN_RIGHT })

  -- ---------- 卡3 本次时长 ----------
  local c3 = card(page, pad + (OV_W + gap) * 2)
  lab(c3, "本次时长")
  local tm = W.num(c3, PADX, 34, "99:99", 28, "ink")
  tm.set("15:00")
  local sub = W.text_mid(c3, CW - PADX - 104, 39, 104, 22,
    { text = "建议 15 分钟", size = 16, color = "ink3",
      align = airui.TEXT_ALIGN_RIGHT, tag = "ovSub" })

  -- 进度线：容器无 set_size，拆成 10 段按 10% 步进点亮
  -- 起点 = 1 + 居中余量（0 是 bw=1 的描边圈，从 0 起会被收敛并告警）
  local SEG_W = 29
  local PROG_W = PROG_SEG * SEG_W                       -- 290
  local PROG_X = 1 + math.floor((CW - PROG_W) / 2)      -- 3
  local segs = {}
  for i = 1, PROG_SEG do
    segs[i] = W.bar(c3, PROG_X + (i - 1) * SEG_W, CH - 2, SEG_W, 2, "line2")
  end

  return {
    set_mode = function(m, i, n)
      name:set_text(m.n)
      idx.set(string.format("%02d / %02d", i, n))
      sub:set_text("建议 " .. m.m .. " 分钟")
    end,
    -- 档位条与进度段是「实心填色块」，走 fill：
    -- 夜间 #1D4ED8 是能一眼数清第几格的中深蓝，#4C8DFF 反而糊成一片
    set_lv = function(v)
      lv.set(tostring(v))
      for k, b in ipairs(bars) do
        W.set_color(b, (k <= v) and "fill" or "line2")
      end
    end,
    set_time = function(txt)
      tm.set(txt)
    end,
    -- k: 0..1，护理进度
    set_prog = function(k)
      local lit = math.floor(k * PROG_SEG + 0.5)
      for i, s in ipairs(segs) do
        W.set_color(s, (i <= lit) and "fill" or "line2")
      end
    end,
  }
end

return M
