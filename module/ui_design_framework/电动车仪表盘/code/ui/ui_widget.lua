--[[
  ui_widget.lua  AirUI 安全原语（本工程唯一控件入口，禁止业务层裸调 airui.*）

  三条硬约束落在这里，业务层写不出越界布局：
  1. 所有容器 scrollable = false —— 几何差 1px 也不会冒出滚动条
  2. 建容器时登记内容区尺寸（w - 2*bw），子控件创建时自动校验，越界 log.warn
  3. label 声明高度自动补到 hzfont 真实行高（字号 + 3）

  坐标：设计画布 = 实机 = 1024x600（kx = ky = 1），直接写数字即可。
]]

local T = require "ui_theme"
local C = T.C
local SZ = T.SIZES
local M = {}

M.page = nil

-- 父容器内容区登记表（weak key：容器销毁后自动回收）
local boxes = setmetatable({}, { __mode = "k" })

local function sx(v) return T.sx(v) end
local function sy(v) return T.sy(v) end
local function sf(v) return T.sf(v) end

function M.register(obj, w, h)
  if obj ~= nil then boxes[obj] = { w = w, h = h } end
end

-- 越界自检：只告警不阻断（真机上靠日志定位，布局本身按算式写死）
local function guard(parent, x, y, w, h, tag)
  local b = (parent ~= nil) and boxes[parent] or nil
  if b == nil then return end
  if x < 0 or y < 0 or (x + w) > b.w or (y + h) > b.h then
    log.warn("ui_widget", "布局越界", tag or "-",
      "rect", x, y, w, h, "right", x + w, "bottom", y + h,
      "content", b.w, b.h)
  end
end

-- ==================== 基础控件 ====================

-- 文本：h 不足会向下探出父容器，这里按 hzfont 行高兜底
function M.label(parent, x, y, w, h, text, size, color, align)
  local sz = sf(size or SZ.micro)
  local hh = math.max(sy(h or 24), sz + 3)
  guard(parent, sx(x), sy(y), sx(w), hh, "label")
  return airui.label({
    parent = parent, x = sx(x), y = sy(y), w = sx(w), h = hh,
    text = text or "", font_size = sz,
    color = color or C.text, align = align or airui.TEXT_ALIGN_LEFT,
  })
end

-- 透明容器：分组 / 热区 / 背景色块（显隐一律走 set_color，不用 hide/open）
function M.group(parent, x, y, w, h, onclick, radius)
  guard(parent, sx(x), sy(y), sx(w), sy(h), "group")
  local o = airui.container({
    parent = parent, x = sx(x), y = sy(y), w = sx(w), h = sy(h),
    color = C.bg, color_opacity = 0, radius = radius or 0,
    border_width = 0, scrollable = false, on_click = onclick,
  })
  M.register(o, sx(w), sy(h))
  return o
end

-- 卡片：默认 1px 发丝描边，登记内容区 = w-2 / h-2
function M.card(parent, x, y, w, h, radius, onclick, bw, no_glint)
  bw = bw or 1
  guard(parent, sx(x), sy(y), sx(w), sy(h), "card")
  local o = airui.container({
    parent = parent, x = sx(x), y = sy(y), w = sx(w), h = sy(h),
    color = C.cardGlass, color_opacity = C.cardOpa, radius = radius or 14,
    border_color = (bw > 0) and C.cardEdge or nil, border_width = bw,
    scrollable = false, on_click = onclick,
  })
  local cw, ch = sx(w) - 2 * sx(bw), sy(h) - 2 * sy(bw)
  M.register(o, cw, ch)
  -- 顶部 1px 高光线：模拟玻璃上沿的反光，窄控件（cw-28 < 8）自动跳过
  if not no_glint and (cw - 28) >= 8 then
    airui.container({
      parent = o, x = 14, y = 0, w = cw - 28, h = 1,
      color = C.hairline, color_opacity = C.hlOpa, radius = 1,
      border_width = 0, scrollable = false,
    })
  end
  return o
end

-- 幽灵描边：卡内水印 / 装饰轮廓（无底色，只有描边）。
-- AirUI 的 border_opa 固定 COVER、不能单独设透明度，所以描边色必须由调用方预混
-- （见 app_config.finish 的 p.ghost）。建完不再碰，零刷新成本。
function M.outline(parent, x, y, w, h, radius, color, bw)
  guard(parent, sx(x), sy(y), sx(w), sy(h), "outline")
  local o = airui.container({
    parent = parent, x = sx(x), y = sy(y), w = sx(w), h = sy(h),
    color = C.bg, color_opacity = 0, radius = radius or 14,
    border_color = color, border_width = bw or 2,
    scrollable = false,
  })
  M.register(o, sx(w), sy(h))
  return o
end

-- 水平发丝线
function M.hline(parent, x, y, w, color)
  guard(parent, sx(x), sy(y), sx(w), 1, "hline")
  return airui.container({
    parent = parent, x = sx(x), y = sy(y), w = sx(w), h = 1,
    color = color or C.hairline, color_opacity = C.hairOpa or 255, radius = 0,
    border_width = 0, scrollable = false,
  })
end

-- 垂直发丝线
function M.vline(parent, x, y, h, color)
  guard(parent, sx(x), sy(y), 1, sy(h), "vline")
  return airui.container({
    parent = parent, x = sx(x), y = sy(y), w = 1, h = sy(h),
    color = color or C.hairline, color_opacity = C.hairOpa or 255, radius = 0,
    border_width = 0, scrollable = false,
  })
end

-- shape items 几何缩放（set_items 前换算；width/color/opacity 保持原值）
function M.scale_items(items)
  local out = {}
  for i, it in ipairs(items or {}) do
    local o = {}
    for k, v in pairs(it) do o[k] = v end
    if o.x1 ~= nil then o.x1, o.y1 = sx(o.x1), sy(o.y1) end
    if o.x2 ~= nil then o.x2, o.y2 = sx(o.x2), sy(o.y2) end
    if o.cx ~= nil then o.cx, o.cy = sx(o.cx), sy(o.cy) end
    if o.x ~= nil then o.x, o.y = sx(o.x), sy(o.y) end
    if o.w ~= nil then o.w = sx(o.w) end
    if o.h ~= nil then o.h = sy(o.h) end
    if o.r ~= nil then o.r = math.max(1, sx(o.r)) end
    if o.rx ~= nil then o.rx = math.max(1, sx(o.rx)) end
    if o.ry ~= nil then o.ry = math.max(1, sy(o.ry)) end
    if o.width ~= nil then o.width = math.max(1, math.floor(o.width + 0.5)) end
    if o.start_angle ~= nil then o.start_angle = math.floor(o.start_angle + 0.5) end
    if o.end_angle ~= nil then o.end_angle = math.floor(o.end_angle + 0.5) end
    out[i] = o
  end
  return out
end

-- shape 外框与 items 几何按设计坐标缩放
function M.shape(parent, x, y, w, h, items)
  guard(parent, sx(x), sy(y), sx(w), sy(h), "shape")
  return airui.shape({
    parent = parent, x = sx(x), y = sy(y), w = sx(w), h = sy(h),
    items = M.scale_items(items),
  })
end

-- ==================== 页面 ====================

function M.new_page()
  local p = airui.container({
    parent = nil, x = sx(T.PX), y = sy(T.PY),
    w = sx(T.PW), h = sy(T.PH),
    color = C.bg, color_opacity = 255, radius = 0,
    border_width = 0, scrollable = false,
  })
  M.register(p, sx(T.PW), sy(T.PH))
  M.page = p
  return p
end

-- 主题切换重建：整屏销毁，引用表清空（不换表本身）
function M.destroy_pages()
  if M.page ~= nil then
    pcall(function() M.page:destroy() end)
    M.page = nil
  end
end

-- ==================== 增量 set_text ====================
-- LVGL label 的 set_text 没有"内容没变就跳过"的短路，这里按 weak key 缓存上次文本
local last_text = setmetatable({}, { __mode = "k" })

function M.st(lb, text)
  if lb == nil then return end
  text = tostring(text)
  if last_text[lb] == text then return end
  last_text[lb] = text
  -- 销毁判定放到「内容确实变了」之后：原来每个控件每帧都调一次 C 方法，
  -- 20 个控件 30fps 就是每秒 600 次纯开销，而命中缓存时根本不会碰 label。
  if lb.is_destroyed ~= nil and lb:is_destroyed() then return end
  lb:set_text(text)
end

-- shape 增量更新：key 没变就不重绘（全屏级 shape 重绘很贵）
-- build 是函数，只在真正需要重绘时才执行，避免每帧造表
local last_items = setmetatable({}, { __mode = "k" })

function M.si(sh, key, build)
  if sh == nil then return end
  local cache = last_items[sh]
  if cache == nil then
    cache = {}
    last_items[sh] = cache
  end
  if cache.key == key then return false end
  cache.key = key
  -- 同 M.st：销毁判定只在真的要重绘时才做，命中缓存时省掉一次 C 调用
  if sh.is_destroyed ~= nil and sh:is_destroyed() then return false end
  sh:set_items(build())
  return true
end

return M
