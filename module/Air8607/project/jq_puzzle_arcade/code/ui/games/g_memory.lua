--[[
@module  g_memory
@summary 益智游戏三：翻牌记忆（4x4 十六张、八对图案）
@version 1.0
@date    2026.11.03
@usage
页面接口同 g2048，另有 o.onTap(x, y)。
@note
八种图案全部用 line / circle / rect 现画（fx.icon），不用图片也不用字形：
hzfont 里没有这些符号，用文字代替必然显示方框。
翻错的两张牌不立刻翻回去，而是等 0.75 秒——留着让玩家记住位置。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

M.id = "g_memory"
M.name = "翻牌记忆"
M.en = "MEMORY PAIRS"
M.desc = "翻开两张找一样的图案 / 八对都配上"
M.tip = "一次翻两张，图案一样就配对成功"
M.accent = T.c.violet
M.record_key = "arcade_memory_moves"
M.rules = "桌上扣着 16 张牌，图案两两一样，一共八对。\n一次翻两张：图案一样就配对成功，留在桌上；不一样会等一会儿再翻回去。\n翻得次数越少越厉害，把八对全部配上就过关。"

M.rank_hint = "翻牌次数越少越靠前"

function M.format_record(v)
    if not v or v <= 0 then return "还没玩过" end
    return string.format("最好 %d 次翻牌", v)
end

-- 排行榜里的成绩文案（榜单页统一调 format_value）
function M.format_value(v)
    if not v or v <= 0 then return "--" end
    return string.format("%d 次", v)
end

local N = 4
local GAP = 12
local CELL = 92
local BOARD = N * CELL + (N - 1) * GAP   -- 404
local PAIRS = 8
local FLIP_BACK = 0.75

-- 八种图案的配色：白底上要深一点才看得清，同时色相彼此拉开
-- 真正用来区分的是图案形状，颜色只是"再帮一把手"
local ICON_C = {
    0x2F8FE0,   -- 蓝
    0x35A85C,   -- 绿
    0xE8A317,   -- 黄
    0xE0489A,   -- 粉
    0x8A5CF0,   -- 紫
    0x18A5B8,   -- 青
    0xD9532B,   -- 橙红
    0x5B6B7C,   -- 蓝灰
}

-- 大厅预览：三张牌，中间那张在"翻来翻去"
function M.preview(P, x, y, w, h, t)
    local cs = math.floor(math.min(h - 8, (w - 16) / 3 - 6))
    if cs < 12 then cs = 12 end
    local gap = 6
    local total = cs * 3 + gap * 2
    local ox = x + math.floor((w - total) / 2)
    local oy = y + math.floor((h - cs) / 2)
    local phase = (t * 0.7) % 2

    for i = 1, 3 do
        local px = ox + (i - 1) * (cs + gap)
        local ccx = px + math.floor(cs / 2)
        local ccy = oy + math.floor(cs / 2)
        if i == 2 and phase < 1 then
            -- 翻开的瞬间：白底 + 图案色描边，图案淡入
            local k = fx.clamp((phase - 0.6) / 0.4, 0, 1)
            P:box(px, oy, cs, cs, 0xFFFFFF, 255, 8)
            P:frame(px, oy, cs, cs, ICON_C[4], 2, 255, 8)
            fx.icon(P, 5, ccx, ccy, math.floor(cs * 0.3), ICON_C[4],
                math.floor(60 + 195 * k))
        else
            P:box(px, oy, cs, cs, 0x8EC5F5, 255, 8)
            P:frame(px, oy, cs, cs, 0xFFFFFF, 2, 255, 8)
            fx.icon(P, (i == 1) and 2 or 8, ccx, ccy,
                math.floor(cs * 0.26), 0xFFFFFF, 200)
        end
    end
end

function M.build(root, W, H, host)
    local o = {}

    local bx = math.floor((W - BOARD) / 2)
    local by = math.floor((H - BOARD) / 2)

    local kind = {}       -- 每张牌的图案编号 1..8
    local st = {}         -- 0 背面 / 1 翻开 / 2 已配对
    local pop = {}        -- 配对高亮计时（数组，0 = 无）
    local openA, openB = nil, nil
    local waitT = 0
    local moves, pairs, elapsed, done = 0, 0, 0, false
    local best = host and host.best(M.record_key) or 0

    local function new_game()
        local deck = {}
        for i = 1, PAIRS do
            deck[#deck + 1] = i
            deck[#deck + 1] = i
        end
        for i = #deck, 2, -1 do
            local j = math.random(1, i)
            deck[i], deck[j] = deck[j], deck[i]
        end
        for i = 1, N * N do
            kind[i] = deck[i]
            st[i] = 0
            pop[i] = 0
        end
        openA, openB = nil, nil
        waitT = 0
        moves, pairs, elapsed, done = 0, 0, 0, false
        best = host and host.best(M.record_key) or 0
        log.info("g_memory", "新开一局")
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
        if done or waitT > 0 then return end
        local i = hit(x, y)
        if not i or st[i] ~= 0 then return end

        st[i] = 1
        if openA == nil then
            openA = i
            return
        end
        openB = i
        moves = moves + 1

        if kind[openA] == kind[openB] then
            st[openA], st[openB] = 2, 2
            pop[openA], pop[openB] = 0.0001, 0.0001
            openA, openB = nil, nil
            pairs = pairs + 1
            if pairs >= PAIRS then
                done = true
                if host then
                    local rank = host.save_min(M.record_key, moves)
                    best = host.best(M.record_key)
                    host.win("八对全配上啦！",
                        string.format("翻了 %d 次牌，花了 %s\n%s", moves, T.mmss(elapsed),
                            rank and string.format("上榜啦，第 %d 名！", rank)
                            or string.format("最好成绩 %d 次", best)))
                end
            end
        else
            waitT = FLIP_BACK
        end
    end

    o.update = function(self, P, t, dt)
        if not done and moves > 0 then elapsed = elapsed + dt end

        -- 翻错的两张到点回位
        if waitT > 0 then
            waitT = waitT - dt
            if waitT <= 0 then
                waitT = 0
                if openA then st[openA] = 0 end
                if openB then st[openB] = 0 end
                openA, openB = nil, nil
            end
        end

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
            local s = st[i]
            local color = ICON_C[kind[i]]

            if s == 0 then
                -- 卡背：亮蓝底 + 白色粗边 + 白色环心，像一张扣着的牌
                P:box(x, y, CELL, CELL, 0x8EC5F5, 255, 12)
                P:frame(x, y, CELL, CELL, 0xFFFFFF, 3, 255, 12)
                P:ring(cx, cy, 19, 0xFFFFFF, 2, 180)
                P:dot(cx, cy, 4, 0xFFFFFF, 200)
                P:dot(x + 13, y + 13, 3, 0xFFFFFF, 140)
                P:dot(x + CELL - 13, y + 13, 3, 0xFFFFFF, 140)
                P:dot(x + 13, y + CELL - 13, 3, 0xFFFFFF, 140)
                P:dot(x + CELL - 13, y + CELL - 13, 3, 0xFFFFFF, 140)
            elseif s == 1 then
                -- 翻开还没配上：白底 + 图案色的粗边，图案看得最清楚
                P:box(x, y, CELL, CELL, 0xFFFFFF, 255, 12)
                P:frame(x, y, CELL, CELL, color, 3, 255, 12)
                fx.icon(P, kind[i], cx, cy, 26, color, 255)
            else
                -- 配对成功：淡绿底 + 呼吸的绿边，安静地"收下这张"
                local k = fx.breathe(t, i * 0.4)
                P:box(x, y, CELL, CELL, 0xE9F8EC, 255, 12)
                P:frame(x, y, CELL, CELL, fx.shade(T.c.green, -0.12), 2,
                    math.floor(160 + 70 * k), 12)
                fx.icon(P, kind[i], cx, cy, 26, color, 230)

                local pf = pop[i]
                if pf > 0 and pf < 0.5 then
                    local u = pf / 0.5
                    local e = math.floor(4 + 10 * u)
                    P:frame(x - e, y - e, CELL + e * 2, CELL + e * 2,
                        T.c.green, 2, math.floor(200 * (1 - u)), 12 + e)
                end
            end

            if pop[i] > 0 then
                pop[i] = pop[i] + dt
                if pop[i] > 0.6 then pop[i] = 0 end
            end
        end
    end

    o.stats = function(self)
        return string.format("配上 %d / %d 对", pairs, PAIRS),
            string.format("翻了 %d 次 / 用时 %s / 最好 %d 次", moves, T.mmss(elapsed), best)
    end

    -- 外壳切页时问一句"这一局结束了没"：结束了就把底部提示换成"按重玩再来一盘"
    o.is_over = function(self) return done end

    o.restart = function(self) new_game() end

    new_game()
    return o
end

return M
