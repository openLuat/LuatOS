--[[
@module  view_stardust
@summary AURORA UI - 页面 4「星尘」：触摸光绘粒子场
@version 1.0
@date    2026.10.22
@author  江访

=== 视觉效果 ===
一个中心引力 + 切向涡流的粒子场：粒子被吸入中心的同量绕心旋转，
形成漩涡星云；手指在左半屏划动会在触点喷出高速粒子，把星云"搅散"，
松手后粒子重新被涡流捕获。每颗粒子都带一条沿速度反方向的拖尾线段。

=== 这是本工程唯一"手上的东西" ===
前面三个页面是"看"的，这一页是"玩"的：
airui.touch_subscribe 拿到的是原始触点，本页把触点当作粒子发射器；
UI Store 里 FactoryTwin 的手势只用来开抽屉，PetPark 的命中检测只用来选中宠物，
没有一页把触摸变成内容本身。

=== 预算 ===
最多 140 颗粒子，每颗 1 个圆 + 3 个线段（只有高速粒子才画拖尾），
实测稳定在 110~150 个图元之间；粒子数是硬上限，不会因为用户乱划而爆表。
]]
local fx = require "fx"

local M = {
    id = "stardust",
    name = "星尘",
    en = "STARDUST",
    desc = "触摸光绘  涡流粒子场",
}

local MAXP    = 110
local GRAV    = 78        -- 向心加速度（px/s²）
local SWIRL   = 118       -- 切向加速度（px/s²）
local DRAG    = 0.986     -- 每帧阻尼
local LIFE_D  = 0.30      -- 每秒衰减的生命值（1 / LIFE_D ≈ 3.3 秒）

function M.build(parent, W, H, card)
    local o = {
        w = W, h = H,
        pool = fx.pool(),
        ppool = fx.pool(),
        px = {}, py = {}, vx = {}, vy = {},
        life = {}, hue = {}, sz = {},
        alive = {},
        cursor = 1, count = 0,
        swirl = true, trail = true,
        emit_acc = 0, hue0 = 188,
    }
    o.cx, o.cy = W * 0.5, H * 0.5
    for i = 1, MAXP do
        o.px[i], o.py[i], o.vx[i], o.vy[i] = 0, 0, 0, 0
        o.life[i], o.hue[i], o.sz[i] = 0, 0, 1
        o.alive[i] = false
    end

    o.shape = airui.shape({
        parent = parent, x = 0, y = 0, w = W, h = H, items = {},
    })

    if card then
        o.c1 = card(1, "粒子数", 0x22E6FF, "0 / " .. MAXP, "触摸喷射  自动回收")
        o.c2 = card(2, "涡流引力", 0x2BE59D, "开启", "关闭后粒子自由漂移")
        o.c3 = card(3, "粒子拖尾", 0xFF3D9A, "开启", "高速粒子绘制速度尾迹")

        o.sw1 = airui.switch({
            parent = o.c2.root, x = o.c2.w - 88, y = 44, w = 66, h = 34,
            checked = true, style = "success",
            on_change = function(obj)
                local ok, st = pcall(function() return obj:get_state() end)
                if ok then o.swirl = st and true or false end
            end,
        })
        o.sw2 = airui.switch({
            parent = o.c3.root, x = o.c3.w - 88, y = 44, w = 66, h = 34,
            checked = true, style = "success",
            on_change = function(obj)
                local ok, st = pcall(function() return obj:get_state() end)
                if ok then o.trail = st and true or false end
            end,
        })
        o.btn = airui.button({
            parent = o.c1.root, x = 18, y = 62, w = 108, h = 34,
            text = "清空", font_size = 15,
            style = {
                bg_color = 0x12213A, bg_opa = 255, text_color = 0x9FE7FF,
                radius = 10, border_width = 1, border_color = 0x24405F,
                pressed_bg_color = 0x22E6FF, pressed_text_color = 0x04121C,
            },
            on_click = function() M.clear(o) end,
        })
        o.txt_n = "0 / " .. MAXP
    end
    return o
end

-- ==================== 粒子池 ====================
--[[取一个空槽：从游标位置循环找
不用"数组末尾压缩"的做法，是因为压缩会把正在飞的粒子下标整体搬家，
拖尾线段会瞬间跳一下；固定槽 + alive 标记最省心。]]
local function alloc(o)
    for _ = 1, MAXP do
        local i = o.cursor
        o.cursor = i % MAXP + 1
        if not o.alive[i] then
            o.alive[i] = true
            o.count = o.count + 1
            return i
        end
    end
    return nil
end

function M.clear(o)
    for i = 1, MAXP do o.alive[i] = false end
    o.count = 0
    log.info("stardust", "粒子场已清空")
end

--[[在 (x,y) 喷一颗粒子
@param number sp 初速度（px/s）
@param number dir 方向（弧度）；nil 表示随机
]]
local function emit(o, x, y, sp, dir)
    local i = alloc(o)
    if not i then return end
    local rnd = math.random()
    if not dir then dir = rnd * fx.TAU end
    o.px[i], o.py[i] = x, y
    o.vx[i] = math.cos(dir) * sp
    o.vy[i] = math.sin(dir) * sp
    o.life[i] = 0.75 + math.random() * 0.25
    o.sz[i] = 0.8 + math.random() * 1.5
    -- 色相跟着触点位置走：左边偏青、右边偏紫，划过时形成流光
    o.hue[i] = o.hue0 + (x / o.w) * 90 + (math.random() - 0.5) * 26
end

-- ==================== 每帧绘制 ====================
function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    local cx, cy = o.cx, o.cy
    P:reset()

    o.hue0 = 176 + 40 * fx.noise1(t * 0.25)

    -- ---- 环境发射器：无人操作时也一直有粒子流动 ----
    o.emit_acc = o.emit_acc + dt
    if o.emit_acc >= 0.12 then
        o.emit_acc = 0
        local a = t * 0.85
        local rr = math.min(W, H) * 0.30
        emit(o, cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.62, 26, a + math.pi / 2)
    end

    -- ---- 涡流圈（背景装饰，先画） ----
    P:ring(cx, cy, math.floor(math.min(W, H) * 0.30), 0x1B2C48, 1, 110)
    P:ring(cx, cy, math.floor(math.min(W, H) * 0.30 * 0.62), 0x16294A, 1, 90)
    for k = 1, 3 do
        local a = t * (0.55 + k * 0.18) + k * 2.1
        local rr = math.min(W, H) * (0.16 + k * 0.05)
        P:dot(cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.7,
            2, 0x5FE6FF, 90)
    end

    -- ---- 物理 + 绘制 ----
    local px, py, vx, vy = o.px, o.py, o.vx, o.vy
    local life, hue, sz, alive = o.life, o.hue, o.sz, o.alive
    local drag = DRAG ^ (dt * 60)
    local live = 0
    for i = 1, MAXP do
        if alive[i] then
            local x, y = px[i], py[i]
            local dx, dy = cx - x, cy - y
            local d = math.sqrt(dx * dx + dy * dy) + 1
            local nx, ny = dx / d, dy / d

            if o.swirl then
                -- 向心 + 切向（切向取法向旋转 90°），越靠近中心旋转越快
                local g = GRAV * (0.45 + 0.55 * fx.clamp(d / 260, 0, 1))
                local s = SWIRL * (0.55 + 0.85 * fx.clamp(1 - d / 300, 0, 1))
                vx[i] = (vx[i] + (nx * g - ny * s) * dt) * drag
                vy[i] = (vy[i] + (ny * g + nx * s) * dt) * drag
            else
                vx[i] = vx[i] * drag
                vy[i] = vy[i] * drag
            end

            px[i] = x + vx[i] * dt
            py[i] = y + vy[i] * dt
            life[i] = life[i] - dt * LIFE_D
            if life[i] <= 0 then
                alive[i] = false
                o.count = o.count - 1
            else
                live = live + 1
                local lf = life[i]
                local col = fx.hsl(hue[i], 0.95, 0.40 + 0.28 * lf)
                -- 拖尾：沿速度反方向拉一小段（长度与速度成正比）
                local speed = math.sqrt(vx[i] * vx[i] + vy[i] * vy[i])
                if o.trail and speed > 40 then
                    local k = 0.030
                    P:line(px[i], py[i], px[i] - vx[i] * k, py[i] - vy[i] * k,
                        col, 1, math.floor(60 * lf))
                end
                -- 粒子本体：生命末尾收缩成一个小点
                P:dot(px[i], py[i], sz[i] * (0.6 + 1.6 * lf), col,
                    math.floor(90 + 150 * lf))
                if lf > 0.93 and i % 2 == 0 then
                    -- 刚喷出的粒子带一点白芯，只给一半粒子画，省图元
                    P:dot(px[i], py[i], 1, 0xFFFFFF, math.floor(200 * lf))
                end
            end
        end
    end
    o.live = live

    -- ---- 中心核 ----
    local pulse = 0.5 + 0.5 * math.sin(t * 3.1)
    P:dot(cx, cy, math.floor(10 + 6 * pulse), 0x9FF3FF, 30)
    P:dot(cx, cy, 3, 0xFFFFFF, 230)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

-- ==================== 右侧卡片（5Hz） ====================
function M.panel(o, t, dt)
    if not o.c1 then return end
    local P = o.ppool
    P:reset()
    fx.meter(P, 140, 52, o.c1.w - 158, 8, o.count / MAXP, 0x22E6FF)
    P:finish()
    o.c1.shape:set_items(P.items)

    -- 卡 2 / 卡 3 只画一条分隔线，控件本体是原生 switch
    P:reset()
    P:line(18, 92, o.c2.w - 18, 92, 0x1B2C48, 1, 120)
    P:finish()
    o.c2.shape:set_items(P.items)

    P:reset()
    P:line(18, 92, o.c3.w - 18, 92, 0x1B2C48, 1, 120)
    P:finish()
    o.c3.shape:set_items(P.items)

    local v = o.count .. " / " .. MAXP
    if v ~= o.txt_n then
        o.txt_n = v
        o.c1.value:set_text(v)
    end
end

-- ==================== 触摸：触点即发射器 ====================
function M.touch(o, ev, x, y)
    if ev == "down" then
        for _ = 1, 10 do emit(o, x, y, 60 + math.random() * 90) end
        o.last_x, o.last_y = x, y
        return true
    elseif ev == "move" then
        local lx, ly = o.last_x or x, o.last_y or y
        -- 沿上一段轨迹插值补点：触点事件是离散的，快划时直接喷会断成一串点
        local dx, dy = x - lx, y - ly
        local dist = math.sqrt(dx * dx + dy * dy)
        local steps = math.floor(dist / 7) + 1
        if steps > 8 then steps = 8 end
        for s = 1, steps do
            local fx_ = lx + dx * s / steps
            local fy_ = ly + dy * s / steps
            emit(o, fx_, fy_, 40 + math.random() * 70)
        end
        o.last_x, o.last_y = x, y
        return true
    elseif ev == "up" then
        o.last_x, o.last_y = nil, nil
        return true
    end
    return false
end

return M
