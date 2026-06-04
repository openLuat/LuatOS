--[[
@module  auto_play
@summary 黑白棋电脑AI模块
@version 1.0.0
@date    2026.04.14
@author  郭幸福
]]

local M = {}

local DIRECTIONS = {
    {-1, -1}, {-1, 0}, {-1, 1},
    {0, -1},          {0, 1},
    {1, -1},  {1, 0},  {1, 1}
}

local EMPTY = 0
local BLACK = 1
local WHITE = 2

local CORNERS = {{1,1}, {1,8}, {8,1}, {8,8}}
local ADJACENT_CORNERS = {
    {1,2}, {2,1}, {2,2},
    {1,7}, {2,7}, {2,8},
    {7,1}, {7,2}, {8,2},
    {7,7}, {7,8}, {8,7}
}

local EDGES = {}
for i = 1, 8 do
    if i ~= 1 and i ~= 8 then
        table.insert(EDGES, {1, i})
        table.insert(EDGES, {8, i})
        table.insert(EDGES, {i, 1})
        table.insert(EDGES, {i, 8})
    end
end

local function count_flipped(board, row, col, player)
    local flipped = 0
    local opponent = (player == BLACK) and WHITE or BLACK

    for _, dir in ipairs(DIRECTIONS) do
        local dr, dc = dir[1], dir[2]
        local r, c = row + dr, col + dc
        local dir_flipped = 0

        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            if board[r][c] == opponent then
                dir_flipped = dir_flipped + 1
            elseif board[r][c] == player then
                flipped = flipped + dir_flipped
                break
            else
                break
            end
            r = r + dr
            c = c + dc
        end
    end

    return flipped
end

local function is_valid_move(board, row, col, player)
    if row < 1 or row > 8 or col < 1 or col > 8 then
        return false
    end
    if board[row][col] ~= EMPTY then
        return false
    end

    return count_flipped(board, row, col, player) > 0
end

local function is_corner(row, col)
    for _, corner in ipairs(CORNERS) do
        if row == corner[1] and col == corner[2] then
            return true
        end
    end
    return false
end

local function is_adjacent_to_corner(row, col)
    for _, adj in ipairs(ADJACENT_CORNERS) do
        if row == adj[1] and col == adj[2] then
            return true
        end
    end
    return false
end

local function is_edge(row, col)
    for _, edge in ipairs(EDGES) do
        if row == edge[1] and col == edge[2] then
            return true
        end
    end
    return false
end

local function get_valid_moves(board, player)
    local moves = {}
    for i = 1, 8 do
        for j = 1, 8 do
            if is_valid_move(board, i, j, player) then
                table.insert(moves, {row = i, col = j})
            end
        end
    end
    return moves
end

function M.get_best_move(board, player)
    local moves = get_valid_moves(board, player)
    if #moves == 0 then
        return nil
    end

    local best_move = nil
    local best_score = -1

    for _, move in ipairs(moves) do
        local row, col = move.row, move.col
        local score = 0

        if is_corner(row, col) then
            score = 1000
        elseif is_adjacent_to_corner(row, col) then
            score = -100
        elseif is_edge(row, col) then
            score = 50
        end

        local flipped = count_flipped(board, row, col, player)
        score = score + flipped * 10

        if score > best_score then
            best_score = score
            best_move = move
        end
    end

    return best_move
end

return M
