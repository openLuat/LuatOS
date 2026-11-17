--[[
@module  ui_home
@summary 充放电终端主界面（VoltAgent 翠绿信号）
@version 1.0
@date    2026.11.17
@description
  1024x600 单屏终端，布局逐像素映射 docs/充放电终端UI效果稿.html：
    - 顶栏：品牌 Logo + 充放电状态卡片（三态） + 时钟
    - 左列：电池电量卡（电池图 / 百分比 / 健康环）
    - 右列：实时功率卡（进出功率 + 曲线）+ 输出端口卡（四口开关）
    - 底栏：多重保护
  hzfont 矢量字库无「·」「°」，单位用 ASCII，分隔用空格。
]]

local T = require "theme"
local fx = require "fx"

local M = {}

local SW, SH = T.screen.w, T.screen.h            -- 1024, 600
local C, F, L, PERF = T.c, T.f, T.l, T.perf
local LB, RT, CT = T.LB, T.RT, T.CT
local P = fx.pool()                              -- 每帧复用的图元池

-- ==================== 数据（仿真源） ====================
local S = {
    charging  = true,
    soc       = 60.0,    -- 电量百分比
    health    = 98,      -- 健康度
    cycles    = 128,
    cell_temp = 31.6,
    cap_wh    = 74,      -- 总容量
    avail_mah = 11152,
    charged_wh = 12.9,
    remain_h  = 4.8,
    input     = { w = 60, v = 20.0, a = 3.00 },
    ports = {
        { name = "USB-C1", proto = "PD 100W",  on = true,  v = 20.0, a = 3.00, w = 60.0 },
        { name = "USB-C2", proto = "PD 30W",   on = true,  v = 15.0, a = 2.00, w = 30.0 },
        { name = "USB-A1", proto = "QC 22.5W", on = true,  v = 12.0, a = 1.80, w = 21.6 },
        { name = "USB-A2", proto = "5V 2A",    on = false, v = 5.0,  a = 0.00, w = 0.0  },
    },
    curve = {},   -- 输出功率曲线（0..1 归一化）
    phase = 0,    -- 动画相位（单位=等效帧数，由真实时间推进）
    frame = 0,    -- 帧计数（用于曲线降频）
}
local CURVE_N = 40    -- 曲线采样点（64→40，光栅化量减半，视觉无差）

-- ==================== 布局引用 ====================
local H     = L.header     -- 顶栏
local BAT   = L.battery    -- 电池卡
local POW   = L.power      -- 功率卡
local PORTS = L.ports      -- 端口卡
local FT    = L.footer     -- 底栏

-- ==================== 格式化 ====================
local function fmtI(n) return string.format("%d", math.floor(n + 0.5)) end
local function fmt1(n) return string.format("%.1f", n) end
local function fmt2(n) return string.format("%.2f", n) end

-- 输出总功率 / 在线端口数
local function total_out_w()
    local w = 0
    for i = 1, #S.ports do if S.ports[i].on then w = w + S.ports[i].w end end
    return w
end
local function on_count()
    local n = 0
    for i = 1, #S.ports do if S.ports[i].on then n = n + 1 end end
    return n
end

-- ==================== 图元辅助 ====================
--[[绿色闪电折线（7 点首尾重合，视觉闭合），s 为缩放]]
local function bolt_items(cx, cy, s, color, width, round)
    local xs = { cx + 4 * s, cx - 32 * s, cx - 8 * s, cx - 12 * s, cx + 24 * s, cx, cx + 4 * s }
    local ys = { cy - 40 * s, cy + 8 * s, cy + 8 * s, cy + 40 * s, cy - 8 * s, cy - 8 * s, cy - 40 * s }
    P:poly(xs, ys, 7, color, width, 255, round)
end

-- ==================== 控件句柄 ====================
local W = {}

-- ==================== 充/放电状态（三态：充电中 / 放电中 / 保持） ====================
local function compute_state()
    if S.soc >= 100 then return "hold" end        -- 电量满 → 保持
    if S.charging then return "charge" end        -- 按钮充电 → 充电中
    if on_count() > 0 then return "discharge" end -- 有端口输出 → 放电中
    return "hold"                                 -- 无充电无输出 → 保持
end

local function render_state_card()
    local st = compute_state()
    if st == "charge" then
        W.stCard:set_border_color(C.green)
        W.stCard:set_color(C.panel)
        W.stDot:set_color(C.green)
        W.stTxt:set_color(C.mint)
        W.stTxt:set_text("充电中")
        W.stPow:set_color(C.parchment)
        W.stPow:set_text(fmtI(S.input.w) .. "W")
    elseif st == "discharge" then
        W.stCard:set_border_color(C.info)
        W.stCard:set_color(C.panel)
        W.stDot:set_color(C.info)
        W.stTxt:set_color(C.info)
        W.stTxt:set_text("放电中")
        W.stPow:set_color(C.parchment)
        W.stPow:set_text(fmtI(total_out_w()) .. "W")
    else
        W.stCard:set_border_color(C.line)
        W.stCard:set_color(C.panel)
        W.stDot:set_color(C.steel)
        W.stTxt:set_color(C.steel)
        W.stTxt:set_text("保持")
        W.stPow:set_color(C.steel)
        W.stPow:set_text(S.soc >= 100 and "满电" or "待机")
    end
end

local function toggle_charging()
    S.charging = not S.charging
    render_state_card()
end

-- ==================== 根容器 ====================
-- 所有控件都挂在 W.root 下：切主题时整棵销毁重建，不用逐个清颜色
local function build_root()
    W.root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255,
        radius = 0, border_width = 0, scrollable = false,
    })
end

-- ==================== 主题切换 ====================
--[[切主题：色板原地覆盖 → 延迟到点击回调栈之外销毁重建
    （禁止在回调栈内 destroy 控件）]]
local function toggle_theme()
    T.next_theme()
    T.defer(function()
        sys.wait(40)
        M.rebuild()
    end)
end

-- ==================== 顶栏 ====================
local function build_header()
    -- 品牌 Logo（圆角方块 + 绿色闪电）
    local logo = T.box(W.root, 22, 18, 42, 42, C.panel2, 6, 1, C.line)
    P:reset()
    bolt_items(20, 20, 0.30, C.green, 2, false)
    P:finish()
    -- 内容区 = 42 - 2×1 = 40，shape 必须 ≤ 40 才不触发滚动条
    T.shape(logo, 0, 0, 40, 40, P.items)

    -- 品牌名
    T.label(W.root, 76, 21, 150, 0, "移动电源", F.text, C.snow, LB)
    T.label(W.root, 76, 42, 220, 0, "POWERBANK 20000 MAH", F.mini, C.steel, LB)

    -- 状态卡片（三态：充电中 / 放电中 / 保持，点击切换充电）
    local sx = 590
    W.stCard = T.box(W.root, sx, 19, 180, 40, C.panel, 10, 1, C.green)
    W.stDot = T.box(W.root, sx + 16, 35, 8, 8, C.green, 4, 0)
    W.stTxt = T.text_mid(W.root, sx + 30, 19, 90, 40, "充电中", F.sub, C.mint, LB)
    W.stPow = T.text_mid(W.root, sx + 122, 19, 54, 40, fmtI(S.input.w) .. "W", F.mini, C.parchment, RT)
    T.hot(W.root, sx, 19, 180, 40, toggle_charging)

    -- 主题切换：顶栏胶囊（132x36 ≈ 28x8mm；right=910，与 918 起的时钟留 8px）
    local tx = 778
    W.themeBox = T.box(W.root, tx, 21, 132, 36, C.panel2, 18, 1, C.line)
    W.themeTxt = T.text_mid(W.root, tx, 21, 132, 36,
        T.theme == "dark" and "切换亮色" or "切换暗色", F.text, C.parchment, CT)
    T.hot(W.root, tx, 21, 132, 36, toggle_theme)

    -- 时钟芯片
    local cxl = 918
    T.box(W.root, cxl, 23, 84, 32, C.panel2, 16, 1, C.line)
    W.clock = T.text_mid(W.root, cxl, 23, 84, 32, "14:32", F.text, C.snow, CT)
end

-- ==================== 分隔线辅助 ====================
local function hline(parent, x, y, w, color, opa)
    P:reset()
    P:line(0, 0, w, 0, color, 1, opa, false)
    P:finish()
    return T.shape(parent, x, y, w, 2, P.items)
end

-- ==================== 电池图绘制（局部坐标） ====================
-- 轮廓要往内缩 2px 再画：shape 会裁掉画出组件边界的图元，
-- 描边贴边时（x=0 / x=BAT_W / y=BAT_H）外侧一半被裁掉，真机上电池边框只剩 1px 淡线，
-- 与暗色卡面几乎同色 → 屏幕上看不出是电池。
-- 描边颜色也不用 C.line（暗色 #3D3A39 在 #1B1A19 卡面上对比过低），改用 C.steel。
local BAT_W, BAT_H = 120, 224
local BX0, BY_TOP, BW_IN, BH_IN = 4, 12, 112, 208
local B_BOTTOM = BY_TOP + BH_IN

local function paint_battery()
    P:reset()
    -- 顶部凸起 + 外壳（外壳底色随主题：暗色近黑 / 亮色纯白）
    -- 注意：描边颜色必须每次现取 C.steel，不能在上面缓存成 local（切主题会失真）
    P:box(50, 2, 20, 12, C.cell_bg, 255, 4)
    P:frame(50, 2, 20, 12, C.steel, 3, 255, 4)
    P:box(2, 10, BAT_W - 4, BAT_H - 12, C.cell_bg, 255, 20)
    P:frame(2, 10, BAT_W - 4, BAT_H - 12, C.steel, 3, 255, 20)
    -- 填充 + 体积感（左暗影 / 右高光）+ 液面亮线
    local soc = fx.clamp(S.soc, 0, 100) / 100
    local fh = math.floor(BH_IN * soc)
    if fh > 0 then
        local y0 = B_BOTTOM - fh
        P:box(BX0, y0, BW_IN, fh, C.green, 255, 4)
        if fh > 14 then
            P:box(BX0, y0 + 2, 7, fh - 4, fx.shade(C.green, -0.35), 70, 3)
            P:box(BX0 + BW_IN - 9, y0 + 3, 7, fh - 6, fx.shade(C.green, 0.4), 95, 3)
        end
        P:line(BX0, y0, BX0 + BW_IN, y0, C.snow, 3, 200, true)
    end
    -- 分段刻度线（25 / 50 / 75%）：钢灰半透明，暗腔与绿液上都看得见
    for _, t in ipairs({ 0.25, 0.5, 0.75 }) do
        local sy = math.floor(B_BOTTOM - BH_IN * t)
        P:line(BX0, sy, BX0 + BW_IN, sy, C.steel, 1, 90, false)
    end
    P:finish()
    return P.items
end

local function paint_health_ring()
    P:reset()
    P:ring(22, 22, 16, C.line_dim, 4, 255)
    local a = -90 + 360 * fx.clamp(S.health, 0, 100) / 100
    P:arc(22, 22, 16, -90, math.floor(a), C.green, 4, 255, true)
    P:finish()
    return P.items
end

--[[充电气泡：14 个气泡各自独立（横坐标 / 半径 / 速度 / 摆幅 / 相位）
  速度用「像素/秒」而不是「周期帧数」：固定周期会在电量升高（行程变长）时越走越快，
  60% 时 31~47px/s，满电却飙到 54~83px/s，单帧位移 2.5px 就开始有台阶感。
  改为恒定速度后单帧位移稳定在 1.1~1.5px；行程固定 200px，气泡升到当前液面处淡出，
  液面低时自然早消失 —— 速度与电量彻底解耦。
    cx   基准横坐标（液体区圆心 9~111，人工排布，间距 4~12px 不等，不成斜线）
    r    半径 2~5（越大浮得越快：r=2 → 38px/s，r=5 → 50px/s）
    amp/w 横摆幅度与角速度（各自独立，避免共振成条纹）
    ph0  初始相位（0~90 → 0~200px 的起始偏移）]]
local BUB = {
    { cx =  18, r = 3, amp = 1.6, w = 0.068, ph0 =  0 },
    { cx =  39, r = 5, amp = 2.8, w = 0.052, ph0 = 37 },
    { cx =  62, r = 4, amp = 2.1, w = 0.086, ph0 = 62 },
    { cx =  88, r = 3, amp = 1.2, w = 0.061, ph0 = 14 },
    { cx =  27, r = 4, amp = 3.2, w = 0.094, ph0 = 71 },
    { cx =  52, r = 2, amp = 2.4, w = 0.073, ph0 = 25 },
    { cx =  76, r = 5, amp = 1.0, w = 0.056, ph0 = 84 },
    { cx = 100, r = 4, amp = 2.9, w = 0.089, ph0 = 48 },
    { cx =  14, r = 2, amp = 1.5, w = 0.065, ph0 =  9 },
    { cx =  46, r = 3, amp = 2.2, w = 0.078, ph0 = 57 },
    { cx =  70, r = 4, amp = 3.4, w = 0.050, ph0 = 31 },
    { cx =  95, r = 3, amp = 1.8, w = 0.091, ph0 = 68 },
    { cx =  33, r = 5, amp = 2.6, w = 0.058, ph0 = 19 },
    { cx =  58, r = 2, amp = 1.3, w = 0.082, ph0 = 44 },
}
local BUB_N = #BUB
local TRAVEL = B_BOTTOM - 6 - (BY_TOP + 2)   -- 200px：满液面的上升行程

local function paint_bubbles()
    P:reset()
    -- 只有「充电中」才有气泡：放电与保持（满电/待机）一律不画
    if compute_state() == "charge" then
        local soc = fx.clamp(S.soc, 0, 100) / 100
        local fh = math.floor(BH_IN * soc)
        if fh > 18 then
            local top = B_BOTTOM - fh + 2          -- 液面下 2px，再往上淡出消失
            for i = 1, BUB_N do
                local b = BUB[i]
                local v = 30 + b.r * 4             -- px/s：r=2 → 38，r=5 → 50
                local dy = (S.phase * v / 33 + b.ph0 / 90 * TRAVEL) % TRAVEL
                local by = B_BOTTOM - 6 - math.floor(dy)
                if by > top then
                    -- 独立摆动：频率/幅度/相位各不相同，不会连成直线
                    local bx = b.cx + math.floor(math.sin(S.phase * b.w + i * 1.7) * b.amp + 0.5)
                    if bx < 9 then bx = 9 elseif bx > 111 then bx = 111 end
                    local a = 1
                    if by - top < 18 then a = (by - top) / 18 end          -- 接近液面淡出
                    local d = B_BOTTOM - 4 - by
                    if d < 22 then a = math.min(a, d / 22) end             -- 底部淡入
                    if a > 0.05 then
                        local opa = math.floor((120 + b.r * 22) * a)
                        P:dot(bx, by, b.r, 0xDFFFF2, opa)                  -- 亮白绿气泡
                        if b.r >= 4 then
                            P:dot(bx, by - 1, 1, 0xFFFFFF, math.floor(235 * a))
                        end
                    end
                end
            end
        end
    end
    P:finish()
    return P.items
end

-- ==================== 电池卡 ====================
local function build_battery()
    local card = T.card(W.root, BAT.x, BAT.y, BAT.w, BAT.h)

    -- 翠绿强调边框（50% 透明，2px）
    P:reset()
    P:frame(1, 1, BAT.w - 2, BAT.h - 2, C.green, 2, 140, 8)
    P:finish()
    T.shape(card, 0, 0, BAT.w, BAT.h, P.items)

    -- 卡头
    T.box(card, 16, 13, 3, 13, C.green, 1, 0)
    T.label(card, 28, 11, 120, 0, "电池电量", F.text, C.snow, LB)
    T.label(card, 230, 13, 90, 0, "74 WH", F.mini, C.steel, RT)

    -- 电池图 + 气泡（相对卡内 (16, 96)）
    W.batShape = T.shape(card, 16, 96, BAT_W, BAT_H, paint_battery())
    W.batFx = T.shape(card, 16, 96, BAT_W, BAT_H, paint_bubbles())

    -- 右侧信息
    -- 数字宽度按 3 位数预留（118 装不下 64 号的 "100"，第三位会被裁掉）；
    -- % 随位数动态贴靠右边缘（238 / 276，保持与末位数字约 8px 间隙）
    W.pct = T.label(card, 152, 104, 136, 0, fmtI(S.soc), F.huge, C.mint, LB)
    W.pctUnit = T.label(card, 238, 148, 30, 0, "%", F.body, C.green, LB)
    W.cap = T.label(card, 152, 182, 180, 0, fmtI(S.avail_mah) .. " MAH 可用", F.mini, C.steel, LB)
    T.label(card, 152, 226, 90, 0, "已充电", F.mini, C.steel, LB)
    W.chargedV = T.label(card, 152, 246, 90, 0, fmt1(S.charged_wh) .. " Wh", F.text, C.snow, LB)
    T.label(card, 248, 226, 84, 0, "剩余时间", F.mini, C.steel, LB)
    W.remainV = T.label(card, 248, 246, 84, 0, fmt1(S.remain_h) .. " h", F.text, C.snow, LB)

    -- 健康区
    hline(card, 16, 389, 304, C.line_dim, 255)
    W.healthRing = T.shape(card, 16, 399, 44, 44, paint_health_ring())
    W.healthTxt = T.text_mid(card, 16, 399, 44, 44, fmtI(S.health) .. "%", F.mini, C.mint, CT)
    T.label(card, 76, 399, 130, 0, "电池健康度", F.sub, C.snow, LB)
    W.cycleTxt = T.label(card, 76, 422, 250, 0,
        "循环 " .. S.cycles .. " 次  电芯 " .. fmt1(S.cell_temp) .. "C", F.mini, C.steel, LB)
end

-- ==================== 竖线辅助 ====================
local function vline(parent, x, y, h, color, opa)
    P:reset()
    P:line(0, 0, 0, h, color, 1, opa, false)
    P:finish()
    return T.shape(parent, x, y, 2, h, P.items)
end

-- ==================== 曲线数据与绘制 ====================
local CURVE_W, CURVE_H = 592, 78
local CURVE_MAX_W = 150   -- 归一化上限（W）

local function init_curve()
    for i = 1, CURVE_N do
        S.curve[i] = 0.75 + 0.08 * math.sin(i * 0.3)
    end
end

local function paint_curve()
    P:reset()
    P:dash(0, 20, CURVE_W, 20, C.line_dim, 1, 160, 6, 6)
    P:dash(0, 50, CURVE_W, 50, C.line_dim, 1, 160, 6, 6)
    fx.spark(P, S.curve, #S.curve, 0, 0, CURVE_W, CURVE_H, C.green, 2, 220)
    P:finish()
    return P.items
end

-- ==================== 功率卡 ====================
local function build_power()
    local card = T.card(W.root, POW.x, POW.y, POW.w, POW.h)

    -- 卡头
    T.box(card, 16, 13, 3, 13, C.green, 1, 0)
    T.label(card, 28, 11, 140, 0, "实时功率", F.text, C.snow, LB)
    W.powTime = T.label(card, 506, 13, 110, 0, "14:32:05", F.mini, C.steel, RT)

    -- 输入区
    T.label(card, 20, 40, 160, 0, "输入 TYPE-C PD", F.mini, C.steel, LB)
    W.powInW = T.label(card, 20, 60, 60, 0, fmtI(S.input.w), F.big, C.mint, LB)
    T.label(card, 68, 82, 30, 0, "W", F.text, C.steel, LB)
    W.powInSub = T.label(card, 20, 104, 160, 0,
        fmtI(S.input.v) .. "V " .. fmt2(S.input.a) .. "A", F.mini, C.parchment, LB)

    -- 分隔竖线
    vline(card, 316, 40, 72, C.line_dim, 255)

    -- 输出区
    T.label(card, 336, 40, 160, 0, "输出 总功率", F.mini, C.steel, LB)
    W.powOutW = T.label(card, 336, 60, 90, 0, fmtI(total_out_w()), F.big, C.snow, LB)
    T.label(card, 410, 82, 30, 0, "W", F.text, C.steel, LB)
    W.powOutSub = T.label(card, 336, 104, 180, 0,
        on_count() .. " 口在输出", F.mini, C.parchment, LB)

    -- 曲线
    W.curve = T.shape(card, 20, 134, CURVE_W, CURVE_H, paint_curve())
end

-- ==================== 端口卡 ====================
local port_handles = {}

local function refresh_output()
    W.powOutW:set_text(fmtI(total_out_w()))
    W.powOutSub:set_text(on_count() .. " 口在输出")
end

local function render_port(i)
    local p = S.ports[i]
    local h = port_handles[i]
    if not h then return end
    if p.on then
        h.box:set_color(C.port_on)
        h.box:set_border_color(C.green)
        h.name:set_color(C.snow)
        h.amp:set_color(C.snow)
        h.w:set_color(C.parchment)
        h.dot:set_color(C.green)
        h.txt:set_color(C.parchment)
        h.txt:set_text("输出中")
    else
        h.box:set_color(C.panel2)
        h.box:set_border_color(C.line)
        h.name:set_color(C.steel)
        h.amp:set_color(C.steel)
        h.w:set_color(C.steel)
        h.dot:set_color(C.line_dim)
        h.txt:set_color(C.steel)
        h.txt:set_text("空闲")
    end
end

local function toggle_port(i)
    S.ports[i].on = not S.ports[i].on
    render_port(i)
    refresh_output()
    render_state_card()
end

local function build_port(i, x, y, w, hgt, is_main)
    local p = S.ports[i]
    local on = p.on
    local box = T.box(W.root, x, y, w, hgt, on and C.port_on or C.panel2, 8, 1, on and C.green or C.line)
    local ph = { box = box, i = i }

    if is_main then
        ph.name = T.label(box, 16, 8, 150, 0, p.name, F.text, on and C.snow or C.steel, LB)
        T.label(box, 16, 34, 120, 0, p.proto, F.mini, C.green, LB)
        ph.amp = T.label(box, 220, 6, 130, 0, fmt2(p.a) .. "A", F.body, on and C.snow or C.steel, LB)
        ph.w = T.label(box, 220, 34, 140, 0, fmt1(p.v) .. "V " .. fmtI(p.w) .. "W", F.mini, C.parchment, LB)
        ph.dot = T.box(box, w - 76, 24, 8, 8, on and C.green or C.line_dim, 4, 0)
        ph.txt = T.text_mid(box, w - 64, 8, 58, 40, on and "输出中" or "空闲", F.sub, on and C.parchment or C.steel, RT)
    else
        ph.name = T.label(box, 12, 6, 94, 0, p.name, F.sub, on and C.snow or C.steel, LB)
        T.label(box, 12, 28, 165, 0, p.proto, F.mini, C.green, LB)
        ph.amp = T.label(box, 12, 52, 130, 0, fmt2(p.a) .. "A", F.body, on and C.snow or C.steel, LB)
        ph.w = T.label(box, 12, 77, 165, 0, fmt1(p.v) .. "V " .. fmtI(p.w) .. "W", F.mini, C.parchment, LB)
        ph.dot = T.box(box, w - 22, 10, 8, 8, on and C.green or C.line_dim, 4, 0)
        ph.txt = T.text_mid(box, w - 84, 8, 56, 16, on and "输出中" or "空闲", F.mini, on and C.parchment or C.steel, RT)
    end

    T.hot(W.root, x, y, w, hgt, function() toggle_port(i) end)
    port_handles[i] = ph
end

local function build_ports()
    local card = T.card(W.root, PORTS.x, PORTS.y, PORTS.w, PORTS.h)

    T.box(card, 16, 13, 3, 13, C.green, 1, 0)
    T.label(card, 28, 11, 140, 0, "输出端口", F.text, C.snow, LB)
    T.label(card, 506, 13, 110, 0, "点击开关", F.mini, C.steel, RT)

    -- 主口（整行）
    build_port(1, PORTS.x + 16, PORTS.y + 40, 600, 58, true)
    -- 三个子口（字号 16 后 4 行需要 100 高，避免底行溢出）
    local y = PORTS.y + 108
    local colw = 193
    for i = 2, 4 do
        build_port(i, PORTS.x + 16 + (i - 2) * (colw + 10), y, colw, 100, false)
    end
end

-- ==================== 底栏 ====================
local function build_footer()
    T.box(W.root, 22, 561, 10, 10, C.green, 2, 0)
    T.text_mid(W.root, 38, 547, 84, 38, "多重保护", F.text, C.mint, LB)

    local x = 128
    for _, s in ipairs({ "过流", "过压", "过温", "短路", "过放" }) do
        T.box(W.root, x, 555, 46, 22, C.panel2, 11, 1, C.line)
        T.text_mid(W.root, x, 555, 46, 22, s, F.mini, C.steel, CT)
        x = x + 52
    end
end

-- ==================== 时钟 ====================
local clock_t = 14 * 3600 + 32 * 60   -- 备用起始 14:32:00

local function update_clock()
    local t = os.time()
    local hm, hms
    if t and t > 1700000000 then
        hm = os.date("%H:%M", t)
        hms = os.date("%H:%M:%S", t)
    else
        clock_t = clock_t + 1
        local hh = math.floor(clock_t / 3600) % 24
        local mm = math.floor(clock_t / 60) % 60
        local ss = clock_t % 60
        hm = string.format("%02d:%02d", hh, mm)
        hms = string.format("%02d:%02d:%02d", hh, mm, ss)
    end
    W.clock:set_text(hm)
    W.powTime:set_text(hms)
end

-- ==================== 数据刷新（5Hz） ====================
local function update_text()
    -- 电量漂移
    if S.charging then
        S.soc = S.soc + 0.06
        if S.soc > 100 then S.soc = 100 end
    else
        S.soc = S.soc - 0.05
        if S.soc < 0 then S.soc = 0 end
    end
    S.charged_wh = S.charged_wh + (S.charging and 0.01 or 0)
    S.remain_h = S.charging and ((100 - S.soc) * 0.12) or (S.soc * 0.02)

    -- 输入微调（电压固定 20V）
    S.input.w = 60 + math.sin(S.phase * 0.05) * 2
    S.input.a = S.input.w / S.input.v

    local pct_v = fmtI(S.soc)
    W.pct:set_text(pct_v)
    local pct_three = #pct_v >= 3
    if W._pctThree ~= pct_three then
        W._pctThree = pct_three
        W.pctUnit:set_pos(pct_three and 276 or 238, 148)
    end
    W.cap:set_text(fmtI(S.avail_mah) .. " MAH 可用")
    W.chargedV:set_text(fmt1(S.charged_wh) .. " Wh")
    W.remainV:set_text(fmt1(S.remain_h) .. " h")
    -- 输入功率只在充电态有效：放电/保持时没有输入，显示 0W
    if compute_state() == "charge" then
        W.powInW:set_text(fmtI(S.input.w))
        W.powInSub:set_text(fmtI(S.input.v) .. "V " .. fmt2(S.input.a) .. "A")
    else
        W.powInW:set_text("0")
        W.powInSub:set_text("未连接输入")
    end

    -- 电池图只在整数百分比变化时重画（原来 5Hz 无条件重绘 120x224 纯浪费）
    if W._soc ~= pct_v then
        W._soc = pct_v
        W.batShape:set_items(paint_battery())
    end
    render_state_card()
end

-- ==================== 帧动画（30fps） ====================
-- 相位按真实时间推进：定时器抖动 / 偶发丢帧不再直接变成视觉抖动
-- mcu.ticks() 是毫秒开机滴答；老固件缺失时退化为按帧推进
local now_ms = (mcu and mcu.ticks) or function() return 0 end
local last_t = now_ms()

local function frame_step()
    local t = now_ms()
    local dt = t - last_t
    last_t = t
    if dt <= 0 or dt > 200 then dt = PERF.frame_ms end   -- 首次调用 / 计数回绕 / 长挂起：按名义帧长兜底
    S.phase = S.phase + dt / PERF.frame_ms               -- 折算成等效帧数，下游公式不变
    S.frame = S.frame + 1

    -- 输出功率曲线：每 2 帧推进一次（15fps 足够，省下预算给气泡重绘）
    if S.frame % 2 == 0 then
        local out = total_out_w() / CURVE_MAX_W
        out = out + (fx.noise1(S.phase * 0.02) - 0.5) * 0.06
        table.remove(S.curve, 1)
        S.curve[#S.curve + 1] = fx.clamp(out, 0, 1)
        W.curve:set_items(paint_curve())
    end

    -- 充电气泡：仅「充电中」逐帧重绘；放电/保持补画一次空表后停止重绘
    local bubble_on = compute_state() == "charge"
    if bubble_on or W._bubOn ~= false then
        W._bubOn = bubble_on
        W.batFx:set_items(paint_bubbles())
    end
end

-- ==================== 入口 ====================
local timers = {}

function M.build()
    init_curve()
    build_root()
    build_header()
    build_battery()
    build_power()
    build_ports()
    build_footer()
    render_state_card()
    update_clock()
end

--[[切主题后整棵重建：销毁根容器即可带走全部子控件，
    再按新色板重新构建（定时器不用重启，它们引用的是 W 表）]]
function M.rebuild()
    if W.root then
        W.root:destroy()
        W.root = nil
    end
    for k in pairs(W) do W[k] = nil end
    for k in pairs(port_handles) do port_handles[k] = nil end
    M.build()
end

function M.run()
    update_clock()
    update_text()
    frame_step()
    timers.clock = sys.timerLoopStart(update_clock, PERF.clock_ms)
    timers.text  = sys.timerLoopStart(update_text, PERF.text_ms)
    timers.frame = sys.timerLoopStart(frame_step, PERF.frame_ms)
end

function M.destroy()
    for k, t in pairs(timers) do
        if t then sys.timerStop(t) end
    end
    timers = {}
    if W.root then
        W.root:destroy()
        W.root = nil
    end
end

return M
