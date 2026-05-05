--[[
  Tetris（AirUI，480×800，8101_turnkey / 沙箱）。棋盘宽 10×CELL_SIZE ≤ 480。
]]
local tetris_game = {}

local SCREEN_W = 480
local SCREEN_H = 800

local GRID_W = 10
local GRID_H = 20
-- 10×20 格；单格尽量大，且棋盘总宽不超过 480（10×28=280）
local CELL_SIZE = 28

local EMPTY_COLOR = 0x1F2937
local BOARD_BG = 0x0B1220
local ROOT_BG = 0x020617
local INFO_BG = 0x0F172A

local HEADER_H = 52
local STATUS_BAR_H = 40
-- 状态提示在标题栏下方，棋盘紧贴其下留白
local BOARD_W = GRID_W * CELL_SIZE
local BOARD_H = GRID_H * CELL_SIZE
local BOARD_X = math.floor((SCREEN_W - BOARD_W) / 2)
local BOARD_Y = HEADER_H + STATUS_BAR_H + 8

local SHAPES = {
    { { 1, 1, 1, 1 } },
    { { 1, 0, 0 }, { 1, 1, 1 } },
    { { 0, 0, 1 }, { 1, 1, 1 } },
    { { 1, 1 }, { 1, 1 } },
    { { 0, 1, 1 }, { 1, 1, 0 } },
    { { 0, 1, 0 }, { 1, 1, 1 } },
    { { 1, 1, 0 }, { 0, 1, 1 } },
}

local PIECE_COLORS = {
    0x22D3EE,
    0x3B82F6,
    0xF59E0B,
    0xFACC15,
    0x22C55E,
    0xA855F7,
    0xEF4444,
}

local FALL_INTERVAL_MS = 550

local root
local board_container
local board_cells
local cell_cache
local score_label
local lines_label
local status_label
local pause_button
local timer_id

local grid
local current_piece
local score
local lines
local paused
local game_over

local on_exit
local host_win_id

local function request_exit()
    if host_win_id ~= nil then
        exwin.close(host_win_id)
        return
    end
    if on_exit ~= nil then
        on_exit()
    end
end

local function on_create()
    math.randomseed(os.time())
    tetris_game.start()
end

local function on_destroy()
    tetris_game.cleanup()
end

local function on_get_focus() end

local function on_lose_focus() end

local function make_button_style()
    return {
        bg_color = 0x1E293B,
        bg_opa = 255,
        border_color = 0x475569,
        border_width = 2,
        radius = 14,
        pad = 8,
        text_color = 0xE2E8F0,
        pressed_bg_color = 0x334155,
        pressed_bg_opa = 255,
        pressed_text_color = 0xFFFFFF,
        focus_outline_color = 0x94A3B8,
        focus_outline_width = 2,
    }
end

local function make_dpad_style()
    return {
        bg_color = 0x111827,
        bg_opa = 255,
        border_color = 0x64748B,
        border_width = 2,
        radius = 18,
        pad = 8,
        text_color = 0xF8FAFC,
        pressed_bg_color = 0x1F2937,
        pressed_bg_opa = 255,
        pressed_text_color = 0xFFFFFF,
        focus_outline_color = 0x94A3B8,
        focus_outline_width = 2,
    }
end

local function make_round_button_style(bg_color, border_color)
    return {
        bg_color = bg_color,
        bg_opa = 255,
        border_color = border_color,
        border_width = 2,
        radius = 999,
        pad = 8,
        text_color = 0xFFFFFF,
        pressed_bg_color = border_color,
        pressed_bg_opa = 255,
        pressed_text_color = 0xFFFFFF,
        focus_outline_color = 0xE2E8F0,
        focus_outline_width = 2,
    }
end

local function set_timer_running(enable)
    if enable then
        if timer_id == nil then
            timer_id = sys.timerLoopStart(function()
                tetris_game.step_down()
            end, FALL_INTERVAL_MS)
        end
        return
    end

    if timer_id ~= nil then
        sys.timerStop(timer_id)
        timer_id = nil
    end
end

local function init_grid()
    grid = {}
    for y = 1, GRID_H do
        grid[y] = {}
        for x = 1, GRID_W do
            grid[y][x] = 0
        end
    end
end

local function clone_piece(piece)
    return {
        x = piece.x,
        y = piece.y,
        shape = piece.shape,
        color = piece.color,
    }
end

local function each_block(piece, fn)
    for row = 1, #piece.shape do
        for col = 1, #piece.shape[row] do
            if piece.shape[row][col] == 1 then
                fn(piece.x + col - 1, piece.y + row - 1)
            end
        end
    end
end

local function rotate_shape(shape)
    local h = #shape
    local w = #shape[1]
    local rotated = {}
    for x = 1, w do
        rotated[x] = {}
        for y = 1, h do
            rotated[x][y] = shape[h - y + 1][x]
        end
    end
    return rotated
end

local function valid_position(piece)
    local valid = true
    each_block(piece, function(x, y)
        if x < 1 or x > GRID_W or y < 1 or y > GRID_H or grid[y][x] ~= 0 then
            valid = false
        end
    end)
    return valid
end

local function spawn_piece()
    local index = math.random(1, #SHAPES)
    local shape = SHAPES[index]
    current_piece = {
        x = math.floor((GRID_W - #shape[1]) / 2) + 1,
        y = 1,
        shape = shape,
        color = index,
    }
    if not valid_position(current_piece) then
        game_over = true
        current_piece = nil
        set_timer_running(false)
    end
end

local function merge_piece()
    if current_piece == nil then
        return
    end
    each_block(current_piece, function(x, y)
        if x >= 1 and x <= GRID_W and y >= 1 and y <= GRID_H then
            grid[y][x] = current_piece.color
        end
    end)
end

local function clear_lines()
    local cleared = 0
    local y = GRID_H
    while y >= 1 do
        local full = true
        for x = 1, GRID_W do
            if grid[y][x] == 0 then
                full = false
                break
            end
        end

        if full then
            cleared = cleared + 1
            for row = y, 2, -1 do
                for col = 1, GRID_W do
                    grid[row][col] = grid[row - 1][col]
                end
            end
            for col = 1, GRID_W do
                grid[1][col] = 0
            end
        else
            y = y - 1
        end
    end

    if cleared > 0 then
        score = score + cleared * 100
        lines = lines + cleared
    end

    return cleared
end

local function update_labels(message)
    if score_label ~= nil then
        score_label:set_text("Score: " .. tostring(score))
    end
    if lines_label ~= nil then
        lines_label:set_text("Lines: " .. tostring(lines))
    end
    if status_label ~= nil then
        if game_over then
            status_label:set_text("Game over. Tap Retry.")
        elseif paused then
            status_label:set_text("Paused")
        elseif message ~= nil then
            status_label:set_text(message)
        else
            status_label:set_text("Tap buttons to play")
        end
    end
    if pause_button ~= nil and pause_button.set_text then
        if paused then
            pause_button:set_text("Resume")
        else
            pause_button:set_text("Pause")
        end
    end
end

local function render_board()
    for y = 1, GRID_H do
        for x = 1, GRID_W do
            cell_cache[y][x] = grid[y][x]
        end
    end

    if current_piece ~= nil then
        each_block(current_piece, function(x, y)
            if x >= 1 and x <= GRID_W and y >= 1 and y <= GRID_H then
                cell_cache[y][x] = current_piece.color
            end
        end)
    end

    for y = 1, GRID_H do
        for x = 1, GRID_W do
            local value = cell_cache[y][x]
            local color = EMPTY_COLOR
            if value ~= 0 then
                color = PIECE_COLORS[value]
            end
            board_cells[y][x]:set_color(color)
        end
    end
end

local function refresh(message)
    update_labels(message)
    render_board()
end

function tetris_game.step_down()
    if paused or game_over or current_piece == nil then
        return
    end

    local next_piece = clone_piece(current_piece)
    next_piece.y = next_piece.y + 1
    if valid_position(next_piece) then
        current_piece = next_piece
        refresh(nil)
        return
    end

    merge_piece()
    local cleared = clear_lines()
    spawn_piece()
    if game_over then
        refresh(nil)
    elseif cleared > 0 then
        refresh("Cleared " .. tostring(cleared) .. " line(s)")
    else
        refresh(nil)
    end
end

local function hard_drop()
    if paused or game_over or current_piece == nil then
        return
    end

    while true do
        local next_piece = clone_piece(current_piece)
        next_piece.y = next_piece.y + 1
        if not valid_position(next_piece) then
            break
        end
        current_piece = next_piece
    end

    merge_piece()
    local cleared = clear_lines()
    spawn_piece()
    if game_over then
        refresh(nil)
    elseif cleared > 0 then
        refresh("Cleared " .. tostring(cleared) .. " line(s)")
    else
        refresh(nil)
    end
end

local function move_piece(dx, dy)
    if paused or game_over or current_piece == nil then
        return
    end

    local next_piece = clone_piece(current_piece)
    next_piece.x = next_piece.x + dx
    next_piece.y = next_piece.y + dy
    if valid_position(next_piece) then
        current_piece = next_piece
        refresh(nil)
    end
end

local function rotate_piece()
    if paused or game_over or current_piece == nil then
        return
    end

    local next_piece = clone_piece(current_piece)
    next_piece.shape = rotate_shape(current_piece.shape)

    if valid_position(next_piece) then
        current_piece = next_piece
        refresh(nil)
        return
    end

    next_piece.x = next_piece.x - 1
    if valid_position(next_piece) then
        current_piece = next_piece
        refresh(nil)
        return
    end

    next_piece.x = next_piece.x + 2
    if valid_position(next_piece) then
        current_piece = next_piece
        refresh(nil)
    end
end

local function toggle_pause()
    if game_over then
        return
    end

    paused = not paused
    set_timer_running(not paused)
    refresh(nil)
end

local function reset_game()
    score = 0
    lines = 0
    paused = false
    game_over = false
    init_grid()
    spawn_piece()
    set_timer_running(not game_over)
    refresh("Tap buttons to play")
end

local function create_board_cells(parent)
    board_cells = {}
    cell_cache = {}

    for y = 1, GRID_H do
        board_cells[y] = {}
        cell_cache[y] = {}
        for x = 1, GRID_W do
            local cell = airui.container({
                parent = parent,
                x = (x - 1) * CELL_SIZE,
                y = (y - 1) * CELL_SIZE,
                w = CELL_SIZE,
                h = CELL_SIZE,
                color = EMPTY_COLOR,
                border_color = 0x334155,
                border_width = 1,
                radius = 3,
            })
            board_cells[y][x] = cell
            cell_cache[y][x] = 0
        end
    end
end

local function create_controls(parent)
    local style = make_button_style()
    local dpad_style = make_dpad_style()
    local a_style = make_round_button_style(0x7C3AED, 0x8B5CF6)
    local b_style = make_round_button_style(0x0F766E, 0x14B8A6)
    local btn_w = 112
    local btn_h = 44
    local gap_y = 12
    -- 控制区紧跟棋盘，避免硬编码 y（换分辨率或 CELL_SIZE 时仍对齐）
    local controls_top_gap = 14
    local row1_y = BOARD_Y + BOARD_H + controls_top_gap
    local row2_y = row1_y + btn_h + gap_y
    local round_size = 56
    local round_y1 = row1_y - 4
    local round_y2 = row2_y - 4
    local round_x = math.floor((SCREEN_W - round_size) / 2)
    local panel_pad = 14
    local panel_h = btn_h * 2 + gap_y + panel_pad * 2

    airui.container({
        parent = parent,
        x = 8,
        y = row1_y - panel_pad,
        w = SCREEN_W - 16,
        h = panel_h,
        color = 0x0F172A,
        border_color = 0x334155,
        border_width = 1,
        radius = 18,
    })

    airui.button({
        parent = parent,
        x = 18,
        y = row1_y,
        w = btn_w,
        h = btn_h,
        text = "<",
        font_size = 22,
        style = dpad_style,
        on_click = function()
            move_piece(-1, 0)
        end,
    })

    airui.button({
        parent = parent,
        x = round_x,
        y = round_y1,
        w = round_size,
        h = round_size,
        text = "Rot",
        font_size = 16,
        style = a_style,
        on_click = function()
            rotate_piece()
        end,
    })

    airui.button({
        parent = parent,
        x = SCREEN_W - 18 - btn_w,
        y = row1_y,
        w = btn_w,
        h = btn_h,
        text = ">",
        font_size = 22,
        style = dpad_style,
        on_click = function()
            move_piece(1, 0)
        end,
    })

    pause_button = airui.button({
        parent = parent,
        x = 18,
        y = row2_y,
        w = btn_w,
        h = btn_h,
        text = "Pause",
        font_size = 20,
        style = style,
        on_click = function()
            toggle_pause()
        end,
    })

    airui.button({
        parent = parent,
        x = round_x,
        y = round_y2,
        w = round_size,
        h = round_size,
        text = "Drop",
        font_size = 16,
        style = b_style,
        on_click = function()
            hard_drop()
        end,
    })

    airui.button({
        parent = parent,
        x = SCREEN_W - 18 - btn_w,
        y = row2_y,
        w = btn_w,
        h = btn_h,
        text = "Retry",
        font_size = 20,
        style = style,
        on_click = function()
            reset_game()
        end,
    })
end

local function create_ui()
    root = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = ROOT_BG,
        parent = airui.screen,
    })

    airui.container({
        parent = root,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = HEADER_H,
        color = INFO_BG,
        border_width = 0,
        radius = 0,
    })

    airui.button({
        parent = root,
        x = 8,
        y = 6,
        w = 64,
        h = 40,
        text = "Back",
        font_size = 18,
        style = {
            bg_color = 0x1E293B,
            pressed_bg_color = 0x334155,
            text_color = 0xE2E8F0,
            radius = 20,
            border_width = 1,
            border_color = 0x475569,
            pad = 0,
        },
        on_click = function()
            request_exit()
        end,
    })

    local score_w = 128
    airui.label({
        parent = root,
        text = "Tetris",
        x = 80,
        y = 10,
        w = SCREEN_W - 80 - 12 - score_w - 8,
        h = 32,
        font_size = 22,
        color = 0xE2E8F0,
    })

    score_label = airui.label({
        parent = root,
        text = "Score: 0",
        x = SCREEN_W - 12 - score_w,
        y = 8,
        w = score_w,
        h = 22,
        font_size = 18,
        color = 0xE2E8F0,
    })

    local lines_w = 200
    lines_label = airui.label({
        parent = root,
        text = "Lines: 0",
        x = SCREEN_W - 12 - lines_w,
        y = 30,
        w = lines_w,
        h = 22,
        font_size = 16,
        color = 0x94A3B8,
    })

    status_label = airui.label({
        parent = root,
        text = "Tap buttons to play",
        x = 12,
        y = HEADER_H + 4,
        w = SCREEN_W - 24,
        h = STATUS_BAR_H - 4,
        font_size = 17,
        color = 0x93C5FD,
        align = airui.TEXT_ALIGN_CENTER,
    })

    board_container = airui.container({
        parent = root,
        x = BOARD_X,
        y = BOARD_Y,
        w = BOARD_W,
        h = BOARD_H,
        color = BOARD_BG,
        border_width = 0,
        radius = 8,
    })

    create_board_cells(board_container)
    create_controls(root)
end

function tetris_game.cleanup()
    set_timer_running(false)
    if root ~= nil then
        root:destroy()
        root = nil
    end
    board_container = nil
    board_cells = nil
    cell_cache = nil
    score_label = nil
    lines_label = nil
    status_label = nil
    pause_button = nil
    on_exit = nil
    host_win_id = nil
    grid = nil
    current_piece = nil
end

---@param exit_cb function|nil 兼容旧调用方式，作为返回兜底回调
function tetris_game.start(exit_cb)
    tetris_game.cleanup()
    on_exit = exit_cb
    create_ui()
    reset_game()
end

local function open_handler()
    host_win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_TETRIS_WIN", open_handler)

return tetris_game
