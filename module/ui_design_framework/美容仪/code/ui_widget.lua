--[[
  ui_widget.lua  AirUI 安全原语（本工程唯一的控件入口，禁止裸调 airui.*）

  职责：
  1) 几何收敛（AGENTS §A4）：容器创建时登记内容区 cw/ch = 外框 − 2×border_width；
     之后每个子控件创建前按父级 cw/ch 收敛 x+w / y+h，越界则收缩并按 tag 去重告警。
     ⚠ 收敛只保证「不出滚动条」，不保证文字没被裁 —— 那是调用方该改的数字。
  2) 显隐一律 set_color(c, opa)，禁用 hide/open（I2）。
  3) 热区一律透明容器 + 闭包（I1），不用 airui.button。
  4) 主题重涂：每个控件建好就登记进 WATCH，切主题后 repaint() 一次性刷色。

  坐标：设计画布与实机同为 1024x600，故不做缩放换算。

  === 颜色参数怎么传 ===
  所有 color 形参既接受数值，也接受**令牌名**（字符串，如 "glow"）。

    传数值   color = C.ink3        → 走色值映射表 cfg.map（旧值→新值）
    传字符串 color = "glow"        → 每次重涂直接取 cfg.C.glow

  为什么要有令牌名这条路：日间 fill 与 glow 是同一个墨青值，而夜间它们要分别
  变成 #1D4ED8 / #4C8DFF。色值映射表的键是「旧色值」，一个键只能映射到一个
  目标色，两个角色必然串味。所以凡是有多语义的令牌（fill/glow/on_fill/win/card/bg）
  一律传名字，不进映射表。

  === 运行时改色必须走 M.set_color ===
  直接 obj:set_color(...) 会让登记里的旧值停在原处，下次换主题时映射对不上，
  表现为「切回来有一部分控件颜色不回来」。M.set_color 把「下发」和「改登记」
  绑成一次操作，别绕开。
]]

local cfg = require "app_config"

local M = {}

local C = cfg.C
local SZ = cfg.SIZES
M.SZ = SZ

-- ==================== 内容区登记（A4） ====================
-- 弱键表：控件被回收时条目自动消失，不需要手动清理
local CSIZE = setmetatable({}, { __mode = "k" })
local warned = {}

local function csize_of(obj)
  local s = CSIZE[obj]
  if s then return s[1], s[2], s[3] end
  return nil, nil, nil
end

-- 收敛：返回父内容区内的安全 x/y/w/h
-- 内容区 = [bw, bw+cw] × [bw, bw+ch]（bw 为该容器的 border_width）：
-- 固件把 padding 设为 -bw 来抵消边框，所以子控件原点仍是 0，
-- 但 0..bw 这一圈是描边本身，子控件压上去会把边框盖掉。
local function fit(parent, x, y, w, h, tag)
  local cw, ch, bw = csize_of(parent)
  if not cw then return x, y, w, h end
  local ox, oy, ow, oh = x, y, w, h
  local l, t, r, b = bw, bw, bw + cw, bw + ch
  local clipped = false

  if x < l then x = l; clipped = true end
  if y < t then y = t; clipped = true end

  if x + w > r then
    w = r - x
    if w < 1 then w = 1 end
    clipped = true
  end
  if y + h > b then
    h = b - y
    if h < 1 then h = 1 end
    clipped = true
  end

  if clipped then
    local key = tostring(tag or "?") .. ":" .. tostring(parent)
    if not warned[key] then
      warned[key] = true
      log.warn("uiw", "越界已收敛", tag,
        string.format("%d,%d %dx%d -> %d,%d %dx%d (cw=%d ch=%d bw=%d)",
          ox, oy, ow, oh, x, y, w, h, cw, ch, bw))
    end
  end
  return x, y, w, h
end
M.fit = fit

function M.register(obj, cw, ch, bw)
  CSIZE[obj] = { cw, ch, bw or 0 }
  return obj
end

-- ==================== 主题登记 ====================
-- 强键数组：这里必须持有控件本身，弱键表会被 GC 清空，
-- 表现就是「切主题只有顶层变了」。本工程不重建页面，不存在条目淤积。
local WATCH = {}
-- 反查表（弱键）：给 set_color/set_items 找自己的登记条目
local WREF = setmetatable({}, { __mode = "k" })

--- 颜色规范化：字符串当令牌名，数值原样，nil 取默认令牌
local function col(v, def)
  if type(v) == "string" then return cfg.C[v], v end
  if v == nil and def then return cfg.C[def], def end
  return v, nil
end
M.col = col

--- 取重涂目标色：有令牌走令牌，否则查色值映射
local function target(val, token)
  if token then
    local v = cfg.C[token]
    if v then return v end
  end
  return cfg.map[val] or val
end

--- items 里的 color / fill_color 允许写令牌名，建对象前先解成数值
--  返回 (可直接交给 airui 的 items, 令牌表或 nil)
local function resolve_items(items)
  local real, tokens = {}, nil
  for i = 1, #items do
    local it = items[i]
    local tk
    if type(it.color) == "string" then
      tk = tk or {}
      tk.color = it.color
    end
    if type(it.fill_color) == "string" then
      tk = tk or {}
      tk.fill_color = it.fill_color
    end
    if tk then
      local c = {}
      for k, v in pairs(it) do c[k] = v end
      for f, token in pairs(tk) do c[f] = cfg.C[token] end
      real[i] = c
      tokens = tokens or {}
      tokens[i] = tk
    else
      real[i] = it
    end
  end
  return real, tokens
end

local function watch(obj, kind, val, token, opa)
  local e = { obj = obj, kind = kind, val = val, token = token, opa = opa }
  WATCH[#WATCH + 1] = e
  -- 反查只保留主条目（box 会同时登记底色与描边，底色那条优先）
  if not WREF[obj] then WREF[obj] = e end
  return obj
end
M.watch = watch

--- 按当前色板重涂所有登记过的控件
--  @return 实际下发的条目数（0 说明登记表是空的，调用方应回滚主题）
function M.repaint()
  local n, fail = 0, 0
  for i = 1, #WATCH do
    local e = WATCH[i]
    local ok = pcall(function()
      if e.kind == "container" then
        e.obj:set_color(target(e.val, e.token), e.opa)
      elseif e.kind == "border" then
        e.obj:set_border_color(target(e.val, e.token))
      elseif e.kind == "label" then
        e.obj:set_color(target(e.val, e.token))
      elseif e.kind == "shape" then
        local items = e.val
        if e.tokens then
          local out = {}
          for k = 1, #items do
            local it, tk = items[k], e.tokens[k]
            if tk then
              local c = {}
              for kk, vv in pairs(it) do c[kk] = vv end
              for f, token in pairs(tk) do c[f] = cfg.C[token] end
              out[k] = c
            else
              out[k] = it
            end
          end
          items = out
        end
        e.obj:set_items(items)
      end
    end)
    if ok then n = n + 1 else fail = fail + 1 end
  end
  if fail > 0 then
    log.warn("uiw", "重涂失败", fail, "/", #WATCH)
  end
  return n
end

--- 运行时改底色（同时同步登记，避免下次切主题映射对不上）
--  @param v   色值或令牌名
--  @param opa 容器透明度 0..255，可选（nil 表示沿用登记值）
function M.set_color(obj, v, opa)
  local val, token = col(v, nil)
  if val == nil then return end
  local e = WREF[obj]
  if e then
    e.val, e.token = val, token
    -- 只有 container 的 set_color 接受第二参数；label 传了会被忽略，但别依赖这个
    if e.kind == "container" then
      if opa ~= nil then e.opa = opa end
      obj:set_color(val, e.opa)
      return
    end
  elseif opa ~= nil then
    obj:set_color(val, opa)
    return
  end
  obj:set_color(val)
end

--- 运行时改描边色
function M.set_border(obj, v)
  local val, token = col(v, nil)
  if val == nil then return end
  local e = WREF[obj]
  if e and e.kind == "border" then
    e.val, e.token = val, token
  end
  obj:set_border_color(val)
end

--- 运行时换图元组（同时同步登记，避免被 repaint 刷回创建时的形态）
function M.set_items(obj, items)
  local real, tokens = resolve_items(items)
  local e = WREF[obj]
  if e and e.kind == "shape" then
    e.val, e.tokens = real, tokens
  end
  obj:set_items(real)
end

-- ==================== 容器 ====================
-- bw > 0 时必须传 border_color（G2 反向：传了 border_width 才画线）
function M.box(parent, x, y, w, h, o)
  o = o or {}
  x, y, w, h = fit(parent, x, y, w, h, o.tag or "box")
  local bw = o.bw or 0
  local opa = (o.opa ~= nil) and o.opa or 255
  local cv, ct = col(o.color, "card")
  local bv, bt
  if bw > 0 then bv, bt = col(o.border, "line2") end
  local el = airui.container({
    parent = parent, x = x, y = y, w = w, h = h,
    color = cv,
    color_opacity = opa,
    radius = o.radius or 0,
    border_color = (bw > 0) and bv or nil,
    border_width = bw,
    scrollable = false,
    on_click = o.on_click,
  })
  -- 内容区：每侧各缩 bw（描边圈不可被覆盖）
  M.register(el, w - 2 * bw, h - 2 * bw, bw)
  watch(el, "container", cv, ct, opa)
  if bw > 0 then watch(el, "border", bv, bt) end
  return el
end

-- 纯色条（分隔线 / 竖条 / 进度条），1px 级，无描边
function M.bar(parent, x, y, w, h, color, opa)
  x, y, w, h = fit(parent, x, y, w, h, "bar")
  local cv, ct = col(color, "line2")
  local op = opa or 255
  local el = airui.container({
    parent = parent, x = x, y = y, w = w, h = h,
    color = cv, color_opacity = op,
    radius = 0, border_width = 0, scrollable = false,
  })
  watch(el, "container", cv, ct, op)
  return el
end

-- ==================== 文字 ====================
-- 高度按真实行高兜底：hzfont line_height = size + 3（G3）
local function text_h(size, want)
  local base = size + 3
  if want and want >= base then return want end
  return base
end

function M.label(parent, x, y, w, o)
  o = o or {}
  local size = o.size or SZ[1]
  local h = text_h(size, o.h)
  x, y, w, h = fit(parent, x, y, w, h, o.tag or "label")
  local cv, ct = col(o.color, "ink")
  local lb = airui.label({
    parent = parent, text = o.text or "",
    x = x, y = y, w = w, h = h,
    font_size = size, color = cv,
    align = o.align or airui.TEXT_ALIGN_LEFT,
  })
  watch(lb, "label", cv, ct)
  return lb
end

-- 垂直居中：AirUI 的 label 文字顶部对齐（text_align 只管水平），
-- 必须让 label 高 = 行高，再按容器高居中，视觉中心才对得上。
function M.text_mid(parent, x, y, w, h, o)
  o = o or {}
  local size = o.size or SZ[1]
  local th = text_h(size)
  local yy = y + math.max(0, math.floor((h - th) / 2))
  return M.label(parent, x, yy, w, { text = o.text, size = size,
    color = o.color, align = o.align, tag = o.tag })
end

-- ==================== 图片 ====================
-- fit：stretch（1:1）/ cover（等比填满并居中裁切）/ contain
-- zoom：256 = 100%，切换微缩动画靠它（每帧 set_zoom）
-- 图片不登记：主题只用一套图，src 永不随主题变（暗色靠垫层+遮边条表达）
function M.image(parent, x, y, w, h, src, fitMode, zoom)
  x, y, w, h = fit(parent, x, y, w, h, "image")
  return airui.image({
    parent = parent, x = x, y = y, w = w, h = h,
    src = src, fit = fitMode or "stretch",
    zoom = zoom or 256,
  })
end

-- 出血图：w/h 必须给图片原始尺寸，x/y 可为负（由父容器裁切）
-- 用于「容器比图小、要居中裁切」的场景。这里必须用 fit="center"：
--   cover/contain/stretch 会在 update_align 里把 pivot 强制成 (0,0)，
--   之后 set_zoom 就是「以左上角为原点放大」，微缩动画会往右下漂；
--   center 分支不动 pivot，默认 (50%,50%) 按原始尺寸算，才是绕画面中心推近。
function M.image_raw(parent, x, y, w, h, src)
  return airui.image({
    parent = parent, x = x, y = y, w = w, h = h,
    src = src, fit = "center", zoom = 256,
  })
end

-- 图标不用 symbol 字体：label 传了 font_size 就走 hzfont，hzfont 没有 LVGL
-- 私有字形（F3），会渲染成空心方框；label 也没有 set_opacity / set_color(c, opa)
-- 这种显隐手段。所以图标一律用 shape 拼（play 三角 3 段 line，pause 两个 rect），
-- 需要切换形态时用 M.set_items(另一组)。


-- ==================== 矢量图元 ====================
-- items 直接按 1:1 设计坐标给（本工程不做缩放换算）；支持 line/circle/rect
function M.shape(parent, x, y, w, h, items)
  x, y, w, h = fit(parent, x, y, w, h, "shape")
  local real, tokens = resolve_items(items)
  local sh = airui.shape({ parent = parent, x = x, y = y, w = w, h = h,
    items = real })
  watch(sh, "shape", real, nil, nil)
  if tokens then WREF[sh].tokens = tokens end
  return sh
end

-- ==================== 折线（箭头 V 形） ====================
-- shape 只有 line/circle/ellipse/rect，无弧无箭头字形（F1/F3）
function M.polyline(parent, x, y, w, h, pts, color, width)
  local items = {}
  for i = 1, #pts - 1 do
    items[#items + 1] = {
      type = "line",
      x1 = pts[i][1], y1 = pts[i][2], x2 = pts[i + 1][1], y2 = pts[i + 1][2],
      color = color, width = width or 2,
    }
  end
  return M.shape(parent, x, y, w, h, items)
end

-- ==================== 热区 ====================
-- 透明容器 + 闭包（I1）；按下反馈交给调用方，避免 90ms 定时器拖尾
-- 不登记主题：它本来就全透明，换主题时不需要重涂
--
-- ⚠ 调用顺序铁律：热区必须是该区域里**最后一个**创建的子对象。
--   LVGL9 的 lv_obj 派生对象（container / shape / image）默认就带
--   LV_OBJ_FLAG_CLICKABLE，也就是说任何可见容器都会自己吃掉 press。
--   先 W.press 建热区、再往它里面塞可见底板 → 底板在上层截住点击，
--   热区永远收不到 → 真机上表现「按钮点不动」。
--   正确写法：先把可见件摆在父容器上，最后 W.press(父, 同区域) 盖上去。
function M.press(parent, x, y, w, h, on_click, radius, tag)
  x, y, w, h = fit(parent, x, y, w, h, tag or "press")
  return airui.container({
    parent = parent, x = x, y = y, w = w, h = h,
    color = 0xFFFFFF, color_opacity = 0,
    radius = radius or 0, border_width = 0,
    scrollable = false, on_click = on_click,
  })
end

-- ==================== 补间 ====================
-- frames 帧、每帧 frame_ms；setter(t) 收到 0→1
-- 第 1 帧即 t=1/frames（不是 0），末帧精确落 1，避免残留中间值
function M.tween(frames, setter, done)
  local i = 0
  local function step()
    i = i + 1
    setter(i / frames)
    if i < frames then
      sys.timerStart(step, cfg.ANIM.frame_ms)
    elseif done then
      done()
    end
  end
  sys.timerStart(step, cfg.ANIM.frame_ms)
end
M.tween_ms = cfg.ANIM.frame_ms

-- ==================== 等宽数字块（F5） ====================
-- 会变的数字串必须一格一个数字：hzfont 的 adv_w 等于字形位图宽度
-- （lv_font_hzfont.c），'1111' 比 '8888' 窄一截，整串 set_text 会左右跳。
-- 模板：'9' 为数字格（宽 size*0.66），其余连续字符合成一个窄格（宽 size*0.30）
local function num_build(parent, x, y, tmpl, size, color)
  local dw = math.floor(size * 0.66 + 0.5)
  local sw = math.floor(size * 0.30 + 0.5)
  local th = size + 3
  local cells, cx = {}, x
  local i, n = 1, #tmpl
  while i <= n do
    local ch = tmpl:sub(i, i)
    if ch == "9" then
      local lb = M.label(parent, cx, y, dw, { text = "0", size = size,
        color = color, align = airui.TEXT_ALIGN_CENTER, tag = "num" })
      cells[#cells + 1] = { lb = lb, start = i, len = 1 }
      cx = cx + dw
      i = i + 1
    else
      local j = i
      while j <= n and tmpl:sub(j, j) ~= "9" do j = j + 1 end
      local seg = tmpl:sub(i, j - 1)
      local lb = M.label(parent, cx, y, sw * #seg, { text = seg, size = size,
        color = color, align = airui.TEXT_ALIGN_CENTER, tag = "num" })
      cells[#cells + 1] = { lb = lb, start = i, len = #seg, fixed = true }
      cx = cx + sw * #seg
      i = j
    end
  end
  local h = { cells = cells, tmpl = tmpl, w = cx - x, h = th }

  -- 按位左对齐填充：值短了就补空格，长位不挪动前面的格
  function h.set(v)
    v = tostring(v or "")
    for _, c in ipairs(cells) do
      if not c.fixed then
        local ch = v:sub(c.start, c.start)
        if ch == "" or ch == " " then ch = " " end
        c.lb:set_text(ch)
      end
    end
  end
  return h
end

function M.num(parent, x, y, tmpl, size, color)
  return num_build(parent, x, y, tmpl, size, color)
end

-- 数字块宽度：给右对齐定位用（容器没有 set_size，只能算好 x 再建）
function M.num_w(tmpl, size)
  local dw = math.floor(size * 0.66 + 0.5)
  local sw = math.floor(size * 0.30 + 0.5)
  local w, i, n = 0, 1, #tmpl
  while i <= n do
    if tmpl:sub(i, i) == "9" then
      w = w + dw
      i = i + 1
    else
      local j = i
      while j <= n and tmpl:sub(j, j) ~= "9" do j = j + 1 end
      w = w + sw * (j - i)
      i = j
    end
  end
  return w
end

return M
