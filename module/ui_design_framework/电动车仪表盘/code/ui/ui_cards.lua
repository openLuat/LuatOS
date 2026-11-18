--[[
  ui_cards.lua  侧栏卡片组

  左列：指示灯 / 驾驶模式（三档胶囊，可点击）/ 本次骑行时长 → 64-216 / 228-380 / 392-484
  右列：指示灯 / 电量数字卡（只有一个 hero 数字）→ 64-216 / 228-484

  删卡记录：温度卡（v2 早期）、输出功率卡（2026-11-17）、电量段条 / 量程（2026-11-17）。
  续航副行删过又补回来了：删它是因为当初和段条 / 量程一起走 set_items 重建；
  而它本身只是改 label 文本（set_text），成本可以忽略，卡片空着反而浪费 256 的高度。

  所有卡片走 W.card（玻璃质感：半透明底 + 1px 预混描边 + 顶部高光线），
  内容区 230x150 / 230x90 / 230x254，子控件坐标全部按内容区核算，不留越界。
]]

local sim  = require "app_sim"
local util = require "app_util"
local T    = require "ui_theme"
local W    = require "ui_widget"

local C  = T.C
local L  = T.L
local SZ = T.SIZES

local M = {}

local R = {}

-- 刷新游标。必须声明在 M.build 之前，并且每次 build 都归位：
-- 主题切换会整卡重建，R 换了新控件，但游标还是旧值。
-- 那 M.render 里「值没变」的分支就全部短路，新控件停在 build 时的
-- 初始文本 / 初始色上——数字卡在占位的 "78"，电池 4 格停在灰色。
local last_charge = nil
local last_ride, last_pct, last_sub = -1, -1, nil

-- ==================== 电量卡（右列，228..484 = 256 高） ====================
-- 内容区 230x254。四层：标签 / hero 数字 + 「%」/ 发丝线 / 续航副行。
-- 原来内容全挤在 78..175，上下各空 78 / 79，卡看着是空的。现在均分：
-- 上留白 44、内容 44..210、下留白 44。
-- 成本：段条和量程仍然是删掉的（它们是 shape，得重建）；留下的是 label，
-- 续航 2.4s 才变一次，走 set_text，不碰 items 表。
-- 右侧 138..212 从「数字右边缘」到「卡内边距」一直是空的：数字只有 104 宽，
-- 剩下 86px 全白。压一块幽灵电池水印（描边外壳 + 4 格电池芯）在那儿。
-- 4 格按电量亮灭：竖排、自下而上，格数 = round(百分比 / 25)，非零至少 1 格
-- （1% 时显示空电池比显示一格更误导）。亮格按余量换色——≥50 绿 / ≥20 琥珀 /
-- 其余红——但压到 59% 透明度：60x18 的小色块，面积摆在这儿，压不压透明度
-- 都不会抢走 64px 的「78」。灭格是 4% 文字色，只是让轨道可见。
-- 纯灰白（上一版）技术上最"安全"，但一块中性色的电池在这张卡里跟谁都不搭；
-- 绿/琥珀/红才是电池该有的语言，低透明度已经足够让它待在水印层级。
-- 验算：标签 44+19=63、数值 76+67=143、「%」100+30=130 / 114+22=136、
-- 线 172+1=173、副行 188+22=210 ≤ 254；横向 14+202=216 ≤ 230；
-- 水印外壳 140+72=212 / 72+96=168、格 146+60=206 / 78+84=162、
-- 凸头 62+12=74 / 162+28=190，全部落在数值右侧的空档里。
local GHOST_N, GHOST_W, GHOST_H, GHOST_GAP = 4, 60, 18, 4
local GHOST_X, GHOST_Y = 146, 78

local function build_battery(parent, on_charge)
  local c = W.card(parent, L.right_x, L.batt_y, L.col_w, L.batt_h, 14, on_charge)
  -- 幽灵水印先建，让它压在文字下面（LVGL 按创建顺序叠放）
  -- 电池芯拆成 4 格：空心的电池图标读出来是「0%、没电」，必须能看出存量。
  -- 底色走真 alpha（容器底色支持 color_opacity，只有 border 不支持），
  -- 灭格 4% 文字色，透出卡片背后的玻璃与色斑。i = 1 是最下一格。
  R.battCells = {}
  for i = 1, GHOST_N do
    R.battCells[i] = W.group(c, GHOST_X,
      GHOST_Y + (GHOST_N - i) * (GHOST_H + GHOST_GAP), GHOST_W, GHOST_H, nil, 5)
    R.battCells[i]:set_color(C.text, 10)
  end
  W.outline(c, 140, 72, 72, 96, 18, C.ghost, 2)             -- 电池身
  W.group(c, 162, 62, 28, 12, nil, 4):set_color(C.ghost, 255) -- 正极凸头
  W.label(c, 14, 44, 202, 19, "剩余电量", SZ.micro, C.textMute, airui.TEXT_ALIGN_LEFT)
  R.battVal = W.label(c, 14, 76, 104, 67, "78", SZ.hero, C.text, airui.TEXT_ALIGN_LEFT)
  -- 「%」是常量，不存引用
  W.label(c, 100, 114, 30, 22, "%", SZ.label, C.textDim, airui.TEXT_ALIGN_LEFT)
  -- 1px 发丝线：隔开「数字区」和「续航区」。走默认 hairline + hairOpa
  -- （深色主题 6% 白 = 设计稿 --hair 的 rgba(255,255,255,.06)），创建后不再碰。
  W.hline(c, 14, 172, 202)
  R.battSub = W.label(c, 14, 188, 202, 22, "可行驶 — km", SZ.micro, C.textDim,
    airui.TEXT_ALIGN_LEFT)
end

-- ==================== 骑行卡（92 高） ====================
-- 均速已挪到底带第 3 栏，这里只留一项，字号给到 big 便于余光一瞥
local function build_ride(parent)
  local c = W.card(parent, L.left_x, L.card_y3, L.col_w, L.card_h3, 14)
  W.label(c, 14, 12, 202, 19, "本次骑行时长", SZ.micro, C.textMute, airui.TEXT_ALIGN_LEFT)
  R.rideVal = W.label(c, 14, 40, 202, 40, "00:00", SZ.big, C.text, airui.TEXT_ALIGN_LEFT)
end

-- ==================== 模式卡 ====================
local function build_mode(parent, on_mode)
  local c = W.card(parent, L.left_x, L.card_y2, L.col_w, L.card_h2, 14)
  W.label(c, 14, 10, 202, 19, "驾驶模式", SZ.micro, C.textMute, airui.TEXT_ALIGN_LEFT)
  R.pills = {}
  for i = 1, 3 do
    local y = 34 + (i - 1) * 40                -- 34 / 74 / 114，末行 114+34=148 ≤ 150
    -- no_glint：34 高的小胶囊不需要顶部高光线，选中时边框已是档位色
    local pill = W.card(c, 14, y, 202, 34, 17, function() on_mode(i) end, 1, true)
    local lb = W.label(pill, 0, 5, 200, 22, sim.MODES[i].cn, SZ.micro, C.textDim,
      airui.TEXT_ALIGN_CENTER)
    R.pills[i] = { box = pill, lb = lb }
  end
end

-- ==================== 组装 ====================
function M.build(parent, on_mode, on_charge)
  R = {}
  -- 归位：重建后所有「变了吗」的判断都要重新成立一次
  last_charge, last_ride, last_pct, last_sub = nil, -1, -1, nil
  build_mode(parent, on_mode)
  build_ride(parent)
  build_battery(parent, on_charge)
  M.set_mode(sim.mode)
  -- 建完立刻刷一次，免得首帧/切换瞬间闪一下构建时的初始态
  M.render(0)
end

-- 模式切换：换胶囊配色（不重建界面）
function M.set_mode(i)
  for k = 1, 3 do
    local e = R.pills and R.pills[k]
    if e ~= nil then
      local on = (k == i)
      local col = T.accent(k)
      e.box:set_color(col, on and 34 or 0)
      e.box:set_border_color(on and col or C.cardEdge, 1)
      e.lb:set_color(on and C.text or C.textDim)
    end
  end
end

-- ==================== 刷新 ====================
function M.render(dt)
  -- 低价值数据每帧只比整数刻度，变了才格式化。
  -- 每帧都调 util.clock / 拼 "可行驶 .. km" 再由 W.st 比对丢弃，等于白造字符串：
  -- 30fps 下每秒约 60 个临时串，GC 会在帧时间上打出尖峰。
  local ride = math.floor(sim.ride_s)
  if ride ~= last_ride then
    last_ride = ride
    W.st(R.rideVal, util.clock(sim.ride_s))
  end

  -- 电量只有一个整数：每帧比一次，省掉原来的 6.7Hz 累加器分支
  local pi = math.floor(util.clamp(sim.battery, 0, 100) + 0.5)
  if pi ~= last_pct then
    last_pct = pi
    W.st(R.battVal, util.fmt(pi))
    -- 幽灵电池 4 格跟着刷：竖排、自下而上。25% 一档四舍五入，
    -- 非零至少亮 1 格（<13% 掉到 0 格就成了「空电池」，比高估更误导）。
    -- 亮格按余量换色（≥50 绿 / ≥20 琥珀 / 其余红），59% 透明度 + 4% 灭格。
    -- 电量约 12s 才变 1 个整数，也就是 4 次 set_color / 12s。
    local lit = (pi > 0) and math.max(1, math.floor(pi / 25 + 0.5)) or 0
    local lit_col = (pi >= 50 and C.green) or (pi >= 20 and C.amber) or C.red
    for i = 1, GHOST_N do
      if i <= lit then
        R.battCells[i]:set_color(lit_col, 150)               -- 59% 余量色
      else
        R.battCells[i]:set_color(C.text, 10)                 -- 4% 轨道
      end
    end
  end

  -- 副行：平时显示续航（2.4s 才变的整数），充电时换文案。
  -- key 用整数档位：-1 = 充电，其余 = 续航 km。充电时 range 还在变，
  -- 但文案不变，所以 -1 这个 key 让拼串彻底短路。
  local sub = sim.charging and -1 or sim.range
  if sub ~= last_sub then
    last_sub = sub
    if sim.charging then
      W.st(R.battSub, "正在充电…")
    else
      W.st(R.battSub, "可行驶 " .. util.fmt(sim.range) .. " km")
    end
  end

  -- 充电只换颜色
  if last_charge ~= sim.charging then
    last_charge = sim.charging
    R.battVal:set_color(sim.charging and C.green or C.text)
    R.battSub:set_color(sim.charging and C.green or C.textDim)
  end
end

return M
