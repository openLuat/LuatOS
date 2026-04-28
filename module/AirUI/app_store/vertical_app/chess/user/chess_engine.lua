--[[
  国际象棋引擎：走法生成、合法性、α-β 搜索（纯 Lua）
  坐标：r=1 白方底线（UI 底部），r=8 黑方底线；c=1..8 对应 a..h
]]

local M = {}

local INF = 300000

local PVAL = { P = 100, N = 320, B = 330, R = 500, Q = 900, K = 20000 }

local function pc_val(ch)
    local u = ch:upper()
    return PVAL[u] or 0
end

local function is_white_piece(ch)
    return ch >= "A" and ch <= "Z" and ch ~= "."
end

local function is_black_piece(ch)
    return ch >= "a" and ch <= "z"
end

local function piece_side_white(ch)
    if is_white_piece(ch) then
        return true
    end
    if is_black_piece(ch) then
        return false
    end
    return nil
end

function M.new_game()
    local b = {}
    for r = 1, 8 do
        b[r] = {}
        for c = 1, 8 do
            b[r][c] = "."
        end
    end
    local back_w = { "R", "N", "B", "Q", "K", "B", "N", "R" }
    local back_b = { "r", "n", "b", "q", "k", "b", "n", "r" }
    for c = 1, 8 do
        b[1][c] = back_w[c]
        b[2][c] = "P"
        b[7][c] = "p"
        b[8][c] = back_b[c]
    end
    return {
        board = b,
        white_move = true,
        ep = nil,
        castle = { WK = true, WQ = true, BK = true, BQ = true },
    }
end

local ORTH = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIAG = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local KNIGHT = { { 2, 1 }, { 2, -1 }, { -2, 1 }, { -2, -1 }, { 1, 2 }, { 1, -2 }, { -1, 2 }, { -1, -2 } }

local function find_king(board, white)
    local want = white and "K" or "k"
    for r = 1, 8 do
        for c = 1, 8 do
            if board[r][c] == want then
                return r, c
            end
        end
    end
    return nil
end

-- 方格 (tr,tc) 是否被白方攻击
local function sq_attacked_by_white(s, tr, tc)
    local b = s.board
    -- 白兵（向 rank 增大方向吃）
    if tr >= 2 then
        if tc > 1 and b[tr - 1][tc - 1] == "P" then
            return true
        end
        if tc < 8 and b[tr - 1][tc + 1] == "P" then
            return true
        end
    end
    -- 马
    for _, d in ipairs(KNIGHT) do
        local r, c = tr + d[1], tc + d[2]
        if r >= 1 and r <= 8 and c >= 1 and c <= 8 and b[r][c] == "N" then
            return true
        end
    end
    -- 王（邻格）
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local r, c = tr + dr, tc + dc
                if r >= 1 and r <= 8 and c >= 1 and c <= 8 and b[r][c] == "K" then
                    return true
                end
            end
        end
    end
    -- 直线 / 斜线（车象后）
    for _, d in ipairs(ORTH) do
        local r, c = tr + d[1], tc + d[2]
        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            local ch = b[r][c]
            if ch ~= "." then
                if ch == "R" or ch == "Q" then
                    return true
                end
                break
            end
            r, c = r + d[1], c + d[2]
        end
    end
    for _, d in ipairs(DIAG) do
        local r, c = tr + d[1], tc + d[2]
        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            local ch = b[r][c]
            if ch ~= "." then
                if ch == "B" or ch == "Q" then
                    return true
                end
                break
            end
            r, c = r + d[1], c + d[2]
        end
    end
    return false
end

local function sq_attacked_by_black(s, tr, tc)
    local b = s.board
    if tr <= 7 then
        if tc > 1 and b[tr + 1][tc - 1] == "p" then
            return true
        end
        if tc < 8 and b[tr + 1][tc + 1] == "p" then
            return true
        end
    end
    for _, d in ipairs(KNIGHT) do
        local r, c = tr + d[1], tc + d[2]
        if r >= 1 and r <= 8 and c >= 1 and c <= 8 and b[r][c] == "n" then
            return true
        end
    end
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local r, c = tr + dr, tc + dc
                if r >= 1 and r <= 8 and c >= 1 and c <= 8 and b[r][c] == "k" then
                    return true
                end
            end
        end
    end
    for _, d in ipairs(ORTH) do
        local r, c = tr + d[1], tc + d[2]
        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            local ch = b[r][c]
            if ch ~= "." then
                if ch == "r" or ch == "q" then
                    return true
                end
                break
            end
            r, c = r + d[1], c + d[2]
        end
    end
    for _, d in ipairs(DIAG) do
        local r, c = tr + d[1], tc + d[2]
        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            local ch = b[r][c]
            if ch ~= "." then
                if ch == "b" or ch == "q" then
                    return true
                end
                break
            end
            r, c = r + d[1], c + d[2]
        end
    end
    return false
end

local function in_check(s, white_king)
    local kr, kc = find_king(s.board, white_king)
    if not kr then
        return true
    end
    if white_king then
        return sq_attacked_by_black(s, kr, kc)
    end
    return sq_attacked_by_white(s, kr, kc)
end

local function add_slide(moves, b, r, c, dirs, white_turn, piece_chars)
    for _, d in ipairs(dirs) do
        local nr, nc = r + d[1], c + d[2]
        while nr >= 1 and nr <= 8 and nc >= 1 and nc <= 8 do
            local t = b[nr][nc]
            if t == "." then
                moves[#moves + 1] = { r, c, nr, nc }
            else
                if white_turn and is_black_piece(t) or (not white_turn) and is_white_piece(t) then
                    moves[#moves + 1] = { r, c, nr, nc }
                end
                break
            end
            nr, nc = nr + d[1], nc + d[2]
        end
    end
end

local function add_knight(moves, b, r, c, white_turn)
    for _, d in ipairs(KNIGHT) do
        local nr, nc = r + d[1], c + d[2]
        if nr >= 1 and nr <= 8 and nc >= 1 and nc <= 8 then
            local t = b[nr][nc]
            if t == "." then
                moves[#moves + 1] = { r, c, nr, nc }
            elseif white_turn and is_black_piece(t) or (not white_turn) and is_white_piece(t) then
                moves[#moves + 1] = { r, c, nr, nc }
            end
        end
    end
end

local function add_king(moves, b, r, c, white_turn)
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local nr, nc = r + dr, c + dc
                if nr >= 1 and nr <= 8 and nc >= 1 and nc <= 8 then
                    local t = b[nr][nc]
                    if t == "." then
                        moves[#moves + 1] = { r, c, nr, nc }
                    elseif white_turn and is_black_piece(t) or (not white_turn) and is_white_piece(t) then
                        moves[#moves + 1] = { r, c, nr, nc }
                    end
                end
            end
        end
    end
end

-- 伪合法走法（不含王车易位）
local function gen_pseudo(s)
    local moves = {}
    local b = s.board
    local wt = s.white_move
    for r = 1, 8 do
        for c = 1, 8 do
            local p = b[r][c]
            if p == "." then
                -- continue
            elseif wt and is_white_piece(p) or (not wt) and is_black_piece(p) then
                local uw = p:upper()
                if uw == "P" then
                    if wt then
                        local nr = r + 1
                        if nr <= 8 and b[nr][c] == "." then
                            if nr == 8 then
                                moves[#moves + 1] = { r, c, nr, c, promo = "Q" }
                            else
                                moves[#moves + 1] = { r, c, nr, c }
                                if r == 2 and b[3][c] == "." and b[4][c] == "." then
                                    moves[#moves + 1] = { r, c, 4, c }
                                end
                            end
                        end
                        for dc = -1, 1, 2 do
                            local nc = c + dc
                            if nc >= 1 and nc <= 8 and nr <= 8 then
                                local nt = b[nr][nc]
                                if is_black_piece(nt) then
                                    if nr == 8 then
                                        moves[#moves + 1] = { r, c, nr, nc, promo = "Q" }
                                    else
                                        moves[#moves + 1] = { r, c, nr, nc }
                                    end
                                end
                            end
                        end
                        if s.ep then
                            local er, ec = s.ep.r, s.ep.c
                            if r == er and math.abs(c - ec) == 1 and b[er][ec] == "p" then
                                moves[#moves + 1] = { r, c, er + 1, ec, ep = true }
                            end
                        end
                    else
                        local nr = r - 1
                        if nr >= 1 and b[nr][c] == "." then
                            if nr == 1 then
                                moves[#moves + 1] = { r, c, nr, c, promo = "q" }
                            else
                                moves[#moves + 1] = { r, c, nr, c }
                                if r == 7 and b[6][c] == "." and b[5][c] == "." then
                                    moves[#moves + 1] = { r, c, 5, c }
                                end
                            end
                        end
                        for dc = -1, 1, 2 do
                            local nc = c + dc
                            if nc >= 1 and nc <= 8 and nr >= 1 then
                                local nt = b[nr][nc]
                                if is_white_piece(nt) then
                                    if nr == 1 then
                                        moves[#moves + 1] = { r, c, nr, nc, promo = "q" }
                                    else
                                        moves[#moves + 1] = { r, c, nr, nc }
                                    end
                                end
                            end
                        end
                        if s.ep then
                            local er, ec = s.ep.r, s.ep.c
                            if r == er and math.abs(c - ec) == 1 and b[er][ec] == "P" then
                                moves[#moves + 1] = { r, c, er - 1, ec, ep = true }
                            end
                        end
                    end
                elseif uw == "N" then
                    add_knight(moves, b, r, c, wt)
                elseif uw == "B" then
                    add_slide(moves, b, r, c, DIAG, wt, nil)
                elseif uw == "R" then
                    add_slide(moves, b, r, c, ORTH, wt, nil)
                elseif uw == "Q" then
                    add_slide(moves, b, r, c, ORTH, wt, nil)
                    add_slide(moves, b, r, c, DIAG, wt, nil)
                elseif uw == "K" then
                    add_king(moves, b, r, c, wt)
                end
            end
        end
    end
    return moves
end

local function clear_ep_after_non_pawn_double(s, from_r, from_c, to_r, to_c, moved)
    s.ep = nil
    local uw = moved:upper()
    if uw == "P" and math.abs(to_r - from_r) == 2 then
        s.ep = { r = to_r, c = to_c }
    end
end

local function apply_move(s, m)
    local b = s.board
    local r1, c1, r2, c2 = m[1], m[2], m[3], m[4]
    local moved = b[r1][c1]
    local captured = b[r2][c2]
    local undo = {
        r1 = r1,
        c1 = c1,
        r2 = r2,
        c2 = c2,
        moved = moved,
        captured = captured,
        ep_prev = s.ep and { r = s.ep.r, c = s.ep.c } or nil,
        castle_prev = {
            WK = s.castle.WK,
            WQ = s.castle.WQ,
            BK = s.castle.BK,
            BQ = s.castle.BQ,
        },
        white_move_prev = s.white_move,
        promo = m.promo,
        ep_capture = m.ep,
    }

    if m.ep then
        captured = b[r1][c2]
        b[r2][c2] = moved
        b[r1][c1] = "."
        b[r1][c2] = "."
        undo.ep_pawn_r = r1
        undo.ep_pawn_c = c2
        undo.captured = captured
    else
        b[r2][c2] = moved
        b[r1][c1] = "."
        if m.castle then
            if m.castle == "WK" then
                b[1][8] = "."
                b[1][6] = "R"
            elseif m.castle == "WQ" then
                b[1][1] = "."
                b[1][4] = "R"
            elseif m.castle == "BK" then
                b[8][8] = "."
                b[8][6] = "r"
            elseif m.castle == "BQ" then
                b[8][1] = "."
                b[8][4] = "r"
            end
        end
    end

    if m.promo then
        b[r2][c2] = m.promo
    end

    -- 易位权
    if moved == "K" then
        s.castle.WK, s.castle.WQ = false, false
    elseif moved == "k" then
        s.castle.BK, s.castle.BQ = false, false
    elseif moved == "R" then
        if r1 == 1 and c1 == 1 then
            s.castle.WQ = false
        end
        if r1 == 1 and c1 == 8 then
            s.castle.WK = false
        end
    elseif moved == "r" then
        if r1 == 8 and c1 == 1 then
            s.castle.BQ = false
        end
        if r1 == 8 and c1 == 8 then
            s.castle.BK = false
        end
    end
    if captured == "r" and r2 == 8 and c2 == 1 then
        s.castle.BQ = false
    end
    if captured == "r" and r2 == 8 and c2 == 8 then
        s.castle.BK = false
    end
    if captured == "R" and r2 == 1 and c2 == 1 then
        s.castle.WQ = false
    end
    if captured == "R" and r2 == 1 and c2 == 8 then
        s.castle.WK = false
    end

    clear_ep_after_non_pawn_double(s, r1, c1, r2, c2, moved)
    s.white_move = not s.white_move
    return undo
end

local function unapply_move(s, undo)
    local b = s.board
    local r1, c1, r2, c2 = undo.r1, undo.c1, undo.r2, undo.c2
    s.white_move = undo.white_move_prev
    s.ep = undo.ep_prev
    s.castle.WK = undo.castle_prev.WK
    s.castle.WQ = undo.castle_prev.WQ
    s.castle.BK = undo.castle_prev.BK
    s.castle.BQ = undo.castle_prev.BQ

    if undo.ep_capture then
        b[r1][c1] = undo.moved
        b[r2][c2] = "."
        b[undo.ep_pawn_r][undo.ep_pawn_c] = undo.captured
    else
        b[r1][c1] = undo.moved
        b[r2][c2] = undo.captured
        if undo.castle_m then
            if undo.castle_m == "WK" then
                b[1][8] = "R"
                b[1][6] = "."
            elseif undo.castle_m == "WQ" then
                b[1][1] = "R"
                b[1][4] = "."
            elseif undo.castle_m == "BK" then
                b[8][8] = "r"
                b[8][6] = "."
            elseif undo.castle_m == "BQ" then
                b[8][1] = "r"
                b[8][4] = "."
            end
        end
    end
end

local function gen_castle(s)
    local out = {}
    local b = s.board
    if in_check(s, s.white_move) then
        return out
    end
    if s.white_move and b[1][5] == "K" then
        if s.castle.WK and b[1][8] == "R" and b[1][6] == "." and b[1][7] == "." then
            if not sq_attacked_by_black(s, 1, 5) and not sq_attacked_by_black(s, 1, 6) and not sq_attacked_by_black(s, 1, 7) then
                out[#out + 1] = { 1, 5, 1, 7, castle = "WK" }
            end
        end
        if s.castle.WQ and b[1][1] == "R" and b[1][2] == "." and b[1][3] == "." and b[1][4] == "." then
            if not sq_attacked_by_black(s, 1, 5) and not sq_attacked_by_black(s, 1, 4) and not sq_attacked_by_black(s, 1, 3) then
                out[#out + 1] = { 1, 5, 1, 3, castle = "WQ" }
            end
        end
    elseif (not s.white_move) and b[8][5] == "k" then
        if s.castle.BK and b[8][8] == "r" and b[8][6] == "." and b[8][7] == "." then
            if not sq_attacked_by_white(s, 8, 5) and not sq_attacked_by_white(s, 8, 6) and not sq_attacked_by_white(s, 8, 7) then
                out[#out + 1] = { 8, 5, 8, 7, castle = "BK" }
            end
        end
        if s.castle.BQ and b[8][1] == "r" and b[8][2] == "." and b[8][3] == "." and b[8][4] == "." then
            if not sq_attacked_by_white(s, 8, 5) and not sq_attacked_by_white(s, 8, 4) and not sq_attacked_by_white(s, 8, 3) then
                out[#out + 1] = { 8, 5, 8, 3, castle = "BQ" }
            end
        end
    end
    return out
end

-- 修复 apply 中易位：需在 b[r2][c2]=K 之后移动车；上面 apply_move 已处理车
-- 易位走法需设置 undo.castle_m
local function apply_move_fixed(s, m)
    local undo = apply_move(s, m)
    if m.castle then
        undo.castle_m = m.castle
    end
    return undo
end

function M.legal_moves(s)
    local pseudo = gen_pseudo(s)
    for _, cm in ipairs(gen_castle(s)) do
        pseudo[#pseudo + 1] = cm
    end
    local legal = {}
    for _, m in ipairs(pseudo) do
        local mover_white = s.white_move
        local u = apply_move_fixed(s, m)
        local ok = not in_check(s, mover_white)
        unapply_move(s, u)
        if ok then
            legal[#legal + 1] = m
        end
    end
    return legal
end

function M.apply(s, m)
    return apply_move_fixed(s, m)
end

function M.unapply(s, u)
    unapply_move(s, u)
end

function M.in_check(s)
    return in_check(s, s.white_move)
end

function M.eval_white_pov(s)
    local sc = 0
    local b = s.board
    for r = 1, 8 do
        for c = 1, 8 do
            local ch = b[r][c]
            if ch == "." then
                -- skip
            elseif is_white_piece(ch) then
                sc = sc + pc_val(ch)
                sc = sc + (r - 4) * 2
                sc = sc + (4 - math.abs(c - 4.5)) * 1
            elseif is_black_piece(ch) then
                sc = sc - pc_val(ch:upper())
                sc = sc - (8 - r - 3) * 2
                sc = sc - (4 - math.abs(c - 4.5)) * 1
            end
        end
    end
    return sc
end

local function move_score_capture(m, s)
    local victim = s.board[m[3]][m[4]]
    if m.ep then
        victim = s.white_move and "p" or "P"
    end
    if victim == "." then
        return 0
    end
    return pc_val(victim:upper())
end

local function sort_moves(moves, s)
    table.sort(moves, function(a, b)
        return move_score_capture(a, s) > move_score_capture(b, s)
    end)
end

function M.search_best(s, max_depth)
    max_depth = max_depth or 3
    local moves = M.legal_moves(s)
    if #moves == 0 then
        return nil
    end
    sort_moves(moves, s)
    local best_m = moves[1]
    local best_val

    local function negamax(depth, alpha, beta)
        local moves2 = M.legal_moves(s)
        if #moves2 == 0 then
            if M.in_check(s) then
                return -INF
            end
            return 0
        end
        if depth == 0 then
            if s.white_move then
                return M.eval_white_pov(s)
            end
            return -M.eval_white_pov(s)
        end
        sort_moves(moves2, s)
        local best = -INF
        for _, m in ipairs(moves2) do
            local u = apply_move_fixed(s, m)
            local sc = -negamax(depth - 1, -beta, -alpha)
            unapply_move(s, u)
            if sc > best then
                best = sc
            end
            if best > alpha then
                alpha = best
            end
            if alpha >= beta then
                break
            end
        end
        return best
    end

    best_val = -INF
    for _, m in ipairs(moves) do
        local u = apply_move_fixed(s, m)
        local sc = -negamax(max_depth - 1, -INF, INF)
        unapply_move(s, u)
        if sc > best_val then
            best_val = sc
            best_m = m
        end
    end
    return best_m
end

return M
