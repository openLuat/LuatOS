--[[
  ui_theme.lua  设计令牌（唯一色板真源）+ 亮/暗就地重涂

  令牌键名 = 效果稿 CSS 变量名去掉 `--`，token_diff.py 按此逐键对账。
  带 alpha 的三个键（disc / vline / edgeline）在 P.*_opa 里给同名 opa。

  为什么重涂而不是重建（T2 路线 B）：键盘页有「敲到一半的会员号」、档位页有
  「已选档位」、支付页有「进行中的订单」，重建会全部清掉（T5 禁止调 enter()）。

  落盘 T9：模式存 fskv，重启 apply 恢复。
  兜底 T7：repaint 返回 0 说明固件 set_color 全挂，退回整体重建。
]]

local ST = require "app_state"
local W  = require "ui_widget"

local M = {}

-- ==================== 令牌 ====================
-- 暗色：暖金 + 石墨黑。卡片对 bg 1.40:1，面本身可辨；轮廓 edge 1.72:1（F6 ≥1.4）。
M.P = { dark = {
  bg        = 0x0E0F12,   -- 页面底
  panel     = 0x171A20,   -- 面板（预留）
  card      = 0x2A2F38,   -- 卡片 / 按钮底（1.40:1）
  tile      = 0x343B47,   -- 内嵌块 / 胶囊 / 键帽
  track     = 0x3C4450,   -- 槽底（预留）
  hl        = 0x4A5261,   -- 高光（预留）
  edge      = 0x454D5A,   -- 块轮廓（1.72:1）
  divider   = 0x39404C,   -- 分隔线
  shadow    = 0x000000,   -- 错位投影
  text      = 0xF4F1EA,   -- 主文字 16.1:1
  text_sub  = 0xC9C4B9,   -- 次级 10.6:1
  text_dim  = 0xA9A296,   -- 辅助 7.6:1（小字按 7:1 定）
  pri       = 0xD9B36C,   -- 暖金：金额 / 强调
  pri_deep  = 0xB08A46,   -- 金线 / 角标描边
  on_pri    = 0x141518,   -- 压金底的字
  btn       = 0xD9B36C,   -- 主按钮底
  sel       = 0x3A3423,   -- 选中档位卡底
  ok        = 0x7FB98A,
  warn      = 0xD9A05B,
  danger    = 0xC86A6A,
  disc      = 0xD9B36C,   -- 背景大圆盘
  vline     = 0xF4F1EA,   -- 竖细线
  edgeline  = 0xD9B36C,   -- 上下压边金线
}, light = {
  bg        = 0xE2D8C5,   -- 米底（压深，白卡才浮得起来 1.41:1）
  panel     = 0xFBF8F2,
  card      = 0xFFFFFF,
  tile      = 0xFDFAF4,
  track     = 0xDED4C0,
  hl        = 0xFFFFFF,
  edge      = 0xA8997C,   -- 轮毂 2.00:1
  divider   = 0xCFC4AE,
  shadow    = 0x9C8E72,
  text      = 0x221F1A,   -- 13.4:1
  text_sub  = 0x4A443A,   -- 7.6:1
  text_dim  = 0x5C5548,   -- 5.9:1
  pri       = 0x7E5A18,   -- 5.0:1
  pri_deep  = 0x5F4210,
  on_pri    = 0xFFFDF9,
  btn       = 0x26231D,   -- 亮底上主按钮反过来用深炭
  sel       = 0xF8EDD4,
  ok        = 0x2F6B3F,
  warn      = 0x8A5A16,
  danger    = 0x8E3434,
  disc      = 0x7E5A18,
  vline     = 0x221F1A,
  edgeline  = 0x7E5A18,
} }

M.P.dark_opa  = { disc = 14, vline = 13, edgeline = 87 }
M.P.light_opa = { disc = 13, vline = 11, edgeline = 71 }

-- ==================== 当前态 ====================
local cur = "dark"

-- 由 ui.lua 注入
M.on_apply   = nil    -- 重涂后刷新无法 set_color 的部分（渐变底、二维码静区）
M.on_rebuild = nil    -- repaint 全挂时整体重建

function M.get() return cur end
function M.is_light() return cur == "light" end
function M.pal() return (cur == "light") and M.P.light or M.P.dark end
function M.opa() return (cur == "light") and M.P.light_opa or M.P.dark_opa end
function M.c(tok) return M.pal()[tok] or 0xFFFFFF end
function M.a(tok) return M.opa()[tok] or 255 end

function M.apply(theme, persist)
  theme = (theme == "light") and "light" or "dark"
  cur = theme
  ST.S.theme = theme
  if persist then ST.set_theme(theme) end

  W.set_ona(M.opa())
  local pal = M.pal()
  W.set_pal(pal)

  local n = W.repaint(pal)
  if n == 0 and M.on_rebuild then
    log.warn("theme", "set_color 全部失败，退回重建")
    M.on_rebuild(theme)
    return
  end
  if M.on_apply then M.on_apply(pal, theme) end
end

function M.toggle()
  M.apply((cur == "light") and "dark" or "light", true)
  return cur
end

function M.init()
  M.apply(ST.S.theme or "dark", false)
end

return M
