--[[
@module  g2048
@summary 益智游戏一：2048 数字合并（四向滑动）
@version 1.0
@date    2026.11.03
@usage
页面接口（七款游戏统一，由 ui_shell 调用）：
  M.build(root, W, H, host) -> o
  o.update(P, t, dt)   每帧把棋盘画进图元池
  o.onSwipe(dir)       1=上 2=右 3=下 4=左
  o.stats()            返回 HUD 需要更新的两行文字
  o.restart()          重开一局
@note
数字不走 label 每帧 set_text，而是在 refresh_labels() 里做文本去重：
只有值变了才 set_text / set_color，避免 LVGL 反复重排文本产生脏区。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

M.id = "g2048"
M.name = "数字 2048"
M.en = "MERGE 2048"
M.desc = "一样的数字碰在一起 / 合起来变大"
M.tip = "用手指在棋盘上滑一下，方块就朝那边跑"
M.accent = T.c.amber
M.record_key = "arcade_2048"
M.rules = "在棋盘上往上下左右滑一下，所有方块都朝那个方向跑。\n两个一样的数碰在一起，就会合成它们加起来的数。\n每次滑完都会冒出一个新的 2 或 4。\n合出 2048 就成功啦！棋盘塞满又合不动时就结束。"

-- 榜单页抬头那句话：告诉孩子这个榜怎么排
M.rank_hint = "分数越高的越靠前"

-- 大厅卡片上的记录文案（本作记录是分数，越大越好）
function M.format_record(v)
    if not v or v <= 0 then return "还没玩过" end
    return string.format("最好 %d 分", v)
end

-- 排行榜里的成绩文案（榜单页统一调 format_value）
function M.format_value(v)
    if not v or v <= 0 then return "--" end
    return string.format("%d 分", v)
end

-- ==================== 棋盘几何 ====================
local N = 4
local GAP = 12
local CELL = 96
local BOARD = N * CELL + (N - 1) * GAP    -- 420，舞台高 446，上下各留 13

-- ==================== 数值配色 ====================
-- 孩子认数字之前先认颜色，所以每一档都是不同的糖果色：
-- 小数字用浅色配深字（对比最清楚），大数字用饱和色配白字，
-- 2048 单独给一个亮粉，合出来的那一刻最有"长大了"的感觉。
local TILE = {
    [2]    = { bg = 0x9AD0EC, fg = 0x2A4A5C },   -- 天蓝
    [4]    = { bg = 0x7ED4A6, fg = 0x1E4A33 },   -- 薄荷
    [8]    = { bg = 0xFFD166, fg = 0x6B4A00 },   -- 太阳黄
    [16]   = { bg = 0xFFB03A, fg = 0x5A3200 },   -- 橙黄
    [32]   = { bg = 0xFF8A3D, fg = 0xFFFFFF },   -- 蜜橘
    [64]   = { bg = 0xFF6B6B, fg = 0xFFFFFF },   -- 珊瑚红
    [128]  = { bg = 0xF0559B, fg = 0xFFFFFF },   -- 玫瑰
    [256]  = { bg = 0xC65DD8, fg = 0xFFFFFF },   -- 紫罗兰
    [512]  = { bg = 0x9B6BFF, fg = 0xFFFFFF },   -- 葡萄紫
    [1024] = { bg = 0x5B8DEF, fg = 0xFFFFFF },   -- 天蓝
    [2048] = { bg = 0xFF4FA3, fg = 0xFFFFFF },   -- 亮粉（目标色）
}
local TILE_MAX = TILE[2048]

local function tile_style(v)
    return TILE[v] or TILE_MAX
end

local function cell_label(parent, x, y, color)
    -- h 给到 40：30 号字的行高约 36px，框比字高才不会把数字顶部切掉
    return airui.label({
        parent = parent, x = x, y = y, w = CELL, h = 40,
        text = "", font_size = T.f.val, color = color,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

-- ==================== 大厅预览 ====================
--[[迷你 4x4 棋盘：一颗高亮方块在呼吸，示意"合并"这件事]]
function M.preview(P, x, y, w, h, t)
    local gap = 5
    local cs = math.floor((math.min(w, h) - gap * (N - 1)) / N)
    local bw = cs * N + gap * (N - 1)
    local ox = x + math.floor((w - bw) / 2)
    local oy = y + math.floor((h - bw) / 2)
    local demo = {
        2, 0, 4, 0,
        0, 8, 0, 16,
        0, 0, 32, 0,
        0, 64, 0, 128,
    }
    local k = fx.breathe(t, 0)
    for i = 1, N * N do
        local c = (i - 1) % N
        local r = math.floor((i - 1) / N)
        local px = ox + c * (cs + gap)
        local py = oy + r * (cs + gap)
        local v = demo[i]
        if v == 0 then
            P:box(px, py, cs, cs, T.paint.slot, 255, 5)
        else
            local tc = tile_style(v)
            P:box(px, py, cs, cs, tc.bg, 255, 5)
        end
    end
    -- 呼吸的白色描边落在右下角那颗 128 上，示意"这一块要变了"
    local px = ox + 3 * (cs + gap)
    local py = oy + 3 * (cs + gap)
    P:frame(px - 3, py - 3, cs + 6, cs + 6, 0xFFFFFF, 2,
        math.floor(120 + 100 * k), 6)
end

-- ==================== 页面构建 ====================
function M.build(root, W, H, host)
    local o = {}

    local bx = math.floor((W - BOARD) / 2)
    local by = math.floor((H - BOARD) / 2)

    local g = {}          -- 16 格数值，0 表示空
    local flash = {}      -- 每格的出生脉冲计时（0 = 无）
    local tx = {}         -- 文本缓存，用于去重
    local lbs = {}
    local score, moves, best = 0, 0, 0
    local over, won = false, false

    for i = 1, N * N do
        local c = (i - 1) % N
        local r = math.floor((i - 1) / N)
        lbs[i] = cell_label(root,
            bx + c * (CELL + GAP),
            by + r * (CELL + GAP) + 28,
            T.c.txt)
    end

    -- ==================== 文本刷新（去重）====================
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
                    lbs[i]:set_color(tile_style(v).fg)
                end
                -- 四位数字在 96px 格里用 22 号，三位以内用 30 号
                lbs[i]:set_font_size((v >= 1024) and T.f.body or T.f.val)
            end
        end
    end

    -- ==================== 出块 / 开局 ====================
    local function spawn()
        local empty = {}
        for i = 1, N * N do
            if g[i] == 0 then empty[#empty + 1] = i end
        end
        if #empty == 0 then return false end
        local i = empty[math.random(1, #empty)]
        g[i] = (math.random() < 0.9) and 2 or 4
        flash[i] = 0.0001
        return true
    end

    local function new_game()
        for i = 1, N * N do
            g[i] = 0
            flash[i] = 0
            tx[i] = nil
        end
        score, moves, over, won = 0, 0, false, false
        best = host and host.best(M.record_key) or 0
        spawn()
        spawn()
        refresh_labels()
        log.info("g2048", "新开一局")
    end

    -- ==================== 判定 ====================
    local function has_move()
        for i = 1, N * N do
            if g[i] == 0 then return true end
        end
        for r = 1, N do
            for c = 1, N do
                local i = (r - 1) * N + c
                local v = g[i]
                if c < N and g[i + 1] == v then return true end
                if r < N and g[i + N] == v then return true end
            end
        end
        return false
    end

    -- ==================== 滑动合并 ====================
    --[[把 4 条线取出来 -> 压缩 -> 合并 -> 写回
    dir: 1=上 2=右 3=下 4=左（"最靠近该方向墙壁的一格"排在数组第 1 位）
    ]]
    local function slide(dir)
        local moved = false
        local gain = 0
        local top = false

        for k = 1, N do
            local idx = {}
            for j = 1, N do
                local r, c
                if dir == 1 then          -- 上：按列，从第 1 行开始
                    r, c = j, k
                elseif dir == 3 then      -- 下：按列，从第 4 行开始
                    r, c = N - j + 1, k
                elseif dir == 4 then      -- 左：按行，从第 1 列开始
                    r, c = k, j
                else                      -- 右：按行，从第 4 列开始
                    r, c = k, N - j + 1
                end
                idx[j] = (r - 1) * N + c
            end

            -- 压缩掉空格
            local vals, n = {}, 0
            for j = 1, N do
                local v = g[idx[j]]
                if v ~= 0 then
                    n = n + 1
                    vals[n] = v
                end
            end

            -- 相邻相同则合并
            local out, m, j = {}, 0, 1
            while j <= n do
                if j < n and vals[j] == vals[j + 1] then
                    local merged = vals[j] * 2
                    m = m + 1
                    out[m] = merged
                    gain = gain + merged
                    if merged >= 2048 then top = true end
                    j = j + 2
                else
                    m = m + 1
                    out[m] = vals[j]
                    j = j + 1
                end
            end

            -- 写回（末尾补 0）
            for j = 1, N do
                local v = out[j] or 0
                local i = idx[j]
                if g[i] ~= v then
                    g[i] = v
                    moved = true
                    if v ~= 0 then flash[i] = 0.0001 end
                end
            end
        end

        return moved, gain, top
    end

    local function check_end()
        if not has_move() then
            over = true
            if host then
                local rank = host.save(M.record_key, score)
                best = host.best(M.record_key)
                host.lose("这一步走完啦",
                    string.format("这次得了 %d 分，走了 %d 步\n%s\n\n再来一次会更好！",
                        score, moves,
                        rank and string.format("上榜啦，第 %d 名！", rank)
                        or string.format("最好成绩 %d 分", best)))
            end
        end
    end

    -- ==================== 对外接口 ====================
    o.onSwipe = function(self, dir)
        if over then return end
        local moved, gain, top = slide(dir)
        if not moved then return end
        score = score + gain
        moves = moves + 1
        if score > best then best = score end
        spawn()
        refresh_labels()
        if top and not won then
            won = true
            -- 达成 2048 不算结束：把记录先存了，再让玩家选择继续冲分
            if host then
                local rank = host.save(M.record_key, score)
                best = host.best(M.record_key)
                host.notice("太棒了！你合出了 2048",
                    string.format("现在有 %d 分\n%s\n还想拼更大的数字吗？", score,
                        rank and string.format("上榜啦，第 %d 名！", rank)
                        or "这次没进前 5 名"),
                    "接着玩", nil)
            end
        else
            check_end()
        end
    end

    o.update = function(self, P, t, dt)
        -- 底板：投影 + 奶油色板 + 深一号的描边，像一块真的棋盘
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
                P:box(x, y, CELL, CELL, T.paint.slot, 255, 14)
            else
                local tc = tile_style(v)

                -- 出生脉冲：向外扩散的一圈同色描边，0.32 秒淡出
                local fl = flash[i]
                if fl > 0 and fl < 0.32 then
                    local k = fl / 0.32
                    local e = math.floor(2 + 7 * k)
                    P:frame(x - e, y - e, CELL + e * 2, CELL + e * 2,
                        tc.bg, 3, math.floor(190 * (1 - k)), 14 + e)
                end

                P:box(x, y, CELL, CELL, tc.bg, 255, 14)
                -- 顶部高光：一条白色亮边，方块才有"塑料积木感"而不是纯色块
                P:box(x + 8, y + 6, CELL - 16, 5, 0xFFFFFF, 70, 3)
            end
        end

        -- 计时衰减：脉冲只活 0.4 秒
        for i = 1, N * N do
            local fl = flash[i]
            if fl > 0 then
                fl = fl + dt
                flash[i] = (fl > 0.4) and 0 or fl
            end
        end

        refresh_labels()
    end

    o.stats = function(self)
        -- 孩子最关心"我最大的数字到几了"，比分更容易看懂，所以放在第一行
        local maxTile = 0
        for i = 1, N * N do
            if g[i] > maxTile then maxTile = g[i] end
        end
        return string.format("最大 %d  得分 %d", maxTile, score),
            string.format("最好 %d 分 / 走了 %d 步", best, moves)
    end

    -- 外壳切页时问一句"这一局结束了没"：结束了就把底部提示换成"按重玩再来一盘"
    o.is_over = function(self) return over end

    o.restart = function(self) new_game() end

    new_game()
    return o
end

return M
