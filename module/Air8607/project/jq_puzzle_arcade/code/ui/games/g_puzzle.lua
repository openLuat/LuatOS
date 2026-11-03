--[[
@module  g_puzzle
@summary 益智游戏二：数字华容道（4x4 数字滑块）
@version 1.0
@date    2026.11.03
@usage
页面接口同 g2048，另有 o.onTap(x, y) 用于点按相邻方块。
@note
开局不是随机排列，而是从"已解好"的局面出发随机走 260 步合法移动：
这样既保证一定可解（奇偶校验天然成立），又保证不是几步就能还原。
方块颜色由序号经 HSL 渐变算出，越靠后越暖；已在正确位置的方块右上角带绿点。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

M.id = "g_puzzle"
M.name = "数字华容道"
M.en = "SLIDE 15"
M.desc = "把 1 到 15 排整齐 / 空位留在右下角"
M.tip = "点一下空位旁边的方块，它就滑过去"
M.accent = T.c.cyan
M.record_key = "arcade_puzzle_moves"
M.rules = "棋盘上放着 1 到 15 的数字方块，右下角留了一个空位。\n点空位旁边（上下左右）的方块，它就会滑进空位里。\n把数字按 1、2、3 ... 一直到 15 排好，空位留在右下角，就完成啦。\n已经在正确位置的方块，右上角会亮一个绿点。"

M.rank_hint = "步数越少越靠前"

-- 大厅卡片上的记录文案（本作记录是"最少步数"，越小越好）
function M.format_record(v)
    if not v or v <= 0 then return "还没玩过" end
    return string.format("最好 %d 步", v)
end

-- 排行榜里的成绩文案（榜单页统一调 format_value）
function M.format_value(v)
    if not v or v <= 0 then return "--" end
    return string.format("%d 步", v)
end

local N = 4
local GAP = 12
local CELL = 96
local BOARD = N * CELL + (N - 1) * GAP
local SHUFFLE_STEPS = 260

-- 方块配色：整个色环走一遍，序号越大越暖
-- 孩子记不住 1..15 的位置，但记得住"粉色那块在右边"，颜色本身就是线索
local TC = {}
for v = 1, 15 do
    TC[v] = {
        bg = fx.hsl(196 + v * 17, 0.66, 0.56),
        fg = 0xFFFFFF,
    }
end

-- 大厅预览
function M.preview(P, x, y, w, h, t)
    local gap = 5
    local cs = math.floor((math.min(w, h) - gap * (N - 1)) / N)
    local bw = cs * N + gap * (N - 1)
    local ox = x + math.floor((w - bw) / 2)
    local oy = y + math.floor((h - bw) / 2)
    -- 一小段"正在滑动"的循环：第 1 行的方块来回挪
    local k = 0.5 + 0.5 * math.sin(t * 1.6)
    for r = 0, N - 1 do
        for c = 0, N - 1 do
            local v = r * N + c + 1
            local px = ox + c * (cs + gap)
            local py = oy + r * (cs + gap)
            if v == 16 then
                P:box(px, py, cs, cs, T.paint.slot, 255, 5)
            else
                local tc = TC[(v % 15) + 1]
                P:box(px, py, cs, cs, tc.bg, 255, 5)
            end
        end
    end
    -- 白色描边在第一行来回移动，示意"这块正在滑"
    local px = ox + math.floor(k * 3) * (cs + gap)
    P:frame(px - 2, oy - 2, cs + 4, cs + 4, 0xFFFFFF, 2,
        math.floor(140 + 110 * k), 6)
end

local function cell_index(x, y, bx, by)
    local c = math.floor((x - bx) / (CELL + GAP)) + 1
    local r = math.floor((y - by) / (CELL + GAP)) + 1
    if c < 1 or c > N or r < 1 or r > N then return nil end
    -- 落在间距里不算命中
    local lx = x - (bx + (c - 1) * (CELL + GAP))
    local ly = y - (by + (r - 1) * (CELL + GAP))
    if lx > CELL or ly > CELL then return nil end
    return (r - 1) * N + c
end

function M.build(root, W, H, host)
    local o = {}

    local bx = math.floor((W - BOARD) / 2)
    local by = math.floor((H - BOARD) / 2)

    local g = {}
    local tx = {}
    local lbs = {}
    local blank, moves, elapsed, done = 16, 0, 0, false
    local best = 0

    for i = 1, N * N do
        local c = (i - 1) % N
        local r = math.floor((i - 1) / N)
        -- h 给到 40：30 号字的行高约 36px，框比字高才不会把数字顶部切掉
        lbs[i] = airui.label({
            parent = root,
            x = bx + c * (CELL + GAP),
            y = by + r * (CELL + GAP) + 28,
            w = CELL, h = 40,
            text = "", font_size = T.f.val, color = T.c.txt,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    local function refresh_labels()
        for i = 1, N * N do
            local v = g[i]
            local s = (v == 0) and "" or tostring(v)
            if tx[i] ~= s then
                tx[i] = s
                lbs[i]:set_text(s)
                if v == 0 then
                    lbs[i]:set_color(T.c.txt)
                else
                    lbs[i]:set_color(TC[v].fg)
                end
            end
        end
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

    local function new_game()
        for i = 1, N * N do g[i] = i end
        g[N * N] = 0
        blank = N * N
        local last = 0
        for _ = 1, SHUFFLE_STEPS do
            local list = neighbors(blank)
            local cand = {}
            for j = 1, #list do
                if list[j] ~= last then cand[#cand + 1] = list[j] end
            end
            local pick = cand[math.random(1, #cand)]
            g[blank] = g[pick]
            g[pick] = 0
            last = blank
            blank = pick
        end
        moves, elapsed, done = 0, 0, false
        tx = {}
        best = host and host.best(M.record_key) or 0
        refresh_labels()
        log.info("g_puzzle", "新开一局")
    end

    local function solved()
        for i = 1, N * N - 1 do
            if g[i] ~= i then return false end
        end
        return g[N * N] == 0
    end

    o.onTap = function(self, x, y)
        if done then return end
        local i = cell_index(x, y, bx, by)
        if not i or i == blank then return end
        -- 只接受与空位正交相邻的方块
        local ok = false
        local list = neighbors(blank)
        for j = 1, #list do
            if list[j] == i then ok = true break end
        end
        if not ok then return end

        g[blank] = g[i]
        g[i] = 0
        blank = i
        moves = moves + 1
        refresh_labels()

        if solved() then
            done = true
            if host then
                local rank = host.save_min(M.record_key, moves > 0 and moves or 1)
                best = host.best(M.record_key)
                host.win("排好啦，真棒！",
                    string.format("用了 %d 步，花了 %s\n%s", moves, T.mmss(elapsed),
                        rank and string.format("上榜啦，第 %d 名！", rank)
                        or string.format("最好成绩 %d 步", best)))
            end
        end
    end

    o.update = function(self, P, t, dt)
        if moves > 0 and not done then elapsed = elapsed + dt end

        P:shadow(bx - 12, by - 12, BOARD + 24, BOARD + 24, 24, 52)
        P:box(bx - 12, by - 12, BOARD + 24, BOARD + 24, T.paint.board, 255, 24)
        P:frame(bx - 12, by - 12, BOARD + 24, BOARD + 24, T.paint.board_ln, 3, 255, 24)

        for i = 1, N * N do
            local c = (i - 1) % N
            local r = math.floor((i - 1) / N)
            local x = bx + c * (CELL + GAP)
            local y = by + r * (CELL + GAP)
            local v = g[i]

            if v == 0 then
                -- 空位：比底板浅一档的凹槽，一眼能看出"这块空着"
                P:box(x, y, CELL, CELL, T.paint.slot, 255, 14)
                P:frame(x, y, CELL, CELL, T.paint.board_ln, 2, 200, 14)
            else
                local tc = TC[v]
                P:box(x, y, CELL, CELL, tc.bg, 255, 14)
                P:box(x + 8, y + 6, CELL - 16, 5, 0xFFFFFF, 70, 3)
                -- 已就位：右上角绿点，扫一眼就知道还差几块
                if v == i then
                    P:dot(x + CELL - 15, y + 15, 5, 0xFFFFFF, 235)
                    P:dot(x + CELL - 15, y + 15, 3, T.c.green, 255)
                end
            end
        end

        refresh_labels()
    end

    o.stats = function(self)
        local ok = 0
        for i = 1, N * N - 1 do
            if g[i] == i then ok = ok + 1 end
        end
        return string.format("摆好 %d 块  走了 %d 步", ok, moves),
            string.format("用时 %s / 最好 %d 步", T.mmss(elapsed), best)
    end

    -- 外壳切页时问一句"这一局结束了没"：结束了就把底部提示换成"按重玩再来一盘"
    o.is_over = function(self) return done end

    o.restart = function(self) new_game() end

    new_game()
    return o
end

return M
