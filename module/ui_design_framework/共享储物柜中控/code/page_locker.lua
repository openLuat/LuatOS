--[[
@module  page_locker
@summary 共享储物柜中控 - 页面框架（状态 / 切页 / 顶栏 / 底注 / 分发）
@note
  切页方式：**整页销毁重建**。每次 render() 先 destroy 旧页根容器，再按当前路由重建。
  container 的 hide()/open() 在真机上恢复不回来，用透明度藏页又会留下跨页命中；
  本项目单页控件数 < 80，重建耗时远小于一次重绘，代价可以接受。
  所有切换都经 sys.timerStart 延迟 20ms，避免在点击回调栈内销毁正在命中的控件。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local C = T.c
local F = T.f
local L = T.LAYOUT

local M = {}

-- ==================== 共享状态 ====================
M.S = {
    route   = "home",
    digits  = "",      -- 取件码已输入
    spec    = "S",
    box_no  = "A6",
    ok      = true,
    mode    = "pick",  -- pick / store
}

M.CODE_LEN  = 4        -- 只校验位数，不做码值比对（演示期一律成功；接真实业务时在 submit 里换成平台校验）

-- goods 是"能装什么"（用户视角），不再写厘米数（工程师视角，用户读不懂也换不了算）；
-- price 只作单价展示，不做预付：计费按实际存放时长，取件时结算。
M.SPECS = {
    S = { name = "小柜", goods = "文件袋 · 小快递",   price = 2, left = "余6格" },
    M = { name = "中柜", goods = "双肩包 · 鞋盒",     price = 3, left = "余4格" },
    L = { name = "大柜", goods = "登机箱 · 大纸箱",   price = 5, left = "余2格" },
}

-- CHROME = 顶栏 + 底注 + 时钟，跨页常驻；BODY_ROOT = 页面内容，切页只重建这一层。
-- 拆开的收益：切页少建 ~14 个控件，且时钟数字 label 不再被反复销毁重建
-- （原来每次切页都会把 CLOCK 置 nil，若恰好跨过整分钟，那一次更新时间就被吞掉）。
local CHROME, BODY_ROOT, CLOCK
local pending, again, want_full = false, false, false

-- ==================== 小工具 ====================
local function clock_text()
    local t = os.date("*t")
    return string.format("%02d:%02d", t.hour or 0, t.min or 0)
end
M.clock_text = clock_text

-- 圆角块 + 居中文字 + 热区：所有按钮统一走这里，
-- 热区与视觉尺寸严格同框，不会出现点不到边缘的情况。
function M.button(parent, cfg)
    -- border_w / border_color 可选：白底按钮放在米白页面上没有轮廓会糊成一片，
    -- 需要时由调用方显式传（不传则 border_w=0、不设 border_color，保持无描边）
    local b = W.box(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        color = cfg.color or C.card, radius = cfg.radius or T.r.btn,
        border_w = cfg.border_w or 0, border_color = cfg.border_color,
        tag = cfg.tag or "btn" })
    W.text_mid(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        text = cfg.text, size = cfg.size or F.h3,
        color = cfg.tcolor or C.ink, tag = "btn_t" })
    if cfg.on_click then
        W.press(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
            radius = cfg.radius or T.r.btn, target = b, tx = cfg.x, ty = cfg.y,
            on_click = cfg.on_click, tag = "btn_p" })
    end
    return b
end

-- 延迟重建：连续点击（例如连按 +）时把多次重建合并成一次，
-- 既避免在回调栈内销毁正在命中的控件，也不会丢掉中间的状态变更。
-- full = true 连顶栏一起重建（只有切主题需要；切页一律只重建 body）。
function M.refresh(full)
    if full then want_full = true end
    if pending then
        again = true
        return
    end
    pending = true
    sys.timerStart(function()
        pending = false
        local f = want_full
        want_full = false
        M.render(f)
        if again then
            again = false
            M.refresh()
        end
    end, 20)
end

-- 注意：函数名不能用 goto（Lua 5.2+ 保留字，点号访问会直接报语法错误）
-- 同路由也重建：规格屏点另一档时 route 不变但 S.spec 变了，early-return 会让选中态不刷新
function M.nav(route)
    M.S.route = route
    if route == "code" then M.S.digits = "" end
    M.refresh()
end

-- 流程推进：取件码屏 → 开门 → 结果；规格屏 → 开门 → 结果。
-- 演示期只校验位数，不做码值比对；接真实业务时在这里换成平台校验。
-- 演示用取件码：4 位，首位非 0，避免出现 "0000" 这种像占位符的号码。
-- 真机上 math.random 未播种会每次开机都给出同一串，所以调用方要先 randomseed。
local function new_code()
    return string.format("%d%03d", math.random(1, 9), math.random(0, 999))
end

function M.submit()
    local route = M.S.route
    if route == "code" then
        if #M.S.digits < M.CODE_LEN then return end
        M.S.mode, M.S.ok = "pick", true
        M.nav("open")
    elseif route == "spec" then
        M.S.mode, M.S.ok = "store", true
        M.S.digits = new_code()      -- 存件成功后要把码发给用户，结果页要显示它
        M.nav("open")
    elseif route == "open" then
        M.S.ok = true
        M.nav("done")
    end
end

-- ==================== 顶栏 / 底注 ====================
-- 对应 HTML 的 .bar：左 brand（LOCKER24 + 站点名），右 hud（主题钮 / 在线 / 时钟）。
-- 顶栏高 64，所有元素按 40 高的盒居中（12..52，中心 32）。
local function build_bar(page)
    local bar = W.box(page, { x = 0, y = 0, w = T.W, h = L.bar_h, color = C.bg, tag = "bar" })

    -- 品牌：HTML 是 <b>LOCKER<i>24</i></b>，即 "LOCKER" 深色 + "24" 橙色
    W.text_mid(bar, { x = 40, y = 12, w = 82, h = 40, text = "LOCKER",
        size = F.body, color = C.ink, align = airui.TEXT_ALIGN_LEFT, tag = "brand" })
    W.text_mid(bar, { x = 122, y = 12, w = 30, h = 40, text = "24",
        size = F.body, color = C.orange, align = airui.TEXT_ALIGN_LEFT, tag = "brand24" })
    W.text_mid(bar, { x = 160, y = 12, w = 280, h = 40, text = "阳光里社区 · A 站 01 号机",
        size = F.small, color = C.ink2, align = airui.TEXT_ALIGN_LEFT, tag = "dev" })

    -- 主题钮：.themebtn 高 34、圆角胶囊、1px 描边。左侧图标 + 右侧当前模式名。
    -- 太阳 / 月牙都是 shape 画的：月牙 = 亮色圆 + 一枚按钮底色圆从右上盖掉一块。
    local dark = (T.mode == "dark")
    local tb = W.box(bar, { x = 730, y = 15, w = 86, h = 34, color = C.card,
        radius = 17, border_w = 1, border_color = C.line2, tag = "themebtn" })
    if dark then
        W.shape(tb, { x = 11, y = 9, w = 17, h = 17, tag = "theme_ic", items = {
            { type = "circle", cx = 8, cy = 8, r = 6, color = C.ink2,
              fill = true, fill_color = C.ink2 },
            { type = "circle", cx = 12, cy = 4, r = 6, color = C.card,
              fill = true, fill_color = C.card },
        } })
    else
        W.shape(tb, { x = 11, y = 9, w = 17, h = 17, tag = "theme_ic", items = {
            { type = "circle", cx = 8, cy = 8, r = 4, width = 2, color = C.ink2 },
            { type = "line", x1 = 8, y1 = 0, x2 = 8, y2 = 2, width = 2, color = C.ink2 },
            { type = "line", x1 = 8, y1 = 14, x2 = 8, y2 = 16, width = 2, color = C.ink2 },
            { type = "line", x1 = 0, y1 = 8, x2 = 2, y2 = 8, width = 2, color = C.ink2 },
            { type = "line", x1 = 14, y1 = 8, x2 = 16, y2 = 8, width = 2, color = C.ink2 },
        } })
    end
    W.text_mid(tb, { x = 32, y = 0, w = 44, h = 34, text = dark and "暗色" or "亮色",
        size = F.small, color = C.ink2, align = airui.TEXT_ALIGN_LEFT, tag = "theme_t" })
    -- 热区按内容区 84×32（tb 带 1px 描边），照外框写会被收敛并打越界日志
    W.press(tb, { x = 0, y = 0, w = 84, h = 32, radius = 16, tag = "theme_p",
        on_click = function()
            T.toggle()
            T.save_mode()
            M.refresh(true)      -- 色板换了，顶栏自己的颜色也要重涂，必须连 chrome 一起重建
        end })

    -- 在线：7px 青点 + 文案
    W.box(bar, { x = 830, y = 27, w = 9, h = 9, color = C.teal, radius = 4, tag = "dot" })
    W.text_mid(bar, { x = 846, y = 12, w = 64, h = 40, text = "设备在线",
        size = F.small, color = C.ink2, align = airui.TEXT_ALIGN_LEFT, tag = "online" })

    -- 时钟：会变值，走等宽格（"09:59" → "10:00" 不能整块左右跳）
    -- 等宽 5 位在 22px 下宽 63（2×14 + 7 + 2×14），920+63=983 恰好不越过右边界 984
    CLOCK = W.num(bar, { x = 920, y = 17, size = F.body, template = "99:99",
        color = C.ink, align = airui.TEXT_ALIGN_RIGHT, tag = "clock" })
    if CLOCK then CLOCK.set(clock_text()) end
end

-- .foot：一行居中，三段信息用 · 分隔（HTML 用 4px 圆点，字符中点更省控件且不会算错宽度）
local function build_foot(page)
    local foot = W.box(page, { x = 0, y = L.foot_y, w = T.W, h = L.foot_h,
        color = C.bg, tag = "foot" })
    W.text_mid(foot, { x = 40, y = 8, w = 944, h = 40,
        text = "取件码 24 小时内有效 · 单件限重 30kg · 客服 400-820-1234",
        size = F.small, color = C.ink2, tag = "foot_t" })
end

-- ==================== 渲染 ====================
local BUILD = {}   -- 由子模块注册：BUILD[route] = function(body)

function M.build(route, fn)
    BUILD[route] = fn
end

function M.render(full)
    -- 先删 body 再删 chrome、先建 chrome 再建 body：保证 body 始终压在 chrome 之上。
    -- 两者区域不重叠（chrome 占 0..64 与 544..600，body 占 64..544），所以叠序对命中无影响，
    -- 但叠序稳定能避免"某次重建后顶栏被盖住"这类只在真机偶发的问题。
    if BODY_ROOT then
        pcall(function() BODY_ROOT:destroy() end)
        BODY_ROOT = nil
    end

    if full or not CHROME then
        if CHROME then pcall(function() CHROME:destroy() end) end
        CHROME, CLOCK = nil, nil
        -- parent 传 nil = 挂在当前屏幕（airui 未向 Lua 暴露屏幕对象，act_scr 只是 C 侧局部变量）
        CHROME = W.box(nil, { x = 0, y = 0, w = T.W, h = T.H, color = C.bg, tag = "page" })
        build_bar(CHROME)
        build_foot(CHROME)
    end

    local body = W.box(nil, { x = 0, y = L.body_y, w = T.W, h = L.body_h,
        color = C.bg, tag = "body" })
    BODY_ROOT = body

    local fn = BUILD[M.S.route]
    if fn then
        local ok, err = pcall(fn, body)
        if not ok then log.error("page", "build 失败", M.S.route, err) end
    end
end

function M.start()
    -- 先恢复上次的主题，再建第一屏：否则会先闪一帧默认亮色再切暗
    T.load_mode()

    -- 取件码要随机：不播种的话每次开机都是同一串，演示时连着存两件看到同一个码
    math.randomseed(os.time())

    -- 子模块在这里把自己注册进来（放在函数内，避免模块互相 require 形成环）
    require "page_entry"
    require "page_flow"
    M.render(true)          -- 首帧两者都要建

    -- 时钟独立节拍：20 秒轮询一次，仅在分钟变化时写入
    sys.taskInit(function()
        local last = ""
        while true do
            local txt = clock_text()
            if txt ~= last then
                last = txt
                if CLOCK and CLOCK.set then
                    pcall(function() CLOCK.set(txt) end)
                end
            end
            sys.wait(20000)
        end
    end)
end

return M
