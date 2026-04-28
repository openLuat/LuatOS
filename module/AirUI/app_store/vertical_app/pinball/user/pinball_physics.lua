--[[
@module  pinball_physics
@summary 2D 弹球：圆与线段、圆与圆、可摆动挡板（角度插值）
]]

local M = {}

-- 逻辑坐标为像素，速度单位 px/s
local MAX_SPEED = 780

local function hypot(ax, ay)
    local d = math.sqrt(ax * ax + ay * ay)
    if d < 1e-12 then
        return 0
    end
    return d
end

local function closest_on_seg(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local l2 = dx * dx + dy * dy
    if l2 < 1e-10 then
        return x1, y1
    end
    local t = ((px - x1) * dx + (py - y1) * dy) / l2
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end
    return x1 + t * dx, y1 + t * dy
end

--- @param ball { x, y, vx, vy, r }
--- @return hit boolean
function M.resolve_segment_ball(ball, x1, y1, x2, y2, restitution)
    local bx, by, br = ball.x, ball.y, ball.r
    local cx, cy = closest_on_seg(bx, by, x1, y1, x2, y2)
    local ddx, ddy = bx - cx, by - cy
    local dist = hypot(ddx, ddy)
    if dist >= br or dist < 1e-8 then
        return false
    end
    local nx = ddx / dist
    local ny = ddy / dist
    local overlap = br - dist
    ball.x = ball.x + nx * overlap
    ball.y = ball.y + ny * overlap
    local vn = ball.vx * nx + ball.vy * ny
    if vn < 0 then
        local r = restitution or 0.75
        ball.vx = ball.vx - (1 + r) * vn * nx
        ball.vy = ball.vy - (1 + r) * vn * ny
    end
    return true
end

--- bumper: { cx, cy, r, points? }
function M.resolve_bumper_ball(ball, bumper, restitution)
    local dx = ball.x - bumper.cx
    local dy = ball.y - bumper.cy
    local dist = hypot(dx, dy)
    local min_d = bumper.r + ball.r
    if dist >= min_d or dist < 1e-8 then
        return false
    end
    local nx = dx / dist
    local ny = dy / dist
    local overlap = min_d - dist
    ball.x = ball.x + nx * overlap
    ball.y = ball.y + ny * overlap
    local vn = ball.vx * nx + ball.vy * ny
    if vn < 0 then
        local r = restitution or 1.12
        ball.vx = ball.vx - (1 + r) * vn * nx
        ball.vy = ball.vy - (1 + r) * vn * ny
    end
    return true
end

--- flipper: { ox, oy, L, ang, a_rest, a_hit, restitution? }
--- pressed=true 摆向 a_hit（抬起击打）；false 摆回 a_rest（放下）
function M.update_flipper_angle(f, dt, pressed)
    local target = pressed and f.a_hit or f.a_rest
    -- 按下时较快上摆，松开时略慢落回（更像释放后落下）
    local rate = pressed and 40 or 28
    local k = rate * dt
    if k > 1 then
        k = 1
    end
    f.ang = f.ang + (target - f.ang) * k
end

function M.flipper_segment(f)
    local ex = f.ox + f.L * math.cos(f.ang)
    local ey = f.oy + f.L * math.sin(f.ang)
    return f.ox, f.oy, ex, ey
end

function M.clamp_speed(ball)
    local sp = hypot(ball.vx, ball.vy)
    if sp > MAX_SPEED then
        local m = MAX_SPEED / sp
        ball.vx = ball.vx * m
        ball.vy = ball.vy * m
    end
end

--- 单个子步：重力、积分、多次解析碰撞
--- @param world { ball, gravity, segments, bumpers, flippers, bumper_cd }
--- @return score_add number
function M.substep(world, dt, left_down, right_down)
    local phys = M
    local b = world.ball
    local score_add = 0

    local fl = world.flippers

    b.vy = b.vy + world.gravity * dt
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt

    local flipper_kick = false
    for _ = 1, 6 do
        local any = false
        for _, seg in ipairs(world.segments) do
            if phys.resolve_segment_ball(b, seg.x1, seg.y1, seg.x2, seg.y2, seg.rest) then
                any = true
            end
        end
        if fl then
            for fi, f in ipairs(fl) do
                local x1, y1, x2, y2 = phys.flipper_segment(f)
                local pressed = (fi == 1 and left_down) or (fi == 2 and right_down)
                if phys.resolve_segment_ball(b, x1, y1, x2, y2, f.restitution) then
                    any = true
                    if pressed and not flipper_kick then
                        flipper_kick = true
                        b.vy = b.vy - 220
                        if fi == 1 then
                            b.vx = b.vx + 95
                        else
                            b.vx = b.vx - 95
                        end
                    end
                end
            end
        end
        if not any then
            break
        end
    end

    for _ = 1, 2 do
        for i, bump in ipairs(world.bumpers) do
            if phys.resolve_bumper_ball(b, bump, bump.restitution or 1.12) then
                world.bumper_cd[i] = world.bumper_cd[i] or 0
                if world.bumper_cd[i] <= 0 then
                    score_add = score_add + (bump.points or 120)
                    world.bumper_cd[i] = 22
                end
            end
        end
    end

    phys.clamp_speed(b)
    return score_add
end

return M
