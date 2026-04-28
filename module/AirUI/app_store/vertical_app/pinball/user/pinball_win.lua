--[[
@module  pinball_win
@summary 二维弹球：挡板、缓冲器、落孔失球、计分
]]

-- exapp 沙箱里包装后的 exwin 在 _ENV 上；rawget(_G,"exwin") 易误用裸 exwin，退出后无法 exapp.close
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

local phys = require "pinball_physics"

local win_id = nil
local main_container = nil
local game_area = nil
local game_timer = nil

local SCREEN_W = 480
local SCREEN_H = 800
local GAME_Y = 52
local GAME_H = 600

-- 台面逻辑坐标（相对 game_area）
local PLAY_L = 14
local PLAY_R = 466
local PLAY_TOP = 38
local PLAY_BOT = 558
local BALL_R = 9

local score_label = nil
local lives_label = nil
local hint_label = nil
local ball_gfx = nil
local bumper_gfx = {}
local destroyed = false

local world = nil
local score = 0
local lives = 3
local best_score = 0
local waiting_launch = true
local left_ms = 0
local right_ms = 0
--- 底部控制条按住挡板（与台面触摸分离，不误触）
local left_hold = false
local right_hold = false
--- TP_HOLD 时若每次用 x 重算左右，坐标抖动会导致右挡图像闪烁；按下时锁定一侧直至抬起
local flip_touch_lock = nil

local TICK_MS = 16
local SUBSTEPS = 4
local FLIPPER_HOLD_MS = 400

local flip_L_gfx = {}
local flip_R_gfx = {}

local function ensure_airui()
    if not airui or not airui.init then
        return false
    end
    if type(exapp) == "table" then
        return true
    end
    local bsp = (rtos and rtos.bsp and rtos.bsp()) or ""
    bsp = tostring(bsp)
    if bsp:upper():find("PC", 1, true) then
        return airui.init(480, 800, airui.COLOR_FORMAT_ARGB8888)
    end
    local w, h = 480, 800
    if lcd and lcd.getSize then
        w, h = lcd.getSize()
    end
    return airui.init(w, h)
end

local function stroke_segment(parent, x1, y1, x2, y2, color)
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local n = math.max(2, math.floor(len / 9))
    for i = 0, n do
        local t = i / n
        local px = math.floor(x1 + dx * t - 4)
        local py = math.floor(y1 + dy * t - 4)
        airui.container({
            parent = parent,
            x = px,
            y = py,
            w = 9,
            h = 9,
            color = color,
            radius = 2,
        })
    end
end

local function build_world()
    local segments = {
        { x1 = PLAY_L, y1 = PLAY_TOP, x2 = PLAY_R, y2 = PLAY_TOP, rest = 0.78 },
        { x1 = PLAY_L, y1 = PLAY_TOP, x2 = PLAY_L, y2 = PLAY_BOT - 72, rest = 0.78 },
        { x1 = PLAY_R, y1 = PLAY_TOP, x2 = PLAY_R, y2 = PLAY_BOT - 72, rest = 0.78 },
        { x1 = PLAY_L, y1 = PLAY_BOT - 72, x2 = 168, y2 = PLAY_BOT, rest = 0.82 },
        { x1 = PLAY_R, y1 = PLAY_BOT - 72, x2 = 312, y2 = PLAY_BOT, rest = 0.82 },
        -- 顶部两角导向
        { x1 = PLAY_L, y1 = PLAY_TOP + 120, x2 = 108, y2 = PLAY_TOP + 210, rest = 0.76 },
        { x1 = PLAY_R, y1 = PLAY_TOP + 120, x2 = 372, y2 = PLAY_TOP + 210, rest = 0.76 },
    }

    local bumpers = {
        { cx = 240, cy = 118, r = 20, points = 150, restitution = 1.1 },
        { cx = 150, cy = 228, r = 17, points = 120, restitution = 1.1 },
        { cx = 330, cy = 228, r = 17, points = 120, restitution = 1.1 },
        { cx = 240, cy = 318, r = 15, points = 100, restitution = 1.08 },
    }

    -- 屏幕 +y 向下。a_rest=放下（杆尖略朝台面内下方），a_hit=按下抬起击打（杆尖上摆）
    -- 逻辑：pressed → 插值向 a_hit；未按 → 向 a_rest（与 pinball_physics.update_flipper_angle 一致）
    local aL_rest = math.atan2(14, 66)
    local aL_hit = math.atan2(-36, 80)
    local aR_rest = math.atan2(14, -66)
    local aR_hit = math.atan2(-36, -80)

    -- 枢轴略靠向台心，避免与左右边框/墙线重叠（原 88/392 → 内移）
    local flippers = {
        {
            ox = 118,
            oy = 542,
            L = 92,
            ang = aL_rest,
            a_rest = aL_rest,
            a_hit = aL_hit,
            restitution = 1.02,
        },
        {
            ox = 362,
            oy = 542,
            L = 92,
            ang = aR_rest,
            a_rest = aR_rest,
            a_hit = aR_hit,
            restitution = 1.02,
        },
    }

    return {
        ball = { x = 240, y = 96, vx = 0, vy = 0, r = BALL_R },
        gravity = 680,
        segments = segments,
        bumpers = bumpers,
        flippers = flippers,
        bumper_cd = {},
    }
end

local function refresh_hud()
    if score_label then
        score_label:set_text("得分 " .. tostring(score))
    end
    if lives_label then
        lives_label:set_text("球 " .. tostring(lives))
    end
end

local function play_bumper_sound()
    if not audio or not audio.start or not audio.write then
        return
    end
    local SR = 22050
    local n = math.floor(SR * 0.06)
    local parts = {}
    for i = 0, n - 1 do
        local t = i / SR
        local env = 1 - i / math.max(1, n)
        env = env * env
        local s = math.sin(2 * math.pi * 520 * t) * 0.55 + math.sin(2 * math.pi * 1800 * t) * 0.2
        local v = math.floor(7000 * env * s)
        if v > 32767 then
            v = 32767
        elseif v < -32768 then
            v = -32768
        end
        parts[#parts + 1] = string.pack("<i2", v)
    end
    local pcm = table.concat(parts)
    pcall(function()
        audio.stop(0)
    end)
    pcall(function()
        if audio.start(0, audio.PCM, 1, SR, 16, true) then
            audio.write(0, pcm)
            if audio.finish then
                audio.finish(0)
            end
        end
    end)
end

local function drain_ball()
    lives = lives - 1
    refresh_hud()
    if lives <= 0 then
        if score > best_score then
            best_score = score
        end
        if hint_label then
            hint_label:set_text("游戏结束 最佳 " .. tostring(best_score) .. " · 点重开")
        end
        waiting_launch = true
        world.ball.vx = 0
        world.ball.vy = 0
        return
    end
    waiting_launch = true
    world.ball.vx = 0
    world.ball.vy = 0
    if hint_label then
        hint_label:set_text("点发射继续")
    end
end

local function launch_ball()
    if not world then
        return
    end
    waiting_launch = false
    world.ball.x = 248
    world.ball.y = 96
    world.ball.vx = (math.random(-260, 260)) / 10
    world.ball.vy = 440 + math.random(0, 90)
    if hint_label then
        hint_label:set_text("左/右挡板")
    end
end

local function sync_flipper_gfx()
    if not world or not flip_L_gfx[1] then
        return
    end
    local function lay(parts, ox, oy, ex, ey)
        local dx = ex - ox
        local dy = ey - oy
        local n = #parts
        for i = 1, n do
            local t = (i - 0.5) / n
            -- 统一向下取整，避免相邻帧 ±1 像素抖动
            local px = math.floor(ox + dx * t + 0.5) - 5
            local py = math.floor(oy + dy * t + 0.5) - 5
            parts[i]:set_pos(px, py)
        end
    end
    local f1 = world.flippers[1]
    local f2 = world.flippers[2]
    local ax1, ay1, ax2, ay2 = phys.flipper_segment(f1)
    local bx1, by1, bx2, by2 = phys.flipper_segment(f2)
    lay(flip_L_gfx, ax1, ay1, ax2, ay2)
    lay(flip_R_gfx, bx1, by1, bx2, by2)
end

local function reset_game()
    score = 0
    lives = 3
    waiting_launch = true
    world = build_world()
    refresh_hud()
    if hint_label then
        hint_label:set_text("点发射开球")
    end
    if world and ball_gfx then
        ball_gfx:set_pos(math.floor(world.ball.x - BALL_R), math.floor(world.ball.y - BALL_R))
    end
end

local function tick_frame(dt_ms)
    if destroyed or not world then
        return
    end

    local dt = dt_ms / 1000
    -- 先取本帧挡板输入（再扣按钮脉冲时间）
    local left_on = (left_ms > 0) or left_hold
    local right_on = (right_ms > 0) or right_hold
    if left_ms > 0 then
        left_ms = left_ms - dt_ms
        if left_ms < 0 then
            left_ms = 0
        end
    end
    if right_ms > 0 then
        right_ms = right_ms - dt_ms
        if right_ms < 0 then
            right_ms = 0
        end
    end

    phys.update_flipper_angle(world.flippers[1], dt, left_on)
    phys.update_flipper_angle(world.flippers[2], dt, right_on)

    local sdt = dt / SUBSTEPS
    local add = 0

    if waiting_launch then
        world.ball.x = 248
        world.ball.y = 96
        world.ball.vx = 0
        world.ball.vy = 0
    else
        for _ = 1, SUBSTEPS do
            add = add + phys.substep(world, sdt, left_on, right_on)
        end
        for i = 1, #world.bumpers do
            if world.bumper_cd[i] and world.bumper_cd[i] > 0 then
                world.bumper_cd[i] = world.bumper_cd[i] - 1
            end
        end
        if add > 0 then
            score = score + add
            refresh_hud()
            play_bumper_sound()
        end

        local b = world.ball
        if b.y > PLAY_BOT - 8 and b.x > 170 and b.x < 310 then
            drain_ball()
        end
        if b.y > GAME_H + 20 or b.x < -40 or b.x > SCREEN_W + 40 then
            drain_ball()
        end
    end

    if ball_gfx and world then
        local bx = world.ball.x
        local by = world.ball.y
        ball_gfx:set_pos(math.floor(bx - BALL_R + 0.5), math.floor(by - BALL_R + 0.5))
    end
    sync_flipper_gfx()
end

local function on_tick()
    tick_frame(TICK_MS)
end

local function on_exit()
    if win_id then
        exwin.close(win_id)
    end
end

local function create_ui()
    score = 0
    lives = 3
    waiting_launch = true

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x0a1628,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 6,
        w = SCREEN_W,
        h = 36,
        text = "弹球 Pinball",
        font_size = 22,
        color = 0xE8F4FC,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.button({
        parent = main_container,
        x = 364,
        y = 6,
        w = 108,
        h = 34,
        text = "退出",
        font_size = 18,
        text_color = 0xF1F5F9,
        bg_color = 0x374151,
        on_click = on_exit,
    })

    game_area = airui.container({
        parent = main_container,
        x = 0,
        y = GAME_Y,
        w = SCREEN_W,
        h = GAME_H,
        color = 0x0d3b2c,
    })

    -- 外框亮边
    airui.container({
        parent = game_area,
        x = 4,
        y = 4,
        w = SCREEN_W - 8,
        h = GAME_H - 8,
        color = 0x0a2f24,
        radius = 6,
    })

    local wall_c = 0x1a6b4a
    stroke_segment(game_area, PLAY_L, PLAY_TOP, PLAY_R, PLAY_TOP, wall_c)
    stroke_segment(game_area, PLAY_L, PLAY_TOP, PLAY_L, PLAY_BOT - 72, wall_c)
    stroke_segment(game_area, PLAY_R, PLAY_TOP, PLAY_R, PLAY_BOT - 72, wall_c)
    stroke_segment(game_area, PLAY_L, PLAY_BOT - 72, 168, PLAY_BOT, wall_c)
    stroke_segment(game_area, PLAY_R, PLAY_BOT - 72, 312, PLAY_BOT, wall_c)
    stroke_segment(game_area, PLAY_L, PLAY_TOP + 120, 108, PLAY_TOP + 210, wall_c)
    stroke_segment(game_area, PLAY_R, PLAY_TOP + 120, 372, PLAY_TOP + 210, wall_c)

    world = build_world()
    for i = 1, #world.bumpers do
        local b = world.bumpers[i]
        local d = b.r * 2
        bumper_gfx[i] = airui.container({
            parent = game_area,
            x = math.floor(b.cx - b.r),
            y = math.floor(b.cy - b.r),
            w = d,
            h = d,
            color = 0xF4D03F,
            radius = b.r,
        })
    end

    ball_gfx = airui.container({
        parent = game_area,
        x = 240 - BALL_R,
        y = 96 - BALL_R,
        w = BALL_R * 2,
        h = BALL_R * 2,
        color = 0xF8F9FA,
        radius = BALL_R,
    })

    score_label = airui.label({
        parent = main_container,
        x = 12,
        y = GAME_Y + GAME_H + 4,
        w = 200,
        h = 26,
        text = "得分 0",
        font_size = 20,
        color = 0xE2E8F0,
        align = airui.TEXT_ALIGN_LEFT,
    })

    lives_label = airui.label({
        parent = main_container,
        x = 200,
        y = GAME_Y + GAME_H + 4,
        w = 120,
        h = 26,
        text = "球 3",
        font_size = 20,
        color = 0xE2E8F0,
        align = airui.TEXT_ALIGN_LEFT,
    })

    hint_label = airui.label({
        parent = main_container,
        x = 12,
        y = GAME_Y + GAME_H + 28,
        w = 456,
        h = 22,
        text = "点发射开球",
        font_size = 15,
        color = 0x94A3B8,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local ctrl = airui.container({
        parent = main_container,
        x = 0,
        y = 718,
        w = SCREEN_W,
        h = 82,
        color = 0x0b1220,
    })

    local function press_left()
        left_ms = FLIPPER_HOLD_MS
    end
    local function press_right()
        right_ms = FLIPPER_HOLD_MS
    end

    local FLIP_DOT = 12
    for i = 1, FLIP_DOT do
        flip_L_gfx[i] = airui.container({
            parent = game_area,
            x = 0,
            y = 0,
            w = 10,
            h = 10,
            color = 0xE8956C,
            radius = 4,
        })
        flip_R_gfx[i] = airui.container({
            parent = game_area,
            x = 0,
            y = 0,
            w = 10,
            h = 10,
            color = 0xE8956C,
            radius = 4,
        })
    end
    sync_flipper_gfx()

    airui.button({
        parent = ctrl,
        x = 6,
        y = 10,
        w = 108,
        h = 54,
        text = "左挡",
        font_size = 20,
        text_color = 0xF1F5F9,
        bg_color = 0x1E3A8A,
        on_click = press_left,
    })

    airui.button({
        parent = ctrl,
        x = 124,
        y = 10,
        w = 108,
        h = 54,
        text = "右挡",
        font_size = 20,
        text_color = 0xF1F5F9,
        bg_color = 0x1E3A8A,
        on_click = press_right,
    })

    airui.button({
        parent = ctrl,
        x = 242,
        y = 10,
        w = 116,
        h = 54,
        text = "发射",
        font_size = 20,
        text_color = 0x0f172a,
        bg_color = 0xFBBF24,
        on_click = function()
            if waiting_launch and world and lives > 0 then
                launch_ball()
            end
        end,
    })

    airui.button({
        parent = ctrl,
        x = 368,
        y = 10,
        w = 104,
        h = 54,
        text = "重开",
        font_size = 20,
        text_color = 0xF1F5F9,
        bg_color = 0x7C2D12,
        on_click = function()
            reset_game()
        end,
    })

    -- 底部控制条：按下时锁定左/右 lane，HOLD 期间不再用 x 重算（避免右挡区抖动闪烁）
    if airui.touch_subscribe and airui.TP_DOWN and airui.TP_UP then
        airui.touch_subscribe(function(state, x, y, _track)
            if destroyed or not x or not y then
                return
            end
            if state == airui.TP_UP then
                flip_touch_lock = nil
                left_hold = false
                right_hold = false
                return
            end
            if y < 718 or y > 800 then
                return
            end
            local is_hold = airui.TP_HOLD and state == airui.TP_HOLD
            if state == airui.TP_DOWN then
                if x >= 4 and x < 122 then
                    flip_touch_lock = "l"
                elseif x >= 124 and x < 242 then
                    flip_touch_lock = "r"
                else
                    flip_touch_lock = nil
                end
            end
            if state == airui.TP_DOWN or is_hold then
                if flip_touch_lock == "l" then
                    left_hold = true
                    right_hold = false
                elseif flip_touch_lock == "r" then
                    left_hold = false
                    right_hold = true
                else
                    left_hold = false
                    right_hold = false
                end
            end
        end)
    end

    destroyed = false
    if game_timer then
        sys.timerStop(game_timer)
    end
    game_timer = sys.timerLoopStart(on_tick, TICK_MS)
end

local function on_create()
    create_ui()
end

local function on_destroy()
    destroyed = true
    left_hold = false
    right_hold = false
    flip_touch_lock = nil
    if game_timer then
        sys.timerStop(game_timer)
        game_timer = nil
    end
    bumper_gfx = {}
    flip_L_gfx = {}
    flip_R_gfx = {}
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    game_area = nil
    ball_gfx = nil
    score_label = nil
    lives_label = nil
    hint_label = nil
    world = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    if win_id then
        return
    end
    if not ensure_airui() then
        log.error("pinball_win", "airui init failed")
        return
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_PINBALL_WIN", open_handler)

function pinball_open()
    open_handler()
end
