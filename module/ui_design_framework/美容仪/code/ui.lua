--[[
  ui.lua  页面编排：建控件 + 把状态变化分发给各段
  单向依赖：ui → ui_* / ui_widget / app_state；反向不成立。

  刷新策略（P5）：只在值真的变了才下发。
    - 倒计时：秒变化时更新（1Hz）
    - 托片提示：只在 运行/暂停/切模式 时更新，不含剩余时间（剩余在卡3）
    - 时钟：10s 一次
]]

local cfg = require "app_config"
local W = require "ui_widget"
local ST = require "app_state"
local topbar = require "ui_topbar"
local overview = require "ui_overview"
local carousel = require "ui_carousel"
local tray = require "ui_tray"

local M = {}

local page, top, ov, car, tr
local last_sec, last_run = -1, false

local function hint_text()
  local m = ST.cur()
  if ST.S.run then
    return "护理中 · " .. m.n .. " · " .. ST.S.lv .. " 档"
  end
  if ST.S.left < ST.S.total and ST.S.left > 0 then
    return "已暂停 · " .. m.n .. " · 剩余 " .. ST.fmt(ST.S.left)
  end
  return m.d .. " · 每周 2–3 次，避开破损肌肤"
end

local function sync_time(force)
  local s = ST.S.left
  if not force and s == last_sec then return end
  last_sec = s
  ov.set_time(ST.fmt(s))
  -- 总时长在 S 表里（ST.total 不存在，取 nil 会直接崩在除法）
  local total = ST.S.total
  if type(total) ~= "number" or total < 1 then total = 1 end
  local k = 1 - s / total
  if k < 0 then k = 0 elseif k > 1 then k = 1 end
  ov.set_prog(k)
end

local function sync_all()
  ov.set_mode(ST.cur(), ST.S.i, ST.N)
  ov.set_lv(ST.S.lv)
  car.render(ST.S.i)
  sync_time(true)
  tr.set_hint(hint_text())
  tr.set_run(ST.S.run)
  last_run = ST.S.run
end

-- 切模式：换图 + 微缩过场 + 三卡同步
local function shift(dir)
  if not ST.pick(ST.S.i + dir) then return end
  car.render(ST.S.i)
  car.animate()
  ov.set_mode(ST.cur(), ST.S.i, ST.N)   -- pick 已把档位套成该模式默认值
  ov.set_lv(ST.S.lv)
  sync_time(true)
  tr.set_hint(hint_text())
  tr.set_run(ST.S.run)        -- pick 会把运行态复位
  last_run = ST.S.run
end

--- 换主题：只改色板 + 重涂，控件一个都不重建
--  顺序是死的，颠倒会出问题：
--    use_theme 覆盖 C 并重建映射表 → repaint 按映射刷所有登记控件
--    → carousel.apply_theme 把显隐态（遮边条/垫层/缩放）再摆正
--    → render 让页码点与长条按新色落位 → 顶栏文案回写
--  apply_theme 必须在 repaint 之后：repaint 会用登记里的 opa 回填颜色，
--  先摆显隐的话会被刷回创建时的全透明，暗色下就是「相框不见了」。
local function apply_theme(name)
  local prev = cfg.theme
  if prev == name then return end
  if not cfg.use_theme(name) then return end

  local n = W.repaint()
  if n == 0 then
    -- 登记表为空说明控件没走 ui_widget（不该发生）。此时宁可回滚也不重建：
    -- 重建会丢模式/档位/倒计时，且旧的 LVGL 对象没有销毁路径。
    cfg.use_theme(prev)
    W.repaint()
    log.error("theme", "重涂 0 条，已回滚到", prev)
    return
  end

  -- 后两步各自兜底：任一步抛错都不该让界面停在「色板换了、相框没换」的半截状态，
  -- 也不该把顶栏按钮文案卡在旧主题上（那样用户会以为没切成功而反复点）
  local ok1, err1 = pcall(car.apply_theme)
  if not ok1 then log.error("theme", "展示窗重排失败", err1) end
  local ok2, err2 = pcall(car.render, ST.S.i)
  if not ok2 then log.error("theme", "轮播重排失败", err2) end

  top.set_theme(name)
  log.info("theme", name, n, "条")
end

function M.build()
  -- page 必须走 W.box 才进登记表：裸调 airui.container 的话，
  -- 换主题时页面底色不会跟着变，暗色主题下会露出一整块米白
  page = W.box(nil, 0, 0, cfg.HW.screen.w, cfg.HW.screen.h,
    { color = "bg", tag = "page" })

  top = topbar.build(page, function() apply_theme(cfg.other(cfg.theme)) end)
  ov = overview.build(page, function(v)
    if ST.set_lv(v) then
      ov.set_lv(ST.S.lv)
      tr.set_hint(hint_text())
    end
  end)
  car = carousel.build(page, shift)
  tr = tray.build(page, function()
    ST.toggle()
    tr.set_run(ST.S.run)
    tr.set_hint(hint_text())
    last_run = ST.S.run
  end)

  sync_all()
  return page
end

-- 每帧：dt 是名义帧长（秒），elapsed_ms 是真实累计毫秒
-- 倒计时必须按真实经过时间走：固定 33ms 累加会在节拍补偿生效后
-- 每帧多算/少算 1–2ms，15 分钟能偏出二三十秒。
local last_ms
function M.tick(dt, elapsed_ms)
  local d = dt
  if last_ms and elapsed_ms > last_ms then
    d = (elapsed_ms - last_ms) / 1000
  end
  last_ms = elapsed_ms
  if ST.tick(d) then
    sync_time(false)
    if not ST.S.run and last_run then          -- 倒计时归零自动结束
      last_run = false
      tr.set_run(false)
      tr.set_hint(hint_text())
    end
  end
  top.tick(elapsed_ms)
end

--- 主动切换主题（顶栏按钮已内置回调，这里留给调试/外部调用）
function M.set_theme(name) apply_theme(name) end

--- 当前主题名
function M.theme() return cfg.theme end

function M.page() return page end

return M
