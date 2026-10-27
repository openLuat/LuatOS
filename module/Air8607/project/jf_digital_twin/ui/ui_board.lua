--[[
@module  ui_board
@summary DIGITAL TWIN - 大屏骨架与视图调度（1024x600 横屏）
@version 1.0
@date    2026.10.23
@author  江访

=== 布局 ===
  顶栏 HUD   (y  0..52)   标题 | 视图名 + 说明 | FPS / 图元 / 时钟
  背景层     (全屏)       纯矢量：天空渐变 + 地平线 + 厂房天际线 + 地面 + 光池
  视图层     (全屏)       每页一个透明 root：卡片容器 -> shape -> 图片 -> 文字
  底栏       (y 542..592) 三个视图按钮 + 状态字幕

=== 关键设计决策 ===
1、背景层只建一次、永不刷新（set_items 只在 build 时调一次）。
   它**不能**进每帧的图元池，否则全屏重绘会连带重画一百多个渐变带。
   T.use_photo=true 时才退回到照片底图（真机上会死在内存上，见 theme.lua 文件头）。
2、视图懒加载 + set_hidden(true) 隐藏，不销毁重建：开机只付第一页的开销，
   也避免反复创建/销毁 LVGL 对象（label 目前没有 set_hidden 接口，只能整页隐藏）。
3、时间基准按 mcu.hz() 折算：Air1603 约 20ms/tick，把 tick 当 1ms 会让整条
   时间轴缩放 20 倍（动画慢 20 倍、FPS 还虚报成 299）。
4、动画步长用固定 30ms，只有实测挂起超过 3 帧才按真实时间补跳。
5、文字 5Hz（见 bdui.hot / bdui.put）：set_text 会重排文本并产生额外脏区。
]]

local fx = require "fx"
local T  = require "theme"
local S  = require "scene3d"
local data = require "plant_data"

local v_twin   = require "view_twin"
local v_line   = require "view_line"
local v_energy = require "view_energy"
local VIEWS = { v_twin, v_line, v_energy }

local M = {}

local objs, roots, pills = {}, {}, {}
local curIdx, autoOn, built = 0, true, false

-- ==================== 时间基准 ====================
local TICKS_PER_MS = 1

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    if sys and sys.mtime then return sys.mtime() end
    return os.time() * 1000
end

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end   -- ticks 是 uint32，跨回绕时差值为负
    return d
end

local function init_timebase()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
        log.info("ui_board", string.format(
            "时间基准: mcu.hz()=%d, 每 tick 约 %.1f ms", hz, 1000 / hz))
    else
        TICKS_PER_MS = 1
        log.info("ui_board", "时间基准: mcu.hz() 不可用(PC 模拟器)，按 1 tick/ms")
    end
end

-- ==================== 矢量背景（真机默认路径）====================
--[[
为什么是"一次性 shape"而不是每帧重画：
它只在 build 时 set_items 一次，之后永不 invalidate → 不产生脏区。
每帧真正失效的只有视图那一层（全息网格 / 光柱 / 面板动态件）。
如果把这些静态渐变也放进每帧的池子里，全屏重绘会多背 100 多个图元。

为什么远景厂房放在 z 正方向：
负 z 是近处（sy 往屏幕下方走），z 越大越远、越往地平线 cy 收敛，
厂房是"天际线"，所以 x 铺到 ±6、z 取 +2..+7。
]]
local function build_backdrop(base, SW, SH)
    local P = fx.pool()
    P:reset()

    local HOR = T.cam.cy
    -- 天空：地平线附近最亮，向上压暗到近黑（16 条就够，色带在 600px 高度上不可见）
    local BANDS = 16
    local bh = math.ceil(HOR / BANDS)
    for i = 0, BANDS - 1 do
        local k = (i + 1) / BANDS
        local kk = k * k
        local r = math.floor(0x03 + 0x09 * kk)
        local g = math.floor(0x07 + 0x1D * kk)
        local b = math.floor(0x0D + 0x33 * kk)
        P:box(0, i * bh, SW, bh + 1, (r << 16) | (g << 8) | b, 255, 0)
    end

    -- 地平线光带：三层同色不同透明度，做出"远处有光"的空气感
    P:line(0, HOR - 3, SW, HOR - 3, T.c.cyan, 1, 16)
    P:line(0, HOR - 2, SW, HOR - 2, T.c.cyan, 1, 28)
    P:line(0, HOR - 1, SW, HOR - 1, T.c.cyan, 1, 46)
    P:line(0, HOR,     SW, HOR,     T.c.cyan, 1, 72)
    P:line(0, HOR + 1, SW, HOR + 1, T.c.cyan, 1, 40)

    --[[远景厂房天际线：要塞在 z=5~9（真远处）
    早先放在 z=2~7、高度给到 2.0，算下来盒子顶上冲到 y≈60，
    正好糊在 HUD 标题上，8 个盒子叠成一团乱线。
    现在高度压到 0.6~1.1、z 推到 5~9，天际线稳定落在 y 126~250 这条带里。]]
    local BLDS = {
        { -7.5, 7.0, 1.6, 1.6, 0.80 },
        { -5.6, 5.2, 1.4, 1.4, 0.70 },
        { -3.8, 8.4, 1.8, 1.8, 1.05 },
        { -1.9, 6.0, 1.2, 1.2, 0.62 },
        {  0.2, 8.8, 1.6, 1.6, 0.95 },
        {  2.1, 5.6, 1.3, 1.3, 0.68 },
        {  4.2, 7.6, 1.7, 1.7, 0.90 },
        {  6.4, 5.0, 1.5, 1.5, 0.75 },
    }
    for i = 1, #BLDS do
        local b = BLDS[i]
        S.box(P, b[1], b[2], b[3], b[4], b[5], 0x1E4A6E, 220)
    end

    -- 地平线到画面底部：渐暗的地面（越近越暗，和网格的亮度衰减方向一致）
    local GN = 16
    local gh = math.ceil((SH - HOR) / GN)
    for i = 0, GN - 1 do
        local k = i / (GN - 1)
        local r = math.floor(0x0C - 0x09 * k)
        local g = math.floor(0x17 - 0x11 * k)
        local b = math.floor(0x26 - 0x1E * k)
        P:box(0, HOR + i * gh, SW, gh + 1, (r << 16) | (g << 8) | b, 255, 0)
    end

    --[[全息投射光池：画面底部中央的同心椭圆
    没有照片底图时，中央下半部分是"空的"，光池给它一个"数据投射在地面上"的落点，
    也是整屏唯一一处暖色以外的柔光——视线会被它压住，不会飘。]]
    --[[只画 3 圈、每圈 20 段
    椭圆在 shape 里是"N 段折线"，段数直接等于图元数：6 圈 × 40 段 = 240 个图元，
    比整屏其它东西加起来还多，一加就把帧率从 17 拉到 9（实测）。
    20 段在 300px 宽的椭圆上弦高不到 1px，肉眼分辨不出来。]]
    local pcx, pcy = SW / 2, SH - 116
    P:ellipse(pcx, pcy, 156, 28, T.c.cyan, 1, 40, 20)
    P:ellipse(pcx, pcy, 126, 22, T.c.cyan, 1, 90, 20)
    P:ellipse(pcx, pcy, 96, 16, T.c.cyan, 1, 130, 20)

    P:finish()
    return airui.shape({ parent = base, x = 0, y = 0, w = SW, h = SH, items = P.items })
end

-- ==================== 顶栏 HUD ====================
local function build_hud(base)
    airui.container({
        parent = base, x = 20, y = 12, w = 4, h = 28,
        color = T.c.cyan, color_opacity = 255, radius = 2, border_width = 0,
    })
    airui.label({
        parent = base, x = 32, y = 6, w = 340, h = 20,
        text = "DIGITAL TWIN", font_size = T.f.mini, color = T.c.cyan,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = base, x = 32, y = 22, w = 340, h = 30,
        text = "数字孪生车间", font_size = T.f.val, color = T.c.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })

    M.lbName = airui.label({
        parent = base, x = 300, y = 8, w = 220, h = 26,
        text = "--", font_size = T.f.body, color = T.c.cyan,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbDesc = airui.label({
        parent = base, x = 300, y = 32, w = 420, h = 20,
        text = "", font_size = T.f.mini, color = T.c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    M.lbFps = airui.label({
        parent = base, x = 810, y = 6, w = 194, h = 22,
        text = "FPS --", font_size = T.f.text, color = T.c.teal,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    M.lbInfo = airui.label({
        parent = base, x = 744, y = 28, w = 260, h = 18,
        text = "", font_size = T.f.mini, color = T.c.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 底栏 ====================
local PILL_ON = {
    bg_color = T.c.cyan, bg_opa = 255, text_color = T.c.ink,
    radius = 6, border_width = 1, border_color = T.c.cyan,
    pressed_bg_color = T.c.cyan, pressed_text_color = T.c.ink,
}
local PILL_OFF = {
    bg_color = 0x0A1A2A, bg_opa = 230, text_color = T.c.dim,
    radius = 6, border_width = 1, border_color = T.c.line,
    pressed_bg_color = T.c.cyan, pressed_text_color = T.c.ink,
}

local function build_bar(base)
    airui.container({
        parent = base, x = 12, y = T.bar.y, w = T.screen.w - 24, h = T.bar.h,
        color = 0x050C16, color_opacity = 232, radius = 8,
        border_color = T.c.line, border_width = 1,
    })
    local bar = airui.container({
        parent = base, x = 12, y = T.bar.y, w = T.screen.w - 24, h = T.bar.h,
        color = 0x000000, color_opacity = 0, radius = 8, border_width = 0,
    })

    for i, v in ipairs(T.views) do
        pills[i] = airui.button({
            parent = bar,
            x = T.pill.x - 12 + (i - 1) * (T.pill.w + T.pill.gap),
            y = T.pill.y - T.bar.y,
            w = T.pill.w, h = T.pill.h,
            text = v.name, font_size = T.f.text,
            style = PILL_OFF,
            on_click = function() M.select(i) end,
        })
    end

    M.lbTicker = airui.label({
        parent = bar, x = 404, y = 16, w = 482, h = 20,
        text = "", font_size = T.f.sub, color = T.c.dim,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    M.lbAuto = airui.label({
        parent = bar, x = 874, y = 14, w = 100, h = 22,
        text = "轮播 开", font_size = T.f.mini, color = T.c.cyan,
        align = airui.TEXT_ALIGN_RIGHT,
        on_click = function() M.set_auto(not autoOn) end,
    })
end

-- ==================== 视图切换 ====================
function M.select(i)
    if i < 1 or i > #VIEWS then return end
    if curIdx == i then return end

    if roots[curIdx] then roots[curIdx]:set_hidden(true) end

    local v = VIEWS[i]
    if not objs[i] then
        local root = airui.container({
            parent = M.stage, x = 0, y = 0,
            w = T.screen.w, h = T.screen.h,
            radius = 0, border_width = 0,
        })
        roots[i] = root
        objs[i] = v.build(root, data)
    else
        roots[i]:set_hidden(false)
    end

    -- 场景底图：视图1 全亮，其它视图压暗，让全息层成为主角
    if M.bg then
        M.bg:set_opacity((i == 1) and 255 or 120)
    end

    for k, b in ipairs(pills) do
        b:set_style((k == i) and PILL_ON or PILL_OFF)
    end

    curIdx = i
    M.lbName:set_text(v.name)
    M.lbDesc:set_text(T.views[i].desc)
    log.info("ui_board", "切换视图", v.id, v.name)
end

-- ==================== 骨架 ====================
function M.build(SW, SH)
    if built then return end
    built = true

    data.init()

    local base = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = T.c.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    --[[背景
    真机默认走纯矢量（T.use_photo = false）：1024x600 照片要 2.4MB 连续内存做
    ARGB8888 解码，真机 LVGL 堆虽然空闲 6MB，但碎片化后拿不到这么大的连续块，
    而且解码失败**不会被缓存**，每次重绘都重新解码 369ms —— 日志里 fps=1~2 就是它。
    矢量背景零解码、零混合，且只画一次。]]
    if T.use_photo then
        M.bg = airui.image({
            parent = base, x = 0, y = 0, w = SW, h = SH,
            src = T.asset(T.img.bg), opacity = 255,
        })
        if not M.bg then
            log.warn("ui_board", "场景底图缺失，退化为矢量背景", T.img.dir .. T.img.bg)
            M.bg = nil
            build_backdrop(base, SW, SH)
        end
    else
        build_backdrop(base, SW, SH)
    end

    build_hud(base)

    -- 视图层：所有视图挂在这个透明容器下，切视图只切隐藏
    M.stage = airui.container({
        parent = base, x = 0, y = 0, w = SW, h = SH,
        radius = 0, border_width = 0,
    })

    build_bar(base)
    M.select(1)
end

-- ==================== 主循环 ====================
function M.run()
    init_timebase()

    local t = 0
    local prev = now_ms()
    local waitMs = T.perf.frame_ms
    local frames, fsum = 0, 0
    local fps = 0
    local costAvg = 0
    local textT, autoT = 0, 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now

        local dt
        if realMs > T.perf.frame_ms * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = T.perf.frame_ms / 1000 end
        else
            dt = T.perf.frame_ms / 1000
        end
        t = t + dt

        data.tick(dt)

        -- 只对视图更新单独计时：这个数字是定位"慢在哪"的关键
        local t0 = now_ms()
        local v = VIEWS[curIdx]
        local obj = objs[curIdx]
        if v and obj then
            obj.pool = obj.pool or fx.pool()
            local P = obj.pool
            P:reset()
            local ok, err = pcall(v.update, obj, P, t, dt)
            if not ok then
                log.error("ui_board", "视图帧更新失败", v.id, err)
                sys.wait(1000)
            else
                obj.n = P:finish()
                obj.shape:set_items(P.items)
            end
        end
        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS
        costAvg = costAvg + (cost - costAvg) * 0.15

        frames = frames + 1
        fsum = fsum + realMs / 1000
        if fsum >= 0.5 then
            fps = frames / fsum
            frames, fsum = 0, 0
        end

        -- HUD / 字幕（200ms 节拍）
        textT = textT + realMs / 1000
        if textT >= T.perf.text_ms / 1000 then
            textT = 0
            local lvFps = 0
            local dbg = airui.debug()
            if type(dbg) == "table" then lvFps = dbg.fps or 0 end
            M.lbFps:set_text(string.format("FPS %d/%s",
                math.floor(fps + 0.5), (lvFps > 0) and tostring(lvFps) or "--"))
            M.lbInfo:set_text(string.format("图元 %d | %.1fms | %s",
                (obj and obj.n or 0), costAvg, data.clock_str()))
            M.lbTicker:set_text(string.format(
                "在制 %d 单   良率 %.2f%%   单耗 %.2f kWh/pcs",
                126 + math.floor(t / 7) % 9,
                data.kpi.yield * 100, data.raw.unit))
        end

        -- 自动轮播
        if autoOn then
            autoT = autoT + realMs / 1000
            if autoT >= T.perf.auto_sec then
                autoT = 0
                local nx = curIdx + 1
                if nx > #VIEWS then nx = 1 end
                M.select(nx)
            end
        end

        --[[节拍：sys.wait(x) 是"至少睡这么久"，LVGL 的重绘就发生在我们让出 CPU 的这段时间。
        死守固定节拍会有两种后果：
          - 真机重绘比 frame_ms 慢 → 刷新消息在 msgbus 里堆积 → refresh retry 刷屏；
          - 重绘比 frame_ms 快很多 → 白等，帧率上不去。
        所以按实测 realMs 自适应：跟不上就放宽（上限 frame_max），跟得上就慢慢收回。]]
        local w = waitMs
        if realMs > T.perf.frame_ms * 1.7 then
            w = math.min(w + 10, T.perf.frame_max)
        elseif realMs < T.perf.frame_ms * 1.15 then
            w = math.max(w - 5, T.perf.frame_ms)
        end
        if cost + 2 > w then w = cost + 2 end
        waitMs = w
    end
end

-- 自动轮播开关（给外部/调试用）
function M.set_auto(on)
    autoOn = on and true or false
    if M.lbAuto then
        M.lbAuto:set_text(autoOn and "轮播 开" or "轮播 关")
        M.lbAuto:set_color(autoOn and T.c.cyan or T.c.dim2)
    end
end

return M
