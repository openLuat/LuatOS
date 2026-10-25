--[[
@module  ui_board
@summary INDUS BOARD - 看板骨架与视图调度（1024x600 横屏）
@version 1.0
@date    2026.10.23
@author  江访

=== 布局（1024x600）===
  顶栏 HUD   (y  0..58)   标题 | 视图名 + 说明 | FPS / LVGL-FPS / 图元数 / 时钟
  舞台       (y 62..514)  不等分栏大屏，每页一张 rect 表（见 bd_*.lua）
  视图切换栏 (y 522..588) 产线总览 / 设备监控 / 质量能耗 + 自动轮播开关

=== 关键设计决策 ===
1、一个视图 = 一个 airui.shape + 一批 label：
   整页动态图元全部写进同一个图元池，一帧只 set_items 一次。
   若每个分块各挂一个 shape，LVGL 每帧要遍历多个对象、算多个脏区，
   开销直接翻倍而且看不出好处。
2、视图懒加载 + 隐藏而非销毁：切视图只 set_hidden，避免反复创建/销毁 LVGL 对象；
   首次切到某视图时才 build，开机只付第一个视图的开销。
   root 是透明容器，隐藏它即隐藏整页（label 还没有 set_hidden 接口）。
3、时间基准用 mcu.ticks() 并按 mcu.hz() 折算：
   Air1603 上约 20ms/tick，把每个 tick 当 1ms 会让整条时间轴缩放 20 倍，
   动画慢 20 倍、FPS 还虚报成 299。见下方 init_timebase。
4、动画步长用固定值而不是 tick 差：
   tick 分辨率 20ms 比帧间隔 30ms 还粗，直接当 dt 会一顿一顿地跳；
   sys.wait 是 1ms 精度软件定时器，固定步长反而最平滑。
5、文字 200ms 才刷新：set_text 会让 LVGL 重排文本并额外产生一块脏区。
]]

local fx = require "fx"
local T = require "theme"
local data = require "board_data"

-- 三张视图（顺序与 theme.views 一致）
-- require 先落到局部变量再组表：写成 { require "x", ... } 会被 Lua 的多返回值展平
local v_overview  = require "bd_overview"
local v_equipment = require "bd_equipment"
local v_quality   = require "bd_quality"
local VIEWS = { v_overview, v_equipment, v_quality }

local M = {}

-- ==================== 运行时状态 ====================
local objs = {}          -- 已构建的视图对象
local roots = {}         -- 视图 root 容器
local pills = {}         -- 视图按钮
local curIdx = 0
local autoBtn = nil
local autoOn = true
local built = false

-- ==================== 时间基准 ====================
--[[tick 必须经 mcu.hz() 折算成毫秒
mcu.ticks() 返回原始 tick 数，每 tick 多少时间依平台而变：
  模拟器 / Air8000     约 1ms  / tick   (hz = 1000)
  Air1601 / Air1603    约 20ms / tick   (hz = 50)   <- Air8607 主控属于这一档
PC 模拟器的 luat_mcu_hz() 返回 1（而 ticks 本身就是毫秒），
所以 hz <= 1 时按 1 tick/ms 处理，两个平台都能算对。]]
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

-- ==================== 顶栏 HUD ====================
local function build_hud(base)
    airui.container({
        parent = base, x = 18, y = 14, w = 5, h = 30,
        color = T.c.cyan, color_opacity = 255, radius = 2, border_width = 0,
    })
    airui.label({
        parent = base, x = 32, y = 10, w = 300, h = 32,
        text = "工业产线看板", font_size = 26,
        color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
    })

    M.lbName = airui.label({
        parent = base, x = 336, y = 8, w = 160, h = 26,
        text = "--", font_size = T.f.body,
        color = T.c.cyan, align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbDesc = airui.label({
        parent = base, x = 336, y = 34, w = 480, h = 22,
        text = "", font_size = T.f.text,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })

    M.lbFps = airui.label({
        parent = base, x = 820, y = 6, w = 188, h = 26,
        text = "FPS --", font_size = T.f.text,
        color = T.c.green, align = airui.TEXT_ALIGN_RIGHT,
    })
    M.lbInfo = airui.label({
        parent = base, x = 820, y = 32, w = 188, h = 22,
        text = "", font_size = T.f.mini,
        color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 底部视图切换栏 ====================
local PILL_ON = {
    bg_color = T.c.cyan, bg_opa = 255, text_color = T.c.ink,
    radius = 10, border_width = 1, border_color = T.c.cyan,
    pressed_bg_color = T.c.cyan, pressed_text_color = T.c.ink,
}
local PILL_OFF = {
    bg_color = 0x131E33, bg_opa = 255, text_color = T.c.dim,
    radius = 10, border_width = 1, border_color = T.c.line,
    pressed_bg_color = T.c.cyan, pressed_text_color = T.c.ink,
}

local function build_bar(base)
    local bar = airui.container({
        parent = base, x = T.stage.x, y = T.bar.y, w = T.stage.w, h = T.bar.h,
        color = 0x0D1424, color_opacity = 255, radius = 12,
        border_color = T.c.line, border_width = 1,
    })

    --[[按钮统一用 on_click
    这是 agri_greenhouse / airui_showcase 在本板验证过的写法：
    on_pressed 在本板连点击都触发不了。M.select 内部有 curIdx == i 的重复调用保护。]]
    for i, v in ipairs(T.views) do
        pills[i] = airui.button({
            parent = bar,
            x = T.pill.x - T.stage.x + (i - 1) * (T.pill.w + T.pill.gap),
            y = T.pill.y - T.bar.y,
            w = T.pill.w, h = T.pill.h,
            text = v.name, font_size = T.f.text,
            style = PILL_OFF,
            on_click = function()
                M.select(i)
            end,
        })
    end

    autoBtn = airui.button({
        parent = bar,
        x = T.auto.x - T.stage.x, y = T.auto.y - T.bar.y,
        w = T.auto.w, h = T.auto.h,
        text = "自动轮播", font_size = T.f.text,
        style = PILL_ON,
        on_click = function()
            autoOn = not autoOn
            autoBtn:set_style(autoOn and PILL_ON or PILL_OFF)
        end,
    })
end

-- ==================== 视图切换 ====================
--[[切换视图：懒加载 + 隐藏旧容器
@param number i 视图序号（1..#VIEWS）
]]
function M.select(i)
    if i < 1 or i > #VIEWS then return end
    if curIdx == i then return end

    if roots[curIdx] then roots[curIdx]:set_hidden(true) end

    local v = VIEWS[i]
    if not objs[i] then
        local root = airui.container({
            parent = M.stage, x = 0, y = 0, w = T.inner.w, h = T.inner.h,
            radius = 0, border_width = 0,
        })
        roots[i] = root
        objs[i] = v.build(root, v.rects, data)
    else
        roots[i]:set_hidden(false)
    end

    for k, b in ipairs(pills) do
        b:set_style((k == i) and PILL_ON or PILL_OFF)
    end

    curIdx = i
    M.lbName:set_text(v.name)
    M.lbDesc:set_text(T.views[i].desc)
    log.info("ui_board", "切换视图", v.id, v.name)
end

-- ==================== 界面骨架 ====================
--[[搭建整屏界面（在 airui.init + font_load 之后调用）
@param number SW 屏幕宽
@param number SH 屏幕高
]]
function M.build(SW, SH)
    if built then return end
    built = true

    data.init()

    local base = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = T.c.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    build_hud(base)

    -- 舞台外框
    airui.container({
        parent = base, x = T.stage.x, y = T.stage.y, w = T.stage.w, h = T.stage.h,
        color = T.c.deep, color_opacity = 255, radius = 12,
        border_color = T.c.line, border_width = 1,
    })
    -- 舞台内容区：clip_corner 保证图元不会溢出圆角
    M.stage = airui.container({
        parent = base, x = T.inner.x, y = T.inner.y, w = T.inner.w, h = T.inner.h,
        color = T.c.deep, color_opacity = 255, radius = 8,
        border_width = 0, clip_corner = true,
    })

    build_bar(base)
    M.select(1)
end

-- ==================== 主动画循环 ====================
--[[逐帧驱动当前视图（阻塞式，请在独立 task 里调用）
推进时间 -> 数据模拟 -> 统计 FPS -> 视图 update -> 定时刷新 HUD / 自动轮播
]]
function M.run()
    init_timebase()

    local t = 0
    local prev = now_ms()
    local waitMs = T.perf.frame_ms
    local frames, fsum = 0, 0
    local fps = 0
    local costAvg = 0
    local hudT = 0
    local autoT = 0
    local textT = 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now

        --[[动画步长用固定值，只有真的挂起过（超过 3 帧）才按真实时间补跳
        见文件头"关键设计决策 4"。]]
        local dt
        if realMs > T.perf.frame_ms * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = T.perf.frame_ms / 1000 end
        else
            dt = T.perf.frame_ms / 1000
        end
        t = t + dt

        -- 数据模拟先走（视图的 update 只读不写）
        data.tick(dt)

        -- 只对视图更新单独计时：这个数字是定位「慢在哪」的关键
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

        -- HUD 文字（200ms 节拍）
        textT = textT + realMs / 1000
        if textT >= T.perf.text_ms / 1000 then
            textT = 0
            local lvFps = 0
            local dbg = airui.debug()
            if type(dbg) == "table" then lvFps = dbg.fps or 0 end
            M.lbFps:set_text(string.format("FPS %d/%s",
                math.floor(fps + 0.5), (lvFps > 0) and tostring(lvFps) or "--"))
            M.lbInfo:set_text(string.format("图元 %d  计算 %.1fms  %s",
                obj and (obj.n or 0) or 0, costAvg, data.clock_str()))
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

        --[[补偿式节拍
        sys.wait(x) 是「至少睡这么久」，工作越重帧率越低会自我恶化，
        这里按实测耗时把睡眠补回来。]]
        local w = T.perf.frame_ms - cost
        if w < 2 then w = 2 end
        waitMs = w
    end
end

return M
