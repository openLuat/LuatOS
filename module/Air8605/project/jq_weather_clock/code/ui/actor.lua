--[[
@module  actor
@summary 画面主体：骑自行车的人 / 小猫 / 小狗 + 小窝（雨雪与夜里会躲进窝）
@version 1.0
@date    2026.11.08

=== 三种形象 ===
cyclist : 一直蹬车向前（车轮转、腿踩踏板、地面往后退，做出"一直在前进"的错觉）
cat/dog : 在草地上慢慢晃悠；下雨/下雪/天黑 → 自己走回小窝，进窝后只在窗户里露个小脑袋
点击画面中间的角色即可循环切换（ui_main 负责判定点击）。

=== 为什么全部用 shape 画 ===
没有素材依赖：不占文件系统、不进图片解码缓存、换配色只改常量。
代价是每帧要重算几十个图元 —— 都塞进同一个 shape 里，一帧只提交一次。
]]

local draw = require "draw"
local conf = require "conf"

local M = {}

M.KINDS = conf.actor.order or { "cyclist", "cat", "dog", "rabbit" }
M.NAMES = { cyclist = "骑行", cat = "小猫", dog = "小狗", rabbit = "兔子" }

-- ==================== 配色 ====================
local C = {
    tire      = 0x1B2333,
    rim       = 0x6B7793,
    spoke     = 0x9AA6C2,
    frame     = 0xE0463C,
    frame_dk  = 0xB8362E,
    saddle    = 0x232A3C,
    shirt     = 0xF2544B,
    shirt_dk  = 0xC43F38,
    -- 裤子上过一版 0x2C3E5C，夜里整个人像"没腿"：深蓝压在深蓝天上是糊的。
    -- 提到 0x35507A 后夜景也能看出踩踏动作。
    pants     = 0x35507A,
    pants_dk  = 0x263A5C,
    skin      = 0xF3CBA9,
    helmet    = 0xF2F5FA,
    helmet_dk = 0xCAD3E2,
    pack      = 0xE8B84B,
    cat       = 0xF0A24B,
    cat_dk    = 0xD07F32,
    cat_belly = 0xF8D9B0,
    dog       = 0xC08B5E,
    dog_dk    = 0x91623C,
    dog_belly = 0xEBCBA8,
    -- 兔子别用纯白：压在浅蓝天空和青绿草地上会糊掉一圈，改用带蓝调的浅灰白，
    -- 肚子再提亮一层，才有"白兔"的体积感
    rabbit      = 0xE2E5F0,
    rabbit_pale = 0xF7F8FD,
    rabbit_dk   = 0xA9AEC4,
    rabbit_pink = 0xF2A9B8,
    -- 兔子的描边色：参考图里整只兔子勾了一圈深边，压在草地/天空上轮廓才立得住。
    -- 不用纯黑：纯黑在浅蓝天空上太扎眼，深蓝灰跟阴影一个体系
    rabbit_line = 0x5F6577,
    house     = 0x9A6B44,
    house_dk  = 0x6B4526,
    roof      = 0xD9613F,
    window_off= 0x3A4A62,
    window_on = 0xFFD27A,
    shadow    = 0x0A1420,
}

-- ==================== 兔子的蹦跳节奏 ====================

--[[兔子是"蹦一下、歇一会儿"，不是匀速连跳（一直蹦看着累）
一个周期 = 蹦 620ms + 站着歇 900ms：
  蹦的时候：身体升降、腿伸展、耳朵后飘，**位移也只发生在这段**；
  歇的时候：脚刹住，只有一点呼吸起伏和微蹲。
位移必须跟着节奏走 —— 否则身体停着、位置还在往前挪，就成了"站着滑行"，
比连跳更怪。只在 40% 的时间里前进，所以跳跃段的速度要抬上去，平均速度才不掉。
]]
local HOP_MS    = 620    -- 一次蹦跳（腾空 + 落地缓冲）的时长
local HOP_AIR   = 0.66   -- 其中腾空占的比例，余下是落地缓冲
local HOP_REST  = 900    -- 蹦完站着歇多久
local HOP_CYCLE = HOP_MS + HOP_REST
local HOP_BOOST = 1.6    -- 跳跃段的位移速度倍数

-- ==================== 状态 ====================

function M.new(kind, x)
    local a = {
        kind = kind or "cyclist",
        x = x or conf.actor.x,
        tx = x or conf.actor.x,
        phase = 0,
        wheel = 0,       -- 车轮角（弧度）
        crank = 0,       -- 曲柄角（弧度）
        state = "out",   -- out | to_home | home | to_play
        head = 0,        -- 小动物探头相位
        face = 1,        -- 1 朝右 / -1 朝左（走动时按实际位移翻转）
        moving = false,  -- 这一帧有没有真的挪动（兔子靠它决定蹦不蹦）
    }
    return a
end

function M.next_kind(kind)
    local list = M.KINDS
    for i = 1, #list do
        if list[i] == kind then
            return list[i % #list + 1]
        end
    end
    return list[1]
end

local function approach(cur, target, step)
    if cur < target - step then return cur + step end
    if cur > target + step then return cur - step end
    return target
end

local function wander_target(a)
    local lo, hi = conf.actor.pet_min_x, conf.actor.pet_max_x
    -- 用相位做确定性的"随机"：同一台机器每次走位一致，方便复现
    local k = math.sin(a.phase / 3700 + (a.kind == "cat" and 0 or 1.7))
    return math.floor(lo + (hi - lo) * (0.5 + 0.45 * k))
end

--- 每帧推进角色状态
---@param a table 角色
---@param dt number 帧间隔（ms）
---@param e table 环境（night / is_rain / is_snow）
function M.update(a, dt, e)
    local dt_s = dt / 1000
    local x0 = a.x
    a.phase = a.phase + dt

    if a.kind == "cyclist" then
        --[[车轮与地面的速度要能对上：车轮半径 46 → 周长 289px，
        3.2 rad/s ≈ 0.51 圈/秒 ≈ 147 px/秒。scene 里地面参照物就用 147 px/秒后退，
        两边对不上时看起来就是"车轮在转、车没走"（脚踏车原地踩）。]]
        a.wheel = (a.wheel + dt_s * 3.2) % (math.pi * 2)
        a.crank = (a.crank + dt_s * 1.6) % (math.pi * 2)
        a.moving = true      -- 骑车人一直在前进，留给后面的形象切换用
        return
    end

    -- 小动物：车轮不重要，用走路相位
    a.wheel = (a.wheel + dt_s * 5.0) % (math.pi * 2)
    a.crank = a.wheel

    local house_x = conf.actor.house_x - 14
    local shelter = e.night or e.is_rain or e.is_snow

    if shelter then
        if a.state ~= "home" and a.state ~= "to_home" then
            a.state = "to_home"
            a.tx = house_x
        end
    else
        if a.state == "home" or a.state == "to_home" then
            a.state = "to_play"
            a.tx = wander_target(a)
        end
    end

    --[[走动 + 转身
    角色是按"朝右"画的。以前只改 x 不改朝向，往回走时就成了"面朝前、身体倒着滑"。
    这里按实际位移翻转 face，绘制时把整只动物水平镜像（见 mirror）。
    ]]
    local function move(tx, speed)
        local before = a.x
        local step = speed * dt_s
        if a.kind == "rabbit" then
            -- 兔子只在蹦跳那一小段前进，落地歇着的时候脚是刹住的（见文件头 HOP_CYCLE）
            step = ((a.phase % HOP_CYCLE) < HOP_MS) and (step * HOP_BOOST) or 0
        end
        a.x = approach(a.x, tx, step)
        if a.x > before + 0.01 then
            a.face = 1
        elseif a.x < before - 0.01 then
            a.face = -1
        end
        return a.x
    end

    if a.state == "to_home" then
        if math.abs(move(house_x, 86) - house_x) <= 2 then
            a.state = "home"
            a.head = 0
        end
    elseif a.state == "to_play" then
        if math.abs(move(a.tx, 62) - a.tx) <= 2 then a.state = "out" end
    elseif a.state == "out" then
        if math.abs(move(a.tx, 30) - a.tx) <= 3 then a.tx = wander_target(a) end
    end

    --[[这一帧到底挪没挪：兔子靠它决定是"蹦"还是"站着呼吸"。
    用位移而不是速度/状态来判断，因为到点的那一帧 approach 会正好落在目标上，
    状态还停在 out，但身体已经不动了。]]
    a.moving = math.abs(a.x - x0) > 0.05
end

--- 角色是否在小窝里（隐藏本体）
function M.is_home(a)
    return a.kind ~= "cyclist" and a.state == "home"
end

--[[水平镜像包装
shape 图元没有变换矩阵，但小动物只需要"左右翻转"。这里包一层假的池子：
所有坐标进来先按 x = 2*cx - x 镜像再转给真池子，绘制函数一行都不用改。
弧线的角度也要镜像：关于竖轴对称时 a → 180 - a，顺时针区间 [a0,a1] → [180-a1, 180-a0]。
]]
local function mirror(P, cx, dir)
    if dir >= 0 then return P end
    local M_ = {}
    local c2 = cx * 2
    function M_:line(x1, y1, x2, y2, c, w, o, r) P:line(c2 - x1, y1, c2 - x2, y2, c, w, o, r) end
    function M_:box(x, y, w, h, c, o, rad) P:box(c2 - x - w, y, w, h, c, o, rad) end
    function M_:dot(x, y, r, c, o) P:dot(c2 - x, y, r, c, o) end
    function M_:ring(x, y, r, c, w, o) P:ring(c2 - x, y, r, c, w, o) end
    function M_:ellipse(x, y, rx, ry, c, w, o, f, fo, s)
        P:ellipse(c2 - x, y, rx, ry, c, w, o, f, fo, s)
    end

    function M_:arc(x, y, r, a0, a1, c, w, o, rd)
        local span = a1 - a0
        local s = (180 - a1) % 360
        P:arc(c2 - x, y, r, s, s + span, c, w, o, rd)
    end

    function M_:arc_poly(x, y, r, a0, a1, c, w, o, st)
        P:arc_poly(c2 - x, y, r, 180 - a1, 180 - a0, c, w, o, st)
    end
    return M_
end

-- ==================== 骑车人 ====================

local function draw_cyclist(P, a, gy)
    local x = a.x
    local t = a.phase
    local bob = math.sin(a.wheel * 2) * 2

    -- 地面投影
    P:ellipse(x, gy + 4, 100, 10, C.shadow, 0, 0, true, 70)

    local wheel_r = 46
    local wy = gy - wheel_r
    local rear_x, front_x = x - 74, x + 74

    -- 车轮
    for _, cx in ipairs({ rear_x, front_x }) do
        P:ring(cx, wy, wheel_r, C.tire, 9, 255)
        P:ring(cx, wy, wheel_r - 7, C.rim, 2, 200)
        for s = 0, 5 do
            local ang = a.wheel + s * math.pi / 3
            P:line(cx, wy, cx + math.cos(ang) * (wheel_r - 12), wy + math.sin(ang) * (wheel_r - 12),
                C.spoke, 2, 170)
        end
        P:dot(cx, wy, 4, 0x2B3550, 255)
    end

    -- 车架
    local bb = { x + 8, gy - 58 }
    local seat = { x - 32, gy - 118 }
    local head = { x + 46, gy - 114 }
    local rear_hub = { rear_x, wy }
    local front_hub = { front_x, wy }

    P:line(rear_hub[1], rear_hub[2], bb[1], bb[2], C.frame_dk, 7, 255, true)
    P:line(bb[1], bb[2], seat[1], seat[2], C.frame, 8, 255, true)
    P:line(seat[1], seat[2], rear_hub[1], rear_hub[2], C.frame, 6, 255, true)
    P:line(bb[1], bb[2], head[1], head[2], C.frame, 8, 255, true)
    P:line(seat[1], seat[2], head[1], head[2], C.frame, 7, 255, true)
    P:line(head[1], head[2], front_hub[1], front_hub[2], C.frame, 7, 255, true)

    -- 车座 + 车把
    P:box(seat[1] - 20, seat[2] - 10, 36, 9, C.saddle, 255, 4)
    P:line(head[1], head[2], x + 66, gy - 132, C.saddle, 6, 255, true)
    P:line(x + 56, gy - 134, x + 76, gy - 130, C.saddle, 5, 255, true)

    -- 曲柄与两个踏板
    local cr = 18
    local p1x, p1y = bb[1] + math.cos(a.crank) * cr, bb[2] + math.sin(a.crank) * cr
    local p2x, p2y = bb[1] - math.cos(a.crank) * cr, bb[2] - math.sin(a.crank) * cr
    P:line(bb[1], bb[2], p1x, p1y, C.rim, 4, 220, true)
    P:line(bb[1], bb[2], p2x, p2y, C.rim, 4, 220, true)
    P:dot(bb[1], bb[2], 7, 0xC9D2E4, 255)

    -- 骑手关键点
    local hip = { x - 20, gy - 148 + bob }
    local shoulder = { x + 12, gy - 202 + bob }
    local headc = { x + 26, gy - 220 + bob }

    -- 远侧的腿（先画，被车架/身体压住）
    P:line(hip[1] - 6, hip[2], (hip[1] + p2x) / 2 + 14, (hip[2] + p2y) / 2, C.pants_dk, 11, 255, true)
    P:line((hip[1] + p2x) / 2 + 14, (hip[2] + p2y) / 2, p2x, p2y, C.pants_dk, 10, 255, true)
    P:dot(p2x, p2y, 5, 0x1B2333, 255)

    -- 背包
    P:box(x - 42, gy - 208 + bob, 26, 44, C.pack, 255, 11)

    -- 躯干
    P:line(hip[1], hip[2], shoulder[1], shoulder[2], C.shirt, 19, 255, true)

    -- 头 + 头盔 + 护目镜
    P:dot(headc[1], headc[2], 15, C.skin, 255)
    -- 头盔半径比头大一点、带窄一点：否则整颗头被白色包住，看不出脸
    P:arc(headc[1], headc[2], 17, 178, 362, C.helmet, 10, 255, false)
    P:line(headc[1] - 16, headc[2] - 2, headc[1] + 18, headc[2] - 3, C.helmet_dk, 4, 255, true)
    P:line(headc[1] + 2, headc[2] + 1, headc[1] + 14, headc[2] + 1, 0x24304C, 4, 235, true)

    -- 手臂（肩 → 肘 → 手把）
    P:line(shoulder[1], shoulder[2], x + 42, gy - 164 + bob, C.shirt_dk, 10, 255, true)
    P:line(x + 42, gy - 164 + bob, x + 66, gy - 133 + bob, C.skin, 8, 255, true)

    -- 近侧的腿（压在最上面）
    P:line(hip[1], hip[2], (hip[1] + p1x) / 2 + 16, (hip[2] + p1y) / 2, C.pants, 12, 255, true)
    P:line((hip[1] + p1x) / 2 + 16, (hip[2] + p1y) / 2, p1x, p1y, C.pants, 11, 255, true)
    P:dot(p1x, p1y, 5, 0x2B3550, 255)

    -- 上衣下摆的一点层次
    P:line(hip[1] + 2, hip[2] - 26, hip[1] + 16, hip[2] - 26, C.shirt_dk, 4, 200, true)
end

-- ==================== 小猫 / 小狗 ====================

local function draw_legs(P, x, by, gy, ph, color, w)
    local swing = math.sin(ph) * 6
    P:line(x - 22, by + 8, x - 22 + swing, gy - 2, color, w, 255, true)
    P:line(x - 6, by + 10, x - 6 - swing, gy - 2, color, w, 255, true)
    P:line(x + 12, by + 10, x + 12 + swing, gy - 2, color, w, 255, true)
    P:line(x + 26, by + 8, x + 26 - swing, gy - 2, color, w, 255, true)
end

local function draw_cat(P, a, gy)
    local x, t = a.x, a.phase
    local bob = math.sin(t / 190) * 2
    local by = gy - 30 + bob
    local ph = t / 130

    P:ellipse(x, gy + 2, 44, 7, C.shadow, 0, 0, true, 55)

    -- 尾巴（先画，压在身体下）
    local wag = math.sin(t / 260) * 22
    P:arc_poly(x - 34, by - 16, 24, 150 + wag, 268 + wag, C.cat_dk, 7, 255, 14)

    draw_legs(P, x, by, gy, ph, C.cat_dk, 7)

    -- 身体
    P:ellipse(x, by, 36, 21, C.cat, 0, 0, true, 255)
    P:ellipse(x + 6, by + 8, 24, 11, C.cat_belly, 0, 0, true, 190)
    -- 背上的花纹
    P:line(x - 16, by - 16, x - 8, by - 9, C.cat_dk, 4, 220, true)
    P:line(x - 2, by - 19, x + 6, by - 12, C.cat_dk, 4, 220, true)

    -- 头
    local hx, hy = x + 30, by - 20
    P:dot(hx, hy, 19, C.cat, 255)
    -- 耳朵（两条粗线拼三角）
    P:line(hx - 14, hy - 12, hx - 17, hy - 30, C.cat, 8, 255, true)
    P:line(hx - 17, hy - 30, hx - 1, hy - 17, C.cat, 8, 255, true)
    P:line(hx + 6, hy - 17, hx + 18, hy - 28, C.cat, 8, 255, true)
    P:line(hx + 18, hy - 28, hx + 20, hy - 10, C.cat, 8, 255, true)
    -- 眼睛 + 鼻子
    P:dot(hx + 2, hy - 3, 3, 0x2A3242, 255)
    P:dot(hx + 13, hy - 3, 3, 0x2A3242, 255)
    P:dot(hx + 8, hy + 5, 2, 0xE88A8A, 255)
    -- 胡须
    P:line(hx + 12, hy + 2, hx + 26, hy - 1, 0xFFFFFF, 1, 140, false)
    P:line(hx + 12, hy + 5, hx + 26, hy + 7, 0xFFFFFF, 1, 140, false)
end

local function draw_dog(P, a, gy)
    local x, t = a.x, a.phase
    local bob = math.sin(t / 170) * 2
    local by = gy - 33 + bob
    local ph = t / 120

    P:ellipse(x, gy + 2, 48, 8, C.shadow, 0, 0, true, 55)

    -- 尾巴（上翘、摇）：两段折线 + 尾尖，单段直线看着像插了根棍子
    local wag = math.sin(t / 150) * 16
    local tx, ty = x - 52, by - 26 + wag
    P:line(x - 38, by - 10, x - 46, by - 20 + wag * 0.4, C.dog_dk, 8, 255, true)
    P:line(x - 46, by - 20 + wag * 0.4, tx, ty, C.dog_dk, 7, 255, true)
    P:dot(tx, ty, 4, C.dog_dk, 255)

    draw_legs(P, x, by, gy, ph, C.dog_dk, 8)

    P:ellipse(x, by, 40, 22, C.dog, 0, 0, true, 255)
    P:ellipse(x + 8, by + 9, 26, 11, C.dog_belly, 0, 0, true, 170)

    -- 头
    local hx, hy = x + 34, by - 22
    P:dot(hx, hy, 20, C.dog, 255)
    -- 下垂的耳朵
    P:ellipse(hx - 15, hy - 2, 8, 15, C.dog_dk, 0, 0, true, 255)
    P:ellipse(hx + 14, hy - 4, 7, 13, C.dog_dk, 0, 0, true, 255)
    -- 嘴
    P:ellipse(hx + 12, hy + 7, 10, 7, C.dog_belly, 0, 0, true, 255)
    P:dot(hx + 19, hy + 5, 3, 0x2A3242, 255)
    -- 眼睛
    P:dot(hx + 4, hy - 3, 3, 0x2A3242, 255)
    P:dot(hx + 14, hy - 4, 3, 0x2A3242, 255)
end

-- ==================== 兔子 ====================

--[[兔子：蹦一下、歇一会儿地往前（造型照野兔奔跑的样子改过一版）
参考真实野兔：
· 身体前低后高：胸在下方、臀在上方，整个身子是往前倾的
· 耳朵超长、贴着背往后飘 —— 竖起来的耳朵没有速度感
· 后腿极粗（跳跃主力）、前腿细，腾空时前腿收、后腿向后甩
· 全身勾一圈深色描边，压在草地和天空上轮廓才立得住

身体不用椭圆拼：椭圆既不能倾斜、两块拼起来还会在交界处咬出凹角，
改用"圆头粗线"拉出来的胶囊（臀粗、胸细），天然平滑且自带倾角。

q = 腾空程度 0~1，sq = 落地压缩量；两套姿态之间按 q 插值，起跳/落地不会跳帧。
周期、休息时长、速度补偿都在文件头的 HOP_* 常量里，这里只负责把相位翻译成姿态。
]]

--- 带描边的圆头线（腿、耳朵）：先画粗的深色，再叠细的浅色
--- 描边只宽 3px：兔子整体才 70x75，边再粗就变成"勾线涂色"的贴纸了
local function limb(P, x1, y1, x2, y2, w, color)
    P:line(x1, y1, x2, y2, C.rabbit_line, w + 3, 255, true)
    P:line(x1, y1, x2, y2, color, w, 255, true)
end

--- 带描边的实心椭圆（大腿、头）
local function blob(P, cx, cy, rx, ry, color)
    P:ellipse(cx, cy, rx + 2, ry + 2, C.rabbit_line, 0, 0, true, 255)
    P:ellipse(cx, cy, rx, ry, color, 0, 0, true, 255)
end

local function draw_rabbit(P, a, gy)
    local x, t = a.x, a.phase

    -- 相位落在周期的哪一段：前 HOP_MS 是蹦，之后是站着歇
    local cy = t % HOP_CYCLE
    local hopping = a.moving and cy < HOP_MS
    local hu = cy / HOP_MS

    local q, sq = 0, 0
    if hopping then
        if hu < HOP_AIR then
            q = math.sin(math.pi * hu / HOP_AIR)                     -- 0 → 1 → 0
        else
            sq = math.sin(math.pi * (hu - HOP_AIR) / (1 - HOP_AIR)) * 4
        end
    end

    --[[椭圆没法旋转，俯仰角只能靠"整个头上下错位"假造：
    起跳瞬间抬头、落下时低头，比笔直上下的平移像蹦跳得多。]]
    local pitch = hopping and (-2 * math.cos(math.pi * hu / HOP_AIR)) or 0

    -- 歇着的时候蹲一点、慢慢喘气，比直挺挺站着自然
    local crouch = hopping and 0 or 2.5
    local breathe = hopping and 0 or math.sin(t / 430) * 1.2
    local by = gy - 31 - q * 22 + sq + crouch + breathe   -- 身体中心（抬得高一点，腿才露得出来）

    -- 影子：跳起来要缩小变淡，否则身体腾空了影子还钉在地上
    P:ellipse(x - 4, gy + 2, 36 - q * 14, 6 - q * 3, C.shadow, 0, 0, true, 48 - q * 22)

    -- 四个关键点：臀（最高）/ 腰 / 胸 / 头（最低最前）—— 连起来就是往前倾的身架
    local hpx, hpy = x - 11 - q * 5, by - 6 - q * 2   -- 臀（后端，最高最粗）
    local mpx, mpy = x + 5 + q * 2, by - 1            -- 腰
    local cpx, cpy = x + 17 + q * 4, by + 5           -- 胸（前端，收窄）
    local hx,  hy  = x + 33 + q * 2, by + 1 + pitch   -- 头（压得比背低）

    --[[远侧耳朵（先画，垫在头后面）：短一截、压暗
    有了它，两只耳朵才不是一根棍，耳朵和背之间也才有一层"后面的东西"]]
    P:line(hx - 15, hy - 7, hx - 34, hy - 16 + q * 6, C.rabbit_line, 7, 255, true)
    P:line(hx - 15, hy - 7, hx - 34, hy - 16 + q * 6, C.rabbit_dk, 4, 255, true)

    -- 远侧后腿：整条压暗、错开几像素，两条腿叠着才有前后层次
    local bfx = draw.lerp(x - 20, hpx - 22, q)        -- 后脚落点
    local bfy = draw.lerp(gy - 4, hpy + 12, q)
    limb(P, hpx - 3, hpy + 11, bfx - 5, bfy - 3, 7, C.rabbit_dk)

    -- 上翘的短尾：贴着屁股，别飘在外面像个多余的球
    P:dot(hpx - 16, hpy + 2, 5, C.rabbit_line, 255)
    P:dot(hpx - 16, hpy + 2, 3, C.rabbit_pale, 255)

    --[[身体：用"圆头粗线"拉出来的胶囊，不是椭圆
    椭圆拼两块会在交界处咬出一个凹角（背上像被啃了一口），而且椭圆没法倾斜；
    圆头粗线的两端本来就是半圆，天然平滑，线的角度还正好就是身体的倾角。
    臀 → 腰 → 胸 分成两根不同粗细的线段，前后一样粗会变成一根海豹似的管子。]]
    P:line(hpx, hpy, mpx, mpy, C.rabbit_line, 37, 255, true)
    P:line(mpx, mpy, cpx, cpy, C.rabbit_line, 31, 255, true)
    P:line(hpx, hpy, mpx, mpy, C.rabbit, 33, 255, true)
    P:line(mpx, mpy, cpx, cpy, C.rabbit, 27, 255, true)
    -- 肚子上的亮面（贴地时更明显，腾空时被身体拉平）
    P:ellipse(cpx - 4, cpy + 9, 12, 5, C.rabbit_pale, 0, 0, true, 180 - q * 40)

    --[[近侧后腿：只有小腿 + 脚掌，没有单独的大腿块
    参考图里"大腿"其实就是屁股那半块身体，再画一个带描边的圆会像身上贴了个球。
    贴地时折在肚子下面，腾空时整条向后甩开 —— 起跳蹬出去那一下的余势。
    脚掌不描边、直接用灰的：这么小的圆再勾一圈边就成甜甜圈了。]]
    limb(P, hpx - 2, hpy + 12, bfx, bfy, 9, C.rabbit)
    P:ellipse(bfx, bfy, 8, 5, C.rabbit_dk, 0, 0, true, 255)

    -- 前腿：细，贴地时伸到身前撑住，腾空时缩回腹下
    local shx, shy = cpx + 3, cpy + 10
    local ffx = draw.lerp(x + 28, cpx + 8, q)
    local ffy = draw.lerp(gy - 3, cpy + 13, q)
    limb(P, shx, shy, ffx, ffy, 6, C.rabbit)
    P:ellipse(ffx, ffy, 6, 4, C.rabbit_dk, 0, 0, true, 255)

    --[[近侧耳朵：从头顶往后飘，分两段画（根部宽、耳尖窄）——
    line 是等宽的，一条线拉到耳尖就成了根棍子。
    画在头**前面**（先耳后头）：头会压住耳根，耳朵就是从脑袋后面长出来的；
    反过来先画头再画耳，耳根那圈描边会横切在头顶上，脑袋像被削掉一块。]]
    local erx, ery = hx - 10 - q * 3, hy - 12 + q * 3  -- 整条耳朵随腾空整体后移，不能只甩耳尖（会折成钩子）
    local emx, emy = erx - 17, ery - 13
    local etx, ety = erx - 33, ery - 24
    P:line(erx, ery, emx, emy, C.rabbit_line, 12, 255, true)
    P:line(erx, ery, emx, emy, C.rabbit, 8, 255, true)
    P:line(emx, emy, etx, ety, C.rabbit_line, 9, 255, true)
    P:line(emx, emy, etx, ety, C.rabbit, 5, 255, true)
    -- 内耳粉色：只占耳根到耳尖之间的中段
    P:line(draw.lerp(erx, etx, 0.22), draw.lerp(ery, ety, 0.22),
        draw.lerp(erx, etx, 0.74), draw.lerp(ery, ety, 0.74),
        C.rabbit_pink, 3, 220, true)

    -- 头：比胸口低一点、往前探（最后画，压住耳根）
    blob(P, hx, hy, 14, 14, C.rabbit)

    -- 眼睛 + 鼻子（眼睛朝前看，别太大：参考图里头小、眼睛也小，大眼会变萌系）
    P:dot(hx + 6, hy - 3, 3, 0x2A3242, 255)
    P:dot(hx + 7, hy - 4, 1, 0xFFFFFF, 235)
    P:dot(hx + 12, hy + 4, 2, C.rabbit_pink, 255)
end

-- ==================== 小窝 ====================

function M.draw_house(P, e)
    local hx, gy = conf.actor.house_x, e.ground_y
    local w, h = 132, 96
    local left = hx - w / 2
    local top = gy - h
    local lit = e.night or e.is_rain or e.is_snow

    P:ellipse(hx, gy + 3, 82, 9, C.shadow, 0, 0, true, 55)

    -- 屋顶（人字顶用粗线拼，shape 没有多边形填充）
    P:line(left - 14, top + 4, hx, top - 50, C.roof, 18, 255, true)
    P:line(hx, top - 50, left + w + 14, top + 4, C.roof, 18, 255, true)
    P:box(left - 6, top - 2, w + 12, 8, C.roof, 255, 4)

    -- 墙体
    P:box(left, top, w, h, C.house, 255, 8)
    P:box(left + 6, top + 10, w - 12, h - 16, C.house_dk, 0, 6)

    -- 烟囱
    P:box(left + 34, top - 44, 16, 30, 0xB0754C, 255, 3)

    -- 门
    P:box(hx - 19, gy - 54, 38, 54, C.house_dk, 255, 7)
    P:dot(hx + 12, gy - 28, 3, 0xE8C88B, 255)

    -- 窗（夜里/雨雪天亮起来，外面套一圈暖光）
    local wc = lit and C.window_on or C.window_off
    if lit then
        P:dot(hx + 48, gy - 64, 18, 0xFFD27A, 20)
        P:dot(hx + 48, gy - 64, 14, 0xFFD27A, 26)
    end
    P:box(hx + 32, gy - 78, 32, 28, wc, 255, 5)
    P:line(hx + 48, gy - 78, hx + 48, gy - 50, C.house_dk, 2, 220)
    P:line(hx + 32, gy - 64, hx + 64, gy - 64, C.house_dk, 2, 220)

    -- 窝里的小动物：只在窗户里露个脑袋
    return lit, hx + 48, gy - 64
end

--- 角色探头（在小窝窗户里）
local function draw_peek(P, a, e)
    local lit, wx, wy = M.draw_house(P, e)
    if not lit then return end
    local color = C.dog
    if a.kind == "cat" then
        color = C.cat
    elseif a.kind == "rabbit" then
        color = C.rabbit
    end
    -- 窗户是亮的暖黄，脑袋直接压上去会糊成一片，先垫一圈深色描边
    P:dot(wx, wy + 2, 10, 0x3A2A18, 255)
    P:dot(wx, wy + 2, 8, color, 255)
    if a.kind == "cat" then
        P:line(wx - 6, wy - 4, wx - 8, wy - 12, color, 4, 255, true)
        P:line(wx - 8, wy - 12, wx - 1, wy - 6, color, 4, 255, true)
        P:line(wx + 2, wy - 6, wx + 8, wy - 12, color, 4, 255, true)
        P:line(wx + 8, wy - 12, wx + 6, wy - 4, color, 4, 255, true)
    elseif a.kind == "rabbit" then
        P:ellipse(wx - 5, wy - 13, 3, 9, C.rabbit, 0, 0, true, 255)
        P:ellipse(wx + 5, wy - 13, 3, 9, C.rabbit, 0, 0, true, 255)
    else
        P:ellipse(wx - 6, wy, 3, 6, C.dog_dk, 0, 0, true, 255)
        P:ellipse(wx + 6, wy, 3, 6, C.dog_dk, 0, 0, true, 255)
    end
    P:dot(wx - 3, wy, 1, 0x2A3242, 255)
    P:dot(wx + 3, wy, 1, 0x2A3242, 255)
end

-- ==================== 统一入口 ====================

--- 画小窝 + 当前角色
function M.draw(P, a, e)
    local gy = e.ground_y

    if M.is_home(a) then
        draw_peek(P, a, e)
        return
    end

    -- 小动物按朝向镜像绘制（骑车人永远朝右，不受影响）
    local D = (a.kind ~= "cyclist") and mirror(P, a.x, a.face) or P

    --[[小窝只在小动物模式出现
    骑行模式是"一直在前进"：骑车人钉在屏幕中间、地面往后退，画面里出现一栋
    始终不动的房子就自相矛盾了（房子既不会倒退也不会跟上）。所以人骑车时画面
    里只有路、草和树；切成小猫小狗才有一座固定的小窝。]]
    if a.kind ~= "cyclist" then
        M.draw_house(P, e)
    end

    if a.kind == "cyclist" then
        draw_cyclist(P, a, gy)
    elseif a.kind == "dog" then
        draw_dog(D, a, gy)
    elseif a.kind == "rabbit" then
        draw_rabbit(D, a, gy)
    else
        draw_cat(D, a, gy)
    end
end

return M
