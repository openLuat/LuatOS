--[[
@module page_room
@summary 会议室门牌主页面（单页 exwin，页面内三套模板 + 六个弹层 + toast）
         与 code/preview.html 1:1：
           1 天际线（城市剪影 + 圆盘时钟）  2 商务蓝（大时钟 + 塔 + 二维码）
           3 红白表格（左侧状态卡 + 右侧会议表格）
         弹层：会议详情 / 预约会议室 / 扫码签到 / 模板切换 / 门禁 / 会议日程

         三条硬规矩（踩坑记录）：
         1. 三套模板一次性建好，切模板只 set_hidden，不 destroy 重建；
         2. label 没有 set_hidden，需要隐藏的文字一律包一层容器，或直接 set_text("");
         3. 容器不保存 .w/.h，进度条等动态宽度自己用变量记账。
]]
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

local C   = theme.C
local S   = mock.state
local W, H = theme.W, theme.H

local PAGE                       -- make_page 返回的模块（主题切换要调 rerender）

--------------------------------------------------------------------
-- 小工具
--------------------------------------------------------------------
local function shape(parent, x, y, w, h, items)
    -- 登记图元：切主题时靠 set_items 就地换色，不重建 shape
    return theme.skin_shape(
        airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = items }), items)
end

local function line(x1, y1, x2, y2, col, wdt)
    return { type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = col,
             width = wdt or 1, round_start = true, round_end = true }
end

local function rect(x, y, w, h, col, r)
    return { type = "rect", x = x, y = y, w = w, h = h, color = col,
             radius = r or 0, width = 1, fill = true, fill_color = col, fill_opacity = 255 }
end

local function ring(cx, cy, r, col, wdt)
    return { type = "circle", cx = cx, cy = cy, r = r, color = col,
             width = wdt or 2, fill = false }
end

local function disc(cx, cy, r, col)
    return { type = "circle", cx = cx, cy = cy, r = r, color = col, width = 1,
             fill = true, fill_color = col, fill_opacity = 255 }
end

-- 时间相关文案
local function hm() return mock.fmt(S.vnow) end
local function date_long() return "2026/11/19" end
local function left_txt()
    return "会议中 · 剩余 " .. tostring(mock.left_min()) .. " 分钟"
end

-- 三套模板名（模板按钮 / 切换 toast 共用）
local TPL_NAME = { "天际线", "商务蓝", "红白表格" }

--------------------------------------------------------------------
-- 弹层 / toast（全页面共用一套）
--------------------------------------------------------------------
local layers_root, mask, sheets = nil, nil, {}
local cur_layer = nil
local toast_box, toast_lab, toast_timer = nil, nil, nil
local build_layers_ref            -- build_layers 的前向引用（懒建弹层用）
local layers_pending = false      -- true = 本次重建先不建弹层，等第一次打开再建
local pending_layers = false      -- 弹层还没建（show_layer 里补建）
local root_ref                    -- 当前页面 root（懒建弹层时挂控件用；模板挂在 tpl_root 上）

-- 重建控件树必须离开 LVGL 事件回调（回调里 destroy 控件树会卡死 / 看门狗复位），
-- 统一丢给 sys.timerStart 30ms 之后再做
local function defer(fn)
    sys.timerStart(function() pcall(fn) end, 30)
end

local function close_layers()
    if not layers_root then return end
    pcall(layers_root.set_hidden, layers_root, true)
    cur_layer = nil
end

local function show_layer(name)
    -- 弹层可能还没建（主题切换后的懒建路径，或者上一次构建中途出错）：
    -- 这里必须自己补建，不能静默 return —— 否则表现就是「按钮点了没反应」
    if not layers_root then
        if not (build_layers_ref and root_ref) then return end
        pending_layers = false
        defer(function()
            if not layers_root then
                build_layers_ref(root_ref)
                close_layers()
            end
            show_layer(name)
        end)
        return
    end
    for k, v in pairs(sheets) do
        if v.cont then pcall(v.cont.set_hidden, v.cont, k ~= name) end
    end
    pcall(layers_root.set_hidden, layers_root, false)
    cur_layer = name
    if sheets[name] and sheets[name].on_show then pcall(sheets[name].on_show) end
    -- 只刷当前弹层相关的内容（原来每次点开都全量刷一遍，点一下要等几十次 set_text）
    if name == "sched" and PAGE and PAGE.refresh_rows then PAGE.refresh_rows() end
    if name == "book" and PAGE and PAGE.refresh_book then PAGE.refresh_book() end
    if name == "door" and PAGE and PAGE.refresh_door then PAGE.refresh_door() end
end

-- toast 用固定 520×46 的条（label 改宽度会错位，固定尺寸最稳）
local function toast(msg)
    if not toast_box then return end
    pcall(toast_lab.set_text, toast_lab, msg or "")
    pcall(toast_box.set_hidden, toast_box, false)
    if toast_timer then sys.timerStop(toast_timer) end
    toast_timer = sys.timerStart(function()
        pcall(toast_box.set_hidden, toast_box, true)
        toast_timer = nil
    end, 1800)
end

-- 主题切换：只做原地改色（theme.repaint），**绝不重建页面**。
-- 之前 repaint 失效时会退回 PAGE.rerender()，而 rerender 会 destroy 整个 root ——
-- 弹层、模板、toast 全没了，layers_root 变 nil，于是「切完主题点模板按钮没反应」。
-- 现在无论 repaint 成功与否都保留控件树：最坏情况只是颜色没变，点击始终可用。
local theme_timer
local function toggle_theme()
    theme.toggle_theme()
    -- 触摸屏一次点击经常进来两次回调：两次 toggle 会把主题来回抵消，
    -- 并让 repaint 的 from == to。这里 40ms 窗口内只跑最后一次。
    if theme_timer then sys.timerStop(theme_timer) end
    theme_timer = sys.timerStart(function()
        theme_timer = nil
        local ok, n = pcall(theme.repaint)
        if not ok and log and log.error then
            log.error("page", "theme.repaint failed: " .. tostring(n))
        end
        if PAGE and PAGE.redraw_all then pcall(PAGE.redraw_all) end
        toast(theme.cur == "light" and "已切换浅色主题" or "已切换深色主题")
    end, 40)
end

-- 取消某一笔（带 bid 直接取消；不带就用日程里选中的那笔 / 最后一笔）
local function cancel_one(bid)
    local b = bid and mock.find_book(bid)
    if not b and S.sel_bid then b = mock.find_book(S.sel_bid) end
    if not b and #S.bookings > 0 then b = S.bookings[#S.bookings] end
    if not b then toast("当前没有预约") return end
    mock.del_booking(b.bid)
    close_layers()
    PAGE.redraw_all()
    toast("已取消预约 · " .. (b.day == 2 and "明天 " or "")
        .. mock.fmt(b.st) .. "-" .. mock.fmt(b.et) .. " 已释放")
end

-- 预约弹层里那条「取消预约」：直接取消最新那笔（html cancel-last）
local function cancel_last()
    local b = S.bookings[#S.bookings]
    if not b then toast("当前没有预约") return end
    cancel_one(b.bid)
end

-- 三套模板的「取消预约」入口：有货就直接释放（用户点了取消就该消失），
-- 之前这里是「选中 + 打开日程」，点了看起来毫无反应，是真机上最刺眼的 bug
local function cancel_flow()
    if #S.bookings == 0 then toast("当前没有预约") return end
    cancel_one(nil)
end

-- 点某场会议 → 设为「正在使用」，虚拟时钟落到该场时段内（= html setCurrent）
local function set_current(m)
    if not m then return end
    if (m.idx or 0) <= 0 then
        toast("这是你的预约场次，选它再点「取消预约」即可取消")
        return
    end
    S.cur, S.free = m.idx, false
    if S.vnow < m.st + 1 then S.vnow = m.st + 1 end
    if S.vnow > m.et - 1 then S.vnow = m.et - 1 end
    PAGE.redraw_all()
    toast("已切换为：" .. mock.fmt(m.st) .. " - " .. mock.fmt(m.et) .. " " .. m.topic)
end

-- 会议中 / 空闲 互切（html data-act="state"）
local function toggle_free()
    S.free = not S.free
    PAGE.redraw_all()
    toast(S.free and "会议已结束 · 房间空闲，可立即预约" or "已恢复为「会议中」")
end

--------------------------------------------------------------------
-- 模板 1：天际线（深蓝夜空 + 城市剪影 + 圆盘时钟）
--------------------------------------------------------------------
local function build_a(p, dy)
    theme.box(p, 0, 0, W, 300, C.bg_top)
    theme.box(p, 0, 300, W, 130, C.bg)
    theme.box(p, 0, 430, W, H - 430, C.bg_bot)

    -- 城市剪影：楼底贴屏幕底（600），两批图元（每批 ≤30，超过会丢图元）
    local hs = { 64, 118, 86, 150, 104, 72, 132, 96, 160, 110, 78, 140, 92, 120, 66, 100 }
    local ws = { 62, 48, 72, 44, 58, 80, 50, 66, 42, 70, 54, 60, 74, 46, 64, 56 }
    local i1, i2 = {}, {}
    local x = -6
    for i = 1, #hs do
        local bw, bh = ws[i], hs[i]
        local it = (i % 2 == 0) and i2 or i1
        it[#it + 1] = rect(x, 170 - bh, bw, bh, (i % 2 == 0) and C.city2 or C.city1)
        if i % 3 == 1 then
            it[#it + 1] = rect(x + 10, 170 - bh + 12, 7, 10, C.citywin)
            it[#it + 1] = rect(x + 26, 170 - bh + 12, 7, 10, C.citywin)
        end
        x = x + bw + 12
    end
    shape(p, 0, 430, W, 170, i1)
    shape(p, 0, 430, W, 170, i2)
    -- 雾化：越靠底越实（html 的 gradient(to top)）
    theme.box_a(p, 0, 452, W, 148, C.bg_bot, 0, 80)
    theme.box_a(p, 0, 500, W, 100, C.bg_bot, 0, C.haze_opa)

    -- 顶栏（白条 + 品牌 + 工具）
    theme.box(p, 0, 0, W, 58, C.card)
    theme.icon(p, 22, 14, 30, "door", C.red)
    theme.txt(p, 64, 14, 240, 30, mock.room.brand, C.text, 20)
    -- 工具条：按钮样式统一画，点击交给上面的透明热区（闭包参数自己捕获，别在 for 里塞）
    theme.btn(p, 568, 9, 100, 40, "扫码签到", C.card2, C.text, C.line, 1, 6, nil)
    dy.a_dnd = theme.btn(p, 678, 9, 84, 40, "免打扰", C.card2, C.text, C.line, 1, 6, nil)
    dy.a_theme = theme.btn(p, 772, 9, 68, 40, theme.cur == "dark" and "浅色" or "深色",
        C.card2, C.text, C.line, 1, 6, nil)
    dy.tpl_btn = dy.tpl_btn or {}
    dy.tpl_btn[1] = theme.btn(p, 850, 9, 150, 40, "模板 · " .. TPL_NAME[S.tpl],
        C.card2, C.text, C.line, 1, 6, nil)
    theme.hit(p, 568, 9, 100, 40, function() show_layer("qr") end)
    theme.hit(p, 678, 9, 84, 40, function() S.dnd = not S.dnd; PAGE.redraw_dnd() end)
    theme.hit(p, 772, 9, 68, 40, toggle_theme)
    theme.hit(p, 850, 9, 150, 40, function() show_layer("tpl") end)

    -- 左：会议室名 / 副标题 / 容量
    theme.txt(p, 56, 150, 400, 56, mock.room.name, C.text2, 44)
    theme.txt(p, 56, 216, 400, 26, "M E E T I N G   R O O M", C.sub, 18)
    theme.txt(p, 56, 258, 400, 26, mock.room.floor .. " · 可容纳 " .. mock.room.cap .. " 人", C.sub, 16)

    -- 中：圆盘时钟（点盘面切「当前时间 / 会议剩余时间」两个面，与 preview.html 一致）
    local DX, DY = 396, 182          -- 盘心 = (512, 298)
    -- 细刻度 60 格（每 6°）：分两批，单批 ≤30 图元（一批塞 60 个会丢图元）
    local tA, tB, tC = {}, {}, {}
    for i = 0, 59 do
        local a = math.rad(i * 6 - 90)
        local g = (i < 30) and tA or tB
        g[#g + 1] = line(116 + math.floor(math.cos(a) * 96), 116 + math.floor(math.sin(a) * 96),
                         116 + math.floor(math.cos(a) * 106), 116 + math.floor(math.sin(a) * 106),
                         C.ring1, 1)
    end
    -- 时刻度 12 格（每 30°，更长更粗）
    for i = 0, 11 do
        local a = math.rad(i * 30 - 90)
        tC[#tC + 1] = line(116 + math.floor(math.cos(a) * 86), 116 + math.floor(math.sin(a) * 86),
                           116 + math.floor(math.cos(a) * 97), 116 + math.floor(math.sin(a) * 97),
                           C.ring2, 2)
    end
    dy.a_dial = theme.box_b(p, DX, DY, 232, 232, C.dial1, 116, C.ring2, 1)
    shape(p, DX, DY, 232, 232, tA)
    shape(p, DX, DY, 232, 232, tB)
    shape(p, DX, DY, 232, 232, tC)

    -- 面 1：当前时间（html: 时钟 44 → 间隔 12 → 分隔线+日期 → 间隔 7 → 星期）
    -- label 没有 set_hidden，整面文字必须装进一个透明容器，切面时只对容器做显隐
    -- （否则两个面会叠在一起：时间和「剩余时间」糊成一团）
    local face_clock = theme.box_a(p, DX, DY, 232, 232, C.dial1, 116, 0)
    dy.a_clock = theme.txt(face_clock, 0, 51, 232, 56, hm(), C.text2, 44, "center")
    theme.box(face_clock, 72, 119, 88, 2, C.ring2, 1)
    dy.a_date = theme.txt(face_clock, 0, 130, 232, 22, date_long(), C.sub, 16, "center")
    dy.a_week = theme.txt(face_clock, 0, 159, 232, 22, mock.date.week, C.sub, 16, "center")

    -- 面 2：会议剩余时间（透明容器：盖住文字但露出刻度）
    local face_left = theme.box_a(p, DX, DY, 232, 232, C.dial1, 116, 0)
    dy.a_lmin = theme.txt(face_left, 0, 51, 120, 56, "0", C.text2, 44, "right")
    theme.txt(face_left, 124, 66, 64, 26, "分钟", C.sub, 16)
    dy.a_llab = theme.txt(face_left, 0, 130, 232, 22, "剩余时间", C.sub, 16, "center")
    dy.a_ltip = theme.txt(face_left, 0, 159, 232, 22, "", C.sub, 16, "center")
    dy.a_left = face_left

    local function apply_dial()
        local clock_on = (S.dial == "clock")
        pcall(face_clock.set_hidden, face_clock, not clock_on)
        pcall(face_left.set_hidden, face_left, clock_on)
    end
    apply_dial()
    theme.hit(p, DX, DY, 232, 232, function()
        S.dial = (S.dial == "clock") and "left" or "clock"
        apply_dial()
        -- 提示要说「还剩多久」，而不是干巴巴一句「表盘显示会议剩余时间」
        if S.dial == "clock" then
            toast("现在是 " .. hm())
        elseif S.free then
            local nm = mock.next_meeting()
            if nm then
                local gap = math.max(0, math.ceil(nm.st - S.vnow))
                toast(string.format("距下一场还有 %d 分钟 · %s 开始", gap, mock.fmt(nm.st)))
            else
                toast("今天没有后续会议了")
            end
        else
            local m = mock.cur_meeting()
            toast(string.format("会议还剩 %d 分钟 · 预计 %s 结束",
                mock.left_min(), m and mock.fmt(m.et) or "--:--"))
        end
    end)

    -- 右：当前会议（html .a-right：650,128 宽 322）
    local tk_fg = (theme.cur == "dark") and C.white or C.red2
    dy.a_label = theme.txt(p, 650, 128, 350, 22, "CURRENT MEETING · 当前会议", C.tagc, 16)
    dy.a_range = theme.txt(p, 650, 160, 350, 40, "", C.text2, 30)
    theme.box(p, 650, 216, 348, 52, C.redsoft, 6)
    theme.box(p, 650, 216, 5, 52, C.red, 2)
    dy.a_topic = theme.txt(p, 670, 216, 318, 52, "", tk_fg, 18)
    dy.a_next = theme.txt(p, 650, 286, 350, 26, "", C.sub, 16)
    -- 会议主题卡片可点（html data-act="detail"）
    theme.hit(p, 650, 216, 348, 52, function()
        S.detail_m = mock.cur_meeting() or mock.next_meeting() or mock.base[1]
        show_layer("detail")
    end)
    -- 房名可点：报一次房间信息（html data-act="room"）
    theme.hit(p, 56, 150, 400, 56, function()
        toast(mock.room.name .. " · " .. mock.room.floor .. " · 可容纳 " .. mock.room.cap .. " 人")
    end)

    -- 底栏（html: 高 64，渐变蓝）
    theme.box(p, 0, 536, W, 64, C.blue)
    theme.box_a(p, 0, 536, W, 20, C.blue2, 0, 120)
    dy.a_dot = theme.circle(p, 26, 563, 10, C.yellow)
    dy.a_status = theme.txt(p, 46, 536, 400, 64, "", C.white, 16)
    -- 左下状态区可点：会议中 / 空闲 互切（html data-act="state"）
    theme.hit(p, 20, 542, 300, 52, toggle_free)
    local fb = { { 518, 88, "会议详情", "detail" }, { 616, 88, "会议日程", "sched" },
                 { 714, 104, "预约会议室", "book" } }
    for i = 1, #fb do
        local b = fb[i]
        theme.btn(p, b[1], 546, b[2], 44, b[3], C.blue2, C.white, C.white, 1, 6, nil)
        theme.hit(p, b[1], 546, b[2], 44, function()
            if b[4] == "detail" then
                S.detail_m = mock.cur_meeting() or mock.next_meeting() or mock.base[1]
            end
            show_layer(b[4])
        end)
    end
    -- 有预约时才出现：红底「取消预约」（html .tool.warn，rgba(206,52,60,.92) 白字）
    -- button 没有 set_hidden，所以外面套一层透明容器，显隐打在容器上
    local acbox = theme.box_a(p, 828, 546, 88, 44, C.card, 6, 0)
    theme.btn(acbox, 1, 2, 86, 40, "取消预约", C.red, C.white, C.white, 1, 6, nil)
    theme.hit(acbox, 0, 0, 88, 44, cancel_flow)
    pcall(acbox.set_hidden, acbox, true)
    dy.a_cancel_btn = acbox
    -- 开门：白底深蓝字（深色主题下用 card 底 + text 字，避免白底白字糊成一块白）
    dy.a_door = theme.btn(p, 926, 546, 72, 44, "开门", C.card, C.text, C.white, 1, 6, nil)
    theme.hit(p, 926, 546, 72, 44, function() show_layer("door") end)
end

--------------------------------------------------------------------
-- 二维码：21×21 伪随机码点 + 三个定位角（纯 shape 绘制，不贴图）
-- html 里是 25×25 的 img，这里用行内合并 + 分批 ≤26 图元的 shape 还原观感
--------------------------------------------------------------------
local function qr_items(x0, y0, cell, col)
    local N = 21
    local function finder(fx, fy)
        -- 三个定位角 + 它们外圈的 1 格白色隔离带（真 QR 一定有，缺了就像马赛克）
        return (fx < 7 and fy < 7)
            or (fx >= N - 7 and fy < 7)
            or (fx < 7 and fy >= N - 7)
    end
    local function guard(fx, fy)
        -- 每个定位角外侧各留一格空白（真 QR 的隔离带）
        if fy == 7 and fx < 8 then return true end        -- 左上角下方
        if fx == 7 and fy < 8 then return true end        -- 左上角右侧
        if fy == 7 and fx >= N - 8 then return true end   -- 右上角下方
        if fx == N - 8 and fy < 8 then return true end    -- 右上角左侧
        if fy == N - 8 and fx < 8 then return true end    -- 左下角上方
        if fx == 7 and fy >= N - 8 then return true end   -- 左下角右侧
        return false
    end
    local function dark(cx, cy)
        -- 定时图案：第 6 行/列黑白相间，非常像真二维码
        if cy == 6 and cx > 7 and cx < N - 8 then return (cx % 2 == 0) end
        if cx == 6 and cy > 7 and cy < N - 8 then return (cy % 2 == 0) end
        -- 双重 hash 打散：单用 cx*cy 会排出明显的斜纹（旧版本就是一团漩涡）
        local h = (cx * 73856093) % 1000003 + (cy * 19349663) % 1000033
            + (cx * cy * 193) % 999983
        return (h * 31 + 17) % 100 < 47
    end
    local items = {}
    for cy = 0, N - 1 do
        for cx = 0, N - 1 do
            if not finder(cx, cy) and not guard(cx, cy) and dark(cx, cy) then
                -- 一格一个方块，不横向合并：合并出来的长条一眼就假
                items[#items + 1] = rect(x0 + cx * cell, y0 + cy * cell, cell, cell, col)
            end
        end
    end
    -- 三个定位角：外框 7×7 → 内白 5×5 → 实心 3×3
    local fx = { 0, N - 7, 0 }
    local fy = { 0, 0, N - 7 }
    for i = 1, 3 do
        local px, py = x0 + fx[i] * cell, y0 + fy[i] * cell
        items[#items + 1] = rect(px, py, 7 * cell, 7 * cell, col)
        items[#items + 1] = rect(px + cell, py + cell, 5 * cell, 5 * cell, C.qr_bg)
        items[#items + 1] = rect(px + 2 * cell, py + 2 * cell, 3 * cell, 3 * cell, col)
    end
    return items
end

local function draw_qr(parent, x, y, size, col)
    local cell = math.floor(size / 21)
    local off = math.floor((size - cell * 21) / 2)
    -- shape 的图元坐标是相对 (x,y) 的，这里统一按相对坐标生成
    local items = qr_items(off, off, cell, col or C.qr_fg)
    local i = 1
    while i <= #items do
        local batch = {}
        for k = i, math.min(i + 25, #items) do batch[#batch + 1] = items[k] end
        shape(parent, x, y, size, size, batch)
        i = i + 26
    end
end

--------------------------------------------------------------------
-- 模板 2：商务蓝（大时钟 + 同心弧 + 通信塔 + 二维码）
--------------------------------------------------------------------
local function build_b(p, dy)
    theme.box(p, 0, 0, W, H, C.b2)
    theme.box(p, 0, 0, W, 200, C.b1)
    theme.box(p, 0, 420, W, 180, C.b3)

    -- 同心圆（html 是三个 800/540/340 的圆，只留描边）
    local arcs = {
        ring(784, 200, 400, C.arc, 2),
        ring(734, 180, 270, C.arc, 2),
        ring(734, 190, 170, C.arc, 2),
    }
    shape(p, 0, 0, W, H, arcs)

    -- 通信塔（塔身 + 两层平台 + 圆环；坐标来自 html 的 SVG 105 中轴）
    local tw = {
        line(827, 130, 827, 178, C.arc, 2),
        line(824, 218, 824, 310, C.arc, 2),
        line(830, 218, 830, 310, C.arc, 2),
        line(821, 356, 821, 422, C.arc, 3),
        line(833, 356, 833, 422, C.arc, 3),
        line(818, 482, 772, 600, C.arc, 2),
        line(836, 482, 882, 600, C.arc, 2),
        line(827, 482, 827, 600, C.arc, 2),
        ring(827, 198, 14, C.arc, 2),
        ring(827, 330, 30, C.arc, 2),
        ring(827, 448, 38, C.arc, 2),
    }
    shape(p, 0, 0, W, H, tw)

    -- 左上：大时钟 + 日期
    dy.b_clock = theme.txt(p, 56, 36, 420, 80, hm(), C.text2, 64)
    dy.b_date = theme.txt(p, 56, 122, 420, 24, date_long() .. "  " .. mock.date.week, C.sub, 16)

    -- 右上：工具（html 顺序：会议日程 / 取消预约 / 免打扰 / 深色 / 模板）
    theme.btn(p, 468, 42, 88, 44, "会议日程", C.card2, C.text, C.line, 1, 6, nil)
    theme.hit(p, 468, 42, 88, 44, function() show_layer("sched") end)
    -- 取消预约：整块容器（含文字+热区），有预约时才显示
    local cbox = theme.box_b(p, 566, 42, 88, 44, C.card2, 6, C.red, 1)
    theme.txt(cbox, 0, 0, 88, 44, "取消预约", C.red2, 16, "center")
    theme.hit(cbox, 0, 0, 88, 44, cancel_flow)
    dy.cancel_b = cbox
    dy.b_dnd = theme.btn(p, 664, 42, 84, 44, "免打扰", C.card2, C.text, C.line, 1, 6, nil)
    dy.b_theme = theme.btn(p, 758, 42, 68, 44, theme.cur == "dark" and "浅色" or "深色",
        C.card2, C.text, C.line, 1, 6, nil)
    dy.tpl_btn = dy.tpl_btn or {}
    dy.tpl_btn[2] = theme.btn(p, 836, 42, 132, 44, "模板 · " .. TPL_NAME[S.tpl],
        C.card2, C.text, C.line, 1, 6, nil)
    theme.hit(p, 664, 42, 84, 44, function() S.dnd = not S.dnd; PAGE.redraw_dnd() end)
    theme.hit(p, 758, 42, 68, 44, toggle_theme)
    theme.hit(p, 836, 42, 132, 44, function() show_layer("tpl") end)

    -- 会议中 / 空闲 双芯片（html: 56,198 两个 222×84 并排）
    -- 外面再套一个大框，把「房名 + 状态」整体框住
    -- （原来只有右边状态芯片自己带边框；这里用四条 1px 线画空心框，不会遮住底色）
    shape(p, 50, 192, 456, 96, {
        line(0, 0, 455, 0, C.line, 1),
        line(0, 95, 455, 95, C.line, 1),
        line(0, 0, 0, 95, C.line, 1),
        line(455, 0, 455, 95, C.line, 1),
    })
    theme.box_b(p, 56, 198, 222, 84, C.card, 8, C.line, 1)
    theme.txt(p, 76, 210, 190, 34, mock.room.name, C.text, 22)
    theme.txt(p, 76, 250, 190, 24, "MEETING ROOM", C.sub, 16)
    dy.b_chip = theme.box_b(p, 278, 198, 222, 84, C.redsoft, 8, C.red, 1)
    dy.b_chip_b = theme.txt(p, 298, 210, 190, 34, "会议中", C.red2, 22)
    dy.b_chip_e = theme.txt(p, 298, 250, 190, 24, "IN MEETING", C.sub, 16)
    -- 双芯片可点：会议中 / 空闲 互切（html data-act="state"）
    theme.hit(dy.b_chip, 0, 0, 222, 84, toggle_free)

    -- 当前会议（html .b-label 前面有个 16px 小日历图标，但 16px 下描边框 +
    -- 内部横线糊在一起，看着就是个空方框，直接不要图标，标题从原图标位起排）
    dy.b_label = theme.txt(p, 56, 330, 540, 22, "CURRENT MEETING · 当前会议", C.tagc, 16)
    dy.b_topic = theme.txt(p, 56, 366, 740, 42, "", C.text2, 30)
    theme.hit(p, 56, 360, 740, 54, function()
        S.detail_m = mock.cur_meeting() or mock.next_meeting() or mock.base[1]
        show_layer("detail")
    end)
    dy.b_time = theme.txt(p, 56, 422, 500, 26, "", C.text, 20)
    theme.box_a(p, 56, 468, 380, 6, C.prog_track, 3, C.prog_opa)
    dy.b_fill = theme.box(p, 56, 468, 10, 6, C.blue, 3)
    dy.b_ptext = theme.txt(p, 56, 484, 460, 22, "", C.sub, 16)

    -- 二维码卡片（html: right 72 / bottom 90，140×140 白卡 + 126 码）
    -- 126 = 21 × 6，每格 6px 整除，不会出现半格糊边
    -- 第 8 参数点名语义键：浅色下 qr_bg 与 card 同为白色，按值反查会认成卡片
    theme.box(p, 812, 338, 140, 140, C.qr_bg, 10, "qr_bg")
    draw_qr(p, 819, 345, 126, C.qr_fg)
    theme.txt(p, 812, 488, 140, 22, "扫码签到", C.sub, 16, "center")
    theme.hit(p, 812, 338, 140, 140, function() show_layer("qr") end)

    -- 底部圆点 = 模板指示器（点哪个切哪个，与 preview 的 dotsB 一致）
    local dxs = { 56, 108, 160 }
    dy.b_dots, dy.b_dotp = {}, {}
    for i = 1, 3 do
        dy.b_dots[i] = theme.circle(p, dxs[i], 548, 10, C.dim)
        dy.b_dotp[i] = theme.box(p, dxs[i] - 9, 548, 28, 10, C.blue, 5)
        pcall(dy.b_dotp[i].set_hidden, dy.b_dotp[i], true)
        local idx = i
        theme.hit(p, dxs[i] - 9, 530, 46, 40, function() PAGE.set_tpl(idx) end)
    end
end

--------------------------------------------------------------------
-- 模板 3：红白表格（状态卡 + 会议表格，门户风）
--------------------------------------------------------------------
local ROW_MAX = 6       -- 日程弹层最多 6 行
-- 表格模板 6 行：预约几场就要能看见几场（原来固定 4 行，第 3 场起就被挤掉，
-- 用户会以为「只记住了一场」）。6 行 +「下一场」条正好铺到 598 < 600。
local ROW_C   = 6

local function build_c(p, dy)
    theme.box(p, 0, 0, W, H, C.c3)
    -- 背景：四块虚化色斑（用大圆角容器模拟照片景深）
    -- 关键：必须夹在屏幕内。色斑超出 W/H（或用到负坐标）会让父容器产生滚动范围，
    -- LVGL 就在屏幕底部画一条横滚动条 —— 就是表格底下那条「下划线」。
    theme.box(p, 0, 0, 540, 320, C.c1, 190)
    theme.box(p, 420, 180, W - 420, 420, C.c2, 210)
    theme.box(p, 120, 320, 560, H - 320, C.c4, 170)
    theme.box_a(p, 0, 0, W, H, C.cshade, 0, C.cshade_opa)

    -- 顶栏（html: 高 72，红底；右侧 免打扰/深色/模板 + 大时钟 + 日期）
    theme.box(p, 0, 0, W, 72, C.ctop1)
    theme.box_a(p, 0, 60, W, 12, C.ctop2, 0, 120)
    theme.icon(p, 26, 20, 32, "door", C.white)
    theme.txt(p, 68, 20, 260, 32, mock.room.brand, C.white, 20)
    dy.c_dnd = theme.btn(p, 458, 14, 84, 44, "免打扰", C.ctop2, C.white, C.redsoft, 1, 6, nil)
    dy.c_theme = theme.btn(p, 552, 14, 68, 44, theme.cur == "dark" and "浅色" or "深色",
        C.ctop2, C.white, C.redsoft, 1, 6, nil)
    dy.tpl_btn = dy.tpl_btn or {}
    dy.tpl_btn[3] = theme.btn(p, 630, 14, 150, 44, "模板 · " .. TPL_NAME[S.tpl],
        C.ctop2, C.white, C.redsoft, 1, 6, nil)
    theme.hit(p, 458, 14, 84, 44, function() S.dnd = not S.dnd; PAGE.redraw_dnd() end)
    theme.hit(p, 552, 14, 68, 44, toggle_theme)
    theme.hit(p, 630, 14, 150, 44, function() show_layer("tpl") end)
    -- 顶栏垂直居中：栏高 72、按钮 y=14 高 44（中心 36）。
    -- 时钟/日期原来 h 给 44/24 但字号只有 30/16，theme.txt 居中后中心落在 32，
    -- 比按钮里的文字高 4px —— 就是「时间和免打扰没对齐」。
    -- 改成让 h 正好等于行高（30→38、16→21），中心与按钮一致 = 36。
    dy.c_clock = theme.txt(p, 798, 17, 80, 38, hm(), C.white, 30)
    theme.txt(p, 880, 26, 132, 21, mock.date.md .. " " .. mock.date.week, C.redsoft, 16)

    -- 左栏（html: left 40 / top 96 / 宽 272）
    theme.box(p, 40, 96, 272, 76, C.ccard, 4)
    theme.txt(p, 40, 96, 272, 76, mock.room.name, C.ccardtext, 28, "center")
    theme.hit(p, 40, 96, 272, 76, function()
        toast(mock.room.name .. " · " .. mock.room.floor .. " · 可容纳 " .. mock.room.cap .. " 人")
    end)

    dy.c_state = theme.box(p, 40, 184, 272, 103, C.ccard, 4)
    dy.c_state_b = theme.txt(p, 40, 206, 272, 36, "正在使用", C.red, 24, "center")
    dy.c_state_s = theme.txt(p, 40, 250, 272, 24, "OCCUPIED", C.sub, 16, "center")
    -- 状态卡可点：会议中 / 空闲 互切（html data-act="state"）
    theme.hit(p, 40, 184, 272, 103, toggle_free)

    dy.c_lock = theme.box(p, 40, 299, 272, 64, C.ccard, 4)
    dy.c_lockic = theme.icon(dy.c_lock, 20, 22, 20, "lock", C.red)
    dy.c_locktx = theme.txt(dy.c_lock, 52, 0, 200, 64, "门禁已上锁", C.ccardtext, 17)
    theme.hit(p, 40, 299, 272, 64, function() show_layer("door") end)

    local b1 = theme.box(p, 40, 375, 131, 56, C.ccard, 4)
    theme.icon(b1, 14, 16, 20, "cal", C.ccardtext)
    theme.txt(b1, 40, 0, 80, 56, "会议日程", C.ccardtext, 16)
    theme.hit(p, 40, 375, 131, 56, function() show_layer("sched") end)

    theme.box(p, 181, 375, 131, 56, C.ctop1, 4)
    theme.txt(p, 181, 375, 131, 56, "预约会议室", C.white, 16, "center")
    theme.hit(p, 181, 375, 131, 56, function() show_layer("book") end)

    -- 我预约时出现（html 是红色虚线框：虚线画不出来，用 1px 红边代替）
    local ccl = theme.box_b(p, 40, 443, 272, 52, C.ccard, 4, C.red, 1)
    theme.txt(ccl, 0, 0, 272, 52, "取消预约", C.red, 17, "center")
    theme.hit(ccl, 0, 0, 272, 52, cancel_flow)
    dy.c_cancel = ccl

    -- 右栏表格（html: left 332 / top 96 / 宽 652）
    theme.box(p, 332, 96, 652, 46, C.chead, 4)
    theme.txt(p, 350, 96, 140, 46, "时间", C.cheadtext, 16)
    theme.txt(p, 490, 96, 300, 46, "会议主题", C.cheadtext, 16)
    theme.txt(p, 818, 96, 92, 46, "人数", C.cheadtext, 16, "right")

    dy.rows = {}
    for i = 1, ROW_C do
        local y = 150 + (i - 1) * 66
        local row = theme.box(p, 332, y, 652, 58, C.crow, 4)
        local tm = theme.txt(row, 18, 0, 140, 58, "", C.sub, 16)
        local topic = theme.txt(row, 158, 0, 320, 58, "", C.crowtext, 17)
        -- 人数列右移缩小，给右边的切换/取消按钮留出 14px 间距（原来两者贴在一起很难看）
        local ppl = theme.txt(row, 466, 0, 100, 58, "", C.sub, 16, "right")
        -- 行尾：状态标签（进行中/我预约/已结束）或操作按钮（切换/取消），字号统一 16
        local tagc = theme.box_a(row, 580, 12, 62, 34, C.card, 6, 140)
        local tagtx = theme.txt(tagc, 0, 0, 62, 34, "", C.dim, 16, "center")
        pcall(tagc.set_hidden, tagc, true)
        -- 操作按钮不画边框（1px 边框容易被看成「下划线/右划线」），纯色块更干净
        local goc = theme.box(row, 580, 12, 62, 34, C.card2, 6)
        local gotx = theme.txt(goc, 0, 0, 62, 34, "切换", C.red2, 16, "center")
        local idx = i
        theme.hit(goc, 0, 0, 62, 34, function()
            local m = dy.rows[idx] and dy.rows[idx].data
            if not m then return end
            if m.mine then
                -- 我的预约：按钮直接就是「取消」，点一下就释放（= 用户直觉）
                cancel_one(m.bid)
            else
                set_current(m)
            end
        end)
        -- 行左侧可点：看这一行的会议详情（html data-act="detail"）
        theme.hit(row, 0, 0, 566, 58, function()
            S.detail_m = (dy.rows[idx] and dy.rows[idx].data) or nil
            show_layer("detail")
        end)
        dy.rows[i] = { cont = row, tm = tm, topic = topic, ppl = ppl,
                       tagc = tagc, tagtx = tagtx, goc = goc, gotx = gotx, data = nil }
        pcall(row.set_hidden, row, true)
    end

    -- 下一场（6 行表格之后：y = 150 + 6*66 = 546；条高 46、底 592，
    -- 离屏幕底留 8px，避免贴边时被看成多出一条横线）
    theme.box(p, 332, 546, 652, 46, C.crow, 4)
    dy.c_next = theme.txt(p, 352, 546, 500, 46, "", C.sub, 16)
    theme.box_b(p, 894, 553, 80, 32, C.crow, 4, C.red, 1)
    theme.txt(p, 894, 553, 80, 32, "预约", C.red2, 16, "center")
    -- 点击层必须最后建：LVGL 是后创建的盖在上面，
    -- 之前把 hit 写在按钮前面，被按钮盖住，所以「预约」完全点不动
    theme.hit(p, 892, 546, 84, 46, function() show_layer("book") end)
end

--------------------------------------------------------------------
-- 六个弹层
--------------------------------------------------------------------
local dy, sp = {}, {}
-- 三套模板的公共父容器：模板是懒建的，如果直接挂在 root 上，后建的模板会排在
-- layers_root / toast 之后（z 序更高）——切到商务蓝后点「会议日程」，弹层其实开了，
-- 但整块被当前模板盖住，看起来就是「点了没反应」。统一塞进 tpl_root 就永远在弹层下面。
local tpl_root

-- 弹层：宽度按 html（普通 470 / 日程 552 / 扫码·门禁 404），垂直居中
local function mk_sheet(name, w, h)
    w = w or 470
    local x = math.floor((W - w) / 2)
    local y = math.floor((H - h) / 2)
    return theme.box(layers_root, x, y, w, h, C.panel, 16), x, y
end

local function sheet_close(cont, w)
    local cx = w - 48
    theme.hit(cont, cx, 4, 44, 44, close_layers)
    theme.icon(cont, cx + 12, 16, 18, "close", C.dim)
end

local function build_layers(root)
    layers_root = theme.box_a(root, 0, 0, W, H, C.mask, 0, C.mask_opa)
    theme.hit(layers_root, 0, 0, W, H, close_layers)

    -- 1) 会议详情（html: 470 宽；主题作为副标题，下面 4 行 kv + 会议内容块）
    local d, dx = mk_sheet("detail", 470, 512)
    theme.txt(d, 26, 22, 340, 30, "会议详情", C.text, 22)
    local dsub = theme.txt(d, 26, 58, 380, 22, "", C.sub, 16)
    sheet_close(d, 470)
    local kvn = { "时间", "预约人", "参会人数", "会议室" }
    local kl = {}
    for i = 1, 4 do
        local y = 92 + (i - 1) * 44
        theme.txt(d, 26, y, 110, 44, kvn[i], C.sub, 16)
        kl[i] = theme.txt(d, 140, y, 300, 44, "", C.text, 16)
        shape(d, 26, y + 43, 418, 1, { rect(0, 0, 418, 1, C.line) })
    end
    -- 内容块加高到 164：原来 118 高、说明只留一行 14px，长句直接被裁掉
    theme.box(d, 26, 276, 418, 164, C.panel2, 8)
    theme.txt(d, 42, 286, 300, 24, "会议内容", C.text, 16)
    local ag = {}
    for i = 1, 3 do
        ag[i] = theme.txt(d, 42, 312 + (i - 1) * 24, 386, 22, "", C.sub, 16)
    end
    -- 说明拆成两行，字号 15，能完整落在块内
    local dnote1 = theme.txt(d, 42, 386, 386, 20, "", C.dim, 15)
    local dnote2 = theme.txt(d, 42, 408, 386, 20, "", C.dim, 15)
    theme.btn(d, 26, 452, 200, 42, "关闭", C.panel2, C.text, C.line, 1, 6, close_layers)
    theme.btn(d, 236, 452, 208, 42, "查看会议日程", C.blue, C.white, C.blue, 0, 6, nil)
    theme.hit(d, 236, 452, 208, 42, function() show_layer("sched") end)
    sheets.detail = { cont = d, on_show = function()
        -- 点哪一场就看哪一场（S.detail_m 由打开方写入），
        -- 之前固定取「当前会议」，所以点三行看到的内容一模一样
        local m = S.detail_m or mock.cur_meeting() or mock.next_meeting() or mock.base[1]
        pcall(dsub.set_text, dsub, m.topic)
        pcall(kl[1].set_text, kl[1],
            (m.day == 2 and "明天 " or "") .. mock.fmt(m.st) .. " - " .. mock.fmt(m.et))
        pcall(kl[2].set_text, kl[2], (m.owner or "李静") .. " · " .. (m.dept or "研发部"))
        pcall(kl[3].set_text, kl[3], tostring(m.people or 4) .. " / " .. mock.room.cap .. " 人")
        pcall(kl[4].set_text, kl[4], mock.room.name .. " · " .. mock.room.floor)
        for i = 1, 3 do
            pcall(ag[i].set_text, ag[i], "· " .. tostring((m.agenda or {})[i] or ""))
        end
        pcall(dnote1.set_text, dnote1, m.note1 or "投屏 · 白板 · 交互稿已上传共享盘")
        pcall(dnote2.set_text, dnote2, m.note2 or "请提前 5 分钟到场，会前资料已随日程同步。")
    end }

    -- 2) 预约会议室（html: 470 宽；今天/明天 分段 + 3 个时段 + 我的预约条）
    local b = mk_sheet("book", 470, 472)
    theme.txt(b, 26, 22, 340, 30, "预约会议室", C.text, 22)
    theme.txt(b, 26, 58, 400, 22, mock.room.name .. " · " .. mock.room.floor .. " · 可容纳 "
        .. mock.room.cap .. " 人", C.sub, 16)
    sheet_close(b, 470)
    local seg, segt = {}, {}
    local segx = { 26, 235 }
    local segw = { 199, 209 }
    for i = 1, 2 do
        seg[i] = theme.box_b(b, segx[i], 88, segw[i], 48, C.slot_bg, 10, C.line, 1)
        segt[i] = theme.txt(seg[i], 0, 0, segw[i], 48, i == 1 and "今天" or "明天", C.text, 18, "center")
        local idx = i
        theme.hit(b, segx[i], 88, segw[i], 48, function()
            S.date = idx
            PAGE.refresh_book()
        end)
    end
    local sl, sltx, sltag = {}, {}, {}
    for i = 1, 3 do
        local y = 148 + (i - 1) * 62
        local s = mock.slots[i]
        sl[i] = theme.box_b(b, 26, y, 418, 56, C.slot_bg, 10, C.line, 1)
        theme.txt(sl[i], 18, 0, 220, 56, mock.fmt(s.st) .. " - " .. mock.fmt(s.et), C.text, 17)
        sltx[i] = theme.txt(sl[i], 250, 0, 150, 56, "", C.sub, 16, "right")
        local idx = i
        theme.hit(b, 26, y, 418, 56, function()
            S.slot = idx
            PAGE.refresh_book()
        end)
    end
    local minebar = theme.box(b, 26, 340, 418, 52, C.redsoft, 8)
    -- 文字区原来只有 250 宽，预约到第 2 场就被截成「已预约 14:15-15:30、15:45-17:00（」
    local minetx = theme.txt(minebar, 14, 0, 296, 52, "", C.red2, 14)
    local mineb = theme.box(minebar, 318, 12, 88, 28, C.white, 6)
    theme.txt(mineb, 0, 0, 88, 28, "取消预约", C.red2, 15, "center")
    theme.hit(minebar, 320, 12, 84, 28, cancel_last)
    theme.btn(b, 26, 404, 199, 42, "取消", C.panel2, C.text, C.line, 1, 6, close_layers)
    theme.btn(b, 235, 404, 209, 42, "确认预约", C.blue, C.white, C.blue, 0, 6, nil)
    theme.hit(b, 235, 404, 209, 42, function()
        local day = S.date
        local s = mock.slots[S.slot]
        if mock.slot_taken(day, s.st) then
            toast("这个时段已经预约过了")
            return
        end
        local nb = mock.add_booking(day, S.slot)
        if day == 1 then S.sel_bid = nb.bid end
        close_layers()
        PAGE.redraw_all()
        toast("预约成功 · " .. mock.fmt(s.st) .. "-" .. mock.fmt(s.et) .. " 已写入日程")
        -- html: 620ms 后自动打开「会议日程」，让用户看见刚写入的那一行
        sys.timerStart(function() pcall(show_layer, "sched") end, 620)
    end)
    sheets.book = { cont = b, seg = seg, segt = segt, segw = segw,
                    sl = sl, sltx = sltx, minebar = minebar, minetx = minetx }

    -- 3) 扫码签到（html: 404 宽，标题居中 + 236 码卡）
    local q = mk_sheet("qr", 404, 420)
    theme.txt(q, 26, 22, 352, 30, "扫码签到", C.text, 22, "center")
    theme.txt(q, 26, 58, 352, 22, "使用企业微信扫描下方二维码", C.sub, 16, "center")
    sheet_close(q, 404)
    theme.box(q, 84, 92, 236, 236, C.qr_bg, 12, "qr_bg")
    -- 210 = 21 × 10，整除后码点方正
    draw_qr(q, 97, 105, 210, C.qr_fg)
    theme.btn(q, 26, 352, 166, 42, "关闭", C.panel2, C.text, C.line, 1, 6, close_layers)
    theme.btn(q, 204, 352, 174, 42, "模拟签到成功", C.blue, C.white, C.blue, 0, 6, nil)
    theme.hit(q, 204, 352, 174, 42, function()
        close_layers()
        toast("签到成功 · 已记录参会")
    end)
    sheets.qr = { cont = q }

    -- 4) 模板切换（html: 470 宽，无底部按钮，只有右上角关闭）
    local t = mk_sheet("tpl", 470, 358)
    theme.txt(t, 26, 22, 340, 30, "选择显示模板", C.text, 22)
    theme.txt(t, 26, 58, 400, 22, "点顶栏的模板方框可随时切换", C.sub, 16)
    sheet_close(t, 470)
    local tl = { { "天际线 · 企业蓝", "白顶栏 + 城市夜景 + 圆形表盘时钟" },
                 { "商务蓝 · 二维码", "大时钟 + 同心弧 + 通信塔 + 扫码签到" },
                 { "红白表格 · 预约列表", "红白门户风 + 时段表格 + 门禁卡" } }
    local ts = {}
    for i = 1, 3 do
        local y = 88 + (i - 1) * 84
        ts[i] = theme.box_b(t, 26, y, 418, 76, C.slot_bg, 10, C.line, 1)
        theme.txt(ts[i], 18, 12, 380, 28, tl[i][1], C.text, 19)
        theme.txt(ts[i], 18, 42, 380, 24, tl[i][2], C.sub, 15)
        local ti = i
        theme.hit(t, 26, y, 418, 76, function()
            close_layers()
            PAGE.set_tpl(ti)
        end)
    end
    sheets.tpl = { cont = t, items = ts }

    -- 5) 门禁控制（html: 404 宽，3 行 kv + 取消/确认开门）
    local g = mk_sheet("door", 404, 318)
    theme.txt(g, 26, 22, 300, 30, "门禁控制", C.text, 22)
    theme.txt(g, 26, 58, 340, 22, mock.room.name .. " · " .. mock.room.floor, C.sub, 16)
    sheet_close(g, 404)
    theme.txt(g, 26, 90, 110, 44, "当前状态", C.sub, 16)
    local gdot = theme.circle(g, 152, 109, 10, C.red)
    local gstat = theme.txt(g, 170, 90, 200, 44, "门禁已上锁", C.red, 16)
    shape(g, 26, 133, 352, 1, { rect(0, 0, 352, 1, C.line) })
    theme.txt(g, 26, 140, 110, 44, "开门权限", C.sub, 16)
    theme.txt(g, 140, 140, 240, 44, "会议期间可远程开门", C.text, 16)
    shape(g, 26, 183, 352, 1, { rect(0, 0, 352, 1, C.line) })
    theme.txt(g, 26, 190, 110, 30, "操作说明", C.sub, 16)
    local gtip = theme.txt(g, 140, 190, 240, 48, "确认后远程开锁，30 秒内可进入", C.text, 15)
    theme.btn(g, 26, 250, 166, 42, "取消", C.panel2, C.text, C.line, 1, 6, close_layers)
    -- 已解锁时这个按钮是「上锁」，不再是「开门」：文案和说明都跟着状态走
    local gbtn = theme.btn(g, 204, 250, 174, 42, "确认开门", C.red, C.white, C.red, 0, 6, nil)
    theme.hit(g, 204, 250, 174, 42, function()
        S.door = not S.door
        close_layers()
        PAGE.redraw_all()
        toast(S.door and "门禁已解锁 · 30 秒内可推门进入"
            or "门禁已上锁 · 点「开门」可再次解锁")
    end)
    sheets.door = { cont = g, dot = gdot, stat = gstat, btn = gbtn, tip = gtip }

    -- 6) 会议日程（html: 552 宽；进行中蓝框、我的预约绿框 + 已选中；底部三键）
    local sc = mk_sheet("sched", 552, 534)
    theme.txt(sc, 26, 22, 400, 30, "会议日程", C.text, 22)
    local ssub = theme.txt(sc, 26, 58, 480, 22, "", C.sub, 16)
    sheet_close(sc, 552)
    local srows = {}
    for i = 1, ROW_MAX do
        local y = 88 + (i - 1) * 54
        -- 外框 = 边框色，内层缩 2px = 行底色（伪描边，方便运行时改颜色）
        local outer = theme.box(sc, 26, y, 500, 48, C.line, 10)
        local inner = theme.box(outer, 1, 1, 498, 46, C.panel2, 9)
        local tm = theme.txt(inner, 14, 0, 118, 46, "", C.sub, 16)
        local tt = theme.txt(inner, 132, 0, 250, 46, "", C.text, 16)
        local pp = theme.txt(inner, 372, 0, 40, 46, "", C.sub, 15, "right")
        local tgc = theme.box(inner, 420, 11, 64, 24, C.panel2, 4)
        local tg = theme.txt(tgc, 0, 0, 64, 24, "", C.dim, 14, "center")
        local idx = i
        theme.hit(sc, 26, y, 500, 48, function()
            local data = srows[idx] and srows[idx].data
            if not data then return end
            if data.mine then
                S.sel_bid = (S.sel_bid == data.bid) and nil or data.bid
                PAGE.refresh_rows()
                toast(S.sel_bid and "已选中这笔预约，按「取消预约」释放" or "已取消选中")
            elseif (data.idx or 0) > 0 and not data.past then
                set_current(data)
            end
        end)
        srows[i] = { outer = outer, inner = inner, tm = tm, tt = tt, pp = pp,
                     tgc = tgc, tg = tg, data = nil }
        pcall(outer.set_hidden, outer, true)
    end
    local stip1 = theme.txt(sc, 26, 418, 500, 22,
        "点普通场次切换为「正在使用」；点你的预约可选中后取消。", C.dim, 15)
    theme.btn(sc, 26, 466, 160, 42, "关闭", C.panel2, C.text, C.line, 1, 6, close_layers)
    -- 「取消预约」只在选中了某笔预约时出现：button 不能 set_hidden，套一层容器
    local scancel = theme.box_a(sc, 196, 466, 160, 42, C.card, 8, 0)
    theme.btn(scancel, 1, 2, 158, 38, "取消预约", C.red, C.white, C.red, 0, 8, nil)
    theme.hit(scancel, 0, 0, 160, 42, cancel_flow)
    pcall(scancel.set_hidden, scancel, true)
    theme.btn(sc, 366, 466, 160, 42, "预约会议室", C.blue, C.white, C.blue, 0, 6, nil)
    theme.hit(sc, 366, 466, 160, 42, function() show_layer("book") end)
    sheets.sched = { cont = sc, rows = srows, sub = ssub, stip = stip1, cancel = scancel }

    close_layers()   -- 关键：否则启动时遮罩 + 全部弹层叠在主页上
end
build_layers_ref = build_layers

--------------------------------------------------------------------
-- 刷新：只改属性，不重建控件
--------------------------------------------------------------------
local function set_txt(l, s)
    if l then pcall(l.set_text, l, s or "") end
end

local last_status_min = nil

local function refresh_status(force)
    local mm = math.floor(S.vnow)
    if not force and mm == last_status_min then return end
    last_status_min = mm
    local m  = mock.cur_meeting()
    local nm = mock.next_meeting()
    local range = m and (mock.fmt(m.st) .. " - " .. mock.fmt(m.et)) or "—"
    local topic = m and m.topic or "当前没有会议，可现场预约"
    -- nm 现在包含「我自己的预约」（见 mock.next_meeting），预约完不会再显示「今天暂无后续会议」
    -- 今天没后续但明天有预约时，明确说出来（否则约了明天在主界面完全看不到）
    local tmrw = mock.tomorrow_text()
    local nxt
    if nm then
        nxt = "下一场 " .. mock.fmt(nm.st) .. " · " .. nm.topic
    elseif tmrw then
        nxt = tmrw .. " 有预约"
    else
        nxt = "今天暂无后续会议"
    end
    -- 空闲态优先播报自己的预约（今天 + 明天），让用户看到「我刚才约的确实进去了」
    local mytxt = mock.my_text()
    local mybrief = mock.my_brief()

    -- 1 天际线
    set_txt(dy.a_label, S.free and "ROOM AVAILABLE · 当前空闲" or "CURRENT MEETING · 当前会议")
    set_txt(dy.a_range, S.free and "空闲" or range)
    set_txt(dy.a_topic, S.free and "房间空闲，可直接扫码预约" or topic)
    -- 这条只有 350 宽，用压缩版（今天 1 场 · 明天 1 场），写具体时间会被裁掉
    set_txt(dy.a_next, S.free and (mybrief and ("已预约 " .. mybrief) or "可预约时段 14:15 起") or nxt)
    set_txt(dy.a_status, (S.free and "当前空闲 · 可直接预约" or left_txt()) .. (S.dnd and " · 免打扰" or ""))
    -- html: 空闲 → 黄点 #FFC24B；会议中 → 绿点 #3BE08A
    if dy.a_dot then pcall(dy.a_dot.set_color, dy.a_dot, S.free and C.yellow or C.green, 255) end
    set_txt(dy.a_clock, hm())
    -- 圆盘第二面：会议中 = 剩余时间；空闲 = 距下一场分钟数
    if S.free then
        local gap = nm and math.max(0, math.ceil(nm.st - S.vnow)) or 0
        set_txt(dy.a_llab, "距下一场")
        set_txt(dy.a_lmin, tostring(gap))
        set_txt(dy.a_ltip, nm and (mock.fmt(nm.st) .. " 开始") or "今日会议已结束")
    else
        set_txt(dy.a_llab, "剩余时间")
        set_txt(dy.a_lmin, tostring(mock.left_min() or 0))
        set_txt(dy.a_ltip, m and ("预计 " .. mock.fmt(m.et) .. " 结束") or "")
    end

    -- 2 商务蓝
    set_txt(dy.b_clock, hm())
    set_txt(dy.b_label, S.free and "ROOM AVAILABLE · 当前空闲" or "CURRENT MEETING · 当前会议")
    set_txt(dy.b_topic, topic)
    set_txt(dy.b_time, range)
    set_txt(dy.b_chip_b, S.free and "空闲" or "会议中")
    set_txt(dy.b_chip_e, S.free and "AVAILABLE" or "IN MEETING")
    if dy.b_chip then pcall(dy.b_chip.set_color, dy.b_chip, S.free and C.sched_mine or C.redsoft, 255) end
    if dy.b_chip_b then pcall(dy.b_chip_b.set_color, dy.b_chip_b, S.free and C.green or C.red2) end
    local pct = 0
    if m and m.et > m.st then pct = (S.vnow - m.st) / (m.et - m.st) end
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    if dy.b_fill then pcall(dy.b_fill.set_size, dy.b_fill, math.max(6, math.floor(380 * pct)), 6) end
    local done = m and math.floor(S.vnow - m.st) or 0
    if m and done < 0 then done = 0 end
    set_txt(dy.b_ptext, (m and not S.free)
        and string.format("已进行 %d 分钟 · 共 %d 分钟", done, m.et - m.st)
        or (mytxt and ("我已预约 " .. mytxt) or "当前时段无会议 · 可直接预约"))

    -- 3 红白表格
    set_txt(dy.c_clock, hm())
    set_txt(dy.c_state_b, S.free and "当前空闲" or "正在使用")
    set_txt(dy.c_state_s, S.free and "AVAILABLE" or "OCCUPIED")
    if dy.c_state_b then pcall(dy.c_state_b.set_color, dy.c_state_b, S.free and C.green or C.red) end
    if dy.c_state_s then pcall(dy.c_state_s.set_color, dy.c_state_s, S.free and C.green or C.red) end
    if dy.c_locktx then
        set_txt(dy.c_locktx, S.door and "门禁已开启" or "门禁已上锁")
        pcall(dy.c_locktx.set_color, dy.c_locktx, S.door and C.green or C.ccardtext)
    end
    set_txt(dy.c_next, nxt)

    -- 顶栏主题按钮写的是「点了会切到哪个主题」，换肤不再重建控件，文案得自己更新
    local tnext = (theme.cur == "dark") and "浅色" or "深色"
    set_txt(dy.a_theme, tnext)
    set_txt(dy.b_theme, tnext)
    set_txt(dy.c_theme, tnext)
end

-- 表格模板（红白）行：进行中 → 红底 + 「进行中」标签；我的预约 → 「取消」；其余 → 「切换」
local function fill_row_c(r, m)
    if not m then
        pcall(r.cont.set_hidden, r.cont, true)
        r.data = nil
        return
    end
    r.data = m
    pcall(r.cont.set_hidden, r.cont, false)
    set_txt(r.tm, mock.fmt(m.st) .. " - " .. mock.fmt(m.et))
    -- 明天的预约加「明日」前缀，否则和今天的场次分不清
    set_txt(r.topic, (m.day == 2 and "明日 · " or "") .. m.topic)
    set_txt(r.ppl, tostring(m.people or 4) .. " 人")

    local is_cur = (m.idx or 0) > 0 and m.idx == S.cur and not S.free
    pcall(r.cont.set_color, r.cont, is_cur and C.ctop1 or C.crow, 255)
    pcall(r.topic.set_color, r.topic, is_cur and C.white or C.crowtext)
    pcall(r.tm.set_color, r.tm, is_cur and C.redsoft or C.sub)
    pcall(r.ppl.set_color, r.ppl, is_cur and C.redsoft or C.sub)

    pcall(r.tagc.set_hidden, r.tagc, not is_cur)
    pcall(r.goc.set_hidden, r.goc, is_cur)
    if is_cur then
        set_txt(r.tagtx, "进行中")
        pcall(r.tagc.set_color, r.tagc, C.red, 255)
        pcall(r.tagtx.set_color, r.tagtx, C.white)
    else
        -- 我的预约一律显示「取消」，点一下真的删（不再需要先选中再按底栏）
        -- 底色不再看 sel：之前一行的 sel_bid 命中、另一行没命中，
        -- 同一个「取消」就出现一白一红，看着像坏了两处。
        local is_mine = m.mine and true or false
        set_txt(r.gotx, is_mine and "取消" or "切换")
        pcall(r.gotx.set_color, r.gotx, is_mine and C.red or C.red2)
        pcall(r.goc.set_color, r.goc, is_mine and C.redsoft or C.card2, 255)
    end
end

-- 日程弹层行：进行中蓝框、我的预约绿框（选中加深）
local function fill_row_s(r, m)
    if not m then
        pcall(r.outer.set_hidden, r.outer, true)
        r.data = nil
        return
    end
    r.data = m
    pcall(r.outer.set_hidden, r.outer, false)
    set_txt(r.tm, mock.fmt(m.st) .. " - " .. mock.fmt(m.et))
    set_txt(r.tt, m.topic)
    set_txt(r.pp, tostring(m.people or 4) .. " 人")

    local is_cur = (m.idx or 0) > 0 and m.idx == S.cur and not S.free
    local sel = m.mine and S.sel_bid == m.bid
    -- 明天的预约不能按今天的时间判「已结束」
    local past = (m.day ~= 2) and (m.et <= S.vnow) and not is_cur
    m.past = past          -- 点击回调要按它跳过已结束的场次（= html m.past）

    local bg, bd = C.panel2, C.line
    if is_cur then bg, bd = C.sched_cur, C.blue
    elseif m.mine then bg, bd = C.sched_mine, C.green end
    -- 选中：整行换成高饱和绿底 + 深色字（深色主题下 sched_mine 几乎和 panel2 同色，
    -- 只加绿边框根本看不出来，这就是「选中的预约时间不明显」的原因）
    if sel and not is_cur then bg = C.green end
    pcall(r.outer.set_color, r.outer, bd, 255)
    pcall(r.inner.set_color, r.inner, bg, 255)
    local fg_main = sel and (not is_cur) and C.bg_top or C.text
    local fg_sub = sel and (not is_cur) and C.bg_top or C.sub
    pcall(r.tt.set_color, r.tt, (past and not sel) and C.dim or fg_main)
    pcall(r.tm.set_color, r.tm, is_cur and C.blue or fg_sub)
    pcall(r.pp.set_color, r.pp, fg_sub)

    local tag, tbg, tfg
    if is_cur then tag, tbg, tfg = "进行中", C.blue, C.white
    elseif m.mine then
        -- 明日预约的标签直接写「明日」（标签位 64 宽，写「我预约」+ 主题前缀会挤爆）
        -- 别在文案里塞 ✓ 之类的符号：hzfont 没有这个字形，真机上就是一串方框
        if m.day == 2 then tag = "明日"
        else tag = sel and "已选中" or "我预约" end
        if sel then tbg, tfg = C.bg_top, C.green else tbg, tfg = C.green, C.white end
    elseif past then tag, tbg, tfg = "已结束", C.panel2, C.dim
    else tag, tbg, tfg = "待开始", C.panel2, C.sub end
    set_txt(r.tg, tag)
    pcall(r.tgc.set_color, r.tgc, tbg, 255)
    pcall(r.tg.set_color, r.tg, tfg)
end

-- 每秒 set_color/set_text 几十次会拖垮 airui（真机上表现为几十秒后看门狗复位），
-- 所以行内容只在「状态签名」变化时才重画
local last_rows_sig, last_min = nil, nil

local function rows_sig()
    return tostring(S.cur) .. "|" .. tostring(S.free) .. "|" .. tostring(S.sel_bid)
        .. "|" .. tostring(#S.bookings) .. "|" .. tostring(S.door) .. "|"
        .. tostring(math.floor(S.vnow / 5))
end

local function refresh_rows(force)
    if not force and rows_sig() == last_rows_sig then return end
    last_rows_sig = rows_sig()
    -- 日程 / 表格里必须带上「明天的预约」（置顶），否则约了明天回到主界面什么都看不到
    local list = mock.agenda_list()

    -- 三套模板的「取消预约」入口：有预约才显示
    local has = #S.bookings > 0
    -- 模板懒构建后，未建模板的字段是 nil，这里必须逐个判空（直接取 .set_hidden 会崩）
    if dy.a_cancel_btn then pcall(dy.a_cancel_btn.set_hidden, dy.a_cancel_btn, not has) end
    if dy.cancel_b then pcall(dy.cancel_b.set_hidden, dy.cancel_b, not has) end
    if dy.c_cancel then pcall(dy.c_cancel.set_hidden, dy.c_cancel, not has) end

    if dy.rows then
        for i = 1, ROW_C do
            local r = dy.rows[i]
            if r then fill_row_c(r, list[i]) end
        end
    end
    if sheets.sched then
        for i = 1, ROW_MAX do
            local r = sheets.sched.rows[i]
            if r then fill_row_s(r, list[i]) end
        end
        pcall(sheets.sched.cancel.set_hidden, sheets.sched.cancel, not S.sel_bid)
        -- 副标题：html = 房间 · 今天 · 日期（有明天的预约再追加一段）
        local sub = mock.room.name .. " · " .. mock.room.floor .. " · 今天 · " .. date_long()
        local tm2 = {}
        for _, b in ipairs(S.bookings) do
            if b.day == 2 then tm2[#tm2 + 1] = mock.fmt(b.st) .. "-" .. mock.fmt(b.et) end
        end
        if #tm2 > 0 then sub = sub .. " · 明天 " .. table.concat(tm2, "、") end
        set_txt(sheets.sched.sub, sub)
    end
end

local function refresh_book()
    local bk = sheets.book
    if not bk then return end
    for i = 1, 2 do
        local on = (S.date == i)
        pcall(bk.seg[i].set_color, bk.seg[i], on and C.seg_on_bg or C.slot_bg, 255)
        pcall(bk.segt[i].set_color, bk.segt[i], on and C.seg_on_fg or C.text)
    end
    for i = 1, 3 do
        local s = mock.slots[i]
        local taken = mock.slot_taken(S.date, s.st)
        local pick = (S.slot == i) and not taken
        set_txt(bk.sltx[i], taken and "已预约" or "空闲")
        pcall(bk.sl[i].set_color, bk.sl[i], pick and C.seg_on_bg or C.slot_bg, 255)
        pcall(bk.sltx[i].set_color, bk.sltx[i], taken and C.red2 or C.sub)
    end
    local n, ts = 0, {}
    for _, b in ipairs(S.bookings) do
        if b.day == S.date then
            n = n + 1
            ts[#ts + 1] = mock.fmt(b.st) .. "-" .. mock.fmt(b.et)
        end
    end
    pcall(bk.minebar.set_hidden, bk.minebar, n == 0)
    -- 最多列两条，再多就省略号（条只有 418 宽，塞不下会像之前那样被裁一半）
    local show = ts
    if #ts > 2 then show = { ts[1], ts[2] .. " …" } end
    set_txt(bk.minetx, "已预约 " .. n .. " 场 · " .. table.concat(show, "、"))
end

local function refresh_dnd()
    local on = S.dnd
    local t = on and "免打扰中" or "免打扰"
    local bs = { dy.a_dnd, dy.b_dnd, dy.c_dnd }
    for i = 1, #bs do
        if bs[i] then pcall(bs[i].set_text, bs[i], t) end
    end
end

local function refresh_door()
    set_txt(dy.c_locktx, S.door and "门禁已开启" or "门禁已上锁")
    theme.set_icon(dy.c_lockic, S.door and "check" or "lock", 20, S.door and C.green or C.red)
    local g = sheets.door
    if g then
        pcall(g.dot.set_color, g.dot, S.door and C.green or C.red, 255)
        set_txt(g.stat, S.door and "门禁已解锁" or "门禁已上锁")
        pcall(g.stat.set_color, g.stat, S.door and C.green or C.red)
        -- 状态切换后按钮要翻面：已解锁 → 「确认上锁」
        if g.btn then
            pcall(g.btn.set_text, g.btn, S.door and "确认上锁" or "确认开门")
        end
        if g.tip then
            pcall(g.tip.set_text, g.tip, S.door
                and "已解锁，30 秒内可推门进入"
                or "确认后远程开锁，30 秒内可进入")
        end
    end
    if dy.a_door then pcall(dy.a_door.set_text, dy.a_door, S.door and "已开锁" or "开门") end
end

--------------------------------------------------------------------
-- 切模板：三套模板是同一页里的三个整屏容器，只做显隐（不 destroy 重建）
-- 模板改为「懒构建」：切到哪套才建哪套，建好后一直缓存复用。
-- 原来启动时把三套全建出来，主题切换 destroy 重建时又三套全建一遍，
-- 一遍要创建上千个控件 —— 这就是「切主题要等好几秒」的原因。
--------------------------------------------------------------------
local function ensure_tpl(i)
    if sp[i] then return sp[i] end
    if not tpl_root then return nil end
    local box = theme.box(tpl_root, 0, 0, W, H, C.bg)
    -- 构建失败必须把半成品销毁并置 nil：否则下次再切到这套模板会拿到半棵树，
    -- 表现为「按钮点了以后再点别的全没反应」
    local ok, err = pcall(function()
        if i == 1 then build_a(box, dy)
        elseif i == 2 then build_b(box, dy)
        else build_c(box, dy) end
    end)
    if not ok then
        pcall(box.destroy, box)
        if log and log.error then
            log.error("page", "build_tpl " .. i .. " failed: " .. tostring(err))
        end
        return nil
    end
    sp[i] = box
    pcall(box.set_hidden, box, i ~= S.tpl)
    return box
end

local function apply_tpl()
    ensure_tpl(S.tpl)
    for i = 1, 3 do
        if sp[i] then pcall(sp[i].set_hidden, sp[i], i ~= S.tpl) end
    end
    -- 三套模板各自的「模板 · xx」按钮文案跟着走
    if dy.tpl_btn then
        for i = 1, 3 do
            if dy.tpl_btn[i] then
                pcall(dy.tpl_btn[i].set_text, dy.tpl_btn[i], "模板 · " .. TPL_NAME[S.tpl])
            end
        end
    end
    -- 商务蓝底部圆点：当前模板显示为长胶囊
    if dy.b_dots then
        for i = 1, 3 do
            pcall(dy.b_dots[i].set_hidden, dy.b_dots[i], i == S.tpl)
            if dy.b_dotp[i] then
                pcall(dy.b_dotp[i].set_hidden, dy.b_dotp[i], i ~= S.tpl)
            end
        end
    end
end

--------------------------------------------------------------------
-- 构建
--------------------------------------------------------------------
local function build(root)
    last_status_min, last_rows_sig = nil, nil
    -- 重建前先清引用：旧 root 已被 destroy，残留的对象指针再 set_xxx 会直接崩
    dy = {}
    sheets = {}
    layers_root, mask = nil, nil
    cur_layer = nil
    toast_box, toast_lab = nil, nil
    tpl_root = nil
    for i = 1, 3 do sp[i] = nil end
    root_ref = root
    -- 模板容器先建，弹层/ toast 后建 —— 这样 z 序永远是 模板 < 弹层 < toast，
    -- 后面懒建出来的模板也只会加在 tpl_root 里，不会盖住弹层
    tpl_root = theme.box(root, 0, 0, W, H, C.bg)
    -- 只建当前模板（其它两套等切过去时再建）
    ensure_tpl(S.tpl)
    apply_tpl()

    -- 主题切换触发的重建：弹层先不建（六个弹层也不便宜），等用户下次点开再建
    if layers_pending then
        layers_pending = false
        pending_layers = true
    else
        pending_layers = false      -- 正常构建：弹层马上就建，别让 show_layer 误判去补建
        build_layers(root)
    end

    -- toast（html: 顶部居中，top 70px）
    local tw = 520
    toast_box = theme.box_a(root, math.floor((W - tw) / 2), 70, tw, 46, C.toast_bg, 8, C.toast_opa)
    toast_lab = theme.txt(toast_box, 0, 0, tw, 46, "", C.white, 17, "center")
    pcall(toast_box.set_hidden, toast_box, true)

    PAGE.redraw_all()

    -- 定时器：虚拟时钟 + 动态文案（1 分钟 = 8 秒）
    return function()
        S.vnow = S.vnow + 0.125
        PAGE.refresh_status()
        PAGE.refresh_rows()
    end, 1000
end

--------------------------------------------------------------------
-- 对外：页面模块
--------------------------------------------------------------------
PAGE = theme.make_page(1, "会议室门牌", build)

PAGE.refresh_status = refresh_status
PAGE.refresh_rows   = refresh_rows
PAGE.refresh_book   = refresh_book
PAGE.refresh_dnd    = refresh_dnd
PAGE.refresh_door   = refresh_door
PAGE.refresh_all    = function()
    refresh_status(true); refresh_rows(true); refresh_book()
    refresh_dnd(); refresh_door()
end
PAGE.apply_tpl      = apply_tpl
PAGE.redraw_all     = function()
    apply_tpl()
    PAGE.refresh_all()
end
PAGE.set_tpl        = function(i)
    if i == S.tpl then return end
    local prev = S.tpl
    S.tpl = i
    local ok = pcall(PAGE.redraw_all)
    if not ok then
        S.tpl = prev
        pcall(PAGE.redraw_all)
        toast("模板切换失败，已退回原模板")
        return
    end
    toast("已切换到「" .. TPL_NAME[i] .. "」")
end
PAGE.redraw_dnd = function()
    refresh_dnd()
    toast(S.dnd and "已开启免打扰" or "已关闭免打扰")
end
PAGE.redraw_door = refresh_door

return PAGE
