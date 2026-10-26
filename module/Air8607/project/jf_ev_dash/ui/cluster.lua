--[[
@module  cluster
@summary EV DASH - 电动车仪表盘（速度弧 / 电量环 / 功率环 / 里程 / 电耗趋势）
@version 1.0
@date    2026.10.23
@author  江访

=== 画面构成（1024x600，零图片素材）===
  1、主表盘：外径 234，速度弧半径 210、带宽 22，扫角 135°~405°（270°），0~180 km/h
     进度弧是整段一条 arc 图元（单色，跟驾驶模式强调色走、进红区转红），
     弧头配一圈光晕 + 一颗亮点
     150 以上是红区；表内两条细弧反向旋转，做出"电驱能量场"的流动感
  2、左侧两张卡：电量（SOC 环 + 续航 / 电压 / 温度）、里程（ODO / TRIP / AVG / 行程条）
  3、右侧两张卡：功率（输出/回收双向环）、电耗趋势（60 格迷你折线）
  4、顶栏：左转向、近光、READY、时钟、车外温度、远光、右转向
  5、底部：ECO / NORMAL / SPORT 三个驾驶模式，切换同时改强调色与动力学参数

=== 为什么圆环一定要用 arc 图元 ===
弧是"真圆"，不是折线逼近：
  - 折线逼近在弧宽 22px 时，每个顶点都要靠圆头去补，段数不够会数出"珠子"
    （弦长 < 线宽时圆头会凸出到弧外侧），段数够多又是几十个图元的开销；
  - arc 图元由 lv_draw_arc 直出，角度掩膜 + 抗锯齿，任意扫角、任意带宽都是圆滑的，
    两端圆头（rounded）也是几何意义上的半圆。
代价是 arc 的绘制区域是"圆心 ± r"的整框，比一条线贵，所以：
  只有速度弧 / 电量环 / 功率环 / 两条装饰弧用 arc，其余一律 line / circle / rect。

=== 分层与预算 ===
  静态层（外环、刻度、轨道弧、分隔线、READY 药丸）只画一次，约 50 个图元
  动态层每帧 3 个图元：速度弧整段 1 个 arc + 弧头光晕 2 个圆
  四张卡 10Hz 刷新（人眼对卡片跳变不敏感，对速度弧很敏感）
]]
local fx = require "fx"
local T = require "theme"

local M = {}
local C, D = T.c, T.dial
local SW, SH = T.screen.w, T.screen.h

-- ==================== 时间基准 ====================
--[[为什么不能直接把 mcu.ticks() 的差值当毫秒：
tick 的物理长度随平台变化（模拟器 / Air8000 约 1ms，1601 约 20ms），
必须配 mcu.hz() 换算：ms = diff_ticks * 1000 / mcu.hz()。
本工程两条路径：
  1、mcu.ticks2(1) —— 直接给 64 位毫秒（高段、低段两个返回值），
     与 tick 长度无关、可预见时间内不回绕，优先用；
  2、退回 mcu.ticks() + mcu.hz()：对 32 位无符号回绕做补偿，
     并且帧时长要用多帧平均（20ms/tick 的平台上，30ms 一帧会抖成 20/20/40）。]]
local HZ = 1000          -- 每秒 tick 数（mcu.hz() 的返回值，取不到按 1ms/tick）
local HAS_T2 = false     -- mcu.ticks2 是否可用

local function init_time_base()
    --[[注意不能写 type(mcu) ~= "table"：LuatOS 的 mcu 是 rotable，
    type() 返回的是 "userdata"（__index 仍能取到函数）。
    用 type() 判断会让这个函数直接 return —— hz 永远取不到，
    退回"默认 1000 tick/秒"，在 20ms/tick 的平台上 dt 会小 20 倍（动画慢 20 倍）。]]
    if not mcu then return end
    if mcu.ticks2 then
        local ok, h = pcall(mcu.ticks2, 1)
        if ok and type(h) == "number" then
            HAS_T2 = true
        end
    end
    local hz = mcu.hz and mcu.hz()
    if type(hz) == "number" and hz >= 1 then HZ = hz end
    --[[把这台机器实际的时间分辨率打出来：
    ticks2 走 64 位高精度计数器（毫秒级）；否则 tick 一格就是 1000/hz 毫秒。]]
    local res = 1
    if not HAS_T2 then
        res = math.floor(1000 / HZ + 0.5)
        if res < 1 then res = 1 end
    end
    log.info("ev", string.format("时间基准 ticks2=%s mcu.hz()=%d 分辨率≈%dms 平均窗口=%d帧",
        tostring(HAS_T2), HZ, res, (HAS_T2 or HZ >= 200) and 4 or 8))
end

-- 读一次时钟：ticks2 时返回"毫秒"，否则返回原始 tick
local function read_tick()
    if HAS_T2 then
        local h, l = mcu.ticks2(1)
        return h * 1000000 + l
    end
    if mcu and mcu.ticks then return mcu.ticks() end
    return nil
end

-- 两个 tick 之差 → 毫秒
local function tick_ms(d)
    if HAS_T2 then return d end
    return d * 1000 / HZ
end

-- 差值回绕补偿：ticks() 是 32 位无符号，Lua 减法会出负数
local function tick_delta(now, prev)
    local d = now - prev
    if d < 0 then
        if HAS_T2 then
            d = 0
        else
            d = d + 4294967296
        end
    end
    return d
end

-- ==================== 动态图层范围 ====================
--[[动态层（每帧重画）只覆盖表盘本身，不再整屏失效。
1024x600 整屏失效一次就是 61 万像素要重绘，真机上帧率直接掉到个位数；
缩到表盘 472x472（外框半径 234 + 2px 余量）后，每帧重绘面积只有 1/3，
而且不会连带重画左右四张卡与顶栏文字。
左右边界要落在卡片之外：246..278 是空档，748..768 也是。]]
local DIAL = { x = D.cx - 236, y = D.cy - 236, w = 472, h = 472 }

-- 顶栏指示灯拆成左右两个小图层，只在灯光/转向/闪烁状态变化时重画
local IND_L = { x = 46, y = 8, w = 212, h = 44 }
local IND_R = { x = 878, y = 8, w = 136, h = 44 }

-- ==================== 小工具 ====================
local function lbl(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h, text = text,
        font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local o    -- 全部运行期状态（单屏仪表，不需要多页面结构）
local draw_indicators   -- 前置声明：M.build() 收尾时要先画一次指示灯
local draw_cards        -- 前置声明：M.build() 收尾时要先铺一次四张卡

--[[文本缓存写回
LVGL 每次 set_text 都要重新排版文本，1 秒 30 次是纯浪费。
这里只在值真的变了才写。]]
local function upd(key, node, v)
    if o.txt[key] ~= v then
        o.txt[key] = v
        node:set_text(v)
    end
end

-- 进度 0..1 → 扫角（度）
local function sweep(t, a0, a1)
    return a0 + fx.clamp(t, 0, 1) * (a1 - a0)
end

-- 车速 → 扫角（度）
local function ang(v)
    return sweep(v / D.vmax, D.a0, D.a1)
end

-- ==================== 静态层 ====================
--[[静态层只画一次（1024x600 全屏）。凡是"不随时间连续变化"的东西都放这里。
注意：放静态层只省 Lua 侧开销，**渲染面积照旧**——只要它在表盘脏区里，
每帧还是会跟着重画一遍。弧一律走 shape 组件的原生 arc 图元
（0 度在 3 点钟方向、顺时针增大，起止角相差 360 度即画整圆），
r 按带宽中心线给，fx 的 P:arc 内部补半个带宽换算成 LVGL 的外半径。]]
local function build_static()
    local P = fx.pool()
    local cx, cy, R, Ra, Rw = D.cx, D.cy, D.R, D.Ra, D.Rw
    P:reset()

    --[[底噪光环：几圈极低透明度的同心环，比渐变图省事，
    在近黑底上能形成"屏幕自身在发光"的错觉。
    静态层里的弧可以用原生 arc：它的绘制区域虽然还是整圆 bbox，
    但会被"脏区"裁掉，而现在的脏区只有弧头那一小块（30x30 左右）。]]
    P:ring(cx, cy, R, 0x16232F, 1, 210)
    P:ring(cx, cy, R - 6, 0x101A24, 1, 160)
    P:ring(cx, cy, R - 34, 0x0C141C, 1, 120)
    P:ring(cx, cy, 120, 0x111B26, 1, 150)

    --[[中心辉光：2 层极低透明度的实心圆。
    实心圆是按 bbox 逐行填充的，6 层 ≈ 19 万像素/帧，真机上是纯浪费；
    2 层在近黑底上已经能看出软衰减。颜色写死：跟强调色走的话每次切模式
    都要重建静态层（整屏重绘），而这个透明度下青/绿/品红的差别看不出来。]]
    P:dot(cx, cy, 118, 0x0B2A32, 9)
    P:dot(cx, cy, 90, 0x0B2A32, 12)

    --[[速度轨道：一整条暗弧，进度弧盖在上面。
    两端圆头：平头切口带抗锯齿锯齿，放大看就是"粗糙的斜切"；
    轨道/红区/进度弧的真端头全部圆头，端帽互相对齐才像一条完整的弧。]]
    P:arc(cx, cy, Ra, D.a0, D.a1, 0x121D29, Rw, 255, true)
    -- 轨道内外各一条收边细弧，弧带看起来才"嵌"在表盘里
    P:arc(cx, cy, Ra + Rw / 2 + 4, D.a0, D.a1, 0x1E2B3A, 1, 220, true)
    P:arc(cx, cy, Ra - Rw / 2 - 4, D.a0, D.a1, 0x1E2B3A, 1, 160, true)

    --[[红区：只跟表底 / 红区起点有关，画在进度弧之下。
    起点也用圆头：红区起点恰好落在 360 度（3 点钟），
    平头起始与深蓝轨道之间是一条硬直线，看起来像弧带断开；
    圆头把这道缝包成圆角过渡，末端 405 度的圆帽也和轨道对齐。]]
    P:arc(cx, cy, Ra, ang(D.vred), ang(D.vmax), C.red, Rw, 70, true)

    -- 刻度：小刻度短而暗，大刻度长而亮
    local v = 0
    while v <= D.vmax do
        local a = math.rad(ang(v))
        local ca, sa = math.cos(a), math.sin(a)
        local major = (v % D.major == 0)
        local r0 = Ra - Rw / 2 - 6
        local r1 = major and (r0 - 11) or (r0 - 5)
        P:line(cx + ca * r0, cy + sa * r0, cx + ca * r1, cy + sa * r1,
            major and 0x5E7288 or 0x2E3D4F, major and 2 or 1, major and 235 or 160, true)
        v = v + D.minor
    end

    -- 顶栏分隔线（底部分隔线由卡片与模式键自己界定，不再画）
    P:line(24, 56, SW - 24, 56, 0x16212D, 1, 190)

    -- READY 药丸：淡强调色底 + 描边，文字由 label 覆盖上去
    P:box(232, 15, 96, 28, C.normal, 26, 14)
    P:frame(232, 15, 96, 28, C.normal, 1, 90, 14)

    P:finish()
    o.static_shape:set_items(P.items)

    -- 刻度数字：位置按角度算好，一次性摆上去（label 不能旋转，所以只放数字）
    local Rl = Ra - Rw / 2 - 44
    local v2 = 0
    while v2 <= D.vmax do
        local a = math.rad(ang(v2))
        local lx = cx + math.cos(a) * Rl - 17
        local ly = cy + math.sin(a) * Rl - 10
        local col = (v2 >= D.vred) and C.red or C.dim
        lbl(o.root, math.floor(lx), math.floor(ly), 34, 20,
            tostring(v2), T.f.sub, col, airui.TEXT_ALIGN_CENTER)
        v2 = v2 + D.major
    end
end

-- ==================== 卡片底板 ====================
--[[卡片 = "纯图元 + 文字"，故意不用 container
container 就是 lv_obj_create，默认带 LV_OBJ_FLAG_SCROLLABLE：
只要子对象包围盒超出内容区一点点（描边 1px、字体行高比给的高 1px……），
LVGL 就会在右/下画滚动条 —— 真机上表现为"卡片里多一圈方角细框"。
shape 的 C 代码硬编码了 lv_obj_remove_flag(SCROLLABLE / CLICKABLE)，
任何情况下都不会画出滚动条，所以让它兼任卡片底板。

注意：不要在 shape 上挂自定义字段（userdata 没有 __newindex，赋值直接抛错退出 VM）。
]]
local function card(geo)
    local s = airui.shape({
        parent = o.root, x = geo.x, y = geo.y, w = geo.w, h = geo.h, items = {},
    })
    if not s then
        log.error("ev", "卡片 shape 创建失败", geo.x, geo.y)
    end
    return s
end

--[[卡片底板：圆角填充 + 1px 描边 + 顶部高光
C 层画矩形用的是 x2 = x + w（含端点），所以宽高各减 1 才是"正好铺满 shape"，
否则右下各多 1px 会被图层裁掉，描边看起来缺一条边。]]
local function panel_bg(P, w, h, tint)
    P:box(0, 0, w - 1, h - 1, C.panel, 245, 16)
    P:frame(0, 0, w - 1, h - 1, C.line, 1, 255, 16)
    P:line(18, 2, w - 19, 2, tint, 1, 120, true)
end

local CW = T.cards.a.w - 32     -- 卡片内容宽度

-- ==================== 卡片里的环 ====================
--[[小环：轨道 + 进度弧 + 弧头光点
@param table P 图元池
@param number cx,cy 环心（相对卡片）
@param number t 进度 0..1
@param number color 进度色
@param bool ccw 反向（功率回收用，从起点逆时针长出来）
]]
local function ring_gauge(P, cx, cy, t, color, ccw)
    local r, w = T.ring.r, T.ring.w
    P:ring(cx, cy, r, 0x15202C, w, 255)
    P:ring(cx, cy, r + w / 2 + 3, 0x1E2B3A, 1, 170)
    t = fx.clamp(t, 0, 1)
    if t > 0.002 then
        local a0 = T.ring.a0
        local a1 = ccw and (a0 - (T.ring.a1 - T.ring.a0) * t) or (a0 + (T.ring.a1 - T.ring.a0) * t)
        P:arc(cx, cy, r, math.min(a0, a1), math.max(a0, a1), color, w, 255, true)
        local e = math.rad(a1)
        P:dot(cx + math.cos(e) * r, cy + math.sin(e) * r, 5, fx.shade(color, 0.55), 235)
    end
end

-- ==================== 构建卡片 ====================
local function build_cards()
    -- ---------- 电量卡 ----------
    local ra = card(T.cards.a)
    o.sh_a = ra
    lbl(ra, 16, 10, CW, 18, "电量 BATTERY", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_soc = lbl(ra, 20, 71, 76, 26, "78%", T.f.val, C.amber, airui.TEXT_ALIGN_CENTER)
    o.lb_range = lbl(ra, 108, 50, 112, 30, "412 km", T.f.val, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(ra, 108, 82, 112, 16, "续航 RANGE", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    lbl(ra, 108, 104, 112, 18, "电压 396 V", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    -- 底部三格小指标
    lbl(ra, 16, 138, 60, 16, "电池温度", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_bt = lbl(ra, 16, 154, 60, 20, "32 C", T.f.sub, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(ra, 88, 138, 60, 16, "健康度", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_soh = lbl(ra, 88, 154, 60, 20, "98%", T.f.sub, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(ra, 160, 138, 60, 16, "剩余充电", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_chg = lbl(ra, 160, 154, 60, 20, "6.2 h", T.f.sub, C.txt, airui.TEXT_ALIGN_LEFT)

    -- ---------- 里程卡 ----------
    local rb = card(T.cards.b)
    o.sh_b = rb
    lbl(rb, 16, 10, CW, 18, "里程 ODO", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_odo = lbl(rb, 16, 28, CW, 34, "12345.6 km", T.f.num, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(rb, 16, 74, 96, 16, "TRIP", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_trip = lbl(rb, 16, 90, 96, 26, "128.4", T.f.val, C.normal, airui.TEXT_ALIGN_LEFT)
    lbl(rb, 124, 74, 96, 16, "AVG", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_avg = lbl(rb, 124, 90, 96, 26, "0", T.f.val, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(rb, 16, 130, CW, 16, "本次行程 TRIP", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    lbl(rb, 16, 186, CW, 16, "最长续航 520 km", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_wear = lbl(rb, 16, 206, CW, 16, "电池循环 128 次", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)

    -- ---------- 功率卡 ----------
    local rc = card(T.cards.c)
    o.sh_c = rc
    lbl(rc, 16, 10, CW, 18, "功率 POWER", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_kw = lbl(rc, 132, 71, 84, 26, "0", T.f.val, C.txt, airui.TEXT_ALIGN_CENTER)
    lbl(rc, 16, 52, 108, 18, "功率 kW", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_regen = lbl(rc, 16, 82, 108, 16, "回收 0.0 kW", T.f.mini, C.green, airui.TEXT_ALIGN_LEFT)
    o.lb_motor = lbl(rc, 16, 104, 108, 18, "电机 34 C", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    lbl(rc, 16, 138, 60, 16, "效率", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_eff = lbl(rc, 16, 154, 60, 20, "94%", T.f.sub, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(rc, 88, 138, 60, 16, "扭矩", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_tq = lbl(rc, 88, 154, 60, 20, "0 Nm", T.f.sub, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(rc, 160, 138, 60, 16, "能耗", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_cons = lbl(rc, 160, 154, 68, 20, "0.0", T.f.sub, C.txt, airui.TEXT_ALIGN_LEFT)

    -- ---------- 电耗趋势卡 ----------
    local rd = card(T.cards.d)
    o.sh_d = rd
    lbl(rd, 16, 10, CW, 18, "电耗 CONSUMPTION", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_cons2 = lbl(rd, 16, 28, 120, 40, "0.0", T.f.big, C.violet, airui.TEXT_ALIGN_LEFT)
    lbl(rd, 16, 68, CW, 16, "kWh/100km", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_maxcons = lbl(rd, 16, 196, 96, 16, "MAX 0.0", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_avgcons = lbl(rd, 108, 196, 96, 16, "AVG 0.0", T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)
end

-- ==================== 中央文字 ====================
--[[必须在动态图元层之后创建：z 序按创建顺序，车速数字要压在装饰弧之上。
三行都落在半径 120 以内的圆里：96pt 三位数约 170x80，放得下。]]
local function build_center()
    o.lb_speed = lbl(o.root, D.cx - 170, D.cy - 66, 340, 96, "0",
        T.f.speed, C.txt, airui.TEXT_ALIGN_CENTER)
    o.lb_unit = lbl(o.root, D.cx - 60, D.cy + 30, 120, 22, "km/h",
        T.f.body, C.dim, airui.TEXT_ALIGN_CENTER)
    o.lb_gear = lbl(o.root, D.cx - 40, D.cy + 54, 80, 32, "D",
        T.f.num, C.normal, airui.TEXT_ALIGN_CENTER)
end

-- ==================== 顶栏 / 底部 ====================
local function build_bars()
    o.lb_clock = lbl(o.root, 432, 10, 160, 36, "--:--", T.f.val,
        C.txt, airui.TEXT_ALIGN_CENTER)
    lbl(o.root, 232, 20, 96, 20, "READY", T.f.mini, C.normal, airui.TEXT_ALIGN_CENTER)
    lbl(o.root, 700, 16, 96, 24, "26 C", T.f.sub, C.dim, airui.TEXT_ALIGN_RIGHT)

    lbl(o.root, 24, 558, 220, 18, "按住表盘 加速 / 松手 滑行", T.f.mini,
        C.dim2, airui.TEXT_ALIGN_LEFT)
    lbl(o.root, 780, 558, 220, 18, "点击模式键 / 顶栏灯光", T.f.mini,
        C.dim2, airui.TEXT_ALIGN_RIGHT)

    --[[驾驶模式按键：同样用 shape 兜底，不用 container
    点击靠 on_touch 的热区判定，不依赖 LVGL 的 on_click，
    这样文字比按钮宽也不会冒出滚动条。]]
    local n = #T.modes
    local total = n * T.chip.w + (n - 1) * T.chip.gap
    local x0 = math.floor((SW - total) / 2)
    o.chips = {}
    for i, m in ipairs(T.modes) do
        local x = x0 + (i - 1) * (T.chip.w + T.chip.gap)
        local s = airui.shape({
            parent = o.root, x = x, y = T.chip.y, w = T.chip.w, h = T.chip.h,
            items = {},
        })
        local t = lbl(s, 0, 11, T.chip.w, 22, m.id, T.f.body,
            C.dim, airui.TEXT_ALIGN_CENTER)
        o.chips[i] = { shape = s, label = t }
    end
    M.sync_chips()
end

-- ==================== 速度弧 ====================
--[[整段一条弧：一个 shape + 一条 shape 组件的原生 arc 图元
arc 由 lv_draw_arc 直出（角度掩膜 + 抗锯齿），圆度和两端圆头都是几何意义上的真圆，
既没有折线逼近的"珠子"，也没有分块拼接的接缝与按块量化的色阶。

代价是明确的：`set_items` 会让整个 shape 的 bbox 失效，每帧都要把表盘这一块
（DIAL 472x472，约 22 万像素）重画一遍 —— 底图 + 轨道 + 刻度 + 数字 + 弧带全部重来。
本工程选择"整段"，用这部分帧率换掉分块那套接缝外扩、换色扩散预算、弧头跨块的复杂度。

颜色整段同色：跟驾驶模式的强调色走，车速进红区后整段向红过渡。
沿弧长做渐变要十几条 arc 拼色，又会回到"拼"的老路上去。

⚠️ 不要用"一个小 shape + set_pos 跟着弧头跑"来做光点：LVGL 的对象位置变更
比重新 set_items 贵得多，实测 PC 上 26fps 直接掉到 6fps。亮点直接画在弧的同一个 shape 里。]]
local ARC = fx.pool()

--[[每帧：把速度弧整段推进到当前角度
@param number v 车速 km/h]]
local function update_arc(v)
    local P = ARC
    local ox, oy = DIAL.x, DIAL.y
    P:reset()
    --[[车速太低就不画：起止角相同的 arc 本身不画图，
    但 0.4 km/h 以下扫角不足 1 度，硬画只是一个圆头疙瘩。]]
    if v > 0.4 then
        local r, w = D.Ra, D.Rw
        local a = ang(v)
        local hot = fx.clamp((v - D.vred) / (D.vmax - D.vred), 0, 1)
        local col = fx.mix(o.accent, C.red, hot)
        -- 两端圆头：平头切口放大看是粗糙的斜切，端帽要和轨道对齐
        P:arc(D.cx - ox, D.cy - oy, r, D.a0, a, col, w, 255, true)
        -- 弧头亮点：和弧同一个 shape，弧头走到哪亮点跟到哪，天然同步
        local hx = D.cx + math.cos(math.rad(a)) * r - ox
        local hy = D.cy + math.sin(math.rad(a)) * r - oy
        if (o.quality or 2) >= 1 then
            P:dot(hx, hy, 13, col, 45)
        end
        P:dot(hx, hy, 6, fx.shade(col, 0.7), 245)
    end
    o.narc = P:finish()
    o.arc_shape:set_items(P.items)
end

-- ==================== 构建整屏 ====================
function M.build()
    o = {
        root = nil,
        txt = {},
        speed = 0, speed_t = 0, prev_t = 0,
        throttle = false,
        boot = 0, booting = true,
        mode = T.mode_default,
        accent = T.modes[T.mode_default].color,
        battery = 78.0, motor_t = 34.0, batt_t = 28.0,
        power = 0, regen = 0, torque = 0,
        cons = 0, cons_max = 0, cons_sum = 0, cons_n = 0,
        odo = 12345.6, trip = 128.4, avg = 0, vmax_seen = 0,
        turnL = false, turnR = false, light = true, high = false,
        blink = true, spin = 0, ready = 0,
        spark = {}, spark_n = 60, spark_acc = 0,
        demo = false, demo_t = 0, idle = 0,
    }

    o.root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    -- 先建静态图元层，再建卡片与文字，最后建动态图元层
    o.static_shape = airui.shape({
        parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {},
    })

    build_static()
    build_cards()
    build_bars()

    --[["杂项"动态层（装饰弧 / 模式涟漪）：
    这两样只有 q>=2 或切换模式时才需要，平时整层不刷新，等于零开销。]]
    o.dyn_shape = airui.shape({
        parent = o.root, x = DIAL.x, y = DIAL.y, w = DIAL.w, h = DIAL.h, items = {},
    })
    -- 速度弧：整段一条 arc + 弧头亮点，和杂项层同一块脏区
    o.arc_shape = airui.shape({
        parent = o.root, x = DIAL.x, y = DIAL.y, w = DIAL.w, h = DIAL.h, items = {},
    })
    -- 顶栏指示灯（两个小图层，状态变化时才重画）
    o.sh_ind_l = airui.shape({
        parent = o.root, x = IND_L.x, y = IND_L.y, w = IND_L.w, h = IND_L.h, items = {},
    })
    o.sh_ind_r = airui.shape({
        parent = o.root, x = IND_R.x, y = IND_R.y, w = IND_R.w, h = IND_R.h, items = {},
    })
    -- 中央车速数字再往后建，压在装饰弧之上
    build_center()
    draw_indicators()

    for i = 1, o.spark_n do o.spark[i] = 0 end
    -- 首帧把四张卡一次铺好（之后按 card_ms 轮转，一次只刷一张）
    draw_cards(nil)

    airui.touch_subscribe(function(state, x, y)
        M.on_touch(state, x, y)
    end)
    log.info("ev", "仪表盘构建完成")
end

-- ==================== 模式 ====================
function M.set_mode(i)
    if not o or i == o.mode then return end
    o.mode = i
    o.flash = 1                  -- 切模式时打一圈涟漪
    M.sync_chips()
    log.info("ev", "驾驶模式 " .. T.modes[i].id)
end

--[[模式键重绘：选中态 = 强调色淡底 + 强调色描边，未选中 = 卡片底 + 灰描边
只在切模式时执行一次，用临时图元池画完就丢，不占每帧预算。]]
function M.sync_chips()
    local P = fx.pool()
    for i, ch in ipairs(o.chips) do
        local m = T.modes[i]
        local on = (i == o.mode)
        P:reset()
        P:box(0, 0, T.chip.w - 1, T.chip.h - 1, on and m.color or C.panel, on and 40 or 245, 13)
        P:frame(0, 0, T.chip.w - 1, T.chip.h - 1, on and m.color or C.line, 1, 255, 13)
        if on then
            P:line(24, 2, T.chip.w - 25, 2, m.color, 1, 160, true)
        end
        P:finish()
        ch.shape:set_items(P.items)
        ch.label:set_color(on and m.color or C.dim)
    end
end

local function hit(x, y, gx, gy, gw, gh)
    return x >= gx and x < gx + gw and y >= gy and y < gy + gh
end

-- ==================== 触摸 ====================
--[[触摸状态常量按 C 层枚举兜底
AIRUI_TOUCH_STATE_DOWN = 1 / HOLD = 2 / UP = 3。
万一某个固件版本的 airui 表里没导出 TP_DOWN，直接比 nil 会让"整个界面点不动"。]]
local TP_DOWN = airui.TP_DOWN or 1
local TP_UP = airui.TP_UP or 3

--[[命中顺序：先判按键（顶栏四个热区 + 底部三个模式键），最后才把"表盘内"当油门。
否则按在模式键上会被当成加速。]]
function M.on_touch(state, x, y)
    if not o or type(x) ~= "number" or type(y) ~= "number" then return end

    if state == TP_DOWN then
        -- 顶栏：左转向 / 近光 / 远光 / 右转向（指示灯是独立图层，改完打脏标记）
        if hit(x, y, 18, 4, 76, 50) then
            o.turnL = not o.turnL
            o.ind_dirty = true
            return
        elseif hit(x, y, 104, 4, 56, 50) then
            o.light = not o.light
            o.ind_dirty = true
            return
        elseif hit(x, y, 864, 4, 56, 50) then
            o.high = not o.high
            o.ind_dirty = true
            return
        elseif hit(x, y, 930, 4, 76, 50) then
            o.turnR = not o.turnR
            o.ind_dirty = true
            return
        end
        -- 底部模式键
        local n = #T.modes
        local total = n * T.chip.w + (n - 1) * T.chip.gap
        local x0 = math.floor((SW - total) / 2)
        for i = 1, n do
            local cx = x0 + (i - 1) * (T.chip.w + T.chip.gap)
            if hit(x, y, cx, T.chip.y, T.chip.w, T.chip.h) then
                M.set_mode(i)
                return
            end
        end
        -- 表盘内 → 加速（只有这里才算"用户在驾驶"，才打断演示巡游）
        local dx, dy = x - D.cx, y - D.cy
        if dx * dx + dy * dy <= D.R * D.R then
            o.throttle = true
            o.idle = 0
        end
    elseif state == TP_UP then
        local was = o.throttle
        o.throttle = false
        if was then o.idle = 0 end
    end
end

-- ==================== 演示曲线 ====================
--[[没有真实整车数据时，让仪表自己"跑起来"
24 秒一个循环：起步 → 巡航（正弦 + 噪声叠加）→ 滑行停车 → 再起步。
所有幅度都由当前档位的 vmax 缩放，所以切到 SPORT 整体波动立刻变大，切 ECO 立刻变小。
真机演示时没人会一直按着屏幕，速度停在 0 会让整个界面看起来像死机。]]
local function demo_target(m)
    local ph = o.demo_t % 24
    local hold = 0
    if ph > 19 then hold = fx.clamp((ph - 19) / 2.0, 0, 1) end
    if ph < 1.5 then hold = fx.clamp(1 - ph / 1.5, 0, 1) end
    local cruise = 0.56
        + 0.20 * math.sin(o.demo_t * 0.78)
        + 0.10 * math.sin(o.demo_t * 2.05 + 1.3)
        + 0.10 * fx.noise1(o.demo_t * 1.5)
    cruise = fx.clamp(cruise, 0.12, 0.95)
    return m.vmax * cruise * (1 - hold)
end

-- ==================== 每帧：动力学 ====================
local function physics(dt, t)
    local m = T.modes[o.mode]

    o.idle = o.idle + dt
    o.demo_t = o.demo_t + dt
    o.demo = (not o.throttle) and o.idle > 3

    if o.booting then
        -- ---- 上电自检：速度弧扫一圈（0 → 表底 → 0）----
        o.boot = o.boot + dt
        local b = o.boot
        if b < 0.6 then
            o.speed = fx.ease_out(b / 0.6) * D.vmax
            o.power = fx.ease_out(b / 0.6) * T.power_max * 0.6
        elseif b < 1.1 then
            local k = 1 - fx.ease_in_out((b - 0.6) / 0.5)
            o.speed = k * D.vmax
            o.power = k * T.power_max * 0.6
        else
            o.speed = 0
            o.power = 0
            if b >= 1.5 then
                o.booting = false
                o.speed_t = 0
                o.idle = 99          -- 自检一结束就进入演示，别让速度停在 0
                log.info("ev", "自检完成，进入演示巡游")
            end
        end
        o.regen = 0
    else
        -- ---- 目标车速：手动加速 / 演示曲线 / 滑行 ----
        local target
        if o.throttle then
            target = m.vmax
        elseif o.demo then
            target = demo_target(m)
        else
            target = 0
        end
        -- 按档位加减速度做速率限制，弧才不跳变
        local rate = (target > o.speed_t) and m.acc or m.dec
        local d = target - o.speed_t
        local step = rate * dt
        if math.abs(d) <= step then
            o.speed_t = target
        else
            o.speed_t = o.speed_t + (d > 0 and step or -step)
        end
        o.speed = fx.approach(o.speed, o.speed_t, 0.35, dt)

        -- 功率：正=输出，负=回收。用速度变化率估一个像样的 kW
        local acc = (o.speed_t - o.prev_t) / math.max(dt, 0.001)
        local kw = acc * (0.06 + o.speed / 300) * 3.0
        o.power = fx.approach(o.power, kw > 0 and kw or 0, 0.18, dt)
        o.regen = fx.approach(o.regen, kw < 0 and -kw or 0, 0.18, dt)
    end
    o.prev_t = o.speed_t

    -- ---- 电量 / 续航：耗电跟功率相关，回收时回一点 ----
    if not o.booting then
        local drain = (0.0015 + o.power * 0.0009 - o.regen * 0.0006) * dt
        o.battery = fx.clamp(o.battery - drain, 0, 100)
    end

    -- ---- 电机 / 电池温度：功率越大越热，缓慢回落 ----
    o.motor_t = fx.approach(o.motor_t, 33 + o.power * 0.34 + o.speed * 0.035, 0.03, dt)
    o.batt_t = fx.approach(o.batt_t, 27 + o.power * 0.10, 0.02, dt)

    -- ---- 扭矩：功率 / 转速（车速低时扭矩大，这是电机的特征）----
    o.torque = fx.approach(o.torque, o.power * 6.2 / (0.6 + o.speed / 30), 0.12, dt)

    -- ---- 电耗：功率 / 车速 × 45 ≈ kWh/100km ----
    if o.speed > 8 then
        o.cons = fx.approach(o.cons, o.power / o.speed * 45, 0.05, dt)
    else
        o.cons = fx.approach(o.cons, 0, 0.05, dt)
    end

    -- ---- 里程 ----
    --[[自检扫针期间不算里程
    否则开机会白涨 0.07 km 里程、MAX 也会被自检刷成表底。]]
    if not o.booting and o.speed > 0.5 then
        local km = o.speed * dt / 3600
        o.odo = o.odo + km
        o.trip = o.trip + km
        o.avg = fx.approach(o.avg, o.speed, 0.004, dt)
        if o.speed > o.vmax_seen then o.vmax_seen = o.speed end
        if o.cons > o.cons_max then o.cons_max = o.cons end
        o.cons_sum = o.cons_sum + o.cons * dt
        o.cons_n = o.cons_n + dt
    end

    -- ---- 强调色跟随模式平滑过渡（不是硬切）----
    o.accent = fx.mix(o.accent, m.color, 0.10)

    -- ---- 转向灯闪烁相位（1.25Hz）----
    o.blink = (t % 0.8) < 0.42

    -- ---- 装饰弧的自转角（车速越高转越快）----
    o.spin = o.spin + dt * (14 + o.speed * 1.35)

    -- ---- READY 指示呼吸 ----
    o.ready = 0.5 + 0.5 * math.sin(t * 2.2)

    -- ---- 电耗趋势采样（每 0.4s 一格，60 格约 24 秒）----
    o.spark_acc = o.spark_acc + dt
    if o.spark_acc >= 0.4 and not o.booting then
        o.spark_acc = 0
        for i = 2, o.spark_n do o.spark[i - 1] = o.spark[i] end
        o.spark[o.spark_n] = fx.clamp(o.cons / 30, 0, 1)
    end

    if o.flash then
        o.flash = o.flash - dt * 1.6
        if o.flash <= 0 then o.flash = nil end
    end
end

-- ==================== 每帧：表盘动态层 ====================
--[[每帧的表盘刷新：
1、速度弧整段一条 arc（连同弧头亮点），每帧一次 set_items；
2、"杂项层"（装饰弧 / 涟漪）单独一个 472x472 的图层，
   q<2 且没有涟漪时整层不刷新 —— 平时零开销。]]
local DYN = fx.pool()

-- 杂项层：装饰弧 + 模式涟漪
local function draw_misc()
    local q = o.quality or T.perf.quality
    --[[只有 q>=2 才动这一层：它一刷新就是整块 472x472（22 万像素），
    真机上等于把刚才省下来的面积又还回去。
    q<2 时切模式的"涟漪"取消，但强调色变化会让所有已点亮的弧块整体换色，
    仍然有"扫过去"的观感。]]
    local need = (q >= 2)
    if not need then
        if o.misc_on then
            -- 降档后把这层清空一次，之后就不再动它
            o.misc_on = false
            local P = DYN
            P:reset()
            o.ndyn = P:finish()
            o.dyn_shape:set_items(P.items)
        end
        return
    end
    o.misc_on = true

    local P = DYN
    local cx, cy = D.cx - DIAL.x, D.cy - DIAL.y
    local acc = o.accent
    P:reset()

    --[[旋转装饰弧（能量场，仅 q>=2）：原生 arc，起止角可以越过 360
    （s1+72 最大到 432），C 层 airui_shape_prepare_arc_angles 会折算。]]
    if q >= 2 then
        local s1 = o.spin % 360
        local s2 = (-o.spin * 0.72) % 360
        P:arc(cx, cy, D.deco_r[1], s1, s1 + 72, acc, 3, 90, true)
        P:arc(cx, cy, D.deco_r[2], s2, s2 + 46, C.violet, 2, 70, true)
    end

    -- 模式切换涟漪：整圆即"起止角相差 360 度"，走 arc 的整圈路径
    if o.flash then
        local r = 118 + (1 - o.flash) * 96
        P:arc(cx, cy, math.floor(r), 0, 360, acc, 2, math.floor(170 * o.flash), false)
    end

    o.ndyn = P:finish()
    o.dyn_shape:set_items(P.items)
end

local function draw_dial()
    update_arc(o.speed)
    draw_misc()
end

-- ==================== 指示灯（状态变化才画） ====================
--[[顶栏指示灯单独放两个小图层：它们平时是不变的，
塞进每帧重画的表盘层里等于白画；而转向灯 1.25Hz 闪烁只需要动这两小块。]]
local IDL, IDR = fx.pool(), fx.pool()

-- 注意这里是赋值不是 local function：前面已有前置声明，
-- 再写 local 会声明一个新的局部变量，M.build() 里的那个仍然是 nil
function draw_indicators()
    local on_op, off_op = 255, 26
    local blink_op = o.blink and on_op or off_op

    -- ---------- 左组：左转向 + 近光 + READY 呼吸点 ----------
    local P = IDL
    local ox, oy = IND_L.x, IND_L.y
    local function L(x1, y1, x2, y2, col, w, op)
        P:line(x1 - ox, y1 - oy, x2 - ox, y2 - oy, col, w, op, true)
    end
    P:reset()
    local lop = o.turnL and blink_op or off_op
    L(65, 19, 52, 28, C.green, 3, lop)
    L(52, 28, 65, 37, C.green, 3, lop)
    L(53, 28, 67, 28, C.green, 3, lop)
    local hop = o.light and on_op or off_op
    L(118, 21, 130, 21, C.green, 3, hop)
    L(118, 35, 130, 35, C.green, 3, hop)
    L(118, 21, 118, 35, C.green, 3, hop)
    L(134, 25, 146, 28, C.green, 2, hop)
    L(134, 31, 146, 28, C.green, 2, hop)
    P:dot(246 - ox, 29 - oy, 4, C.normal, math.floor(90 + 165 * o.ready))
    P:finish()
    o.sh_ind_l:set_items(P.items)

    -- ---------- 右组：远光 + 右转向 ----------
    P = IDR
    ox, oy = IND_R.x, IND_R.y
    local function R(x1, y1, x2, y2, col, w, op)
        P:line(x1 - ox, y1 - oy, x2 - ox, y2 - oy, col, w, op, true)
    end
    P:reset()
    local rop = o.turnR and blink_op or off_op
    R(959, 19, 972, 28, C.green, 3, rop)
    R(972, 28, 959, 37, C.green, 3, rop)
    R(971, 28, 957, 28, C.green, 3, rop)
    local xop = o.high and on_op or off_op
    R(884, 21, 896, 21, C.blue, 3, xop)
    R(884, 35, 896, 35, C.blue, 3, xop)
    R(884, 21, 884, 35, C.blue, 3, xop)
    for i = 0, 2 do
        R(900, 28 - 4 + i * 4, 912, 28 - 7 + i * 7, C.blue, 2, xop)
    end
    P:finish()
    o.sh_ind_r:set_items(P.items)
end

-- ==================== 卡片（轮转刷新，每次只画一张） ====================
--[[为什么"一次只画一张"：
一张卡 232x208 = 4.8 万像素，四张一起重画就是 19 万像素／次。原来按 10Hz 触发，
但帧率一低（4fps 时 dt=250ms）就变成"每帧四张全画"，反而把帧率压得更低 —— 正反馈。
现在每帧只画一张、四张轮转，并且要求至少隔 2 帧，单帧重绘面积降到 1/4。
@param int only 只画第几张（1=电量 2=里程 3=功率 4=电耗），nil = 全画
]]
-- 赋值不是 local function：上面已有前置声明，再 local 会让 M.build 里那个仍是 nil
function draw_cards(only)
    local P = fx.pool()
    local soc = o.battery / 100

    -- ---------- 1、电量：底板 + SOC 环 ----------
    if not only or only == 1 then
        P:reset()
        panel_bg(P, T.cards.a.w, T.cards.a.h, C.amber)
        -- 回收时环变绿，模拟"正在回充"
        local ring_col = (o.regen > 1) and C.green or C.amber
        ring_gauge(P, T.ring.lx, T.ring.ly, soc, ring_col, false)
        P:finish()
        o.sh_a:set_items(P.items)
    end

    -- ---------- 2、里程：底板 + 行程条 ----------
    if not only or only == 2 then
        P:reset()
        panel_bg(P, T.cards.b.w, T.cards.b.h, C.normal)
        local bx, by, bw, bh = 16, 150, CW, 8
        P:box(bx, by, bw, bh, 0x101A26, 230, 4)
        local frac = fx.clamp(o.trip / 300, 0, 1)
        if frac > 0.01 then
            P:box(bx, by, bw * frac, bh, o.accent, 240, 4)
            P:dot(bx + bw * frac, by + bh / 2, 6, o.accent, 55)
        end
        for i = 1, 9 do
            P:line(bx + bw * i / 10, by - 3, bx + bw * i / 10, by + bh + 3, 0x0A121B, 1, 200)
        end
        P:finish()
        o.sh_b:set_items(P.items)
    end

    -- ---------- 3、功率：底板 + 输出/回收双向环 ----------
    if not only or only == 3 then
        P:reset()
        panel_bg(P, T.cards.c.w, T.cards.c.h, C.red)
        local pout = fx.clamp(o.power / T.power_max, 0, 1)
        local preg = fx.clamp(o.regen / T.regen_max, 0, 1)
        ring_gauge(P, T.ring.rx, T.ring.ry, preg, C.green, true)
        if pout > 0.003 then
            local r, w = T.ring.r, T.ring.w
            local a0 = T.ring.a0
            local a1 = a0 + (T.ring.a1 - T.ring.a0) * pout
            P:arc(T.ring.rx, T.ring.ry, r, a0, a1, o.accent, w, 255, true)
            P:dot(T.ring.rx + math.cos(math.rad(a1)) * r,
                T.ring.ry + math.sin(math.rad(a1)) * r, 5, fx.shade(o.accent, 0.55), 235)
        end
        P:finish()
        o.sh_c:set_items(P.items)
    end

    -- ---------- 4、电耗趋势：底板 + 迷你折线 ----------
    if not only or only == 4 then
        P:reset()
        panel_bg(P, T.cards.d.w, T.cards.d.h, C.violet)
        local dx2, dy2, dw, dh = 16, 88, CW, 96
        P:box(dx2, dy2, dw, dh, 0x080E15, 210, 8)
        for i = 1, 3 do
            local gy = dy2 + dh * i / 4
            P:line(dx2 + 4, gy, dx2 + dw - 4, gy, 0x151F2A, 1, 170)
        end
        fx.spark(P, o.spark, o.spark_n, dx2 + 5, dy2 + 6, dw - 10, dh - 12, C.violet, 2, 235)
        P:finish()
        o.sh_d:set_items(P.items)
    end

    -- ---------- 文本：跟着各自的卡一起刷，避免每帧做 20 次 string.format ----------
    if not only or only == 1 then
        upd("soc", o.lb_soc, string.format("%d%%", math.floor(o.battery + 0.5)))
        upd("range", o.lb_range, string.format("%d km", math.floor(o.battery * 5.28 + 0.5)))
        upd("bt", o.lb_bt, string.format("%d C", math.floor(o.batt_t + 0.5)))
        upd("soh", o.lb_soh, string.format("%d%%", math.floor(98 - o.trip / 200)))
        upd("chg", o.lb_chg, string.format("%.1f h", o.battery / 12.6))
    end
    if not only or only == 2 then
        upd("odo", o.lb_odo, string.format("%.1f km", o.odo))
        upd("trip", o.lb_trip, string.format("%.1f", o.trip))
        upd("avg", o.lb_avg, string.format("%d", math.floor(o.avg + 0.5)))
        upd("wear", o.lb_wear, string.format("电池循环 %d 次", 128 + math.floor(o.odo / 100)))
    end
    if not only or only == 3 then
        -- 环心显示"当前更大的那一侧"：输出时是强调色，回收时是绿色
        local regen_dom = o.regen > o.power
        upd("kw", o.lb_kw, string.format("%d",
            math.floor((regen_dom and o.regen or o.power) + 0.5)))
        local kc = regen_dom and C.green or math.floor(o.accent)
        if o.kw_col ~= kc then
            o.kw_col = kc
            o.lb_kw:set_color(kc)
        end
        upd("regen", o.lb_regen, string.format("回收 %.1f kW", o.regen))
        upd("motor", o.lb_motor, string.format("电机 %d C", math.floor(o.motor_t + 0.5)))
        upd("eff", o.lb_eff, string.format("%d%%",
            math.max(70, math.min(99, math.floor(93 + o.power / 22 - o.regen / 40)))))
        upd("tq", o.lb_tq, string.format("%d Nm", math.floor(o.torque + 0.5)))
    end
    if not only or only == 4 then
        upd("cons", o.lb_cons, string.format("%.1f", o.cons))
        upd("cons2", o.lb_cons2, string.format("%.1f", o.cons))
        local avg_cons = (o.cons_n > 1) and (o.cons_sum / o.cons_n) or 0
        upd("cmax", o.lb_maxcons, string.format("MAX %.1f", o.cons_max))
        upd("cavg", o.lb_avgcons, string.format("AVG %.1f", avg_cons))
    end
end

-- ==================== 主循环 ====================
function M.run()
    init_time_base()

    local t = 0
    local prev = read_tick()
    local waitMs = T.perf.frame_ms
    local cardT, clockT, statT = 0, 0, 0
    local frame = 0
    -- 卡片节拍（低帧率时自动放慢：卡片都是慢变量，帧预算优先给速度弧）
    local cardMs = T.perf.card_ms

    o.quality = T.perf.quality
    o.ind_dirty = true
    o.ready_q = -1
    o.ind_prev = nil

    --[[帧时长平滑：tick 精度可能只有 20ms（1601 这类平台），
    单帧差值会 20/20/40 地跳，用多帧平均当 dt，
    物理和动画都不会抖，平均速度又跟真实时间对齐。

    窗口长度按时间分辨率定：mcu.ticks2 是毫秒级，4 帧足够；
    回退到 mcu.ticks()+mcu.hz() 且 tick 很粗（hz<=100，即 >=10ms 一格）时，
    4 帧平均仍能看到 ±10ms 的锯齿，所以拉长到 8 帧。]]
    local avgN = (HAS_T2 or HZ >= 200) and 4 or 8
    local accMs, accN = 0, 0
    local dtMs = T.perf.frame_ms

    -- 帧率统计窗口（约 1 秒）
    local fpsFrames, fpsMs, fps = 0, 0, 0
    local lastCost = 0
    local slowHits = 0

    while true do
        sys.wait(waitMs)

        -- ---------- 时间：tick → 毫秒 ----------
        local rawMs
        local now = read_tick()
        if now and prev then
            rawMs = tick_ms(tick_delta(now, prev))
            prev = now
            if rawMs > 250 then rawMs = 250 end
            if rawMs < 0 then rawMs = 0 end
        else
            rawMs = T.perf.frame_ms
        end
        accMs = accMs + rawMs
        accN = accN + 1
        if accN >= avgN then
            dtMs = accMs / accN
            accMs, accN = 0, 0
        end
        local dt = dtMs / 1000
        if dt > 0.1 then dt = 0.1 elseif dt < 0.004 then dt = 0.004 end

        t = t + dt
        frame = frame + 1
        local c0 = now

        -- ---------- 动力学 ----------
        local ok, err = pcall(physics, dt, t)
        if not ok then log.error("ev", "动力学异常", err) end

        -- ---------- 表盘（每帧） ----------
        local ok2, err2 = pcall(draw_dial)
        if not ok2 then log.error("ev", "绘制异常", err2) end

        -- 车速 / 档位：只在整数值变化时写文本
        upd("speed", o.lb_speed, tostring(math.floor(o.speed + 0.5)))
        upd("gear", o.lb_gear, (o.throttle or o.demo or o.speed > 1) and "D" or "N")
        local gc = math.floor(o.accent)
        if o.gear_col ~= gc then
            o.gear_col = gc
            o.lb_gear:set_color(gc)
        end

        -- ---------- 指示灯（状态变化 / 转向闪烁 / READY 呼吸 8 档） ----------
        local rq = math.floor(o.ready * 8)
        if o.ind_dirty or rq ~= o.ready_q
            or ((o.turnL or o.turnR) and o.blink ~= o.ind_prev) then
            o.ind_dirty, o.ind_prev, o.ready_q = false, o.blink, rq
            local okI, errI = pcall(draw_indicators)
            if not okI then log.error("ev", "指示灯绘制异常", errI) end
        end

        --[[---------- 卡片与读数：轮转刷新，一次只画一张 ----------
        必须同时有"至少隔 2 帧"这一条：低帧率时 dt 已经大于 card_ms，
        纯按时间判断就退化成"每帧都刷四张卡"（19 万像素/帧），
        越卡越刷、越刷越卡。加上帧数下限后，单帧最多刷一张卡。]]
        cardT = cardT + dt
        if cardT >= cardMs / 1000 and (frame - (o.card_frame or 0)) >= 2 then
            cardT = 0
            o.card_frame = frame
            o.card_i = ((o.card_i or 0) % 4) + 1
            local ok3, err3 = pcall(draw_cards, o.card_i)
            if not ok3 then log.error("ev", "卡片刷新异常", err3) end
        end

        -- ---------- 时钟 1Hz ----------
        clockT = clockT + dt
        if clockT >= 1 then
            clockT = 0
            local d = os.date("*t")
            if d then
                upd("clock", o.lb_clock, string.format("%02d:%02d", d.hour, d.min))
            end
        end

        -- ---------- 节流：按本帧脚本耗时补睡眠 ----------
        local cost = 0
        local c1 = read_tick()
        if c0 and c1 then cost = tick_ms(tick_delta(c1, c0)) end
        lastCost = cost
        local w = T.perf.frame_ms - cost
        if w < 2 then w = 2 end
        waitMs = w

        -- ---------- 帧率统计 + 自动降档 ----------
        fpsFrames = fpsFrames + 1
        fpsMs = fpsMs + rawMs
        if fpsMs >= 1000 then
            fps = fpsFrames * 1000 / fpsMs
            fpsFrames, fpsMs = 0, 0
            --[[只降不升：升回来会在阈值附近来回抖，反而更难受。
            开头 3 秒不判（自检扫弧 + 字库首次栅格化 + 图层首绘，
            这一段的帧率天然偏低，按它降档会一直卡在低画质）；
            还要连续 3 个窗口都低才降 —— 单帧/单秒的偶发卡顿（切模式、
            桌面抢占、GC）不该把画质永久拉下来。]]
            if T.perf.auto and (o.quality or 0) > 0 and t > 3 then
                if fps < T.perf.slow_fps then
                    slowHits = slowHits + 1
                else
                    slowHits = 0
                end
                if slowHits >= 3 then
                    slowHits = 0
                    o.quality = o.quality - 1
                    log.warn("ev", string.format("实测 %.1f fps < %d，画质自动降到 %d",
                        fps, T.perf.slow_fps, o.quality))
                end
            end
            --[[帧率低时把卡片节拍放慢（10Hz -> 4Hz）：
            四张卡轮转，每张 232x208 = 4.8 万像素，是除速度弧之外最大的重绘项。
            卡片里都是 SOC / 里程 / 电耗这类慢变量，4Hz 完全够看，
            省下来的帧预算留给速度弧和车速数字。]]
            cardMs = (fps < T.perf.slow_fps) and 250 or T.perf.card_ms
        end

        -- ---------- 每 5 秒一条状态日志 ----------
        statT = statT + dt
        if statT >= 5 then
            statT = 0
            -- lvgl_fps 来自 airui 自己的统计，需要 app_main 里 airui.debug(true) 才有值
            local ad = airui.debug and airui.debug()
            local lf = (ad and ad.fps and ad.fps > 0) and tostring(ad.fps) or "-"
            --[[arc=速度弧这一层的图元数（整段一条弧时是 0 或 3：弧 + 光晕 + 亮点）
            items=杂项层（装饰弧 / 涟漪）的图元数，q<2 时恒为 0。]]
            log.info("ev", string.format(
                "speed=%.0f soc=%.1f arc=%d items=%d lua_fps=%.1f cost=%.1fms dt=%.1fms lvgl_fps=%s q=%d",
                o.speed, o.battery, o.narc or 0,
                o.ndyn or 0, fps, lastCost, dtMs, lf, o.quality or 0))
        end
    end
end

return M
