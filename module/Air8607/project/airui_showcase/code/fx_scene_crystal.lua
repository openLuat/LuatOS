--[[
@module  fx_scene_crystal
@summary AirUI 视觉特效 - 3D 旋转晶体（透视线框）
@version 1.0
@date    2026.10.21

@effect
「立方体 + 对偶八面体」组成的晶体线框：绕 Y 轴匀速自转、绕 X 轴缓慢俯仰。
每个顶点先做 3D 旋转，再透视投影到屏幕（近大远小），棱的颜色与透明度按深度变化
（近处亮、远处暗），下方铺一张透视地面网格提供空间参照。
整帧只有 4 次三角函数（两个轴各一次 sin/cos），其余全是乘加。

@note
这是用 2D 图元拼的伪 3D：没有深度缓冲、没有面填充，遮挡关系靠「深度调亮度」表现。
好处是线框互不遮挡，观感接近全息投影，也更省图元。
]]
local fx = require "fx_core"

local M = {
    id = "crystal",
    name = "3D 晶体",
    desc = "旋转线框晶体，透视投影 + 深度着色",
}

-- 立方体 8 顶点（半边长 1）
local CUBE = {
    { -1, -1, -1 }, { 1, -1, -1 }, { 1, 1, -1 }, { -1, 1, -1 },
    { -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 },
}
-- 立方体 12 条棱（顶点索引对）
local CUBE_E = {
    { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
    { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

-- 对偶八面体 6 顶点：正好是立方体的 6 个面心，天然内切于立方体
local OCTA = {
    { 0, -1, 0 }, { 1, 0, 0 }, { 0, 0, 1 }, { -1, 0, 0 }, { 0, 0, -1 }, { 0, 1, 0 },
}
local OCTA_E = {
    { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 },
    { 6, 2 }, { 6, 3 }, { 6, 4 }, { 6, 5 },
    { 2, 3 }, { 3, 4 }, { 4, 5 }, { 5, 2 },
}

local NC = #CUBE          -- 8
local NO = #OCTA          -- 6
local NV = NC + NO        -- 顶点缓存总长度 14

local VIEW_D = 6.0        -- 视距（归一化坐标单位），越大透视越弱
local FLOOR_Y = 1.62      -- 地面在归一化坐标里的高度
local FLOOR_EXT = 1.70    -- 地面网格半边长
-- 俯仰角越大，地面近端投影越靠下；这两个值配合 o.cy = H*0.44 留出了约 30px 余量

-- 深度系数 k 的实际范围是 [D/(D+√3), D/(D-√3)] ≈ [0.776, 1.406]
local K_MIN, K_SPAN = 0.776, 0.630

function M.build(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool() }
    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })
    o.cx = W * 0.5
    o.cy = H * 0.47
    --[[最大投影半径 = √3 * R * K_MAX ≈ 2.44R（旋转不改变顶点模长 √3，透视还会放大）。
    取 0.19 后上探到 cy-206≈4px、下探到 cy+206≈416px（舞台高 446），
    再留出霓虹辉光最宽 6px 的模糊边刚好不出画。]]
    o.R = math.min(W, H) * 0.19
    o.sx, o.sy, o.sk = {}, {}, {}
    for i = 1, NV do
        o.sx[i], o.sy[i], o.sk[i] = 0, 0, 0
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local cx, cy, R = o.cx, o.cy, o.R
    local sx, sy, sk = o.sx, o.sy, o.sk
    local D = VIEW_D
    P:reset()

    local ay = t * 0.62                            -- Y 轴匀速自转
    local ax = 0.42 + 0.30 * fx.sin(t * 0.47)      -- X 轴缓慢俯仰
    local cax, sax = fx.cos(ax), fx.sin(ax)
    local cay, say = fx.cos(ay), fx.sin(ay)

    --[[顶点投影：绕 Y 转 → 绕 X 转 → 透视除
    x1 = vx*cay - vz*say      z1 = vx*say + vz*cay
    y2 = vy*cax - z1*sax      z2 = vy*sax + z1*cax
    k  = D / (D + z2)         z2 越小（越靠近相机）k 越大
    ]]
    local function proj(i, vx, vy, vz)
        local x1 = vx * cay - vz * say
        local z1 = vx * say + vz * cay
        local y2 = vy * cax - z1 * sax
        local z2 = vy * sax + z1 * cax
        local k = D / (D + z2)
        sx[i] = cx + x1 * R * k
        sy[i] = cy + y2 * R * k
        sk[i] = k
    end

    for i = 1, NC do
        local v = CUBE[i]
        proj(i, v[1], v[2], v[3])
    end
    for i = 1, NO do
        local v = OCTA[i]
        proj(NC + i, v[1], v[2], v[3])
    end

    -- ==================== 地面网格 ====================
    --[[地面只跟随 X 轴俯仰，不参与 Y 轴自转 —— 它是静止的地面，
    晶体在它上方悬浮旋转，这样才有"实物放在地上"的参照感。]]
    local function fproj(wx, wz)
        local y2 = FLOOR_Y * cax - wz * sax
        local z2 = FLOOR_Y * sax + wz * cax
        local k = D / (D + z2)
        return cx + wx * R * k, cy + y2 * R * k, k
    end

    local E = FLOOR_EXT
    -- 沿 z 方向的 5 条放射线
    for i = -2, 2 do
        local wx = i * E * 0.5
        local x1, y1 = fproj(wx, -E)
        local x2, y2 = fproj(wx, E)
        P:line(x1, y1, x2, y2, 0x24597F, 1, 58, false)
    end
    -- 沿 x 方向的 4 条横线（越远越淡）
    for i = -1, 2 do
        local wz = i * E * 0.66
        local x1, y1, k1 = fproj(-E, wz)
        local x2, y2 = fproj(E, wz)
        local opa = math.floor(fx.clamp(44 + 30 * (k1 - 0.7), 24, 105))
        P:line(x1, y1, x2, y2, 0x24597F, 1, opa, false)
    end

    --[[==================== 八面体（内层，紫色霓虹） ====================
    舞台底色是 0x080C18（接近纯黑），原来用 L=0.30、透明度 90 的紫色，
    对比度只有一档，看上去像"糊在背景里的一团"。
    这里改成霓虹灯管的两遍画法：先用宽而暗的同色粗线铺一层光晕，
    再压一条高亮度细线当灯芯，宽度差 + 亮度差在深色底上就造出了发光边。]]
    for e = 1, #OCTA_E do
        local ia, ib = NC + OCTA_E[e][1], NC + OCTA_E[e][2]
        P:line(sx[ia], sy[ia], sx[ib], sy[ib], 0x3A1060, 4, 60, true)
    end
    for e = 1, #OCTA_E do
        local ia, ib = NC + OCTA_E[e][1], NC + OCTA_E[e][2]
        local kk = (sk[ia] + sk[ib]) * 0.5
        local br = fx.clamp((kk - K_MIN) / K_SPAN, 0, 1)
        P:line(sx[ia], sy[ia], sx[ib], sy[ib],
            fx.hsl(284, 0.90, 0.56 + 0.26 * br), 2,
            math.floor(170 + 85 * br), true)
    end

    -- ==================== 立方体（外层，青色霓虹） ====================
    for e = 1, #CUBE_E do
        local ia, ib = CUBE_E[e][1], CUBE_E[e][2]
        P:line(sx[ia], sy[ia], sx[ib], sy[ib], 0x0A3E52, 6, 55, true)
    end
    for e = 1, #CUBE_E do
        local ia, ib = CUBE_E[e][1], CUBE_E[e][2]
        local kk = (sk[ia] + sk[ib]) * 0.5
        local br = fx.clamp((kk - K_MIN) / K_SPAN, 0, 1)
        P:line(sx[ia], sy[ia], sx[ib], sy[ib],
            fx.hsl(192, 0.94, 0.50 + 0.28 * br), 2,
            math.floor(180 + 75 * br), true)
    end

    -- ==================== 顶点辉光 ====================
    for i = 1, NC do
        local br = fx.clamp((sk[i] - K_MIN) / K_SPAN, 0, 1)
        P:dot(sx[i], sy[i], 2 + math.floor(2 * br),
            fx.hsl(186, 0.95, 0.72 + 0.20 * br),
            math.floor(180 + 75 * br))
    end

    -- ==================== 中心核 ====================
    local pulse = 0.5 + 0.5 * fx.sin(t * 2.3)
    P:ring(cx, cy, math.floor(6 + 3 * pulse), 0x9BE8FF, 1,
        math.floor(110 + 90 * pulse))
    P:dot(cx, cy, 3, 0xE8FBFF, 220)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
