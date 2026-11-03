--[[
@module  g_mines
@summary 益智游戏四：小扫雷（6x6 八颗雷，长按插旗）
@version 1.1
@date    2026.11.03
@usage
页面接口同 g2048，另有：
  o.onTap(x, y)      短按挖开
  o.onLongTap(x, y)  长按插旗 / 取消旗
@note
第一次挖开的位置永远不会是雷：布雷在首挖之后进行，并排除首挖格及其八邻格。
数字用 label 显示（6x6 共 36 个，只在状态变化时 set_text），
旗子和小雷用 shape 现画——hzfont 里没有合适的符号可用。
格子做成 62px、只放八颗雷，是给小朋友的手指和耐心留的余量。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

M.id = "g_mines"
M.name = "小扫雷"
M.en = "MINESWEEPER"
M.desc = "点开安全的格子 / 长按做记号"
M.tip = "点一下挖开，按住不放插旗做记号"
M.accent = T.c.green
M.record_key = "arcade_mines_sec"
M.rules = "36 个小格子里藏着 8 颗地雷。\n点开一格：上面的数字说它旁边八格里藏着几颗雷，空白的地方会自己连片打开。\n按住一格不放可以做上小旗子，表示这一格我猜有雷。\n把 28 个安全格全打开就赢啦，点到雷就结束这一局。"

M.rank_hint = "用时越短越靠前"

function M.format_record(v)
    if not v or v <= 0 then return "还没玩过" end
    return string.format("最快 %s", T.mmss(v))
end

-- 排行榜里的成绩文案（榜单页统一调 format_value）
function M.format_value(v)
    if not v or v <= 0 then return "--" end
    return T.mmss(v)
end

-- 6x6 而不是 8x8：格子做到 62px，小朋友的手指也点得准；
-- 8 颗雷、28 个安全格，一局两三分钟就能玩完
local N = 6
local MINES = 8
local CELL = 62
local GAP = 6
local BOARD = N * CELL + (N - 1) * GAP   -- 402
local SAFE_TOTAL = N * N - MINES

-- 数字配色：白底上用深一档的同色相，1~8 每种都不一样，孩子数完格子能对上号
local NUM_C = {
    [1] = 0x2F6FD0,
    [2] = 0x2E9E5B,
    [3] = 0xE03B3B,
    [4] = 0x7A4FD0,
    [5] = 0xD97A00,
    [6] = 0x0E8FA6,
    [7] = 0xC03A8E,
    [8] = 0x5A4630,
}

-- 大厅预览：一小块"挖了一半"的棋盘
function M.preview(P, x, y, w, h, t)
    local n = 5
    local gap = 3
    local cs = math.floor((math.min(w, h) - gap * (n - 1)) / n)
    local bw = cs * n + gap * (n - 1)
    local ox = x + math.floor((w - bw) / 2)
    local oy = y + math.floor((h - bw) / 2)
    local demo = {
        1, 1, 0, 0, 0,
        1, 1, 0, 2, 0,
        0, 0, 1, 0, 0,
        0, 2, 0, 1, 1,
        0, 0, 0, 1, 1,
    }
    for i = 1, n * n do
        local c = (i - 1) % n
        local r = math.floor((i - 1) / n)
        local px = ox + c * (cs + gap)
        local py = oy + r * (cs + gap)
        local v = demo[i]
        if v == 0 then
            -- 没挖开：浅蓝色的小方块按钮
            P:box(px, py, cs, cs, 0x9AD0EC, 255, 4)
            P:frame(px, py, cs, cs, 0xFFFFFF, 1, 210, 4)
        else
            -- 挖开：奶白色平面
            P:box(px, py, cs, cs, 0xFFFDF6, 255, 4)
            P:frame(px, py, cs, cs, T.paint.board_ln, 1, 160, 4)
            if v == 1 then
                local k = fx.breathe(t, i * 0.3)
                P:dot(px + math.floor(cs / 2), py + math.floor(cs / 2),
                    math.floor(cs * 0.22), T.c.green, math.floor(110 + 100 * k))
            else
                -- 旗子：深红小旗 + 白杆
                local fx0 = px + math.floor(cs * 0.42)
                P:line(fx0, py + math.floor(cs * 0.25),
                    fx0, py + math.floor(cs * 0.72), 0x5A4630, 2, 230, true)
                P:box(fx0, py + math.floor(cs * 0.22),
                    math.floor(cs * 0.32), math.floor(cs * 0.28), 0xE03B3B, 240, 1)
            end
        end
    end
end

function M.build(root, W, H, host)
    local o = {}

    local bx = math.floor((W - BOARD) / 2)
    local by = math.floor((H - BOARD) / 2)

    local mine, cnt, st, tx = {}, {}, {}, {}
    local lbs = {}
    local placed, done = false, false
    local boomIdx = 0            -- 踩中的那颗雷（0 = 没踩到）
    local revealed, flags = 0, 0
    local elapsed, boomT = 0, 0
    local best = host and host.best(M.record_key) or 0

    for i = 1, N * N do
        local c = (i - 1) % N
        local r = math.floor((i - 1) / N)
        -- 26 号字行高约 32px，62px 的格子里留 15px 上边距正好居中
        lbs[i] = airui.label({
            parent = root,
            x = bx + c * (CELL + GAP),
            y = by + r * (CELL + GAP) + 15,
            w = CELL, h = 32,
            text = "", font_size = T.f.title, color = T.c.txt,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    local function cell_xy(i)
        local c = (i - 1) % N
        local r = math.floor((i - 1) / N)
        return bx + c * (CELL + GAP), by + r * (CELL + GAP)
    end

    local function neighbors(i)
        local r = math.floor((i - 1) / N) + 1
        local c = (i - 1) % N + 1
        local list = {}
        for dr = -1, 1 do
            for dc = -1, 1 do
                if not (dr == 0 and dc == 0) then
                    local nr, nc = r + dr, c + dc
                    if nr >= 1 and nr <= N and nc >= 1 and nc <= N then
                        list[#list + 1] = (nr - 1) * N + nc
                    end
                end
            end
        end
        return list
    end

    --[[把 label 文字刷到最新（只在变化时写）
    已翻开且有数字 -> 数字；其余一律空串（旗子和小雷由 shape 画）]]
    local function refresh_labels()
        for i = 1, N * N do
            local s = ""
            if st[i] == 1 and cnt[i] > 0 and not mine[i] then
                s = tostring(cnt[i])
            end
            if tx[i] ~= s then
                tx[i] = s
                lbs[i]:set_text(s)
                if s ~= "" then
                    lbs[i]:set_color(NUM_C[cnt[i]] or T.c.txt)
                end
            end
        end
    end

    local function place_mines(safe)
        local banned = {}
        banned[safe] = true
        local ns = neighbors(safe)
        for j = 1, #ns do banned[ns[j]] = true end

        local pool = {}
        for i = 1, N * N do
            if not banned[i] then pool[#pool + 1] = i end
        end
        for k = 1, MINES do
            local j = math.random(k, #pool)
            pool[k], pool[j] = pool[j], pool[k]
            mine[pool[k]] = true
        end

        -- 预计算每格周围雷数，reveal 时不再重复遍历邻格
        for i = 1, N * N do
            local ns2 = neighbors(i)
            local n = 0
            for j = 1, #ns2 do
                if mine[ns2[j]] then n = n + 1 end
            end
            cnt[i] = n
        end
        placed = true
    end

    local function do_lose(hitIdx)
        done = true
        boomT = 0.0001
        boomIdx = hitIdx
        st[hitIdx] = 1
        for i = 1, N * N do
            if mine[i] and st[i] ~= 2 then st[i] = 1 end
        end
        refresh_labels()
        if host then
            host.lose("哎呀，点到地雷了",
                string.format("已经打开 %d 格，还剩 %d 格\n花了 %s\n\n换个地方再试一次吧！",
                    revealed, SAFE_TOTAL - revealed, T.mmss(elapsed)))
        end
    end

    local function do_win()
        done = true
        local sec = math.floor(elapsed)
        if sec < 1 then sec = 1 end
        if host then
            local rank = host.save_min(M.record_key, sec)
            best = host.best(M.record_key)
            host.win("全部排完啦，好厉害！",
                string.format("花了 %s\n%s", T.mmss(sec),
                    rank and string.format("上榜啦，第 %d 名！", rank)
                    or string.format("最快纪录 %s", T.mmss(best))))
        end
    end

    local function reveal(i)
        local stack = { i }
        local guard = 0
        while #stack > 0 and guard < 4096 do
            guard = guard + 1
            local k = table.remove(stack)
            if st[k] == 0 then
                st[k] = 1
                revealed = revealed + 1
                if cnt[k] == 0 then
                    local ns = neighbors(k)
                    for j = 1, #ns do
                        local n = ns[j]
                        if st[n] == 0 and not mine[n] then
                            stack[#stack + 1] = n
                        end
                    end
                end
            end
        end
    end

    local function new_game()
        mine, cnt, st, tx = {}, {}, {}, {}
        for i = 1, N * N do
            mine[i] = false
            cnt[i] = 0
            st[i] = 0
            -- 缓存初值给空串（而不是 nil）：省掉 64 次没必要的 set_text
            tx[i] = ""
        end
        placed, done = false, false
        boomIdx = 0
        revealed, flags = 0, 0
        elapsed, boomT = 0, 0
        best = host and host.best(M.record_key) or 0
        refresh_labels()
        log.info("g_mines", "新开一局")
    end

    local function hit(x, y)
        local c = math.floor((x - bx) / (CELL + GAP)) + 1
        local r = math.floor((y - by) / (CELL + GAP)) + 1
        if c < 1 or c > N or r < 1 or r > N then return nil end
        local lx = x - (bx + (c - 1) * (CELL + GAP))
        local ly = y - (by + (r - 1) * (CELL + GAP))
        if lx > CELL or ly > CELL then return nil end
        return (r - 1) * N + c
    end

    o.onTap = function(self, x, y)
        if done then return end
        local i = hit(x, y)
        if not i or st[i] ~= 0 then return end

        if not placed then
            place_mines(i)
            elapsed = 0
        end

        if mine[i] then
            do_lose(i)
            return
        end

        reveal(i)
        refresh_labels()
        if revealed >= SAFE_TOTAL then do_win() end
    end

    o.onLongTap = function(self, x, y)
        if done then return end
        local i = hit(x, y)
        if not i then return end
        if st[i] == 0 then
            if flags < MINES then
                st[i] = 2
                flags = flags + 1
            end
        elseif st[i] == 2 then
            st[i] = 0
            flags = flags - 1
        end
    end

    o.update = function(self, P, t, dt)
        if placed and not done then elapsed = elapsed + dt end
        if boomT > 0 then
            boomT = boomT + dt
            if boomT > 2 then boomT = 0 end
        end

        P:shadow(bx - 12, by - 12, BOARD + 24, BOARD + 24, 24, 52)
        P:box(bx - 12, by - 12, BOARD + 24, BOARD + 24, T.paint.board, 255, 24)
        P:frame(bx - 12, by - 12, BOARD + 24, BOARD + 24, T.paint.board_ln, 3, 255, 24)

        local k = fx.breathe(t, 0)
        for i = 1, N * N do
            local x, y = cell_xy(i)
            local s = st[i]

            if s == 0 then
                -- 没挖开：浅蓝色的小方块，带白色顶边，看着就想按下去
                P:box(x, y, CELL, CELL, 0x9AD0EC, 255, 6)
                P:box(x + 3, y + 2, CELL - 6, 3, 0xFFFFFF, 90, 2)
            elseif s == 2 then
                -- 插了旗：底色不变，画旗杆 + 红旗
                P:box(x, y, CELL, CELL, 0x9AD0EC, 255, 6)
                P:box(x + 3, y + 2, CELL - 6, 3, 0xFFFFFF, 90, 2)
                local poleX = x + math.floor(CELL * 0.40)
                local topY = y + math.floor(CELL * 0.24)
                local botY = y + math.floor(CELL * 0.74)
                P:line(poleX, topY, poleX, botY, 0x5A4630, 3, 240, true)
                P:box(poleX, topY - 2, math.floor(CELL * 0.34), math.floor(CELL * 0.28),
                    0xE03B3B, 245, 3)
                P:dot(poleX, botY, math.floor(CELL * 0.08), 0x5A4630, 220)
            else
                -- 挖开了：奶白平面，和没挖开的蓝色拉开层次
                P:box(x, y, CELL, CELL, 0xFFFDF6, 255, 6)
                P:frame(x, y, CELL, CELL, T.paint.board_ln, 1, 130, 6)
                if mine[i] then
                    local isHit = (i == boomIdx)
                    P:box(x, y, CELL, CELL, 0xFFE1E1, 255, 6)
                    -- 地雷：深红圆 + 八根短刺 + 白色高光点（尺寸随格子走）
                    local cx = x + math.floor(CELL / 2)
                    local cy = y + math.floor(CELL / 2)
                    local r0 = math.floor(CELL * 0.16)
                    local r1 = math.floor(CELL * 0.27)
                    P:dot(cx, cy, math.floor(CELL * 0.2), 0xE03B3B, 255)
                    for a = 0, 7 do
                        local ang = a * math.pi / 4
                        P:line(cx + math.cos(ang) * r0, cy + math.sin(ang) * r0,
                            cx + math.cos(ang) * r1, cy + math.sin(ang) * r1,
                            0xE03B3B, 3, 240, false)
                    end
                    P:dot(cx - 4, cy - 4, 4, 0xFFFFFF, 200)
                    if isHit and boomT > 0 and boomT < 1.2 then
                        local u = boomT / 1.2
                        P:frame(x - 3, y - 3, CELL + 6, CELL + 6, 0xE03B3B, 3,
                            math.floor(240 * (1 - u)), 8)
                    end
                end
            end
        end

        -- 未布雷时（还没挖第一下）在棋盘中央给一句"从任意格开始"的呼吸光圈
        if not placed then
            local cx = bx + math.floor(BOARD / 2)
            local cy = by + math.floor(BOARD / 2)
            P:ring(cx, cy, 26 + math.floor(6 * k), T.c.green, 2,
                math.floor(60 + 70 * k))
        end

        refresh_labels()
    end

    o.stats = function(self)
        local left = MINES - flags
        if left < 0 then left = 0 end
        return string.format("还剩 %d 颗雷  打开 %d 格", left, revealed),
            string.format("用时 %s / 最快 %s", T.mmss(elapsed),
                best > 0 and T.mmss(best) or "--:--")
    end

    -- 外壳切页时问一句"这一局结束了没"：结束了就把底部提示换成"按重玩再来一盘"
    o.is_over = function(self) return done end

    o.restart = function(self) new_game() end

    new_game()
    return o
end

return M
