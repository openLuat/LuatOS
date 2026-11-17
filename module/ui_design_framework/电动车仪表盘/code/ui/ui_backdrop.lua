--[[
  ui_backdrop.lua  背景层：左右侧光 + 底部大圆弧氛围光

  为什么需要这一层：卡片是半透明的（bg_opa 只有 12/255），底下没有东西可透，
  就会变成「一圈描边浮在纯黑上」的幽灵框。这层就是卡片透出来的内容。

  为什么用椭圆而不是渐变：LVGL 9 没有径向渐变（shape 只有 line/circle/ellipse/rect/arc）。
  设计稿的 radial-gradient 用「同心椭圆 + 递减 fill_opacity」逼近——
  外层大椭圆 alpha 小，内层小椭圆再叠一层，中心自然最亮，边缘向外衰减。

  几何：每一组椭圆的圆心都故意落在屏外（左右 cx = -70 / 1094，底部 cy = 624），
  屏幕上只露出弧边——这是「看不出是个圆」的关键，圆心在屏内就必然看到完整轮廓。
  超出部分由 shape 自身裁剪，不影响滚动条（shape 不吃点击、不参与布局）。

  外框为什么不再是整屏（性能关键）：
    LVGL 判断一个对象要不要参与重绘，只看它的 bbox，不看里面画了什么。
    侧光最外层 rx=355（cx=-70 → 右边界 x=285），中间 454px（x=285..739）一个像素都没有，
    但整屏外框会让表盘 412x412 的每次重绘都把两块 1024x600 算进去。
    现在拆成左 (0,0,285,600) + 右 (739,0,285,600)，底部氛围光的 6 个椭圆
    最高点上沿在 y=474，外框裁到 (0,470,1024,130)。
    视觉零变化，覆盖面积从 2.36 屏降到 0.55 屏；
    且两块侧光的外框与表盘 bbox（306..718）**完全不相交**，表盘重绘不再拖着侧光。

  z 序：色斑要在卡片下面，氛围光要在卡片上面（设计稿里它盖着卡片做染色），
  所以由 ui.lua 在正确时机各调一次。
]]

local cfg = require "app_config"
local sim = require "app_sim"
local T   = require "ui_theme"
local W   = require "ui_widget"

local C = T.C
local L = T.L

local M = {}

local R = {}          -- orbL / orbR / amb 三个 shape

-- 三个外框：坐标是页面绝对坐标，items 里的 cx/cy 会自动减去外框原点
-- 侧光外框 = 最外层椭圆的实际右/左边界（-70+355 = 285；1094-355 = 739）
local ORB_L = { x = 0,   y = 0, w = 285,  h = 600 }
local ORB_R = { x = 739, y = 0, w = 285,  h = 600 }
local AMB   = { x = 0,   y = 470, w = 1024, h = 130 }

-- 把几何表 + 颜色 + 透明度装配成 shape items（cx/cy 平移到外框局部坐标）
local function items_of(list, box, col, opa_fn)
  local items = {}
  for i = 1, #list do
    local e = list[i]
    items[i] = {
      type = "ellipse", cx = e.cx - box.x, cy = e.cy - box.y,
      rx = e.rx, ry = e.ry,
      fill = true, fill_color = col, fill_opacity = opa_fn(e),
      color = col, opacity = 0,          -- 只填充，不描边
    }
  end
  return items
end

-- 侧光：每个椭圆按自己的 alpha，乘两个系数后落地
--   1) 档位补偿 orbA（紫 / 品红提亮，否则暗底上看着「没光」）
--   2) 主题系数 orbK（亮色整体压到 62%，否则浅底发脏）
-- 表里是「同圆心、半径等距、alpha 内浓外淡」的多层结构，
-- 屏幕里看不到任何一条圆形边界（单层椭圆则是一条硬边）。
-- side = "l" 取 cx < 512 的那几层，side = "r" 取其余（层数由 app_config.GLASS.orb 决定，目前各 4 层）。
local function orb_items(side)
  local col = T.accent(sim.mode)
  local mka = cfg.GLASS.orbA and cfg.GLASS.orbA[sim.mode] or 1
  local box = (side == "l") and ORB_L or ORB_R
  local list = {}
  for i = 1, #cfg.GLASS.orb do
    local e = cfg.GLASS.orb[i]
    if (side == "l") == (e.cx < 512) then list[#list + 1] = e end
  end
  return items_of(list, box, col, function(e)
    local v = math.floor(e.opa * mka * (C.orbK or 1) + 0.5)
    if v < 1 then v = 1 end
    return v
  end)
end

-- 底部氛围光：所有椭圆同色同 alpha，靠层数累加出径向衰减
local function amb_items()
  local col = T.accent(sim.mode)
  return items_of(cfg.GLASS.amb, AMB, col, function()
    return C.ambOpa or 6
  end)
end

-- 卡片之前调用：铺在背景上的色斑（左束 / 右束各一块）
function M.build_orb(parent)
  R.orbL = W.shape(parent, ORB_L.x, ORB_L.y, ORB_L.w, ORB_L.h, orb_items("l"))
  R.orbR = W.shape(parent, ORB_R.x, ORB_R.y, ORB_R.w, ORB_R.h, orb_items("r"))
  return R.orbL
end

-- 所有卡片之后调用：盖在最上层的底部氛围光
function M.build_amb(parent)
  R.amb = W.shape(parent, AMB.x, AMB.y, AMB.w, AMB.h, amb_items())
  return R.amb
end

-- 切档：三块一起换色（W.si 按 key 缓存，档位没变不会重绘）
function M.set_mode()
  W.si(R.orbL, sim.mode, function() return orb_items("l") end)
  W.si(R.orbR, sim.mode, function() return orb_items("r") end)
  W.si(R.amb,  sim.mode, amb_items)
end

return M
