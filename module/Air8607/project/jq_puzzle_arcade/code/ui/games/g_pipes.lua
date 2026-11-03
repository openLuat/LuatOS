--[[
@module  g_pipes
@summary 益智游戏五：水管工（6x6 旋转接通）
@version 1.0
@date    2026.11.03
@usage
页面接口同 g2048，另有 o.onTap(x, y) 顺时针旋转一格。
@note
出题方式：先在 6x6 上随机长出一棵生成树（保证从中心水源能通到每一格），
再把每格随机旋转 0..3 次打乱。所以每一局一定可解，且不需要回溯搜索。
接通状态每帧用一次 BFS 现算（36 格，开销可忽略），
只有跟水源连通的那部分水管会亮起来并跑水珠。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

M.id = "g_pipes"
M.name = "接水管"
M.en = "PIPE FLOW"
M.desc = "转一转水管 / 把水送到每个格子"
M.tip = "点一下水管，它就转四分之一圈"
M.accent = T.c.blue
M.record_key = "arcade_pipes_moves"
M.rules = "水从中间那一格流出来。\n点一下水管，它就顺时针转四分之一圈，两个管口对上，水才能流过去。\n把 36 格全接上水就成功啦。\n已经通水的管子是蓝色的，还会有水珠在跑；灰色的说明还没接上。"

M.rank_hint = "转动次数越少越靠前"

function M.format_record(v)
    if not v or v <= 0 then return "还没玩过" end
    return string.format("最好 %d 步", v)
end

-- 排行榜里的成绩文案（榜单页统一调 format_value）
function M.format_value(v)
    if not v or v <= 0 then return "--" end
    return string.format("%d 步", v)
end

local N = 6
local GAP = 6
local CELL = 62
local BOARD = N * CELL + (N - 1) * GAP   -- 402
local SRC = 3 * N + 3                    -- 中心格（第 3 行第 3 列）

-- 位标记：上=1 右=2 下=4 左=8
local DIRS = { 1, 2, 4, 8 }
local OPP = { [1] = 4, [2] = 8, [4] = 1, [8] = 2 }
local DR = { [1] = -1, [2] = 0, [4] = 1, [8] = 0 }
local DC = { [1] = 0, [2] = 1, [4] = 0, [8] = -1 }

local function has(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end

local function neighbors(i)
    local r = math.floor((i - 1) / N) + 1
    local c = (i - 1) % N + 1
    local list = {}
    if r > 1 then list[#list + 1] = i - N end
    if r < N then list[#list + 1] = i + N end
    if c > 1 then list[#list + 1] = i - 1 end
    if c < N then list[#list + 1] = i + 1 end
    return list
end

local function dir_between(a, b)
    if b == a - N then return 1 end
    if b == a + 1 then return 2 end
    if b == a + N then return 4 end
    return 8
end

-- 大厅预览：4x4 小水管，水珠在流
function M.preview(P, x, y, w, h, t)
    local n = 4
    local gap = 3
    local cs = math.floor((math.min(w, h) - gap * (n - 1)) / n)
    local bw = cs * n + gap * (n - 1)
    local ox = x + math.floor((w - bw) / 2)
    local oy = y + math.floor((h - bw) / 2)
    -- 一条贯穿的"回形"水管，示意接通
    local masks = {
        3, 6, 12, 9,
        2, 0, 0, 8,
        2, 0, 0, 8,
        3, 6, 12, 9,
    }
    for i = 1, n * n do
        local c = (i - 1) % n
        local r = math.floor((i - 1) / n)
        local px = ox + c * (cs + gap)
        local py = oy + r * (cs + gap)
        local cx = px + math.floor(cs / 2)
        local cy = py + math.floor(cs / 2)
        local m = masks[i]
        local lit = (m ~= 0)
        local color = lit and 0x3E8BF0 or 0xC2D2E2
        for d = 1, 4 do
            local bit = DIRS[d]
            if has(m, bit) then
                local ex = cx + DC[bit] * (cs / 2 + gap / 2)
                local ey = cy + DR[bit] * (cs / 2 + gap / 2)
                P:line(cx, cy, ex, ey, 0xFFFFFF, 8, 255, true)
                P:line(cx, cy, ex, ey, color, 5, 255, true)
            end
        end
        if lit then
            local u = (t * 0.9 + i * 0.17) % 1
            P:dot(cx, cy - u * cs * 0.5, 2, 0xFFFFFF, 230)
        end
    end
end

function M.build(root, W, H, host)
    local o = {}

    local bx = math.floor((W - BOARD) / 2)
    local by = math.floor((H - BOARD) / 2)

    local base = {}      -- 生成树给出的正确臂
    local rot = {}       -- 当前旋转量 0..3
    local lit = {}       -- 是否与水源连通
    local moves, elapsed, done, litCount = 0, 0, false, 0
    local best = host and host.best(M.record_key) or 0

    local function mask_of(i)
        return fx.rot_mask(base[i], rot[i])
    end

    local function generate()
        base, rot = {}, {}
        for i = 1, N * N do
            base[i] = 0
            rot[i] = 0
        end

        -- 随机生成树：深度优先，把"通路"刻进两头的臂里
        local visited = {}
        local order = {}
        for i = 1, N * N do order[i] = i end
        for i = N * N, 2, -1 do
            local j = math.random(1, i)
            order[i], order[j] = order[j], order[i]
        end

        local start = order[1]
        visited[start] = true
        local stack = { start }
        while #stack > 0 do
            local cur = stack[#stack]
            local cand = {}
            local ns = neighbors(cur)
            for j = 1, #ns do
                local n = ns[j]
                if not visited[n] then cand[#cand + 1] = n end
            end
            if #cand == 0 then
                stack[#stack] = nil
            else
                local n = cand[math.random(1, #cand)]
                local d = dir_between(cur, n)
                -- 臂位图是"或"语义；同一位不会重复出现，加法等价且不依赖位运算符
                if not has(base[cur], d) then base[cur] = base[cur] + d end
                if not has(base[n], OPP[d]) then base[n] = base[n] + OPP[d] end
                visited[n] = true
                stack[#stack + 1] = n
            end
        end

        -- 打乱：每格随机转 0..3 次（可解性由生成树保证）
        for i = 1, N * N do
            rot[i] = math.random(0, 3)
        end
    end

    --[[从水源做一次 BFS，标出哪些格子已经通水
    只有"我这面有臂"且"对面也有对应的臂"才算接上。
    缓冲表在 build 时一次性分配好，BFS 里不再建表（每帧要跑一次）。]]
    local bufM, bufQ = {}, {}
    local function compute_lit()
        for i = 1, N * N do
            lit[i] = false
            bufM[i] = mask_of(i)
        end
        local head, tail = 1, 1
        bufQ[1] = SRC
        lit[SRC] = true
        local cnt = 1
        while head <= tail do
            local cur = bufQ[head]
            head = head + 1
            local r = math.floor((cur - 1) / N) + 1
            local c = (cur - 1) % N + 1
            local curMask = bufM[cur]
            for d = 1, 4 do
                local bit = DIRS[d]
                if has(curMask, bit) then
                    local nr, nc = r + DR[bit], c + DC[bit]
                    if nr >= 1 and nr <= N and nc >= 1 and nc <= N then
                        local n = (nr - 1) * N + nc
                        if not lit[n] and has(bufM[n], OPP[bit]) then
                            lit[n] = true
                            cnt = cnt + 1
                            tail = tail + 1
                            bufQ[tail] = n
                        end
                    end
                end
            end
        end
        litCount = cnt
        return cnt
    end

    local function new_game()
        generate()
        moves, elapsed, done = 0, 0, false
        best = host and host.best(M.record_key) or 0
        compute_lit()
        log.info("g_pipes", "新开一局", "初始接通", litCount)
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
        if not i then return end
        rot[i] = (rot[i] + 1) % 4
        moves = moves + 1
        local n = compute_lit()
        if n >= N * N then
            done = true
            local sec = math.floor(elapsed)
            if host then
                local rank = host.save_min(M.record_key, moves)
                best = host.best(M.record_key)
                host.win("水管全通啦，真棒！",
                    string.format("转了 %d 次，花了 %s\n%s", moves, T.mmss(sec),
                        rank and string.format("上榜啦，第 %d 名！", rank)
                        or string.format("最好成绩 %d 步", best)))
            end
        end
    end

    o.update = function(self, P, t, dt)
        if moves > 0 and not done then elapsed = elapsed + dt end
        if not done then compute_lit() end

        P:shadow(bx - 12, by - 12, BOARD + 24, BOARD + 24, 24, 52)
        P:box(bx - 12, by - 12, BOARD + 24, BOARD + 24, T.paint.board, 255, 24)
        P:frame(bx - 12, by - 12, BOARD + 24, BOARD + 24, T.paint.board_ln, 3, 255, 24)

        for i = 1, N * N do
            local c = (i - 1) % N
            local r = math.floor((i - 1) / N)
            local x = bx + c * (CELL + GAP)
            local y = by + r * (CELL + GAP)
            local cx = x + math.floor(CELL / 2)
            local cy = y + math.floor(CELL / 2)
            local m = mask_of(i)
            local isLit = lit[i]

            -- 格子底：通水的是淡蓝水槽，没通水的是白格子
            P:box(x, y, CELL, CELL, isLit and 0xE4F3FF or 0xFFFFFF, 255, 10)
            P:frame(x, y, CELL, CELL, isLit and 0xB6DCF5 or T.paint.board_ln, 2, 200, 10)

            local body = isLit and 0x3E8BF0 or 0xC9D6E4

            for d = 1, 4 do
                local bit = DIRS[d]
                if has(m, bit) then
                    local ex = cx + DC[bit] * (CELL / 2 + GAP / 2)
                    local ey = cy + DR[bit] * (CELL / 2 + GAP / 2)
                    -- 白色管壁 + 彩色管身 + 一道细细的高光，像一节塑料水管
                    P:line(cx, cy, ex, ey, 0xFFFFFF, 18, 255, false)
                    P:line(cx, cy, ex, ey, body, 12, 255, false)
                    P:line(cx, cy, ex, ey, 0xFFFFFF, 4,
                        isLit and 150 or 110, false)
                end
            end

            -- 中心接头
            P:dot(cx, cy, 10, 0xFFFFFF, 255)
            P:dot(cx, cy, 7, body, 255)

            -- 通水动画：每根臂上跑一颗水珠
            if isLit then
                for d = 1, 4 do
                    local bit = DIRS[d]
                    if has(m, bit) then
                        local u = (t * 1.1 + i * 0.11 + d * 0.25) % 1
                        local px = cx + DC[bit] * u * CELL / 2
                        local py = cy + DR[bit] * u * CELL / 2
                        P:dot(px, py, 3, 0xFFFFFF, math.floor(150 + 105 * (1 - u)))
                    end
                end
            end

            -- 水源：一圈脉冲
            if i == SRC then
                local k = fx.breathe(t, 0)
                P:ring(cx, cy, 20 + math.floor(4 * k), T.c.blue, 3,
                    math.floor(110 + 120 * k))
            end
        end
    end

    o.stats = function(self)
        return string.format("接通 %d / %d 格  转了 %d 次", litCount, N * N, moves),
            string.format("用时 %s / 最好 %d 步", T.mmss(elapsed), best)
    end

    -- 外壳切页时问一句"这一局结束了没"：结束了就把底部提示换成"按重玩再来一盘"
    o.is_over = function(self) return done end

    o.restart = function(self) new_game() end

    new_game()
    return o
end

return M
