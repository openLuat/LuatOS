--[[
@module  ui_draw
@summary 今天吃什么 - 绘图与组件工具箱（图元 / 极坐标 / 缓动 / 抽签 / 控件封装）
@version 1.0
@date    2026.10.26
@usage
本模块只做两件事：
1、把「画一个胶囊 / 一个圆盘 / 一条分隔」变成一行调用，顺便把 C 层要的整数都取整
   （airui.shape 的字段是 lua_tointeger，浮点会变成 0，画出来是空的）；
2、把 airui.container / label / button 的常用参数收成默认值，界面代码里只剩布局。

注意（读源码得到的硬约束，改动前先看这里）：
- label / image / button 都没有 set_hidden，页面级显隐必须用 container 包一层；
- container / label / button 都没有 set_size，尺寸只能在创建时定死；
- label 的文本框高度要 >= 字号 + 4，否则字形会被裁掉；垂直居中要自己算 y 偏移；
- airui.shape:set_items 用 lua_rawlen 取长度，items 必须是「1..n 连续」的数组，
  中间不能有 nil，否则后面的图元全丢。
]]

local M = {}

-- ==================== 数值工具 ====================

-- C 层用 lua_tointeger，这里统一取整
local function rnd(v)
    v = tonumber(v) or 0
    if v >= 0 then return math.floor(v + 0.5) end
    return math.floor(v - 0.5)
end
M.rnd = rnd

--[[移动控件的唯一入口
airui 的 label / container / button / shape 的 set_pos 在 C 层是 luaL_checkinteger，
传浮点不是「取整」，而是直接 luaL_error（number has no integer representation），
协程里抛出会把整个 Lua VM 干掉（表现为 E/main Lua VM exit!! reboot）。
所以任何算出来的坐标都要先过这里，不要在页面代码里直接调 obj:set_pos。]]
function M.set_pos(obj, x, y)
    obj:set_pos(rnd(x), rnd(y))
end

--[[极坐标：角度 0 度在 12 点方向，顺时针为正
（LVGL 的 arc 是 0 度在 3 点、顺时针，这里刻意错开 90 度，
  因为转盘的视觉锚点是「正上方」，扇区 1 从 12 点开始更符合直觉）]]
function M.polar(cx, cy, r, deg)
    local rad = math.rad(deg)
    return cx + r * math.sin(rad), cy - r * math.cos(rad)
end

-- 三次缓出：起步快、收尾慢，转盘停稳的手感全靠它
function M.ease_out_cubic(p)
    local q = 1 - p
    return 1 - q * q * q
end

-- 缓入缓出，用于卡片淡入之类的短动效
function M.ease_in_out(p)
    if p < 0.5 then return 2 * p * p end
    local q = -2 * p + 2
    return 1 - q * q / 2
end

--[[单调毫秒时钟，只用来打点（转一次花了多久）
Air1603 的 mcu.ticks() 约 20ms/tick，要经 mcu.hz() 折算；PC 模拟器 hz()=1 视作 1tick/ms。]]
function M.now_ms()
    if mcu and mcu.ticks then
        local t = mcu.ticks()
        local hz = (mcu.hz and mcu.hz()) or 1000
        if hz and hz > 1 then
            return math.floor(t * 1000 / hz)
        end
        return t
    end
    return (os.time() or 0) * 1000
end

function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- 粗略估算文本宽度（只用于布局自检与日志，不参与真实排版）
function M.text_w(s, size)
    if not s then return 0 end
    local units = 0
    for _, cp in utf8.codes(s) do
        units = units + (cp < 128 and 0.56 or 1.0)
    end
    return math.floor(units * size + 0.5)
end

-- ==================== 随机与抽签 ====================

function M.seed()
    local t = os.time() or 0
    local ticks = (mcu and mcu.ticks and mcu.ticks()) or 0
    math.randomseed(t % 100000 + (ticks % 100000) * 7 + 13579)
    -- 丢弃前几个值，避免同秒开机时序列过于接近
    for _ = 1, 5 do math.random() end
end

--[[从 1..n 里不重复取 k 个，返回索引数组（部分洗牌，O(k)）
家常菜「荤 40 选 2 / 素 30 选 2 / 汤 10 选 1」就是三次调用它。]]
function M.sample(n, k)
    local idx = {}
    for i = 1, n do idx[i] = i end
    if k > n then k = n end
    for i = 1, k do
        local j = math.random(i, n)
        idx[i], idx[j] = idx[j], idx[i]
    end
    local out = {}
    for i = 1, k do out[i] = idx[i] end
    return out
end

-- 洗牌（就地）
function M.shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- ==================== shape 图元 ====================

-- 实心圆
function M.disc(cx, cy, r, color, opa)
    opa = opa or 255
    return {
        type = "circle", cx = rnd(cx), cy = rnd(cy), r = rnd(r),
        color = color, width = 1, opacity = opa,
        fill = true, fill_color = color, fill_opacity = opa,
    }
end

-- 空心圆（只描边）
function M.ring(cx, cy, r, color, w, opa)
    return {
        type = "circle", cx = rnd(cx), cy = rnd(cy), r = rnd(r),
        color = color, width = rnd(w), opacity = opa or 255, fill = false,
    }
end

--[[胶囊：一条两端圆头的粗线
转盘的每个扇区就是一条胶囊：径向铺开时是「糖果格」，
沿弧铺开时是「扇形格」，圆头把相邻扇区之间的缝补成柔和的圆角。]]
function M.capsule(x1, y1, x2, y2, w, color, opa)
    return {
        type = "line",
        x1 = rnd(x1), y1 = rnd(y1), x2 = rnd(x2), y2 = rnd(y2),
        color = color, width = rnd(w), opacity = opa or 255,
        round_start = true, round_end = true,
    }
end

-- 实心矩形 / 圆角矩形
function M.rect(x, y, w, h, radius, color, opa)
    opa = opa or 255
    return {
        type = "rect", x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
        radius = rnd(radius or 0), color = color, width = 1, opacity = opa,
        fill = true, fill_color = color, fill_opacity = opa,
    }
end

-- ==================== 控件封装 ====================
-- 这些封装函数都在 airui.init() 之后才会被调用（见 app/app_main.lua 的启动顺序），
-- 所以这里不缓存 airui 引用，避免模块在 airui 就绪前被 require 时拿到 nil。
--
-- 捕获模式（M.capture(true)）：不碰 airui，把每个控件 / shape 图元按创建顺序记进
-- 一张表，供 tools/preview 在 PC 上离屏渲染成 PNG 检查布局与配色（真机 1024x600
-- 没法截图，这个模式是唯一的「看得见」的自检手段，也是改版式后的回归对照）。

-- 文本对齐（值与 LV_TEXT_ALIGN_* 一致，PC 非 GUI 环境下 airui 为 nil 时用常量兜底）
M.ALIGN_LEFT, M.ALIGN_CENTER, M.ALIGN_RIGHT = 0, 1, 2
if airui and airui.TEXT_ALIGN_CENTER then
    M.ALIGN_LEFT = airui.TEXT_ALIGN_LEFT
    M.ALIGN_CENTER = airui.TEXT_ALIGN_CENTER
    M.ALIGN_RIGHT = airui.TEXT_ALIGN_RIGHT
end

local CAP

--[[开/关捕获：M.capture(true) 开始，M.capture() 结束并返回捕获到的记录表
返回结构：按创建顺序的数组，元素形如
  {kind="box", parent=父记录, x,y,w,h, radius,color,opa,border,border_w, hidden}
  {kind="label", parent=…, x,y,w,h, text,size,color,align}
  {kind="button", …}
  {kind="shape", …, items={...}}]]
function M.capture(on)
    if on then
        CAP = {}
        return CAP
    end
    local c = CAP
    CAP = nil
    return c
end

local function prec(parent)
    if type(parent) == "table" then return parent._rec end
    return nil
end

-- 捕获模式下的「控件替身」：页面代码照常 set_text / set_color / set_items，
-- 这里只把最后一次的状态记到记录里。
local function mkstub(rec)
    local o = { _rec = rec }
    function o:set_text(s) self._rec.text = s end
    function o:get_text() return self._rec.text end
    function o:set_color(c, opa)
        if c then self._rec.color = c end
        if opa then self._rec.opa = opa end
    end
    function o:set_style(s) if s and s.bg_color then self._rec.bg = s.bg_color end end
    function o:set_hidden(h) self._rec.hidden = h and true or false end
    function o:set_pos(x, y) self._rec.x, self._rec.y = rnd(x), rnd(y) end
    function o:set_disabled() end
    function o:set_border_color(c, w)
        if c then self._rec.border = c end
        if w then self._rec.border_w = w end
    end
    function o:set_items(items) self._rec.items = items end
    function o:set_rotation() end
    function o:set_pivot() end
    return o
end

--[[盒子（container）
opts: color/opa/radius/border/border_w/on_click
不传 color 就是透明容器，用来做「可整体隐藏的一层」。]]
function M.box(parent, x, y, w, h, opts)
    opts = opts or {}
    if CAP then
        local rec = {
            kind = "box", parent = prec(parent),
            x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
            radius = rnd(opts.radius or 0), color = opts.color, opa = opts.opa or 255,
            border = opts.border, border_w = opts.border_w or 0, hidden = false,
        }
        CAP[#CAP + 1] = rec
        return mkstub(rec)
    end
    local cfg = {
        parent = parent, x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
        radius = rnd(opts.radius or 0),
        color_opacity = opts.opa or 255,
        border_width = 0,
    }
    if opts.color then
        cfg.color = opts.color
        cfg.color_opacity = opts.opa or 255
    end
    if opts.border then
        cfg.border_color = opts.border
        cfg.border_width = opts.border_w or 1
    end
    if opts.on_click then cfg.on_click = opts.on_click end
    return airui.container(cfg)
end

--[[shape 图元画布
items 必须是 1..n 连续数组（airui.shape:set_items 用 lua_rawlen 取长度）。]]
function M.shape(parent, x, y, w, h, items)
    if CAP then
        local rec = {
            kind = "shape", parent = prec(parent),
            x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
            items = items, hidden = false,
        }
        CAP[#CAP + 1] = rec
        return mkstub(rec)
    end
    return airui.shape({ parent = parent, x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h), items = items })
end

local function cap_label(parent, x, y, w, h, text, size, color, align)
    local rec = {
        kind = "label", parent = prec(parent),
        x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
        text = text or "", size = size, color = color,
        align = align or M.ALIGN_LEFT, hidden = false,
    }
    CAP[#CAP + 1] = rec
    return mkstub(rec)
end

--[[单行文本，垂直居中在 cy 上
h 取「字号 + 6」，保证字形不被裁；y 由 cy 反推，调用方不用关心基线。]]
function M.label_mid(parent, x, cy, w, text, size, color, align)
    local h = size + 6
    if CAP then return cap_label(parent, x, cy - h / 2, w, h, text, size, color, align) end
    return airui.label({
        parent = parent, x = rnd(x), y = rnd(cy - h / 2), w = rnd(w), h = h,
        text = text or "", font = "hzfont", font_size = size, color = color,
        align = align or M.ALIGN_LEFT,
    })
end

-- 任意框内文本（多行菜谱用这个，靠 w 自动换行）
function M.label(parent, x, y, w, h, text, size, color, align)
    if CAP then return cap_label(parent, x, y, w, h, text, size, color, align) end
    return airui.label({
        parent = parent, x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
        text = text or "", font = "hzfont", font_size = size, color = color,
        align = align or M.ALIGN_LEFT,
    })
end

--[[胶囊按钮
opts: bg/text_color/radius/border/border_w/disabled/on_click]]
function M.button(parent, x, y, w, h, text, size, opts)
    opts = opts or {}
    local radius = rnd(opts.radius or math.floor(h / 2))
    if CAP then
        local rec = {
            kind = "button", parent = prec(parent),
            x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
            radius = radius, bg = opts.bg or 0xF2643C,
            text = text, size = size, color = opts.text_color or 0xFFFFFF,
            border = opts.border, border_w = opts.border_w or 0, hidden = false,
        }
        CAP[#CAP + 1] = rec
        return mkstub(rec)
    end
    local style = {
        bg_color = opts.bg or 0xF2643C,
        text_color = opts.text_color or 0xFFFFFF,
        radius = radius,
        border_width = rnd(opts.border_w or 0),
        pad = 0,
    }
    if opts.border then style.border_color = opts.border end
    if opts.bg_opa then style.bg_opa = opts.bg_opa end
    local btn = airui.button({
        parent = parent, x = rnd(x), y = rnd(y), w = rnd(w), h = rnd(h),
        text = text, font = "hzfont", font_size = size,
        style = style, on_click = opts.on_click,
    })
    if opts.disabled and btn then btn:set_disabled(true) end
    return btn
end

return M
