--[[
@module  chess_win
@summary 国际象棋人机对战
]]

-- exapp 沙箱里包装后的 exwin 在 _ENV 上；rawget(_G,"exwin") 易误用裸 exwin，退出后无法 exapp.close
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

local eng = require "chess_engine"
local piece_gfx = require "chess_piece_gfx"
local chess_sound = require "chess_sound"

local win_id = nil
local main_container = nil
local status_label = nil
local board_layer = nil
local cell_w = 56
-- 棋盘按「屏幕行 dr、列 dc」存：dr=1 为上、dr=8 为下（你始终在 dr=8 一侧）
local cells = {}
local state = nil
local selected = nil
local human_white = true
local game_over = false
local destroyed = false
local AI_DEPTH = 3

local SCREEN_W = 480
local SCREEN_H = 800
local BOARD_ORG_X = 16
local BOARD_ORG_Y = 120

local LIGHT_SQ = 0xEEE8D5
local DARK_SQ = 0xC9A227
local SEL_SQ = 0x7CB342
local LAST_SQ = 0x81C784

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

local function is_white_piece(ch)
    return ch >= "A" and ch <= "Z" and ch ~= "."
end

local function is_black_piece(ch)
    return ch >= "a" and ch <= "z"
end

local function human_turn()
    if not state then
        return false
    end
    if game_over then
        return false
    end
    if state.white_move and human_white then
        return true
    end
    if (not state.white_move) and (not human_white) then
        return true
    end
    return false
end

--- 屏幕行 dr -> 引擎行 er（你方总在屏幕下方：执白时白在 er=1.. 在下；执黑时黑在 er=8.. 在下）
local function display_to_engine_rank(dr)
    if human_white then
        return 9 - dr
    end
    return dr
end

local function engine_to_display_rank(er)
    if human_white then
        return 9 - er
    end
    return er
end

-- true：用 container 拼图形；false：用下方 Unicode / 字母
local USE_GRAPHICS_PIECES = true

-- Unicode 国际象棋字形（U+2654–U+265F）：白轮廓 / 黑实心
-- 若设备字体缺字会显示方框，可改 USE_UNICODE_PIECES = false 回退字母
local USE_UNICODE_PIECES = true

-- 字面量为 UTF-8，不依赖 utf8 库；若需动态生成可用 utf8.char(0x2654) 等
local PIECE_UNICODE = {
    K = "♔",
    Q = "♕",
    R = "♖",
    B = "♗",
    N = "♘",
    P = "♙",
    k = "♚",
    q = "♛",
    r = "♜",
    b = "♝",
    n = "♞",
    p = "♟",
}

local PIECE_ASCII = {
    K = "K",
    Q = "Q",
    R = "R",
    B = "B",
    N = "N",
    P = "P",
    k = "k",
    q = "q",
    r = "r",
    b = "b",
    n = "n",
    p = "p",
}

local function piece_char_disp(ch)
    if ch == "." then
        return ""
    end
    if USE_UNICODE_PIECES and PIECE_UNICODE[ch] then
        return PIECE_UNICODE[ch]
    end
    return PIECE_ASCII[ch] or ch
end

local function square_color(er, ec)
    return (er + ec) % 2 == 0 and LIGHT_SQ or DARK_SQ
end

local function refresh_cell_color(er, ec, extra)
    local dr = engine_to_display_rank(er)
    local dc = ec
    local L = cells[dr] and cells[dr][dc]
    if not L then
        return
    end
    local col = square_color(er, ec)
    if extra == "sel" then
        col = SEL_SQ
    elseif extra == "last" then
        col = LAST_SQ
    end
    L.square:set_color(col)
end

local last_move = nil

local function redraw_board()
    if not state then
        return
    end
    for dr = 1, 8 do
        for dc = 1, 8 do
            local er = display_to_engine_rank(dr)
            local ec = dc
            local ch = state.board[er][ec]
            local L = cells[dr] and cells[dr][dc]
            if L then
                if USE_GRAPHICS_PIECES and L.piece_root then
                    L.lab:set_text("")
                    if ch == "." then
                        piece_gfx.clear(L)
                        pcall(function()
                            L.piece_root:set_hidden(true)
                        end)
                    else
                        piece_gfx.draw(L, ch)
                        pcall(function()
                            L.piece_root:set_hidden(false)
                        end)
                    end
                elseif L.lab then
                    piece_gfx.clear(L)
                    pcall(function()
                        L.piece_root:set_hidden(true)
                    end)
                    L.lab:set_text(piece_char_disp(ch))
                    if is_white_piece(ch) then
                        L.lab:set_color(0xFFFEF5)
                    elseif is_black_piece(ch) then
                        L.lab:set_color(0x0D0D0D)
                    else
                        L.lab:set_color(0x555555)
                    end
                end
            end
            refresh_cell_color(er, ec, nil)
        end
    end
    if selected then
        refresh_cell_color(selected.er, selected.ec, "sel")
    end
    if last_move then
        refresh_cell_color(last_move[1], last_move[2], "last")
        refresh_cell_color(last_move[3], last_move[4], "last")
    end
end

local function set_status(t)
    if status_label then
        status_label:set_text(t or "")
    end
end

local function check_game_end()
    local moves = eng.legal_moves(state)
    if #moves > 0 then
        if eng.in_check(state) then
            set_status((state.white_move and "白方" or "黑方") .. " 被将军")
        else
            set_status(human_turn() and "该你走" or "电脑思考中…")
        end
        return false
    end
    game_over = true
    if eng.in_check(state) then
        set_status("将杀！ " .. (state.white_move and "黑方胜" or "白方胜"))
    else
        set_status("逼和")
    end
    return true
end

local function schedule_ai()
    if destroyed or not state or game_over then
        return
    end
    if human_turn() then
        return
    end
    set_status("电脑思考中…")
    sys.timerStart(function()
        if destroyed or not state or game_over then
            return
        end
        local m = eng.search_best(state, AI_DEPTH)
        if not m or destroyed then
            set_status("引擎无走法")
            return
        end
        eng.apply(state, m)
        chess_sound.play_drop()
        last_move = { m[1], m[2], m[3], m[4] }
        selected = nil
        redraw_board()
        if not check_game_end() and human_turn() then
            set_status("该你走")
        elseif not game_over then
            schedule_ai()
        end
    end, 40)
end

local function try_human_move(r1, c1, r2, c2)
    local moves = eng.legal_moves(state)
    for _, m in ipairs(moves) do
        if m[1] == r1 and m[2] == c1 and m[3] == r2 and m[4] == c2 then
            eng.apply(state, m)
            chess_sound.play_drop()
            last_move = { r1, c1, r2, c2 }
            selected = nil
            redraw_board()
            if check_game_end() then
                return
            end
            schedule_ai()
            return
        end
    end
end

local function on_cell_click(er, ec)
    if not state or game_over or not human_turn() then
        return
    end
    local p = state.board[er][ec]
    local mine = (human_white and is_white_piece(p)) or ((not human_white) and is_black_piece(p))

    if selected then
        if selected.er == er and selected.ec == ec then
            selected = nil
            redraw_board()
            return
        end
        -- 直接点另一枚己方棋子：改选，不必先取消
        if mine and p ~= "." then
            selected = { er = er, ec = ec }
            redraw_board()
            return
        end
        try_human_move(selected.er, selected.ec, er, ec)
        return
    end

    if mine and p ~= "." then
        selected = { er = er, ec = ec }
        redraw_board()
    end
end

local function new_game()
    state = eng.new_game()
    selected = nil
    last_move = nil
    game_over = false
    redraw_board()
    if check_game_end() then
        return
    end
    if not human_turn() then
        schedule_ai()
    else
        set_status("该你走（执" .. (human_white and "白" or "黑") .. "）")
    end
end

local function set_side_as_white(hw)
    human_white = hw
    new_game()
end

local function close_chess_window()
    if destroyed then
        return
    end
    local w = win_id
    if not w then
        return
    end
    exwin.close(w)
end

local function create_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x1B2838,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 8,
        w = SCREEN_W,
        h = 32,
        text = "Chess",
        font_size = 26,
        color = 0xECEFF1,
        align = airui.TEXT_ALIGN_CENTER,
    })

    status_label = airui.label({
        parent = main_container,
        x = 8,
        y = 44,
        w = SCREEN_W - 16,
        h = 28,
        text = "",
        font_size = 15,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_CENTER,
    })

    board_layer = airui.container({
        parent = main_container,
        x = BOARD_ORG_X,
        y = BOARD_ORG_Y,
        w = cell_w * 8,
        h = cell_w * 8,
        color = 0x2E3B4E,
    })

    cells = {}
    for dr = 1, 8 do
        cells[dr] = {}
        for dc = 1, 8 do
            local er = display_to_engine_rank(dr)
            local ec = dc
            local x = (dc - 1) * cell_w
            local y = (dr - 1) * cell_w
            local dr0, dc0 = dr, dc
            local function cell_tap()
                local er1 = display_to_engine_rank(dr0)
                on_cell_click(er1, dc0)
            end
            local sq = airui.container({
                parent = board_layer,
                x = x,
                y = y,
                w = cell_w,
                h = cell_w,
                color = square_color(er, ec),
                radius = 0,
            })
            local lab = airui.label({
                parent = sq,
                x = 0,
                y = 0,
                w = cell_w,
                h = cell_w,
                text = "",
                font_size = 38,
                color = 0x333333,
                align = airui.TEXT_ALIGN_CENTER,
            })
            local piece_root = airui.container({
                parent = sq,
                x = 0,
                y = 0,
                w = cell_w,
                h = cell_w,
            })
            -- 全格透明层叠在最上，统一接收点击（几何块不再挡事件）
            local click_pad = airui.container({
                parent = sq,
                x = 0,
                y = 0,
                w = cell_w,
                h = cell_w,
                color = 0x000000,
                color_opacity = 0,
                on_click = cell_tap,
            })
            cells[dr][dc] = {
                square = sq,
                lab = lab,
                piece_root = piece_root,
                click_pad = click_pad,
            }
        end
    end

    local bar = airui.container({
        parent = main_container,
        x = 0,
        y = BOARD_ORG_Y + cell_w * 8 + 16,
        w = SCREEN_W,
        h = 200,
        color = 0x1B2838,
    })

    airui.button({
        parent = bar,
        x = 12,
        y = 8,
        w = 140,
        h = 44,
        text = "我执白",
        font_size = 18,
        text_color = 0xF5F5F5,
        bg_color = 0x37474F,
        on_click = function()
            set_side_as_white(true)
        end,
    })

    airui.button({
        parent = bar,
        x = 164,
        y = 8,
        w = 140,
        h = 44,
        text = "我执黑",
        font_size = 18,
        text_color = 0xF5F5F5,
        bg_color = 0x37474F,
        on_click = function()
            set_side_as_white(false)
        end,
    })

    airui.button({
        parent = bar,
        x = 316,
        y = 8,
        w = 140,
        h = 44,
        text = "新局",
        font_size = 18,
        text_color = 0xF5F5F5,
        bg_color = 0x455A64,
        on_click = function()
            new_game()
        end,
    })

    local exit_btn = airui.button({
        parent = bar,
        x = 12,
        y = 60,
        w = 444,
        h = 44,
        text = "退出",
        font_size = 18,
        text_color = 0xEEEEEE,
        bg_color = 0x546E7A,
        on_click = close_chess_window,
    })
    if exit_btn and exit_btn.set_on_click then
        exit_btn:set_on_click(close_chess_window)
    end

    new_game()
end

local function on_create()
    destroyed = false
    create_ui()
end

local function on_destroy()
    destroyed = true
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    cells = {}
    status_label = nil
    board_layer = nil
    state = nil
    selected = nil
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    if win_id then
        return
    end
    if not ensure_airui() then
        log.error("chess_win", "airui init failed")
        return
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_CHESS_WIN", open_handler)

function chess_open()
    open_handler()
end
