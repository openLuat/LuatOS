--[[
  ui_widget.lua  AirUI 安全原语（本工程唯一控件入口，禁止裸调 airui.*）

  三件事，缺一件都视为不合格：

  1) 几何收敛（A4）
     容器创建时登记内容区 cw/ch = 外框 − 2×border_width；之后每个子控件创建前按父级
     cw/ch 收敛 x+w / y+h，越界就收缩并按 tag 去重告警。
     ⚠ 收敛只保证「不出滚动条」，不保证「文字没被裁」—— 数字算错还得回去改数字。

  2) 主题登记 + 就地重涂（T3 / T4 / T6 / T8）
     每个控件创建时把「颜色令牌名」登记进当前页面组（强键表，页面活着控件就不被 GC）。
     切主题只对登记表 set_color，不重建控件 —— 键盘里已敲的号码、已选档位全部保住（T5 的效果）。
     图元没有 set_color，走重下 items（T8）。

  3) 等宽数字块（F5）
     hzfont 的 adv_w 等于字形位图宽度，'1111' 比 '8888' 窄一截；
     会变的数字串（时钟 / 余额 / 币数 / 金额 / 倒计时）必须一格一个数字。
     模拟器字体等宽，这类抖动永远复现不出来。

  坐标：设计画布 = 实机 1024x600，不做缩放换算。
]]

local cfg = require "app_config"
local ICO = require "ui_icons"

local M = {}

M.SZ = cfg.SIZES
local SZ = cfg.SIZES
local ALIGN_L, ALIGN_C, ALIGN_R = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT
M.ALIGN_L, M.ALIGN_C, M.ALIGN_R = ALIGN_L, ALIGN_C, ALIGN_R

-- ==================== 当前色板 ====================
local PAL = {}          -- 由 ui_theme.set_pal 注入；初值空表，init 前取色兜底白不会索引 nil
local ONA = {}          -- 半透明令牌 opa（disc / vline / edgeline）
M.pal = function() return PAL end
M.set_pal = function(p) PAL = p end
M.c = function(tok) return PAL[tok] or 0xFFFFFF end
M.set_ona = function(t) ONA = t or {} end
-- 半透明令牌的 opa（背景圆盘 / 竖线 / 压边金线），随主题切换
M.a = function(tok) return ONA[tok] or 255 end

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
-- 坐标系按固件文档：子控件 x/y 原点 = 父容器**内容区**左上角，内容区 = 外框 − 2×描边宽度。
-- 所以安全范围是 [0, cw] × [0, ch]，**不要再把 bw 叠加到起点上**（叠加一次就右移/下移 1px，
-- 右缘立刻越过内容区 → 容器右下角多出两条滚动条，真机上就是两道浅灰细线）。
-- 右/下再内收 1px：子控件与内容区严丝合缝时 LVGL 也会判成溢出，留 1px 才干净。
local function fit(parent, x, y, w, h, tag)
  local cw, ch, bw = csize_of(parent)
  if not cw then return x, y, w, h end
  local ox, oy, ow, oh = x, y, w, h
  local l, t = 0, 0
  local R, B = cw, ch                    -- 真实边界：越过这条才算业务算错
  local r, b = R - 1, B - 1              -- 安全边界：贴边也内收 1px，防滚动条
  if r < l then r = l end
  if b < t then b = t end
  local clipped = false
  -- 只把"真的越过内容区"记成告警；被 1px 安全边距收掉的属于正常贴边，不刷日志
  local hard = (x < l) or (y < t) or (x + w > R) or (y + h > B)

  if x < l then x = l; clipped = true end
  if y < t then y = t; clipped = true end
  if x + w > r then w = r - x; if w < 1 then w = 1 end; clipped = true end
  if y + h > b then h = b - y; if h < 1 then h = 1 end; clipped = true end

  if clipped and hard then
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
local GROUPS = {}          -- 强键：组名 -> 条目数组（T4）
local CUR = nil
local OSTATE = setmetatable({}, { __mode = "k" })   -- obj -> 当前不透明度

function M.group(name)
  CUR = name
  if not GROUPS[name] then GROUPS[name] = {} end
  return GROUPS[name]
end

function M.group_drop(name)
  GROUPS[name] = nil
  if CUR == name then CUR = nil end
end

local function add(e)
  if not CUR then return end
  local g = GROUPS[CUR]
  if g then g[#g + 1] = e end
end

-- 登记（页面内部用，一般由 box/label/icon 自动调用）
-- k = "c" 容器 | "l" 文字 | "s" 图元
local TOK = setmetatable({}, { __mode = "k" })     -- obj -> 条目（供 opa 反查令牌）

-- bw：容器的描边宽度。set_border_color 的第二参数是「宽度」不是「不透明度」，
-- 重涂时必须回填原宽度 —— 传 255 会把内容区压成负数，卡片里所有子控件被整块裁掉。
function M.skin(obj, k, ck, bk, ikey, sz, bw)
  local e = { o = obj, k = k, ck = ck, bk = bk, ikey = ikey, sz = sz, bw = bw }
  add(e)
  TOK[obj] = e
  return obj
end

-- 透明度（显隐唯一手段，I2）：0 隐藏、255 显示
-- 登记在 OSTATE 里，repaint 按登记值重下，不会把隐藏控件刷回可见（T6）
function M.opa(obj, v)
  local s = OSTATE[obj]
  if not s then s = { oa = 255 }; OSTATE[obj] = s end
  if s.oa == v then return obj end
  s.oa = v
  local e = TOK[obj]
  if e and e.k == "c" then
    -- 登记时带令牌就用令牌（切主题跟着走），没令牌的用创建时的字面色（lit）
    local c = (e.ck and PAL[e.ck]) or e.lit
    if c then
      pcall(obj.set_color, obj, c, v)
      -- 描边宽度不跟 set_color 走：隐藏时一并归零，否则底色透明了边框还亮着（幽灵框）
      if e.bk then
        local bc = PAL[e.bk]
        if bc then pcall(obj.set_border_color, obj, bc, (v > 0) and (e.bw or 1) or 0) end
      end
    else
      log.warn("uiw", "显隐无效：对象没有登记颜色", tostring(obj))
    end
  elseif e and e.k == "s" then
    -- 图元没有 set_color，显隐只能重下 items 并带上 opacity
    pcall(obj.set_items, obj, ICO.items(e.ikey, e.sz, PAL[e.ck] or 0xFFFFFF, PAL, v))
  end
  return obj
end

-- 描边重涂（运行期改描边色的唯一入口）
-- set_border_color(color, width) 的第二参数是「边框宽度」，不是不透明度：
-- 传 255 会把容器内容区压成负数，卡片 / 按键里的文字与图标被整块裁掉（真机表现为"只剩色块"）。
-- 宽度一律回填登记值。
function M.border(obj, ck)
  local e = TOK[obj]
  local s = OSTATE[obj]
  local w = (s and s.oa <= 0) and 0 or ((e and e.bw) or 1)
  local c = (type(ck) == "string") and PAL[ck] or ck
  if c then pcall(obj.set_border_color, obj, c, w) end
  return obj
end

local function oa_of(obj)
  local s = OSTATE[obj]
  return s and s.oa or 255
end

-- 就地重涂（T3）：只 set_color，不重建；返回成功条数，为 0 说明固件 set_color 全挂（T7）
function M.repaint(p)
  PAL = p
  local n, fail = 0, 0
  for _, g in pairs(GROUPS) do
    for i = 1, #g do
      local e = g[i]
      local c = e.ck and p[e.ck]
      local ok = true
      if e.k == "c" then
        if c then ok = pcall(function() e.o:set_color(c, oa_of(e.o)) end) end
        -- 宽度必须回填登记值（1），不能传 255：255 是 set_color 的 opacity，不是边框宽度；
        -- 隐藏态（opacity 0）必须给 0，否则重涂会把描边重新画出来（幽灵框）
        if ok and e.bk then
          local bw = oa_of(e.o) > 0 and (e.bw or 1) or 0
          ok = pcall(function() e.o:set_border_color(p[e.bk], bw) end)
        end
      elseif e.k == "l" then
        if c then ok = pcall(function() e.o:set_color(c) end) end
      elseif e.k == "s" then
        local oa = oa_of(e.o)
        ok = pcall(function() e.o:set_items(ICO.items(e.ikey, e.sz, c or 0xFFFFFF, p, oa)) end)
      end
      if ok then n = n + 1 else fail = fail + 1 end
    end
  end
  if fail > 0 then log.warn("uiw", "重涂失败", fail) end
  return n
end

-- ==================== 容器 ====================
-- bw > 0 必须给描边色（G2）：只传 border_width 不传色 = 幽灵框
function M.box(parent, x, y, w, h, o)
  o = o or {}
  x, y, w, h = fit(parent, x, y, w, h, o.tag or "box")
  local dbw = o.bw or 0                    -- 设计描边宽度（显隐恢复时按它回填）
  -- opa_tok：按令牌取 opa（主题相关），o.opa：字面值（显隐用 0）
  local opa = (o.opa ~= nil) and o.opa or (o.opa_tok and (ONA[o.opa_tok] or 255)) or 255
  -- 创建即隐藏（opa = 0）的块不要画描边：set_color 到 0 只让底色透明，
  -- 描边色是独立的，会留下一圈"幽灵框"（toast 待机态在真机上就是一道亮弧）
  local bw = (opa > 0) and dbw or 0
  local col = o.color or PAL.card
  local el = airui.container({
    parent = parent, x = x, y = y, w = w, h = h,
    color = col, color_opacity = opa,
    radius = o.radius or 0,
    border_color = (bw > 0) and (o.border or PAL.edge) or nil,
    border_width = bw,
    scrollable = false,
    on_click = o.on_click,
  })
  M.register(el, w - 2 * dbw, h - 2 * dbw, dbw)
  if o.skin then
    M.skin(el, "c", o.skin, (dbw > 0) and (o.bskin or "edge"), nil, nil, dbw)
  else
    -- 没走令牌的容器也要能被 W.opa 控制：记下创建时的字面色
    TOK[el] = { o = el, k = "c", lit = col }
  end
  -- 必须记「实际下发的那一个 opa」：记 255 的话，半透明装饰块（opa_tok = disc/vline）
  -- 在切主题 repaint 时会被刷成不透明，一眼就是一块死色圆盘（T3/T6）
  OSTATE[el] = { oa = opa }
  return el
end

-- 纯色条（分隔线 / 竖条 / 进度条）
function M.bar(parent, x, y, w, h, ck, opa)
  x, y, w, h = fit(parent, x, y, w, h, "bar")
  local el = airui.container({
    parent = parent, x = x, y = y, w = w, h = h,
    color = PAL[ck] or ck, color_opacity = opa or 255,
    radius = 0, border_width = 0, scrollable = false,
  })
  M.register(el, w, h, 0)
  if type(ck) == "string" then
    M.skin(el, "c", ck)
  else
    TOK[el] = { o = el, k = "c", lit = ck }
  end
  OSTATE[el] = { oa = opa or 255 }
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
  local el = airui.label({
    parent = parent, text = o.text or "",
    x = x, y = y, w = w, h = h,
    font_size = size, color = PAL[o.ck] or PAL.text,
    align = o.align or ALIGN_L,
  })
  if o.ck then M.skin(el, "l", o.ck) end
  return el
end

-- 垂直居中 + 默认水平居中：AirUI 的 label 只按 align 摆水平位置，
-- 不传 align 就是左对齐 —— 这里原来漏了 ALIGN_C，所有 text_mid 的文字其实都贴着
-- label 左边画，真机上表现为「按钮 / 卡片里的字整体偏左」。
-- 坐标就是内容区坐标（原点 = 内容区左上角），**不再加 bw**：加了等于把文字块整体
-- 右移 1px，右缘越过内容区 → 父容器右缘多一条滚动条。
function M.text_mid(parent, x, y, w, h, o)
  o = o or {}
  local size = o.size or SZ[1]
  local th = text_h(size)
  local cw = csize_of(parent)
  local yy = y + math.max(0, math.floor((h - th) / 2))
  -- 右缘收到内容区的安全边界内：超出 1px 会被 fit 裁掉，裁右侧等于把重心往左推
  local ax, aw = x, w
  if cw then
    local R = cw - 1
    if ax + aw > R then aw = math.max(1, R - ax) end
  end
  return M.label(parent, ax, yy, aw, { text = o.text, size = size,
    ck = o.ck, align = o.align or ALIGN_C, tag = o.tag, h = th })
end

-- 右对齐文本（数值右缘固定，不随长度位移）
function M.text_right(parent, x, y, w, h, o)
  o = o or {}
  o.align = ALIGN_R
  return M.text_mid(parent, x, y, w, h, o)
end

-- ==================== 图元 ====================
function M.shape(parent, x, y, w, h, items, tag)
  x, y, w, h = fit(parent, x, y, w, h, tag or "shape")
  return airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = items })
end

-- 图标：自动登记（主题切换时重下 items，T8）
-- ck 指定单色图标的颜色令牌；双色图标（金币）内部自己取 pal
function M.icon(parent, name, x, y, s, ck, tag)
  x, y, s, s = fit(parent, x, y, s, s, tag or ("icon:" .. name))
  local col = PAL[ck] or PAL.text_sub
  local el = airui.shape({ parent = parent, x = x, y = y, w = s, h = s,
                           items = ICO.items(name, s, col, PAL) })
  M.skin(el, "s", ck or "text_sub", nil, name, s)
  return el
end

-- 二维码：真二维码由固件生成（码面是 RGB565 位图，不是 shape）
-- 静区 / 前景色显式给死，不跟随主题（扫不出来的主题没有意义）
-- 固件没编进 qrcode / 生成失败时 C 层给 nil 而不抛错：
-- 不判 nil 的话 M.build 会在这一行断掉，整屏一个控件都建不出来
function M.qrcode(parent, x, y, size, o)
  o = o or {}
  x, y, size, size = fit(parent, x, y, size, size, o.tag or "qrcode")
  local ok, el = pcall(airui.qrcode, {
    parent = parent, x = x, y = y, size = size,
    data = o.data or "",
    dark_color = o.dark or 0x0B0714,
    light_color = o.light or 0xFFFFFF,
    quiet_zone = (o.quiet ~= false),
  })
  if not ok or el == nil then
    log.warn("uiw", "二维码不可用", o.tag, ok and "nil" or tostring(el))
    return nil
  end
  return el
end

-- 折线（箭头 / 勾这类临时图元，不登记）
function M.polyline(parent, x, y, w, h, pts, ck, width)
  local items = {}
  for i = 1, #pts - 1 do
    items[#items + 1] = { type = "line",
      x1 = pts[i][1], y1 = pts[i][2], x2 = pts[i + 1][1], y2 = pts[i + 1][2],
      color = PAL[ck] or ck, width = width or 2, round_end = true }
  end
  return M.shape(parent, x, y, w, h, items, "poly")
end

-- ==================== 热区 ====================
-- 透明容器 + 闭包（I1）
function M.press(parent, x, y, w, h, fn, o)
  o = o or {}
  x, y, w, h = fit(parent, x, y, w, h, o.tag or "press")
  local el = airui.container({
    parent = parent, x = x, y = y, w = w, h = h,
    color = 0xFFFFFF, color_opacity = 0,
    radius = o.radius or 0, border_width = 0,
    scrollable = false,
    on_click = fn,
  })
  M.register(el, w, h, 0)
  return el
end

-- 可点击的块（卡片 / 按键）：块本体 + 叠上去的透明热区
-- 按下把描边刷成青 90ms 再复原；复原色取 keep 令牌（选中卡传 "cyber"，否则选中态会被刷掉）
function M.press_box(parent, x, y, w, h, fn, o)
  o = o or {}
  local el = M.box(parent, x, y, w, h, {
    color = o.color, opa = o.opa, radius = o.radius,
    bw = o.bw, border = o.border, skin = o.skin, bskin = o.bskin, tag = o.tag,
  })
  local bw = o.bw or 0
  local keep = o.keep or o.bskin or "edge"
  local busy = false
  -- 热区按内容区坐标摆：起点 (1,1)、尺寸 (cw-2, ch-2)，右/下缘都停在 cw-1 / ch-1。
  -- 起点不要写成 bw+1 —— 热区原点是内容区左上角，再加 bw 等于整体右移 1px，
  -- 右缘越界 → 每张卡片 / 每个键帽右下角各多两道滚动条（真机上的浅灰细线）。
  M.press(el, 1, 1, w - 2 * bw - 2, h - 2 * bw - 2, function()
    if bw > 0 and not busy then
      busy = true
      el:set_border_color(PAL.pri, bw)
      sys.timerStart(function()
        busy = false
        pcall(function() el:set_border_color(PAL[keep] or PAL.edge, bw) end)
      end, cfg.ANIM.press_ms)
    end
    fn()
  end, { radius = o.radius, tag = (o.tag or "pb") .. ":hit" })
  return el
end

-- ==================== 等宽数字块（F5） ====================
-- '9' 为数字格（宽 size*0.66），其余连续字符合成一个窄格（宽 size*0.30）
local function num_build(parent, x, y, tmpl, size, ck)
  local dw = math.floor(size * 0.66 + 0.5)
  local sw = math.floor(size * 0.30 + 0.5)
  local th = size + 3
  local cells, cx = {}, x
  local i, n = 1, #tmpl
  while i <= n do
    local ch = tmpl:sub(i, i)
    if ch == "9" then
      local lb = M.label(parent, cx, y, dw, { text = "0", size = size,
        ck = ck, align = ALIGN_C, tag = "num", h = th })
      cells[#cells + 1] = { lb = lb, start = i, len = 1 }
      cx = cx + dw
      i = i + 1
    else
      local j = i
      while j <= n and tmpl:sub(j, j) ~= "9" do j = j + 1 end
      local seg = tmpl:sub(i, j - 1)
      local lb = M.label(parent, cx, y, sw * #seg, { text = seg, size = size,
        ck = ck, align = ALIGN_C, tag = "num", h = th })
      cells[#cells + 1] = { lb = lb, start = i, len = #seg, fixed = true }
      cx = cx + sw * #seg
      i = j
    end
  end
  local h = { cells = cells, tmpl = tmpl, w = cx - x, h = th }

  -- 按位填充：默认左对齐（输入回显用），right = true 时右对齐（金额用）。
  -- 右对齐走「左侧补空格凑满模板长度」，格子的 x 位置一律不动，所以数字右缘恒定；
  -- 模板里的小数点/冒号是固定窄格，不参与填值，值必须自己带上同样的分隔符
  -- （例：模板 "999.99" ↔ 值 "19.90"），否则分隔符会错位落进数字格里。
  function h.set(v, right)
    v = tostring(v or "")
    if #v > #tmpl then
      v = right and v:sub(-#tmpl) or v:sub(1, #tmpl)
    end
    if right and #v < #tmpl then
      v = string.rep(" ", #tmpl - #v) .. v
    end
    local dirty = false
    for _, c in ipairs(cells) do
      if not c.fixed then
        local ch = v:sub(c.start, c.start)
        if ch == "" then ch = " " end
        if c.last ~= ch then
          c.lb:set_text(ch)
          c.last = ch
          dirty = true
        end
      end
    end
    return dirty
  end
  return h
end

function M.num(parent, x, y, tmpl, size, ck)
  return num_build(parent, x, y, tmpl, size, ck)
end

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

-- ==================== 生命周期 ====================
function M.kill(obj)
  if obj then pcall(obj.destroy, obj) end
end

-- 指针字（放一个 2px 细条模拟光标，比色块轻）
function M.caret(parent, x, y, h, ck)
  return M.bar(parent, x, y, 2, h, ck or "pri", 255)
end

-- ==================== 位图 ====================
-- 图片缺失不能让整屏空掉：pcall 判抛错，还要判 obj == nil（C 层失败不抛错）。
-- 参数名不能叫 fit：会遮蔽上面的 fit() 收敛函数，第一行就变成「调用字符串」
function M.image(parent, x, y, w, h, src, mode)
  x, y, w, h = fit(parent, x, y, w, h, "img")
  local ok, obj = pcall(airui.image, {
    parent = parent, x = x, y = y, w = w, h = h,
    src = src, fit = mode or "stretch",
  })
  if not ok or obj == nil then
    log.warn("uiw", "图片加载失败", tostring(src), ok and "nil" or tostring(obj))
    return nil
  end
  return obj
end

return M
