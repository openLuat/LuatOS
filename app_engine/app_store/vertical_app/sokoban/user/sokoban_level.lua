--[[
@module  sokoban_level
@summary 可解推箱子关卡生成（逆向拉箱打乱 + 正向求解校验）
]]

local M = {}

local function key_xy(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function key_state(player_idx, boxes)
    return tostring(player_idx) .. "|" .. table.concat(boxes, ",")
end

local function sorted_copy(arr)
    local t = {}
    for i = 1, #arr do
        t[i] = arr[i]
    end
    table.sort(t)
    return t
end

local function index_of(arr, v)
    for i = 1, #arr do
        if arr[i] == v then
            return i
        end
    end
    return nil
end

local function build_board(w, h, level)
    local walls = {}
    for y = 1, h do
        walls[y] = {}
        for x = 1, w do
            local border = (x == 1 or y == 1 or x == w or y == h)
            walls[y][x] = border
        end
    end

    local interior = (w - 2) * (h - 2)
    local wall_count = math.max(0, math.floor(interior * (0.05 + math.min(0.12, level * 0.0035))))
    local tries = 0
    while wall_count > 0 and tries < interior * 8 do
        tries = tries + 1
        local x = math.random(2, w - 1)
        local y = math.random(2, h - 1)
        if not walls[y][x] then
            walls[y][x] = true
            wall_count = wall_count - 1
        end
    end
    return walls
end

local function collect_free_cells(walls, w, h)
    local cells = {}
    for y = 2, h - 1 do
        for x = 2, w - 1 do
            if not walls[y][x] then
                cells[#cells + 1] = { x = x, y = y }
            end
        end
    end
    return cells
end

local function make_index_maps(w, h)
    local idx_to_xy = {}
    local xy_to_idx = {}
    local idx = 1
    for y = 1, h do
        for x = 1, w do
            idx_to_xy[idx] = { x = x, y = y }
            xy_to_idx[key_xy(x, y)] = idx
            idx = idx + 1
        end
    end
    return idx_to_xy, xy_to_idx
end

local function build_boxes_set(boxes)
    local s = {}
    for i = 1, #boxes do
        s[boxes[i]] = true
    end
    return s
end

local DIRS = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local function reachable(player_idx, boxes, walls, idx_to_xy, xy_to_idx, w, h)
    local box_set = build_boxes_set(boxes)
    local q = { player_idx }
    local head = 1
    local seen = { [player_idx] = true }
    while head <= #q do
        local cur = q[head]
        head = head + 1
        local p = idx_to_xy[cur]
        for i = 1, #DIRS do
            local d = DIRS[i]
            local nx = p.x + d[1]
            local ny = p.y + d[2]
            if nx >= 1 and nx <= w and ny >= 1 and ny <= h then
                local ni = xy_to_idx[key_xy(nx, ny)]
                if not walls[ny][nx] and not box_set[ni] and not seen[ni] then
                    seen[ni] = true
                    q[#q + 1] = ni
                end
            end
        end
    end
    return seen
end

local function all_on_goals(boxes, goals_set)
    for i = 1, #boxes do
        if not goals_set[boxes[i]] then
            return false
        end
    end
    return true
end

local function min_push_solve(player_idx, boxes, goals_set, walls, idx_to_xy, xy_to_idx, w, h)
    local start_boxes = sorted_copy(boxes)
    local start_key = key_state(player_idx, start_boxes)
    local q = { { p = player_idx, b = start_boxes, push = 0 } }
    local head = 1
    local seen = { [start_key] = true }

    while head <= #q do
        local cur = q[head]
        head = head + 1

        if all_on_goals(cur.b, goals_set) then
            return cur.push
        end

        local box_set = build_boxes_set(cur.b)
        local reach = reachable(cur.p, cur.b, walls, idx_to_xy, xy_to_idx, w, h)
        for bi = 1, #cur.b do
            local bidx = cur.b[bi]
            local bxy = idx_to_xy[bidx]
            for di = 1, #DIRS do
                local d = DIRS[di]
                local px = bxy.x - d[1]
                local py = bxy.y - d[2]
                local tx = bxy.x + d[1]
                local ty = bxy.y + d[2]
                if px >= 1 and px <= w and py >= 1 and py <= h and tx >= 1 and tx <= w and ty >= 1 and ty <= h then
                    local pidx = xy_to_idx[key_xy(px, py)]
                    local tidx = xy_to_idx[key_xy(tx, ty)]
                    if reach[pidx] and not walls[ty][tx] and not box_set[tidx] then
                        local nb = sorted_copy(cur.b)
                        nb[bi] = tidx
                        table.sort(nb)
                        local nkey = key_state(bidx, nb)
                        if not seen[nkey] then
                            seen[nkey] = true
                            q[#q + 1] = { p = bidx, b = nb, push = cur.push + 1 }
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function reverse_scramble(player_idx, boxes, walls, idx_to_xy, xy_to_idx, w, h, steps)
    local p = player_idx
    local b = sorted_copy(boxes)
    local pulled = 0
    for _ = 1, steps do
        local box_set = build_boxes_set(b)
        local moves = {}
        for di = 1, #DIRS do
            local d = DIRS[di]
            local pxy = idx_to_xy[p]
            local nx = pxy.x + d[1]
            local ny = pxy.y + d[2]
            local bx = pxy.x - d[1]
            local by = pxy.y - d[2]
            if nx >= 1 and nx <= w and ny >= 1 and ny <= h then
                local ni = xy_to_idx[key_xy(nx, ny)]
                if not walls[ny][nx] and not box_set[ni] then
                    moves[#moves + 1] = { np = ni, pull = false }
                    if bx >= 1 and bx <= w and by >= 1 and by <= h then
                        local bi = xy_to_idx[key_xy(bx, by)]
                        if box_set[bi] then
                            moves[#moves + 1] = { np = ni, pull = true, box_from = bi, box_to = p }
                        end
                    end
                end
            end
        end

        if #moves == 0 then
            break
        end
        local pick = moves[math.random(1, #moves)]
        if pick.pull and math.random() < 0.8 then
            local idx = index_of(b, pick.box_from)
            if idx then
                b[idx] = pick.box_to
                table.sort(b)
                pulled = pulled + 1
            end
        end
        p = pick.np
    end
    return p, b, pulled
end

function M.generate(level)
    local w = math.min(12, 7 + math.floor((level - 1) / 3))
    local h = math.min(12, 7 + math.floor((level - 1) / 4))
    local box_n = math.min(4, 1 + math.floor((level - 1) / 4))
    local min_push = math.min(24, 3 + math.floor(level * 0.7))

    local idx_to_xy, xy_to_idx = make_index_maps(w, h)

    for _ = 1, 60 do
        local walls = build_board(w, h, level)
        local free_cells = collect_free_cells(walls, w, h)
        if #free_cells >= box_n + 2 then
            local goals = {}
            local used = {}
            for i = 1, box_n do
                local pick = free_cells[math.random(1, #free_cells)]
                while used[key_xy(pick.x, pick.y)] do
                    pick = free_cells[math.random(1, #free_cells)]
                end
                used[key_xy(pick.x, pick.y)] = true
                goals[#goals + 1] = xy_to_idx[key_xy(pick.x, pick.y)]
            end

            local player_pos = free_cells[math.random(1, #free_cells)]
            while used[key_xy(player_pos.x, player_pos.y)] do
                player_pos = free_cells[math.random(1, #free_cells)]
            end
            local player_idx = xy_to_idx[key_xy(player_pos.x, player_pos.y)]
            local goals_set = build_boxes_set(goals)

            local steps = 20 + level * 6
            local start_p, start_b, pull_count =
                reverse_scramble(player_idx, goals, walls, idx_to_xy, xy_to_idx, w, h, steps)
            if pull_count >= box_n * 2 and not all_on_goals(start_b, goals_set) then
                local pushes = min_push_solve(start_p, start_b, goals_set, walls, idx_to_xy, xy_to_idx, w, h)
                if pushes and pushes >= min_push then
                    local wall_rows = {}
                    local goal_rows = {}
                    local box_rows = {}
                    for y = 1, h do
                        wall_rows[y] = {}
                        goal_rows[y] = {}
                        box_rows[y] = {}
                        for x = 1, w do
                            wall_rows[y][x] = walls[y][x] and true or false
                            goal_rows[y][x] = false
                            box_rows[y][x] = false
                        end
                    end
                    for i = 1, #goals do
                        local pxy = idx_to_xy[goals[i]]
                        goal_rows[pxy.y][pxy.x] = true
                    end
                    for i = 1, #start_b do
                        local pxy = idx_to_xy[start_b[i]]
                        box_rows[pxy.y][pxy.x] = true
                    end
                    local pxy = idx_to_xy[start_p]
                    return {
                        level = level,
                        w = w,
                        h = h,
                        walls = wall_rows,
                        goals = goal_rows,
                        boxes = box_rows,
                        player = { x = pxy.x, y = pxy.y },
                        target_pushes = pushes,
                    }
                end
            end
        end
    end
    return nil
end

return M
