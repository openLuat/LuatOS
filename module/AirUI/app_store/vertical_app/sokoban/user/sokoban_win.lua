--[[
@module  sokoban_win
@summary AirUI 推箱子（关卡递进、地图增长、可解关卡）
]]

local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

local packs_mod = require "sokoban_level_sets"
local level_sets = (packs_mod and packs_mod.sets) or {}

local win_id = nil
local main_container = nil
local board_layer = nil

local SCREEN_W = 480
local SCREEN_H = 800

local BOARD_X = 10
local BOARD_Y = 118
local BOARD_W = 460
local BOARD_H = 500

local status_label = nil
local info_label = nil
local hint_label = nil
local title_label = nil
local hud_left = nil
local destroyed = false
local active_set_idx = 1
local levels = {}
local max_level = 0
local is_advancing = false
local load_level = nil
local player_obj = nil
local box_objs = {}

if #level_sets > 0 then
    local init_pack = level_sets[1]
    levels = (init_pack and init_pack.levels) or {}
    max_level = #levels
end

local cur = {
    level = 1,
    map = nil,
    player = { x = 1, y = 1 },
    moves = 0,
    pushes = 0,
    cell = 32,
    ox = 0,
    oy = 0,
    walls = {},
    goals = {},
    boxes = {},
    history = {},
}

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

local function box_key(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function is_box(x, y)
    return cur.boxes[box_key(x, y)] == true
end

local function set_box(x, y, v)
    cur.boxes[box_key(x, y)] = v and true or nil
end

local function in_map(x, y)
    local m = cur.map
    return m and x >= 1 and x <= m.w and y >= 1 and y <= m.h
end

local function is_wall(x, y)
    if not in_map(x, y) then
        return true
    end
    return cur.walls[y] and cur.walls[y][x] or false
end

local function is_goal(x, y)
    if not in_map(x, y) then
        return false
    end
    return cur.goals[y] and cur.goals[y][x] or false
end

local function refresh_hud()
    if title_label then
        title_label:set_text("当前关 " .. tostring(cur.level) .. "/" .. tostring(max_level))
    end
    if status_label then
        status_label:set_text("步数 " .. tostring(cur.moves) .. "  推箱 " .. tostring(cur.pushes))
    end
    if info_label and cur.map then
        info_label:set_text("地图 " .. tostring(cur.map.w) .. "x" .. tostring(cur.map.h) ..
            "  目标 " .. tostring(cur.map.target_pushes))
    end
end

local function switch_level_set(next_idx)
    if #level_sets == 0 then
        return
    end
    if next_idx < 1 then
        next_idx = #level_sets
    elseif next_idx > #level_sets then
        next_idx = 1
    end
    active_set_idx = next_idx
    local pack = level_sets[active_set_idx]
    levels = (pack and pack.levels) or {}
    max_level = #levels
    cur.level = 1
    if max_level > 0 then
        load_level(1)
    elseif hint_label then
        hint_label:set_text("当前地图集为空")
        refresh_hud()
    end
end

local function sanitize_level(data)
    if not data then
        return nil
    end
    local cleaned = {
        level = data.level,
        w = data.w,
        h = data.h,
        walls = {},
        goals = {},
        boxes = {},
        player = { x = data.player.x, y = data.player.y },
        target_pushes = data.target_pushes or 0,
    }
    for y = 1, data.h do
        cleaned.walls[y] = {}
        cleaned.goals[y] = {}
        cleaned.boxes[y] = {}
        for x = 1, data.w do
            local wall = data.walls[y][x] and true or false
            local goal = data.goals[y][x] and true or false
            local box = data.boxes[y][x] and true or false
            if wall and (goal or box) then
                wall = false
            end
            cleaned.walls[y][x] = wall
            cleaned.goals[y][x] = goal and not wall
            cleaned.boxes[y][x] = box and not wall
        end
    end
    local px = math.max(1, math.min(data.w, cleaned.player.x))
    local py = math.max(1, math.min(data.h, cleaned.player.y))
    if cleaned.walls[py][px] or cleaned.boxes[py][px] then
        for y = 1, data.h do
            for x = 1, data.w do
                if not cleaned.walls[y][x] and not cleaned.boxes[y][x] then
                    px, py = x, y
                    break
                end
            end
        end
    end
    cleaned.player.x = px
    cleaned.player.y = py
    return cleaned
end

local function draw_wall(parent, x, y, cell)
    airui.container({
        parent = parent,
        x = x,
        y = y,
        w = cell - 2,
        h = cell - 2,
        color = 0x334155,
        radius = 6,
    })
    airui.container({
        parent = parent,
        x = x + 2,
        y = y + 2,
        w = cell - 8,
        h = cell - 8,
        color = 0x475569,
        radius = 5,
    })
end

local function draw_goal(parent, x, y, cell)
    local d = math.max(8, math.floor(cell * 0.5))
    local gx = x + math.floor((cell - d) / 2)
    local gy = y + math.floor((cell - d) / 2)
    airui.container({
        parent = parent,
        x = gx,
        y = gy,
        w = d,
        h = d,
        color = 0xF59E0B,
        radius = math.floor(d / 2),
    })
    airui.container({
        parent = parent,
        x = gx + 3,
        y = gy + 3,
        w = d - 6,
        h = d - 6,
        color = 0xFCD34D,
        radius = math.floor((d - 6) / 2),
    })
end

local function draw_box(parent, x, y, cell, on_goal)
    local margin = math.max(3, math.floor(cell * 0.14))
    local bx = x + margin
    local by = y + margin
    local bw = cell - margin * 2 - 2
    local bh = bw
    airui.container({
        parent = parent,
        x = bx,
        y = by,
        w = bw,
        h = bh,
        color = on_goal and 0x16A34A or 0xB45309,
        radius = 5,
    })
    airui.container({
        parent = parent,
        x = bx + 3,
        y = by + 3,
        w = bw - 6,
        h = bh - 6,
        color = on_goal and 0x22C55E or 0xD97706,
        radius = 4,
    })
end

local function draw_player(parent, x, y, cell)
    local d = math.max(12, math.floor(cell * 0.62))
    local px = x + math.floor((cell - d) / 2)
    local py = y + math.floor((cell - d) / 2)
    airui.container({
        parent = parent,
        x = px,
        y = py,
        w = d,
        h = d,
        color = 0x2563EB,
        radius = math.floor(d / 2),
    })
    airui.container({
        parent = parent,
        x = px + math.floor(d * 0.22),
        y = py + math.floor(d * 0.2),
        w = math.max(4, math.floor(d * 0.22)),
        h = math.max(4, math.floor(d * 0.22)),
        color = 0xBFDBFE,
        radius = math.max(2, math.floor(d * 0.11)),
    })
end

local function clear_dynamic_objs()
    for i = 1, #box_objs do
        if box_objs[i] then
            box_objs[i]:destroy()
        end
    end
    box_objs = {}
    if player_obj then
        player_obj:destroy()
        player_obj = nil
    end
end

local function rebuild_dynamic()
    if not board_layer or not cur.map then
        return
    end
    clear_dynamic_objs()
    local m = cur.map
    for y = 1, m.h do
        for x = 1, m.w do
            if is_box(x, y) then
                local px = cur.ox + (x - 1) * cur.cell + 1
                local py = cur.oy + (y - 1) * cur.cell + 1
                local on_goal = is_goal(x, y)
                local margin = math.max(3, math.floor(cur.cell * 0.14))
                local bx = px + margin
                local by = py + margin
                local bw = cur.cell - margin * 2 - 2
                local obj = airui.container({
                    parent = board_layer,
                    x = bx,
                    y = by,
                    w = bw,
                    h = bw,
                    color = on_goal and 0x22C55E or 0xD97706,
                    radius = 5,
                })
                box_objs[#box_objs + 1] = obj
            end
        end
    end
    local ppx = cur.ox + (cur.player.x - 1) * cur.cell + 1
    local ppy = cur.oy + (cur.player.y - 1) * cur.cell + 1
    local d = math.max(12, math.floor(cur.cell * 0.62))
    local px = ppx + math.floor((cur.cell - d) / 2)
    local py = ppy + math.floor((cur.cell - d) / 2)
    player_obj = airui.container({
        parent = board_layer,
        x = px,
        y = py,
        w = d,
        h = d,
        color = 0x2563EB,
        radius = math.floor(d / 2),
    })
end

local function rebuild_board()
    if not cur.map then
        return
    end
    clear_dynamic_objs()
    if board_layer then
        board_layer:destroy()
        board_layer = nil
    end
    board_layer = airui.container({
        parent = main_container,
        x = BOARD_X,
        y = BOARD_Y,
        w = BOARD_W,
        h = BOARD_H,
        color = 0xCBD5E1,
        radius = 12,
    })
    local m = cur.map
    local cell = math.floor(math.min((BOARD_W - 20) / m.w, (BOARD_H - 20) / m.h))
    cur.cell = cell
    cur.ox = math.floor((BOARD_W - cell * m.w) / 2)
    cur.oy = math.floor((BOARD_H - cell * m.h) / 2)

    for y = 1, m.h do
        for x = 1, m.w do
            local px = cur.ox + (x - 1) * cell + 1
            local py = cur.oy + (y - 1) * cell + 1
            if is_wall(x, y) then
                draw_wall(board_layer, px, py, cell)
            else
                if is_goal(x, y) then
                    draw_goal(board_layer, px, py, cell)
                end
                if is_box(x, y) then
                    draw_box(board_layer, px, py, cell, is_goal(x, y))
                end
            end
        end
    end

    rebuild_dynamic()
end

local function save_history()
    local snap = {
        px = cur.player.x,
        py = cur.player.y,
        moves = cur.moves,
        pushes = cur.pushes,
        boxes = {},
    }
    for k, v in pairs(cur.boxes) do
        if v then
            snap.boxes[k] = true
        end
    end
    cur.history[#cur.history + 1] = snap
end

local function restore_history()
    local snap = cur.history[#cur.history]
    if not snap then
        return
    end
    cur.history[#cur.history] = nil
    cur.player.x = snap.px
    cur.player.y = snap.py
    cur.moves = snap.moves
    cur.pushes = snap.pushes
    cur.boxes = snap.boxes
    refresh_hud()
    rebuild_dynamic()
end

local function solved()
    if not cur.map then
        return false
    end
    for y = 1, cur.map.h do
        for x = 1, cur.map.w do
            if is_goal(x, y) and not is_box(x, y) then
                return false
            end
        end
    end
    return true
end

load_level = function(level)
    if level > max_level then
        if hint_label then
            hint_label:set_text("已完成全部预置关卡，可扩展关卡库后继续")
        end
        return false
    end
    local data = sanitize_level(levels[level])
    if not data then
        if hint_label then
            hint_label:set_text("关卡加载失败，请重试")
        end
        return false
    end
    cur.level = level
    is_advancing = false
    cur.map = data
    cur.player = { x = data.player.x, y = data.player.y }
    cur.moves = 0
    cur.pushes = 0
    cur.history = {}
    cur.walls = data.walls
    cur.goals = data.goals
    cur.boxes = {}
    for y = 1, data.h do
        for x = 1, data.w do
            if data.boxes[y][x] then
                set_box(x, y, true)
            end
        end
    end
    if hint_label then
        hint_label:set_text("把所有箱子推到金色目标点")
    end
    refresh_hud()
    rebuild_board()
    return true
end

local function try_move(dx, dy)
    if destroyed or not cur.map or is_advancing then
        return
    end
    local nx = cur.player.x + dx
    local ny = cur.player.y + dy
    if is_wall(nx, ny) then
        return
    end

    if is_box(nx, ny) then
        local bx = nx + dx
        local by = ny + dy
        if is_wall(bx, by) or is_box(bx, by) then
            return
        end
        save_history()
        set_box(nx, ny, false)
        set_box(bx, by, true)
        cur.player.x = nx
        cur.player.y = ny
        cur.moves = cur.moves + 1
        cur.pushes = cur.pushes + 1
    else
        save_history()
        cur.player.x = nx
        cur.player.y = ny
        cur.moves = cur.moves + 1
    end

    refresh_hud()
    rebuild_board()
    if solved() then
        is_advancing = true
        if hint_label then
            hint_label:set_text("过关！进入下一关...")
        end
        local next_level = cur.level + 1
        sys.timerStart(function()
            if not destroyed then
                if not load_level(next_level) then
                    is_advancing = false
                end
            end
        end, 450)
    end
end

local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x020617,
    })

    title_label = airui.label({
        parent = main_container,
        x = 12,
        y = 14,
        w = 260,
        text = "",
        font_size = 19,
        color = 0xE2E8F0,
    })
    status_label = airui.label({
        parent = main_container,
        x = 12,
        y = 40,
        w = 260,
        text = "",
        font_size = 15,
        color = 0xC7D2FE,
    })
    info_label = airui.label({
        parent = main_container,
        x = 12,
        y = 62,
        w = 260,
        text = "",
        font_size = 13,
        color = 0x94A3B8,
    })
    hint_label = airui.label({
        parent = main_container,
        x = 12,
        y = 632,
        text = "",
        font_size = 16,
        color = 0xFDE68A,
    })

    board_layer = airui.container({
        parent = main_container,
        x = BOARD_X,
        y = BOARD_Y,
        w = BOARD_W,
        h = BOARD_H,
        color = 0x0F172A,
        radius = 12,
    })

    local function mk_btn(x, y, w, h, text, cb)
        return airui.button({
            parent = main_container,
            x = x,
            y = y,
            w = w,
            h = h,
            text = text,
            font_size = 22,
            text_color = 0xF8FAFC,
            bg_color = 0x1D4ED8,
            radius = 10,
            on_click = cb,
        })
    end

    mk_btn(386, 12, 82, 44, "退出", function()
        if exwin and exwin.close and win_id then
            exwin.close(win_id)
        end
    end)
    mk_btn(302, 10, 78, 44, "重开", function()
        load_level(cur.level)
    end)
    mk_btn(216, 10, 78, 44, "撤销", function()
        restore_history()
    end)

    mk_btn(92, 706, 84, 74, "左", function()
        try_move(-1, 0)
    end)
    mk_btn(198, 706, 84, 74, "下", function()
        try_move(0, 1)
    end)
    mk_btn(304, 706, 84, 74, "右", function()
        try_move(1, 0)
    end)
    mk_btn(198, 640, 84, 56, "上", function()
        try_move(0, -1)
    end)

    -- 先立即加载一次，再延后一拍校正，兼容不同固件刷新时序
    switch_level_set(1)
    sys.timerStart(function()
        if destroyed then
            return
        end
        if not cur.map then
            switch_level_set(1)
        end
        if max_level <= 0 and hint_label then
            hint_label:set_text("关卡库为空，请先在本地运行 Python 生成脚本")
        end
    end, 30)
end

local function on_create()
    create_ui()
end

local function on_destroy()
    destroyed = true
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 主容器销毁时其子对象一并释放，避免重复 destroy 导致卡住
    box_objs = {}
    player_obj = nil
    board_layer = nil
    title_label = nil
    hud_left = nil
    status_label = nil
    info_label = nil
    hint_label = nil
    win_id = nil
end

local function on_get_focus()
    if destroyed then
        return
    end
    if not cur.map and max_level > 0 then
        load_level(1)
    end
end
local function on_lose_focus() end

local function open_handler()
    if win_id then
        return
    end
    if not ensure_airui() then
        log.error("sokoban_win", "airui init failed")
        return
    end
    destroyed = false
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_SOKOBAN_WIN", open_handler)

function sokoban_open()
    open_handler()
end
