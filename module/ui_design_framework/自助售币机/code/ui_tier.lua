--[[
  ui_tier.lua  档位页（3 列 × 2 行，卡 313×134 + 底部汇总卡 968×104）

  对象数恒定（P3）：6 张卡一次建好，运行期只 set_text / set_color / opa，
  不按档位数量增删控件。

  坐标见 docs/handoff.md §3.5。
]]

local cfg = require "app_config"
local ST  = require "app_state"
local W   = require "ui_widget"

local M = {}
local L = cfg.L

local root, cards = {}, {}, {}      -- cards[i] = { box, coin_lb, sub_lb, gift_lb, dot, tick }
local sum_coin, sum_gift, sum_mem, sum_pay, bal_num

-- ==================== 构建 ====================
local function build_card(i, x, y)
  local t = ST.TIERS[i]
  local c = W.box(root, x, y, L.tier_card_w, L.tier_card_h, {
    bw = 1, radius = 14, skin = "card", bskin = "edge", tag = "tc" .. i })

  local ent = { box = c }
  -- 内容区 311×132（外框 313×134，bw=1）：三行文字块 21..112，上下留白各 20/21
  -- 26 号行高 29 / 16 号行高 19，y 是外框坐标，故比效果稿的 top 多 1px
  ent.coin_lb = W.label(c, 20, 21, 190, { text = "", size = 26, ck = "text", h = 32, tag = "tcn" .. i })
  ent.sub_lb  = W.label(c, 20, 63, 200, { text = "", size = 16, ck = "text_dim", h = 19, tag = "tcs" .. i })
  ent.gift_lb = W.label(c, 20, 93, 180, { text = "", size = 16, ck = "ok", h = 19, tag = "tcg" .. i })

  -- 角标 64×24 → 内容区 62×22（只有热销档才显示）
  -- bskin 必须给：显隐靠 W.opa 把底色刷成透明，描边是独立属性，
  -- 不登记描边令牌的话隐藏后仍留一圈金边（幽灵框 G2/I2）
  local bg = W.box(c, 231, 23, 64, 24, { bw = 1, radius = 12, skin = "tile",
                                         bskin = "pri_deep", border = W.c("pri_deep"),
                                         tag = "tcb" .. i })
  ent.badge = bg
  W.text_mid(bg, 0, 0, 60, 22, { text = "热销", size = 16, ck = "pri", tag = "tcbt" .. i })

  -- 选中勾：实心圆 24 + 折线 14（圆心 277+12, 99+12；右/下各留 10px）
  -- skin = "pri"：不带令牌的话切主题后这枚圆点仍是旧主题的金色（T3）
  ent.dot  = W.box(c, 277, 99, 24, 24, { color = W.c("pri"), skin = "pri",
                                        radius = 12, opa = 0, tag = "tcd" .. i })
  ent.tick = W.icon(c, "check", 282, 104, 14, "on_pri", "tct" .. i)

  -- 热区按内容区坐标：内容区 311×132，起点 (1,1)、右/下缘 309/130
  W.press(c, 1, 1, 309, 130, function() M.on_pick(i) end, { tag = "tch" .. i })
  return ent
end

function M.build()
  W.group("tier")
  root = W.box(nil, -1080, 0, cfg.HW.screen.w, cfg.HW.screen.h, { color = W.c("bg"), opa = 0, tag = "tier" })

  W.label(root, 28, 76, 360, { text = "选择游戏币档位", size = 26, ck = "text", h = 36, tag = "ttitle" })
  W.label(root, 28, 122, 420, { text = "扫码支付 · 游戏币即时到账 · 会员额外加赠", size = 16, ck = "text_dim", h = 19, tag = "tdesc" })

  -- 余额胶囊 184×38 → 内容区 182×36
  local bb = W.box(root, 812, 76, 184, 38, { bw = 1, radius = 19, skin = "tile", bskin = "edge", tag = "tbal" })
  W.label(bb, 14, 9, 60, { text = "余额", size = 16, ck = "text_sub", h = 19, tag = "tbalt" })
  bal_num = W.num(bb, 182 - W.num_w("9999", 20) - 10, 6, "9999", 20, "pri")

  for i = 1, ST.TIER_MAX do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    cards[i] = build_card(i, L.tier_x + col * L.tier_dx, L.tier_y + row * L.tier_dy)
  end

  -- 汇总卡 968×104 → 内容区 966×102
  local s = W.box(root, L.sum_x, L.sum_y, L.sum_w, L.sum_h, {
    bw = 1, radius = 14, skin = "card", bskin = "edge", tag = "tsum" })

  -- 内容区 966×102，中线 52：整行按各自的真实行高对齐到这条线
  W.label(s, 28, 42, 60, { text = "已选", size = 16, ck = "text_dim", h = 19, tag = "ts1" })
  sum_coin = W.num(s, 70, 34, "9999", 34, "text")
  W.label(s, 168, 42, 30, { text = "币", size = 16, ck = "text_dim", h = 19, tag = "ts2" })

  W.label(s, 210, 42, 50, { text = "赠送", size = 16, ck = "text_dim", h = 19, tag = "ts3" })
  sum_gift = W.num(s, 252, 34, "999", 34, "ok")

  W.label(s, 352, 42, 50, { text = "会员", size = 16, ck = "text_dim", h = 19, tag = "ts4" })
  sum_mem = W.label(s, 394, 41, 130, { text = "未登录", size = 18, ck = "text_sub", h = 22, tag = "ts5" })

  -- 实付：标签 552 · ¥ 596 · 数字 622（模板 6 格 = 3×29 + 13 + 2×29 = 158 → 780 ≤ 792）
  -- 模板必须全用 9 占位：写成 "999.00" 时 ".00" 会被当成固定窄格文本，小数位永远显示 .00
  W.label(s, 552, 42, 40, { text = "实付", size = 16, ck = "text_dim", h = 19, tag = "ts6" })
  W.label(s, 596, 38, 28, { text = "¥", size = 26, ck = "pri", h = 29, tag = "ts7" })
  sum_pay = W.num(s, 622, 29, "999.99", 44, "pri")

  local b = W.box(s, 792, 20, 148, 64, { color = W.c("btn"), radius = 14, bw = 0, skin = "btn", tag = "tpay" })
  W.text_mid(b, 0, 0, 146, 64, { text = "确认支付", size = 20, ck = "on_pri", tag = "tpayt" })
  W.press(b, 1, 1, 146, 62, function() M.on_pay() end, { tag = "tpayhit" })

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
function M.sync()
  if not root then return end

  for i = 1, ST.TIER_MAX do
    local e, t = cards[i], ST.TIERS[i]
    if e then
      local sel = (ST.S.tier == i)
      local info = ST.info(i)

      -- 自定义档：币数位置显示已输入金额，副行给单位说明
      if t.custom then
        e.coin_lb:set_text("自定义")
        e.sub_lb:set_text("最低 ¥10 · " .. tostring(ST.S.cusYuan or 0) .. " 元")
        e.gift_lb:set_text("按 10 币 / 元折算")
      else
        e.coin_lb:set_text(tostring(t.coins))
        e.sub_lb:set_text("¥" .. tostring(t.price) .. " · " .. t.per)
        e.gift_lb:set_text((t.gift or 0) > 0 and ("+" .. t.gift .. " 赠币") or "无赠币")
      end

      pcall(e.coin_lb.set_color, e.coin_lb, W.c(sel and "pri" or "text"))
      pcall(e.gift_lb.set_color, e.gift_lb, W.c((t.gift or 0) > 0 and "ok" or "text_dim"))
      pcall(e.box.set_color, e.box, W.c(sel and "sel" or "card"), 255)
      pcall(e.box.set_border_color, e.box, W.c(sel and "pri" or "edge"), 1)

      -- 热销角标只给第 4 档（1000 币，单位价最低的非自定义档）
      W.opa(e.badge, (i == 4) and 255 or 0)
      W.opa(e.dot, sel and 255 or 0)
      W.opa(e.tick, sel and 255 or 0)

      local _ = info
    end
  end

  local info = ST.info()
  if sum_coin then sum_coin.set(tostring(info.coins)) end
  -- 模板 "+999" 里的 + 是固定窄格，值必须自己带上 +，否则首字符会被填进第一个数字格，整串错位
  if sum_gift then sum_gift.set("+" .. tostring(info.gift)) end
  if sum_pay  then sum_pay.set(ST.money(info.pay), true) end
  if sum_mem  then
    local m = ST.S.member or ""
    sum_mem:set_text((m ~= "") and ("会员 " .. m:sub(-4)) or "未登录")
    pcall(sum_mem.set_color, sum_mem, W.c((m ~= "") and "text" or "text_sub"))
  end
  if bal_num then bal_num.set(tostring(ST.S.bal), true) end
end

return M
