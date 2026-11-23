--[[
  app_state.lua  业务状态：会员号 / 档位 / 余额 / 支付三态 / 主题

  只存数据与规则，不碰任何控件（单向依赖：ui → app_state）。
  所有「改值」都走这里的函数，UI 侧靠调用方回调同步，不做全量轮询。
]]

local cfg = require "app_config"

local M = {}

-- ======================= 档位 =======================
-- per 是单位币价文案，局数按「每局约 12 币」估算（演示值）
M.TIERS = {
  { id = "t100",  coins = 100,  price = 10,  gift = 0,   per = "0.10 元/币" },
  { id = "t300",  coins = 300,  price = 30,  gift = 20,  per = "0.09 元/币" },
  { id = "t500",  coins = 500,  price = 50,  gift = 50,  per = "0.09 元/币" },
  { id = "t1000", coins = 1000, price = 100, gift = 130, per = "0.08 元/币" },
  { id = "t2000", coins = 2000, price = 200, gift = 300, per = "0.08 元/币" },
  { id = "tcus",  coins = 0,    price = 0,   gift = 0,   per = "10 币/元", custom = true },
}

M.TIER_MAX = 6
M.CODE_LEN = 11          -- 会员号 4~11 位
M.PAY_SEC = 120          -- 二维码有效期（秒）
M.SCAN_SEC = 60          -- 扫码等待上限（秒）
M.SUCC_SEC = 10          -- 成功页自动回首页（秒）

M.S = {
  page    = "login",     -- login / scan / tier / pay / success / kb
  code    = "",          -- 已输入会员号
  member  = "",          -- 已登录会员号（空 = 未登录）
  tier    = nil,         -- 当前档位索引
  cusYuan = 0,           -- 自定义档：输入金额（元）
  bal     = 0,           -- 账户余额（币）
  payMth  = "wx",        -- wx / ali
  paySt   = "wait",      -- wait / ok / fail / expired
  left    = 0,           -- 支付剩余秒
  scanLeft = 0,          -- 扫码剩余秒
  succLeft = 10,         -- 成功页剩余秒
  theme   = "dark",
}

local KEY_THEME = "arcade.theme"
local KEY_BAL   = "arcade.bal"
local KEY_MEM   = "arcade.mem"

local function kv_get(k)
  if not (fskv and fskv.get) then return nil end
  local ok, v = pcall(fskv.get, k)
  if ok then return v end
  return nil
end

local function kv_set(k, v)
  if not (fskv and fskv.set) then return end
  pcall(fskv.set, k, v)
end

function M.init()
  local t = kv_get(KEY_THEME)
  if t == "light" or t == "dark" then M.S.theme = t end
  local b = tonumber(kv_get(KEY_BAL))
  if b and b >= 0 then M.S.bal = math.floor(b) end
end

-- ======================= 会员号输入 =======================
function M.code_push(ch)
  if #M.S.code >= M.CODE_LEN then return false end
  if not ch:match("%d") then return false end
  M.S.code = M.S.code .. ch
  return true
end

function M.code_pop()
  if #M.S.code == 0 then return false end
  M.S.code = M.S.code:sub(1, -2)
  return true
end

function M.code_clear()
  M.S.code = ""
end

function M.code_ok()
  local n = #M.S.code
  if n < 4 then return false, "会员号至少 4 位" end
  M.S.member = M.S.code
  kv_set(KEY_MEM, M.S.member)
  return true
end

function M.logout()
  M.S.member = ""
  M.S.code = ""
end

-- ======================= 档位 / 金额 =======================
-- 自定义档按 10 币 / 元折算，最低 10 元
function M.info(i)
  i = i or M.S.tier
  if not i then return { coins = 0, gift = 0, pay = 0, per = "", label = "—" } end
  local t = M.TIERS[i]
  if not t then return { coins = 0, gift = 0, pay = 0, per = "", label = "—" } end
  if t.custom then
    local yuan = M.S.cusYuan
    return {
      coins = math.floor(yuan * 10), gift = 0, pay = yuan,
      per = "10 币/元", label = "自定义", custom = true,
    }
  end
  return { coins = t.coins, gift = t.gift, pay = t.price, per = t.per,
           label = t.coins .. " 币档" }
end

function M.tier_coins(i)          -- 卡片上「到账 X 币」
  local t = M.TIERS[i]
  if not t then return 0 end
  if t.custom then return math.floor(M.S.cusYuan * 10) end
  return t.coins
end

function M.tier_plays(i)          -- 「可玩约 N 局」：按每局 12 币
  local t = M.TIERS[i]
  if not t then return 0 end
  local c = M.tier_coins(i) + (t.gift or 0)
  return math.max(1, math.floor(c / 12 + 0.5))
end

function M.pick(i)
  if i < 1 or i > M.TIER_MAX then return false end
  M.S.tier = i
  if M.TIERS[i].custom and M.S.cusYuan < 10 then M.S.cusYuan = 10 end
  return true
end

function M.set_cus(yuan)
  if yuan < 10 then yuan = 10 end
  if yuan > 500 then yuan = 500 end
  M.S.cusYuan = math.floor(yuan * 100 + 0.5) / 100
end

-- ======================= 支付 =======================
function M.pay_begin()
  M.S.paySt = "wait"
  M.S.left = M.PAY_SEC
end

function M.pay_done(ok)
  local info = M.info()
  if ok then
    M.S.paySt = "ok"
    M.S.bal = M.S.bal + info.coins + info.gift
    kv_set(KEY_BAL, M.S.bal)
  else
    M.S.paySt = "fail"
  end
  M.S.left = 0
end

function M.pay_switch(mth)
  M.S.payMth = mth
end

-- ======================= 扫码登录 =======================
function M.scan_begin()
  M.S.scanLeft = M.SCAN_SEC
end

-- 硬件扫码回调只回一串码；校验规则必须与键盘登录一致，否则两条路径会分叉
function M.scan_ok(code)
  code = tostring(code or "")
  if #code < 4 or #code > M.CODE_LEN then return false end
  M.S.code = code
  M.S.member = code
  kv_set(KEY_MEM, code)
  M.S.scanLeft = 0
  return true
end

-- 返回 true 表示「显示用的整秒数变了」，调用方据此决定是否下发
function M.tick_scan(dt)
  if M.S.page ~= "scan" then return false end
  local before = math.ceil(M.S.scanLeft)
  M.S.scanLeft = M.S.scanLeft - dt
  if M.S.scanLeft <= 0 then
    M.S.scanLeft = 0
    return true
  end
  return math.ceil(M.S.scanLeft) ~= before
end

-- ======================= 支付成功 =======================
function M.succ_begin()
  M.S.succLeft = M.SUCC_SEC
end

-- 返回 true 表示倒计时归零，调用方负责回首页
function M.tick_succ(dt)
  if M.S.page ~= "success" then return false end
  local before = math.ceil(M.S.succLeft)
  M.S.succLeft = M.S.succLeft - dt
  if M.S.succLeft <= 0 then
    M.S.succLeft = 0
    return true
  end
  return math.ceil(M.S.succLeft) ~= before
end

-- 倒计时：按真实经过秒推进；返回 true 表示「秒数变了」
function M.tick_pay(dt)
  if M.S.page ~= "pay" or M.S.paySt ~= "wait" then return false end
  local before = math.ceil(M.S.left)
  M.S.left = M.S.left - dt
  if M.S.left <= 0 then
    M.S.left = 0
    M.S.paySt = "expired"
    return true
  end
  return math.ceil(M.S.left) ~= before
end

-- ======================= 主题 =======================
function M.set_theme(t)
  M.S.theme = (t == "light") and "light" or "dark"
  kv_set(KEY_THEME, M.S.theme)
  return M.S.theme
end

-- 金额格式化：恒定两位小数。
-- 不能「整数就不带小数」：金额走 W.num 等宽格，值是 "30" 时小数点位的窄格还在，
-- 于是显示成 "30." 后面拖一片空格；而且位数一变整块金额会横向跳（F5）。
function M.money(v)
  v = tonumber(v) or 0
  return string.format("%.2f", v)
end

-- 倒计时文本 mm:ss
function M.clock_text(sec)
  if sec < 0 then sec = 0 end
  return string.format("%02d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

return M
