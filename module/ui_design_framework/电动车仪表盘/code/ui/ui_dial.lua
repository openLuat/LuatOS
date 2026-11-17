--[[
  ui_dial.lua  主视觉车速表盘

  图层（自下而上）：
    雾光层  随档位变色的柔光 + 外发丝                            （切档才重绘，表盘面已透明）
    静态层  8 段渐变轨道 + 33 根刻度                             （一次铺好，只在重建时生成）
    数字层  0/20/.../160 刻度数字                                （静态 label）
    进度层  高亮进度弧 + 末端亮点                                （8Hz 重绘）
    指针层  指针 + 指针尾 + 末端亮点                             （20Hz 重绘）
    轴心层  轴盖                                                （静态）
    文字层  BRAND / 数字车速 / KM/H / ODO                       （变更时才 set_text）

  性能约定：每个 shape 都只占自己的包围盒（不再用 1024x600 整屏），
  set_items 会让对象整块失效，外框越大每帧重画越贵。
]]

local cfg  = require "app_config"
local sim  = require "app_sim"
local util = require "app_util"
local T    = require "ui_theme"
local W    = require "ui_widget"

local C   = T.C
local L   = cfg.LAYOUT
local SZ  = T.SIZES

local M = {}

local MAX   = cfg.MAX_SPEED
local START = cfg.START_ANG
local SWEEP = cfg.SWEEP_ANG
local PI    = math.pi

local CX, CY = L.dial_cx, L.dial_cy

-- 静态层外框：408x408 @ (308, 86) → 308+408=716 / 86+408=494
local SB  = L.static_box
local SOX, SOY = CX - SB / 2, CY - SB / 2
local SC  = SB / 2                          -- 静态层局部中心 204

-- 动态层外框：412x412 @ (306, 84) → 306+412=718 / 84+412=496
local DB  = L.dyn_box
local DOX, DOY = CX - DB / 2, CY - DB / 2
local DC  = DB / 2                          -- 动态层局部中心 206

local R = {}                                -- 本组件控件引用

local RING_SEG = SWEEP / 8

-- ==================== 几何工具 ====================
-- 以局部圆心为基准的极坐标取整（C 层 lua_tointeger 会把小数读成 0，必须取整）
local function polar(cx, cy, r, deg)
  local rad = deg * PI / 180
  return math.floor(cx + r * math.cos(rad) + 0.5),
         math.floor(cy + r * math.sin(rad) + 0.5)
end

local function angle_of(spd)
  if spd < 0 then spd = 0 elseif spd > MAX then spd = MAX end
  return START + SWEEP * (spd / MAX)
end

local function accent()
  return T.accent(sim.mode)
end

-- ==================== 静态层 ====================
-- 雾光层：只有 2 个 item，切档时单独重绘（原表盘面 face_r 的实心圆已删除，改透明）
local function build_glow()
  local gc = cfg.mode_glow(sim.mode)
  return {
    { type = "circle", cx = SC, cy = SC, r = L.glow_r,
      fill = true, fill_color = gc, fill_opacity = C.glowOpa, color = gc, opacity = 0 },
    -- 外发丝：给雾光一圈边界，避免"糊"在黑底上
    { type = "circle", cx = SC, cy = SC, r = L.glow_r,
      width = 1, color = C.ringEdge, opacity = 77 },
  }
end

-- 切档时调用：雾光颜色跟着档位色走（ECO 青 / NORMAL 紫 / SPORT 品红）
function M.set_mode()
  W.si(R.glow, sim.mode, build_glow)
end

local function build_static(parent)
  local items = {}

  R.glow = W.shape(parent, SOX, SOY, SB, SB, build_glow())

  -- 渐变轨道：8 段暗态弧，进度弧会盖在上面
  local cols = { C.ringD1, C.ringD2, C.ringD3, C.ringD2,
                 C.ringD1, C.ringD2, C.ringD3, C.ringD2 }
  for i = 1, #cols do
    local a0 = math.floor(START + RING_SEG * (i - 1) - 0.6 + 0.5)
    local a1 = math.floor(START + RING_SEG * i + 0.6 + 0.5)
    items[#items + 1] = { type = "arc", cx = SC, cy = SC, r = L.ring_r,
      start_angle = a0, end_angle = a1, width = L.ring_w, color = cols[i],
      rounded = true }
  end

  -- 刻度：0..32 共 33 根（主 4 根一组，对齐 0/20/.../160 共 9 个数字）
  for i = 0, 32 do
    local t = i / 32
    local deg = START + SWEEP * t
    local major = (i % 4 == 0)
    local mid = (i % 2 == 0)
    local r_in = major and L.tick_in_major or (mid and L.tick_in_mid or L.tick_in_minor)
    local wd = major and 3 or (mid and 2 or 1)
    local col = major and C.tickMajor or (mid and C.tickMid or C.tickMinor)
    local x1, y1 = polar(SC, SC, L.tick_out, deg)
    local x2, y2 = polar(SC, SC, r_in, deg)
    items[#items + 1] = { type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
      width = wd, color = col, round_end = true }
  end

  R.dial = W.shape(parent, SOX, SOY, SB, SB, items)
end

-- ==================== 刻度数字 ====================
local function build_numbers(parent)
  R.nums = {}
  for i = 0, 32, 4 do
    local t = i / 32
    local deg = START + SWEEP * t
    local nx, ny = polar(CX, CY, L.num_r, deg)
    R.nums[#R.nums + 1] = W.label(parent, nx - 20, ny - 11, 40, 22,
      tostring(math.floor(MAX * t + 0.5)), SZ.label, C.tickText,
      airui.TEXT_ALIGN_CENTER)
  end
end

-- ==================== 进度弧 ====================
function M.render_progress()
  local end_deg = angle_of(sim.speed)
  local end_i = math.floor(end_deg + 0.5)
  local ratio = sim.speed / MAX
  local col = accent()
  -- key 里带上模式：换模式时即使车速没变也要换色重绘
  W.si(R.prog, end_i * 4 + sim.mode, function()
    local items = {}
    if end_i - START >= 1 then
      items[#items + 1] = { type = "arc", cx = DC, cy = DC, r = L.ring_r,
        start_angle = START, end_angle = end_i, width = L.ring_w,
        color = col, rounded = true }
    end
    -- 超过 86% 叠一段红弧提示（超速区）
    if ratio > 0.86 and end_i - START >= 1 then
      local hi = math.floor(START + SWEEP * 0.86 + 0.5)
      if end_i > hi then
        items[#items + 1] = { type = "arc", cx = DC, cy = DC, r = L.ring_r,
          start_angle = hi, end_angle = end_i, width = L.ring_w,
          color = C.red, rounded = true }
      end
    end
    -- 末端游标点已删：它落在弧头正上方、4px 圆被 ring_w 宽的圆头弧完全盖住，
    -- 肉眼零差别，但每 200ms 要跟着整块 412x412 重绘一次，还多一个 items 分配。
    return items
  end)
end

-- ==================== 指针 ====================
function M.render_needle()
  local end_i = math.floor(angle_of(sim.speed) + 0.5)
  local rad = end_i * PI / 180
  local cs, sn = math.cos(rad), math.sin(rad)
  local tx = math.floor(DC + L.needle_len * cs + 0.5)
  local ty = math.floor(DC + L.needle_len * sn + 0.5)
  local bx = math.floor(DC - L.needle_tail * cs + 0.5)
  local by = math.floor(DC - L.needle_tail * sn + 0.5)
  W.si(R.needle, end_i, function()
    return {
      -- 指针柔光已删：那条 10px 低透明线是给 CSS drop-shadow 凑的替代品，
      -- 真机上被 4px 主体完全盖住，只在两端露一点毛边，却要多画一次粗线。
      -- 指针主体
      { type = "line", x1 = DC, y1 = DC, x2 = tx, y2 = ty,
        width = 4, color = C.needle, round_start = true, round_end = true },
      -- 指针尾
      { type = "line", x1 = DC, y1 = DC, x2 = bx, y2 = by,
        width = 4, color = C.needleTail, round_start = true, round_end = true },
      -- 尖端亮点
      { type = "circle", cx = tx, cy = ty, r = 4,
        fill = true, fill_color = C.needleTip, color = C.needleTip, opacity = 0 },
    }
  end)
end

-- ==================== 文字层 ====================
local function build_text(parent)
  R.brand = W.label(parent, CX - 150, L.brand_y, 300, 22,
    util.sp("CHRONO"), SZ.micro, C.brand, airui.TEXT_ALIGN_CENTER)

  R.speed = W.label(parent, CX - 150, L.hero_y, 300, L.hero_h,
    "0", SZ.hero, C.text, airui.TEXT_ALIGN_CENTER)

  R.unit = W.label(parent, CX - 150, L.unit_y, 300, 22,
    "KM/H", SZ.label, C.unit, airui.TEXT_ALIGN_CENTER)

  R.odo = W.label(parent, CX - 150, L.odo_y, 300, 19,
    "ODO 12860 KM", SZ.micro, C.textMute, airui.TEXT_ALIGN_CENTER)
end

-- ==================== 构建 ====================
-- 刷新/动画游标：必须声明在 M.build 之前，并且每次 build 都归位。
-- 主题切换会整盘重建，控件是新的、游标还是旧的，「值没变」的分支全短路，
-- 速度 / 里程就停在 build 时的占位值上，直到数值自己变一次才恢复。
local acc_need, acc_prog = 0, 0
local last_speed, last_odo = -1, -1

function M.build(parent)
  acc_need, acc_prog = 0, 0
  last_speed, last_odo = -1, -1
  build_static(parent)
  build_numbers(parent)

  R.prog = W.shape(parent, DOX, DOY, DB, DB, {})
  R.needle = W.shape(parent, DOX, DOY, DB, DB, {})

  -- 轴心（盖住指针根部）
  local hs = L.hub_r * 2 + 22                  -- 44
  R.hub = W.shape(parent, CX - hs / 2, CY - hs / 2, hs, hs, {
    { type = "circle", cx = hs / 2, cy = hs / 2, r = L.hub_r - 1,
      fill = true, fill_color = C.hub, color = C.hub, opacity = 0 },
    { type = "circle", cx = hs / 2, cy = hs / 2, r = L.hub_r + 3,
      width = 1, color = C.hubRim, opacity = 120 },
    { type = "circle", cx = hs / 2, cy = hs / 2, r = 5,
      fill = true, fill_color = C.hubDot, color = C.hubDot, opacity = 0 },
    { type = "circle", cx = hs / 2 - 3, cy = hs / 2 - 3, r = 2,
      fill = true, fill_color = C.needleTip, color = C.needleTip, opacity = 90 },
  })

  build_text(parent)

  M.render_progress()
  M.render_needle()
end

-- ==================== 每帧 ====================
function M.render(dt)
  -- 数字层：先比数值，只有真的变了才 tostring / 拼串。
  -- W.st 内部会短路（内容相同不 set_text），但参数是「先算出来再传进去」——
  -- 每帧 tostring 一次、每帧拼一次 "ODO .. KM"，30fps 就是每秒 60 个临时字符串，
  -- 这些垃圾进 GC 会把帧时间打出一两个尖峰，观感就是「偶尔顿一下」。
  local sp = math.floor(sim.speed + 0.5)
  if sp ~= last_speed then
    last_speed = sp
    W.st(R.speed, tostring(sp))
  end
  local od = math.floor(sim.odo)
  if od ~= last_odo then
    last_odo = od
    W.st(R.odo, "ODO " .. util.fmt(sim.odo) .. " KM")
  end

  -- 累加器减去阈值而不是清 0：清 0 会把周期量化成整帧，dt 抖动时还会在
  -- N 帧 / N+1 帧之间跳，指针和弧各自跳自己的，看上去就"一个快一个慢"。
  acc_need = acc_need + dt
  if acc_need >= cfg.ANIM.need_ms / 1000 then
    acc_need = acc_need - cfg.ANIM.need_ms / 1000
    M.render_needle()
  end

  acc_prog = acc_prog + dt
  if acc_prog >= cfg.ANIM.prog_ms / 1000 then
    acc_prog = acc_prog - cfg.ANIM.prog_ms / 1000
    M.render_progress()
  end
end

return M
