--[[
@module  g_simon
@summary 益智游戏六：记忆序列（four pads 复现演示顺序）
@version 1.0
@date    2026.11.03
@usage
页面接口同 g2048，另有 o.onTap(x, y) 点四个色块之一。
@note
四个色块轮流亮起，玩家按同样顺序点回来；每过一关序列加长一格。
出题用的是 math.random，所以每局都不一样；最高关卡会存到本机。
关卡到 20 直接判"记忆大师"，避免一局玩到天荒地老。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

M.id = "g_simon"
M.name = "记顺序"
M.en = "MEMORY FLOW"
M.desc = "看清哪块亮 / 按一样的顺序点回去"
M.tip = "先看它亮，再按同样的顺序点回去"
M.accent = T.c.magenta
M.record_key = "arcade_simon_round"
M.rules = "四个色块会一个一个亮起来，要记住亮的顺序。\n全部亮完以后，按同样的顺序把它们点一遍。\n点对了就过关，下一关会多记一个。\n点错了这一局就结束，看看你能记到第几关。"

M.rank_hint = "记到的关卡越高越靠前"

function M.format_record(v)
    if not v or v <= 0 then return "还没玩过" end
    return string.format("最好到第 %d 关", v)
end

-- 排行榜里的成绩文案（榜单页统一调 format_value）
function M.format_value(v)
    if not v or v <= 0 then return "--" end
    return string.format("第 %d 关", v)
end

local PAD_W, PAD_H = 220, 160
local GAP = 16
local MAX_ROUND = 20
local SHOW_ON, SHOW_OFF = 0.42, 0.16
local SHOW_SLOT = SHOW_ON + SHOW_OFF

-- 四个色块：绿 / 红 / 琥珀 / 蓝，配四种轮廓差别大的图标
local PADS = {
    { color = T.c.green,  icon = 1 },
    { color = T.c.red,    icon = 4 },
    { color = T.c.amber,  icon = 3 },
    { color = T.c.blue,   icon = 2 },
}

-- 大厅预览：2x2 色块，按节奏轮流亮
function M.preview(P, x, y, w, h, t)
    local pw = math.floor((w - 10) / 2)
    local ph = math.floor((h - 10) / 2)
    local ox = x + math.floor((w - (pw * 2 + 6)) / 2)
    local oy = y + math.floor((h - (ph * 2 + 6)) / 2)
    local step = math.floor(t * 2) % 4 + 1
    for i = 1, 4 do
        local c = (i - 1) % 2
        local r = math.floor((i - 1) / 2)
        local px = ox + c * (pw + 6)
        local py = oy + r * (ph + 6)
        local p = PADS[i]
        if i == step then
            P:box(px, py, pw, ph, p.color, 255, 8)
        else
            P:box(px, py, pw, ph, fx.mix(T.c.panel, p.color, 0.3), 255, 8)
            P:frame(px, py, pw, ph, p.color, 2, 220, 8)
        end
    end
end

function M.build(root, W, H, host)
    local o = {}

    local totalW = PAD_W * 2 + GAP
    local totalH = PAD_H * 2 + GAP
    local ox = math.floor((W - totalW) / 2)
    local oy = math.floor((H - totalH) / 2)

    local seq = {}
    local round, inputIdx = 1, 1
    local mode = "show"        -- show / input / over
    local showT = 0
    local flash = { 0, 0, 0, 0 }
    local elapsed, done = 0, false
    local best = host and host.best(M.record_key) or 0

    local function pad_rect(i)
        local c = (i - 1) % 2
        local r = math.floor((i - 1) / 2)
        return ox + c * (PAD_W + GAP), oy + r * (PAD_H + GAP)
    end

    local function extend()
        seq[#seq + 1] = math.random(1, 4)
    end

    local function start_show()
        mode = "show"
        showT = 0
        inputIdx = 1
    end

    local function new_game()
        seq = {}
        round = 1
        elapsed = 0
        done = false
        extend()
        start_show()
        best = host and host.best(M.record_key) or 0
        log.info("g_simon", "新开一局")
    end

    local function do_lose(i)
        mode = "over"
        done = true
        flash[i] = 0.0001
        if host then
            local rank = host.save(M.record_key, round)
            best = host.best(M.record_key)
            host.lose("顺序记错啦",
                string.format("这次记到了第 %d 关，用了 %s\n%s",
                    round, T.mmss(elapsed),
                    rank and string.format("上榜啦，第 %d 名！", rank)
                    or string.format("最好一次记到第 %d 关", best)))
        end
    end

    o.onTap = function(self, x, y)
        if mode ~= "input" then return end
        local hitPad = 0
        for i = 1, 4 do
            local px, py = pad_rect(i)
            if T.hit(x, y, px, py, PAD_W, PAD_H) then
                hitPad = i
                break
            end
        end
        if hitPad == 0 then return end

        flash[hitPad] = 0.0001
        if hitPad ~= seq[inputIdx] then
            do_lose(hitPad)
            return
        end

        inputIdx = inputIdx + 1
        if inputIdx > #seq then
            -- 整套序列点完，进入下一关
            if round >= MAX_ROUND then
                mode = "over"
                done = true
                if host then
                    local rank = host.save(M.record_key, round)
                    best = host.best(M.record_key)
                    host.win("记忆力太厉害了！",
                        string.format("一路记到第 %d 关，用了 %s\n%s", round, T.mmss(elapsed),
                            rank and string.format("上榜啦，第 %d 名！", rank)
                            or string.format("最好成绩 第 %d 关", best)))
                end
                return
            end
            round = round + 1
            extend()
            start_show()
        end
    end

    o.update = function(self, P, t, dt)
        if not done then elapsed = elapsed + dt end

        -- 演示节奏推进
        local litPad, litK = 0, 0
        if mode == "show" then
            showT = showT + dt
            local idx = math.floor(showT / SHOW_SLOT) + 1
            if idx > #seq then
                mode = "input"
                inputIdx = 1
            else
                local phase = showT - (idx - 1) * SHOW_SLOT
                if phase < SHOW_ON then
                    litPad = seq[idx]
                    litK = 1 - phase / SHOW_ON      -- 1 → 刚亮，0 → 快灭
                end
            end
        end

        for i = 1, 4 do
            if flash[i] > 0 then
                flash[i] = flash[i] + dt
                if flash[i] > 0.3 then flash[i] = 0 end
            end
        end

        -- 序列进度点：一排小圆点，已点对的亮起来
        local n = #seq
        if n > 0 then
            local dotW = 14
            local total = n * dotW
            local dx = math.floor((W - total) / 2)
            local dy = oy - 26
            if dy < 10 then dy = 10 end
            local filled = (mode == "input") and (inputIdx - 1) or 0
            for i = 1, n do
                local cx = dx + (i - 1) * dotW + math.floor(dotW / 2)
                if i <= filled then
                    P:dot(cx, dy, 4, T.c.magenta, 240)
                else
                    P:dot(cx, dy, 4, T.c.line2, 200)
                end
            end
        end

        for i = 1, 4 do
            local px, py = pad_rect(i)
            local p = PADS[i]
            local on = (litPad == i) or (flash[i] > 0)

            -- 亮起时整块变成饱和色 + 白色图标；不亮时是淡彩底 + 粗描边
            if on then
                local k = (litPad == i) and litK or (1 - flash[i] / 0.3)
                -- 外面套一圈同色淡边，像灯泡亮起来时的光圈
                P:frame(px - 6, py - 6, PAD_W + 12, PAD_H + 12, p.color, 3,
                    math.floor(120 + 100 * k), 22)
                P:box(px, py, PAD_W, PAD_H, p.color, 255, 18)
                fx.icon(P, p.icon, px + math.floor(PAD_W / 2),
                    py + math.floor(PAD_H / 2), 30, 0xFFFFFF, 240)
            else
                P:box(px, py, PAD_W, PAD_H, fx.mix(T.c.panel, p.color, 0.26), 255, 18)
                P:frame(px, py, PAD_W, PAD_H, p.color, 3, 190, 18)
                fx.icon(P, p.icon, px + math.floor(PAD_W / 2),
                    py + math.floor(PAD_H / 2), 30, p.color, 220)
            end
        end

        -- 输入阶段给一圈很淡的整屏边框，提示"轮到你了"
        if mode == "input" then
            local k = fx.breathe(t, 0)
            P:frame(ox - 12, oy - 12, totalW + 24, totalH + 24, T.c.magenta, 1,
                math.floor(40 + 60 * k), 22)
        end
    end

    o.stats = function(self)
        local st = (mode == "show") and "看好啦" or ((mode == "input") and "该你啦" or "结束了")
        return string.format("第 %d 关  要记 %d 个  %s", round, #seq, st),
            string.format("用时 %s / 最好 第 %d 关", T.mmss(elapsed), best)
    end

    -- 外壳切页时问一句"这一局结束了没"：结束了就把底部提示换成"按重玩再来一盘"
    o.is_over = function(self) return done end

    o.restart = function(self) new_game() end

    new_game()
    return o
end

return M
