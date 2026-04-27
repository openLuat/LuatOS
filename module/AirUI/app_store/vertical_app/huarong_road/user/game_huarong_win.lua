--[[
@module  game_huarong_win
@summary 数字华容道窗口模块
@version 1.0.0
@date    2026.04.13
@author  郭幸福
]]

local win_id = nil
local main_container
local board = {}
local tiles = {}
local moves = 0
local moves_label
local game_over_msgbox = nil
local solving_timer = nil
local solution_steps = {}
local solution_index = 0
local is_auto_solving = false
local solve_btn = nil
local best_solution = 0

local TILE_COLORS = {
    { bg = 0xEEE4DA, text = 0x776E65 },
    { bg = 0xEDE0C8, text = 0x776E65 },
    { bg = 0xF2B179, text = 0xF9F6F2 },
    { bg = 0xF59563, text = 0xF9F6F2 },
    { bg = 0xF67C5F, text = 0xF9F6F2 },
    { bg = 0xF65E3B, text = 0xF9F6F2 },
    { bg = 0xEDCF72, text = 0xF9F6F2 },
    { bg = 0xEDCC61, text = 0xF9F6F2 },
    { bg = 0xEDC850, text = 0xF9F6F2 },
    { bg = 0xEDC53F, text = 0xF9F6F2 },
    { bg = 0xEDC22E, text = 0xF9F6F2 },
    { bg = 0x3C3A32, text = 0xF9F6F2 },
    { bg = 0x246, text = 0xFFFFFF },
    { bg = 0xE91E63, text = 0xFFFFFF },
    { bg = 0x9C27B0, text = 0xFFFFFF },
}

local function get_tile_color(value)
    if value == 0 then
        return { bg = 0xBBADA0, text = 0xBBADA0 }
    end
    local index = (value - 1) % #TILE_COLORS + 1
    return TILE_COLORS[index]
end

local function find_empty()
    for i = 1, 4 do
        for j = 1, 4 do
            if board[i][j] == 0 then
                return i, j
            end
        end
    end
    return nil, nil
end

local function count_inversions(tiles_flat)
    local inversions = 0
    local len = #tiles_flat
    for i = 1, len do
        for j = i + 1, len do
            if tiles_flat[i] ~= 0 and tiles_flat[j] ~= 0 and tiles_flat[i] > tiles_flat[j] then
                inversions = inversions + 1
            end
        end
    end
    return inversions
end

local function is_solvable(tiles_flat)
    local inversions = count_inversions(tiles_flat)
    local _, empty_row = find_empty()
    local empty_row_from_bottom = 5 - empty_row
    if empty_row_from_bottom % 2 == 1 then
        return inversions % 2 == 1
    else
        return inversions % 2 == 0
    end
end

local function shuffle_board()
    local tiles_flat = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0}
    repeat
        for i = #tiles_flat, 2, -1 do
            local j = math.random(i)
            tiles_flat[i], tiles_flat[j] = tiles_flat[j], tiles_flat[i]
        end
    until is_solvable(tiles_flat)

    for i = 1, 4 do
        for j = 1, 4 do
            board[i][j] = tiles_flat[(i-1)*4 + j]
        end
    end
end

local function init_board()
    for i = 1, 4 do
        board[i] = {0, 0, 0, 0}
    end
    shuffle_board()
end

local function check_win()
    local expected = 1
    for i = 1, 4 do
        for j = 1, 4 do
            if i == 4 and j == 4 then
                if board[i][j] ~= 0 then
                    return false
                end
            else
                if board[i][j] ~= expected then
                    return false
                end
                expected = expected + 1
            end
        end
    end
    return true
end

local function update_tiles()
    for i = 1, 4 do
        for j = 1, 4 do
            local value = board[i][j]
            local tile = tiles[i][j]
            if tile then
                local color = get_tile_color(value)
                tile:set_style({ bg_color = color.bg, text_color = color.text })
                tile:set_text(value == 0 and "" or tostring(value))
            end
        end
    end
    moves_label:set_text("步数: " .. moves)
end

local function move_empty(dir)
    local empty_i, empty_j = find_empty()
    if not empty_i then return false end

    local new_i, new_j = empty_i, empty_j

    if dir == "up" then
        new_i = empty_i + 1
    elseif dir == "down" then
        new_i = empty_i - 1
    elseif dir == "left" then
        new_j = empty_j + 1
    elseif dir == "right" then
        new_j = empty_j - 1
    end

    if new_i < 1 or new_i > 4 or new_j < 1 or new_j > 4 then
        return false
    end

    board[empty_i][empty_j] = board[new_i][new_j]
    board[new_i][new_j] = 0
    return true
end

local function reset_game()
    moves = 0
    init_board()
    update_tiles()
end

local function handle_move(dir)
    if move_empty(dir) then
        moves = moves + 1
        update_tiles()

        if check_win() then
            if game_over_msgbox then
                game_over_msgbox:destroy()
                game_over_msgbox = nil
            end
            game_over_msgbox = airui.msgbox({
                title = "恭喜通关",
                text = "你用了 " .. moves .. " 步完成！\n点击重新开始",
                buttons = { "重新开始" },
                on_action = function(self, label)
                    if label == "重新开始" then
                        self:hide()
                    end
                    self:destroy()
                    game_over_msgbox = nil
                    reset_game()
                end
            }):show()
        end
    end
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xFAF8EF, parent = airui.screen })

    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 80, color = 0xBBADA0 })
    airui.label({ parent = title_bar, x = 20, y = 20, w = 200, h = 40, text = "数字华容道", size = 32, color = 0xfefefe, align = airui.TEXT_ALIGN_LEFT })

    local info_container = airui.container({ parent = title_bar, x = 280, y = 20, w = 180, h = 40, color = 0xBBADA0 })
    moves_label = airui.label({ parent = info_container, x = 0, y = 0, w = 180, h = 40, text = "步数: 0", size = 24, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    local board_container = airui.container({ parent = main_container, x = 35, y = 100, w = 410, h = 410, color = 0xBBADA0, radius = 5 })

    local tile_size = 90
    local gap = 10
    for i = 1, 4 do
        tiles[i] = {}
        for j = 1, 4 do
            local x = (j-1) * (tile_size + gap) + gap
            local y = (i-1) * (tile_size + gap) + gap
            local tile = airui.button({
                parent = board_container,
                x = x, y = y,
                w = tile_size, h = tile_size,
                text = "",
                style = {
                    bg_color = 0xCDC1B4,
                    text_color = 0x776E65,
                    border_width = 0,
                    radius = 3,
                },
                on_click = function() end
            })
            tiles[i][j] = tile
        end
    end

    local dpad_container = airui.container({ parent = main_container, x = 115, y = 520, w = 250, h = 170, color = 0xFAF8EF })

    airui.button({
        parent = dpad_container,
        x = 97, y = 5,
        w = 55, h = 55,
        text = "↑",
        size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("up") end
    })

    airui.button({
        parent = dpad_container,
        x = 10, y = 60,
        w = 55, h = 55,
        text = "←",
        size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("left") end
    })

    airui.button({
        parent = dpad_container,
        x = 185, y = 60,
        w = 55, h = 55,
        text = "→",
        size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("right") end
    })

    airui.button({
        parent = dpad_container,
        x = 97, y = 115,
        w = 55, h = 55,
        text = "↓",
        size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("down") end
    })

    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 740, w = 480, h = 60, color = 0xffffff })

    local new_btn = airui.button({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = 240,
        h = 60,
        text = "新游戏",
        style = {
            bg_color = 0x8F7A66,
            text_color = 0xfefefe,
            border_color = 0x8F7A66,
            border_width = 0,
            radius = 0,
        },
        on_click = reset_game
    })

    local back_btn = airui.button({
        parent = bottom_bar,
        x = 240,
        y = 0,
        w = 240,
        h = 60,
        text = "返回首页",
        style = {
            bg_color = 0x2195F6,
            text_color = 0xfefefe,
            border_color = 0x2195F6,
            border_width = 0,
            radius = 0,
        },
        on_click = function() exwin.close(win_id) end
    })

    reset_game()
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if game_over_msgbox then
        game_over_msgbox:destroy()
        game_over_msgbox = nil
    end

    if main_container then
        main_container:destroy()
        main_container = nil
    end

    tiles = {}
    board = {}
    moves = 0
    moves_label = nil
end

local function on_get_focus()
end

local function on_lose_focus()
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_GAME_HUARONG_WIN", open_handler)