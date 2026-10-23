--[[
@module  eff
@summary MOTO DASH 图片特效层（底纹 / 手指光晕 / 点击闪光 / 扫描光带）
@version 1.0
@date    2026.10.22
@author  江访

=== 分层 ===
  root
   ├─ 底纹 bg_weave.png        （最底：所有图元之下）
   ├─ static_shape             （刻度、外环，一次性）
   ├─ dyn_shape                （指针、弧、彗尾，30fps）
   ├─ 卡片 shape + 文字
   └─ glow / flash / scan      （最顶：光必须能盖住卡片和文字才像光）

=== 为什么只用 set_pos / set_opacity，绝不用 set_zoom / set_rotation ===
真机是 1024x600 RGB 直刷、无 GPU。LVGL 的图片缩放与旋转是**每帧重采样**：
  · dyn_shape 每帧全屏 invalidate，底图会被重新画一遍；
  · 底图一旦 zoom != 256，这一遍就变成对 61 万像素做插值，直接掉帧。
所以：底图必须 1:1（w/h 等于图片像素），光晕只平移 + 改透明度。

=== 写操作的缓存 ===
LVGL 每次 set_pos / set_opacity 都会 invalidate 一块矩形（192x192 = 3.7 万像素）。
本模块对每个精灵记住上次下发的值，位置差 < 1px、透明度相同就整条跳过，
静止时光晕零开销、不产生任何重绘。

=== 内存 ===
底图 101KB + 光晕 13KB + 扫光 3KB；解码后约 2.4MB + 150KB。
theme.img 三项都可单独关闭，关底图可以省掉每帧一次全屏 blit。
]]
local M = {}
local T = require "theme"

local SW, SH = T.screen.w, T.screen.h
local CFG = T.img or {}
local DIR = CFG.dir or "/luadb/"
local GLOW = 192          -- 光晕贴图边长（与素材一致，勿改）
local SCAN_H = 96         -- 扫光条高度（与素材一致，勿改）

local o = {
    t = 0,
    tx = SW / 2, ty = SH / 2, press = false,
    gx = SW / 2, gy = SH / 2, ga = 0,
    fx = 0, fy = 0, fa = 0,
    sy = -SCAN_H, sa = 0,
}

local st = {}   -- 每个精灵上一次真正下发的值

local function slot(key)
    local s = st[key]
    if not s then
        s = { x = -99999, y = -99999, o = -1 }
        st[key] = s
    end
    return s
end

local function put_pos(img, key, x, y)
    if not img then return end
    local s = slot(key)
    x, y = math.floor(x), math.floor(y)
    if s.x ~= x or s.y ~= y then
        s.x, s.y = x, y
        img:set_pos(x, y)
    end
end

local function put_opa(img, key, v)
    if not img then return end
    local s = slot(key)
    v = math.floor(v + 0.5)
    if v < 0 then v = 0 elseif v > 255 then v = 255 end
    if s.o ~= v then
        s.o = v
        img:set_opacity(v)
    end
end

-- 素材存在性检查：缺图时只打日志，不抛错（图片组件本身不会因为 src 无效而失败）
local function asset(name)
    local p = DIR .. name
    if io and io.exists then
        local ok, has = pcall(io.exists, p)
        if ok and not has then
            log.warn("eff", "缺少素材", p)
            return nil
        end
    end
    return p
end

local function make(parent, key, name, w, h, x, y, opa)
    if CFG[key] == false then return nil end
    local src = asset(name)
    if not src then return nil end
    local ok, im = pcall(airui.image, {
        parent = parent, x = x, y = y, w = w, h = h,
        src = src, opacity = opa or 255,
    })
    if ok and im then
        return im
    end
    log.warn("eff", "图片创建失败", src)
    return nil
end

-- ==================== 构建 ====================
-- 底纹：必须在所有图元之前创建
function M.build_bg(parent)
    o.bg = make(parent, "bg", "bg_weave.png", SW, SH, 0, 0, 255)
    if o.bg then
        st.bg = { x = 0, y = 0, o = 255 }
    end
end

-- 光效：必须在所有内容之后创建（最上层）
function M.build_overlay(parent)
    o.glow  = make(parent, "glow",  "fx_glow.png", GLOW, GLOW, -GLOW, -GLOW, 0)
    o.flash = make(parent, "flash", "fx_glow.png", GLOW, GLOW, -GLOW, -GLOW, 0)
    o.scan  = make(parent, "scan",  "fx_scan.png", SW, SCAN_H, 0, -SCAN_H, 0)

    if o.glow  then st.glow  = { x = -GLOW, y = -GLOW, o = 0 } end
    if o.flash then st.flash = { x = -GLOW, y = -GLOW, o = 0 } end
    if o.scan  then st.scan  = { x = 0, y = -SCAN_H, o = 0 } end
end

-- ==================== 交互入口 ====================
function M.press(x, y)
    o.tx, o.ty, o.press = x, y, true
end

function M.move(x, y)
    o.tx, o.ty = x, y
end

function M.release()
    o.press = false
end

-- 指定位置闪一下：按住表盘、点击按键都用它
function M.flash(x, y)
    o.fx, o.fy, o.fa = x, y, 1
end

-- 自上而下扫一道光：切骑行模式时用
function M.sweep()
    o.sy, o.sa = -SCAN_H, 1
end

-- ==================== 每帧推进 ====================
function M.update(dt)
    o.t = o.t + dt

    -- ---- 手指光晕：按下淡入 + 平滑跟随 + 呼吸，松手淡出 ----
    local k = 1 - (1 - 0.20) ^ (dt * 60)
    o.ga = o.ga + ((o.press and 1 or 0) - o.ga) * k
    if o.glow then
        if o.ga > 0.02 then
            local m = 1 - (1 - 0.42) ^ (dt * 60)
            o.gx = o.gx + (o.tx - o.gx) * m
            o.gy = o.gy + (o.ty - o.gy) * m
            put_pos(o.glow, "glow", o.gx - GLOW / 2, o.gy - GLOW / 2)
            local pulse = 0.86 + 0.14 * math.sin(o.t * 6.4)
            put_opa(o.glow, "glow", 205 * o.ga * pulse)
        else
            put_opa(o.glow, "glow", 0)
        end
    end

    -- ---- 点击闪光：0.4 秒衰减 ----
    if o.fa > 0.01 then
        o.fa = o.fa - dt * 2.6
        if o.fa < 0 then o.fa = 0 end
        put_pos(o.flash, "flash", o.fx - GLOW / 2, o.fy - GLOW / 2)
        put_opa(o.flash, "flash", 235 * o.fa)
    else
        put_opa(o.flash, "flash", 0)
    end

    -- ---- 扫描光带：约 0.45 秒从顶扫到底，两端淡入淡出 ----
    if o.sa > 0 then
        o.sy = o.sy + dt * 1520
        local p = (o.sy + SCAN_H) / (SH + SCAN_H)
        if p >= 1 then
            o.sa = 0
            put_opa(o.scan, "scan", 0)
        else
            put_pos(o.scan, "scan", 0, o.sy)
            local e = math.min(1, p / 0.15, (1 - p) / 0.15)
            put_opa(o.scan, "scan", 225 * e)
        end
    end
end

return M
