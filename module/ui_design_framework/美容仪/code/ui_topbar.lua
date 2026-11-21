--[[
  ui_topbar.lua  顶栏 0..64：品牌 / 主题切换 / 电量 / 时钟
  纯静态 + 两个等宽数字块（时钟每分钟变一次，电量偶尔变 → F5 要等宽）

  右侧三件自右向左排布（右边界 1024-48=976，件间距 16）：
    时钟   923..976  宽 53（num_w("99:99",18) 实算，写死 11*4+5 会短 4px）
    电量   819..907  宽 88
    主题   731..803  宽 72

  改版前电量胶囊写死 bx=888..976，和时钟 923..976 压在了一起，
  时钟的「:00」直接盖在胶囊右端上。这轮按三件宽度实算重排，不留重叠。
]]

local cfg = require "app_config"
local W = require "ui_widget"

local L = cfg.LAYOUT
local M = {}

-- 没有 RTC / 未对时时 os.date 可能返回 nil：取不到就显示 00:00，
-- 绝不让格式化崩在开机路径上
local function clock_text()
  local ok, t = pcall(os.date, "*t")
  if not ok or type(t) ~= "table" then return "00:00" end
  return string.format("%02d:%02d", t.hour or 0, t.min or 0)
end

-- on_theme 是点击切换主题的回调，由 ui.lua 注入，避免 topbar 反向依赖 ui
function M.build(page, on_theme)
  local pad = L.pad

  -- 品牌 mark：描边圆 + 实心小点（无字形依赖）
  -- 用 glow 令牌：日间是墨青，夜间是 #4C8DFF（细线在深底才够亮）
  W.shape(page, pad, 21, 22, 22, {
    { type = "circle", cx = 11, cy = 11, r = 9, color = "glow", width = 2 },
    { type = "circle", cx = 11, cy = 11, r = 3, color = "glow", width = 1,
      fill = true, fill_color = "glow" },
  })

  W.text_mid(page, pad + 32, 0, 72, L.top_h, {
    text = "LUMA", size = 18, color = "ink", tag = "brand" })

  W.bar(page, pad + 112, 24, 1, 16, "line2")

  W.text_mid(page, pad + 124, 0, 44, L.top_h, {
    text = "光弧", size = 16, color = "ink3", tag = "brandcn" })

  -- ---------- 主题切换按钮 72x28 ----------
  -- 先摆可见件，热区最后盖在 page 上 —— 与托盘主按钮、轮播箭头同一范式。
  -- LVGL9 的 container 默认带 LV_OBJ_FLAG_CLICKABLE，先建热区再往里塞底板，
  -- 底板会在上层把 press 截走，热区永远收不到（这就是真机上点不动的原因）。
  local th = W.box(page, L.theme_x, L.theme_y, L.theme_w, L.theme_h,
    { color = "card", bw = 1, border = "line2", radius = 14, tag = "themebg" })
  -- 文字用 fill 令牌：明示「这是个可操作的主色元素」
  -- 父容器 bw=1 → 内容区 70x26，坐标直接从内容区原点起算，避免 fit 收敛告警
  local ttxt = W.text_mid(th, 1, 1, L.theme_w - 2, L.theme_h - 2, {
    text = cfg.THEME_NAME[cfg.theme], size = 16, color = "fill",
    align = airui.TEXT_ALIGN_CENTER, tag = "themetx" })
  W.press(page, L.theme_x, L.theme_y, L.theme_w, L.theme_h, function()
    log.info("theme", "按钮点击", cfg.theme)
    if on_theme then on_theme() end
  end, 14, "themehit")
  -- 开机打一次几何：点不动时先用这条确认按钮确实建在预期位置
  log.info("topbar", "主题按钮", L.theme_x, L.theme_y, L.theme_w, L.theme_h)

  -- ---------- 电量胶囊 88x28（内容区 86x26） ----------
  -- 排版：竖条 14..17 ｜ 两位数字格 26..48 ｜ 百分号 48..61
  local cap = W.box(page, L.batt_x, L.batt_y, L.batt_w, L.batt_h,
    { color = "card", bw = 1, border = "line2", radius = 14, tag = "battcap" })
  -- 左端竖条表示「有电」
  W.bar(cap, 14, 8, 3, 12, "glow")
  -- 数字只做两位等宽格；'%' 必须单独给一个够宽的居中 label：
  -- num 的窄格宽 = size*0.30 = 5px，16 号 '%' 字形约 9px，居中绘制会向两侧各溢出 2px，
  -- 压到前一位数字上 —— 这就是「电量和百分号重叠」的根因，挪坐标治不了，只能换宽格。
  local batt = W.num(cap, 26, 4, "99", 16, "ink2")
  batt.set("78")   -- 本工程未接电量 ADC，接上后调 set_batt(0..99)
  W.text_mid(cap, 48, 4, 13, 19, {
    text = "%", size = 16, color = "ink2",
    align = airui.TEXT_ALIGN_CENTER, tag = "battpct" })

  -- ---------- 时钟 ----------
  local clock = W.num(page, 1024 - pad - W.num_w("99:99", 18), L.clock_y,
    "99:99", 18, "ink")
  clock.set(clock_text())

  -- 顶栏底线：line 只做分隔（F6）
  W.bar(page, pad, L.top_h, L.content_w, 1, "line")

  -- 时钟按 clk_ms 节流：主循环 elapsed 是 33ms 的倍数，
  -- 用 t % 1000 == 0 永远命中不了（lcm(33,1000)=33000ms 才凑上一次）
  local last = 0
  return {
    clock = clock,
    batt = batt,
    set_batt = function(v)
      -- 胶囊只有两位数字格，100 塞不下，钳到 99
      v = math.max(0, math.min(99, math.floor(v + 0.5)))
      batt.set(tostring(v))
    end,
    --- 主题切换后回写按钮文案（按钮显示的是「当前主题」）
    set_theme = function(name)
      ttxt:set_text(cfg.THEME_NAME[name] or "")
    end,
    tick = function(t)
      if t - last < cfg.ANIM.clk_ms then return end
      last = t
      clock.set(clock_text())
    end,
  }
end

return M
