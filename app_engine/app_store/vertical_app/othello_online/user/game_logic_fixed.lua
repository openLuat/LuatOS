local function computer_move()
    if not game_started then
        return
    end

    if current_player ~= computer_color then
        return
    end

    local move = auto_play.get_best_move(board, computer_color)
    if not move then
        if not has_valid_move(computer_color) then
            local next_player = (computer_color == BLACK) and WHITE or BLACK
            if has_valid_move(next_player) then
                current_player = next_player
                update_score_ui()
            else
                check_game_over()
            end
            return
        else
            for i = 1, 8 do
                for j = 1, 8 do
                    if is_valid_move(i, j, computer_color) then
                        move = {row = i, col = j}
                        break
                    end
                end
                if move then
                    break
                end
            end
        end
    end

    if move then
        local flipped = get_flipped(move.row, move.col, computer_color)
        make_move(move.row, move.col, computer_color, flipped)
        count_pieces()
        update_board_ui(move.row, move.col)
        for _, pos in ipairs(flipped) do
            update_board_ui(pos[1], pos[2])
        end
        update_score_ui()

        local next_player = (computer_color == BLACK) and WHITE or BLACK
        if not has_valid_move(next_player) then
            if not has_valid_move(computer_color) then
                check_game_over()
                return
            end
        else
            current_player = next_player
            update_score_ui()
        end
    end
end

local function computer_move_delayed()
    computer_move()
end

local function reset_game()
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
    game_started = true

    if current_player ~= player_color then
        sys.timerStart(computer_move_delayed, 500)
    end
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