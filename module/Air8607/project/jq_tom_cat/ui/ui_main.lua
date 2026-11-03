--[[
@module  ui_main
@summary 汤姆猫 - 界面装配 + 交互状态机 + 主循环
@version 1.0
@date    2026.10.25
@author  蒋骞

=== 三层结构 ===
  shStatic  静态层，开机画一次：背景 + 猫本体（耳朵/身体/头/眼/鼻/胡须）
  shDyn     动态层，每帧重算：尾巴 / 瞳孔 / 眼睑 / 嘴 / 两只前爪 / 粒子
  原生控件  左面板（container + label + button）、头顶气泡
动态层只覆盖猫舞台（theme.stage，598x588），不是整屏，这样每帧无效区减半。

=== 交互状态机 ===
idle --(点击猫身)--> reach(0.10s 爪子扑过去) --> hold(0.75s 捂住 + 抖动)
     --> back(0.20s 弹回身侧) --> idle
按住不放不会重复触发：只在 TP_DOWN 时判定一次（同 PetPark / beat_forge）。
每次触发同时做四件事：中文台词（本地 TTS 播报）、气泡文案、眯眼幅度、粒子与涟漪。

=== "点了就有反应" ===
1. on_touch 里 react() 之后立刻 draw_dynamic() 出一帧，不等主循环的 sleep：
   触摸到画面变化从"最多一个帧周期（33ms）"降到事件处理本身（几毫秒），
   因为 airui 的触摸回调本来就在 LVGL 的 indev 读里，同一轮 handler 就会刷新。
2. 语音在 react() 里只发一条 TTS 请求，不 setup、不 wait（见 app/voice.lua）。
3. 空闲时动态层隔帧重算（idle_every=2），但触摸那一帧强制全量重算。
]]
local T = require "theme"
local fx = require "fx"
local cat = require "cat"
local voice = require "voice"

local W, H = T.screen.w, T.screen.h
local C = T.c
local F = T.f
local SX, SY = T.stage.x, T.stage.y

local M = {}
local o = {}                      -- 界面对象
local rng = fx.rng(os.time() or 20261025)

-- ==================== 时间基准 ====================
local TICKS_PER_MS = 1

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    return 0
end

local function tick_diff(a, b)
    if a >= b then return a - b end
    return a + 4294967296 - b
end

-- ==================== 交互参数 ====================
-- 爪子扑过去要"抢在声音前面"，所以 reach 压到 0.10s；hold 是捂住停留
local PHASE = { reach = 0.10, hold = 0.75, back = 0.20 }  -- 秒
local PAW_OFF = 64      -- 两只前爪相对点击点左右分开的距离
local PAW_DY = 16       -- 前爪中心略低于点击点
local EYE_CX, EYE_CY = 660, 190

-- ==================== 状态 ====================
local S = {
    t = 0,
    phase = "idle",
    ph = 0,
    goal_l = { x = cat.rest_l.x, y = cat.rest_l.y },
    goal_r = { x = cat.rest_r.x, y = cat.rest_r.y },
    paw_l = { x = cat.rest_l.x, y = cat.rest_l.y },
    paw_r = { x = cat.rest_r.x, y = cat.rest_r.y },

    lid = 0,             -- 眼睑闭合 0..1
    lid_t = 0,           -- 本次眨眼的剩余时间
    blink_wait = 2.2,    -- 下次眨眼倒计时
    hold_lid = 0,        -- 被摸时的眯眼目标

    mouth = 0,
    mouth_t = 0,
    bubble_t = 0,
    bubble_on = false,

    eye_dx = 0, eye_dy = 0, eye_tx = 0, eye_ty = 0,

    tail_ph = 0,
    parts = {},
    ripple = nil,
    dirty = true,
}

-- ==================== 小工具 ====================
local function lbl(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h, text = text,
        font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function btn_style(on)
    if on then
        return { bg_color = 0xE9718C, bg_opa = 255, text_color = 0xFFFFFF,
            border_color = 0xC95470, border_width = 2, radius = 16, pad = 0,
            pressed_bg_color = 0xC95470, pressed_text_color = 0xFFFFFF }
    end
    return { bg_color = 0xE7E8EC, bg_opa = 255, text_color = 0x7C879E,
        border_color = 0xCFD3DB, border_width = 2, radius = 16, pad = 0,
        pressed_bg_color = 0xCFD3DB, pressed_text_color = 0x7C879E }
end

-- ==================== 动态层绘制 ====================
local function draw_dynamic()
    local P = o.pDyn
    P:reset()
    cat.draw_dynamic(P, {
        paw_l = S.paw_l,
        paw_r = S.paw_r,
        eye_dx = S.eye_dx,
        eye_dy = S.eye_dy,
        lid = S.lid,
        mouth = S.mouth,
        tail_ph = S.tail_ph,
        parts = S.parts,
        ripple = S.ripple,
    })
    o.nDyn = P:finish()
    o.shDyn:set_items(P.items)
end

-- ==================== 面板 ====================
-- 面板左侧部位、右侧该部位说的话（和 cat.REGIONS 的 say 保持一致）
local ROWS = {
    { "头顶", "谢谢主人", C.accent },
    { "耳朵", "耳朵好痒", C.ear_in },
    { "眼睛", "别戳眼睛", C.iris },
    { "口鼻", "主人你好", C.tongue },
    { "肚子", "肚子好舒服", C.accent2 },
    { "前爪", "手也摸摸", C.fur_light },
    { "后脚", "脚脚怕痒", C.accent },
    { "尾巴", "别拽尾巴", C.nose },
}

local function update_status()
    local s
    local vs = voice.st
    if not vs.ready then
        -- 静音时把探测结果显示出来（ex/audio_v2/audio 各在不在），排查不用连串口
        s = "静音 " .. (vs.diag or "")
    elseif not vs.enabled then
        s = "语音已关闭"
    elseif vs.mode == "ex_tts" then
        s = "语音就绪 exaudio+TTS"
    elseif vs.mode == "ex_stream" then
        s = "语音就绪 WAV 播放"
    elseif vs.mode == "av2_tts" then
        s = "语音就绪 audio_v2 TTS"
    else
        s = "语音就绪 audio TTS"
    end
    if o.lbStatus:get_text() ~= s then o.lbStatus:set_text(s) end
end

local function toggle_sound()
    local on = voice.set_enabled(not voice.st.enabled)
    o.soundBtn:set_text(on and "语音  开" or "语音  关")
    o.soundBtn:set_style(btn_style(on))
    update_status()
    S.dirty = true
end

local function build_panel()
    local P = T.panel
    o.panel = airui.container({
        parent = o.root, x = P.x, y = P.y, w = P.w, h = P.h,
        color = C.panel, color_opacity = 232, radius = 26,
        border_width = 2, border_color = C.panel_brd,
    })

    lbl(o.panel, 24, 16, P.w - 48, 44, "汤姆猫", F.title, C.text)
    lbl(o.panel, 24, 62, P.w - 48, 26, "点猫身上任意位置", F.body, C.text_sub)
    lbl(o.panel, 24, 88, P.w - 48, 26, "两只前爪会捂住那里", F.body, C.text_sub)

    for i, r in ipairs(ROWS) do
        local y = 128 + (i - 1) * 30
        airui.container({
            parent = o.panel, x = 28, y = y + 7, w = 12, h = 12,
            color = r[3], radius = 6, border_width = 0,
        })
        lbl(o.panel, 52, y, 120, 26, r[1], F.body, C.text)
        lbl(o.panel, 176, y, 150, 26, r[2], F.body, C.text_sub)
    end

    o.soundBtn = airui.button({
        parent = o.panel, x = 24, y = 372, w = P.w - 48, h = 48,
        text = voice.st.enabled and "语音  开" or "语音  关",
        font_size = F.btn, style = btn_style(voice.st.enabled),
        on_click = toggle_sound,
    })

    o.lbStatus = lbl(o.panel, 24, 430, P.w - 48, 24, "", F.small, C.text_sub)
    lbl(o.panel, 24, 456, P.w - 48, 22, "点空白处不会有反应", F.small, 0xA9B0BF)
    o.lbFps = lbl(o.panel, 24, 484, P.w - 48, 22, "", F.small, 0xA9B0BF)
end

-- ==================== 气泡 ====================
local function set_bubble(text, secs)
    if o.bubbleLabel:get_text() ~= text then o.bubbleLabel:set_text(text) end
    if not S.bubble_on then
        o.bubble:set_hidden(false)
        S.bubble_on = true
    end
    S.bubble_t = secs
end

-- ==================== 交互 ====================
local function spawn_particles(x, y, color)
    local n = #S.parts
    if n > 32 then return end
    for i = 1, 7 do
        local a = (i / 7) * fx.TAU + rng() * 0.6
        local sp = 45 + rng() * 65
        local life = 0.5 + rng() * 0.3
        S.parts[#S.parts + 1] = {
            x = x, y = y,
            vx = math.cos(a) * sp,
            vy = math.sin(a) * sp - 45,
            life = life, max = life,
            r = 5 + rng() * 4,
            color = (i % 2 == 0) and color or 0xFFFFFF,
        }
    end
end

local function react(region_id, x, y)
    local rg = cat.REGIONS[region_id]
    if not rg then return end

    S.phase = "reach"
    S.ph = 0
    -- 每个部位的前爪分开距离不一样：摸脸要分开宽一点，否则爪子把张开的嘴挡没了
    local spread = rg.spread or PAW_OFF
    local dy = rg.dy or PAW_DY
    S.goal_l.x = fx.clamp(x - spread, 480, 840)
    S.goal_l.y = fx.clamp(y + dy, 90, 540)
    S.goal_r.x = fx.clamp(x + spread, 480, 840)
    S.goal_r.y = S.goal_l.y

    -- 瞳孔追着点击点看
    S.eye_tx = fx.clamp((x - EYE_CX) / 70, -1, 1) * 9
    S.eye_ty = fx.clamp((y - EYE_CY) / 70, -1, 1) * 7

    S.hold_lid = rg.lid

    -- 一句中文台词：气泡 + 张嘴时长。
    -- 张嘴/气泡按字数估时：一个汉字 3 字节、念一字约 0.22s
    local chars = math.max(2, math.floor(#rg.say / 3 + 0.5))
    local dur = 0.25 + chars * 0.22
    S.mouth_t = dur
    set_bubble(rg.say, dur + 0.6)

    spawn_particles(x, y, rg.color)
    S.ripple = { x = x, y = y, r = 8, life = 0.30, max = 0.30, color = rg.color }
    S.dirty = true

    log.info("tomcat", "摸到", region_id, rg.say)

    -- 语音不在这里发：先让画面刷出去，播报交给调用方在出帧之后异步起（见 on_touch）
    return rg.say
end

-- 触摸常量按 C 层枚举兜底：个别固件不导出 TP_*，直接比 nil 会让整个界面点不动
local TP_DOWN = airui.TP_DOWN or 1

local function on_touch(state, x, y)
    if state ~= TP_DOWN then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end

    -- 左面板归原生控件，不参与猫的命中
    local P = T.panel
    if x >= P.x and x < P.x + P.w and y >= P.y and y < P.y + P.h then return end
    -- 气泡可见时，气泡区域也算控件（避免点气泡顺带摸头）
    local B = T.bubble
    if S.bubble_on and x >= B.x and x < B.x + B.w and y >= B.y and y < B.y + B.h then return end

    local tail_x, tail_y = cat.tail_tip(S.tail_ph)
    local id = cat.hit(x, y, S.paw_l, S.paw_r, tail_x, tail_y)
    if not id then return end

    local say_text = react(id, x, y)

    -- 先出帧：这里本来就在 LVGL 的 indev 回调里，同一轮 handler 就会刷屏，
    -- 触摸到画面变化从"最多等一个帧周期"降到事件处理本身（几毫秒）。
    -- 推 16ms 是为了让爪子第一帧就有明显位移，不然 ph=0 时爪子还在原位。
    M.update(0.016)
    draw_dynamic()

    -- 再起播：play_start 是同步 C 调用，放这里会拖慢上面那帧上屏，
    -- 丢给任务里做，画面立刻刷出、语音晚几毫秒起（听感上仍是"同时"）
    if say_text then
        sys.taskInit(function() voice.say(id, say_text) end)
    end
end

-- ==================== 构建 ====================
function M.build()
    if o.root then return false end

    o.root = airui.container({
        parent = nil, x = 0, y = 0, w = W, h = H,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    -- 静态层（整屏）→ 动态层（猫舞台）→ 面板 / 气泡（原生控件压在画面上）
    o.shStatic = airui.shape({ parent = o.root, x = 0, y = 0, w = W, h = H, items = {} })
    o.shDyn = airui.shape({
        parent = o.root, x = SX, y = SY,
        w = T.stage.w, h = T.stage.h, items = {},
    })

    local P = fx.pool(0, 0)
    cat.draw_static(P)
    o.shStatic:set_items(P.items)
    log.info("tomcat", "静态层图元", P:size())

    build_panel()

    local B = T.bubble
    o.bubble = airui.container({
        parent = o.root, x = B.x, y = B.y, w = B.w, h = B.h,
        color = 0xFFFFFF, color_opacity = 242, radius = 28,
        border_width = 2, border_color = C.accent,
    })
    o.bubbleLabel = lbl(o.bubble, 0, 12, B.w, 34, "", F.bubble, C.text,
        airui.TEXT_ALIGN_CENTER)
    o.bubble:set_hidden(true)

    o.pDyn = fx.pool(SX, SY)
    draw_dynamic()
    update_status()

    log.info("tomcat", "界面构建完成", "airui", tostring(airui.version and airui.version()))
    return true
end

-- ==================== 每帧推进 ====================
function M.update(dt)
    S.t = S.t + dt
    S.tail_ph = S.tail_ph + dt * 2.1

    -- ---- 眨眼 ----
    if S.lid_t > 0 then S.lid_t = S.lid_t - dt end
    S.blink_wait = S.blink_wait - dt
    if S.blink_wait <= 0 and S.lid_t <= 0 then
        S.lid_t = 0.17
        S.blink_wait = 2.4 + rng() * 3.6
    end
    local lid = S.hold_lid
    if S.lid_t > 0 then
        local b = math.sin((1 - S.lid_t / 0.17) * math.pi)
        if b > lid then lid = b end
    end
    S.lid = fx.approach(S.lid, lid, 0.55, dt)
    if S.lid < 0.02 then S.lid = 0 end

    -- ---- 前爪相位机 ----
    if S.phase == "reach" then
        S.ph = S.ph + dt
        local p = fx.ease_out(S.ph / PHASE.reach)
        S.paw_l.x = fx.lerp(cat.rest_l.x, S.goal_l.x, p)
        S.paw_l.y = fx.lerp(cat.rest_l.y, S.goal_l.y, p)
        S.paw_r.x = fx.lerp(cat.rest_r.x, S.goal_r.x, p)
        S.paw_r.y = fx.lerp(cat.rest_r.y, S.goal_r.y, p)
        if S.ph >= PHASE.reach then S.phase = "hold"; S.ph = 0 end
    elseif S.phase == "hold" then
        S.ph = S.ph + dt
        local jx = math.sin(S.t * 21) * 3
        local jy = math.cos(S.t * 17) * 2
        S.paw_l.x = S.goal_l.x + jx
        S.paw_l.y = S.goal_l.y + jy
        S.paw_r.x = S.goal_r.x - jx
        S.paw_r.y = S.goal_r.y + jy
        if S.ph >= PHASE.hold then
            S.phase = "back"
            S.ph = 0
            S.hold_lid = 0
            S.eye_tx, S.eye_ty = 0, 0
        end
    elseif S.phase == "back" then
        S.ph = S.ph + dt
        local p = fx.ease_back(S.ph / PHASE.back)
        S.paw_l.x = fx.lerp(S.goal_l.x, cat.rest_l.x, p)
        S.paw_l.y = fx.lerp(S.goal_l.y, cat.rest_l.y, p)
        S.paw_r.x = fx.lerp(S.goal_r.x, cat.rest_r.x, p)
        S.paw_r.y = fx.lerp(S.goal_r.y, cat.rest_r.y, p)
        if S.ph >= PHASE.back then
            S.phase = "idle"
            S.ph = 0
            S.paw_l.x, S.paw_l.y = cat.rest_l.x, cat.rest_l.y
            S.paw_r.x, S.paw_r.y = cat.rest_r.x, cat.rest_r.y
        end
    end

    -- ---- 嘴巴 ----
    if S.mouth_t > 0 then S.mouth_t = S.mouth_t - dt end
    S.mouth = fx.approach(S.mouth, (S.mouth_t > 0) and 1 or 0, 0.5, dt)
    if S.mouth < 0.04 then S.mouth = 0 end

    -- ---- 瞳孔 ----
    S.eye_dx = fx.approach(S.eye_dx, S.eye_tx, 0.10, dt)
    S.eye_dy = fx.approach(S.eye_dy, S.eye_ty, 0.10, dt)

    -- ---- 气泡 ----
    if S.bubble_t > 0 then
        S.bubble_t = S.bubble_t - dt
        if S.bubble_t <= 0 and S.bubble_on then
            o.bubble:set_hidden(true)
            S.bubble_on = false
        end
    end

    -- ---- 粒子 ----
    for i = #S.parts, 1, -1 do
        local p = S.parts[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(S.parts, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy - 24 * dt      -- 轻轻上飘
            p.vx = p.vx * 0.985
        end
    end

    -- ---- 涟漪 ----
    local rp = S.ripple
    if rp then
        rp.life = rp.life - dt
        rp.r = rp.r + dt * 130
        if rp.life <= 0 then S.ripple = nil end
    end

    -- ---- 是否需要重画 ----
    S.dirty = (S.phase ~= "idle") or S.mouth > 0 or S.lid > 0
        or #S.parts > 0 or S.ripple ~= nil
end

-- ==================== HUD ====================
local hudTxt = {}
local function set_txt(lb, key, s)
    if hudTxt[key] ~= s then
        hudTxt[key] = s
        lb:set_text(s)
    end
end

local function update_hud()
    -- 音频流任务是异步启动的，状态行必须周期刷新，否则会一直停在"静音模式"
    update_status()

    local dbg = airui.debug and airui.debug()
    local fps = (type(dbg) == "table" and dbg.fps) or 0
    set_txt(o.lbFps, "fps", string.format("FPS %d   图元 %d",
        math.floor(fps + 0.5), o.nDyn or 0))
end

-- ==================== 主循环 ====================
function M.run()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then TICKS_PER_MS = hz / 1000 end

    airui.touch_subscribe(on_touch)
    log.info("tomcat", "主循环启动")

    local last = now_ms()
    local frame = 0
    local hudT = 1000
    while true do
        local t0 = now_ms()

        -- 用实测帧间隔推进动画：sys.wait 是"至少睡 N 毫秒"，帧率掉下来时
        -- 固定 dt 会让动作整体变慢（捂爪/张嘴就和声音对不上了）。
        -- 单帧上限 80ms：偶发一次长阻塞不应该让动画"跳一格"。
        local dt = tick_diff(t0, last) / TICKS_PER_MS / 1000
        last = t0
        if dt <= 0.001 then
            dt = T.perf.frame_ms / 1000
        elseif dt > 0.08 then
            dt = 0.08
        end
        M.update(dt)

        frame = frame + 1
        if S.dirty or (frame % T.perf.idle_every) == 0 then
            draw_dynamic()
        end

        hudT = hudT + T.perf.frame_ms
        if hudT >= T.perf.hud_ms then
            hudT = 0
            update_hud()
        end

        -- 等待扣掉本轮耗时：固定节拍，不累加漂移
        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS
        local w = T.perf.frame_ms - cost
        if w < 5 then w = 5 end
        sys.wait(w)
    end
end

M.S = S

return M
