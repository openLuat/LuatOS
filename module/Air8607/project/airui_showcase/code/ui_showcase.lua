--[[
@module  ui_showcase
@summary AirUI 视觉特效演示 - 界面骨架与场景调度（1024x600 横屏）
@version 1.0
@date    2026.10.21

=== 布局（1024x600）===
  顶栏 HUD  (y 0..58)     : 主标题 | 当前场景名 + 说明 | FPS 与图元数
  特效舞台  (y 62..514)   : 994x446 内容区，每个场景在里面铺一个全幅 airui.shape
  场景切换栏(y 522..588)  : 7 个场景按钮 + 自动轮播开关

=== 关键设计决策 ===
1. 场景懒加载 + 隐藏而非销毁：切场景只 set_hidden，避免反复创建/销毁 LVGL 对象；
   首次切到某场景时才 build，开机只付第一个场景的开销。
2. 每个场景挂在自己的 root 容器下：容器是一个透明盒子，隐藏它即隐藏整场景，
   不用逐个控件 set_hidden（label 还没有 set_hidden 接口）。
3. 时间基准用 mcu.ticks() 而不是累加固定步长：sys.wait(33) 的实际间隔会漂移，
   按真实时间推进动画速度才稳定。注意 tick 单位依平台而异（Air1603 约 20ms/tick），
   必须经 mcu.hz() 折算，见下方 init_timebase。
4. HUD 文字每 250ms 才刷新一次：每帧 set_text 会让 LVGL 反复重排文本，
   白白吃掉几百微秒的帧预算。
]]
local fx = require "fx_core"

local M = {}

-- ==================== 场景清单 ====================
local SCENES = {
    require "fx_scene_galaxy",
    require "fx_scene_spectrum",
    require "fx_scene_radar",
    require "fx_scene_gauge",
    require "fx_scene_crystal",     -- 3D 透视线框晶体
    require "fx_scene_tunnel",
    require "fx_scene_globe",       -- 3D 点云星球
}

-- ==================== 布局常量 ====================
--[[目标帧间隔
LVGL 自身的画面刷新周期是固件常量 AIRUI_REFRESH_PERIOD_MS = 33ms。
这里刻意取 30ms 略快一点：两者若完全同频会发生拍频，
周期性出现「这一刷新周期里没等到新数据」的顿挫感。
如果真机仍吃力，把这里调大即可（40 = 25fps，50 = 20fps）。]]
local FRAME_MS = 30
local AUTO_SEC = 7           -- 自动轮播时每个场景停留时长
local HUD_MS = 250           -- HUD 文字刷新间隔

local STAGE_X, STAGE_Y = 12, 62
local STAGE_W, STAGE_H = 1000, 452
local INNER_W, INNER_H = STAGE_W - 6, STAGE_H - 6

local BAR_Y, BAR_H = 522, 66
local PILL_X, PILL_Y = 26, 532
local PILL_W, PILL_H, PILL_GAP = 112, 46, 8
local AUTO_X, AUTO_W = 880, 118

-- ==================== 运行时状态 ====================
local C = fx.C
local objs = {}          -- 已构建的场景对象
local roots = {}         -- 场景 root 容器
local pills = {}         -- 场景按钮
local curIdx = 0
local autoBtn = nil
local autoOn = true
local built = false

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    if sys and sys.mtime then return sys.mtime() end
    return os.time() * 1000
end

-- ==================== 时间基准 ====================
--[[为什么 tick 必须经 mcu.hz() 折算，不能直接 d/1000 当秒
mcu.ticks() 返回的是「系统经历的原始 tick 数」，每 tick 对应多少时间依平台而变：
  模拟器 / Air8000     约 1ms  / tick   (hz = 1000)
  Air1601 / Air1603    约 20ms / tick   (hz = 50)   <- Air8607 主控属于这一档
把每个 tick 当 1ms，整条时间轴就缩放 20 倍：真实 30ms 只被算成 1.5ms，
于是动画慢 20 倍，HUD 的 FPS 还虚报成 299（1/0.0033）—— 这就是"跑得很慢"的根因。
正确写法：秒 = tick差 / mcu.hz()。

PC 模拟器的 luat_mcu_hz() 返回 1（而 luat_mcu_ticks() 本身返回的就是毫秒），
所以 hz <= 1 时按 1 tick/ms 处理，两个平台都能算对。
]]
local TICKS_PER_MS = 1

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end   -- ticks 是 uint32，跨回绕时差值为负
    return d
end

--[[按 mcu.hz() 初始化 tick → 毫秒 的换算系数
@return number 每毫秒的 tick 数（Air1603 上约 0.05）
]]
function M.init_timebase()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
        log.info("ui_showcase", string.format(
            "时间基准: mcu.hz()=%d, 每 tick 约 %.1f ms, 采用 %.4f tick/ms",
            hz, 1000 / hz, TICKS_PER_MS))
    else
        TICKS_PER_MS = 1
        log.info("ui_showcase", "时间基准: mcu.hz() 不可用(PC 模拟器)，按 1 tick/ms")
    end
    return TICKS_PER_MS
end

-- ==================== 顶栏 HUD ====================
local function build_hud(base)
    -- 左侧品牌色条
    airui.container({
        parent = base, x = 18, y = 16, w = 5, h = 30,
        color = C.cyan, color_opacity = 255, radius = 2, border_width = 0,
    })
    airui.label({
        parent = base, x = 32, y = 12, w = 300, h = 32,
        text = "AirUI 视觉特效演示", font_size = 26,
        color = C.txt, align = airui.TEXT_ALIGN_LEFT,
    })

    M.lbName = airui.label({
        parent = base, x = 340, y = 10, w = 180, h = 26,
        text = "--", font_size = 20,
        color = C.cyan, align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbDesc = airui.label({
        parent = base, x = 340, y = 36, w = 470, h = 22,
        text = "", font_size = 16,
        color = C.dim, align = airui.TEXT_ALIGN_LEFT,
    })

    M.lbFps = airui.label({
        parent = base, x = 828, y = 8, w = 180, h = 26,
        text = "FPS --", font_size = 18,
        color = C.green, align = airui.TEXT_ALIGN_RIGHT,
    })
    M.lbInfo = airui.label({
        parent = base, x = 828, y = 34, w = 180, h = 22,
        text = "", font_size = 16,
        color = C.dim2, align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 底部场景切换栏 ====================
local PILL_ON = {
    bg_color = C.cyan, bg_opa = 255, text_color = C.ink,
    radius = 10, border_width = 1, border_color = C.cyan,
    pressed_bg_color = C.cyan, pressed_text_color = C.ink,
}
local PILL_OFF = {
    bg_color = C.panel2, bg_opa = 255, text_color = C.dim,
    radius = 10, border_width = 1, border_color = C.line,
    pressed_bg_color = C.cyan, pressed_text_color = C.ink,
}

local function build_bar(base)
    local bar = airui.container({
        parent = base, x = STAGE_X, y = BAR_Y, w = STAGE_W, h = BAR_H,
        color = C.panel, color_opacity = 255, radius = 12,
        border_color = C.line, border_width = 1,
    })

    --[[按钮统一用 on_click
    这是 agri_greenhouse 工程在本板验证过的写法。此前为了"更跟手"换成
    on_pressed，结果连点击都无法触发，先退回已验证的组合，避免同时变更多个变量。
    M.select 内部有 curIdx == i 的重复调用保护，重复触发也安全。]]
    for i, sc in ipairs(SCENES) do
        pills[i] = airui.button({
            parent = bar,
            x = PILL_X - STAGE_X + (i - 1) * (PILL_W + PILL_GAP),
            y = PILL_Y - BAR_Y,
            w = PILL_W, h = PILL_H,
            text = sc.name, font_size = 18,
            style = PILL_OFF,
            on_click = function()
                M.select(i)
            end,
        })
    end

    autoBtn = airui.button({
        parent = bar,
        x = AUTO_X - STAGE_X, y = PILL_Y - BAR_Y, w = AUTO_W, h = PILL_H,
        text = "自动轮播", font_size = 18,
        style = PILL_ON,
        on_click = function()
            autoOn = not autoOn
            autoBtn:set_style(autoOn and PILL_ON or PILL_OFF)
        end,
    })
end

-- ==================== 场景切换 ====================
--[[切换场景：懒加载 + 隐藏旧容器
@param number i 场景序号（1..#SCENES）
]]
function M.select(i)
    if i < 1 or i > #SCENES then return end
    if curIdx == i then return end

    if roots[curIdx] then roots[curIdx]:set_hidden(true) end

    local sc = SCENES[i]
    if not objs[i] then
        -- 首次进入才构建：root 是透明容器，隐藏它即隐藏整个场景
        local root = airui.container({
            parent = M.stage, x = 0, y = 0, w = INNER_W, h = INNER_H,
            radius = 0, border_width = 0,
        })
        roots[i] = root
        objs[i] = sc.build(root, INNER_W, INNER_H)
    else
        roots[i]:set_hidden(false)
    end

    for k, b in ipairs(pills) do
        b:set_style((k == i) and PILL_ON or PILL_OFF)
    end

    curIdx = i
    M.lbName:set_text(sc.name)
    M.lbDesc:set_text(sc.desc)
    log.info("ui_showcase", "切换场景", sc.id, sc.name)
end

-- ==================== 界面骨架 ====================
--[[搭建整屏界面（在 airui.init + font_load 之后调用）
@param number SW 屏幕宽
@param number SH 屏幕高
]]
function M.build(SW, SH)
    if built then return end
    built = true

    -- 全屏底色
    local base = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    build_hud(base)

    -- 舞台外框（霓虹描边）
    airui.container({
        parent = base, x = STAGE_X, y = STAGE_Y, w = STAGE_W, h = STAGE_H,
        color = C.deep, color_opacity = 255, radius = 12,
        border_color = C.line, border_width = 1,
    })
    -- 舞台内容区：clip_corner 保证场景图元不会溢出圆角
    M.stage = airui.container({
        parent = base, x = STAGE_X + 3, y = STAGE_Y + 3, w = INNER_W, h = INNER_H,
        color = C.deep, color_opacity = 255, radius = 8,
        border_width = 0, clip_corner = true,
    })

    build_bar(base)

    M.select(1)
end

-- ==================== 主动画循环 ====================
--[[逐帧驱动当前场景（阻塞式，请在独立 task 里调用）
循环内做四件事：推进时间 → 调用场景 update → 统计 FPS → 定时刷新 HUD / 自动轮播
]]
function M.run()
    -- 先按 mcu.hz() 建好时间基准，否则 dt 会被整体缩放，动画速度和 FPS 读数都是错的
    M.init_timebase()

    local t = 0
    local prev = now_ms()
    local waitMs = FRAME_MS
    local frames, fsum = 0, 0
    local fps = 0
    local costAvg = 0
    local hudT = 0
    local autoT = 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        -- tick 数必须经 TICKS_PER_MS 折算成毫秒，不能直接除以 1000
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now

        --[[动画步长：正常情况下用固定值，而不是 realMs
        Air1603 的 tick 分辨率约 20ms，比 FRAME_MS(30ms) 还粗。
        直接拿 tick 差当 dt，每帧只能取到 20 或 40ms，动画会一顿一顿地跳。
        而 sys.wait 本身是 1ms 精度的软件定时器，节拍是准的，
        所以固定步长反而最平滑；只有真的挂起过（超过 3 帧）才按真实时间补跳。]]
        local dt
        if realMs > FRAME_MS * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = FRAME_MS / 1000 end
        else
            dt = FRAME_MS / 1000
        end
        t = t + dt

        -- 只对场景更新单独计时：这个数字是定位「慢在哪」的关键
        local t0 = now_ms()
        local sc = SCENES[curIdx]
        local obj = objs[curIdx]
        if sc and obj then
            local ok, err = pcall(sc.update, obj, t, dt)
            if not ok then
                log.error("ui_showcase", "场景帧更新失败", sc.id, err)
                sys.wait(1000)
            end
        end
        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS   -- 毫秒
        costAvg = costAvg + (cost - costAvg) * 0.15     -- 滑动平均，避免数字乱跳

        --[[FPS 统计用真实时间 realMs 而不是固定步长 dt
        tick 只有 20ms 分辨率，单帧看着不准，但累计和等于真正流逝的时间，
        所以 frames / fsum 长期平均是准的。]]        
        frames = frames + 1
        fsum = fsum + realMs / 1000
        if fsum >= 0.5 then
            fps = frames / fsum
            frames, fsum = 0, 0
        end

        -- HUD 文字（计时同样用真实时间，否则掉帧时 HUD 会跟着变慢）
        hudT = hudT + realMs / 1000
        if hudT >= HUD_MS / 1000 then
            hudT = 0
            -- 第二个数字是 LVGL 真实的画面刷新率，用来判断慢的是脚本还是渲染
            local lvFps = 0
            local dbg = airui.debug()
            if type(dbg) == "table" then lvFps = dbg.fps or 0 end
            M.lbFps:set_text(string.format("FPS %d/%s",
                math.floor(fps + 0.5), (lvFps > 0) and tostring(lvFps) or "--"))
            M.lbInfo:set_text(string.format("图元 %d 计算 %.1fms",
                obj and (obj.n or 0) or 0, costAvg))
        end

        -- 自动轮播
        if autoOn then
            autoT = autoT + realMs / 1000
            if autoT >= AUTO_SEC then
                autoT = 0
                local nx = curIdx + 1
                if nx > #SCENES then nx = 1 end
                M.select(nx)
            end
        end

        --[[补偿式节拍
        sys.wait(FRAME_MS) 是「至少睡这么久」，实际周期 = FRAME_MS + 本帧工作耗时，
        于是工作越重帧率越低，会自我恶化。这里按实测耗时把睡眠补回来，
        让周期尽量贴住 FRAME_MS，掉帧时也不会滚雪球。]]
        local w = FRAME_MS - cost
        if w < 2 then w = 2 end
        waitMs = w
    end
end

return M
