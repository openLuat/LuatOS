--[[
  ui_carousel.lua  单焦点轮播 194..458
    左露边 234x208(y=28) + 焦点 420x264(y=0) + 右露边 234x208(y=28)
    234 + 20 + 420 + 20 + 234 = 928，三槽正好铺满，两端不留白。

  切换 = 换图，不做轨道位移（6 张图 translate 会在首尾露出 254px 空白）。

  === 微缩动画 ===
  image 支持 zoom（256 = 100%），这就是真机上唯一能做「缩放」的手段：
    新图以基准×107% 入场，6 帧收到基准值 —— 视觉上是「推近后落定」；
    同时 opacity 130→255，避免换图瞬间的硬切。
  旧图不参与动画（它已经被新 src 顶掉），所以不存在两图叠加的内存峰值。
  动画期间再次点击：换 token，旧 tween 的后续帧自动作废（不会两个动画抢同一个 zoom）。

  === 夜间「深框亮窗」（见 docs/美容仪UI深蓝科技稿.html）===
  效果稿给图片加 10/16px 内缩 + object-fit:contain + 暖白窗底。真机不能照搬：
  改 fit 会走 update_align() 把 pivot 强制成 (0,0)，之后的 set_zoom 变成
  「以左上角为原点放大」，动画会往右下漂（见 ui_widget.image_raw 的说明）。
  所以这里用三层叠出等价观感，几何一个数字都不动：

    1) 垫层  win 色（暖白），尺寸 = 裁切层内缩 pad 后的窗口，默认 opa=0；
    2) 图片  仍是出血图，日间 zoom=256 铺满整层、把垫层完全盖住；
             夜间 zoom 缩到窗口内，四周露出暖白；
    3) 遮边条 4 条 card 色的细容器（上/下/左/右），日间 opa=0 不可见，
             夜间 opa=255 就是深蓝相框。

  图片内容一个像素都不改色 —— 白底产品图染色会变成青蓝全息图，认不出是器械。
]]

local cfg = require "app_config"
local W = require "ui_widget"
local ST = require "app_state"

local L = cfg.LAYOUT
local M = {}

local SIDE_W, SIDE_H = L.side_w, L.side_h          -- 234 x 208
local MAIN_W, MAIN_H = L.main_w, L.main_h          -- 420 x 264
local SIDE_OUT = 232                                -- 234 - 2×1
local SIDE_IN  = 206                                -- 208 - 2×1
local MAIN_OUT = 418                                -- 420 - 2×1
local MAIN_IN  = 262                                -- 264 - 2×1

local NAME_H = 34
local DOT_GAP, DOT_SZ = 13, 6
local DOTS_W = (ST.N - 1) * DOT_GAP + DOT_SZ + 22   -- 5×13+6+22 = 93

-- 图片原始尺寸（gen_mode_png.py 统一输出，六张同规格）
local IMG_W, IMG_H = cfg.IMG_W, cfg.IMG_H

-- 展示窗几何：pad 是相框厚度，window 是内缩后的暖白窗口
local MW, SW = cfg.WIN.main, cfg.WIN.side
local MAIN_PAD = MW.pad
local SIDE_PAD = SW.pad
local MAIN_WIN_W, MAIN_WIN_H = MAIN_OUT - MAIN_PAD * 2, MAIN_IN - MAIN_PAD * 2   -- 386 x 230
local SIDE_WIN_W, SIDE_WIN_H = SIDE_OUT - SIDE_PAD * 2, SIDE_IN - SIDE_PAD * 2   -- 212 x 186

--- 一个槽位的展示窗三层：暖白垫层 / 出血图 / 四条遮边条
--  返回 { win=垫层, img=图, bands={...} }，调用方负责把图放到正确位置
local function window_layers(clip, out_w, out_h, pad, src)
  local win = W.box(clip, pad, pad, out_w - pad * 2, out_h - pad * 2,
    { color = "win", bw = 0, opa = 0, tag = "win" })
  local img = W.image_raw(clip, math.floor((out_w - IMG_W) / 2),
    math.floor((out_h - IMG_H) / 2), IMG_W, IMG_H, src)
  -- 遮边条必须在图之后建（后建的盖在上面）
  local strips = {
    { 0, 0, out_w, pad },                          -- 上
    { 0, out_h - pad, out_w, pad },                -- 下
    { 0, pad, pad, out_h - pad * 2 },              -- 左
    { out_w - pad, pad, pad, out_h - pad * 2 },    -- 右
  }
  local bands = {}
  for i = 1, #strips do
    local s = strips[i]
    bands[i] = W.box(clip, s[1], s[2], s[3], s[4],
      { color = "card", bw = 0, opa = 0, tag = "band" })
  end
  return { win = win, img = img, bands = bands }
end

-- 侧槽：卡片 + 裁切层 + 展示窗三层 + 底部模式名条
local function side_slot(parent, x, on_click, init_key)
  local card = W.box(parent, x, L.side_top, SIDE_W, SIDE_H,
    { color = "card", bw = 1, border = "line2", tag = "side" })
  local clip = W.box(card, 1, 1, SIDE_OUT, SIDE_IN,
    { color = "card", bw = 0, tag = "sideclip" })
  local lay = window_layers(clip, SIDE_OUT, SIDE_IN, SIDE_PAD,
    cfg.img_src(init_key))

  W.bar(card, 1, SIDE_IN - NAME_H, SIDE_OUT, 1, "line2")
  W.box(card, 1, SIDE_IN - NAME_H + 1, SIDE_OUT, NAME_H - 1,
    { color = "card", tag = "nmbar" })
  local nm = W.text_mid(card, 1, SIDE_IN - NAME_H + 1, SIDE_OUT, NAME_H - 1,
    { text = "", size = 16, color = "ink2", align = airui.TEXT_ALIGN_CENTER,
      tag = "nm" })
  -- 热区最后建：压在图上，图本身不接点击
  W.press(parent, x, L.side_top, SIDE_W, SIDE_H, on_click, 0, "sidehit")
  return { img = lay.img, win = lay.win, bands = lay.bands, name = nm }
end

function M.build(page, on_pick)
  local box = W.box(page, L.pad, L.car_y, L.content_w, L.car_h,
    { color = "card", opa = 0, tag = "carou" })

  -- 初始三张图必须带 key：src=nil 会拼出 mode_nil.png，日志干净但槽位全空
  local i0 = ST.S.i
  local prevK = ST.MODES[ST.wrap(i0 - 1)].k
  local curK  = ST.MODES[i0].k
  local nextK = ST.MODES[ST.wrap(i0 + 1)].k

  local sL = side_slot(box, 0, function() on_pick(-1) end, prevK)
  local sR = side_slot(box, L.side_r_x, function() on_pick(1) end, nextK)

  -- 焦点槽：卡片(420×264) → 裁切层(418×262) → 展示窗三层
  -- 图偏 -1,-9 让图片中心对齐裁切层中心；set_zoom 的 pivot 是图中心，
  -- 所以放大时是「以画面中心为原点推近」，不会往右下漂
  local main = W.box(box, L.main_x, 0, MAIN_W, MAIN_H,
    { color = "card", bw = 1, border = "glow", tag = "main" })
  local mainClip = W.box(main, 1, 1, MAIN_OUT, MAIN_IN,
    { color = "card", bw = 0, tag = "mainclip" })
  local mLay = window_layers(mainClip, MAIN_OUT, MAIN_IN, MAIN_PAD,
    cfg.img_src(curK))
  local mainImg, mainWin = mLay.img, mLay.win

  -- 左右箭头：压在焦点卡内侧 14px，不遮器械（器械在画面中央）
  local ARROW = 44
  local ay = math.floor((MAIN_IN - ARROW) / 2)
  local function arrow(x, dir)
    -- 先摆可见件（圆底 + V 形折线），最后盖热区：
    -- 顺序反了的话圆底（默认 CLICKABLE）会在上层截住 press，箭头点不动
    W.box(main, x, ay, ARROW, ARROW,
      { color = "card", bw = 1, border = "line2", radius = 22, tag = "navbg" })
    -- V 形：两段 line 折线（F1/F3，没有箭头字形）
    local cx = ARROW / 2
    local pts = (dir < 0)
      and { { cx + 3, 13 }, { cx - 3, 22 }, { cx + 3, 31 } }
      or  { { cx - 3, 13 }, { cx + 3, 22 }, { cx - 3, 31 } }
    W.polyline(main, x, ay, ARROW, ARROW, pts, "ink2", 2)
    W.press(main, x, ay, ARROW, ARROW,
      function() on_pick(dir) end, 22, "nav")
  end
  arrow(14, -1)
  arrow(MAIN_OUT - 14 - ARROW, 1)

  -- 页码点：6 等宽点 + 1 个可位移的长条（容器无 set_size，靠位移表达「当前点拉长」）
  local dotsBox = W.box(main, math.floor((MAIN_OUT - DOTS_W) / 2), 14, DOTS_W, 24,
    { color = "card", opa = 235, radius = 12, tag = "dots" })
  local dots = {}
  for i = 1, ST.N do
    dots[i] = W.box(dotsBox, 11 + (i - 1) * DOT_GAP, 9, DOT_SZ, DOT_SZ,
      { color = "line2", radius = 3, tag = "dot" })
  end
  -- 长条在最后创建：盖住当前点，视觉上就是「当前点被拉长」
  local pill = W.box(dotsBox, 11 - 5, 9, 16, DOT_SZ, { color = "fill", radius = 3 })

  local token = 0

  local api = {}

  -- 只换图，不动布局；dir 仅用于未来做方向性位移
  function api.render(i)
    local prev = ST.MODES[ST.wrap(i - 1)]
    local cur  = ST.MODES[i]
    local nxt  = ST.MODES[ST.wrap(i + 1)]

    sL.img:set_src(cfg.img_src(prev.k))
    sR.img:set_src(cfg.img_src(nxt.k))
    sL.name:set_text(prev.n)
    sR.name:set_text(nxt.n)

    mainImg:set_src(cfg.img_src(cur.k))
    pill:set_pos(11 + (i - 1) * DOT_GAP - 5, 9)
    for k = 1, ST.N do
      W.set_color(dots[k], "line2")
    end
  end

  -- 微缩过场：新图 基准×107% → 基准，同时淡入
  -- 夜间基准是 210（图缩到窗口内），起止点必须按基准折算，
  -- 否则从 274 直接掉到 210 会有一次明显的「猛缩」
  function api.animate()
    token = token + 1
    local my = token
    local z1 = api.base_zoom()
    local z0 = math.floor(z1 * cfg.ANIM.zoom_in / 256 + 0.5)
    mainImg:set_zoom(z0)
    mainImg:set_opacity(130)
    W.tween(cfg.ANIM.zoom_frames, function(t)
      if my ~= token then return end
      mainImg:set_zoom(math.floor(z0 + (z1 - z0) * t + 0.5))
      mainImg:set_opacity(math.floor(130 + 125 * t))
    end)
  end

  --- 当前主题下焦点图的基准缩放（256 = 原尺寸铺满）
  function api.base_zoom()
    return (cfg.theme == "night") and MW.zoom or 256
  end

  --- 切主题后重设「展示窗」相关的一切
  --  必须在 ui_widget.repaint() 之后调用：repaint 会按登记里的 opa 回填颜色，
  --  把显隐态刷掉，所以顺序反了会出现「框是透明的」或「垫层盖住图」
  function api.apply_theme()
    local dark = (cfg.theme == "night")
    local bop = dark and 255 or 0
    local sl, sr = sL, sR
    for _, list in ipairs({ mLay.bands, sl.bands, sr.bands }) do
      for _, b in ipairs(list) do W.set_color(b, "card", bop) end
    end
    local wop = dark and 255 or 0
    W.set_color(mainWin, "win", wop)
    W.set_color(sl.win, "win", wop)
    W.set_color(sr.win, "win", wop)

    mainImg:set_zoom(api.base_zoom())
    mainImg:set_opacity(255)
    local sop = dark and SW.opacity or 255
    sl.img:set_opacity(sop)
    sr.img:set_opacity(sop)
  end

  -- 建完立刻按当前主题摆一次（上电时可能是夜间，虽然本轮默认日间）
  api.apply_theme()

  return api
end

return M
