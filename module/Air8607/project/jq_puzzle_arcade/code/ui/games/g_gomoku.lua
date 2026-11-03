--[[
@module  g_gomoku
@summary 益智游戏七：五子棋（11x11，人机 / 双人可切换，含悔棋）
@version 1.0
@date    2026.11.03
@usage
页面接口同其它游戏，另有：
  o.onTap(x, y)   落子 / 切换模式 / 悔棋
@note
为什么是 11x11：格子在 36px 左右，是"孩子手指点得中"的下限；
棋盘小一点，五连也更容易凑成，赢面大才愿意接着玩。

AI 只做单层评分，不做极小化极大：
11x11 全盘搜索放不进 20ms 的帧预算，而单层攻守评分 + 一点随机
已经能做到"会堵你的三连，但偶尔看漏"——这正是给孩子当对手需要的强度。
计算只在轮到电脑时做一次（约 1ms），不占每帧。

思考停顿走 update 里的计时器（aiTimer），不 sleep：
主循环还要画棋盘、响应悔棋，阻塞会把整个页面卡住。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

M.id = "g_gomoku"
M.name = "五子棋"
M.en = "GOMOKU"
M.desc = "五颗棋子连成线就赢 / 可人机可双人"
M.tip = "点交叉点落子，五颗连成一条线就赢"
M.accent = T.c.teal
M.record_key = "arcade_gomoku_moves"
M.rank_hint = "赢棋用的手数越少越靠前"
M.rules = "黑棋先下，点棋盘的交叉点就能落子。\n横着、竖着、斜着，只要自己的五颗棋子连成一条线就赢。\n人机模式下你下黑棋，电脑会等一会儿再落子。\n下错了可以按悔一步，人机模式会连电脑那一步一起撤掉。"

function M.format_value(v)
    if not v or v <= 0 then return "--" end
    return string.format("%d 手", v)
end

function M.format_record(v)
    if not v or v <= 0 then return "还没玩过" end
    return string.format("最快 %d 手赢", v)
end

-- ==================== 棋盘几何 ====================
local N = 11
local CELL = 36
local PAD = 18
local SPAN = (N - 1) * CELL          -- 360，10 个格距
local BOARD = SPAN + PAD * 2         -- 396
local STONE = 15                     -- 棋子半径
local BX, BY = 12, 25                -- 棋盘外框左上角（446 - 396 = 50，上下各 25）
local GX, GY = BX + PAD, BY + PAD    -- 第一条线的位置

-- 右侧面板（x 从棋盘右边再让 16px 开始）
local PX = BX + BOARD + 16
local PW = 994 - PX                  -- 424 起，宽 570

-- 四个方向：横 / 竖 / 右下 / 左下
local DIRS = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }

-- 棋力评分：按"这条线上能连到几颗"分档，两端全被封住再打折
-- 不做活四/冲四的细致区分：给孩子当对手，能挡住三连、会贪四连就够了，
-- 规则越简单越好调，也不容易出现"AI 忽然下出怪棋"的情况
local RANK_SCORE = { 0, 10, 100, 1000, 10000, 100000 }   -- 下标 = 连子数 1..5
local BLOCKED_RATE = 0.12                                 -- 两端都堵住时的残值

local function idx_of(r, c)
    return (r - 1) * N + c
end

local function inboard(r, c)
    return r >= 1 and r <= N and c >= 1 and c <= N
end

-- 大厅预览：迷你棋盘 + 一条五连
function M.preview(P, x, y, w, h, t)
    local n = 5
    local cell = math.floor((math.min(w, h) - 8) / (n - 1))
    if cell < 8 then cell = 8 end
    local span = cell * (n - 1)
    local ox = x + math.floor((w - span) / 2)
    local oy = y + math.floor((h - span) / 2)

    -- 棋盘底
    P:box(ox - 6, oy - 6, span + 12, span + 12, T.paint.board, 255, 8)
    for i = 0, n - 1 do
        P:line(ox + i * cell, oy, ox + i * cell, oy + span, T.paint.board_ln, 1, 190, false)
        P:line(ox, oy + i * cell, ox + span, oy + i * cell, T.paint.board_ln, 1, 190, false)
    end
    -- 一条斜着的五连（黑子）+ 两颗白子
    local k = fx.breathe(t, 0)
    for i = 0, 4 do
        local cx = ox + i * cell
        local cy = oy + i * cell
        local isLast = (i == 4)
        if isLast then
            P:ring(cx, cy, math.floor(cell * 0.42) + 2, T.c.gold, 2,
                math.floor(120 + 110 * k))
        end
        P:dot(cx, cy, math.floor(cell * 0.36), 0x33302E, 255)
    end
    P:dot(ox + 3 * cell, oy, math.floor(cell * 0.36), 0xFFFFFF, 255)
    P:ring(ox + 3 * cell, oy, math.floor(cell * 0.36), 0xC9B99F, 1, 220)
    P:dot(ox, oy + 4 * cell, math.floor(cell * 0.36), 0xFFFFFF, 255)
    P:ring(ox, oy + 4 * cell, math.floor(cell * 0.36), 0xC9B99F, 1, 220)
end

local function chip_label(parent, x, y, w, h, text, fs)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = fs, color = T.c.dim,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

function M.build(root, W, H, host)
    local o = {}

    local g = {}              -- 0 空 / 1 黑 / 2 白
    local turn = 1
    local mode = "ai"         -- "ai" 人机 / "pvp" 双人
    local over = false
    local winner = 0          -- 0 未分 / 1 黑胜 / 2 白胜 / 3 平局
    local winLine = {}        -- 连成五子的格子
    local history = {}        -- 落子顺序（悔棋用）
    local lastIdx = 0
    local moves = 0
    local aiTimer = 0         -- > 0 表示电脑正在"思考"
    local elapsed = 0
    local dropT = {}          -- 落子脉冲计时
    local best = host and host.best(M.record_key) or 0

    -- AI 缓冲：候选点的下标 + 去重标记，一次建好反复用，避免每次思考都新建表
    local candIdx, candMark = {}, {}

    -- ==================== label ====================
    local lbTurn = airui.label({
        parent = root, x = PX + 96, y = 44, w = PW - 120, h = 40,
        text = "", font_size = T.f.title, color = T.c.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local lbTurnSub = airui.label({
        parent = root, x = PX + 96, y = 84, w = PW - 120, h = 20,
        text = "", font_size = T.f.sub, color = T.c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local lbMode = {
        chip_label(root, PX, 151, 270, 36, "人机对战", T.f.text),
        chip_label(root, PX + 300, 151, 270, 36, "两人对战", T.f.text),
    }
    local lbUndo = chip_label(root, PX, 231, PW, 36, "悔一步", T.f.text)
    local lbInfo = airui.label({
        parent = root, x = PX, y = 292, w = PW, h = 120,
        text = "", font_size = T.f.sub, color = T.c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- ==================== 规则与判胜 ====================
    local function can_undo()
        if over or aiTimer > 0 or #history == 0 then return false end
        return true
    end

    local function check_win(i)
        local color = g[i]
        local r = math.floor((i - 1) / N) + 1
        local c = (i - 1) % N + 1

        for d = 1, #DIRS do
            local dr, dc = DIRS[d][1], DIRS[d][2]
            local cells = { i }
            for s = 1, 4 do
                local nr, nc = r + dr * s, c + dc * s
                if inboard(nr, nc) and g[idx_of(nr, nc)] == color then
                    table.insert(cells, idx_of(nr, nc))
                else
                    break
                end
            end
            for s = 1, 4 do
                local nr, nc = r - dr * s, c - dc * s
                if inboard(nr, nc) and g[idx_of(nr, nc)] == color then
                    table.insert(cells, 1, idx_of(nr, nc))
                else
                    break
                end
            end
            if #cells >= 5 then
                -- 只取 5 颗用来高亮（六连以上也只画 5 个金环，画面不乱）
                while #cells > 5 do table.remove(cells) end
                return true, cells
            end
        end
        return false, nil
    end

    local function report_end()
        if winner == 1 then
            -- 黑棋赢才交成绩：人机模式玩家执黑，双人模式两边都是人下的
            local rank = host.save_min(M.record_key, moves)
            best = host.best(M.record_key)
            local tail = rank and string.format("上榜啦，第 %d 名！", rank)
                or string.format("最快纪录 %d 手", best)
            if mode == "ai" then
                host.win("你赢啦！", string.format("你用了 %d 手\n%s", moves, tail))
            else
                host.win("黑棋赢啦！", string.format("黑棋用了 %d 手\n%s", moves, tail))
            end
        elseif winner == 2 then
            if mode == "ai" then
                host.lose("电脑赢了这一盘",
                    string.format("你下了 %d 手\n别灰心，再试一次就能赢！", moves))
            else
                local rank = host.save_min(M.record_key, moves)
                best = host.best(M.record_key)
                host.win("白棋赢啦！",
                    string.format("白棋用了 %d 手\n%s", moves,
                        rank and string.format("上榜啦，第 %d 名！", rank)
                        or string.format("最快纪录 %d 手", best)))
            end
        else
            host.lose("棋盘下满了", "这一盘是平局，谁也没连成五颗\n你们都很厉害！")
        end
    end

    local function do_place(i, color)
        g[i] = color
        moves = moves + 1
        history[#history + 1] = i
        lastIdx = i
        dropT[i] = 0.0001

        local won, line = check_win(i)
        if won then
            over = true
            winner = color
            winLine = line
            report_end()
            return
        end
        if moves >= N * N then
            over = true
            winner = 3
            report_end()
            return
        end

        turn = (color == 1) and 2 or 1
        if mode == "ai" and turn == 2 then
            -- 电脑"想一会儿"再落子：固定 0.55 秒会显得机械，0.4~0.7 更像真人
            aiTimer = 0.4 + math.random() * 0.3
        end
    end

    -- ==================== AI（单层攻守评分）====================
    --[[以 i 为中心、沿 (dr,dc) 方向落子后能连到几颗、两端是否还活着
    不建闭包：这个函数每次 AI 落子会被调 (候选点数 x 4) 次，
    在里面写 local function walk 等于每次都新建一个函数对象。
    ]]
    local function dir_score(i, dr, dc, who)
        local r = math.floor((i - 1) / N) + 1
        local c = (i - 1) % N + 1
        local cnt = 1
        local open = 0

        for sign = 1, -1, -2 do
            for s = 1, 4 do
                local nr, nc = r + dr * s * sign, c + dc * s * sign
                if not inboard(nr, nc) then break end   -- 棋盘边算堵死，不算活口
                local v = g[idx_of(nr, nc)]
                if v == who then
                    cnt = cnt + 1
                else
                    if v == 0 then open = open + 1 end
                    break
                end
            end
        end

        if cnt >= 5 then return RANK_SCORE[5] end
        local s = RANK_SCORE[cnt] or 0
        if open == 0 then s = math.floor(s * BLOCKED_RATE) end
        return s
    end

    local function point_score(i, who)
        local total = 0
        for d = 1, 4 do
            total = total + dir_score(i, DIRS[d][1], DIRS[d][2], who)
        end
        return total
    end

    local function ai_choose()
        -- 候选点：已有棋子周围 2 格内的空位；空盘就下天元
        if moves == 0 then return idx_of(6, 6) end

        local n = 0
        for k = 1, #history do
            local h = history[k]
            local r = math.floor((h - 1) / N) + 1
            local c = (h - 1) % N + 1
            for dr = -2, 2 do
                for dc = -2, 2 do
                    local nr, nc = r + dr, c + dc
                    if inboard(nr, nc) then
                        local ii = idx_of(nr, nc)
                        if g[ii] == 0 and not candMark[ii] then
                            candMark[ii] = true
                            n = n + 1
                            candIdx[n] = ii
                        end
                    end
                end
            end
        end

        local chosen
        if n == 0 then
            -- 理论上走不到：还有空位就一定有棋子邻域。兜底找第一个空位
            for i = 1, N * N do
                if g[i] == 0 then chosen = i break end
            end
        else
            local best1, best2, bestIdx, bestIdx2 = -1, -1, nil, nil
            for k = 1, n do
                local i = candIdx[k]
                -- 自己下这里的收益 + 对手下这里的收益（拦断价值略打折）
                local attack = point_score(i, 2)
                local block = point_score(i, 1)
                local sc = attack + math.floor(block * 0.9)
                if sc > best1 then
                    best2, bestIdx2 = best1, bestIdx
                    best1, bestIdx = sc, i
                elseif sc > best2 then
                    best2, bestIdx2 = sc, i
                end
            end
            chosen = bestIdx
            -- 20% 概率故意选次优点：会漏一两步，孩子才有赢的机会
            if bestIdx2 and math.random() < 0.2 then chosen = bestIdx2 end
        end

        -- 清标记只清这次碰过的点，不整表遍历（121 格不算大，能省则省）
        for k = 1, n do candMark[candIdx[k]] = nil end
        return chosen
    end

    local function ai_move()
        if over then return end
        local i = ai_choose()
        if not i then return end
        do_place(i, 2)
    end

    -- ==================== 局面控制 ====================
    local function new_game()
        for i = 1, N * N do
            g[i] = 0
            dropT[i] = 0
        end
        turn, over, winner = 1, false, 0
        winLine = {}
        history = {}
        lastIdx = 0
        moves = 0
        aiTimer = 0
        elapsed = 0
        best = host and host.best(M.record_key) or 0
        log.info("g_gomoku", "新开一局", mode)
    end

    local function undo()
        if not can_undo() then return end
        local steps = (mode == "ai" and #history >= 2) and 2 or 1
        for _ = 1, steps do
            local i = table.remove(history)
            if i then
                g[i] = 0
                dropT[i] = 0
                moves = moves - 1
            end
        end
        -- 黑先下，所以偶数手之后轮到黑
        turn = (moves % 2 == 0) and 1 or 2
        lastIdx = history[#history] or 0
        aiTimer = 0
        log.info("g_gomoku", "悔棋", steps, "步，当前手数", moves)
    end

    local function set_mode(m)
        if mode == m then return end
        mode = m
        new_game()
        log.info("g_gomoku", "切换模式", m)
    end

    -- ==================== 点按 ====================
    local function hit_board(x, y)
        local c = math.floor((x - GX) / CELL + 0.5) + 1
        local r = math.floor((y - GY) / CELL + 0.5) + 1
        if not inboard(r, c) then return nil end
        local px = GX + (c - 1) * CELL
        local py = GY + (r - 1) * CELL
        local dx, dy = x - px, y - py
        -- 比半格稍宽一点：孩子点不中十字线中心也能落子
        if dx * dx + dy * dy > (CELL * 0.62) * (CELL * 0.62) then return nil end
        return idx_of(r, c)
    end

    o.onTap = function(self, x, y)
        -- 模式切换
        if T.hit(x, y, PX, 137, 270, 64) then
            set_mode("ai")
            return
        end
        if T.hit(x, y, PX + 300, 137, 270, 64) then
            set_mode("pvp")
            return
        end
        -- 悔棋
        if T.hit(x, y, PX, 217, PW, 64) then
            undo()
            return
        end
        -- 落子
        if over or aiTimer > 0 then return end
        if mode == "ai" and turn ~= 1 then return end
        local i = hit_board(x, y)
        if not i or g[i] ~= 0 then return end
        do_place(i, turn)
    end

    -- ==================== 每帧绘制 ====================
    local text_cache = { turn = "", sub = "", undo = "", info = "", mode1 = "", mode2 = "" }

    local function sync_text()
        local turnText, subText
        if over then
            if winner == 3 then
                turnText = "平局"
            elseif mode == "ai" then
                turnText = (winner == 1) and "你赢啦" or "电脑赢了"
            else
                turnText = (winner == 1) and "黑棋赢啦" or "白棋赢啦"
            end
            subText = "按底下的重玩再来一盘"
        elseif aiTimer > 0 then
            turnText = "电脑在想..."
            subText = "等它一会儿"
        elseif mode == "ai" then
            turnText = "轮到你啦"
            subText = "你下黑棋，点棋盘落子"
        else
            turnText = (turn == 1) and "黑棋回合" or "白棋回合"
            subText = "两人轮流点棋盘落子"
        end

        if text_cache.turn ~= turnText then
            text_cache.turn = turnText
            lbTurn:set_text(turnText)
        end
        if text_cache.sub ~= subText then
            text_cache.sub = subText
            lbTurnSub:set_text(subText)
        end

        local m1 = (mode == "ai") and "人机对战" or "人机对战"
        local m2 = (mode == "pvp") and "两人对战" or "两人对战"
        if text_cache.mode1 ~= m1 then
            text_cache.mode1 = m1
            lbMode[1]:set_text(m1)
        end
        if text_cache.mode2 ~= m2 then
            text_cache.mode2 = m2
            lbMode[2]:set_text(m2)
        end
        lbMode[1]:set_color((mode == "ai") and 0xFFFFFF or T.c.dim)
        lbMode[2]:set_color((mode == "pvp") and 0xFFFFFF or T.c.dim)

        local undoText = can_undo() and "悔一步" or "现在不能悔棋"
        if text_cache.undo ~= undoText then
            text_cache.undo = undoText
            lbUndo:set_text(undoText)
        end

        local info = string.format("黑棋 %d 颗 / 白棋 %d 颗\n这局用了 %s\n最快赢棋纪录 %s\n\n横竖斜五颗连成线就赢",
            math.floor((moves + 1) / 2), math.floor(moves / 2),
            T.mmss(elapsed),
            best > 0 and M.format_value(best) or "--")
        if text_cache.info ~= info then
            text_cache.info = info
            lbInfo:set_text(info)
        end
    end

    o.update = function(self, P, t, dt)
        -- 电脑思考计时
        if aiTimer > 0 then
            aiTimer = aiTimer - dt
            if aiTimer <= 0 then
                aiTimer = 0
                ai_move()
            end
        end
        if not over then elapsed = elapsed + dt end

        -- 棋盘
        P:shadow(BX, BY, BOARD, BOARD, 22, 50)
        P:box(BX, BY, BOARD, BOARD, T.paint.board, 255, 20)
        P:frame(BX, BY, BOARD, BOARD, T.paint.board_ln, 3, 255, 20)

        -- 网格
        for i = 0, N - 1 do
            local x = GX + i * CELL
            local y = GY + i * CELL
            P:line(x, GY, x, GY + SPAN, T.paint.board_ln, 1, 200, false)
            P:line(GX, y, GX + SPAN, y, T.paint.board_ln, 1, 200, false)
        end
        -- 星位
        local stars = { { 4, 4 }, { 4, 8 }, { 8, 4 }, { 8, 8 }, { 6, 6 } }
        for s = 1, #stars do
            P:dot(GX + (stars[s][2] - 1) * CELL, GY + (stars[s][1] - 1) * CELL,
                3, T.paint.board_ln, 255)
        end

        -- 棋子
        for i = 1, N * N do
            local v = g[i]
            if v ~= 0 then
                local r = math.floor((i - 1) / N) + 1
                local c = (i - 1) % N + 1
                local cx = GX + (c - 1) * CELL
                local cy = GY + (r - 1) * CELL

                if v == 1 then
                    P:dot(cx + 1, cy + 1, STONE, 0x8A7A66, 70)   -- 一点投影，棋子"浮"起来
                    P:dot(cx, cy, STONE, 0x33302E, 255)
                    P:dot(cx - 5, cy - 5, 4, 0x6A625C, 150)
                else
                    P:dot(cx + 1, cy + 1, STONE, 0x8A7A66, 70)
                    P:dot(cx, cy, STONE, 0xFFFFFF, 255)
                    P:ring(cx, cy, STONE, 0xC9B99F, 2, 255)
                    P:dot(cx - 5, cy - 5, 4, 0xF2EDE2, 255)
                end

                -- 刚落子：一圈扩散光，明确告诉孩子"这步下在这"
                local fl = dropT[i]
                if fl and fl > 0 and fl < 0.4 then
                    local k = fl / 0.4
                    local e = math.floor(2 + 6 * k)
                    P:ring(cx, cy, STONE + e, T.c.teal, 2,
                        math.floor(210 * (1 - k)))
                end
            end
        end

        -- 最后一手：棋子上加个小红点（黑白子都看得见）
        if lastIdx > 0 and g[lastIdx] ~= 0 then
            local r = math.floor((lastIdx - 1) / N) + 1
            local c = (lastIdx - 1) % N + 1
            P:dot(GX + (c - 1) * CELL, GY + (r - 1) * CELL, 4, T.c.magenta, 230)
        end

        -- 五连高亮：连线 + 每颗子套一圈金环
        if #winLine >= 5 then
            local a, b = winLine[1], winLine[5]
            local ar, ac = math.floor((a - 1) / N) + 1, (a - 1) % N + 1
            local br, bc = math.floor((b - 1) / N) + 1, (b - 1) % N + 1
            local k = fx.breathe(t, 0)
            P:line(GX + (ac - 1) * CELL, GY + (ar - 1) * CELL,
                GX + (bc - 1) * CELL, GY + (br - 1) * CELL,
                T.c.gold, 4, math.floor(140 + 90 * k), true)
            for i = 1, #winLine do
                local ii = winLine[i]
                local r = math.floor((ii - 1) / N) + 1
                local c = (ii - 1) % N + 1
                P:ring(GX + (c - 1) * CELL, GY + (r - 1) * CELL, STONE + 4,
                    T.c.gold, 3, 240)
            end
        end

        -- 落子脉冲衰减
        for i = 1, N * N do
            local fl = dropT[i]
            if fl and fl > 0 then
                fl = fl + dt
                dropT[i] = (fl > 0.5) and 0 or fl
            end
        end

        -- ==================== 右侧面板 ====================
        -- 轮到谁：卡片左边放一颗"当前颜色"的棋子
        P:box(PX, 25, PW, 96, T.c.panel, 255, 18)
        P:frame(PX, 25, PW, 96, fx.mix(T.c.teal, T.c.panel, 0.5), 2, 255, 18)

        local showColor = over and winner or turn
        if over and winner == 3 then showColor = 0 end
        if showColor == 1 then
            P:dot(PX + 48, 73, 26, 0x33302E, 255)
            P:dot(PX + 42, 67, 7, 0x6A625C, 150)
        elseif showColor == 2 then
            P:dot(PX + 48, 73, 26, 0xFFFFFF, 255)
            P:ring(PX + 48, 73, 26, 0xC9B99F, 2, 255)
        else
            P:dot(PX + 48, 73, 26, 0xE8DFD0, 255)
        end
        if aiTimer > 0 then
            -- 思考动画：棋子外画一圈转动的弧
            local a0 = (t * 4) % (math.pi * 2)
            P:arc(PX + 48, 73, 32, a0, a0 + 1.6, 12, T.c.teal, 3, 220, false, false)
        end

        -- 模式切换
        local function mode_chip(x, on)
            if on then
                P:shadow(x, 137, 270, 64, 12, 40)
                P:box(x, 137, 270, 64, T.c.teal, 255, 16)
            else
                P:box(x, 137, 270, 64, T.c.panel, 255, 16)
                P:frame(x, 137, 270, 64, 0xB9E4D8, 2, 255, 16)
            end
        end
        mode_chip(PX, mode == "ai")
        mode_chip(PX + 300, mode == "pvp")

        -- 悔棋
        if can_undo() then
            P:box(PX, 217, PW, 64, T.c.panel, 255, 16)
            P:frame(PX, 217, PW, 64, fx.mix(T.c.amber, T.c.panel, 0.45), 2, 255, 16)
        else
            P:box(PX, 217, PW, 64, 0xF7F0E4, 255, 16)
        end

        sync_text()
    end

    o.stats = function(self)
        local who
        if over then
            who = (winner == 3) and "平局" or ((winner == 1) and "黑胜" or "白胜")
        elseif aiTimer > 0 then
            who = "电脑思考中"
        else
            who = (turn == 1) and "黑棋下" or "白棋下"
        end
        return string.format("%s  第 %d 手", who, moves + 1),
            string.format("%s / 下满 %d 手 / 最快 %s", (mode == "ai") and "人机" or "双人",
                N * N, best > 0 and M.format_value(best) or "--")
    end

    -- 外壳切页时问一句"这一局结束了没"：结束了就把底部提示换成"按重玩再来一盘"
    o.is_over = function(self) return over end

    o.restart = function(self) new_game() end

    new_game()
    return o
end

return M
