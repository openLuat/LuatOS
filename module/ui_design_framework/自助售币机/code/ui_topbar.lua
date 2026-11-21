--[[
  ui_topbar.lua  顶栏（1024×58）

  常驻，不随页面移动：parent = nil 的独立根，位置固定 (0,0)。
  必须最后 build —— LVGL 按创建顺序压层，先建就会被后面全屏透明的页面盖住。

  坐标见 docs/handoff.md §3.2。
]]

local cfg = require "app_config"
local ST  = require "app_state"
local W   = require "ui_widget"
local TH  = require "ui_theme"

local M = {}
local L = cfg.L

local root, mem_lb, bal_num, clk_num, sun_ic, moon_ic

-- ==================== 构建 ====================
function M.build()
  W.group("top")
  root = W.box(nil, 0, 0, L.top_w, L.top_h, { color = W.c("bg"), opa = 0, tag = "top" })

  -- 徽标 + 品牌（x=76 起，与 34px 徽标留 14px 间距）
  W.icon(root, "logo", L.brand_x, L.brand_y, L.brand_s, "pri", "toplogo")
  W.label(root, 76, 11, 230, { text = "星光电玩城", size = 20, ck = "text", h = 26, tag = "brand" })
  W.label(root, 76, 38, 300, { text = "STAR ARCADE", size = 16, ck = "text_dim", h = 19, tag = "brand2" })

  -- 会员胶囊：188×32 → 内容区 186×30
  local mb = W.box(root, L.mem_x, L.mem_y, L.mem_w, L.mem_h, {
    bw = 1, radius = 16, skin = "tile", bskin = "edge", tag = "topmem" })
  W.icon(mb, "member", 13, 8, 16, "text_sub", "topmemi")
  mem_lb = W.label(mb, 36, 7, 142, { text = "未登录", size = 16, ck = "text_sub", h = 19, tag = "topmemt" })

  -- 余额胶囊：178×32 → 内容区 176×30；数字右缘贴 166（留 10px）
  local bb = W.box(root, L.bal_x, L.bal_y, L.bal_w, L.bal_h, {
    bw = 1, radius = 16, skin = "tile", bskin = "edge", tag = "topbal" })
  W.icon(bb, "coin", 9, 6, 20, "pri", "topbali")
  W.label(bb, 35, 7, 44, { text = "余额", size = 16, ck = "text_sub", h = 19, tag = "topbalt" })
  bal_num = W.num(bb, 176 - W.num_w("9999", 20) - 10, 5, "9999", 20, "pri")

  -- 时钟胶囊：112×32 → 内容区 110×30；"99:99:99" 18 号宽 82
  local cb = W.box(root, L.clk_x, L.clk_y, L.clk_w, L.clk_h, {
    bw = 1, radius = 16, skin = "tile", bskin = "edge", tag = "topclk" })
  clk_num = W.num(cb, 14, 6, "99:99:99", 18, "text_sub")

  -- 主题按钮：32×32 → 内容区 30×30；日/月两个图标叠放，靠 opa 切换（shape 无 set_color）
  local tb = W.box(root, L.thm_x, L.thm_y, L.thm_w, L.thm_h, {
    bw = 1, radius = 16, skin = "tile", bskin = "edge", tag = "topthm" })
  sun_ic  = W.icon(tb, "sun", 7, 7, 16, "text_sub", "topicons")
  moon_ic = W.icon(tb, "moon", 7, 7, 16, "text_sub", "topiconsm")
  W.press(tb, 1, 1, 28, 28, function() M.on_theme() end, { tag = "topthmhit" })

  W.bar(root, 28, L.hr_y, 968, 1, "divider", 255)

  M.sync_theme()
  M.set_clock()
end

-- ==================== 状态同步 ====================
function M.set_member(code)
  code = code or ""
  if not mem_lb then return end
  local on = (code ~= "")
  mem_lb:set_text(on and ("会员 " .. code:sub(-4)) or "未登录")
  pcall(mem_lb.set_color, mem_lb, W.c(on and "text" or "text_sub"))
end

function M.set_bal(n)
  -- 右对齐：余额格子的 x 是按右缘 166 反推的，靠左填会让 0 贴到"余额"右边，
  -- 数字一进位就往右顶，右缘不固定
  if bal_num then bal_num.set(tostring(math.floor(tonumber(n) or 0)), true) end
end

function M.set_clock()
  if not clk_num then return end
  local t = os.date("*t")
  if type(t) == "table" and t.hour then
    clk_num.set(string.format("%02d:%02d:%02d", t.hour, t.min, t.sec))
  end
end

-- 主题切换后：运行期改过色的（会员字 / 余额 / 日月底色）必须重刷，
-- repaint 只按登记时的 ck 走，覆盖不到这些（T6）。
function M.sync_theme()
  local light = TH.is_light()
  if sun_ic  then W.opa(sun_ic,  light and 0 or 255) end
  if moon_ic then W.opa(moon_ic, light and 255 or 0) end
  M.set_member(ST.S.member)
  M.set_bal(ST.S.bal)
end

return M
