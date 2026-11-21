--[[
  ui_success.lua  支付成功（独立屏，560×460）

  为什么不复用支付页的状态条：成功后二维码还留在屏幕上，用户会以为还要再扫一次，
  而实际该做的是去取币口拿币。所以成功必须换屏，且二维码消失。

  10 秒自动回首页：公共设备上成功页滞留等于把上一位的订单摆在下一个用户面前。
  倒计时到点由 ui.lua 的 tick 驱动，页面自己不开定时器。

  坐标见 docs/handoff.md §3.7。
]]

local cfg = require "app_config"
local ST  = require "app_state"
local W   = require "ui_widget"

local M = {}
local L = cfg.L

local root, amt_num, coin_lb, left_num

-- ==================== 构建 ====================
function M.build()
  W.group("success")
  root = W.box(nil, -1080, 0, cfg.HW.screen.w, cfg.HW.screen.h, { color = W.c("bg"), opa = 0, tag = "success" })

  local c = W.box(root, L.ok_x, L.ok_y, L.ok_w, L.ok_h, {
    bw = 1, radius = 18, skin = "card", bskin = "edge", tag = "okcard" })

  -- 对勾圆环：填充 10% + 2px 描边（真机 = circle 描边，不是阴影/模糊）
  W.box(c, 243, 34, 72, 72, { color = W.c("ok"), opa = 26, bw = 2,
                              border = W.c("ok"), radius = 36, tag = "okring" })
  W.icon(c, "check", 267, 61, 24, "ok", "oktick")

  -- 卡片内容区 558×458：文字块宽 556，右缘留 2px
  W.text_mid(c, 0, 120, 556, 37, { text = "支付成功", size = 34, ck = "text", tag = "oktitle" })
  W.text_mid(c, 0, 163, 556, 21, { text = "游戏币已到账", size = 18, ck = "text_sub", tag = "okdesc" })

  W.bar(c, 48, 204, 462, 1, "divider", 255)

  W.label(c, 48, 224, 200, { text = "支付金额", size = 16, ck = "text_dim", h = 19, tag = "okl1" })
  -- 金额右对齐：右缘 278+232 = 510，"9999.99" 20 号宽 4×13+13+2×6 = 77 → x = 433
  amt_num = W.num(c, 510 - W.num_w("9999.99", 20), 222, "9999.99", 20, "text")

  W.label(c, 48, 256, 200, { text = "到账游戏币", size = 16, ck = "text_dim", h = 19, tag = "okl2" })
  coin_lb = W.text_right(c, 278, 254, 232, 21, { text = "—", size = 18, ck = "pri", tag = "okcoin" })

  -- 取币提示 462×48 → 内容区 460×46
  local tip = W.box(c, 48, 288, 462, 48, { bw = 1, radius = 10, skin = "card", bskin = "edge", tag = "oktip" })
  W.box(tip, 16, 16, 14, 14, { color = W.c("ok"), radius = 7, tag = "oktipd" })
  W.label(tip, 38, 14, 404, { text = "请到下方取币口领取实体币", size = 16, ck = "text_sub", h = 19, tag = "oktipt" })

  left_num = W.num(c, 184, 346, "99", 20, "text")
  W.label(c, 214, 348, 160, { text = "秒后自动返回首页", size = 16, ck = "text_dim", h = 19, tag = "oksec" })

  -- 完成 200×52（无描边）
  local b = W.box(c, 69, 384, 200, 52, { color = W.c("btn"), radius = 14, bw = 0, skin = "btn", tag = "okdone" })
  W.text_mid(b, 0, 15, 198, 21, { text = "完成返回首页", size = 18, ck = "on_pri", tag = "okdonet" })
  W.press(b, 1, 1, 198, 50, function() M.on_home() end, { tag = "okdonehit" })

  -- 继续购买 200×52 → 内容区 198×50
  local m = W.box(c, 289, 384, 200, 52, { bw = 1, radius = 14, skin = "tile", bskin = "edge", tag = "okmore" })
  W.text_mid(m, 0, 15, 196, 21, { text = "继续购买", size = 18, ck = "text_sub", tag = "okmoret" })
  W.press(m, 1, 1, 196, 48, function() M.on_more() end, { tag = "okmorehit" })

  M.sync()
end

-- ==================== 显隐 ====================
function M.show(on)
  -- 传数字 = 过渡帧：直接摆 x（只接受 ≤ 0，右侧永不越界，AGENTS G6）
  if type(on) == "number" then
    if root and on <= 0 then pcall(root.set_pos, root, on, 0) end
    return
  end
  if root then pcall(root.set_pos, root, on and 0 or -1080, 0) end
  if on then M.sync() end
end

-- ==================== 状态同步 ====================
function M.set_left(sec)
  if left_num then left_num.set(string.format("%02d", math.max(0, math.floor(sec or 0)))) end
end

function M.sync()
  if not root then return end
  local info = ST.info()
  if amt_num then amt_num.set(ST.money(info.pay), true) end
  if coin_lb then
    coin_lb:set_text(info.coins .. " 币" .. (info.gift > 0 and (" + " .. info.gift .. " 赠") or ""))
  end
  M.set_left(ST.S.succLeft or 10)
end

return M
