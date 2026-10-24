--[[
@module  cluster
@summary MOTO DASH - 两轮车仪表盘（速度表 / 电量 / 功率 / 里程 / 骑行模式）
@version 1.0
@date    2026.10.22
@author  江访

=== 画面构成（1024x600，无图片素材）===
  1、中央速度表：半径 206，扫角 150°~390°（240°），0~160 km/h
     大刻度每 20 一根带数字，小刻度每 4 一根，140 以上是红线区
     进度弧 + 指针 + 弧头光点 + 中心轴盖，全部由图元逐帧绘制
  2、"旋转光环"：速度表内部的环形带里有两条彗尾在追光，转速与车速联动
     静止时透明度归零（不画），所以怠速时零图元开销
  3、左侧两张卡：电量（20 段电池条 + 续航）、里程（ODO / TRIP / AVG）
  4、右侧两张卡：功率（输出红 / 回收绿的双向条）、速度趋势（迷你折线）
  5、顶栏：左转向、近光、时钟、远光、右转向（大灯与转向灯可点）
  6、底部：ECO / NORMAL / SPORT 三个骑行模式，切换会同时改强调色与动力学参数

=== 三个"像真仪表"的细节 ===
1、上电自检：指针 0→160→0 扫一圈，所有指示灯全亮，1.5 秒后进入骑行态。
   这是真车仪表的标准动作，做出来立刻就"是个表"而不是"一张图"。
2、按住表盘 = 拧油门：速度按模式加速度爬升，松手按减速度滑行；
   功率条的正负、电池条的掉电速度、电机温度全部跟着变。
3、切换模式时强调色是逐帧插值的（mix），不是硬切，配合一圈涟漪更耐看。

=== 分层与预算 ===
  静态层（刻度、轨道弧、内外环、顶栏分隔线）只画一次，约 110 个图元
  动态层每帧约 60~80 个图元：进度弧 24 段 + 红线 6 段 + 指针 5 + 彗尾 14 + 指示灯 8
  卡片内的条与折线 10Hz 刷新（人眼对卡片的"跳变"不敏感，对指针很敏感）
]]
local fx = require "fx"
local eff = require "eff"
local T = require "theme"

local M = {}
local C, D = T.c, T.dial
local SW, SH = T.screen.w, T.screen.h

-- ==================== 时间基准 ====================
local TICKS_PER_MS = 1

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    return os.time() * 1000
end

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end
    return d
end

-- ==================== 小工具 ====================
local function lbl(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h, text = text,
        font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local o    -- 全部运行期状态（单屏仪表，不需要多页面结构）

--[[文本缓存写回
LVGL 每次 set_text 都要重新排版文本，1 秒 30 次是纯浪费。
这里只在值真的变了才写，且把上次的值存在 o.txt 里统一管理。]]
local function upd(key, node, v)
    if o.txt[key] ~= v then
        o.txt[key] = v
        node:set_text(v)
    end
end

-- 速度 → 弧度（屏幕角度，0=右，顺时针为正）
local function ang(v)
    return math.rad(D.a0 + (v / D.vmax) * (D.a1 - D.a0))
end

-- ==================== 静态层 ====================
local function build_static()
    local P = fx.pool()
    local cx, cy, R, Ra = D.cx, D.cy, D.R, D.Ra
    P:reset()

    -- 外圈两道细环 + 一条内环，纯粹是给"表盘"框出边界
    -- 半径层级（由外向内）：196 外环 / 187 弧外沿 / 173 弧内沿
    --                     170..154 刻度 / 143 彗尾环 / 120 数字 / 100 内环
    P:ring(cx, cy, R, 0x1C2530, 1, 220)
    P:ring(cx, cy, R - 3, 0x151C25, 1, 180)
    P:ring(cx, cy, 100, 0x1A222C, 1, 160)

    -- 刻度轨道：一整圈暗底弧，进度弧会盖在上面
    P:arc(cx, cy, Ra, ang(0), ang(D.vmax), 48, 0x1E2731, 13, 255)

    -- 刻度线：小刻度短、大刻度长且更亮
    local v = 0
    while v <= D.vmax do
        local a = ang(v)
        local ca, sa = math.cos(a), math.sin(a)
        local major = (v % D.major == 0)
        local r0 = Ra - 10
        local r1 = major and (Ra - 26) or (Ra - 19)
        P:line(cx + ca * r0, cy + sa * r0, cx + ca * r1, cy + sa * r1,
            major and 0x5C6B80 or 0x333F4E, major and 2 or 1, major and 235 or 170, true)
        v = v + D.minor
    end

    -- 顶栏与底部各一条分隔细线，把"上中下"三层切开
    P:line(24, 58, SW - 24, 58, 0x1B232E, 1, 190)
    P:line(24, 516, SW - 24, 516, 0x1B232E, 1, 190)

    P:finish()
    o.static_shape:set_items(P.items)

    -- 大刻度数字：位置按角度算好，一次性摆上去（label 不能旋转，所以只放数字）
    local Rl = Ra - 60
    local v2 = 0
    while v2 <= D.vmax do
        local a = ang(v2)
        local lx = cx + math.cos(a) * Rl - 16
        local ly = cy + math.sin(a) * Rl - 11
        local col = (v2 >= D.vred) and C.red or C.dim
        lbl(o.root, math.floor(lx), math.floor(ly), 32, 22,
            tostring(v2), T.f.sub, col, airui.TEXT_ALIGN_CENTER)
        v2 = v2 + D.major
    end
end

-- ==================== 卡片 ====================
--[[卡片 = "纯图元 + 文字"，故意不用 container

为什么不用 container：
  container 就是 `lv_obj_create`，**默认带 LV_OBJ_FLAG_SCROLLABLE**。
  只要所有子对象的包围盒超出内容区一点点（border 1px、字体行高比给的高 1px、
  以后多加一个字符……），LVGL 就判定"可滚动"，于是按 AUTO 模式在右/下画出滚动条
  ——真机上看到的就是"卡片里多一圈方角细框、按钮文字下面多一条横线"。
  这类问题即使这次几何算得刚好相等，也很容易复发。

为什么 shape 不会：
  组件 C 代码里对 shape 硬编码了 `lv_obj_remove_flag(shape, LV_OBJ_FLAG_SCROLLABLE)`
  和 `LV_OBJ_FLAG_CLICKABLE`，它在任何情况下都不可能画出滚动条。
  所以干脆让 shape 兼任"卡片底板"：圆角填充 + 描边 + 顶部高光只要 3 个图元，
  和条/折线一起在同一个 10Hz 刷新里重画，成本可以忽略。
  文字作为 shape 的子对象挂在上面（shape 不裁剪内容，几何由我们自己保证）。
]]
--[[注意：不要在 shape 上挂自定义字段
airui 组件的 userdata metatable 只有 __index（方法表）和 __gc，**没有 __newindex**，
所以 `s.tint = x` / `s.cw = x` 会直接抛 "attempt to index a userdata value"，
Lua VM 随即退出重启。几何与 tint 由调用方从 T.cards.* / 常量里取，不往组件上存状态。]]
local function card(geo)
    local s = airui.shape({
        parent = o.root, x = geo.x, y = geo.y, w = geo.w, h = geo.h, items = {},
    })
    if not s then
        log.error("moto", "卡片 shape 创建失败", geo.x, geo.y)
    end
    return s
end

--[[卡片底板：圆角填充 + 1px 描边 + 顶部高光
C 层画矩形用的是 x2 = x + w（含端点），所以宽高各减 1 才是"正好铺满 shape"，
否则右下各多 1px 会被图层裁掉，描边看起来缺一条边。]]
local function panel_bg(P, w, h, tint)
    P:box(0, 0, w - 1, h - 1, C.panel, 245, 18)
    P:frame(0, 0, w - 1, h - 1, C.line, 1, 255, 18)
    P:line(20, 2, w - 21, 2, tint, 1, 120, true)
end

-- 卡片内容宽度：左右各留 18px
local CW = T.cards.a.w - 36

local function build_cards()
    -- ---------- 电量 ----------
    local ra = card(T.cards.a)
    o.sh_a = ra
    lbl(ra, 18, 12, CW, 20, "电量 BATTERY", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_batt = lbl(ra, 17, 34, CW, 52, "78%", T.f.big, C.amber, airui.TEXT_ALIGN_LEFT)
    o.lb_range = lbl(ra, 18, 88, CW, 20, "续航 86 km", T.f.sub, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_batt2 = lbl(ra, 18, 150, CW, 20, "电池温度 32 C", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)

    -- ---------- 里程 ----------
    local rb = card(T.cards.b)
    o.sh_b = rb
    lbl(rb, 18, 12, CW, 20, "里程 ODO", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_odo = lbl(rb, 17, 34, CW, 34, "12345.6 km", T.f.num, C.txt, airui.TEXT_ALIGN_LEFT)
    lbl(rb, 18, 76, 100, 18, "TRIP", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_trip = lbl(rb, 17, 94, CW, 26, "128.4 km", T.f.val, C.normal, airui.TEXT_ALIGN_LEFT)
    lbl(rb, 18, 126, 100, 18, "AVG", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.lb_avg = lbl(rb, 17, 144, CW, 26, "32 km/h", T.f.body, C.dim, airui.TEXT_ALIGN_LEFT)

    -- ---------- 功率 ----------
    local rc = card(T.cards.c)
    o.sh_c = rc
    lbl(rc, 18, 12, CW, 20, "功率 POWER", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_pwr = lbl(rc, 17, 34, CW, 52, "0.0 kW", T.f.big, C.red, airui.TEXT_ALIGN_LEFT)
    o.lb_pwr2 = lbl(rc, 18, 88, CW, 20, "回收 0.0 kW", T.f.sub, C.green, airui.TEXT_ALIGN_LEFT)
    o.lb_temp = lbl(rc, 18, 150, CW, 20, "电机 38 C", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)

    -- ---------- 速度趋势 ----------
    local rd = card(T.cards.d)
    o.sh_d = rd
    lbl(rd, 18, 12, CW, 20, "速度趋势 SPEED", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.lb_max = lbl(rd, 17, 34, CW, 30, "MAX 0 km/h", T.f.body, C.txt, airui.TEXT_ALIGN_LEFT)
    o.lb_avg2 = lbl(rd, 18, 146, CW, 20, "AVG 0 km/h", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)

    -- ---------- 中央文字 ----------
    --[[三行都塞进半径 100 的内环里：
    车速 92pt 约 74px 高（cy-72 .. cy+36），单位 cy+42，档位 cy+66。
    92pt 三位数约 165px 宽，在 dy=36 处内环可用半宽 √(100²-36²)=93 → 刚好放得下。]]
    o.lb_speed = lbl(o.root, D.cx - 170, D.cy - 72, 340, 108, "0",
        T.f.huge, C.txt, airui.TEXT_ALIGN_CENTER)
    o.lb_unit = lbl(o.root, D.cx - 60, D.cy + 42, 120, 22, "km/h",
        T.f.body, C.dim, airui.TEXT_ALIGN_CENTER)
    -- 档位：D=可行驶，N=停车。跟着强调色走，切换模式时颜色一起变
    o.lb_gear = lbl(o.root, D.cx - 40, D.cy + 66, 80, 32, "D",
        T.f.num, C.normal, airui.TEXT_ALIGN_CENTER)
end

-- ==================== 顶栏 / 底部 ====================
local function build_bars()
    o.lb_clock = lbl(o.root, 432, 10, 160, 36, "--:--", T.f.val,
        C.txt, airui.TEXT_ALIGN_CENTER)

    -- 底部提示（纯装饰，说明交互方式）
    lbl(o.root, 24, 546, 250, 20, "按住表盘 手动驾驶 / 松手 自动巡游", T.f.mini,
        C.dim2, airui.TEXT_ALIGN_LEFT)
    lbl(o.root, 750, 546, 250, 20, "点击顶栏开关灯光", T.f.mini,
        C.dim2, airui.TEXT_ALIGN_RIGHT)

    --[[骑行模式按键：同样用 shape 兜底，不用 container
    按键的圆角底板 + 描边写进 shape，点击靠 on_touch 的热区判定
    （顶栏四个灯、三个模式键都在 on_touch 里，不依赖 LVGL 的 on_click）。
    这样即使文字比按钮宽、行高比给的高，也永远不会冒出滚动条。]]
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
        battery = 78.0, motor_t = 38.0,
        power = 0, regen = 0,
        odo = 12345.6, trip = 128.4, avg = 0, vmax_seen = 0,
        turnL = false, turnR = false, light = true, high = false,
        blink = true,
        spark = {}, spark_n = 0, spark_acc = 0,
        streak = 0,
        demo = false, demo_t = 0, idle = 0,
    }

    o.root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    -- 底纹压在最底，图元与卡片都盖在它上面
    eff.build_bg(o.root)

    -- 先建图元层（在卡片之下），再建卡片与文字
    o.static_shape = airui.shape({
        parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {},
    })
    o.dyn_shape = airui.shape({
        parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {},
    })

    build_static()
    build_cards()
    build_bars()

    -- 光效最后建：z 序按创建顺序，光要盖在卡片与文字之上才像"光"
    eff.build_overlay(o.root)

    for i = 1, 60 do o.spark[i] = 0 end

    airui.touch_subscribe(function(state, x, y)
        M.on_touch(state, x, y)
    end)
    log.info("moto", "仪表盘构建完成")
end

-- ==================== 模式 / 灯光 ====================
function M.set_mode(i)
    if not o or i == o.mode then return end
    o.mode = i
    o.flash = 1                  -- 切模式时打一圈涟漪
    eff.sweep()                  -- 同时自上而下扫一道光
    M.sync_chips()
    log.info("moto", "骑行模式 " .. T.modes[i].id)
end

--[[模式键重绘：选中态 = 强调色淡底 + 强调色描边，未选中 = 卡片底 + 灰描边
只在切模式时执行一次，用临时图元池画完就丢，不占每帧预算。]]
function M.sync_chips()
    local P = fx.pool()
    for i, ch in ipairs(o.chips) do
        local m = T.modes[i]
        local on = (i == o.mode)
        P:reset()
        P:box(0, 0, T.chip.w - 1, T.chip.h - 1, on and m.color or C.panel, on and 40 or 245, 14)
        P:frame(0, 0, T.chip.w - 1, T.chip.h - 1, on and m.color or C.line, 1, 255, 14)
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
万一某个固件版本的 airui 表里没导出 TP_DOWN，直接比 nil 会让"整个界面点不动"，
所以这里不再依赖 airui.TP_*，用数值常量并保留可读别名。]]
local TP_DOWN = airui.TP_DOWN or 1
local TP_HOLD = airui.TP_HOLD or 2
local TP_UP = airui.TP_UP or 3

--[[命中顺序很重要
先判按键（顶栏四个热区 + 底部三个模式键），最后才把"表盘内"当油门。
否则按在模式键上会被当成油门加速。]]
function M.on_touch(state, x, y)
    if not o or type(x) ~= "number" or type(y) ~= "number" then return end

    -- 光效先吃事件（按下 / 拖动 / 抬起），不影响下面的业务判定
    if state == TP_DOWN then
        eff.press(x, y)
    elseif state == TP_HOLD then
        eff.move(x, y)
        return
    elseif state == TP_UP then
        eff.release()
    end

    if state == TP_DOWN then
        -- 顶栏：左转向 / 近光 / 远光 / 右转向
        if hit(x, y, 18, 4, 76, 50) then
            o.turnL = not o.turnL
            return
        elseif hit(x, y, 100, 4, 60, 50) then
            o.light = not o.light
            return
        elseif hit(x, y, 864, 4, 60, 50) then
            o.high = not o.high
            return
        elseif hit(x, y, 930, 4, 76, 50) then
            o.turnR = not o.turnR
            return
        end
        -- 底部模式键（airui 的 on_click 也会触发，这里只是兜底）
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
        -- 表盘内 → 油门（只有这里才算"用户在驾驶"，才打断演示巡游）
        local dx, dy = x - D.cx, y - D.cy
        if dx * dx + dy * dy <= D.R * D.R then
            o.throttle = true
            o.idle = 0
            eff.flash(x, y)      -- 按在表盘上爆一颗光斑
        end
    elseif state == TP_UP then
        -- 只有"松油门"才重新计时；点一下车灯不应该把演示巡游停掉
        local was = o.throttle
        o.throttle = false
        if was then o.idle = 0 end
    end
end

-- ==================== 演示曲线 ====================
--[[没有真实车辆数据时，让仪表自己"跑起来"
24 秒一个循环：起步 → 巡航（正弦 + 噪声叠加，做出肉眼可见的起伏）→ 减速停车 → 再起步。
所有幅度都由当前档位的 vmax 缩放，所以切到 SPORT 时整体波动立刻变大，切 ECO 立刻变小
—— 这样"点按钮"就有了看得见的反馈，不用非得按住屏幕拧油门。

为什么不直接按住屏幕就动：
真机演示时没人会一直按着屏幕，表针停在 0 会让整个界面看起来"死机"。
]]
local function demo_target(m)
    local ph = o.demo_t % 24
    -- 停车窗口：19~21 秒滑行停车，0~1.5 秒起步
    local hold = 0
    if ph > 19 then hold = fx.clamp((ph - 19) / 2.0, 0, 1) end
    if ph < 1.5 then hold = fx.clamp(1 - ph / 1.5, 0, 1) end
    local cruise = 0.58
        + 0.20 * math.sin(o.demo_t * 0.85)
        + 0.10 * math.sin(o.demo_t * 2.10 + 1.3)
        + 0.10 * fx.noise1(o.demo_t * 1.6)
    cruise = fx.clamp(cruise, 0.12, 0.95)
    return m.vmax * cruise * (1 - hold)
end

-- ==================== 每帧：动力学 ====================
local function physics(dt, t)
    local m = T.modes[o.mode]

    -- 演示模式：自检结束后接管；用户一碰屏幕就交还手动控制
    o.idle = o.idle + dt
    o.demo_t = o.demo_t + dt
    o.demo = (not o.throttle) and o.idle > 3

    if o.booting then
        -- ---- 上电自检：指针扫一圈 ----
        o.boot = o.boot + dt
        local b = o.boot
        if b < 0.55 then
            o.speed = fx.ease_out(b / 0.55) * D.vmax
        elseif b < 1.05 then
            o.speed = (1 - fx.ease_in_out((b - 0.55) / 0.5)) * D.vmax
        else
            o.speed = 0
            if b >= 1.45 then
                o.booting = false
                o.speed_t = 0
                o.idle = 99          -- 自检一结束就进入演示，别让指针干停着
                log.info("moto", "自检完成，进入演示巡游")
            end
        end
        o.power = 0
        o.regen = 0
    else
        -- ---- 目标车速：手动油门 / 演示曲线 / 滑行 ----
        local target
        if o.throttle then
            target = m.vmax                    -- 拧油门：冲到本档极速
        elseif o.demo then
            target = demo_target(m)            -- 演示：自动跑起伏路
        else
            target = 0                         -- 松手滑行
        end
        -- 按档位加减速度做速率限制，指针才不会跳变
        local rate = (target > o.speed_t) and m.acc or m.dec
        local d = target - o.speed_t
        local step = rate * dt
        if math.abs(d) <= step then
            o.speed_t = target
        else
            o.speed_t = o.speed_t + (d > 0 and step or -step)
        end
        o.speed = fx.approach(o.speed, o.speed_t, 0.35, dt)

        -- 功率：正=输出，负=回收。用速度变化率×车速估一个像样的 kW
        local acc = (o.speed_t - o.prev_t) / math.max(dt, 0.001)
        local kw = acc * 0.085 * (0.38 + o.speed / D.vmax)
        o.power = fx.approach(o.power, kw > 0 and kw or 0, 0.18, dt)
        o.regen = fx.approach(o.regen, kw < 0 and -kw or 0, 0.18, dt)
    end
    o.prev_t = o.speed_t

    -- ---- 电量 / 续航：耗电跟功率相关 ----
    if not o.booting then
        local drain = (0.010 + math.abs(o.power) * 0.030 - o.regen * 0.012) * dt
        o.battery = fx.clamp(o.battery - drain, 0, 100)
    end

    -- ---- 电机温度：功率越大越热，缓慢回落 ----
    local t_target = 36 + o.power * 2.4 + o.speed * 0.045
    o.motor_t = fx.approach(o.motor_t, t_target, 0.03, dt)

    -- ---- 里程 ----
    --[[自检扫针期间不算里程
    扫针时表速会跑到 160，如果照常累加，开机会白涨 0.07 km 里程、
    速度趋势的 MAX 也会被自检刷成 160，看起来像"车自己跑了一趟"。]]
    if not o.booting and o.speed > 0.5 then
        local km = o.speed * dt / 3600
        o.odo = o.odo + km
        o.trip = o.trip + km
        o.avg = fx.approach(o.avg, o.speed, 0.004, dt)
        if o.speed > o.vmax_seen then o.vmax_seen = o.speed end
    end

    -- ---- 强调色跟随模式平滑过渡 ----
    o.accent = fx.mix(o.accent, m.color, 0.10)

    -- ---- 转向灯闪烁相位（1.25Hz）----
    o.blink = (t % 0.8) < 0.42

    -- ---- 表内彗尾的角速度（车速越高转越快）----
    o.streak = o.streak + dt * (0.35 + o.speed / 42)

    -- ---- 速度趋势采样（每 0.4s 一格，60 格约 24 秒）----
    o.spark_acc = o.spark_acc + dt
    if o.spark_acc >= 0.4 and not o.booting then
        o.spark_acc = 0
        for i = 2, 60 do o.spark[i - 1] = o.spark[i] end
        o.spark[60] = o.speed / D.vmax
    end

    if o.flash then
        o.flash = o.flash - dt * 1.6
        if o.flash <= 0 then o.flash = nil end
    end
end

-- ==================== 每帧：动态层 ====================
local function draw_dyn(t)
    local P = fx.pool()
    local cx, cy, Ra = D.cx, D.cy, D.Ra
    local acc = o.accent
    local v = o.speed
    P:reset()

    -- ==================== 红线区（画在进度弧之上，指到红区也看得见） ====================
    --[[16 段：30° 跨度 / 16 = 1.9°/段，弦长 5.9px、弦高 0.1px
    原来只有 8 段（3.75°/段，弦长 11.8px）比线宽 13px 还短，
    圆头叠加后是一串珠子，所以红线区看起来像"糖葫芦"而不是弧。]]
    local pulse = 0.55 + 0.45 * math.sin(t * 6.2)
    if v >= D.vred - 6 then
        -- 接近红线时红线区开始闪，观感上像"要断油了"
        P:arc(cx, cy, Ra, ang(D.vred), ang(D.vmax), 16, C.red,
            13, math.floor(120 + 120 * pulse))
    else
        P:arc(cx, cy, Ra, ang(D.vred), ang(D.vmax), 16, C.red, 13, 150)
    end

    -- ==================== 进度弧 ====================
    if v > 0.4 then
        local a0 = ang(0)
        local a1 = ang(v)
        --[[段数按弦高取：r=180 时 32 段（7.5°/段）弦高 0.39px，肉眼已是圆弧
        弧头一端不加圆头（cap1=false），改由下面那颗光点收尾，不然会叠出个"棒棒糖"]]
        local segs = math.max(2, math.ceil(32 * v / D.vmax))
        P:arc(cx, cy, Ra, a0, a1, segs, acc, 13, 255, true, false)
        -- 弧头光点：一段柔和外晕 + 一颗实心亮点
        local hx, hy = cx + math.cos(a1) * Ra, cy + math.sin(a1) * Ra
        P:dot(hx, hy, 8, acc, 55)
        P:dot(hx, hy, 4, fx.shade(acc, 0.65), 240)
    end

    -- ==================== 表内彗尾（速度感） ====================
    -- 静止时不画：怠速零开销，也让画面更"安静"
    if v > 4 then
        local opa = math.floor(fx.clamp((v - 4) / 90, 0, 1) * 120)
        local rr = 143    -- 落在"数字环(120)"与"刻度(154)"之间
        for k = 1, 2 do
            local base = o.streak * (k == 1 and 1 or -0.72) + k * 2.1
            for s = 0, 5 do
                local a1 = base - s * 0.045
                local a2 = a1 - 0.045
                local fade = 1 - s / 6
                P:line(cx + math.cos(a1) * rr, cy + math.sin(a1) * rr,
                    cx + math.cos(a2) * rr, cy + math.sin(a2) * rr,
                    acc, 3, math.floor(opa * fade), true)
            end
        end
    end

    -- ==================== 指针 ====================
    local a = ang(v)
    local ca, sa = math.cos(a), math.sin(a)
    local len = Ra - 10
    -- 光晕 + 灯芯 + 尾配重，三笔就是一根"实体针"
    P:line(cx - ca * 22, cy - sa * 22, cx + ca * len, cy + sa * len, acc, 9, 45, true)
    P:line(cx - ca * 22, cy - sa * 22, cx + ca * len, cy + sa * len, 0xF2F7FF, 3.5, 245, true)
    P:dot(cx + ca * len, cy + sa * len, 4, 0xFFFFFF, 240)
    -- 中心轴盖
    P:dot(cx, cy, 15, 0x0B1016, 255)
    P:ring(cx, cy, 15, acc, 2, 220)
    P:dot(cx, cy, 5, acc, 255)

    -- ==================== 模式切换涟漪 ====================
    if o.flash then
        local r = 124 + (1 - o.flash) * 92
        P:ring(cx, cy, math.floor(r), o.accent, 2, math.floor(180 * o.flash))
    end

    -- ==================== 顶栏指示灯 ====================
    local on_op = 255
    local off_op = 26
    local blink_op = o.blink and on_op or off_op

    -- 左转向（箭头朝左）
    local lop = o.turnL and blink_op or off_op
    local lx, ly = 56, 29
    P:line(lx + 9, ly - 9, lx - 4, ly, C.green, 3, lop, true)
    P:line(lx - 4, ly, lx + 9, ly + 9, C.green, 3, lop, true)
    P:line(lx - 3, ly, lx + 11, ly, C.green, 3, lop, true)

    -- 右转向
    local rop = o.turnR and blink_op or off_op
    local rx, ry = 968, 29
    P:line(rx - 9, ry - 9, rx + 4, ry, C.green, 3, rop, true)
    P:line(rx + 4, ry, rx - 9, ry + 9, C.green, 3, rop, true)
    P:line(rx + 3, ry, rx - 11, ry, C.green, 3, rop, true)

    -- 近光：一个"灯碗 + 三道光线"
    local hop = o.light and on_op or off_op
    P:line(120, 22, 132, 22, C.green, 3, hop, true)
    P:line(120, 36, 132, 36, C.green, 3, hop, true)
    P:line(120, 22, 120, 36, C.green, 3, hop, true)
    P:line(136, 26, 146, 29, C.green, 2, hop, true)
    P:line(136, 32, 146, 29, C.green, 2, hop, true)

    -- 远光：多加两道更长的光线，用蓝色区分
    local xop = o.high and on_op or off_op
    P:line(884, 22, 896, 22, C.blue, 3, xop, true)
    P:line(884, 36, 896, 36, C.blue, 3, xop, true)
    P:line(884, 22, 884, 36, C.blue, 3, xop, true)
    for i = 0, 2 do
        P:line(900, 29 - 4 + i * 4, 912, 29 - 7 + i * 7, C.blue, 2, xop, true)
    end

    -- 自检阶段所有灯全亮，模拟真车 key-on 的灯检
    if o.booting then
        -- 期间上面的 on/off 已经拉开差距，这里补一对"全亮"的提示圈
        P:ring(cx, cy, D.R - 8, acc, 1, 90)
    end

    o.ndyn = P:finish()
    o.dyn_shape:set_items(P.items)
end

-- ==================== 10Hz：卡片 ====================
local function draw_cards()
    local P = fx.pool()

    -- ---------- 电量：底板 + 20 段电池条 ----------
    P:reset()
    panel_bg(P, T.cards.a.w, T.cards.a.h, C.amber)
    local n, gap = 20, 3
    local bx, by, bw, bh = 18, 116, T.cards.a.w - 36, 22
    local segw = (bw - gap * (n - 1)) / n
    local lit = o.battery / 100 * n
    local batt_col = (o.battery > 20) and C.amber or C.red
    for i = 1, n do
        local sx = bx + (i - 1) * (segw + gap)
        local part = fx.clamp(lit - (i - 1), 0, 1)
        if part > 0 then
            P:box(sx, by, segw, bh, batt_col, math.floor(50 + 205 * part), 3)
        else
            P:box(sx, by, segw, bh, 0x1B222C, 255, 3)
        end
    end
    P:finish()
    o.sh_a:set_items(P.items)

    -- ---------- 里程：底板 + 行程比例条（离底边留 22px，躲开 18px 圆角） ----------
    P:reset()
    panel_bg(P, T.cards.b.w, T.cards.b.h, C.normal)
    P:box(18, 168, T.cards.b.w - 36, 6, 0x1B222C, 255, 3)
    P:box(18, 168, (T.cards.b.w - 36) * fx.clamp(o.trip / 300, 0, 1), 6, o.accent, 235, 3)
    P:finish()
    o.sh_b:set_items(P.items)

    -- ---------- 功率：底板 + 双向条（右输出 / 左回收） ----------
    P:reset()
    panel_bg(P, T.cards.c.w, T.cards.c.h, C.red)
    local px, py, pw, ph = 18, 118, T.cards.c.w - 36, 26
    local mid = px + pw / 2
    P:box(px, py, pw, ph, 0x1B222C, 255, 4)
    local mx = 6.0    -- 满量程 6 kW
    local fo = fx.clamp(o.power / mx, 0, 1)
    local fr = fx.clamp(o.regen / mx, 0, 1)
    if fo > 0.01 then
        P:box(mid, py, (pw / 2) * fo, ph, C.red, 240, 4)
    end
    if fr > 0.01 then
        P:box(mid - (pw / 2) * fr, py, (pw / 2) * fr, ph, C.green, 240, 4)
    end
    P:box(mid - 1, py - 5, 2, ph + 10, 0x46536A, 255, 1)
    P:finish()
    o.sh_c:set_items(P.items)

    -- ---------- 速度趋势：底板 + 迷你折线 ----------
    P:reset()
    panel_bg(P, T.cards.d.w, T.cards.d.h, C.violet)
    local dx2, dy2, dw, dh = 18, 66, T.cards.d.w - 36, 68
    P:box(dx2, dy2, dw, dh, 0x0C1015, 200, 8)
    for i = 1, 3 do
        local gy = dy2 + dh * i / 4
        P:line(dx2 + 4, gy, dx2 + dw - 4, gy, 0x1B222C, 1, 160)
    end
    fx.spark(P, o.spark, 60, dx2 + 6, dy2 + 6, dw - 12, dh - 12, o.accent, 2, 235)
    P:finish()
    o.sh_d:set_items(P.items)

    -- ---------- 文本 ----------
    upd("batt", o.lb_batt, string.format("%d%%", math.floor(o.battery + 0.5)))
    upd("range", o.lb_range, string.format("续航 %d km", math.floor(o.battery * 1.1 + 0.5)))
    upd("batt2", o.lb_batt2, string.format("电池温度 %d C", math.floor(28 + o.power * 0.6)))
    upd("odo", o.lb_odo, string.format("%.1f km", o.odo))
    upd("trip", o.lb_trip, string.format("%.1f km", o.trip))
    upd("avg", o.lb_avg, string.format("%d km/h", math.floor(o.avg + 0.5)))
    upd("pwr", o.lb_pwr, string.format("%.1f kW", o.power))
    upd("pwr2", o.lb_pwr2, string.format("回收 %.1f kW", o.regen))
    upd("temp", o.lb_temp, string.format("电机 %d C", math.floor(o.motor_t + 0.5)))
    upd("max", o.lb_max, string.format("MAX %d km/h", math.floor(o.vmax_seen + 0.5)))
    upd("avg2", o.lb_avg2, string.format("AVG %d km/h", math.floor(o.avg + 0.5)))
end

-- ==================== 主循环 ====================
function M.run()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
        log.info("moto", string.format("时间基准 mcu.hz()=%d", hz))
    else
        TICKS_PER_MS = 1
    end

    local t = 0
    local prev = now_ms()
    local waitMs = T.perf.frame_ms
    local cardT, clockT = 0, 0
    local frame = 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now
        -- 步长固定：tick 分辨率（约 20ms）比帧间隔还粗，用 tick 差当 dt 会抖
        local dt = T.perf.frame_ms / 1000
        if realMs > T.perf.frame_ms * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = T.perf.frame_ms / 1000 end
        end
        t = t + dt
        frame = frame + 1
        local t0 = now_ms()

        local ok, err = pcall(physics, dt, t)
        if not ok then log.error("moto", "动力学异常", err) end

        local ok2, err2 = pcall(draw_dyn, t)
        if not ok2 then log.error("moto", "绘制异常", err2) end

        -- 图片光效（光晕跟随 / 闪光衰减 / 扫光推进）
        local okf, errf = pcall(eff.update, dt)
        if not okf then log.error("moto", "光效异常", errf) end

        -- 速度数字每帧都要跟指针走，但只在整数值变化时写文本
        if o then
            upd("speed", o.lb_speed, tostring(math.floor(o.speed + 0.5)))
            upd("gear", o.lb_gear, (o.throttle or o.speed > 1) and "D" or "N")
            -- 档位颜色跟强调色走：颜色是整型，缓存住避免每帧写样式
            local gc = math.floor(o.accent)
            if o.gear_col ~= gc then
                o.gear_col = gc
                o.lb_gear:set_color(gc)
            end
        end

        -- 卡片与读数 10Hz
        cardT = cardT + dt
        if cardT >= T.perf.card_ms / 1000 then
            cardT = 0
            local ok3, err3 = pcall(draw_cards)
            if not ok3 then log.error("moto", "卡片刷新异常", err3) end
        end

        -- 时钟 1Hz
        clockT = clockT + dt
        if clockT >= 1 then
            clockT = 0
            local d = os.date("*t")
            if d then
                upd("clock", o.lb_clock, string.format("%02d:%02d", d.hour, d.min))
            end
        end

        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS
        local w = T.perf.frame_ms - cost
        if w < 2 then w = 2 end
        waitMs = w

        -- 每 5 秒打一次性能日志：脚本帧率 + 动态图元数
        if frame % 165 == 0 then
            log.info("moto", string.format("speed=%.0f items=%d", o.speed, o.ndyn or 0))
        end
    end
end

return M
