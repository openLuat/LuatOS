--[[
安全原语层（A4 落地）：
  1) 容器创建时登记内容区 cw/ch = 外框 - 2*border_width（弱键表，随控件回收）
  2) 每个子控件创建前按父层 cw/ch 收敛 x+w / y+h，越界收缩并按 tag 去重告警
  3) 会变的数字一律走 num / num_set（等宽格，F5）
禁止业务层裸调 airui.button / airui.container 做热区与显隐
]]

local T = require "ui_theme"
local CFG = require "app_config"
local ui_touch = require "ui_touch"

local M = {}

M.T = T

-- 内容区登记表：弱键，页面对控件无强引用时不阻止回收
local CSIZE = setmetatable({}, { __mode = "k" })
-- 屏幕绝对坐标登记表（沿父链累加；本项目页面不滚动）
local ABS = setmetatable({}, { __mode = "k" })
local group = nil
local warned = {}

local function warn_once(key, msg)
    if warned[key] then return end
    warned[key] = true
    log.warn("uiw", msg)
end

--- 收敛坐标与尺寸到父内容区，返回整数 x,y,w,h
function M.fit(parent, x, y, w, h, tag)
    local cw, ch = CFG.W, CFG.H
    if parent then
        local s = CSIZE[parent]
        if s then cw, ch = s[1], s[2] end
    end
    x, y = math.floor(x or 0), math.floor(y or 0)
    w, h = math.floor(w or 1), math.floor(h or 1)
    if x < 0 then w = w + x; x = 0 end
    if y < 0 then h = h + y; y = 0 end
    if w < 1 then w = 1 end
    if h < 1 then h = 1 end
    if x >= cw then x = cw - 1; w = 1 end
    if y >= ch then y = ch - 1; h = 1 end
    if x + w > cw then
        warn_once(tostring(tag) .. "@x", "[uiw] 横向越界已收敛 " .. tostring(tag) .. " " .. (x + w) .. " > " .. cw)
        w = cw - x
    end
    if y + h > ch then
        warn_once(tostring(tag) .. "@y", "[uiw] 纵向越界已收敛 " .. tostring(tag) .. " " .. (y + h) .. " > " .. ch)
        h = ch - y
    end
    return x, y, w, h
end

--- 标记控件的屏幕绝对坐标：只有 parent=nil 的裸容器（root）需要手动标
function M.mark(o, x, y)
    if o then ABS[o] = { x or 0, y or 0 } end
    return o
end

--- 当前构建分组："sheet" 表示弹层，关闭时可整组撤掉热区
function M.set_group(g) group = g end

local function abs_of(parent, x, y)
    local px, py = 0, 0
    if parent then
        local a = ABS[parent]
        if a then px, py = a[1], a[2] end
    end
    return px + x, py + y
end

--- 回调统一过闸门：固件的 release-select 通路与 ui_touch 兜底通路都会调用同一个闭包，
--- 一次抬起只能执行一次。必须在传参前包（airui 与兜底表拿到的是同一个 guarded 引用）
local function gated(cfg)
    cfg.on_click = ui_touch.guard(cfg.on_click)
    cfg.on_long_press = ui_touch.guard(cfg.on_long_press)
end

-- 容器 → 兜底热区记录（弱键）：按压高亮要把 press 回调挂到对应热区上
local HITOF = setmetatable({}, { __mode = "k" })

--- 带点击的控件同时登记到触摸兜底表；登记的 fn 与 on_click 是同一引用，
--- 两条通路都触发时由 guard 里的 gate 兜住，只执行一次
local function hook(parent, x, y, w, h, fn, tag, long_fn)
    if not fn and not long_fn then return end
    local ax, ay = abs_of(parent, x, y)
    return ui_touch.add(ax, ay, w, h, fn, tag, group, long_fn)
end

--- 容器（默认无描边；有描边时内容区自动缩 2*bw）
function M.box(parent, cfg)
    cfg = cfg or {}
    gated(cfg)
    local bw = cfg.border_width or 0
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "box")
    local args = {
        parent = parent,
        x = x, y = y, w = w, h = h,
        scrollable = false,
        radius = cfg.radius or 0,
        border_width = bw,
    }
    if cfg.color ~= nil then
        args.color = cfg.color
        if cfg.color_opacity then args.color_opacity = cfg.color_opacity end
    else
        args.color = -1
    end
    -- G2：无描边不传 border_color
    if bw > 0 and cfg.border_color then args.border_color = cfg.border_color end
    -- I4：on_click / on_long_press 必须在创建参数里传。
    -- 创建后再 set_on_click，固件侧取不到组件 meta 时会静默 unref 掉，
    -- 不报错、回调永远不触发 → 表现为"整片区域点不动"。
    if cfg.on_click then args.on_click = cfg.on_click end
    if cfg.on_long_press then args.on_long_press = cfg.on_long_press end

    local o = airui.container(args)
    if o then
        CSIZE[o] = { math.max(1, w - 2 * bw), math.max(1, h - 2 * bw) }
        ABS[o] = { abs_of(parent, x, y) }
        local it = hook(parent, x, y, w, h, cfg.on_click, cfg.tag, cfg.on_long_press)
        if it then HITOF[o] = it end
    end
    return o
end

--- 文本（高度不足时按字号+3 抬高，G3）
function M.text(parent, cfg)
    cfg = cfg or {}
    gated(cfg)
    local sz = cfg.size or T.FONT.body
    local h = cfg.h or (sz + 3)
    if h < sz + 3 then h = sz + 3 end
    local x, y, w, hh = M.fit(parent, cfg.x, cfg.y, cfg.w, h, cfg.tag or "text")
    local o = airui.label({
        parent = parent,
        x = x, y = y, w = w, h = hh,
        text = cfg.text or "",
        -- 固件带 hzfont 时用矢量字库；font_load 明确失败才退回内置点阵（不崩，只是小字）
        font = (G_HZFONT == false) and nil or "hzfont",
        font_size = sz,
        color = cfg.color or T.c.text,
        align = cfg.align or airui.TEXT_ALIGN_LEFT,
        on_click = cfg.on_click,
    })
    local it = hook(parent, x, y, w, hh, cfg.on_click, cfg.tag)
    if it and o then HITOF[o] = it end
    return o
end

--- 水平居中 + 垂直居中（在给定矩形内）
function M.text_mid(parent, cfg)
    cfg = cfg or {}
    local sz = cfg.size or T.FONT.body
    local box_h = cfg.box_h or (sz + 3)
    local y = (cfg.y or 0) + math.max(0, (box_h - (sz + 3)) // 2)
    local c = {}
    for k, v in pairs(cfg) do c[k] = v end
    c.y = y
    c.h = sz + 3
    c.align = airui.TEXT_ALIGN_CENTER
    return M.text(parent, c)
end

--- 图形
function M.shape(parent, cfg)
    cfg = cfg or {}
    gated(cfg)
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "shape")
    local o = airui.shape({
        parent = parent,
        x = x, y = y, w = w, h = h,
        items = cfg.items or {},
        on_click = cfg.on_click,
        on_long_press = cfg.on_long_press,
    })
    local it = hook(parent, x, y, w, h, cfg.on_click, cfg.tag, cfg.on_long_press)
    if it and o then HITOF[o] = it end
    return o
end

--- 图片（PNG 透明底，fit=contain）
function M.image(parent, cfg)
    cfg = cfg or {}
    gated(cfg)
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "image")
    local o = airui.image({
        parent = parent,
        x = x, y = y, w = w, h = h,
        src = cfg.src,
        fit = cfg.fit or "contain",
        opacity = cfg.opacity or 255,
        on_click = cfg.on_click,
        on_long_press = cfg.on_long_press,
    })
    local it = hook(parent, x, y, w, h, cfg.on_click, cfg.tag, cfg.on_long_press)
    if it and o then HITOF[o] = it end
    return o
end

--- 热区：透明 container + 闭包（I1），按下时叠一层极淡水膜做反馈
-- 回调必须随创建参数一起下发（I4），创建后再 set_on_click 在固件上会静默失效
function M.press(parent, cfg)
    cfg = cfg or {}
    local bw = cfg.border_width or 0
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "press")
    local flash, blink
    -- tap / hold 同一引用既交给 on_click，也登记到触摸兜底表，由外层的 guard 闸门去重
    local tap = (cfg.on_click or cfg.on_long_press) and function()
        if blink then blink() end
        if cfg.on_click then cfg.on_click() end
    end or nil
    local hold = cfg.on_long_press and function()
        if blink then blink() end
        cfg.on_long_press()
    end or nil
    -- 闸门包在最外层：一次抬起只执行一次，水膜反馈也不会连闪
    tap, hold = ui_touch.guard(tap), ui_touch.guard(hold)
    local area = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = -1, scrollable = false,
        on_click = tap,
        on_long_press = hold,
    })
    if not area then return nil end
    CSIZE[area] = { w, h }
    ABS[area] = { abs_of(parent, x, y) }
    local it = hook(parent, x, y, w, h, tap, cfg.tag, hold)
    if it then HITOF[area] = it end
    local fx, fy, fw, fh = M.fit(area, 0, 0, w - 2 * bw, h - 2 * bw, "press-in")
    flash = airui.container({
        parent = area, x = fx, y = fy, w = fw, h = fh,
        color = T.c.hl, color_opacity = 0,
        radius = cfg.radius or 0, scrollable = false,
    })
    blink = function()
        if not flash then return end
        pcall(function() flash:set_color(T.c.hl, 34) end)
        sys.timerStart(function()
            -- 这 90ms 里页面可能已经销毁（切主题全量重建、返回、关弹层），
            -- 此时 flash 是死对象，set_color 会打 "access destroyed airui component"。
            -- 热区记录被移出 hits 即代表控件已回收，直接放弃这次淡出。
            if it and not ui_touch.alive(it) then return end
            if flash then pcall(function() flash:set_color(T.c.hl, 0) end) end
        end, 90)
    end
    return area
end

--[[
按压高亮层（必须在容器所有子控件之后调用，否则会被子控件盖住）

为什么单独一步、不放进 box()：
  高亮层要压在图片/文字之上，box() 创建时子控件还没建，自动建就永远是底层、看不见。

为什么不用 on_click 里的 blink：
  固件的 on_click 只在 RELEASED 触发，按下到抬起这 80~150ms 屏幕毫无变化，
  主观就是"点了没反应"。这里把 press 挂到 ui_touch 的兜底热区上，
  DOWN 事件立刻变色，不用等抬起。

高亮层不带 on_click → 不 CLICKABLE，LVGL 命中会穿透到父容器，不影响点击；
也不登记热区，兜底命中表里查不到它。
]]
function M.hl(parent, radius, tag)
    if not parent then return nil end
    local cw, ch = CFG.W, CFG.H
    local s = CSIZE[parent]
    if s then cw, ch = s[1], s[2] end
    local x, y, w, h = M.fit(parent, 0, 0, cw, ch, (tag or "hl") .. "-in")
    local flash = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.c.hl, color_opacity = 0,
        radius = radius or 0, scrollable = false,
    })
    if not flash then return nil end
    local it = HITOF[parent]
    if it then
        it.press = function(on)
            pcall(function() flash:set_color(T.c.hl, on and 40 or 0) end)
        end
    end
    return flash
end

--[[
等宽数字块（F5）：数字一格一个 label，格宽固定，改值只换文字 + 重新居中
模板只写模板字符，不要写中文
]]
function M.num(parent, cfg)
    local sz = cfg.size or T.FONT.hero
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "num")
    local hdl = {
        cells = {}, size = sz, x = x, y = y, w = w, h = h,
        align = cfg.align or "center",
    }
    local tpl = cfg.template or "99"
    for i = 1, #tpl do
        local ch = tpl:sub(i, i)
        local digit = ch:match("%d") ~= nil
        local cw = digit and math.ceil(sz * 0.66) or math.ceil(sz * 0.30)
        hdl.cells[i] = {
            w = cw,
            digit = digit,
            ch = ch,
            txt = digit and "0" or ch,
            obj = airui.label({
                parent = parent,
                x = x, y = y, w = cw, h = h,
                text = digit and "0" or ch,
                font = (G_HZFONT == false) and nil or "hzfont", font_size = sz,
                color = cfg.color or T.c.text,
                align = airui.TEXT_ALIGN_CENTER,
            }),
        }
    end
    return hdl
end

function M.num_set(hdl, str)
    if not hdl then return end
    str = tostring(str or "")
    local cells = hdl.cells
    local n = #cells

    -- 从右往左填数字格，位数变化不影响其它数字的位置
    local k = #str
    local first = n + 1
    for i = n, 1, -1 do
        local c = cells[i]
        if c.digit then
            if k > 0 then
                c.txt = str:sub(k, k)
                k = k - 1
                first = i
            else
                c.txt = ""
            end
        end
    end
    if first > n then first = n end

    local total = 0
    for i = first, n do total = total + cells[i].w end

    local start_x = hdl.x
    if hdl.align == "center" then
        start_x = hdl.x + (hdl.w - total) // 2
    elseif hdl.align == "right" then
        start_x = hdl.x + hdl.w - total
    end

    for i = 1, n do
        local c = cells[i]
        local want = (i >= first) and c.txt or ""
        if want ~= c.shown then
            c.shown = want
            pcall(function() c.obj:set_text(want) end)
        end
        if i >= first then
            -- P5：坐标没变就不 set_pos，否则每秒倒计时都会触发一次无谓的布局
            if c.px ~= start_x then
                c.px = start_x
                pcall(function() c.obj:set_pos(start_x, hdl.y) end)
            end
            start_x = start_x + c.w
        end
    end
end

return M
