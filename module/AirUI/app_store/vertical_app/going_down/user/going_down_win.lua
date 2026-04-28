--[[
@module  going_down_win
@summary 男人就下一百层（横版）
@version 1.0
]]

-- exapp 沙箱里包装后的 exwin 在 _ENV 上；rawget(_G,"exwin") 易误用裸 exwin，退出后无法 exapp.close
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

local win_id = nil
local main_container = nil
local game_area = nil

local status_label = nil
local score_label = nil
local best_label = nil
local game_over_label = nil

local btn_left = nil
local btn_right = nil
local btn_down = nil
local btn_exit = nil

local SCREEN_W = 480
local SCREEN_H = 800
local GAME_H = 700
local SPIKE_H = 28
local MIN_ROW_GAP = 72

local PLAYER_W = 26
local PLAYER_H = 42

local BASE_SCROLL = 0.9
local MAX_SCROLL = 4.2
local SCROLL_ACC = 0.0009
local GRAVITY = 0.55
local MAX_FALL_SPEED = 11
local MOVE_STEP = 4
local DOWN_STEP = 30
local REPEAT_MOVE_TICKS = 99999
local REPEAT_INTERVAL = 1

local player = {
    x = 0,
    y = 0,
    vy = 0,
    on_ground = false,
    obj = nil,
}

local floors = {}
local game_timer = nil
local game_over = false

local score_tick = 0
local score = 0
local best_score = 0
local elapsed_tick = 0
local fall_distance = 0
local prev_player_y = 0

local floor_layer = nil
local spike_layer = nil
local repeat_dir = 0
local repeat_ticks = 0
local repeat_wait = 0

local function ensure_airui()
    if not airui or not airui.init then
        return false
    end
    -- app 列表(exapp)模式由外层初始化，避免重复 init
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

local function apply_screen_size() end

local function set_status(text, color)
    if status_label then
        status_label:set_text(text or "")
        if color then
            status_label:set_color(color)
        end
    end
end

local function refresh_score()
    if score_label then
        score_label:set_text("层数: " .. tostring(score))
    end
    if best_label then
        best_label:set_text("最佳: " .. tostring(best_score))
    end
end

local function clear_floors()
    for i = #floors, 1, -1 do
        if floors[i].obj then
            floors[i].obj:destroy()
        end
        table.remove(floors, i)
    end
end

local function spawn_floor_segment(x, y, w)
    if w < 40 then
        return
    end
    local seg = {
        x = x,
        y = y,
        w = w,
        h = 16,
        obj = airui.container({
            parent = floor_layer,
            x = x,
            y = y,
            w = w,
            h = 16,
            color = 0xD9E3F0,
            radius = 3,
        }),
    }
    floors[#floors + 1] = seg
end

local function spawn_floor_row(y)
    -- 一行内随机多个缺口（1~3个），其余部分生成条状地面
    local target_gaps = math.random(1, 3)
    local cursor = 0
    local made_gaps = 0

    while cursor < SCREEN_W do
        local remain = SCREEN_W - cursor
        if remain <= 0 then
            break
        end

        -- 地面段
        local floor_w = math.random(80, 170)
        if floor_w > remain then
            floor_w = remain
        end
        if floor_w > 0 then
            spawn_floor_segment(cursor, y, floor_w)
            cursor = cursor + floor_w
        end

        remain = SCREEN_W - cursor
        if remain <= 0 then
            break
        end

        -- 缺口段（最多 target_gaps 个）
        if made_gaps < target_gaps then
            local gap_w = math.random(40, 140)
            if gap_w > remain then
                gap_w = remain
            end
            cursor = cursor + gap_w
            made_gaps = made_gaps + 1
        else
            -- 缺口数量达到目标后，剩余部分补地面并结束
            spawn_floor_segment(cursor, y, remain)
            break
        end
    end
end

local function ensure_bottom_rows()
    local max_y = -9999
    for i = 1, #floors do
        if floors[i].y > max_y then
            max_y = floors[i].y
        end
    end
    if #floors == 0 then
        max_y = GAME_H - 140
    end

    -- 地面只允许出现在 game_area 内，避免子元素越界触发滚动条
    local max_floor_y = GAME_H - 16
    -- 底部预留最小行距，避免每帧补一行导致在底部重叠
    while max_y < (max_floor_y - MIN_ROW_GAP) do
        max_y = max_y + math.random(MIN_ROW_GAP, 106)
        spawn_floor_row(max_y)
    end
end

local function reset_player()
    player.x = math.floor((SCREEN_W - PLAYER_W) / 2)
    player.y = 72
    player.vy = 0
    player.on_ground = false
    if player.obj then
        player.obj:set_pos(player.x, player.y)
    end
end

local function reset_game()
    game_over = false
    score = 0
    score_tick = 0
    elapsed_tick = 0
    fall_distance = 0
    clear_floors()

    -- 初始随机平台
    spawn_floor_row(GAME_H - 260)
    spawn_floor_row(GAME_H - 180)
    spawn_floor_row(GAME_H - 120)
    ensure_bottom_rows()

    reset_player()
    if game_over_label then
        game_over_label:set_text("")
    end
    prev_player_y = player.y
    refresh_score()
    set_status("上方是尖刺，保持下落！", 0xCDEAC0)
end

local function kill_player(reason)
    if game_over then
        return
    end
    game_over = true
    if score > best_score then
        best_score = score
    end
    refresh_score()
    if game_over_label then
        game_over_label:set_text("完啦")
        game_over_label:set_color(0xFFECEC)
    end
    set_status("完啦！" .. reason .. "（点重开）", 0xFF8A80)
end

local function collides_floor(nx, ny, scroll_speed)
    -- 只处理“从上往下落在平台上”
    if player.vy < 0 then
        return false, nil
    end

    scroll_speed = scroll_speed or 0
    local foot_prev = player.y + PLAYER_H
    local foot_now = ny + PLAYER_H
    local body_l = nx + 3
    local body_r = nx + PLAYER_W - 3

    for i = 1, #floors do
        local f = floors[i]
        local top_now = f.y
        local top_prev = f.y + scroll_speed
        if foot_prev <= top_prev and foot_now >= top_now then
            local overlap = not (body_r < f.x or body_l > (f.x + f.w))
            if overlap then
                return true, top_now - PLAYER_H
            end
        end

        -- 兜底：已经非常接近平台顶部时也吸附，避免高速时漏判
        if foot_now >= top_now - 3 and foot_now <= top_now + 8 then
            local overlap2 = not (body_r < f.x or body_l > (f.x + f.w))
            if overlap2 then
                return true, top_now - PLAYER_H
            end
        end
    end

    return false, nil
end

local function move_world_up(scroll_speed)
    if scroll_speed <= 0 then
        return
    end
    for i = #floors, 1, -1 do
        local f = floors[i]
        f.y = f.y - scroll_speed
        if f.obj then
            f.obj:set_pos(f.x, math.floor(f.y))
        end
        -- 出界后删除，后续由 ensure_bottom_rows 统一补行，避免重叠
        if f.y + f.h < 0 then
            if f.obj then
                f.obj:destroy()
            end
            table.remove(floors, i)
        end
    end
    ensure_bottom_rows()
end

local function update_player(scroll_speed)
    if game_over then
        return
    end

    player.vy = player.vy + GRAVITY
    if player.vy > MAX_FALL_SPEED then
        player.vy = MAX_FALL_SPEED
    end

    local ny = player.y + player.vy
    local landed, floor_y = collides_floor(player.x, ny, scroll_speed)
    if landed then
        player.y = floor_y
        player.vy = 0
        player.on_ground = true
    else
        player.y = ny
        player.on_ground = false
    end

    if player.y < SPIKE_H then
        kill_player("碰到尖刺")
    elseif player.y > GAME_H then
        kill_player("坠落失败")
    end

    if player.obj then
        player.obj:set_pos(math.floor(player.x), math.floor(player.y))
    end
end

local function move_left()
    if game_over then
        return
    end
    player.x = player.x - MOVE_STEP
    if player.x < 0 then
        player.x = 0
    end
end

local function move_right()
    if game_over then
        return
    end
    player.x = player.x + MOVE_STEP
    if player.x + PLAYER_W > SCREEN_W then
        player.x = SCREEN_W - PLAYER_W
    end
end

local function press_left()
    move_left()
    repeat_dir = -1
    repeat_ticks = REPEAT_MOVE_TICKS
    repeat_wait = 0
end

local function press_right()
    move_right()
    repeat_dir = 1
    repeat_ticks = REPEAT_MOVE_TICKS
    repeat_wait = 0
end

local function restart_game()
    repeat_dir = 0
    repeat_ticks = 0
    repeat_wait = 0
    reset_game()
end

local function on_exit()
    if win_id then
        exwin.close(win_id)
    end
end

local function on_tick()
    if game_over then
        return
    end
    elapsed_tick = elapsed_tick + 1
    local scroll_speed = BASE_SCROLL + elapsed_tick * SCROLL_ACC
    if scroll_speed > MAX_SCROLL then
        scroll_speed = MAX_SCROLL
    end
    move_world_up(scroll_speed)

    if not game_over and repeat_ticks > 0 then
        if repeat_wait > 0 then
            repeat_wait = repeat_wait - 1
        else
            if repeat_dir < 0 then
                move_left()
            elseif repeat_dir > 0 then
                move_right()
            end
            repeat_wait = REPEAT_INTERVAL
            repeat_ticks = repeat_ticks - 1
        end
    end

    update_player(scroll_speed)

    -- 层数按人物真实下落距离统计（仅累计向下位移）
    local dy = player.y - prev_player_y
    if dy > 0 then
        fall_distance = fall_distance + dy
    end
    prev_player_y = player.y

    local new_score = math.floor(fall_distance / 80)
    if new_score ~= score then
        score = new_score
        refresh_score()
    end
end

local function create_ui()
    apply_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x101820,
    })

    game_area = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = GAME_H,
        color = 0x111827,
    })

    floor_layer = airui.container({
        parent = game_area,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = GAME_H,
        color = 0x111827,
        opacity = 0,
    })

    player.obj = airui.container({
        parent = game_area,
        x = 220,
        y = 72,
        w = PLAYER_W,
        h = PLAYER_H,
        color = 0xFFD166,
        radius = 0,
    })

    -- 尖刺层放在最后创建，确保层级最高可见
    spike_layer = airui.container({
        parent = game_area,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SPIKE_H,
        color = 0x111827,
        opacity = 0,
    })

    local tooth_w = 18
    local tooth_h = SPIKE_H - 2
    local count = math.floor((SCREEN_W + tooth_w - 1) / tooth_w)
    for i = 0, count - 1 do
        local x = i * tooth_w
        -- 仅红色尖刺（无白色方块）
        airui.container({
            parent = spike_layer,
            x = x,
            y = 0,
            w = tooth_w - 2,
            h = tooth_h - 10,
            color = 0xC1121F,
            radius = 0,
        })
        airui.container({
            parent = spike_layer,
            x = x + 3,
            y = 3,
            w = tooth_w - 8,
            h = tooth_h - 8,
            color = 0xD7263D,
            radius = 0,
        })
        airui.container({
            parent = spike_layer,
            x = x + 6,
            y = 8,
            w = tooth_w - 14,
            h = tooth_h - 10,
            color = 0xF94144,
            radius = 0,
        })
    end

    score_label = airui.label({
        parent = main_container,
        x = 12,
        y = 704,
        w = 180,
        h = 24,
        text = "层数: 0",
        font_size = 18,
        color = 0xE2E8F0,
        align = airui.TEXT_ALIGN_LEFT,
    })

    best_label = airui.label({
        parent = main_container,
        x = 180,
        y = 704,
        w = 120,
        h = 24,
        text = "最佳: 0",
        font_size = 18,
        color = 0xE2E8F0,
        align = airui.TEXT_ALIGN_LEFT,
    })

    status_label = airui.label({
        parent = main_container,
        x = 300,
        y = 704,
        w = 168,
        h = 24,
        text = "",
        font_size = 14,
        color = 0xCDEAC0,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    game_over_label = airui.label({
        parent = game_area,
        x = 0,
        y = math.floor((GAME_H - 96) / 2),
        w = SCREEN_W,
        h = 96,
        text = "",
        font_size = 72,
        color = 0xFFECEC,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local ctrl = airui.container({
        parent = main_container,
        x = 0,
        y = 728,
        w = SCREEN_W,
        h = 72,
        color = 0x0B1220,
    })

    btn_left = airui.button({
        parent = ctrl,
        x = 8,
        y = 8,
        w = 108,
        h = 56,
        text = "左",
        font_size = 22,
        text_color = 0xF1F5F9,
        bg_color = 0x1E3A8A,
        on_click = press_left,
    })

    btn_down = airui.button({
        parent = ctrl,
        x = 248,
        y = 8,
        w = 108,
        h = 56,
        text = "重开",
        font_size = 22,
        text_color = 0xF1F5F9,
        bg_color = 0x7C2D12,
        on_click = restart_game,
    })

    btn_right = airui.button({
        parent = ctrl,
        x = 128,
        y = 8,
        w = 108,
        h = 56,
        text = "右",
        font_size = 22,
        text_color = 0xF1F5F9,
        bg_color = 0x1E3A8A,
        on_click = press_right,
    })

    btn_exit = airui.button({
        parent = ctrl,
        x = 368,
        y = 8,
        w = 104,
        h = 56,
        text = "退出",
        font_size = 22,
        text_color = 0xF1F5F9,
        bg_color = 0x374151,
        on_click = on_exit,
    })

    reset_game()

    if game_timer then
        sys.timerStop(game_timer)
    end
    game_timer = sys.timerLoopStart(on_tick, 33)
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if game_timer then
        sys.timerStop(game_timer)
        game_timer = nil
    end
    clear_floors()

    if main_container then
        main_container:destroy()
        main_container = nil
    end

    win_id = nil
    game_area = nil
    score_label = nil
    best_label = nil
    status_label = nil
    game_over_label = nil
    floor_layer = nil
    spike_layer = nil
    btn_left = nil
    btn_right = nil
    btn_down = nil
    btn_exit = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    if win_id then
        return
    end
    if not ensure_airui() then
        log.error("going_down_win", "airui init failed")
        return
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_GOING_DOWN_WIN", open_handler)

function going_down_open()
    open_handler()
end
