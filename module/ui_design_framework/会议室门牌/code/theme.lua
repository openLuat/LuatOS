--[[
@module theme
@summary 会议室门牌 HMI - 配色 / 主题切换 / 页面工厂 / 通用控件 / 全代码绘制图标
         与 code/preview.html（1024×600）1:1 对应，工程零 PNG 贴图。
         三种模板（天际线 / 商务蓝 / 红白表格）共用一套语义色，浅色 / 深色各一套值。

         === 已确认的 AirUI 行为（实机踩坑，务必遵守）===
         1. label 的文字在控件框内是【顶部对齐】的！给一个 h=110 的框直接写字，字会贴在
            框顶，看起来"整体偏上、没对齐"。所以 theme.txt() 统一把 y 下移、h 收紧到单行
            行高（size*1.28），调用方仍然按"视觉块"给坐标，文字自动垂直居中。
         2. container 有 set_hidden / hide / open，label / shape / button【没有】。
            屏切换一律用"预建 + set_hidden"，不要 destroy + 重建（重建会留下残影、
            画面错位，而且慢）。
         3. shape 的 line 支持 round_start / round_end（圆头），图标一定要开，方头看起来
            又硬又糙。
         4. slider 的轨道粗细由控件高度和 style.pad 决定：h=24 + pad=8 → 轨道 8px，
            正好等于 html 里的 .track 高度；不设 pad 会变成一根 24px 的粗黄油条。
         5. 所有坐标/半径必须取整，小数坐标会导致图元不显示。
         6. 弧线一律用多段折线 ARC()/ELL() 拼接（arc / ellipse 图元在本批固件上不可靠）。
         7. 中文字宽 ≈ 3 字节/字，按 #s 估算宽度会把元素撑开一倍。
         8. 字号下限 16（正文 16~20，标题 20~22，首页时钟 84）。
]]

local sys   = require "sys"
local exwin = require "exwin"

local theme = {}

theme.W, theme.H = 1024, 600
pcall(function()
    local w, h = display.getSize()
    if w and h and w > 0 then theme.W = w end
    if h and h > 0 then theme.H = h end
end)

--------------------------------------------------------------------
-- 调色板：浅色（默认，对应 preview.html 的 light）/ 深色
-- C 是"当前生效"的调色板：切换时就地覆写字段（不换表）
--------------------------------------------------------------------
theme.cur = "light"

-- 配色：浅色（默认，preview.html 的 light）与深色（dark），两张表键必须完全一致
theme.PALETTES = {
    light = {
        bg        = 0xEAF3FC,  bg_top = 0xF7FBFF, bg_bot = 0xA9C8E6,
        haze      = 0xDCE9F6,  haze_opa = 120,
        -- 浅色下这几处"白"故意错开 1~2 个色阶（肉眼无差）：repaint 按值反查语义键，
        -- 若 card/slot_bg/crow/ccard 都等于 0xFFFFFF，就会被统一认成 white，
        -- 切回深色时白底卡片/按钮不会变深灰，浅色主题反而留下大方块白。
        card      = 0xFEFFFF,  card2  = 0xF2F6FB,
        panel     = 0xFDFCFA,  panel2 = 0xF0F3F7,
        text      = 0x1B3A5C,  text2  = 0x16324F,
        sub       = 0x4C7196,  dim    = 0x8FA6BD,
        line      = 0xE3EBF4,  white  = 0xFFFFFF, black = 0x000000,
        blue      = 0x1E7BD6,  blue2  = 0x2EA0CE,
        red       = 0xC8343C,  red2   = 0xA8242A, redsoft = 0xF6DEE0,
        green     = 0x1E8A5B,  yellow = 0xFFC24B, orange = 0xFF8A00,
        city1     = 0xBFD3E8,  city2  = 0xAEC6DF, citywin = 0x5E84AE,
        dial1     = 0xF7FBFF,  dial2  = 0xC6D9EE,
        ring1     = 0x386EA8,  ring2  = 0x508CC8,
        tagc      = 0xA8404E,
        b1        = 0xEEF4FC,  b2 = 0xC9DAF2, b3 = 0xB6CDEC,
        arc       = 0x4678B4,  arc_opa = 46,
        qr_bg     = 0xFFFFFF,  qr_fg  = 0x12161C,
        c1        = 0xE9E3DD,  c2 = 0xDCD6CF, c3 = 0xE6E0DA, c4 = 0xD3CCC4,
        cshade    = 0x000000,  cshade_opa = 46,
        crow      = 0xFCFDFF,  crowtext = 0x2A2E34,
        chead     = 0xF3EEEA,  cheadtext = 0x5A5F66,
        ccard     = 0xFBFEFF,  ccardtext = 0x2B2F35,
        ctop1     = 0xC8343C,  ctop2 = 0xA8242A,
        mask      = 0x000000,  mask_opa = 90,
        toast_bg  = 0x18202C,  toast_opa = 232,
        slot_bg   = 0xFDFEFF,  seg_on_bg = 0xEAF3FF, seg_on_fg = 0x1E7BD6,
        prog_track = 0x1E3C6E, prog_opa = 40,
        sched_cur = 0xEAF3FF,  sched_mine = 0xE7F6EE,
        track     = 0x7896B4,  track_opa = 90,
    },
    dark = {
        bg        = 0x0B2039,  bg_top = 0x14375F, bg_bot = 0x061426,
        haze      = 0x0A1B2E,  haze_opa = 150,
        card      = 0x1B2733,  card2  = 0x22303E,
        panel     = 0x1C242E,  panel2 = 0x232D39,
        -- 注意：text2 不能和 white 同值。repaint 是按色值反查语义键的，
        -- 一旦 dark.text2 == 0xFFFFFF，所有用 C.white 画的文字都会被当成 text2，
        -- 切到浅色就变成 text2 的深蓝 —— 深色 toast 条上的白字直接看不见。
        text      = 0xEAF1F8,  text2  = 0xF2F8FF,
        sub       = 0x9AA8B8,  dim    = 0x7F8FA0,
        line      = 0x2A3644,  white  = 0xFFFFFF, black = 0x000000,
        blue      = 0x1E7BD6,  blue2  = 0x2EA0CE,
        red       = 0xC8343C,  red2   = 0xA8242A, redsoft = 0x3A1B1E,
        green     = 0x1E8A5B,  yellow = 0xFFC24B, orange = 0xFF8A00,
        city1     = 0x0B2039,  city2  = 0x0D2743, citywin = 0xFFD696,
        dial1     = 0x0F2B49,  dial2  = 0x061426,
        ring1     = 0xC8E0FF,  ring2  = 0xBEE1FF,
        tagc      = 0xFF8A94,
        b1        = 0x0A1E38,  b2 = 0x14375F, b3 = 0x0A2447,
        arc       = 0xC8DCF5,  arc_opa = 40,
        qr_bg     = 0xFFFFFF,  qr_fg  = 0x12161C,
        c1        = 0x2A1A1C,  c2 = 0x241B1A, c3 = 0x241C1D, c4 = 0x1E1617,
        cshade    = 0x000000,  cshade_opa = 90,
        crow      = 0x2C2223,  crowtext = 0xEAD8D8,
        chead     = 0x2C2223,  cheadtext = 0xC9A0A0,
        ccard     = 0x302425,  ccardtext = 0xF2A0A4,
        ctop1     = 0xC8343C,  ctop2 = 0xA8242A,
        mask      = 0x000000,  mask_opa = 110,
        toast_bg  = 0x18202C,  toast_opa = 236,
        slot_bg   = 0x232D39,  seg_on_bg = 0x1E2E42, seg_on_fg = 0x7CB8F5,
        prog_track = 0x2F4A6B, prog_opa = 90,
        sched_cur = 0x1E2E42,  sched_mine = 0x1F2E27,
        track     = 0x7896B4,  track_opa = 90,
    },
}

theme.C = {}
for k, v in pairs(theme.PALETTES.light) do theme.C[k] = v end

function theme.toggle_theme()
    theme.cur = (theme.cur == "dark") and "light" or "dark"
    for k, v in pairs(theme.PALETTES[theme.cur]) do theme.C[k] = v end
    log.info("theme", "switch to " .. theme.cur)
    return theme.cur
end

function theme.set_theme(name)
    if not theme.PALETTES[name] then return end
    theme.cur = name
    for k, v in pairs(theme.PALETTES[name]) do theme.C[k] = v end
end

local C = theme.C

theme.TOP_H = 62

--------------------------------------------------------------------
-- 换肤（就地改色，不重建控件）
-- 为什么不用「destroy 整页再重建」：重建一个 label 要重新布局、重新取字形，
-- 几百个控件串起来就是一两秒；set_color / set_style / set_items 只打脏标记，
-- 最后统一重绘一次，几乎是瞬间的。
-- 这里不按「语义键」传色（调用点都是 theme.box(p, ..., C.card)，拿到的是数字），
-- 而是登记"这个控件用了哪个色值"，切换时按值反查调色板得到新值。
-- 同值多键（浅色下 card / white / qr_bg 都是 0xFFFFFF）用键表顺序消歧。
--------------------------------------------------------------------
theme.SKIN = {}                     -- 控件对象 -> 登记项
theme._prev = theme.cur
local skin_seq = {}                 -- 按登记顺序保存（每个对象一条）

function theme.skin_reset()
    theme.SKIN = {}
    skin_seq = {}
end

local function skin_put(o, e)
    if not o then return o end
    e.o = o
    if theme.SKIN[o] then
        for i = 1, #skin_seq do
            if skin_seq[i].o == o then skin_seq[i] = e break end
        end
    else
        skin_seq[#skin_seq + 1] = e
    end
    theme.SKIN[o] = e
    return o
end

-- 键表顺序 = 同值时的优先级
local LABEL_KEYS = { "text", "text2", "sub", "dim", "white", "red", "red2",
    "crowtext", "ccardtext", "cheadtext", "seg_on_fg", "tagc", "citywin", "black" }
local BOX_KEYS = { "bg", "bg_top", "bg_bot", "card", "card2", "panel", "panel2",
    "crow", "chead", "ccard", "slot_bg", "dial1", "dial2", "city1", "city2",
    "haze", "b1", "b2", "b3", "c1", "c2", "c3", "c4", "ctop1", "ctop2",
    "sched_cur", "sched_mine", "seg_on_bg", "redsoft", "prog_track", "track",
    "qr_bg", "blue", "red", "green", "white", "black" }
local LINE_KEYS = { "line", "dim", "sub", "track", "red", "blue", "white" }
local SHAPE_KEYS = { "line", "city1", "city2", "citywin", "dial1", "dial2",
    "ring1", "ring2", "arc", "qr_bg", "qr_fg", "white", "black", "cshade",
    "bg", "bg_top", "bg_bot", "text", "sub", "dim", "red", "green", "blue" }
local OPA_KEYS = { "mask_opa", "haze_opa", "arc_opa", "track_opa", "prog_opa" }

local function remap(v, keys, from, to)
    if v == nil then return nil end
    for i = 1, #keys do
        local k = keys[i]
        if from[k] == v then
            local nv = to[k]
            if nv ~= nil then return nv end
        end
    end
    -- 键表没覆盖到的（调用方算出来的插值色）扫一遍全表
    for k, ov in pairs(from) do
        if ov == v then return to[k] or v end
    end
    return v
end

-- 把已登记的控件全部刷成当前主题颜色，返回刷新的控件数
function theme.repaint()
    local from = theme.PALETTES[theme._prev or theme.cur]
    local to   = theme.PALETTES[theme.cur]
    if not from or not to then return 0 end
    if from == to then
        theme._prev = theme.cur      -- 主题没变（连点抵消）：控件已是当前配色，直接返回
        return 0
    end
    local n = 0
    for i = 1, #skin_seq do
        local e = skin_seq[i]
        local o = e.o
        if o then
            local alive = true
            if o.is_destroyed then
                local ok, d = pcall(o.is_destroyed, o)
                alive = not (ok and d)
            end
            if alive then
                n = n + 1
                local t = e.t
                if t == "box" then
                    local nv = e.ck and to[e.ck] or remap(e.color, BOX_KEYS, from, to)
                    local no
                    if e.opa then
                        no = remap(e.opa, OPA_KEYS, from, to)
                        e.opa = no
                    end
                    e.color = nv        -- 记住刷上去的新色，下次切换按它反查（否则第二次来回会错色）
                    pcall(o.set_color, o, nv, no or 255)
                    if e.bd then
                        local nb = remap(e.bd, LINE_KEYS, from, to)
                        e.bd = nb
                        pcall(o.set_border_color, o, nb, e.bw or 1)
                    end
                elseif t == "label" then
                    local nv = remap(e.color, LABEL_KEYS, from, to)
                    e.color = nv
                    pcall(o.set_color, o, nv)
                elseif t == "btn" then
                    local nb  = remap(e.bg, BOX_KEYS, from, to)
                    local nf  = remap(e.fg, LABEL_KEYS, from, to)
                    local nbd = remap(e.bd, LINE_KEYS, from, to)
                    e.bg, e.fg, e.bd = nb, nf, nbd
                    pcall(o.set_style, o, {
                        bg_color     = nb,
                        text_color   = nf,
                        border_color = nbd,
                    })
                elseif t == "items" then
                    local its = e.it
                    for j = 1, #its do
                        local it = its[j]
                        if it.color then it.color = remap(it.color, SHAPE_KEYS, from, to) end
                        if it.fill_color then
                            it.fill_color = remap(it.fill_color, SHAPE_KEYS, from, to)
                        end
                    end
                    pcall(o.set_items, o, its)
                end
            end
        end
    end
    theme._prev = theme.cur
    if log and log.info then log.info("theme", "repaint " .. n) end
    return n
end

-- 页面自己用 airui.shape 画的图元：登记一下，切主题时才能跟着换色
function theme.skin_shape(o, items)
    return skin_put(o, { t = "items", it = items })
end

--------------------------------------------------------------------
-- 基础控件封装
--------------------------------------------------------------------
-- ckey：可选，指定语义键。浅色下 card / white / qr_bg 同为 0xFFFFFF，
-- 按值反查认不出"这是二维码白底"，只能由调用方点名。
function theme.box(parent, x, y, w, h, color, radius, ckey)
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 0 })
    return skin_put(o, { t = "box", color = color or C.card, ck = ckey })
end

-- 半透明底色（html 的 rgba() 底：圆形悬浮按钮 / 芯片 / 开关轨道 / 蒙层）
function theme.box_a(parent, x, y, w, h, color, radius, opa)
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opa or 160, radius = radius or 0 })
    return skin_put(o, { t = "box", color = color, opa = opa or 160 })
end

function theme.box_b(parent, x, y, w, h, color, radius, bcol, bw)
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 0,
        border_color = bcol or C.line, border_width = bw or 1 })
    return skin_put(o, { t = "box", color = color or C.card,
        bd = bcol or C.line, bw = bw or 1 })
end

function theme.circle(parent, x, y, d, color, radius)
    return theme.box(parent, x, y, d, d, color, radius or math.floor(d / 2))
end

-- 文本：调用方给"视觉块"坐标（x,y,w,h），这里换算成单行 label 并垂直居中
-- （AirUI 的 label 是顶部对齐，直接给大 h 会整体偏上）
-- airui 的 label 只认 TEXT_ALIGN_* 数字常量，直接塞 "center" 字符串会被忽略，
-- 全部退化成左对齐（圆盘时钟文字"跑出表盘"就是这个坑）
local function to_align(a)
    if type(a) == "number" then return a end
    if a == "center" then return airui.TEXT_ALIGN_CENTER or 2 end
    if a == "right" then return airui.TEXT_ALIGN_RIGHT or 3 end
    return airui.TEXT_ALIGN_LEFT or 1
end

function theme.txt(parent, x, y, w, h, text, color, size, align)
    size = size or 20
    local lh = math.floor(size * 1.28 + 0.5)
    if h and h > lh then
        y = y + math.floor((h - lh) / 2)
    else
        lh = h or lh
    end
    -- 关键：label 一定要比父容器窄 4px。
    -- 原因：airui 的 container 默认 scrollbar_mode = AUTO，子控件只要和容器
    -- 同宽/同高（box_b 的 1px 边框还会再吃掉 2px 内容区），LVGL 就会画出
    -- 一条圆头滚动条 —— 在界面上看起来就是「方框里有下划线 / 右划线」。
    w = w - 4
    if w < 8 then w = 8 end
    -- font_size 内部会自动切到 hzfont 矢量字库，字号可以任意大
    local o = airui.label({ parent = parent, x = x + 2, y = y, w = w, h = lh,
        text = text or "", color = color or C.text,
        font_size = size, align = to_align(align) })
    return skin_put(o, { t = "label", color = color or C.text })
end

-- 实心/描边按钮（pad=0 保证文字居中不撑开）
function theme.btn(parent, x, y, w, h, text, bg, fg, bcol, bw, radius, on_click)
    local o = airui.button({ parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font_size = 19,
        style = {
            bg_color     = bg or C.card,
            text_color   = fg or C.text,
            border_color = bcol or bg or C.card,
            border_width = bw or 0,
            radius       = radius or 6,
            pad          = 0,
        },
        on_click = on_click })
    return skin_put(o, { t = "btn", bg = bg or C.card, fg = fg or C.text,
        bd = bcol or bg or C.card, bw = bw or 0 })
end

function theme.link(parent, x, y, w, h, text, color, size, on_click)
    local l = theme.txt(parent, x, y, w, h, text, color, size or 17)
    if on_click and l.set_on_click then l:set_on_click(on_click) end
    return l
end

-- 透明点击热区：盖在图标/文字/卡片上面接收触摸（不遮挡画面）
function theme.hit(parent, x, y, w, h, on_click)
    -- 点击层同样要缩 4px：它经常和父容器同宽同高，LVGL 会因此画出滚动条
    w, h = w - 4, h - 4
    if w < 8 then w = 8 end
    if h < 8 then h = 8 end
    local o = airui.container({ parent = parent, x = x + 2, y = y + 2, w = w, h = h,
        color = C.bg, color_opacity = 0, radius = 0 })
    if on_click then
        if o.set_on_click then o:set_on_click(on_click) end
    end
    return o
end

-- 滑块：轨道自己画（8px 圆角灰条），slider 本体背景透明
-- 直接给 slider 的 main 上背景，浅色下会在轨道外面多出一圈"灰方框"，很难看
function theme.slider(parent, x, y, w, val, on_change)
    -- 灰轨要跟 indicator 对齐（slider 的 pad=6 会让橙色进度左右各缩进 6px，
    -- 灰轨从 x 开始画的话，左端就会露出一小截"空缺"）
    theme.box_a(parent, x + 6, y + 6, w - 12, 8, C.track, 4, C.track_opa)
    return airui.slider({
        parent = parent, x = x, y = y, w = w, h = 20,
        min = 0, max = 100, value = val or 0,
        style = {
            bg_opa = 0,                      -- main 透明，只留橙色进度
            bg_color = C.card,               -- 兜底：万一 0 被忽略也是白底不显形
            -- 注意：radius 同时作用于 indicator 和 knob！
            -- 写成 4 会让旋钮变成"方角矩形"，必须给 h/2 才是圆旋钮
            -- h=20 + pad=6 → 轨道 8px、旋钮 20px（= html 的 .track / .knob）
            radius = 10, pad = 6, border_width = 0,
            indicator_color = C.orange, indicator_opa = 255,
            knob_color = C.white, knob_opa = 255,
            knob_border_color = C.track, knob_border_width = 2,
        },
        on_change = on_change,
    })
end

-- 开关（62×34）：轨道 + 可移动圆点；返回轨道、圆点，切换时自己 set_color / set_pos
function theme.switch(parent, x, y, on)
    local track = theme.box_a(parent, x, y, 62, 34,
        on and C.orange or C.track, 17, on and 255 or C.track_opa)
    local dot = theme.circle(parent, x + (on and 31 or 3), y + 3, 28, C.white)
    return track, dot
end

function theme.set_switch(track, dot, x, y, on)
    pcall(track.set_color, track, on and C.orange or C.track,
        on and 255 or C.track_opa)
    pcall(dot.set_pos, dot, x + (on and 31 or 3), y + 3)
end

--------------------------------------------------------------------
-- 页面工厂（单页 exwin，页面内部自行切屏）
--------------------------------------------------------------------
local registry, current_win = {}, nil

function theme.register(idx, mod) registry[idx] = mod end

sys.subscribe("SWITCH_PAGE", function(idx)
    local mod = registry[idx]
    if not mod then return end
    if current_win then
        local w = current_win
        current_win = nil
        pcall(exwin.close, w)
    end
    current_win = mod.open()
end)

function theme.open_page(idx) sys.publish("SWITCH_PAGE", idx) end

function theme.make_page(idx, title, build_fn)
    local M = { idx = idx, title = title }
    local root, timer_id

    local function create_ui()
        theme.skin_reset()          -- 旧控件随 root 一起销毁，登记表要同步清空
        theme._prev = theme.cur     -- 新建的控件本来就是当前主题色
        root = airui.container({ parent = airui.screen, x = 0, y = 0,
            w = theme.W, h = theme.H, color = C.bg })
        local update, interval = build_fn(root)
        if update then
            timer_id = sys.timerLoopStart(update, interval or 1000)
        end
        if exwin.bind_root then pcall(exwin.bind_root, root) end
    end

    function M.rerender()
        if timer_id then sys.timerStop(timer_id) timer_id = nil end
        if root then pcall(root.destroy, root) root = nil end
        create_ui()
    end

    function M.open()
        return exwin.open({
            on_create  = create_ui,
            on_destroy = function()
                if timer_id then sys.timerStop(timer_id) timer_id = nil end
                if root then root:destroy() root = nil end
            end,
        })
    end

    theme.register(idx, M)
    return M
end

--------------------------------------------------------------------
-- 图标：全部 shape 线/圆/矩形绘制（零贴图）
-- 坐标按 100×100 设计稿（= html 里 SVG 的 24 网格 × 100/24），按 s 缩放；端点一律取整
-- 只用 line / circle / rect；所有 line 圆头（方头看起来又硬又糙）
-- 小尺寸（24~34px）一律用"实心 + 少细节"，细节多了会糊成一团
--------------------------------------------------------------------
local function add_line(items, x1, y1, x2, y2, col, w)
    items[#items + 1] = { type = "line",
        x1 = math.floor(x1 + 0.5), y1 = math.floor(y1 + 0.5),
        x2 = math.floor(x2 + 0.5), y2 = math.floor(y2 + 0.5),
        color = col, width = math.max(1, math.floor(w + 0.5)),
        round_start = true, round_end = true }
end

local function add_circle(items, cx, cy, r, col, w, fill)
    items[#items + 1] = { type = "circle",
        cx = math.floor(cx + 0.5), cy = math.floor(cy + 0.5),
        r = math.max(1, math.floor(r + 0.5)),
        color = col, width = math.max(1, math.floor((w or 1) + 0.5)),
        fill = fill and true or false,
        fill_color = fill and col or nil,
        fill_opacity = fill and 255 or nil }
end

local function add_rect(items, x, y, w, h, col, r, lw, fill)
    items[#items + 1] = { type = "rect",
        x = math.floor(x + 0.5), y = math.floor(y + 0.5),
        w = math.max(1, math.floor(w + 0.5)), h = math.max(1, math.floor(h + 0.5)),
        radius = math.floor((r or 0) + 0.5),
        color = col, width = math.max(1, math.floor((lw or 1) + 0.5)),
        fill = fill and true or false,
        fill_color = fill and col or nil,
        fill_opacity = fill and 255 or nil }
end

-- 生成图标图元（kind, s, col, col2）→ items 表
-- 供 theme.icon 创建，也供 shape:set_items 就地换色（rail 高亮 / 布防盾牌变色）
function theme.icon_items(kind, s, col, col2)
    col  = col or C.text
    col2 = col2 or col
    local k  = s / 100
    -- lw 用"100 网格单位"：L/O/R 内部都再乘 k
    local lw = math.max(2, s / 12) / k
    local it = {}
    local function L(x1, y1, x2, y2, c, w)
        add_line(it, x1 * k, y1 * k, x2 * k, y2 * k, c or col, (w or lw) * k)
    end
    local function O(cx, cy, r, c, w)
        add_circle(it, cx * k, cy * k, r * k, c or col, (w or lw) * k, false)
    end
    local function F(cx, cy, r, c)
        add_circle(it, cx * k, cy * k, r * k, c or col, 1, true)
    end
    local function R(rx, ry, rw, rh, c, rr, w, fill)
        add_rect(it, rx * k, ry * k, rw * k, rh * k, c or col,
            (rr or 0) * k, (w or lw) * k, fill)
    end
    local function ARC(cx, cy, r, a0, a1, c, w)
        local n = math.max(3, math.floor(math.abs(a1 - a0) / 9 + 0.5))
        local px, py
        for i = 0, n do
            local a = math.rad(a0 + (a1 - a0) * i / n)
            local xx, yy = cx + r * math.cos(a), cy + r * math.sin(a)
            if i > 0 then L(px, py, xx, yy, c, w) end
            px, py = xx, yy
        end
    end
    local function ELL(cx, cy, rx, ry, a0, a1, c, w)
        local n = math.max(6, math.floor(math.abs(a1 - a0) / 12 + 0.5))
        local px, py
        for i = 0, n do
            local a = math.rad(a0 + (a1 - a0) * i / n)
            local xx, yy = cx + rx * math.cos(a), cy + ry * math.sin(a)
            if i > 0 then L(px, py, xx, yy, c, w) end
            px, py = xx, yy
        end
    end

    if kind == "user" or kind == "user_f" then
        -- 实心人像：24px 下描边会糊，直接实心
        F(50, 31, 18)
        R(15, 58, 70, 36, col, 18, 1, true)
    elseif kind == "shield" then
        -- 粗线盾 + 内部对勾（col2 传底色/白色）
        local w = 9.5
        L(50, 9, 18, 21, col, w)
        L(18, 21, 18, 50, col, w)
        L(18, 50, 50, 90, col, w)
        L(50, 90, 82, 50, col, w)
        L(82, 50, 82, 21, col, w)
        L(82, 21, 50, 9, col, w)
        L(33, 46, 45, 57, col2, 9)
        L(45, 57, 67, 35, col2, 9)
    elseif kind == "grid" then
        R(12, 12, 31, 31, col, 8, 1, true)
        R(57, 12, 31, 31, col, 8, 1, true)
        R(12, 57, 31, 31, col, 8, 1, true)
        R(57, 57, 31, 31, col, 8, 1, true)
    elseif kind == "elevator" then
        R(18, 11, 64, 78, col, 10, 9)
        L(50, 24, 50, 76, col, 8)
        L(33, 37, 50, 20, col, 8)
        L(50, 20, 67, 37, col, 8)
    elseif kind == "volume" then
        -- 三条粗线拼出实心喇叭 + 两道声波
        local w = 17
        L(15, 50, 50, 24, col, w)
        L(50, 24, 50, 76, col, w)
        L(50, 76, 15, 50, col, w)
        ARC(56, 50, 17, -50, 50, col, 8)
        ARC(56, 50, 30, -50, 50, col, 8)
    elseif kind == "phone" or kind == "phone_call" then
        -- 拱形听筒（恢复最初的造型，不再改动）
        ARC(50, 54, 28, 203, 337, col, 16)
        F(25, 65, 12)
        F(75, 65, 12)
    elseif kind == "intercom" then
        -- 对讲机：机身 + 两条格栅 + 喇叭孔（34px 下清晰）
        R(28, 8, 44, 84, col, 12, 7)
        L(38, 30, 62, 30, col, 7)
        L(38, 44, 62, 44, col, 7)
        F(50, 66, 8)
    elseif kind == "chat" then
        -- 气泡：尾巴先画（被气泡压住一半），再画气泡 + 两条文字线
        L(34, 70, 22, 90, col, 16)
        R(8, 16, 84, 60, col, 17, 1, true)
        L(23, 33, 77, 33, col2, 6)
        L(23, 49, 59, 49, col2, 6)
    elseif kind == "eye" then
        -- 杏仁眼：上下弧开口加大，瞳孔加大（原来像一条缝）
        local w = lw * 0.85
        ELL(50, 50, 41, 27, 186, 354, col, w)
        ELL(50, 50, 41, 27, 6, 174, col, w)
        F(50, 50, 13)
    elseif kind == "gear" then
        F(50, 50, 30)                            -- 齿轮盘
        for i = 0, 7 do                          -- 8 个粗齿
            local a = math.rad(i * 45)
            local c, s2 = math.cos(a), math.sin(a)
            L(50 + 26 * c, 50 + 26 * s2, 50 + 39 * c, 50 + 39 * s2, col, 13)
        end
        F(50, 50, 11, col2)                      -- 中心孔（用底色挖）
    elseif kind == "home" then
        local w = 9
        L(50, 12, 10, 46, col, w)
        L(10, 46, 19, 46, col, w)
        L(19, 46, 19, 84, col, w)
        L(19, 84, 44, 84, col, w)
        L(44, 84, 44, 58, col, w)
        L(44, 58, 56, 58, col, w)
        L(56, 58, 56, 84, col, w)
        L(56, 84, 81, 84, col, w)
        L(81, 84, 81, 46, col, w)
        L(81, 46, 90, 46, col, w)
        L(90, 46, 50, 12, col, w)
    elseif kind == "car" then
        R(12, 44, 76, 24, col, 10, 1, true)
        R(25, 27, 50, 22, col, 8, 1, true)
        F(27, 70, 10)
        F(73, 70, 10)
        L(84, 26, 96, 26, col, 6)
        L(84, 38, 93, 38, col, 6)
    elseif kind == "moon" then
        F(46, 50, 32)
        F(65, 37, 28, col2)
    elseif kind == "sun" then
        F(50, 50, 19)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            L(50 + 25 * math.cos(a), 50 + 25 * math.sin(a),
              50 + 39 * math.cos(a), 50 + 39 * math.sin(a), col, 9)
        end
    elseif kind == "bars" then
        R(17, 50, 17, 34, col, 5, 1, true)
        R(42, 28, 17, 56, col, 5, 1, true)
        R(67, 12, 17, 72, col, 5, 1, true)
    elseif kind == "back" then
        L(64, 21, 33, 50, col, 9)
        L(33, 50, 64, 79, col, 9)
    elseif kind == "search" then
        O(45, 45, 24, col, 9)
        L(63, 63, 85, 85, col, 11)
    elseif kind == "lock" then
        R(22, 44, 56, 40, col, 10, 8)
        ARC(50, 44, 15, 180, 360, col, 9)
    elseif kind == "mic" then
        R(40, 8, 20, 44, col, 10, 7)
        ARC(50, 46, 24, 0, 180, col, 8)
        L(50, 70, 50, 87, col, 8)
    elseif kind == "warning" then
        L(50, 14, 11, 84, col, 9)
        L(11, 84, 89, 84, col, 9)
        L(89, 84, 50, 14, col, 9)
        L(50, 40, 50, 60, col, 9)
        F(50, 72, 6)
    elseif kind == "info" then
        O(50, 50, 36, col, 8)
        F(50, 33, 6)
        L(50, 44, 50, 68, col, 9)
    elseif kind == "close" then
        -- × 号（退格键用；"—"字符在 hzfont 里没有字形）
        L(27, 27, 73, 73, col)
        L(73, 27, 27, 73, col)
    elseif kind == "qr" then
        -- 扫码：三个角框 + 右下角点阵
        R(16, 16, 26, 26, col, 3, 7)
        R(58, 16, 26, 26, col, 3, 7)
        R(16, 58, 26, 26, col, 3, 7)
        F(66, 66, 8)
        F(30, 30, 5)
        F(58, 58, 4)
    elseif kind == "cal" then
        -- 会议日程
        R(14, 24, 72, 62, col, 8, 7)
        L(16, 44, 84, 44, col, 7)
        L(32, 12, 32, 32, col, 8)
        L(68, 12, 68, 32, col, 8)
        F(34, 62, 5)
        F(50, 62, 5)
        F(66, 62, 5)
    elseif kind == "clock" then
        O(50, 50, 36, col, 8)
        L(50, 50, 50, 28, col, 8)
        L(50, 50, 68, 58, col, 8)
    elseif kind == "door" then
        -- 门牌：门框 + 把手
        R(22, 10, 56, 80, col, 8, 8)
        F(64, 52, 5)
    elseif kind == "check" then
        L(20, 52, 42, 74, col, 10)
        L(42, 74, 82, 26, col, 10)
    elseif kind == "plus" then
        L(50, 22, 50, 78, col, 9)
        L(22, 50, 78, 50, col, 9)
    end

    return it
end

function theme.icon(parent, x, y, s, kind, col, col2)
    local it = theme.icon_items(kind, s, col, col2)
    if #it == 0 then return nil end
    local o = airui.shape({ parent = parent, x = math.floor(x), y = math.floor(y),
        w = math.floor(s), h = math.floor(s), items = it })
    return skin_put(o, { t = "items", it = it })
end

-- 就地换色（不重建控件）
function theme.set_icon(shape, kind, s, col, col2)
    if not shape then return end
    local it = theme.icon_items(kind, s, col, col2)
    if #it > 0 then
        skin_put(shape, { t = "items", it = it })
        pcall(shape.set_items, shape, it)
    end
end

return theme
