--[[
@module  game_othello_win
@summary 黑白棋游戏窗口模块
@version 1.0.0
@date    2026.04.13
@author  郭幸福
]]


local auto_play = require "auto_play"
local win_id = nil
local main_container
local board = {}
local cells = {}
local current_player = 1
local black_count = 0
local white_count = 0
local black_label
local white_label
local turn_label
local pass_msgbox = nil
local game_over_msgbox = nil
local color_select_msgbox = nil

local BLACK = 1
local WHITE = 2
local EMPTY = 0

local player_color = BLACK
local computer_color = WHITE
local game_started = false

local DIRECTIONS = {
    {-1, -1}, {-1, 0}, {-1, 1},
    {0, -1},          {0, 1},
    {1, -1},  {1, 0},  {1, 1}
}

local function init_board()
    for i = 1, 8 do
        board[i] = {0, 0, 0, 0, 0, 0, 0, 0}
    end
    board[4][4] = WHITE
    board[4][5] = BLACK
    board[5][4] = BLACK
    board[5][5] = WHITE
    current_player = BLACK
end

local function count_pieces()
    black_count = 0
    white_count = 0
    for i = 1, 8 do
        for j = 1, 8 do
            if board[i][j] == BLACK then
                black_count = black_count + 1
            elseif board[i][j] == WHITE then
                white_count = white_count + 1
            end
        end
    end
end

local function update_score_ui()
    black_label:set_text("黑: " .. black_count)
    white_label:set_text("白: " .. white_count)
    if current_player == BLACK then
        turn_label:set_text("黑棋回合")
    else
        turn_label:set_text("白棋回合")
    end
end

local last_board = {}

local function init_last_board()
    for i = 1, 8 do
        last_board[i] = {0, 0, 0, 0, 0, 0, 0, 0}
    end
end

local function update_board_ui(row, col)
    local cell = cells[row][col]
    if cell then
        local value = board[row][col]
        if value == BLACK then
            cell:set_style({ bg_color = 0x1A1A1A })
        elseif value == WHITE then
            cell:set_style({ bg_color = 0xF5F5F5 })
        else
            cell:set_style({ bg_color = 0x00A0A0 })
        end
    end
end

local function update_board_ui_full()
    for i = 1, 8 do
        for j = 1, 8 do
            local cell = cells[i][j]
            if cell then
                local value = board[i][j]
                if value == BLACK then
                    cell:set_style({ bg_color = 0x1A1A1A })
                elseif value == WHITE then
                    cell:set_style({ bg_color = 0xF5F5F5 })
                else
                    cell:set_style({ bg_color = 0x00A0A0 })
                end
            end
        end
    end
end

local function is_valid_move(row, col, player)
    if row < 1 or row > 8 or col < 1 or col > 8 then
        return false
    end
    if board[row][col] ~= EMPTY then
        return false
    end

    local opponent = (player == BLACK) and WHITE or BLACK

    for _, dir in ipairs(DIRECTIONS) do
        local dr, dc = dir[1], dir[2]
        local r, c = row + dr, col + dc
        local found_opponent = false

        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            if board[r][c] == opponent then
                found_opponent = true
            elseif board[r][c] == player then
                if found_opponent then
                    return true
                end
                break
            else
                break
            end
            r = r + dr
            c = c + dc
        end
    end

    return false
end

local function get_flipped(row, col, player)
    local flipped = {}
    local opponent = (player == BLACK) and WHITE or BLACK

    for _, dir in ipairs(DIRECTIONS) do
        local dr, dc = dir[1], dir[2]
        local r, c = row + dr, col + dc
        local dir_flipped = {}

        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            if board[r][c] == opponent then
                table.insert(dir_flipped, {r, c})
            elseif board[r][c] == player then
                for _, pos in ipairs(dir_flipped) do
                    table.insert(flipped, pos)
                end
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

local function make_move(row, col, player, flipped)
    board[row][col] = player
    if flipped then
        for _, pos in ipairs(flipped) do
            board[pos[1]][pos[2]] = player
        end
    end
    return true
end

local function has_valid_move(player)
    for i = 1, 8 do
        for j = 1, 8 do
            if is_valid_move(i, j, player) then
                return true
            end
        end
    end
    return false
end

local function check_game_over()
    if game_over_msgbox then
        game_over_msgbox:destroy()
        game_over_msgbox = nil
    end
    local winner
    if black_count > white_count then
        winner = "黑棋胜利!"
    elseif white_count > black_count then
        winner = "白棋胜利!"
    else
        winner = "平局!"
    end
    game_over_msgbox = airui.msgbox({
        title = "游戏结束",
        text = winner .. "\n黑:" .. black_count .. " 白:" .. white_count .. "\n点击重新开始",
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
    game_started = false
end

local function computer_move()
    log.info("computer_move: started")
    log.info("computer_move: game_started", game_started)
    log.info("computer_move: current_player", current_player)
    log.info("computer_move: computer_color", computer_color)
    
    if not game_started then
        log.info("computer_move: game not started")
        return
    end

    if current_player ~= computer_color then
        log.info("computer_move: not computer turn", current_player, computer_color)
        return
    end

    local computer_has_move = has_valid_move(computer_color)
    local player_has_move = has_valid_move((computer_color == BLACK) and WHITE or BLACK)
    log.info("computer_move: computer_has_move", computer_has_move)
    log.info("computer_move: player_has_move", player_has_move)
    
    if not computer_has_move and not player_has_move then
        log.info("computer_move: both players can't move")
        check_game_over()
        return
    end
    
    local move = auto_play.get_best_move(board, computer_color)
    log.info("computer_move: best move", move)
    if not move then
        if not computer_has_move then
            log.info("computer_move: computer can't move")
            local next_player = (computer_color == BLACK) and WHITE or BLACK
            if player_has_move then
                current_player = next_player
                update_score_ui()
                log.info("computer_move: switch to next player", next_player)
            else
                log.info("computer_move: game over")
                check_game_over()
            end
            return
        else
            log.info("computer_move: looking for first valid move")
            -- 增强的备用移动查找逻辑
            for i = 1, 8 do
                for j = 1, 8 do
                    log.info("computer_move: checking move", i, j)
                    if is_valid_move(i, j, computer_color) then
                        move = {row = i, col = j}
                        log.info("computer_move: found valid move", move)
                        break
                    end
                end
                if move then
                    break
                end
            end
            if not move then
                log.info("computer_move: no valid move found, double checking")
                -- 再次检查，确保没有遗漏
                local has_valid = has_valid_move(computer_color)
                log.info("computer_move: has_valid_move result", has_valid)
                if has_valid then
                    -- 如果has_valid_move返回true但找不到具体移动，尝试更详细的查找
                    for i = 1, 8 do
                        for j = 1, 8 do
                            if board[i][j] == EMPTY then
                                log.info("computer_move: checking empty cell", i, j)
                                if is_valid_move(i, j, computer_color) then
                                    move = {row = i, col = j}
                                    log.info("computer_move: found valid move after double check", move)
                                    break
                                end
                            end
                        end
                        if move then
                            break
                        end
                    end
                end
                if not move then
                    log.info("computer_move: still no valid move found")
                    return
                end
            end
        end
    end

    if move then
        log.info("computer_move: making move", move)
        local flipped = get_flipped(move.row, move.col, computer_color)
        make_move(move.row, move.col, computer_color, flipped)
        count_pieces()
        update_board_ui(move.row, move.col)
        for _, pos in ipairs(flipped) do
            update_board_ui(pos[1], pos[2])
        end
        update_score_ui()

        local next_player = (computer_color == BLACK) and WHITE or BLACK
        local next_player_has_move = has_valid_move(next_player)
        local computer_still_has_move = has_valid_move(computer_color)
        log.info("computer_move: next_player_has_move", next_player_has_move)
        log.info("computer_move: computer_still_has_move", computer_still_has_move)
        
        if not next_player_has_move and not computer_still_has_move then
            log.info("computer_move: game over after move")
            check_game_over()
            return
        elseif not next_player_has_move then
            log.info("computer_move: next player can't move, checking if game should end")
            -- 检查双方是否都无法移动
            if not computer_still_has_move then
                log.info("computer_move: both players can't move, game over")
                check_game_over()
                return
            end
            log.info("computer_move: computer still has move, playing again")
            sys.timerStart(computer_move_delayed, 500)
        else
            current_player = next_player
            update_score_ui()
            log.info("computer_move: switch to next player", next_player)
        end
    end
    log.info("computer_move: completed")
end


function reset_game()
    if pass_msgbox then
        pass_msgbox:destroy()
        pass_msgbox = nil
    end
    if game_over_msgbox then
        game_over_msgbox:destroy()
        game_over_msgbox = nil
    end
    init_board()
    init_last_board()
    count_pieces()
    update_board_ui_full()
    update_score_ui()
    game_started = false

    log.info("reset_game: creating color_select_msgbox")
    local msgbox = airui.msgbox({
        title = "选择执棋颜色",
        text = "请选择您执棋的颜色",
        buttons = { "执黑先手", "执白后手" },
        on_action = function(self, label)
            log.info("reset_game: color_select_msgbox: button clicked", label)
            if label == "执黑先手" then
                player_color = BLACK
                computer_color = WHITE
                current_player = BLACK  -- 确保current_player正确设置
                game_started = true
            else
                player_color = WHITE
                computer_color = BLACK
                current_player = BLACK  -- 确保current_player正确设置
                game_started = true
                computer_move()
            end
            log.info("reset_game: color_select_msgbox: hiding and destroying")
            self:hide()
            self:destroy()
            color_select_msgbox = nil
            log.info("reset_game: color_select_msgbox: destroyed and nil set")
        end
    })
    log.info("reset_game: msgbox created", msgbox)
    if msgbox then
        msgbox:show()
        color_select_msgbox = msgbox
        log.info("reset_game: color_select_msgbox set", color_select_msgbox)
    else
        log.error("reset_game: failed to create msgbox")
    end
end


function computer_move_delayed()
    computer_move()
end


local function handle_cell_click(row, col)
    if game_over_msgbox then
        return
    end

    if not game_started or current_player ~= player_color then
        return
    end

    if not is_valid_move(row, col, player_color) then
        return
    end

    local flipped = get_flipped(row, col, player_color)
    make_move(row, col, player_color, flipped)
    count_pieces()
    update_board_ui(row, col)
    for _, pos in ipairs(flipped) do
        update_board_ui(pos[1], pos[2])
    end
    update_score_ui()

    local next_player = (player_color == BLACK) and WHITE or BLACK
    if not has_valid_move(next_player) and not has_valid_move(player_color) then
        check_game_over()
        return
    end

    if not has_valid_move(next_player) then
        if pass_msgbox then
            pass_msgbox:destroy()
            pass_msgbox = nil
        end
        local pass_player = (player_color == BLACK) and "黑棋" or "白棋"
        pass_msgbox = airui.msgbox({
            title = "提示",
            text = pass_player .. "无法行动",
            buttons = { "确定" },
            on_action = function(self)
                self:hide()
                self:destroy()
                pass_msgbox = nil
                if has_valid_move(player_color) then
                    current_player = player_color
                    update_score_ui()
                    sys.timerStart(computer_move_delayed, 500)
                end
            end
        }):show()
    else
        current_player = next_player
        update_score_ui()
        sys.timerStart(computer_move_delayed, 500)
    end
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xE8E8E8, parent = airui.screen })

    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 80, color = 0x2E7D32 })
    airui.label({ parent = title_bar, x = 20, y = 20, w = 200, h = 40, text = "黑白棋", size = 32, color = 0xFFFFFF, align = airui.TEXT_ALIGN_LEFT })

    local score_bar = airui.container({ parent = main_container, x = 0, y = 90, w = 480, h = 60, color = 0xFFFFFF })

    black_label = airui.label({ parent = score_bar, x = 20, y = 10, w = 150, h = 40, text = "黑: 2", size = 24, color = 0x1A1A1A, align = airui.TEXT_ALIGN_LEFT })

    turn_label = airui.label({ parent = score_bar, x = 165, y = 10, w = 150, h = 40, text = "黑棋回合", size = 24, color = 0x2E7D32, align = airui.TEXT_ALIGN_CENTER })

    white_label = airui.label({ parent = score_bar, x = 310, y = 10, w = 150, h = 40, text = "白: 2", size = 24, color = 0x1A1A1A, align = airui.TEXT_ALIGN_RIGHT })

    local board_container = airui.container({ parent = main_container, x = 40, y = 170, w = 400, h = 400, color = 0x00A0A0, radius = 5 })

    local cell_size = 48
    local gap = 2

    for i = 1, 8 do
        cells[i] = {}
        for j = 1, 8 do
            local x = (j - 1) * (cell_size + gap)
            local y = (i - 1) * (cell_size + gap)
            local cell = airui.button({
                parent = board_container,
                x = x, y = y,
                w = cell_size, h = cell_size,
                text = "",
                style = {
                    bg_color = 0x00A0A0,
                    border_width = 0,
                    radius = 24,
                },
                on_click = function()
                    handle_cell_click(i, j)
                end
            })
            cells[i][j] = cell
        end
    end

    local hint_bar = airui.container({ parent = main_container, x = 0, y = 590, w = 480, h = 80, color = 0xE8E8E8 })
    airui.label({ parent = hint_bar, x = 20, y = 20, w = 440, h = 40, text = "点击空白位置下棋，夹住对方棋子可翻转", size = 16, color = 0x666666, align = airui.TEXT_ALIGN_CENTER })

    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 740, w = 480, h = 60, color = 0xFFFFFF })

    local new_btn = airui.button({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = 240,
        h = 60,
        text = "新游戏",
        style = {
            bg_color = 0x2E7D32,
            text_color = 0xFFFFFF,
            border_color = 0x2E7D32,
            border_width = 0,
            radius = 0,
        },
        on_click = function()
            if pass_msgbox or game_over_msgbox or color_select_msgbox then
                return
            end
            if not game_started then
                return
            end
            reset_game()
        end
    })


    init_board()
    init_last_board()
    count_pieces()
    update_board_ui_full()
    update_score_ui()
    game_started = false

    log.info("create_ui: creating color_select_msgbox")
    local msgbox = airui.msgbox({
        title = "选择执棋颜色",
        text = "请选择您执棋的颜色",
        buttons = { "执黑先手", "执白后手" },
        on_action = function(self, label)
            log.info("color_select_msgbox: button clicked", label)
            if label == "执黑先手" then
                player_color = BLACK
                computer_color = WHITE
                current_player = BLACK  -- 确保current_player正确设置
                game_started = true
            else
                player_color = WHITE
                computer_color = BLACK
                current_player = BLACK  -- 确保current_player正确设置
                game_started = true
                computer_move()
            end
            log.info("color_select_msgbox: hiding and destroying")
            self:hide()
            self:destroy()
            color_select_msgbox = nil
            log.info("color_select_msgbox: destroyed and nil set")
        end
    })
    log.info("create_ui: msgbox created", msgbox)
    if msgbox then
        msgbox:show()
        color_select_msgbox = msgbox
        log.info("create_ui: color_select_msgbox set", color_select_msgbox)
    else
        log.error("create_ui: failed to create msgbox")
    end

    
    local back_btn = airui.button({
        parent = bottom_bar,
        x = 240,
        y = 0,
        w = 240,
        h = 60,
        text = "返回首页",
        style = {
            bg_color = 0x2195F6,
            text_color = 0xFFFFFF,
            border_color = 0x2195F6,
            border_width = 0,
            radius = 0,
        },
        on_click = function()
            log.info("back_btn: clicked, destroying message boxes")
            if color_select_msgbox then
                log.info("back_btn: destroying color_select_msgbox")
                color_select_msgbox:destroy()
                color_select_msgbox = nil
                log.info("back_btn: color_select_msgbox destroyed")
            else
                log.info("back_btn: color_select_msgbox is nil")
            end
            if pass_msgbox then
                log.info("back_btn: destroying pass_msgbox")
                pass_msgbox:destroy()
                pass_msgbox = nil
                log.info("back_btn: pass_msgbox destroyed")
            else
                log.info("back_btn: pass_msgbox is nil")
            end
            if game_over_msgbox then
                log.info("back_btn: destroying game_over_msgbox")
                game_over_msgbox:destroy()
                game_over_msgbox = nil
                log.info("back_btn: game_over_msgbox destroyed")
            else
                log.info("back_btn: game_over_msgbox is nil")
            end
            log.info("back_btn: closing window")
            exwin.close(win_id)
        end
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    log.info("on_destroy: destroying message boxes")
    if pass_msgbox then
        log.info("on_destroy: destroying pass_msgbox")
        pass_msgbox:destroy()
        pass_msgbox = nil
        log.info("on_destroy: pass_msgbox destroyed")
    else
        log.info("on_destroy: pass_msgbox is nil")
    end
    if game_over_msgbox then
        log.info("on_destroy: destroying game_over_msgbox")
        game_over_msgbox:destroy()
        game_over_msgbox = nil
        log.info("on_destroy: game_over_msgbox destroyed")
    else
        log.info("on_destroy: game_over_msgbox is nil")
    end
    if color_select_msgbox then
        log.info("on_destroy: destroying color_select_msgbox")
        color_select_msgbox:destroy()
        color_select_msgbox = nil
        log.info("on_destroy: color_select_msgbox destroyed")
    else
        log.info("on_destroy: color_select_msgbox is nil")
    end

    log.info("on_destroy: destroying main container")
    if main_container then
        main_container:destroy()
        main_container = nil
        log.info("on_destroy: main_container destroyed")
    else
        log.info("on_destroy: main_container is nil")
    end

    log.info("on_destroy: resetting game state")
    cells = {}
    board = {}
    current_player = BLACK
    log.info("on_destroy: completed")
end

local function on_get_focus()
    if main_container then
        main_container:show()
    end
end

local function on_lose_focus()
    if main_container then
        main_container:hide()
    end
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_GAME_OTHELLO_WIN", open_handler)
