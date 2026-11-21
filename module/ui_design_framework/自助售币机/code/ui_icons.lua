--[[
  ui_icons.lua  矢量图标（shape 图元拼装）

  为什么不用 symbol 字体：label 只要传了 font_size 就走 hzfont，而 hzfont 只收
  GB2312 汉字与常用符号（F3），LVGL 私有字形（用户 / 扫码 / 勾 …）一律渲染成空心方框。

  约定：每个生成器收到 (s, color, pal)，返回 items 表；坐标系是 s × s，
  原点在图标左上角。线宽按尺寸自适应（小图标 2px，大图标 3px）。

  换主题时 shape 没有 set_color（T8），只重下 items：obj:set_items(fn(s, 新色, pal))。
]]

local M = {}

-- 线宽随尺寸走：18/22 用 2px，60 用 3px，140（登录页大金币）用 7px，
-- 固定 3px 会把大图标画成一根细细的圈，远看像没画
local function lw(s)
  local v = math.floor(s / 20 + 0.5)
  if v < 2 then v = 2 end
  if v > 8 then v = 8 end
  return v
end

local function arc_pts(cx, cy, r, a1, a2, segs)      -- 折线近似圆弧（F1：不依赖 arc 图元）
  local pts, n = {}, segs or 8
  for i = 0, n do
    local a = math.rad(a1 + (a2 - a1) * i / n)
    pts[#pts + 1] = { math.floor(cx + r * math.cos(a) + 0.5),
                      math.floor(cy + r * math.sin(a) + 0.5) }
  end
  return pts
end

local function poly(pts, color, w)
  local items = {}
  for i = 1, #pts - 1 do
    items[#items + 1] = { type = "line",
      x1 = pts[i][1], y1 = pts[i][2], x2 = pts[i + 1][1], y2 = pts[i + 1][2],
      color = color, width = w, round_end = true }
  end
  return items
end

-- ==================== 基础图形 ====================
-- 圆形描边环（金币、时钟外圈）
local function ring(s, color, w, inset)
  local c = s / 2
  return { type = "circle", cx = c, cy = c, r = c - (inset or w), color = color, width = w }
end

-- 填充圆点
local function dot(x, y, r, color)
  return { type = "circle", cx = x, cy = y, r = r, color = color, width = 1,
           fill = true, fill_color = color }
end

-- ==================== 图标 ====================
local I = {}

-- 会员（头 + 肩）
function I.member(s, c)
  local w = lw(s)
  local cx = s / 2
  return {
    { type = "circle", cx = cx, cy = s * 0.34, r = s * 0.17, color = c, width = w },
    poly(arc_pts(cx, s * 0.86, s * 0.30, 200, 340, 9), c, w),
  }
end

-- 扫码（四角 L）
function I.scan(s, c)
  local w = lw(s)
  local m, L = s * 0.16, s * 0.26
  local a, b, cc, d = m, m + L, s - m, s - m - L
  local items = {}
  local function seg(x1, y1, x2, y2)
    items[#items + 1] = { type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
                          color = c, width = w, round_end = true }
  end
  seg(a, b, a, a); seg(a, a, b, a)
  seg(cc, b, cc, a); seg(cc, a, d, a)
  seg(a, s - m - L, a, s - m); seg(a, s - m, b, s - m)
  seg(cc, s - m - L, cc, s - m); seg(cc, s - m, d, s - m)
  items[#items + 1] = { type = "line", x1 = s * 0.34, y1 = s / 2, x2 = s * 0.66, y2 = s / 2,
                        color = c, width = w, round_end = true }
  return items
end

-- 时钟（外环 + 指针）
function I.clock(s, c)
  local w = lw(s)
  local cx, cy = s / 2, s / 2
  return {
    ring(s, c, w, w + 1),
    { type = "line", x1 = cx, y1 = cy, x2 = cx, y2 = cy - s * 0.20, color = c, width = w, round_end = true },
    { type = "line", x1 = cx, y1 = cy, x2 = cx + s * 0.17, y2 = cy + s * 0.05, color = c, width = w, round_end = true },
  }
end

-- 金币（双色：外圈金 + 内圈深金 + ¥ 折线）
-- 颜色一律走当前色板令牌：pal.gold / pal.cyber 是旧紫黑主题的键名，已不存在，
-- 取不到就会静默落到写死的青金色 —— 亮色主题下这枚币会和整屏米金打架
function I.coin(s, c, pal)
  local gold = (c and c ~= 0) and c or (pal and (pal.pri or pal.gold)) or 0xD9B36C
  local cyan = (pal and (pal.pri_deep or pal.cyber)) or gold
  local w = lw(s)
  local cx, cy = s / 2, s / 2
  local items = {
    { type = "circle", cx = cx, cy = cy, r = s * 0.44, color = gold, width = w },
    { type = "circle", cx = cx, cy = cy, r = s * 0.32, color = cyan, width = w },
  }
  -- ¥：两撇 + 一竖 + 一横（全用直段）
  local x1, x2 = cx - s * 0.12, cx + s * 0.12
  local yt, ym = cy - s * 0.20, cy - s * 0.02
  local segs = poly({ { x1, yt }, { cx, ym }, { x2, yt } }, cyan, w)
  for i = 1, #segs do items[#items + 1] = segs[i] end
  items[#items + 1] = { type = "line", x1 = cx, y1 = ym, x2 = cx, y2 = cy + s * 0.20, color = cyan, width = w, round_end = true }
  items[#items + 1] = { type = "line", x1 = cx - s * 0.11, y1 = cy + s * 0.06, x2 = cx + s * 0.11, y2 = cy + s * 0.06, color = cyan, width = w, round_end = true }
  return items
end

-- 太阳（主题按钮，暗色下显示「切换到亮色」）
function I.sun(s, c)
  local w = lw(s)
  local cx, cy = s / 2, s / 2
  local items = { dot(cx, cy, s * 0.17, c) }
  for i = 0, 7 do
    local a = math.rad(i * 45)
    items[#items + 1] = {
      type = "line",
      x1 = math.floor(cx + s * 0.27 * math.cos(a) + 0.5),
      y1 = math.floor(cy + s * 0.27 * math.sin(a) + 0.5),
      x2 = math.floor(cx + s * 0.38 * math.cos(a) + 0.5),
      y2 = math.floor(cy + s * 0.38 * math.sin(a) + 0.5),
      color = c, width = w, round_end = true,
    }
  end
  return items
end

-- 月亮（主题按钮，亮色下显示「切换到暗色」）：大圆填充 + 偏移圆按背景色挖
-- 挖洞色必须是「图标所在层的底色」，主题按钮在顶栏上、顶栏透明铺在页面 bg 上 → 用 bg；
-- 用 card 会挖出一块和周围不同色的圆，看着像画歪的月牙
function I.moon(s, c, pal)
  local bg = (pal and pal.bg) or 0x120C22
  local items = { dot(s * 0.52, s * 0.48, s * 0.34, c) }
  items[#items + 1] = dot(s * 0.66, s * 0.36, s * 0.30, bg)
  return items
end

-- 勾（成功 / 选中）
function I.check(s, c)
  local w = lw(s)
  return poly({ { s * 0.22, s * 0.52 }, { s * 0.42, s * 0.72 }, { s * 0.80, s * 0.30 } }, c, w)
end

-- 叉（失败 / 清空）
function I.cross(s, c)
  local w = lw(s)
  local a = poly({ { s * 0.26, s * 0.26 }, { s * 0.74, s * 0.74 } }, c, w)
  local b = poly({ { s * 0.74, s * 0.26 }, { s * 0.26, s * 0.74 } }, c, w)
  for i = 1, #b do a[#a + 1] = b[i] end
  return a
end

-- 右箭头
function I.arrow(s, c)
  local w = lw(s)
  return poly({ { s * 0.40, s * 0.26 }, { s * 0.62, s * 0.50 }, { s * 0.40, s * 0.74 } }, c, w)
end

-- 左箭头（返回）
function I.back(s, c)
  local w = lw(s)
  return poly({ { s * 0.60, s * 0.26 }, { s * 0.38, s * 0.50 }, { s * 0.60, s * 0.74 } }, c, w)
end

-- 退格（← 加方框）
function I.del(s, c)
  local w = lw(s)
  local items = poly({ { s * 0.30, s * 0.50 }, { s * 0.44, s * 0.34 }, { s * 0.74, s * 0.34 },
                       { s * 0.74, s * 0.66 }, { s * 0.44, s * 0.66 }, { s * 0.30, s * 0.50 } }, c, w)
  items[#items + 1] = { type = "line", x1 = s * 0.44, y1 = s * 0.43, x2 = s * 0.62, y2 = s * 0.57, color = c, width = w, round_end = true }
  items[#items + 1] = { type = "line", x1 = s * 0.62, y1 = s * 0.43, x2 = s * 0.44, y2 = s * 0.57, color = c, width = w, round_end = true }
  return items
end

-- 微信（两个圆角气泡）
function I.wx(s, c)
  local items = {
    { type = "ellipse", cx = s * 0.42, cy = s * 0.42, rx = s * 0.30, ry = s * 0.26, color = c, width = 1, fill = true, fill_color = c },
    { type = "ellipse", cx = s * 0.62, cy = s * 0.64, rx = s * 0.26, ry = s * 0.22, color = c, width = 1, fill = true, fill_color = c },
  }
  items[#items + 1] = dot(s * 0.34, s * 0.40, s * 0.045, 0xFFFFFF)
  items[#items + 1] = dot(s * 0.50, s * 0.40, s * 0.045, 0xFFFFFF)
  items[#items + 1] = dot(s * 0.55, s * 0.63, s * 0.040, 0xFFFFFF)
  items[#items + 1] = dot(s * 0.70, s * 0.63, s * 0.040, 0xFFFFFF)
  return items
end

-- 支付宝（圆角方 + 中间支）
function I.ali(s, c)
  local w = lw(s)
  local items = {
    { type = "rect", x = s * 0.16, y = s * 0.16, w = s * 0.68, h = s * 0.68,
      radius = s * 0.16, color = c, width = w, fill = true, fill_color = c },
  }
  items[#items + 1] = { type = "line", x1 = s * 0.34, y1 = s * 0.44, x2 = s * 0.66, y2 = s * 0.44, color = 0xFFFFFF, width = w, round_end = true }
  items[#items + 1] = { type = "line", x1 = s * 0.50, y1 = s * 0.34, x2 = s * 0.50, y2 = s * 0.62, color = 0xFFFFFF, width = w, round_end = true }
  return items
end

-- 二维码
function I.qr(s, c)
  local w = lw(s)
  local b = s * 0.26
  local m = s * 0.14
  local items = {}
  local function corner(x, y)
    items[#items + 1] = { type = "rect", x = x, y = y, w = b, h = b, radius = 2, color = c, width = w }
    items[#items + 1] = { type = "rect", x = x + b * 0.34, y = y + b * 0.34, w = b * 0.32, h = b * 0.32,
                          radius = 1, color = c, width = 1, fill = true, fill_color = c }
  end
  corner(m, m)
  corner(s - m - b, m)
  corner(m, s - m - b)
  items[#items + 1] = { type = "rect", x = s * 0.40, y = s * 0.40, w = s * 0.10, h = s * 0.10,
                        radius = 1, color = c, width = 1, fill = true, fill_color = c }
  items[#items + 1] = { type = "rect", x = s * 0.58, y = s * 0.52, w = s * 0.14, h = s * 0.10,
                        radius = 1, color = c, width = 1, fill = true, fill_color = c }
  items[#items + 1] = { type = "rect", x = s * 0.44, y = s * 0.62, w = s * 0.10, h = s * 0.14,
                        radius = 1, color = c, width = 1, fill = true, fill_color = c }
  return items
end

-- 等待（三个点）
function I.wait(s, c)
  local r = s * 0.10
  return { dot(s * 0.26, s * 0.50, r, c), dot(s * 0.50, s * 0.50, r, c), dot(s * 0.74, s * 0.50, r, c) }
end

-- 客服（耳麦：弧 + 两个方块）
function I.help(s, c)
  local w = lw(s)
  local items = poly(arc_pts(s / 2, s * 0.52, s * 0.30, 180, 360, 10), c, w)
  items[#items + 1] = { type = "rect", x = s * 0.14, y = s * 0.46, w = s * 0.14, h = s * 0.26,
                        radius = 4, color = c, width = w, fill = true, fill_color = c }
  items[#items + 1] = { type = "rect", x = s * 0.72, y = s * 0.46, w = s * 0.14, h = s * 0.26,
                        radius = 4, color = c, width = w, fill = true, fill_color = c }
  return items
end

M.I = I

-- ==================== 出口归一 ====================
-- 两件事必须在这里做，漏一件图标就是一堆原点上的零长线段：
-- ① 拍平：生成器为了好写会返回 { 图元, poly(...) }，poly 返回的是一个「列表」，
--    直接塞进 items 会被当成一个 type 缺省的图元（x1..y2 全默认 0）；
-- ② 取整：airui 的 shape 字段走 airui_marshal_integer → lua_tointeger，
--    Lua 5.3/5.4 对非整数浮点（s*0.34 = 6.8）转换失败返回 0，坐标直接归零。
local NUMK = { "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry",
               "x", "y", "w", "h", "radius", "segments",
               "start_angle", "end_angle", "width", "opacity", "fill_opacity",
               "dash_width", "dash_gap" }

local function norm(out, src)
  for i = 1, #src do
    local it = src[i]
    if type(it) == "table" then
      if it.type == nil and it[1] ~= nil then
        norm(out, it)                       -- 嵌套列表 → 拍平
      else
        for j = 1, #NUMK do
          local k = NUMK[j]
          local v = it[k]
          if type(v) == "number" then it[k] = math.floor(v + 0.5) end
        end
        out[#out + 1] = it
      end
    end
  end
end

-- 统一取生成器：未知名字给一个方框，避免静默画出空 shape
-- opa 不为 255 时把每个图元的 opacity 一起降下来（shape 没有 set_color，显隐只能重下 items）
function M.items(name, s, c, pal, opa)
  local f = I[name]
  local src
  if not f then
    log.warn("uiw", "未知图标", name)
    src = { { type = "rect", x = 1, y = 1, w = s - 2, h = s - 2, radius = 2, color = c, width = 2 } }
  else
    src = f(s, c, pal)
  end
  local items = {}
  norm(items, src)
  if opa and opa < 255 then
    for i = 1, #items do items[i].opacity = opa end
  end
  return items
end

-- ==================== 品牌 / 设备示意 ====================
-- 徽标：菱形 + 中心币（顶栏 34px）
function I.logo(s, c)
  local w = lw(s)
  local items = poly({
    { s * 0.50, s * 0.08 }, { s * 0.92, s * 0.50 }, { s * 0.50, s * 0.92 },
    { s * 0.08, s * 0.50 }, { s * 0.50, s * 0.08 },
  }, c, w)
  items[#items + 1] = { type = "circle", cx = s / 2, cy = s / 2, r = s * 0.16,
                        color = c, width = w }
  items[#items + 1] = { type = "line", x1 = s / 2, y1 = s * 0.34,
                        x2 = s / 2, y2 = s * 0.66, color = c, width = w, round_end = true }
  return items
end

-- 手机（扫码页取景框示意）：机身边框 + 屏内码框 + Home 圆
function I.phone(s, c)
  local w = lw(s)
  return {
    { type = "rect", x = s * 0.19, y = s * 0.04, w = s * 0.62, h = s * 0.92,
      radius = s * 0.09, color = c, width = w },
    { type = "rect", x = s * 0.29, y = s * 0.22, w = s * 0.42, h = s * 0.42,
      radius = 2, color = c, width = w },
    { type = "circle", cx = s * 0.50, cy = s * 0.80, r = s * 0.035, color = c, width = w },
  }
end

return M
