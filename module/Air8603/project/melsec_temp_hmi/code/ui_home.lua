--[[
@module  ui_home
@summary 五页工业 HMI：总览 / 趋势 / 报警 / 设定 / 设备
@version 2.0.0

=== 这一版和上一版的区别 ===
上一版用 airui.container 堆卡片、用 airui.label 当所有文本、图表交给 airui.chart，
结果是：卡片里出现滚动条细框、中文因为没有 font_load 全部不显示、
迷你曲线坐标是小数被 C 层截成 0 而消失、chart 的纵轴写死 0..100 把 26C 压成一条底边直线。

这一版：
  1、卡片 = airui.shape + 图元（圆角填充 / 1px 描边 / 顶部高光 / 角落柔光 / 环形表），
     文字用 label 叠在卡片之上，和 shape 是兄弟节点、绝对坐标定位。
  2、环形表用 shape 的原生 arc 图元（真圆，不是折线逼近）。
  3、趋势自己画：网格 + 虚线阈值 + 两条霓虹折线 + 右端点光斑。
     好处是纵轴可以按数据自适应（chart 的 y_min/y_max 只能在创建时定一次，改不了）。
  4、数值走指数缓动，弧和数字一起平滑逼近，不做硬跳变。
  5、所有坐标取整（fx 里统一 floor），避免 C 层 lua_tointeger 拿到浮点变 0。

=== 分层（z 序即创建顺序）===
  1 背景 shape（全屏竖向渐变 + 两团柔光）
  2 五个页面容器（全屏透明，set_hidden 切换）
  3 顶栏 shape + 顶栏文字
  4 底部导航按钮 + 图标 + 文字 + 选中指示条
]]

local cfg = require("config")
local T   = require("theme")
local fx  = require("fx")

local C, F = T.C, T.f
local SW, SH = T.W, T.H
local AL, AC, AR = T.AL, T.AC, T.AR

local M = {}

-- ============================================================
-- 几何常量
-- ============================================================
local PAD     = 16            -- 水平安全边距
local CY0     = 62            -- 内容区顶
local CY1     = 540           -- 内容区底
local CARD_R  = 14            -- 卡片圆角

-- 通道卡
local CHW, CHH = 330, 248
local CHX = { PAD, PAD + CHW + 12 }        -- 16 / 358
local ALARM_X, ALARM_W = 700, 308

-- 环形表（卡片内坐标）
local GA = { r = 72, band = 10, a0 = 135, a1 = 405 }
local GCX, GCY = 165, 126
local GBOX = 88                              -- 动态图层半径（含辉光余量）

-- 总览第二行
local TR_Y, TR_H = 322, 218
local TR_W = 672
local KPI_Y, KPI_H = 322, 138
local ACT_Y, ACT_H = 470, 70

-- 趋势页
local TF_X, TF_Y, TF_W, TF_H = PAD, CY0, 744, 478
local TS_X, TS_W = 772, 244
local TS_H = 112

-- 报警页
local AL_X, AL_Y, AL_W, AL_H = PAD, CY0, 1000, 478

-- 设定页
local ST_X, ST_Y, ST_W, ST_H = PAD, CY0, 660, 478
local ST_RX, ST_RW = 692, 324

-- 设备页
local DV_KW, DV_KH = 244, 110
local DV_KCARD_X = { 12, 264, 516, 768 }
local DV_RX, DV_RY, DV_RW, DV_RH = PAD, 184, 744, 356
local DV_IX, DV_IW = 772, 240

-- 图标
--[[ 图标和 .lua 平铺在脚本分区根目录，路径固定 /luadb/xxx.png。
     官方 demo 全是这个写法。PLCUI 那套（melsec_hmi_plcui）看着是 src="btn_xx.png"
     裸文件名，其实它有资源表在中间映射；airui 没有这一层，src 必须给完整 VFS 路径。
     ICON_DIR 只留一个常量，要挪位置改这里一处。

     保留一次 io.exists 的目的不是"猜路径"，而是防止图标整批缺失时每张图都刷三条
     "failed to get image info" 错误日志 —— 缺图标只该有一行 warning。]]
local ICON_DIR = "/luadb/"
local iconOK                 -- nil = 还没查；false = 没有图标文件
local function iconRoot()
    if iconOK ~= nil then return iconOK and ICON_DIR or false end
    if io and io.exists then
        local ok, has = pcall(io.exists, ICON_DIR .. "thermo.png")
        if ok and has then
            iconOK = true
            log.info("ui", "图标目录", ICON_DIR)
            return ICON_DIR
        end
    end
    iconOK = false
    log.warn("ui", "未找到图标文件，导航与卡片只显示文字", ICON_DIR .. "*.png")
    return false
end

-- ============================================================
-- 运行期状态
-- ============================================================
local ui = {
    pages = {}, nav = {}, navInd = {}, navLbl = {}, navImg = {},
    ch = {}, mini = {}, miniRow = {}, kpi = {}, reg = {}, live = {},
    big = {}, st = {},
}
local pageKeys = { "overview", "trend", "alarms", "settings", "device" }
local NAV_TEXT = { overview = "总览", trend = "趋势", alarms = "报警", settings = "设定", device = "设备" }
local NAV_ICON = { overview = "layout", trend = "trend", alarms = "alarm", settings = "setting", device = "device" }

local cur = "overview"
local hooks = {}
local th                              -- 阈值表（引用 main 持有的那张）
local hist = { {}, {} }               -- 历史点，单位 0.1C
local HN = cfg.trend.points or 600

local function try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log.warn("ui", "fail:", tostring(err)) end
    return ok
end

-- ============================================================
-- 基础构件
-- ============================================================
local function label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font_size = size or F.body,
        color = color or C.ink, align = align or AL,
    })
end

local function icon(parent, x, y, s, name, opa)
    local d = iconRoot()
    if not d then return nil end
    local ok, obj = pcall(airui.image, {
        parent = parent, x = x, y = y, w = s, h = s,
        src = d .. name .. ".png", fit = "contain", opacity = opa or 255,
    })
    if ok then return obj end
    return nil
end

--[[卡片底板：一次画完，之后不再动
@param number accent 强调色（顶部高光 + 角落柔光）]]
local function card(parent, x, y, w, h, accent)
    local s = airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = {} })
    if not s then return nil end
    local P = fx.pool()
    P:reset()
    -- 主体 + 描边（宽高各减 1，否则右下多出 1px 被裁，看起来缺一条边）
    P:box(0, 0, w - 1, h - 1, C.panel, 250, CARD_R)
    P:frame(0, 0, w - 1, h - 1, C.line, 1, 255, CARD_R)
    -- 顶部高光
    P:hline(CARD_R + 4, 1, w - (CARD_R + 4) * 2, accent or C.line2, 70)
    -- 左上角柔光（大半径低透明度实心圆，营造"屏幕在发光"）
    if accent then
        P:dot(18, 2, 78, accent, 9)
        P:box(0, 0, 54, 3, accent, 235, 2)
    end
    P:finish()
    s:set_items(P.items)
    return s
end

-- 竖向渐变的页面容器
local function page(parent)
    local p = airui.container({ parent = parent, x = 0, y = 0, w = SW, h = SH })
    if p then try(function() p:set_hidden(true) end) end
    return p
end

local function showC(c, on)
    if not c then return end
    if c.set_hidden then
        if pcall(function() c:set_hidden(not on) end) then return end
    end
    if on then
        if c.show then pcall(function() c:show() end)
        elseif c.open then pcall(function() c:open() end) end
    elseif c.hide then
        pcall(function() c:hide() end)
    end
end

-- ============================================================
-- 背景
-- ============================================================
local function build_bg(root)
    local s = airui.shape({ parent = root, x = 0, y = 0, w = SW, h = SH, items = {} })
    local P = fx.pool()
    P:reset()
    P:vgrad(0, 0, SW, SH, C.bg2, C.bg0, 26)
    -- 两团柔光：左上偏青、右下偏紫，极低透明度做体积感
    P:dot(200, 40, 320, C.ch1, 7)
    P:dot(900, 560, 300, C.ch2, 7)
    P:dot(520, 300, 260, 0x1B3A55, 10)
    P:finish()
    s:set_items(P.items)
    return s
end

-- ============================================================
-- 顶栏
-- ============================================================
local function build_top(root)
    local s = airui.shape({ parent = root, x = 0, y = 0, w = SW, h = T.TOP_H + 1, items = {} })
    local P = fx.pool()
    P:reset()
    P:box(0, 0, SW - 1, T.TOP_H - 1, C.bg2, 232, 0)
    P:hline(0, T.TOP_H, SW, C.line, 200)
    P:hline(0, 0, SW, C.line2, 90)
    -- 品牌名左侧一段强调色
    P:box(0, 0, 3, T.TOP_H, C.ch1, 255, 0)
    P:finish()
    s:set_items(P.items)

    icon(root, 18, 12, 28, "thermo", 235)
    label(root, 54, 5, 260, 26, "双路温度监控", F.head, C.ink, AL)
    label(root, 54, 30, 260, 14, "FX3U | RS485 | 隔离 485 J21", F.micro, C.ink3, AL)

    -- 分隔
    local dv = airui.shape({ parent = root, x = 296, y = 12, w = 2, h = 28, items = {} })
    local P2 = fx.pool()
    P2:reset()
    P2:vline(0, 0, 28, C.line2, 200)
    P2:finish()
    if dv then dv:set_items(P2.items) end

    ui.crumb = label(root, 314, 14, 120, 24, "总览", F.label, C.ch1, AL)

    -- 链接状态胶囊：静态底 + 动态圆点 + 动态文字
    ui.linkShape = airui.shape({ parent = root, x = 436, y = 13, w = 210, h = 26, items = {} })
    local P3 = fx.pool()
    P3:reset()
    P3:box(0, 0, 209, 25, C.panel, 235, 13)
    P3:frame(0, 0, 209, 25, C.line, 1, 255, 13)
    P3:finish()
    if ui.linkShape then ui.linkShape:set_items(P3.items) end

    ui.linkDot = airui.shape({ parent = root, x = 450, y = 22, w = 12, h = 12, items = {} })
    ui.linkPool = fx.pool()
    ui.linkText = label(root, 466, 17, 176, 18, "PLC 连接中", F.mini, C.ink3, AL)

    ui.clock = label(root, 660, 3, 160, 30, "--:--:--", F.head, C.ink, AR)
    ui.date  = label(root, 660, 32, 160, 14, "", F.micro, C.ink3, AR)

    -- 报警计数胶囊
    local bs = airui.shape({ parent = root, x = 836, y = 13, w = 172, h = 26, items = {} })
    local P4 = fx.pool()
    P4:reset()
    P4:box(0, 0, 171, 25, C.panel, 235, 13)
    P4:frame(0, 0, 171, 25, C.line, 1, 255, 13)
    P4:finish()
    if bs then bs:set_items(P4.items) end
    ui.badgeDot = airui.shape({ parent = root, x = 850, y = 21, w = 12, h = 12, items = {} })
    ui.badgePool = fx.pool()
    ui.badgeLbl = label(root, 864, 17, 132, 18, "无报警", F.mini, C.ink2, AL)

    return s
end

-- 状态点
local function setDot(shape, pool, color, on)
    if not shape or not pool then return end
    pool:reset()
    if on then
        pool:dot(6, 6, 3, color, 255)
        pool:dot(6, 6, 7, color, 55)
    else
        pool:dot(6, 6, 3, color, 150)
    end
    pool:finish()
    try(function() shape:set_items(pool.items) end)
end

-- ============================================================
-- 通道卡
-- ============================================================
local function build_channel(root, i)
    local bx, by = CHX[i], CY0
    local col = T.chColor[i]
    local c = { col = col, cur = 0, target = 0, level = 0, valid = false,
                warn = 600, alarm = 800, raw = 0, filt = 0 }

    -- 静态底板 + 环形表轨道 + 刻度
    local s = card(root, bx, by, CHW, CHH, col)
    c.card = s
    do
        local P = fx.pool()
        P:reset()
        -- 环内柔光
        P:dot(GCX, GCY, 66, col, 16)
        P:dot(GCX, GCY, 44, col, 10)
        -- 轨道
        P:arc(GCX, GCY, GA.r, GA.a0, GA.a1, 0x1A2A3C, GA.band, 255, true)
        P:arc(GCX, GCY, GA.r + GA.band / 2 + 3, GA.a0, GA.a1, 0x2A3D52, 1, 215, true)
        P:arc(GCX, GCY, GA.r - GA.band / 2 - 3, GA.a0, GA.a1, 0x2A3D52, 1, 160, true)
        -- 刻度：0..100，每 10 小格、每 25 大格
        fx.ticks(P, GCX, GCY, GA.r, GA.band, GA.a0, GA.a1, 100, 10, 25, 0x7C96AE, 0x3E5468)
        -- 底部三分栏分隔
        P:hline(16, 210, CHW - 32, C.line, 170)
        P:vline(118, 218, 24, C.line, 150)
        P:vline(220, 218, 24, C.line, 150)
        P:finish()
        if s then s:set_items(P.items) end
    end

    -- 标题 / 状态胶囊
    label(root, bx + 16, by + 11, 150, 22, cfg.channels[i].name, F.label, C.ink, AL)
    c.pillShape = airui.shape({ parent = root, x = bx + 236, y = by + 10, w = 78, h = 22, items = {} })
    c.pillPool = fx.pool()
    c.pillLbl = label(root, bx + 256, by + 12, 54, 18, "正常", F.mini, C.ok, AC)
    c.pillDotX, c.pillDotY = bx + 248, by + 21

    -- 动态层：进度弧
    c.dyn = airui.shape({
        parent = root, x = bx + GCX - GBOX, y = by + GCY - GBOX,
        w = GBOX * 2, h = GBOX * 2, items = {},
    })
    c.pool = fx.pool()

    -- 大数字
    c.val  = label(root, bx + 55, by + 94, 220, 46, "--.-", F.hero, C.ink3, AC)
    c.unit = label(root, bx + 55, by + 142, 220, 16, "温度 ℃", F.mini, C.ink3, AC)

    -- 底部三栏
    label(root, bx + 16,  by + 214, 100, 14, "AD 原始值", F.micro, C.ink3, AL)
    label(root, bx + 124, by + 214, 96,  14, "预警线",    F.micro, C.ink3, AL)
    label(root, bx + 226, by + 214, 96,  14, "报警线",    F.micro, C.ink3, AL)
    c.ad  = label(root, bx + 16,  by + 228, 100, 18, "----", F.body, C.ink, AL)
    c.wl  = label(root, bx + 124, by + 228, 96,  18, "--.-", F.body, C.warn, AL)
    c.al  = label(root, bx + 226, by + 228, 96,  18, "--.-", F.body, C.alarm, AL)

    ui.ch[i] = c
end

-- 通道卡动态重绘
local function drawChannel(i)
    local c = ui.ch[i]
    if not c or not c.dyn then return end
    local P = c.pool
    P:reset()
    local full = cfg.scale.temp_max          -- 1000 = 100.0C
    local cx, cy = GBOX, GBOX
    local lv = c.level
    local vcol = c.col
    if lv == 2 then vcol = C.alarm elseif lv == 1 then vcol = C.warn end
    if not c.valid then vcol = C.off end

    -- 预警区 / 报警区：淡色弧带 + 外沿细亮线。
    -- 整条实色带盖在暗轨道上会发闷（琥珀叠深蓝=发土黄），所以带子只做很淡的底色，
    -- 用一条 2px 亮线把"限值从哪里开始"标清楚，精度感更好。
    local rim = GA.r + GA.band / 2 + 1
    if c.warn > 0 and c.warn < full then
        local a0s = fx.sweep(c.warn / full, GA.a0, GA.a1)
        local a1s = fx.sweep(math.min(c.alarm, full) / full, GA.a0, GA.a1)
        P:arc(cx, cy, GA.r, a0s, a1s, C.warn, GA.band, 30, true)
        P:arc(cx, cy, rim, a0s, a1s, C.warn, 2, 210, true)
    end
    if c.alarm > 0 and c.alarm < full then
        local a0s = fx.sweep(c.alarm / full, GA.a0, GA.a1)
        P:arc(cx, cy, GA.r, a0s, GA.a1, C.alarm, GA.band, 40, true)
        P:arc(cx, cy, rim, a0s, GA.a1, C.alarm, 2, 235, true)
    end

    -- 进度
    if c.valid then
        fx.progress(P, cx, cy, GA.r, GA.band, c.cur / full, vcol, GA.a0, GA.a1)
    end
    P:finish()
    try(function() c.dyn:set_items(P.items) end)

    -- 胶囊
    local txt, pcol = "正常", C.ok
    if not c.valid then txt, pcol = "失效", C.off
    elseif lv == 2 then txt, pcol = "报警", C.alarm
    elseif lv == 1 then txt, pcol = "预警", C.warn end
    local pp = c.pillPool
    pp:reset()
    pp:box(0, 0, 77, 21, pcol, 34, 11)
    pp:frame(0, 0, 77, 21, pcol, 1, 105, 11)
    pp:dot(13, 11, 3, pcol, 255)
    pp:finish()
    try(function() c.pillShape:set_items(pp.items) end)
    try(function() c.pillLbl:set_text(txt); c.pillLbl:set_color(pcol) end)
end

-- ============================================================
-- 报警行（总览 5 行 / 报警页 8 行）
-- ============================================================
local function build_mini_alarms(root)
    label(root, ALARM_X + 16, CY0 + 12, 150, 22, "最近报警", F.label, C.ink, AL)
    ui.miniCnt = label(root, ALARM_X + 196, CY0 + 14, 96, 18, "0 / 8", F.mini, C.ink3, AR)

    ui.miniBars = airui.shape({ parent = root, x = ALARM_X + 14, y = CY0 + 40, w = 4, h = 200, items = {} })

    ui.miniRow = {}
    for k = 1, 5 do
        local y = CY0 + 46 + (k - 1) * 38
        local r = {
            time = label(root, ALARM_X + 26, y + 9, 48, 18, "", F.micro, C.ink3, AL),
            text = label(root, ALARM_X + 76, y + 8, 148, 20, "", F.sub, C.ink2, AL),
            st   = label(root, ALARM_X + 226, y + 9, 66, 18, "", F.micro, C.ink3, AR),
            y = y,
        }
        ui.miniRow[k] = r
    end
end

local function build_big_alarms(root)
    label(root, AL_X + 16, AL_Y + 12, 180, 22, "报警记录", F.label, C.ink, AL)
    ui.bigCnt = label(root, AL_X + 110, AL_Y + 14, 120, 18, "0 / 8", F.mini, C.ink3, AL)
    label(root, AL_X + 296, AL_Y + 14, 236, 18,
        "保留最近 8 条 | 回落低于回差 1.0℃ 自动恢复", F.micro, C.ink3, AR)

    -- 筛选
    ui.filter = "all"
    local fs = { { "all", "全部" }, { "2", "报警" }, { "1", "预警" }, { "res", "已恢复" } }
    ui.filterBtn = {}
    for k, f in ipairs(fs) do
        local x = AL_X + 556 + (k - 1) * 108
        local on = (f[1] == "all")
        ui.filterBtn[k] = T.btn(root, x, AL_Y + 9, 96, 28, f[2], F.body,
            on and C.panel3 or C.panel2, on and C.ch1 or C.ink2, function()
                ui.filter = f[1]
                for m = 1, #fs do
                    local sel = (fs[m][1] == ui.filter)
                    T.apply_style(ui.filterBtn[m], {
                        bg_color = sel and C.panel3 or C.panel2, bg_opa = 255,
                        text_color = sel and C.ch1 or C.ink2,
                        radius = 8, border_width = 1,
                        border_color = sel and C.ch1 or C.line,
                        pressed_bg_color = C.line2, pressed_bg_opa = 255,
                        pressed_text_color = 0xFFFFFF,
                    })
                end
                if ui.lastRecs then M.update_alarms(ui.lastRecs) end
            end)
    end

    local cs = airui.shape({ parent = root, x = AL_X, y = AL_Y + 45, w = AL_W, h = 2, items = {} })
    local P = fx.pool()
    P:reset(); P:hline(0, 0, AL_W, C.line, 255); P:finish()
    if cs then cs:set_items(P.items) end

    -- 列头
    label(root, AL_X + 26,  AL_Y + 55, 80, 18, "时间", F.mini, C.ink3, AL)
    label(root, AL_X + 122, AL_Y + 55, 60, 18, "级别", F.mini, C.ink3, AL)
    label(root, AL_X + 196, AL_Y + 55, 400, 18, "内容", F.mini, C.ink3, AL)
    label(root, AL_X + 812, AL_Y + 55, 172, 18, "状态", F.mini, C.ink3, AR)

    ui.bigBars = airui.shape({ parent = root, x = AL_X + 16, y = AL_Y + 76, w = 4, h = 380, items = {} })

    ui.big = {}
    for k = 1, 8 do
        local y = AL_Y + 76 + (k - 1) * 46
        ui.big[k] = {
            time = label(root, AL_X + 26,  y + 11, 86, 22, "", F.body, C.ink3, AL),
            lv   = label(root, AL_X + 122, y + 11, 64, 22, "", F.body, C.ink2, AL),
            text = label(root, AL_X + 196, y + 11, 600, 22, "", F.body, C.ink2, AL),
            st   = label(root, AL_X + 812, y + 11, 172, 22, "", F.sub, C.ink3, AR),
            y = y,
        }
    end

    -- 行分隔线
    local ls = airui.shape({ parent = root, x = AL_X + 16, y = AL_Y + 76, w = AL_W - 32, h = 380, items = {} })
    local P2 = fx.pool()
    P2:reset()
    for k = 1, 8 do
        P2:hline(0, (k - 1) * 46 + 40, AL_W - 32, C.line, 120)
    end
    P2:finish()
    if ls then ls:set_items(P2.items) end

    -- 表尾统计（固定位置，不随记录数移动）
    ui.bigFoot = label(root, AL_X + 16, AL_Y + 450, 300, 20, "", F.micro, C.ink3, AL)
    label(root, AL_X + AL_W - 300, AL_Y + 450, 284, 20,
        "最多保留 8 条 | 超出后自动丢弃最早一条", F.micro, C.ink3, AR)
end

-- ============================================================
-- 趋势图（自绘）
-- ============================================================
local function computeRange()
    local lo, hi
    for i = 1, 2 do
        local h = hist[i]
        for k = 1, #h do
            local v = h[k]
            if not lo then lo, hi = v, v
            else
                if v < lo then lo = v end
                if v > hi then hi = v end
            end
        end
    end
    if not lo then return 20, 40 end
    lo, hi = lo / 10, hi / 10
    -- 上下各留 1.5C 余量后向 5 的整数倍取整
    lo = math.max(0, math.floor((lo - 1.5) / 5) * 5)
    hi = math.ceil((hi + 1.5) / 5) * 5
    if hi - lo < 10 then hi = lo + 10 end
    -- 4 等分后每格必须是 5 的整数倍，刻度标签才是 25/30/35 这种整数
    local stepV = math.ceil((hi - lo) / 4 / 5) * 5
    hi = lo + stepV * 4
    return lo, hi
end

--[[画一张趋势
@param string key ui 里的键（缓存放大器和 label 引用）
@param number w,h 绘图区尺寸
@param number cols 最大采样列数（决定图元数量）
@param table yl 纵轴 5 个 label
]]
local function drawTrend(key, w, h, cols, yl)
    local u = ui[key]
    if not u or not u.shape then return end
    local P = u.pool
    P:reset()

    local lo, hi = computeRange()
    local span = hi - lo
    local H1 = h - 1

    local function Y(v) return H1 - (v - lo) / span * H1 end

    -- 底板
    P:box(0, 0, w, h, C.panel2, 190, 6)

    -- 横向网格 + 纵轴刻度值
    for k = 0, 4 do
        local yy = math.floor(H1 - k / 4 * H1)
        P:dash(0, yy, w - 1, yy, C.line, 1, 120, 5, 7)
        if yl and yl[k + 1] then
            try(function() yl[k + 1]:set_text(string.format("%.0f", lo + span * k / 4)) end)
        end
    end
    -- 纵向网格
    local vn = (w > 640) and 6 or 4
    for k = 1, vn - 1 do
        local xx = math.floor(k / vn * (w - 1))
        P:dash(xx, 0, xx, H1, C.line, 1, 80, 5, 9)
    end

    -- 阈值虚线（只在量程内画）
    local function thLine(v, col, opa)
        if v > lo and v < hi then
            local y = Y(v)
            P:dash(0, y, w - 1, y, col, 1, opa, 7, 6)
        end
    end

    -- 曲线
    local sx, sy = u.sx, u.sy
    if not sx then sx, sy = {}, {}; u.sx, u.sy = sx, sy end

    local function series(hh, color)
        local n = #hh
        if n < 2 then return end
        local m = math.min(n, cols)
        local step = (n - 1) / (m - 1)
        for k = 1, m do
            local pos = 1 + (k - 1) * step
            local i0 = math.floor(pos)
            if i0 > n then i0 = n end
            local fr = pos - i0
            local i1 = (i0 < n) and (i0 + 1) or n
            local v = (hh[i0] * (1 - fr) + hh[i1] * fr) / 10
            sx[k] = (k - 1) / (m - 1) * (w - 1)
            sy[k] = H1 - (v - lo) / span * H1
        end
        P:poly(sx, sy, m, color, 5, 22, true)     -- 辉光
        P:poly(sx, sy, m, color, 2, 240, true)    -- 本体
        P:dot(sx[m], sy[m], 4, color, 250)        -- 右端点
        P:dot(sx[m], sy[m], 8, color, 45)
    end

    if th then
        thLine(th[1].warn / 10, C.warn, 90)
        thLine(th[1].alarm / 10, C.alarm, 105)
        thLine(th[2].warn / 10, C.warn, 90)
        thLine(th[2].alarm / 10, C.alarm, 105)
    end

    series(hist[1], C.ch1)
    series(hist[2], C.ch2)

    P:frame(0, 0, w - 1, H1, C.line, 1, 200, 6)
    P:finish()
    try(function() u.shape:set_items(P.items) end)
end

-- 纵轴 / 横轴 label 组
local function axisLabels(parent, plotX, plotY, w, h, key)
    local yl = {}
    for k = 0, 4 do
        local y = plotY + math.floor(h - k / 4 * (h - 1)) - 9
        yl[k + 1] = label(parent, plotX - 44, y, 38, 18, "", F.micro, C.ink3, AR)
    end
    ui[key].yl = yl

    local xl = {}
    local texts = { "-30m", "-20m", "-10m", "现在" }
    for k = 1, 4 do
        local x, al
        if k == 4 then
            x, al = plotX + w - 52, AR
        else
            x, al = plotX + math.floor((k - 1) / 3 * (w - 1)) - 24, AC
        end
        xl[k] = label(parent, x, plotY + h + 5, 52, 16, texts[k],
            F.micro, (k == 4) and C.ink2 or C.ink3, al)
    end
    ui[key].xl = xl
end

-- ============================================================
-- 页面：总览
-- ============================================================
local function build_overview(root)
    build_channel(root, 1)
    build_channel(root, 2)
    build_mini_alarms(root)

    -- 趋势卡
    card(root, PAD, TR_Y, TR_W, TR_H, C.ch1)
    label(root, PAD + 16, TR_Y + 11, 150, 22, "双路温度趋势", F.label, C.ink, AL)
    label(root, PAD + 132, TR_Y + 14, 140, 18, "30 分钟 | 3 秒一点", F.micro, C.ink3, AL)

    -- 图例
    local lg = airui.shape({ parent = root, x = PAD + 268, y = TR_Y + 16, w = 130, h = 16, items = {} })
    local P = fx.pool()
    P:reset()
    P:line(0, 8, 14, 8, C.ch1, 3, 255, true)
    P:line(66, 8, 80, 8, C.ch2, 3, 255, true)
    P:finish()
    if lg then lg:set_items(P.items) end
    label(root, PAD + 288, TR_Y + 11, 40, 18, "CH1", F.micro, C.ink2, AL)
    label(root, PAD + 354, TR_Y + 11, 40, 18, "CH2", F.micro, C.ink2, AL)

    -- 区间按钮
    ui.range = 30
    local ranges = { { 10, "10 分" }, { 30, "30 分" }, { 60, "1 小时" } }
    ui.rangeBtn = {}
    for k, r in ipairs(ranges) do
        local x = PAD + 500 + (k - 1) * 58
        local on = (r[1] == 30)
        ui.rangeBtn[k] = T.btn(root, x, TR_Y + 9, 52, 24, r[2], F.micro,
            on and C.panel3 or C.panel2, on and C.ch1 or C.ink3, function()
                ui.range = r[1]
                for m = 1, #ranges do
                    local sel = (ranges[m][1] == ui.range)
                    T.apply_style(ui.rangeBtn[m], {
                        bg_color = sel and C.panel3 or C.panel2, bg_opa = 255,
                        text_color = sel and C.ch1 or C.ink3,
                        radius = 7, border_width = 1,
                        border_color = sel and C.ch1 or C.line,
                        pressed_bg_color = C.line2, pressed_bg_opa = 255,
                        pressed_text_color = 0xFFFFFF,
                    })
                end
                drawTrend("mini", 612, 142, 200, ui.mini.yl)
            end)
    end

    local px, py, pw, ph = PAD + 44, TR_Y + 44, TR_W - 68, 142
    ui.mini = { shape = airui.shape({ parent = root, x = px, y = py, w = pw, h = ph, items = {} }) }
    ui.mini.pool = fx.pool()
    axisLabels(root, px, py, pw, ph, "mini")

    -- KPI 卡
    card(root, ALARM_X, KPI_Y, ALARM_W, KPI_H, C.ok)
    label(root, ALARM_X + 16, KPI_Y + 11, 200, 22, "运行状态", F.label, C.ink, AL)
    local kp = { { "通讯往返 (ms)", "--", C.ch1 }, { "成功率 (%)", "--", C.ok },
                 { "累计帧数", "--", C.ch2 }, { "运行时长", "--", C.info } }
    ui.mkpi = {}
    for k = 1, 4 do
        local col = (k - 1) % 2
        local row = math.floor((k - 1) / 2)
        local x = ALARM_X + 16 + col * 146
        local y = KPI_Y + 42 + row * 46
        label(root, x, y, 140, 14, kp[k][1], F.micro, C.ink3, AL)
        ui.mkpi[k] = label(root, x, y + 15, 140, 26, "--", F.title, kp[k][3], AL)
    end

    -- 操作卡
    card(root, ALARM_X, ACT_Y, ALARM_W, ACT_H, nil)
    ui.mute = T.ghost(root, ALARM_X + 16, ACT_Y + 15, 136, 40, "消音", F.body, C.ink2,
        function() if hooks.mute then hooks.mute() end end)
    ui.reset = T.ghost(root, ALARM_X + 160, ACT_Y + 15, 132, 40, "复位", F.body, C.ink2,
        function() if hooks.reset then hooks.reset() end end)
end

-- ============================================================
-- 页面：趋势
-- ============================================================
local function build_trend(root)
    card(root, TF_X, TF_Y, TF_W, TF_H, C.ch1)
    label(root, TF_X + 16, TF_Y + 12, 200, 24, "温度曲线", F.title, C.ink, AL)
    label(root, TF_X + 100, TF_Y + 16, 240, 18, "纵轴自适应 | 虚线为阈值", F.micro, C.ink3, AL)

    local lg = airui.shape({ parent = root, x = TF_X + 264, y = TF_Y + 18, w = 130, h = 16, items = {} })
    local P = fx.pool()
    P:reset()
    P:line(0, 8, 14, 8, C.ch1, 3, 255, true)
    P:line(66, 8, 80, 8, C.ch2, 3, 255, true)
    P:finish()
    if lg then lg:set_items(P.items) end
    label(root, TF_X + 284, TF_Y + 13, 40, 18, "CH1", F.micro, C.ink2, AL)
    label(root, TF_X + 350, TF_Y + 13, 40, 18, "CH2", F.micro, C.ink2, AL)

    local ranges = { { 10, "10 分" }, { 30, "30 分" }, { 60, "1 小时" } }
    ui.range2 = 30
    ui.rangeBtn2 = {}
    for k, r in ipairs(ranges) do
        local x = TF_X + 556 + (k - 1) * 60
        local on = (r[1] == 30)
        ui.rangeBtn2[k] = T.btn(root, x, TF_Y + 10, 54, 26, r[2], F.micro,
            on and C.panel3 or C.panel2, on and C.ch1 or C.ink3, function()
                ui.range2 = r[1]
                for m = 1, #ranges do
                    local sel = (ranges[m][1] == ui.range2)
                    T.apply_style(ui.rangeBtn2[m], {
                        bg_color = sel and C.panel3 or C.panel2, bg_opa = 255,
                        text_color = sel and C.ch1 or C.ink3,
                        radius = 7, border_width = 1,
                        border_color = sel and C.ch1 or C.line,
                        pressed_bg_color = C.line2, pressed_bg_opa = 255,
                        pressed_text_color = 0xFFFFFF,
                    })
                end
                drawTrend("full", 688, 376, 300, ui.full.yl)
            end)
    end

    local px, py, pw, ph = TF_X + 44, TF_Y + 54, 688, 376
    ui.full = { shape = airui.shape({ parent = root, x = px, y = py, w = pw, h = ph, items = {} }) }
    ui.full.pool = fx.pool()
    axisLabels(root, px, py, pw, ph, "full")

    -- 右侧四个数值
    local names = { "CH1 当前温度", "CH2 当前温度", "区间最高", "区间最低" }
    local cols  = { C.ch1, C.ch2, C.warn, C.info }
    ui.live = {}
    for k = 1, 4 do
        local y = TF_Y + (k - 1) * (TS_H + 8)
        card(root, TS_X, y, TS_W, TS_H, cols[k])
        label(root, TS_X + 16, y + 12, 200, 20, names[k], F.body, C.ink2, AL)
        ui.live[k] = label(root, TS_X + 16, y + 40, 84, 46, "--.-", F.big, C.ink, AL)
        label(root, TS_X + 92, y + 56, 26, 20, "℃", F.body, C.ink3, AL)
    end
end

-- ============================================================
-- 页面：报警
-- ============================================================
local function build_alarms(root)
    card(root, AL_X, AL_Y, AL_W, AL_H, C.warn)
    build_big_alarms(root)
end

-- ============================================================
-- 页面：设定
-- ============================================================
local function settingsBar(i)
    -- 量程条：0..100C，标出预警 / 报警 / 当前值
    return function(P, w)
        local c = ui.ch[i]
        P:box(0, 0, w, 12, C.panel2, 255, 6)
        P:frame(0, 0, w - 1, 11, C.line, 1, 255, 6)
        local function X(v) return math.floor(fx.clamp(v / 1000, 0, 1) * (w - 1)) end
        local tw, ta = th[i].warn, th[i].alarm
        -- 预警区间
        P:box(X(tw), 0, math.max(2, X(ta) - X(tw)), 12, C.warn, 150, 4)
        -- 报警区间
        P:box(X(ta), 0, math.max(2, w - 1 - X(ta)), 12, C.alarm, 170, 4)
        -- 当前值
        if c and c.valid then
            local x = X(c.filt)
            P:box(x - 1, 0, 3, 12, C.ink, 255, 1)
        end
    end
end

local function refreshSettings()
    if not ui.st then return end
    for i = 1, 2 do
        local u = ui.st[i]
        if u then
            u.warnV:set_text(string.format("%.1f", th[i].warn / 10))
            u.alarmV:set_text(string.format("%.1f", th[i].alarm / 10))
            local P = u.pool
            P:reset()
            settingsBar(i)(P, u.barW)
            P:finish()
            try(function() u.bar:set_items(P.items) end)
            if ui.ch[i] then
                ui.ch[i].warn, ui.ch[i].alarm = th[i].warn, th[i].alarm
                ui.ch[i].wl:set_text(string.format("%.1f", th[i].warn / 10))
                ui.ch[i].al:set_text(string.format("%.1f", th[i].alarm / 10))
            end
        end
        -- 右卡的两路当前值
        local r = ui.stPrev and ui.stPrev.rows[i]
        if r then
            local c = ui.ch[i]
            if c and c.valid then
                r.val:set_text(string.format("%.1f℃", c.filt / 10))
                local lv = c.level or 0
                r.state:set_text(lv == 2 and "报警" or lv == 1 and "预警" or "正常")
                r.state:set_color(lv == 2 and C.alarm or lv == 1 and C.warn or C.ok)
            else
                r.val:set_text("--.-℃")
                r.state:set_text("失效")
                r.state:set_color(C.off)
            end
        end
    end
end

local function setTh(i, field, delta)
    local t = th[i]
    local v = t[field] + delta
    v = math.max(0, math.min(1000, v))
    if field == "warn" then
        if v > t.alarm - 5 then v = t.alarm - 5 end
    else
        if v < t.warn + 5 then v = t.warn + 5 end
    end
    if v == t[field] then return end
    t[field] = v
    refreshSettings()
    if hooks.on_thresholds then hooks.on_thresholds(th) end
end

local function build_settings(root)
    card(root, ST_X, ST_Y, ST_W, ST_H, C.ch1)
    label(root, ST_X + 16, ST_Y + 12, 200, 22, "阈值设定", F.title, C.ink, AL)
    label(root, ST_X + 96, ST_Y + 16, 260, 18, "预警与报警各留 0.5C 间隔 | 立即生效并落盘", F.micro, C.ink3, AL)

    local dv = airui.shape({ parent = root, x = ST_X, y = ST_Y + 42, w = ST_W, h = 2, items = {} })
    local P = fx.pool()
    P:reset(); P:hline(0, 0, ST_W, C.line, 255); P:finish()
    if dv then dv:set_items(P.items) end

    ui.st = {}
    for i = 1, 2 do
        local col = T.chColor[i]
        local bx = ST_X
        local by = ST_Y + 54 + (i - 1) * 208
        local u = { pool = fx.pool(), barW = ST_W - 48 }
        ui.st[i] = u

        -- 通道标题
        local ds = airui.shape({ parent = root, x = bx + 20, y = by + 6, w = 4, h = 18, items = {} })
        local P2 = fx.pool()
        P2:reset(); P2:box(0, 0, 3, 17, col, 255, 2); P2:finish()
        if ds then ds:set_items(P2.items) end
        label(root, bx + 30, by, 160, 24, cfg.channels[i].name, F.label, C.ink, AL)
        u.cur = label(root, bx + 500, by + 3, 140, 20, "当前 --.-C", F.sub, C.ink3, AR)

        -- 两行：预警 / 报警
        local rows = {
            { key = "warn",  name = "预警值", col = C.warn },
            { key = "alarm", name = "报警值", col = C.alarm },
        }
        for k, r in ipairs(rows) do
            local y = by + 30 + (k - 1) * 56
            label(root, bx + 20, y + 8, 70, 22, r.name, F.body, C.ink2, AL)
            local vl = label(root, bx + 92, y + 2, 62, 34, "--.-", F.num, r.col, AL)
            if r.key == "warn" then u.warnV = vl else u.alarmV = vl end
            label(root, bx + 152, y + 13, 20, 18, "℃", F.sub, C.ink3, AL)

            local btns = { { -10, "-1.0" }, { -1, "-0.1" }, { 1, "+0.1" }, { 10, "+1.0" } }
            for m, b in ipairs(btns) do
                local x = bx + 222 + (m - 1) * 74
                local delta = b[1]
                local fld = r.key
                local fg = (delta < 0) and C.ink2 or r.col
                T.btn(root, x, y + 6, 66, 32, b[2], F.sub, C.panel2, fg, function()
                    setTh(i, fld, delta)
                end)
            end
        end

        -- 量程条
        u.bar = airui.shape({ parent = root, x = bx + 20, y = by + 150, w = u.barW, h = 14, items = {} })
        label(root, bx + 20, by + 168, 40, 14, "0", F.micro, C.ink3, AL)
        label(root, bx + u.barW - 30, by + 168, 46, 14, "100℃", F.micro, C.ink3, AR)

        if i == 1 then
            local ln = airui.shape({ parent = root, x = ST_X + 20, y = ST_Y + 258, w = ST_W - 40, h = 2, items = {} })
            local P3 = fx.pool()
            P3:reset(); P3:hline(0, 0, ST_W - 40, C.line, 160); P3:finish()
            if ln then ln:set_items(P3.items) end
        end
    end

    -- ===== 右卡：当前两路 + 系统参数 + 操作 =====
    card(root, ST_RX, ST_Y, ST_RW, ST_H, C.ch2)
    label(root, ST_RX + 16, ST_Y + 12, 200, 22, "本机参数", F.title, C.ink, AL)

    local d1 = airui.shape({ parent = root, x = ST_RX, y = ST_Y + 40, w = ST_RW, h = 2, items = {} })
    local P1 = fx.pool()
    P1:reset(); P1:hline(0, 0, ST_RW, C.line, 255); P1:finish()
    if d1 then d1:set_items(P1.items) end

    -- 两路当前值
    ui.stPrev = { rows = {} }
    for i = 1, 2 do
        local y = ST_Y + 54 + (i - 1) * 44
        local ds = airui.shape({ parent = root, x = ST_RX + 16, y = y + 5, w = 4, h = 18, items = {} })
        local P2 = fx.pool()
        P2:reset(); P2:box(0, 0, 3, 17, T.chColor[i], 255, 2); P2:finish()
        if ds then ds:set_items(P2.items) end
        label(root, ST_RX + 28, y, 64, 26, "CH" .. i, F.label, C.ink, AL)
        -- 注意：不能往 userdata 上挂字段（label 没有 __newindex，赋值会直接抛错退 VM），
        -- 所以这里用普通表包一层
        ui.stPrev.rows[i] = {
            val   = label(root, ST_RX + 76, y - 2, 150, 30, "--.-℃", F.title, C.ink2, AL),
            state = label(root, ST_RX + 200, y + 3, 108, 20, "正常", F.mini, C.ok, AR),
        }
    end

    local d2 = airui.shape({ parent = root, x = ST_RX + 16, y = ST_Y + 150, w = ST_RW - 32, h = 2, items = {} })
    local P3 = fx.pool()
    P3:reset(); P3:hline(0, 0, ST_RW - 32, C.line, 180); P3:finish()
    if d2 then d2:set_items(P3.items) end

    -- 参数清单
    local params = {
        { "采样周期", "330 ms" },
        { "滤波系数", "0.25" },
        { "报警回差", "1.0℃" },
        { "趋势容量", "600 点 / 30 分" },
        { "换算关系", "0-4000 -> 0-100℃" },
        { "阈值存储", "本地 fskv" },
    }
    for k, it in ipairs(params) do
        local y = ST_Y + 162 + (k - 1) * 30
        label(root, ST_RX + 16, y, 96, 20, it[1], F.mini, C.ink3, AL)
        label(root, ST_RX + 116, y, 192, 20, it[2], F.mini, C.ink2, AR)
    end

    T.btn(root, ST_RX + 16, ST_Y + ST_H - 64, ST_RW - 32, 46, "保存并生效", F.label,
        C.ch1, C.on_pri, function()
            if hooks.on_thresholds then hooks.on_thresholds(th) end
        end, 10)
    T.ghost(root, ST_RX + 16, ST_Y + ST_H - 112, ST_RW - 32, 40, "恢复出厂阈值", F.body, C.ink2,
        function()
            for i = 1, 2 do
                th[i].warn = cfg.channels[i].warn
                th[i].alarm = cfg.channels[i].alarm
            end
            refreshSettings()
            if hooks.on_thresholds then hooks.on_thresholds(th) end
        end)
end

-- ============================================================
-- 页面：设备
-- ============================================================
local function build_device(root)
    local kp = { { "通讯往返 (ms)", C.ch1 }, { "成功率 (%)", C.ok },
                 { "累计帧数", C.ch2 }, { "运行时长", C.info } }
    ui.kpi = {}
    for k = 1, 4 do
        local x = DV_KCARD_X[k]
        card(root, x, CY0, DV_KW, DV_KH, kp[k][2])
        label(root, x + 16, CY0 + 14, 200, 20, kp[k][1], F.body, C.ink2, AL)
        ui.kpi[k] = label(root, x + 16, CY0 + 44, 214, 46, "--", F.big, C.ink, AL)
    end

    -- 寄存器表
    card(root, DV_RX, DV_RY, DV_RW, DV_RH, C.ch1)
    label(root, DV_RX + 16, DV_RY + 12, 220, 22, "寄存器映射", F.title, C.ink, AL)
    label(root, DV_RX + 130, DV_RY + 16, 320, 18, "计算机链接 格式4 9600 8E1 站号 00", F.micro, C.ink3, AL)

    local hs = airui.shape({ parent = root, x = DV_RX, y = DV_RY + 44, w = DV_RW, h = 2, items = {} })
    local P = fx.pool()
    P:reset(); P:hline(0, 0, DV_RW, C.line, 255); P:finish()
    if hs then hs:set_items(P.items) end

    label(root, DV_RX + 20,  DV_RY + 54, 100, 18, "软元件", F.mini, C.ink3, AL)
    label(root, DV_RX + 140, DV_RY + 54, 300, 18, "含义", F.mini, C.ink3, AL)
    label(root, DV_RX + 480, DV_RY + 54, 120, 18, "类型", F.mini, C.ink3, AL)
    label(root, DV_RX + 590, DV_RY + 54, 130, 18, "当前值", F.mini, C.ink3, AR)

    local rows = {
        { "D100", "CH1 模拟量原始值", "0-4000" },
        { "D101", "CH2 模拟量原始值", "0-4000" },
        { "D102", "PLC 心跳", "递增" },
        { "D8120", "通信格式寄存器", "HE387" },
        { "D8121", "本站站号", "H00" },
        { "M8000", "运行监视（常 ON）", "ON" },
    }
    ui.reg = {}
    for k, r in ipairs(rows) do
        local y = DV_RY + 80 + (k - 1) * 44
        label(root, DV_RX + 20,  y, 110, 22, r[1], F.label, C.ch1, AL)
        label(root, DV_RX + 140, y + 1, 340, 20, r[2], F.body, C.ink2, AL)
        label(root, DV_RX + 480, y + 3, 120, 18, r[3], F.micro, C.ink3, AL)
        ui.reg[k] = label(root, DV_RX + 570, y, 150, 22, "--", F.label, C.ink, AR)
        local ln = airui.shape({ parent = root, x = DV_RX + 20, y = y + 36, w = DV_RW - 40, h = 2, items = {} })
        local p2 = fx.pool()
        p2:reset(); p2:hline(0, 0, DV_RW - 40, C.line, 110); p2:finish()
        if ln then ln:set_items(p2.items) end
    end
    if ui.reg[4] then ui.reg[4]:set_text("58247") end
    if ui.reg[5] then ui.reg[5]:set_text("0") end
    if ui.reg[6] then ui.reg[6]:set_text("ON") end

    -- 板卡信息
    card(root, DV_IX, DV_RY, DV_IW, DV_RH, C.ch2)
    label(root, DV_IX + 16, DV_RY + 12, 200, 22, "板卡与链路", F.title, C.ink, AL)
    local hs2 = airui.shape({ parent = root, x = DV_IX, y = DV_RY + 44, w = DV_IW, h = 2, items = {} })
    local P3 = fx.pool()
    P3:reset(); P3:hline(0, 0, DV_IW, C.line, 255); P3:finish()
    if hs2 then hs2:set_items(P3.items) end

    local info = {
        { "主控", "Air1603 / Air8603W1" },
        { "屏幕", "10 寸 1024x600 RGB" },
        { "触控", "GT911 电容" },
        { "屏驱动", "JD9165BA" },
        { "485", "UART1 | J21 | 隔离" },
        { "串口参数", "9600 8E1 格式4" },
        { "轮询", "330 ms / 帧" },
        { "固件", "v2.0.0 / 2026-11" },
    }
    for k, it in ipairs(info) do
        local y = DV_RY + 58 + (k - 1) * 28
        label(root, DV_IX + 16, y, 68, 20, it[1], F.mini, C.ink3, AL)
        label(root, DV_IX + 88, y, 144, 20, it[2], F.mini, C.ink2, AL)
    end

    T.ghost(root, DV_IX + 16, DV_RY + DV_RH - 58, 100, 42, "消音", F.body, C.ink2,
        function() if hooks.mute then hooks.mute() end end)
    T.ghost(root, DV_IX + 124, DV_RY + DV_RH - 58, 100, 42, "复位", F.body, C.ink2,
        function() if hooks.reset then hooks.reset() end end)
end

-- ============================================================
-- 底部导航
-- ============================================================
local NAV_TW, NAV_GAP = 160, 16

local function build_nav(root)
    local total = 5 * NAV_TW + 4 * NAV_GAP
    local x0 = math.floor((SW - total) / 2)
    local y = T.NAV_Y

    -- 导航条底
    local s = airui.shape({ parent = root, x = 0, y = y - 8, w = SW, h = T.NAV_H + 16, items = {} })
    local P = fx.pool()
    P:reset()
    P:hline(0, 0, SW, C.line, 160)
    P:finish()
    if s then s:set_items(P.items) end

    for k, key in ipairs(pageKeys) do
        local x = x0 + (k - 1) * (NAV_TW + NAV_GAP)
        ui.nav[key] = T.btn(root, x, y, NAV_TW, T.NAV_H, "", F.label, C.panel2, C.ink2, function()
            T.defer(function() M.go(key) end)
        end, 10)
        ui.navImg[key] = icon(root, x + 16, y + 10, 20, NAV_ICON[key], 150)
        ui.navLbl[key] = label(root, x + 44, y + 9, NAV_TW - 56, 22, NAV_TEXT[key], F.label, C.ink2, AL)
        ui.navInd[key] = airui.shape({ parent = root, x = x + 44, y = y + T.NAV_H - 3, w = NAV_TW - 88, h = 4, items = {} })
    end
    ui.navPool = fx.pool()
end

local function paintNav()
    for _, key in ipairs(pageKeys) do
        local sel = (key == cur)
        local b = ui.nav[key]
        if b then
            T.apply_style(b, {
                bg_color = sel and 0x14293B or C.panel2,
                bg_opa = 255,
                text_color = sel and C.ch1 or C.ink2,
                radius = 10,
                border_width = 1,
                border_color = sel and C.ch1 or C.line,
                pressed_bg_color = C.line2, pressed_bg_opa = 255,
                pressed_text_color = 0xFFFFFF,
            })
        end
        if ui.navLbl[key] then ui.navLbl[key]:set_color(sel and C.ch1 or C.ink2) end
        if ui.navImg[key] then try(function() ui.navImg[key]:set_opacity(sel and 255 or 140) end) end
        local ind = ui.navInd[key]
        if ind then
            local P = ui.navPool
            P:reset()
            if sel then P:box(0, 0, NAV_TW - 88, 3, C.ch1, 255, 2) end
            P:finish()
            try(function() ind:set_items(P.items) end)
        end
    end
end

-- ============================================================
-- 对外：构建
-- ============================================================
-- ============================================================
-- 报警弹窗
-- ============================================================
--[[ 结构：全屏遮罩 container（黑色 65% 不透明，同时挡掉底层所有点击）
         └ 卡片 shape + 图标 + 文字 + 两个按钮
     整棵子树都挂在遮罩下面，所以一次 set_hidden 就能整体显隐。
     弹窗必须最后构建，z 序才在页面和导航之上。]]
local AW, AH = 560, 320
local AX, AY = (SW - AW) / 2, 140      -- 232, 140

local function drawAlertCard(col)
    local P = ui.al.pool
    P:reset()
    P:box(0, 0, AW - 1, AH - 1, C.panel, 252, 16)
    P:frame(0, 0, AW - 1, AH - 1, col, 2, 225, 16)
    P:hline(20, 3, AW - 40, col, 90)
    P:dot(30, 6, 96, col, 16)          -- 左上柔光，和卡片同一套语言
    P:finish()
    try(function() ui.al.card:set_items(P.items) end)
end

local function build_alert(root)
    local veil = airui.container({
        parent = root, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 170,
    })
    ui.al = { veil = veil, pool = fx.pool(), on = false }
    showC(veil, false)

    ui.al.card = airui.shape({ parent = veil, x = AX, y = AY, w = AW, h = AH, items = {} })
    drawAlertCard(C.warn)

    icon(veil, AX + 24, AY + 24, 34, "alert", 255)
    ui.al.lv   = label(veil, AX + 70, AY + 26, 220, 32, "报警", F.num, C.alarm, AL)
    ui.al.time = label(veil, AX + 360, AY + 32, 176, 22, "--:--:--", F.body, C.ink3, AR)

    local dv = airui.shape({ parent = veil, x = AX, y = AY + 76, w = AW, h = 2, items = {} })
    local P = fx.pool()
    P:reset(); P:hline(0, 0, AW, C.line, 255); P:finish()
    if dv then dv:set_items(P.items) end

    ui.al.ch  = label(veil, AX + 24, AY + 94, 380, 22, "通道 1 超限", F.label, C.ink2, AL)
    ui.al.val = label(veil, AX + 24, AY + 116, 340, 60, "--.-", F.huge, C.alarm, AL)
    label(veil, AX + 124, AY + 150, 40, 24, "℃", F.title, C.ink3, AL)
    ui.al.thr = label(veil, AX + 24, AY + 182, 480, 22, "报警值 --.-℃", F.body, C.ink3, AL)
    ui.al.tip = label(veil, AX + 24, AY + 206, 510, 20,
        "请检查对应回路 | 消音只停声音，报警条件解除后自动恢复", F.mini, C.ink3, AL)

    -- 消音是"最该按的那个"，做成级别色主按钮；知道了退成描边
    ui.al.muteBtn = T.btn(veil, AX + 24, AY + 252, 244, 52, "消 音", F.title,
        C.alarm, C.on_pri, function()
            if hooks.mute then hooks.mute() end
            M.hide_alert()
        end, 12)
    ui.al.okBtn = T.ghost(veil, AX + 292, AY + 252, 244, 52, "知道了", F.label, C.ink2,
        function() M.hide_alert() end)
end

-- 显示报警弹窗
function M.show_alert(rec)
    if not ui.al or not rec then return end
    local lv = rec.level or 1
    local col = (lv == 2) and C.alarm or C.warn

    drawAlertCard(col)
    ui.al.lv:set_text(lv == 2 and "报警" or "预警")
    try(function() ui.al.lv:set_color(col) end)
    ui.al.time:set_text(rec.time or os.date("%H:%M:%S"))
    local cname = (cfg.channels[rec.ch] or {}).name or ("通道 " .. tostring(rec.ch))
    ui.al.ch:set_text(cname .. " 超限")
    ui.al.val:set_text(string.format("%.1f", (rec.value or 0) / 10))
    try(function() ui.al.val:set_color(col) end)

    local lim = 0
    if th and th[rec.ch] then lim = (lv == 2) and th[rec.ch].alarm or th[rec.ch].warn end
    ui.al.thr:set_text(string.format("%s值 %.1f℃",
        lv == 2 and "报警" or "预警", lim / 10))

    -- 消音按钮跟随级别配色：预警琥珀、报警玫红
    T.apply_style(ui.al.muteBtn, {
        bg_color = col, bg_opa = 255, text_color = C.on_pri,
        radius = 12, border_width = 0, border_color = col,
        pressed_bg_color = C.line2, pressed_bg_opa = 255, pressed_text_color = 0xFFFFFF,
    })

    showC(ui.al.veil, true)
    ui.al.on = true

    -- 自动收起：0 = 必须手动关
    if ui.al.timer then pcall(sys.timerStop, ui.al.timer); ui.al.timer = nil end
    local ms = (cfg.alarm and cfg.alarm.popup_auto_hide) or 0
    if ms > 0 then
        ui.al.timer = sys.timerStart(function()
            ui.al.timer = nil
            M.hide_alert()
        end, ms)
    end
end

function M.hide_alert()
    if not ui.al then return end
    if ui.al.timer then pcall(sys.timerStop, ui.al.timer); ui.al.timer = nil end
    showC(ui.al.veil, false)
    ui.al.on = false
end

function M.alert_on() return ui.al and ui.al.on or false end

-- ============================================================
-- 对外：构建
-- ============================================================
function M.build(h)
    hooks = h or {}
    th = hooks.th or { { warn = 600, alarm = 800 }, { warn = 600, alarm = 800 } }

    -- 根容器：和 mmy_modbus_hmi / jf_ev_dash 一致，顶层用 container 挂到屏幕，
    -- 底下再铺一层全屏 shape 画背景渐变，然后才是五个页面容器。
    -- （页面容器必须建在顶栏/导航之前，z 序才是"内容在下、框架在上"）
    ui.root = airui.container({ parent = nil, x = 0, y = 0, w = SW, h = SH })
    build_bg(ui.root)

    -- 页面（先建，z 序在下）
    ui.pages = {}
    for _, key in ipairs(pageKeys) do
        ui.pages[key] = page(ui.root)
    end

    -- 顶栏 / 导航（后建，z 序在上）
    build_top(ui.root)
    build_nav(ui.root)

    -- 各页内容
    build_overview(ui.pages.overview)
    build_trend(ui.pages.trend)
    build_alarms(ui.pages.alarms)
    build_settings(ui.pages.settings)
    build_device(ui.pages.device)

    -- 报警弹窗必须最后建：它在 ui.root 上是 z 序最高的，遮住所有页面与导航
    build_alert(ui.root)

    M.go("overview")
    refreshSettings()
    drawChannel(1); drawChannel(2)

    -- 缓动定时器：10Hz 让弧和数字一起逼近目标值
    sys.timerLoopStart(function()
        local dirty = false
        for i = 1, 2 do
            local c = ui.ch[i]
            if c then
                if math.abs(c.target - c.cur) > 0.15 then
                    c.cur = c.cur + (c.target - c.cur) * 0.28
                    dirty = true
                elseif c.cur ~= c.target then
                    c.cur = c.target
                    dirty = true
                end
                if dirty and c.valid then
                    c.val:set_text(string.format("%.1f", c.cur / 10))
                end
            end
        end
        if dirty then drawChannel(1); drawChannel(2) end
    end, 100)

    log.info("ui", "界面已构建", airui.version and airui.version() or "")
end

function M.go(name)
    if not ui.pages[name] then return end
    for key, p in pairs(ui.pages) do showC(p, key == name) end
    cur = name
    paintNav()
    if ui.crumb then ui.crumb:set_text(NAV_TEXT[name] or "") end
    -- 切到趋势页时补一次重绘（隐藏期间 set_items 不会触发渲染）
    T.defer(function()
        if name == "trend" then drawTrend("full", 688, 376, 300, ui.full and ui.full.yl)
        elseif name == "overview" then drawTrend("mini", 612, 142, 200, ui.mini and ui.mini.yl) end
        if name == "settings" then refreshSettings() end
    end, 40)
end

function M.current() return cur end

-- ============================================================
-- 对外：刷新
-- ============================================================
function M.set_clock(s, date)
    if ui.clock then ui.clock:set_text(s or "") end
    if date and ui.date then ui.date:set_text(date) end
end

function M.set_status(txt, color)
    if ui.linkText then
        ui.linkText:set_text(txt or "")
        try(function() ui.linkText:set_color(color or C.ink3) end)
    end
    if ui.linkDot then setDot(ui.linkDot, ui.linkPool, color or C.ink3, false) end
end

function M.set_link(online, rtt)
    if online then
        if ui.linkText then
            ui.linkText:set_text(string.format("PLC 在线 %d ms", rtt or 0))
            try(function() ui.linkText:set_color(C.ok) end)
        end
        if ui.linkDot then setDot(ui.linkDot, ui.linkPool, C.ok, true) end
    else
        if ui.linkText then
            ui.linkText:set_text("通讯中断")
            try(function() ui.linkText:set_color(C.alarm) end)
        end
        if ui.linkDot then setDot(ui.linkDot, ui.linkPool, C.alarm, true) end
    end
end

function M.update_channel(i, r)
    local c = ui.ch[i]
    if not c then return end

    c.valid = r.valid and true or false
    c.raw   = r.raw or 0
    c.filt  = r.filt or 0
    c.warn  = r.warn or c.warn
    c.alarm = r.alarm or c.alarm
    c.level = r.level or 0
    c.target = c.valid and c.filt or 0

    if not c.valid then
        c.cur = 0
        c.primed = false
        c.val:set_text(r.fault and "故障" or "--.-")
        try(function() c.val:set_color(C.ink3) end)
        c.ad:set_text(r.fault and string.format("AD %d", r.raw or 0) or "----")
    else
        -- 第一帧直接落到实际值，不要从 0 慢慢爬（上电后长时间显示 --.- 很奇怪）
        if not c.primed then
            c.cur = c.target
            c.primed = true
        elseif math.abs(c.cur - c.target) < 0.5 then
            c.cur = c.target
        end
        c.val:set_text(string.format("%.1f", c.cur / 10))
        local col = C.ink
        if c.level == 2 then col = C.alarm elseif c.level == 1 then col = C.warn end
        try(function() c.val:set_color(col) end)
        c.ad:set_text(string.format("%d", c.raw or 0))
    end
    c.wl:set_text(string.format("%.1f", c.warn / 10))
    c.al:set_text(string.format("%.1f", c.alarm / 10))
    drawChannel(i)

    -- 设定页的当前值
    local s = ui.st and ui.st[i]
    if s then
        if s.cur then
            s.cur:set_text(c.valid and string.format("当前 %.1f℃", c.filt / 10) or "当前 ----")
        end
        if cur == "settings" then refreshSettings() end
    end
end

function M.update_alarms(records)
    records = records or {}
    ui.lastRecs = records
    local n = #records

    if ui.miniCnt then ui.miniCnt:set_text(string.format("%d / 8", n)) end
    if ui.bigCnt then ui.bigCnt:set_text(string.format("%d / 8", n)) end
    if ui.badgeLbl then
        if n > 0 then
            ui.badgeLbl:set_text(string.format("报警 %d 条", n))
            try(function() ui.badgeLbl:set_color(C.alarm) end)
            if ui.badgeDot then setDot(ui.badgeDot, ui.badgePool, C.alarm, true) end
        else
            ui.badgeLbl:set_text("无报警")
            try(function() ui.badgeLbl:set_color(C.ink2) end)
            if ui.badgeDot then setDot(ui.badgeDot, ui.badgePool, C.ok, false) end
        end
    end

    -- 总览 5 行
    if ui.miniBars then
        local P = fx.pool()
        P:reset()
        for k = 1, 5 do
            local rec = records[k]
            if rec then
                local col = (rec.level == 2) and C.alarm or C.warn
                P:box(0, (k - 1) * 38 + 11, 2, 18, col, 230, 1)
            end
        end
        P:finish()
        try(function() ui.miniBars:set_items(P.items) end)
    end
    for k = 1, 5 do
        local r = ui.miniRow[k]
        local rec = records[k]
        if r then
            if rec then
                r.time:set_text(rec.time or "--:--")
                local col = (rec.level == 2) and C.alarm or C.warn
                if rec.resolved then col = C.ink3 end
                r.text:set_text(string.format("CH%d %s", rec.ch or 0,
                    rec.level == 2 and "报警" or "预警"))
                try(function() r.text:set_color(col) end)
                r.st:set_text(rec.resolved and "已恢复" or (rec.acked and "已确认" or "未确认"))
            else
                r.time:set_text(""); r.text:set_text(""); r.st:set_text("")
            end
        end
    end

    -- 报警页：筛选后展示
    local f = ui.filter or "all"
    local shown = {}
    for _, a in ipairs(records) do
        if (f == "all") or (f == "res" and a.resolved)
            or (f == "2" and a.level == 2 and not a.resolved)
            or (f == "1" and a.level == 1 and not a.resolved) then
            shown[#shown + 1] = a
        end
    end

    if ui.bigBars then
        local P = fx.pool()
        P:reset()
        for k = 1, 8 do
            local rec = shown[k]
            if rec then
                local col = (rec.level == 2) and C.alarm or C.warn
                if rec.resolved then col = C.ink3 end
                P:box(0, (k - 1) * 46 + 12, 2, 22, col, 235, 1)
            end
        end
        P:finish()
        try(function() ui.bigBars:set_items(P.items) end)
    end

    for k = 1, 8 do
        local r = ui.big[k]
        local rec = shown[k]
        if r then
            if rec then
                r.time:set_text(rec.time or "--:--:--")
                r.lv:set_text(rec.level == 2 and "报警" or "预警")
                local col = (rec.level == 2) and C.alarm or C.warn
                try(function() r.lv:set_color(col) end)
                local thr = (rec.level == 2)
                    and (cfg.channels[rec.ch] and cfg.channels[rec.ch].alarm or 0)
                    or (cfg.channels[rec.ch] and cfg.channels[rec.ch].warn or 0)
                if th and th[rec.ch] then
                    thr = (rec.level == 2) and th[rec.ch].alarm or th[rec.ch].warn
                end
                r.text:set_text(string.format("CH%d 触发 %.1f℃ | 阈值 %.1f℃",
                    rec.ch or 0, (rec.value or 0) / 10, thr / 10))
                try(function() r.text:set_color(rec.resolved and C.ink3 or C.ink2) end)
                r.st:set_text(rec.resolved and "已恢复"
                    or (rec.acked and "已确认" or "未确认"))
            else
                r.time:set_text(""); r.lv:set_text("")
                r.text:set_text(""); r.st:set_text("")
            end
        end
    end
    if ui.bigCnt then ui.bigCnt:set_text(string.format("%d / 8", #shown)) end

    if ui.bigFoot then
        if #shown == 0 then
            ui.bigFoot:set_text("当前筛选条件下没有记录")
        else
            ui.bigFoot:set_text(string.format("当前显示 %d 条 | 合计 %d 条记录", #shown, #records))
        end
    end
end

function M.update_device(stats, regs)
    if not ui.kpi[1] then return end
    stats = stats or {}
    ui.kpi[1]:set_text(tostring(stats.rtt or 0))
    ui.kpi[2]:set_text(string.format("%.1f", stats.ok_rate or 100))
    ui.kpi[3]:set_text(tostring(stats.frames or 0))
    ui.kpi[4]:set_text(stats.uptime or "00:00")

    if ui.mkpi then
        ui.mkpi[1]:set_text(tostring(stats.rtt or 0))
        ui.mkpi[2]:set_text(string.format("%.1f", stats.ok_rate or 100))
        ui.mkpi[3]:set_text(tostring(stats.frames or 0))
        ui.mkpi[4]:set_text(stats.uptime or "00:00")
    end

    if regs and ui.reg then
        for k = 1, 3 do
            if ui.reg[k] and regs[k] ~= nil then
                ui.reg[k]:set_text(tostring(regs[k]))
            end
        end
    end
end

function M.update_stats(mx1, mn1, mx2, mn2)
    if not ui.live[1] then return end
    local hi = math.max(mx1 or 0, mx2 or 0)
    local lo = math.min(mn1 or 100, mn2 or 100)
    ui.live[3]:set_text(string.format("%.1f", hi))
    ui.live[4]:set_text(string.format("%.1f", lo))
end

function M.update_live(t1, t2)
    if not ui.live[1] then return end
    ui.live[1]:set_text(string.format("%.1f", t1 or 0))
    ui.live[2]:set_text(string.format("%.1f", t2 or 0))
end

function M.set_muted(muted, active)
    local b = ui.mute
    if not b then return end
    b:set_text(muted and "已消音" or "消音")
    T.apply_style(b, {
        bg_color = muted and 0x3A2A12 or C.panel2,
        bg_opa = 255,
        text_color = muted and C.warn or (active and C.alarm or C.ink2),
        radius = 9,
        border_width = 1,
        border_color = muted and C.warn or (active and C.alarm or C.line2),
        pressed_bg_color = C.line2, pressed_bg_opa = 255, pressed_text_color = 0xFFFFFF,
    })
end

-- 落一个趋势点（单位：C，小数）
function M.push_trend(i, temp)
    local h = hist[i]
    if not h then return end
    h[#h + 1] = math.floor((temp or 0) * 10 + 0.5)
    while #h > HN do table.remove(h, 1) end

    if cur == "overview" then
        drawTrend("mini", 612, 142, 200, ui.mini.yl)
    elseif cur == "trend" then
        drawTrend("full", 688, 376, 300, ui.full.yl)
    end
end

function M.clear_trend()
    hist[1], hist[2] = {}, {}
    if ui.mini then drawTrend("mini", 612, 142, 200, ui.mini.yl) end
    if ui.full then drawTrend("full", 688, 376, 300, ui.full.yl) end
end

function M.set_thresholds(t)
    if t then th = t end
    refreshSettings()
    if cur == "overview" then
        drawTrend("mini", 612, 142, 200, ui.mini and ui.mini.yl)
    elseif cur == "trend" then
        drawTrend("full", 688, 376, 300, ui.full and ui.full.yl)
    end
end

return M
