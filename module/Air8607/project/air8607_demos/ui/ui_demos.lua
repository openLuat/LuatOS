--[[
@module  ui_demos
@summary 场景演示外壳：HUD + 舞台 + 底部切换栏 + 自动轮播
@date    2026.10.26
@design
每个应用场景 = 一个独立 demo 文档（ui/demo_*.lua），对外只暴露 3 个字段：
  M.id / M.name / M.desc  场景标识与文案
  M.build(root, W, H)     在 root 容器内搭建静态控件，返回场景对象 obj
  M.update(obj, t, dt)    每帧刷新动态图元（obj 内的 shape + label）
外壳负责：懒加载场景、隐藏/显示 root、底部按钮切换、自动轮播、FPS HUD。
]]
local fx = require "fx"

local M = {}

-- 场景清单：新增 demo 只需在此追加一行
local SCENES = {
    require "demo_power",
    require "demo_pump",
    require "demo_line",
    require "demo_env",
    require "demo_energy",
}

-- ==================== 布局常量（1024x600） ====================
local FRAME_MS = 30          -- 目标帧间隔（略快于 LVGL 刷新周期 33ms，避免拍频）
local AUTO_SEC = 12          -- 自动轮播时每个场景停留时长
local HUD_MS = 250           -- HUD 刷新间隔

local STAGE_X, STAGE_Y = 12, 62
local STAGE_W, STAGE_H = 1000, 452
local INNER_W, INNER_H = STAGE_W - 6, STAGE_H - 6

local BAR_Y, BAR_H = 522, 66
local PILL_X, PILL_Y = 26, 532
local PILL_H = 46
local AUTO_X0, AUTO_W = 880, 118

-- ==================== 调色 ====================
local C = fx.C

-- ==================== 运行时状态 ====================
local objs, roots, pills = {}, {}, {}
local curIdx = 0
local autoBtn = nil
local autoOn = true
local built = false

-- ==================== 时间基准 ====================
--[[tick 必须经 mcu.hz() 折算：
  PC 模拟器  1 tick ≈ 1ms (hz=1)
  Air1603    1 tick ≈ 20ms (hz=50)   <- Air8607 主控
不折算则动画慢 20 倍。]]
local TICKS_PER_MS = 1

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    if sys and sys.mtime then return sys.mtime() end
    return os.time() * 1000
end

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end   -- uint32 回绕
    return d
end

function M.init_timebase()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
    else
        TICKS_PER_MS = 1
    end
    log.info("ui_demos", string.format("时间基准 %.4f tick/ms", TICKS_PER_MS))
    return TICKS_PER_MS
end

-- ==================== 顶栏 HUD ====================
local function build_hud(base)
    airui.container({
        parent = base, x = 18, y = 16, w = 5, h = 30,
        color = C.cyan, color_opacity = 255, radius = 2, border_width = 0,
    })
    airui.label({
        parent = base, x = 32, y = 12, w = 340, h = 32,
        text = "Air8607 工业场景 UI 演示", font_size = 22, color = C.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbName = airui.label({
        parent = base, x = 380, y = 12, w = 300, h = 32,
        text = "", font_size = 22, color = C.cyan,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbDesc = airui.label({
        parent = base, x = 380, y = 40, w = 440, h = 18,
        text = "", font_size = 13, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbFps = airui.label({
        parent = base, x = 840, y = 10, w = 168, h = 20,
        text = "FPS --/--", font_size = 14, color = C.dim,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    M.lbInfo = airui.label({
        parent = base, x = 840, y = 32, w = 168, h = 18,
        text = "", font_size = 12, color = C.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
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

    local n = #SCENES
    local pillW = math.floor((AUTO_X0 - PILL_X - (n - 1) * 8) / n)
    for i, sc in ipairs(SCENES) do
        local b = airui.button({
            parent = bar,
            x = PILL_X - STAGE_X + (i - 1) * (pillW + 8), y = PILL_Y - BAR_Y,
            w = pillW, h = PILL_H,
            text = sc.name, font_size = 17,
            style = PILL_OFF,
            on_click = function()
                M.select(i)
            end,
        })
        pills[i] = b
    end

    autoBtn = airui.button({
        parent = bar,
        x = AUTO_X0 - STAGE_X, y = PILL_Y - BAR_Y, w = AUTO_W, h = PILL_H,
        text = "自动轮播", font_size = 17,
        style = PILL_ON,
        on_click = function()
            autoOn = not autoOn
            autoBtn:set_style(autoOn and PILL_ON or PILL_OFF)
        end,
    })
end

-- ==================== 场景切换 ====================
function M.select(i)
    if i < 1 or i > #SCENES then return end
    if curIdx == i then return end

    if roots[curIdx] then roots[curIdx]:set_hidden(true) end

    local sc = SCENES[i]
    if not objs[i] then
        -- 懒加载：root 为透明容器，隐藏它即隐藏整个场景，不销毁对象
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
    log.info("ui_demos", "切换场景", sc.id, sc.name)
end

-- ==================== 界面骨架 ====================
function M.build(SW, SH)
    if built then return end
    built = true

    local base = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    build_hud(base)

    airui.container({
        parent = base, x = STAGE_X, y = STAGE_Y, w = STAGE_W, h = STAGE_H,
        color = C.deep, color_opacity = 255, radius = 12,
        border_color = C.line, border_width = 1,
    })
    M.stage = airui.container({
        parent = base, x = STAGE_X + 3, y = STAGE_Y + 3, w = INNER_W, h = INNER_H,
        color = C.deep, color_opacity = 255, radius = 8,
        border_width = 0, clip_corner = true,
    })

    build_bar(base)
    M.select(1)
end

-- ==================== 主动画循环 ====================
function M.run()
    M.init_timebase()

    local t = 0
    local prev = now_ms()
    local waitMs = FRAME_MS
    local frames, fsum = 0, 0
    local fps = 0
    local costAvg = 0
    local hudT, autoT = 0, 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now

        -- 固定步长动画；仅长时间挂起时按真实时间补跳
        local dt
        if realMs > FRAME_MS * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = FRAME_MS / 1000 end
        else
            dt = FRAME_MS / 1000
        end
        t = t + dt

        local t0 = now_ms()
        local sc = SCENES[curIdx]
        local obj = objs[curIdx]
        if sc and obj then
            local ok, err = pcall(sc.update, obj, t, dt)
            if not ok then
                log.error("ui_demos", "场景帧更新失败", sc.id, err)
                sys.wait(1000)
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

        hudT = hudT + realMs / 1000
        if hudT >= HUD_MS / 1000 then
            hudT = 0
            local lvFps = 0
            local dbg = airui.debug()
            if type(dbg) == "table" then lvFps = dbg.fps or 0 end
            M.lbFps:set_text(string.format("FPS %d/%s",
                math.floor(fps + 0.5), (lvFps > 0) and tostring(lvFps) or "--"))
            M.lbInfo:set_text(string.format("图元 %d 计算 %.1fms",
                obj and (obj.n or 0) or 0, costAvg))
        end

        if autoOn then
            autoT = autoT + realMs / 1000
            if autoT >= AUTO_SEC then
                autoT = 0
                local nx = curIdx + 1
                if nx > #SCENES then nx = 1 end
                M.select(nx)
            end
        end

        -- 补偿式节拍：把本帧工作耗时补回睡眠，掉帧不滚雪球
        local w = FRAME_MS - cost
        if w < 2 then w = 2 end
        waitMs = w
    end
end

return M
