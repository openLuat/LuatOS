--[[
@module  page_home
@summary 会议室门牌主页（状态卡 + 今日议程 + 本周预约网格 + 深/浅主题切换）
@version 1.0.0
@note 布局基准 1024x600（Air8607 + 10.1 寸 RGB 屏），所有坐标按「卡片内容区」核算：
      卡片内容区 = 外框 − 2×border_width(2)，子控件底缘留 2~4px 余量，绝不探出。
      交互：
        · 顶栏「浅色/深色」→ 切主题并整页重建（不重启，fskv 记忆）
        · 点状态卡「立即预约」→ 预约页（今天 + 最近空档）
        · 点周视图某天的空白处 → 预约页（该天 + 该天最近空档）
        · 点周视图某天的日期标题 → 选中该天（整列铺淡色底）
        · 当前小时在周视图上是一条淡色横带（跨时间列 + 7 天），跨小时自动跟随
        · 点已有会议色块 → 详情页
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local R = require "router"
local C, G = T.c, T.glass
local M = {}

local SW, SH = T.screen.w, T.screen.h

-- ==================== 布局常量 ====================
local TOP = { x = 18,  y = 14,  w = 988, h = 64  }
local ST  = { x = 18,  y = 90,  w = 300, h = 326 }
local AG  = { x = 18,  y = 428, w = 300, h = 156 }
local WK  = { x = 330, y = 90,  w = 676, h = 494 }   -- 90 + 494 = 584，底边留 16

-- 周视图网格：时间列 64 + 7 天 × 86 = 666，卡片内容宽 672
local GX, GTIME_W, GDAY_W = 2, 64, 86
local GHDR_Y, GHDR_H = 38, 34
local GBODY_Y, GROW_H, GROWS = 72, 33, 12

-- ==================== 运行期句柄 ====================
local PAGE, ROOT, timer
local cache, agenda_items = {}, {}
local lb_sub, lb_date, lb_head, lb_clock
local lb_badge, lb_title, lb_l1, lb_l2, lb_l3, lb_l4, lb_remain
local bar, bar_r, bar_c = nil, -1, -1
local lb_agcount, lb_agtitle
local row_hl, time_lbls                        -- 当前小时整行底板 / 时间轴文字
local sel_day                                  -- 当前选中的星期（整列高亮），默认今天
local col_bg, head_lbls = {}, {}               -- 列底色 / 表头文字

-- ==================== 小工具 ====================
-- 只在文字真正变化时才 set_text，避免每秒重复触发重绘
local function put(lbl, key, s)
    if cache[key] ~= s then
        cache[key] = s
        W.set(lbl, s)
    end
end

local function color_of(dept)
    return T.dept[dept] or T.dept[1]
end

-- 背景由 wallpaper 模块在屏幕级统一绘制（实景照片 + 纱层），页面根容器保持全透明

-- ==================== 顶栏 ====================
local function build_topbar()
    local g = W.glass_card({ parent = ROOT, x = TOP.x, y = TOP.y, w = TOP.w, h = TOP.h })
    local p = g.card
    W.text_mid(p, { text = S.room.name, x = 18, y = 6, w = 330, h = 32,
        size = 24, color = C.text })
    lb_sub = W.text_mid(p, { text = S.room.sub, x = 18, y = 38, w = 330, h = 20,
        size = T.f.mini, color = C.text_dim })
    lb_date = W.text_mid(p, { text = "", x = 368, y = 6, w = 226, h = 24,
        size = T.f.body, color = C.text_sub })
    lb_head = W.text_mid(p, { text = "", x = 368, y = 32, w = 226, h = 22,
        size = T.f.mini, color = C.text_dim })
    W.chip(p, { x = 604, y = 14, w = 86, h = 36, text = "设置",
        off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
        on_click = function() R.go("setup") end })
    R.theme_chip(p, { x = 700, y = 14, w = 86, h = 36 })
    lb_clock = W.text_mid(p, { text = "--:--", x = 796, y = 6, w = 170, h = 48,
        size = 38, color = C.text, align = airui.TEXT_ALIGN_RIGHT })
    return g
end

-- ==================== 状态卡 ====================
local function build_status()
    local g = W.glass_card({ parent = ROOT, x = ST.x, y = ST.y, w = ST.w, h = ST.h })
    local p = g.card
    W.text_mid(p, { text = "会议室状态", x = 14, y = 10, w = 180, h = 20,
        size = T.f.mini, color = C.text_dim })
    lb_badge = W.text_mid(p, { text = "--", x = 14, y = 32, w = 268, h = 54,
        size = T.f.big, color = C.ok })

    -- 当前会议信息块（凹陷面板）
    local box = airui.container({ parent = p, x = 12, y = 90, w = 272, h = 140,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(box, C.tile, G.tile_opa)
    lb_title = W.text_mid(box, { text = "", x = 12, y = 8, w = 244, h = 32,
        size = T.f.h2, color = C.text })
    lb_l1 = W.text_mid(box, { text = "", x = 12, y = 46, w = 244, h = 20,
        size = T.f.mini, color = C.text_sub })
    lb_l2 = W.text_mid(box, { text = "", x = 12, y = 68, w = 244, h = 20,
        size = T.f.mini, color = C.text_sub })
    lb_l3 = W.text_mid(box, { text = "", x = 12, y = 90, w = 244, h = 20,
        size = T.f.mini, color = C.text_sub })
    lb_l4 = W.text_mid(box, { text = "", x = 12, y = 112, w = 244, h = 20,
        size = T.f.mini, color = C.text_dim })

    lb_remain = W.text_mid(p, { text = "", x = 14, y = 236, w = 268, h = 20,
        size = T.f.mini, color = C.text_sub })
    bar = W.bar(p, { x = 14, y = 260, w = 268, h = 8 })
    W.button(p, { x = 14, y = 276, w = 268, h = 42, text = "立即预约",
        size = T.f.body, color = C.pri, tcolor = C.on_accent,
        on_click = function()
            local st = S.free_start(S.today)
            if not st then
                R.toast("今天已无可预约时段")
                return
            end
            R.go("booking", { day = S.today, start = st })
        end })
    return g
end

-- ==================== 今日议程 ====================
local function build_agenda()
    local g = W.glass_card({ parent = ROOT, x = AG.x, y = AG.y, w = AG.w, h = AG.h })
    local p = g.card
    W.text_mid(p, { text = "今日议程", x = 14, y = 8, w = 140, h = 20,
        size = T.f.mini, color = C.text_dim })
    lb_agcount = W.text_mid(p, { text = "", x = 150, y = 8, w = 132, h = 20,
        size = T.f.mini, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    for i = 1, 3 do
        local y = 34 + (i - 1) * 36
        local it = {}
        it.time = W.text_mid(p, { text = "", x = 14, y = y, w = 48, h = 22,
            size = T.f.mini, color = C.pri })
        it.dot = airui.container({ parent = p, x = 68, y = y + 7, w = 6, h = 6,
            color = C.pri, radius = 3, border_width = 0 })
        W.glass(it.dot, C.pri, 0)
        it.topic = W.text_mid(p, { text = "", x = 80, y = y, w = 200, h = 22,
            size = T.f.mini, color = C.text })
        agenda_items[i] = it
    end
    return g
end

-- ==================== 本周预约网格 ====================
local function build_week()
    local g = W.glass_card({ parent = ROOT, x = WK.x, y = WK.y, w = WK.w, h = WK.h })
    local p = g.card
    -- 这三张表跨次重建复用，建之前必须先清空（destroy 会把它们置空）
    head_lbls, col_bg, time_lbls = {}, {}, {}
    W.text_mid(p, { text = "本周预约", x = 14, y = 8, w = 140, h = 20,
        size = T.f.mini, color = C.text_dim })
    W.text_mid(p, { text = "点标题切天 · 点空白处预约", x = 386, y = 8, w = 272, h = 20,
        size = T.f.mini, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })

    -- 表头：整格都是热区，点一下就把那天整列选中并高亮
    W.text_mid(p, { text = "时间", x = GX, y = GHDR_Y, w = GTIME_W - 8, h = GHDR_H,
        size = T.f.mini, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    for d = 1, 7 do
        local x = GX + GTIME_W + (d - 1) * GDAY_W
        head_lbls[d] = W.text_mid(p, { text = S.day_names[d] .. " " .. S.day_of_month(d),
            x = x, y = GHDR_Y, w = GDAY_W, h = GHDR_H, size = T.f.mini,
            color = (d < S.today) and C.text_dim or C.text_sub,   -- 已过去的日子压暗一档
            align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(p, { x = x, y = GHDR_Y, w = GDAY_W, h = GHDR_H, radius = 8, glow = 26,
            on_click = function() M.select_day(d) end })
    end
    -- 表头下沿分隔线
    W.shape(p, { x = GX, y = GBODY_Y - 1, w = GTIME_W + 7 * GDAY_W, h = 1, items = {
        { type = "line", x1 = 0, y1 = 0, x2 = GTIME_W + 7 * GDAY_W, y2 = 0,
          color = C.divider, width = 1, opacity = 110 },
    } })

    -- 当前小时整行底板：横向跨「时间列 + 7 天」，只染底色，不做文字
    -- 建在时间轴文字和 7 个列之前，保证文字/会议色块都压在它上面
    row_hl = airui.container({ parent = p, x = GX, y = GBODY_Y, w = GTIME_W + 7 * GDAY_W,
        h = GROW_H, color = C.pri, radius = 4, border_width = 0 })
    W.glass(row_hl, C.pri, 0)

    -- 时间轴（08:00 ~ 19:00 共 12 行）
    for i = 0, GROWS - 1 do
        time_lbls[i + 1] = W.text_mid(p, { text = string.format("%02d:00", S.room.open_h + i),
            x = GX, y = GBODY_Y + i * GROW_H, w = GTIME_W - 8, h = GROW_H,
            size = T.f.mini, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    end

    -- 7 个日期列
    for d = 1, 7 do
        local cx = GX + GTIME_W + (d - 1) * GDAY_W
        local col = airui.container({ parent = p, x = cx, y = GBODY_Y, w = GDAY_W,
            h = GROWS * GROW_H, color = 0xFFFFFF, color_opacity = 0, border_width = 0 })
        -- 整列底色（选中某天时铺满这一列），放在最底层
        col_bg[d] = airui.container({ parent = col, x = 0, y = 0, w = GDAY_W,
            h = GROWS * GROW_H, color = C.pri, radius = 6, border_width = 0 })
        W.glass(col_bg[d], C.pri, 0)

        -- 空白列热区：按小时拆成 12 格，点哪一格就以该格的整点作为开始时间
        -- （先建；后建的会议色块盖在它上面，点色块仍是进详情）
        for i = 0, GROWS - 1 do
            local h = S.room.open_h + i
            W.press_layer(col, { x = 0, y = i * GROW_H, w = GDAY_W, h = GROW_H,
                radius = 4, glow = 18,
                on_click = function()
                    if d < S.today then
                        R.toast("该日期已过去")
                        return
                    end
                    if d == S.today and h < S.now_h then
                        R.toast("该时段已过去")
                        return
                    end
                    R.go("booking", { day = d, start = h })
                end })
        end
        -- 行分隔虚线（虚线比实线弱一档，不抢会议色块）
        local items = {}
        for i = 1, GROWS - 1 do
            items[#items + 1] = { type = "line", x1 = 0, y1 = i * GROW_H,
                x2 = GDAY_W, y2 = i * GROW_H, color = C.divider, width = 1,
                opacity = 45, dash_width = 4, dash_gap = 6 }
        end
        W.shape(col, { x = 0, y = 0, w = GDAY_W, h = GROWS * GROW_H, items = items })

        -- 该天的会议色块
        for idx, b in ipairs(S.bookings) do
            if b.day == d then
                local by = math.floor((b.start - S.room.open_h) * GROW_H + 0.5)
                local bh = b.dur * GROW_H - 3
                if by >= 0 and by + bh <= GROWS * GROW_H then
                    local dt = color_of(b.dept)
                    local box = airui.container({ parent = col, x = 2, y = by,
                        w = GDAY_W - 4, h = bh, color = dt.tint, radius = 6, border_width = 0 })
                    W.glass(box, dt.tint, G.block_opa)
                    local accent = airui.container({ parent = box, x = 0, y = 0, w = 3, h = bh,
                        color = dt.accent, radius = 2, border_width = 0 })
                    W.glass(accent, dt.accent, 255)
                    if bh < 40 then
                        -- 1 小时：单行居中，只放主题（最多 4 字，72px 内一定放得下）
                        W.text_mid(box, { text = W.clip(b.topic, 4), x = 8, y = 0,
                            w = GDAY_W - 14, h = bh, size = T.f.mini, color = dt.text })
                    else
                        -- 2 小时以上：主题 / 部门 / 时长三行
                        W.text_mid(box, { text = W.clip(b.topic, 4), x = 8, y = 4, w = GDAY_W - 14,
                            h = 22, size = T.f.mini, color = dt.text })
                        W.text_mid(box, { text = W.clip(S.dept_name(b.dept), 3), x = 8, y = 26,
                            w = GDAY_W - 14, h = 22, size = T.f.mini, color = dt.text })
                        if bh >= 70 then
                            W.text_mid(box, { text = b.dur .. " 小时", x = 8, y = 48,
                                w = GDAY_W - 14, h = 22, size = T.f.mini, color = dt.text })
                        end
                    end
                    W.press_layer(col, { x = 2, y = by, w = GDAY_W - 4, h = bh, radius = 6,
                        on_click = function() R.go("detail", { idx = idx }) end })
                end
            end
        end
    end
    return g
end

-- ==================== 选中天（点日期标题切天） ====================
-- 选中态由三处共同表达：整列底色 col_bg、当前小时的整行底板 row_hl、表头/时间文字颜色。
-- 全部用透明度/颜色切换，不用 hide()/open()（真机上 open() 恢复不回来）。
local sel_sig                                          -- 上次绘制的 (选中天, 当前行) 签名，值没变就不重绘
local function paint_select()
    local row = -1
    if S.now_h >= S.room.open_h and S.now_h < S.room.close_h then
        row = math.floor(S.now_h - S.room.open_h)
        if row < 0 or row >= GROWS then row = -1 end
    end
    local sig = (S.today or 0) * 10000 + (sel_day or 0) * 100 + row   -- today 进签名：跨天后重算表头颜色
    if sig == sel_sig then return end
    sel_sig = sig

    for d = 1, 7 do
        local on = (d == sel_day)
        W.glass(col_bg[d], C.pri, on and 30 or 0)
        -- 已过去的日子表头始终压暗，选中时仍用主色
        W.color(head_lbls[d], on and C.pri or ((d < S.today) and C.text_dim or C.text_sub))
    end
    for i = 1, GROWS do                                -- 时间轴上当前那一行文字跟着提亮
        W.color(time_lbls[i], (i - 1 == row) and C.pri or C.text_dim)
    end
    if row_hl then
        if row >= 0 then
            pcall(function() row_hl:set_pos(GX, GBODY_Y + row * GROW_H) end)
            W.glass(row_hl, C.pri, 46)
        else
            W.glass(row_hl, C.pri, 0)                  -- 非开放时段：收起整行底板
        end
    end
end

function M.select_day(d)
    if type(d) ~= "number" or d < 1 or d > 7 then return end
    if sel_day == d then return end
    sel_day = d
    paint_select()
end

-- ==================== 数据刷新 ====================
local function paint_status()
    local cur = S.current()
    if cur then
        put(lb_badge, "badge", "使用中")
        W.color(lb_badge, C.danger)
        put(lb_title, "title", W.clip(cur.topic, 8))
        put(lb_l1, "l1", S.dept_name(cur.dept) .. " · " .. cur.seats .. " 人")
        put(lb_l2, "l2", "负责人 " .. S.owner_text(cur.owner))
        put(lb_l3, "l3", "时段 " .. S.range(cur))
        put(lb_l4, "l4", "预约工号 " .. ((cur.emp and cur.emp ~= "") and cur.emp or "访客"))
        local left = cur.start + cur.dur - S.now_h
        local mins = math.max(0, math.floor(left * 60 + 0.5))
        put(lb_remain, "remain", string.format("剩余 %d 分钟 · %s 结束", mins,
            S.fmt(cur.start + cur.dur)))
        local hot = (left <= 0.5)
        W.color(lb_remain, hot and C.danger or C.text_sub)
        local ratio = left / cur.dur
        local col = hot and C.danger or C.pri
        if math.abs(ratio - bar_r) > 0.01 or col ~= bar_c then
            bar_r, bar_c = ratio, col
            bar.set(ratio, col)
        end
    else
        put(lb_badge, "badge", "空闲中")
        W.color(lb_badge, C.ok)
        put(lb_title, "title", "暂无进行中的会议")
        local nx, _, nd = S.next_any()
        if nx then
            local when = (nd == S.today) and "今天" or (S.day_names[nd] or "")
            put(lb_l1, "l1", "下一场 " .. when .. " " .. S.fmt(nx.start))
            put(lb_l2, "l2", W.clip(nx.topic, 8) .. " · " .. S.dept_name(nx.dept))
        else
            put(lb_l1, "l1", "本周暂无预约")
            put(lb_l2, "l2", "点右侧空白时段即可预约")
        end
        put(lb_l3, "l3", string.format("%d 座 · %02d:00-%02d:00 开放",
            S.room.seats, S.room.open_h, S.room.close_h))
        put(lb_l4, "l4", "支持投屏 · 视频会议")
        put(lb_remain, "remain", "可立即预约")
        W.color(lb_remain, C.ok)
        if bar_r ~= 0 or bar_c ~= C.pri then
            bar_r, bar_c = 0, C.pri
            bar.set(0, C.pri)
        end
    end
end

local function paint_agenda()
    local list = S.today_list()
    local hours = 0
    for _, it in ipairs(list) do hours = hours + it.b.dur end
    put(lb_agcount, "cnt", (#list > 0) and (#list .. " 场 · " .. hours .. " 小时") or "")

    for i = 1, 3 do
        local it = agenda_items[i]
        local row = list[i]
        if row then
            put(it.time, "at" .. i, S.fmt(row.b.start))
            put(it.topic, "ap" .. i, W.clip(row.b.topic, 8))
            W.glass(it.dot, color_of(row.b.dept).accent, 255)
        else
            put(it.time, "at" .. i, "")
            put(it.topic, "ap" .. i, "")
            W.glass(it.dot, C.tile, 0)
        end
    end
    if #list == 0 then
        put(agenda_items[1].topic, "ap1", "今日暂无预约")
        W.color(agenda_items[1].topic, C.text_dim)
        W.glass(agenda_items[1].dot, C.tile, 0)
    elseif agenda_items[1].topic then
        W.color(agenda_items[1].topic, C.text)
    end
end

local function paint()
    S.refresh()
    put(lb_clock, "clock", S.clock_text())
    put(lb_date, "date", S.date_text())
    paint_status()
    paint_agenda()
    paint_select()                                 -- 含「当前小时」整行底板，跨小时后自动跟随
end

-- ==================== 生命周期 ====================
function M.root()
    return PAGE
end

function M.destroy()
    if timer then
        pcall(function() sys.timerStop(timer) end)
        timer = nil
    end
    if PAGE then
        pcall(function() PAGE:destroy() end)
        PAGE = nil
    end
    ROOT = nil
    cache, agenda_items = {}, {}
    bar, bar_r, bar_c = nil, -1, -1
    row_hl, time_lbls = nil, {}                    -- time_lbls 保持表：paint_select 会直接索引它
    sel_day, sel_sig = nil, nil
    head_lbls, col_bg = {}, {}
    lb_sub, lb_date, lb_head, lb_clock = nil, nil, nil, nil
    lb_badge, lb_title, lb_l1, lb_l2, lb_l3, lb_l4, lb_remain = nil, nil, nil, nil, nil, nil, nil
    lb_agcount = nil
end

function M.create()
    M.destroy()
    S.refresh()
    PAGE = airui.container({ parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, border_width = 0 })
    ROOT = PAGE
    cache, agenda_items = {}, {}
    bar_r, bar_c = -1, -1
    sel_day, sel_sig = S.today, nil                -- 进页面默认高亮今天
    build_topbar()
    build_status()
    build_agenda()
    build_week()
    paint()
    timer = sys.timerLoopStart(paint, 1000)
    log.info("page_home", "门牌主页已创建", T.mode)
end

return M
