--[[
  ui_pay.lua  支付页（左 420 二维码 / 右 528 订单明细）

  左卡只放"怎么付"，右卡只放"付多少"。成功不在这里改状态条：
  成功后二维码必须消失，否则用户以为还要再扫一次 → 见 ui_success.lua。

  坐标见 docs/handoff.md §3.6。
]]

local cfg = require "app_config"
local ST  = require "app_state"
local W   = require "ui_widget"

local M = {}
local L = cfg.L

local root, qr, brand_lb, left_num, stat_dot, stat_lb, note_lb
local v1, v2, v3, v4, pay_num

local ROW_Y = { 66, 100, 134, 168 }

-- ==================== 构建 ====================
function M.build()
  W.group("pay")
  root = W.box(nil, -1080, 0, cfg.HW.screen.w, cfg.HW.screen.h, { color = W.c("bg"), opa = 0, tag = "pay" })

  -- ---------- 左卡 420×496 → 内容区 418×494 ----------
  local lc = W.box(root, L.lx_x, L.lx_y, L.lx_w, L.lx_h, {
    bw = 1, radius = 18, skin = "card", bskin = "edge", tag = "pyl" })

  -- 26 号汉字宽度 = 字号，4 个字要 104；原来 w=96，「付」被挤到第二行
  W.label(lc, 28, 26, 112, { text = "扫码支付", size = 26, ck = "text", h = 31, tag = "pylt" })
  brand_lb = W.label(lc, 148, 30, 80, { text = "微信", size = 18, ck = "pri", h = 23, tag = "pylb" })

  -- 二维码框 200×200 → 内容区 198×198；码 170 居中 (14,14)
  local qb = W.box(lc, 109, 64, 200, 200, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "pyq" })
  qr = W.qrcode(qb, 14, 14, 170, { data = "PAY:DEMO", tag = "pyqr" })

  W.label(lc, 28, 288, 180, { text = "剩余支付时间", size = 16, ck = "text_dim", h = 19, tag = "pyt1" })
  left_num = W.num(lc, 300, 287, "99:99", 20, "pri")

  W.label(lc, 28, 326, 362, { text = "请使用手机扫描上方二维码", size = 16, ck = "text_sub", h = 19, tag = "pyt2" })
  W.label(lc, 28, 348, 362, { text = "支付完成后游戏币自动到账", size = 16, ck = "text_sub", h = 19, tag = "pyt3" })

  W.bar(lc, 28, 398, 362, 1, "divider", 255)
  note_lb = W.label(lc, 28, 418, 362, { text = "订单已生成，请在倒计时内完成", size = 16, ck = "text_dim", h = 19, tag = "pynote" })
  W.label(lc, 28, 444, 200, { text = "遇到问题请联系店员", size = 16, ck = "pri", h = 19, tag = "pyhelp" })

  -- ---------- 右卡 528×496 → 内容区 526×494 ----------
  local rc = W.box(root, L.rx_x, L.rx_y, L.rx_w, L.rx_h, {
    bw = 1, radius = 18, skin = "card", bskin = "edge", tag = "pyr" })

  W.label(rc, 28, 24, 200, { text = "订单明细", size = 26, ck = "text", h = 31, tag = "pyrt" })

  local K = { "充值档位", "到账游戏币", "会员加赠", "支付方式" }
  for i = 1, 4 do
    W.label(rc, 28, ROW_Y[i], 200, { text = K[i], size = 16, ck = "text_dim", h = 19, tag = "pyrk" .. i })
  end
  v1 = W.text_right(rc, 320, ROW_Y[1] - 1, 178, 21, { text = "—", size = 18, ck = "text", tag = "pyrv1" })
  v2 = W.text_right(rc, 320, ROW_Y[2] - 1, 178, 21, { text = "—", size = 18, ck = "text", tag = "pyrv2" })
  v3 = W.text_right(rc, 320, ROW_Y[3] - 1, 178, 21, { text = "—", size = 18, ck = "ok", tag = "pyrv3" })
  v4 = W.text_right(rc, 320, ROW_Y[4] - 1, 178, 21, { text = "—", size = 18, ck = "text", tag = "pyrv4" })

  W.bar(rc, 28, 206, 470, 1, "divider", 255)

  W.label(rc, 28, 228, 60, { text = "实付", size = 16, ck = "text_dim", h = 19, tag = "pyra" })
  W.label(rc, 72, 224, 28, { text = "¥", size = 26, ck = "pri", h = 29, tag = "pyrb" })
  pay_num = W.num(rc, 104, 215, "999.99", 44, "pri")

  -- 支付方式：两枚 228×56 → 内容区 226×54
  local w1 = W.box(rc, 28, 292, 228, 56, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "pyw" })
  W.text_mid(w1, 0, 17, 224, 21, { text = "微信支付", size = 18, ck = "text_sub", tag = "pywt" })
  W.press(w1, 1, 1, 224, 52, function() M.on_method("wx") end, { tag = "pywhit" })

  local w2 = W.box(rc, 272, 292, 228, 56, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "pya" })
  W.text_mid(w2, 0, 17, 224, 21, { text = "支付宝", size = 18, ck = "text_sub", tag = "pyat" })
  W.press(w2, 1, 1, 224, 52, function() M.on_method("ali") end, { tag = "pyahit" })

  -- 状态条 470×52 → 内容区 468×50
  local sb = W.box(rc, 28, 364, 470, 52, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "pystat" })
  stat_dot = W.box(sb, 16, 18, 16, 16, { color = W.c("warn"), radius = 8, tag = "pydot" })
  stat_lb  = W.label(sb, 44, 16, 420, { text = "等待支付", size = 18, ck = "text_sub", h = 21, tag = "pystatt" })

  -- 模拟 / 返回：各 228×52 → 内容区 226×50
  local s1 = W.box(rc, 28, 430, 228, 52, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "pysim" })
  W.text_mid(s1, 0, 15, 224, 21, { text = "模拟支付成功", size = 18, ck = "ok", tag = "pysimt" })
  W.press(s1, 1, 1, 224, 48, function() M.on_paid() end, { tag = "pysimhit" })

  local s2 = W.box(rc, 272, 430, 228, 52, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "pyback" })
  W.text_mid(s2, 0, 15, 224, 21, { text = "返回重选", size = 18, ck = "text_sub", tag = "pybackt" })
  W.press(s2, 1, 1, 224, 48, function() M.on_back() end, { tag = "pybackhit" })

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
function M.set_qr(text)
  if qr then pcall(qr.set_data, qr, text or "") end
end

-- kind: "wait" | "ok" | "fail"
function M.set_state(kind, text)
  if not stat_lb then return end
  local ck = (kind == "ok" and "ok") or (kind == "fail" and "danger") or "warn"
  stat_lb:set_text(text or "等待支付")
  pcall(stat_lb.set_color, stat_lb, W.c(ck))
  if stat_dot then pcall(stat_dot.set_color, stat_dot, W.c(ck), 255) end
  if note_lb then
    note_lb:set_text(kind == "fail" and "支付失败，可重试或更换支付方式" or "订单已生成，请在倒计时内完成")
  end
end

function M.set_left(sec)
  if left_num then
    local s = math.max(0, math.floor(sec or 0))
    left_num.set(string.format("%02d:%02d", math.floor(s / 60), s % 60))
  end
end

function M.sync()
  if not root then return end
  local t = ST.TIERS[ST.S.tier] or ST.TIERS[1]
  local info = ST.info()
  local custom = t.custom

  if brand_lb then brand_lb:set_text(ST.S.payMth == "ali" and "支付宝" or "微信") end
  if v1 then v1:set_text(custom and ("自定义 ¥" .. ST.money(info.pay)) or (info.coins .. " 币")) end
  if v2 then v2:set_text(info.coins .. " 币") end
  if v3 then v3:set_text(info.gift > 0 and ("+" .. info.gift .. " 币") or "无") end
  if v4 then v4:set_text(ST.S.payMth == "ali" and "支付宝" or "微信支付") end
  if pay_num then pay_num.set(ST.money(info.pay), true) end
end

return M
