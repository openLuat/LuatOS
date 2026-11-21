--[[
  ui.lua  界面编排（唯一知道「页面之间怎么走」的地方）

  分层：main（节拍）→ ui（编排）→ ui_*（页面）→ ui_widget（原语）→ airui
  页面模块之间不互相 require：跳转全部回到这里，靠 on_xxx 回调向外抛。

  显隐只做 set_pos 把 root 停到屏外左侧（G6：只许停左/上侧，停右侧会撑大滚动区）。

  页面顺序（ORDER）：login → scan → tier → pay → success，kb 是 login 的输入态。
]]

local cfg   = require "app_config"
local ST    = require "app_state"
local W     = require "ui_widget"
local TH    = require "ui_theme"
local TOP   = require "ui_topbar"
local LOGIN = require "ui_login"
local SCAN  = require "ui_scan"
local TIER  = require "ui_tier"
local PAY   = require "ui_pay"
local SUCC  = require "ui_success"
local KB    = require "ui_kb"
local TOAST = require "ui_toast"

local M = {}

local page                      -- 全屏页容器（承载背景装饰）
local acc_1s = 0                -- 时钟节流：1Hz

local PAGES = { login = LOGIN, scan = SCAN, tier = TIER, pay = PAY, success = SUCC, kb = KB }
local ORDER = { "login", "scan", "tier", "pay", "success", "kb" }

-- ==================== 背景装饰 ====================
-- 静态一次构建，运行期永不下发（P1）。全部低 opa，不影响文字对比度。
local function build_deco()
  -- 页面内容区 = 1024×600（page 无描边）。装饰块同样受内容区约束，
  -- 右/下缘一律停在 1023 / 599，贴边会被 LVGL 判成溢出 → 主屏出滚动条。
  -- 暖金大圆盘 400×400：右缘 1024、下缘 400
  -- skin 必须给令牌名：不带 skin 的容器只记得创建时的字面色，切主题不会跟着走
  W.box(page, 623, 0, 400, 400, { color = W.c("disc"), opa_tok = "disc",
                                  skin = "disc", radius = 200, tag = "deco_disc" })
  -- 冷灰小圆盘 160×160：右缘 1024、下缘 560
  W.box(page, 863, 400, 160, 160, { color = W.c("hl"), opa = 40,
                                    skin = "hl", radius = 80, tag = "deco_glow" })
  -- 左侧五条竖细线：x = 0/16/32/48/64，1px 宽
  for i = 0, 4 do
    W.bar(page, i * 16, 0, 1, cfg.HW.screen.h - 1, "vline", W.a("vline"))
  end
  -- 上下压边金线
  W.bar(page, 0, 0, cfg.HW.screen.w - 1, 1, "edgeline", W.a("edgeline"))
  W.bar(page, 0, cfg.HW.screen.h - 2, cfg.HW.screen.w - 1, 1, "edgeline", 43)
end

-- ==================== 构建 ====================
function M.build()
  ST.init()
  TH.init()                                   -- 落盘主题先落地，后续建控件取色才正确

  W.group("root")
  -- skin = "bg"：整屏底色是切主题时必须变的那个色。不登记令牌，亮色主题下背景
  -- 仍是深色，卡片上的深墨绿字直接消失
  page = W.box(nil, 0, 0, cfg.HW.screen.w, cfg.HW.screen.h,
               { color = W.c("bg"), skin = "bg", bw = 0, tag = "bg" })
  build_deco()

  LOGIN.build()
  SCAN.build()
  TIER.build()
  PAY.build()
  SUCC.build()
  KB.build()

  TOAST.build()
  TOP.build()                                 -- 必须最后：LVGL 按创建顺序压层

  M.bind()
  TH.on_apply = function() M.sync_all() end
  TH.on_rebuild = function()
    -- repaint 全挂 = 固件 set_color 不可用。重建同样依赖 set_color，做了也白做，
    -- 这里只报出来，保留可读的旧界面而不是黑屏。
    log.error("ui", "固件 set_color 全部失败，主题无法切换")
    TOAST.show("设备显示异常，请重启", "warn")
  end

  M.refresh_top()
  M.go("login", true)
end

-- ==================== 回调绑定 ====================
function M.bind()
  -- 登录
  LOGIN.on_field = function() M.go("kb") end
  LOGIN.on_ok = function()
    if ST.S.member ~= "" then M.go("tier") else M.go("kb") end
  end
  LOGIN.on_scan = function() M.go("scan") end

  -- 扫码登录：硬件回调只回码串，这里用固定码模拟
  SCAN.on_ok = function()
    if not ST.scan_ok("13800001234") then
      SCAN.set_state("warn", "码无效，请重试", ST.S.scanLeft)
      return
    end
    SCAN.set_state("ok", "已识别 · 会员 1234", 0)
    -- 0.5s 成功态：真机识码也有延迟，直接跳会让人以为没扫上
    sys.timerStart(function()
      M.refresh_top()
      TIER.sync()
      M.go("tier")
    end, 500)
  end
  SCAN.on_cancel = function()
    LOGIN.hint("已取消扫码，可输入会员号或重试", "warn")
    M.go("login")
  end

  -- 档位
  TIER.on_pick = function(i)
    ST.pick(i)
    TIER.sync()
  end
  TIER.on_pay = function()
    if not ST.S.tier then
      TOAST.show("请先选择档位", "warn")
      return
    end
    M.go("pay")                    -- enter("pay") 里已经 pay_begin，重复调会把倒计时重置成 120
    local info = ST.info()
    -- 真机：二维码内容由支付后端下发，这里用订单串占位
    PAY.set_qr(string.format("ARCADE|%s|%d|%s",
      (ST.S.member ~= "" and ST.S.member or "GUEST"), ST.S.tier, ST.money(info.pay)))
    PAY.set_state("wait")
    PAY.set_left(ST.S.left)
    PAY.sync()
  end

  -- 支付
  PAY.on_method = function(m)
    ST.pay_switch(m)
    PAY.sync()
  end
  PAY.on_back = function() M.go("tier") end
  PAY.on_paid = function()
    ST.pay_done(true)
    M.refresh_top()
    M.go("success")
    SUCC.set_left(ST.S.succLeft)
  end

  -- 成功
  SUCC.on_home = function() M.home() end
  SUCC.on_more = function()
    ST.S.tier = nil
    TIER.sync()
    M.go("tier")
  end

  -- 键盘
  KB.on_digit = function(d) ST.code_push(d); KB.sync() end
  KB.on_del   = function() ST.code_pop();  KB.sync() end
  KB.on_clear = function() ST.code_clear(); KB.sync() end
  KB.on_back  = function() M.go("login") end
  KB.on_ok = function()
    local ok, err = ST.code_ok()
    if not ok then
      KB.hint(err, "err")
      return
    end
    M.refresh_top()
    LOGIN.hint(nil)
    TIER.sync()
    KB.hint(nil)
    M.go("tier")
  end

  -- 主题
  TOP.on_theme = function()
    TH.toggle()          -- on_apply 里会 sync_all
  end
end

-- ==================== 页面切换 ====================
local function show_only(name)
  for i = 1, #ORDER do
    local n = ORDER[i]
    local p = PAGES[n]
    if p and p.show then p.show(n == name) end
  end
end

-- ==================== 切页过渡 ====================
-- 只做「新页面从左侧滑入」：位移全程 ≤ 0，右缘永远 ≤ 屏宽，不撑大主屏 scroll area（G6）。
-- 位移量与节拍都放配置里；过渡期间 main 会把巡检节拍提到 busy_ms，否则 50ms 只出 3 帧。
local TRANS = { on = false, t = 0, page = nil }
local SLIDE_PX = cfg.ANIM.slide_px
local SLIDE_MS = cfg.ANIM.slide_ms

-- 三次缓出：起步快、收尾软，20~60fps 下都不会看出「一下停住」
local function ease_out(p)
  local q = 1 - p
  return 1 - q * q * q
end

-- abort=true：过渡被新的切页打断，直接把这页收进隐藏位（否则会先闪一帧到 (0,0)）
local function trans_stop(abort)
  TRANS.on = false
  local p = TRANS.page and PAGES[TRANS.page]
  TRANS.page = nil
  if p and p.show then
    if abort then p.show(false) else p.show(0) end
  end
end

function M.busy()
  return TRANS.on
end

local function enter(name)
  if name == "scan" then
    ST.scan_begin()
    SCAN.sync()
  elseif name == "pay" then
    ST.pay_begin()
  elseif name == "success" then
    ST.succ_begin()
  end
end

function M.go(name, force)
  if not PAGES[name] then return end
  if name == ST.S.page and not force then return end
  local prev = ST.S.page
  -- 连点切页：先把上一段过渡收尾（收进隐藏位），避免两段动画同时改同一个页面
  if TRANS.on then trans_stop(true) end
  enter(name)
  ST.S.page = name
  show_only(name)
  M.refresh_top()
  -- 首次进入（prev 为空，开机构建）不做动画，直接显示
  if prev and prev ~= name and SLIDE_MS > 0 then
    TRANS.on, TRANS.t, TRANS.page = true, 0, name
    local p = PAGES[name]
    if p and p.show then p.show(-SLIDE_PX) end
  end
end

-- 回首页：清会员（公共设备不能把上一位的身份留给下一位）+ 复位订单态
function M.home()
  ST.logout()
  ST.S.tier = nil
  ST.S.paySt = "wait"
  ST.S.left = 0
  ST.pay_switch("wx")
  PAY.set_state("wait")
  PAY.set_left(0)
  LOGIN.sync()
  LOGIN.hint(nil)
  TIER.sync()
  M.refresh_top()
  M.go("login", true)
end

-- ==================== 同步 ====================
function M.refresh_top()
  TOP.set_member(ST.S.member)
  TOP.set_bal(ST.S.bal)
end

function M.sync_all()
  for i = 1, #ORDER do
    local p = PAGES[ORDER[i]]
    if p and p.sync then p.sync() end
  end
  TOP.sync_theme()
  M.refresh_top()
end

-- ==================== 节拍 ====================
-- main 每 50ms 调一次；这里只做「时间相关的下发」，界面静止时不产生任何重绘（P10）。
function M.tick(dt_ms)
  local dt = dt_ms or cfg.ANIM.frame_ms

  -- 切页过渡：位移必须每帧推进（P4 里最贵的那一档），所以放在业务节拍之前，
  -- 且只有取整后的 x 变了才下发（p.show 内部会判，位移不足 1px 时天然跳过）
  if TRANS.on then
    TRANS.t = TRANS.t + dt
    if TRANS.t >= SLIDE_MS then
      trans_stop()
    else
      local p = PAGES[TRANS.page]
      if p and p.show then
        local k = ease_out(TRANS.t / SLIDE_MS)
        p.show(-math.floor(SLIDE_PX * (1 - k) + 0.5))
      end
    end
  end

  acc_1s = acc_1s + dt / 1000
  if acc_1s >= 1 then
    acc_1s = acc_1s - 1
    TOP.set_clock()
  end

  local ds = dt / 1000
  local pg = ST.S.page

  if pg == "scan" then
    SCAN.tick(dt)
    if ST.tick_scan(ds) then
      if ST.S.scanLeft <= 0 then
        LOGIN.hint("扫码超时，请重试或输入会员号", "err")
        M.go("login")
      else
        SCAN.set_state("wait", "等待扫码", math.ceil(ST.S.scanLeft))
      end
    end

  elseif pg == "pay" then
    if ST.tick_pay(ds) then
      PAY.set_left(ST.S.left)
      if ST.S.paySt == "expired" then
        PAY.set_state("fail", "订单已超时 · 请返回重选")
      end
    end

  elseif pg == "success" then
    if ST.tick_succ(ds) then
      if ST.S.succLeft <= 0 then
        M.home()
      else
        SUCC.set_left(ST.S.succLeft)
      end
    end
  end
end

return M
