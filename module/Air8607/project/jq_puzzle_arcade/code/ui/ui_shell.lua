--[[
@module  ui_shell
@summary 益智乐园外壳：顶栏 HUD / 舞台页面调度 / 底部操作栏 / 触摸手势分发 / 主循环
@version 1.0
@date    2026.11.03

=== 布局（1024x600）===
  顶栏 HUD   (y  0..58)   品牌 | 游戏名 + 一句话 | 战绩两行
  舞台       (y 62..514)  1000x452 外框，内容区 994x446
                          （第 1 页大厅，2..8 是七款游戏，第 9 页是排行榜）
  底部操作栏 (y 522..588) 大厅 / 重开 / 玩法 + 操作提示

=== 关键设计决策 ===
1、页面 = 一个容器 + 一个 shape + 一批 label：
   切页面只 set_hidden，不销毁不重建（label 目前没有 set_hidden，靠容器隐藏才省事）。
   首次进入某页才 build，开机只付大厅这一页的开销。
   隐藏期间页面不 update，计时 / 动画 / 电脑思考都停在原地，
   所以"回大厅再进来"就是接着上次的局面玩；新开一局只能靠「重玩」按钮或结算弹窗。
2、每页自带一个 shape：只有当前页会 set_items，所以每帧只有一个绘制对象要遍历，
   比"整个外壳共用一个大画布"少了跨页脏区。
3、触摸走全局订阅 + 环形队列 + 主循环里分发：
   touch_subscribe 的回调跑在 LVGL 的输入线程里，在里面直接改控件是跨线程操作；
   这里只在回调里往预分配的环形缓冲写三个数字，真正的手势判定和页面响应都在主循环任务里做。
4、手势三分类：短按（<26px 且 <450ms）/ 长按（<26px 且 >=450ms）/ 滑动（>=60px）。
   2048 吃滑动，扫雷吃长按插旗，其余吃短按。
5、动画步长用固定帧时长，只有真的挂起超过 3 帧才按真实时间补跳；
   节拍用补偿式 sys.wait（work 越重睡越少），否则帧率会自我恶化。
]]

local fx = require "fx"
local T = require "theme"
local records = require "records"
local overlay = require "ui_overlay"
local home = require "ui_home"
local rank = require "ui_rank"

-- 七款游戏（顺序 = 大厅卡片位序 = 页面序号 2..8）
local GAMES = {
    require "g2048",
    require "g_puzzle",
    require "g_memory",
    require "g_mines",
    require "g_pipes",
    require "g_simon",
    require "g_gomoku",
}
rank.init(GAMES)

-- 大厅卡片 = 七款游戏 + 1 张排行榜入口（第 8 张卡）
-- 卡片位序 i 对应页面 i+1，排行榜正好是最后一页，点卡片的逻辑不用特判
local CARDS = {}
for i = 1, #GAMES do CARDS[i] = GAMES[i] end
CARDS[#CARDS + 1] = rank
home.init(CARDS)

local M = {}

-- 页面表：1 = 大厅，2..8 按 GAMES 顺序，9 = 排行榜
local PAGES = { home }
for i = 1, #GAMES do PAGES[i + 1] = GAMES[i] end
PAGES[#PAGES + 1] = rank

-- ==================== 运行时状态 ====================
local base, stage
local pages = {}        -- [idx] = { root, shape, pool, obj, n }
local cur = 0
local built = false
local accentBar, lbName, lbDesc, lbS1, lbS2, lbTip

-- ==================== 时间基准 ====================
--[[tick 必须经 mcu.hz() 折算成毫秒
mcu.ticks() 返回原始 tick 数，每 tick 多少时间依平台而变：
  模拟器 / Air8000     约 1ms  / tick   (hz = 1000)
  Air1601 / Air1603    约 20ms / tick   (hz = 50)   <- Air8607 主控属于这一档
把每个 tick 当 1ms，整条时间轴就缩放 20 倍（动画慢 20 倍、FPS 虚报）。
PC 模拟器的 luat_mcu_hz() 返回 1（而 ticks 本身就是毫秒），
所以 hz <= 1 时按 1 tick/ms 处理，两个平台都能算对。]]
local TICKS_PER_MS = 1

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    if sys and sys.mtime then return sys.mtime() end
    return os.time() * 1000
end

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end   -- ticks 是 uint32，跨回绕时差值为负
    return d
end

local function init_timebase()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
        log.info("ui_shell", string.format("时间基准: mcu.hz()=%d, 每 tick 约 %.1f ms",
            hz, 1000 / hz))
    else
        TICKS_PER_MS = 1
        log.info("ui_shell", "时间基准: mcu.hz() 不可用(PC 模拟器)，按 1 tick/ms")
    end
end

-- ==================== 游戏回调上下文 ====================
--[[游戏不 require 外壳（否则循环依赖），外壳在 build 时把这个表注入进去。
游戏只会用到下面这几个动作：读榜首 / 交成绩 / 清榜 / 报胜负 / 弹通知。]]
local host = {}

--[[某款游戏的榜首成绩（没记录返回 0）
游戏只关心"现在最好的成绩是多少"，具体是哪一天不需要知道。]]
function host.best(key)
    return records.best(key)
end

--[[交一局成绩，返回名次 1..5；没进前 5 返回 nil。
多包一层括号：records.submit 同时返回"名次 + 新榜首"，
这里只把名次交给游戏，免得调用方误把第二个返回值当名次用。]]
function host.save(key, value)
    return (records.submit(key, value, "max"))
end

function host.save_min(key, value)
    return (records.submit(key, value, "min"))
end

-- 弹窗按钮文案统一面向孩子：两个字的动词最容易被读出来
function host.win(title, body)
    log.info("arcade", "过关", title)
    overlay.open({
        title = title, body = body, color = T.c.green,
        p1 = "再玩一次", f1 = function() overlay.close() M.restart() end,
        p2 = "回大厅", f2 = function() overlay.close() M.open(1) end,
    })
end

function host.lose(title, body)
    log.info("arcade", "结束", title)
    overlay.open({
        title = title, body = body, color = T.c.orange,
        p1 = "再玩一次", f1 = function() overlay.close() M.restart() end,
        p2 = "回大厅", f2 = function() overlay.close() M.open(1) end,
    })
end

function host.notice(title, body, btnText, fn)
    log.info("arcade", "提示", title)
    overlay.open({
        title = title, body = body, color = T.c.amber,
        p1 = btnText or "好呀",
        f1 = function()
            overlay.close()
            if fn then fn() end
        end,
        p2 = "回大厅", f2 = function() overlay.close() M.open(1) end,
    })
end

--[[二次确认（清空成绩这种"删了就回不来"的操作）
默认按钮是"先不清空"：孩子手滑点开弹窗，再滑一下不会真的把成绩删掉。]]
function host.confirm(title, body, okText, fn)
    log.info("arcade", "确认", title)
    overlay.open({
        title = title, body = body, color = T.c.red,
        p1 = okText or "确定",
        f1 = function()
            overlay.close()
            if fn then fn() end
        end,
        p2 = "先不清空", f2 = function() overlay.close() end,
    })
end

-- ==================== 顶栏 HUD ====================
local function build_hud()
    -- 左侧主色条：随当前游戏换色（圆头小胶囊，比竖线更"软"一点）
    accentBar = airui.container({
        parent = base, x = 18, y = 15, w = 8, h = 32,
        color = T.c.cyan, color_opacity = 255, radius = 4, border_width = 0,
    })
    airui.label({
        parent = base, x = 36, y = 10, w = 250, h = 32,
        text = "益智乐园", font_size = T.f.title, color = T.c.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })

    lbName = airui.label({
        parent = base, x = 300, y = 8, w = 300, h = 28,
        text = "--", font_size = T.f.body, color = T.c.cyan,
        align = airui.TEXT_ALIGN_LEFT,
    })
    lbDesc = airui.label({
        parent = base, x = 300, y = 34, w = 450, h = 22,
        text = "", font_size = T.f.text, color = T.c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右侧两行战绩：宽度按"15 个汉字"留足，超宽会换行并被顶栏高度切掉
    -- 文字色一律比主题色压暗 30%：糖果色当字写在奶油底上会糊，压暗才看得清
    lbS1 = airui.label({
        parent = base, x = 770, y = 6, w = 240, h = 26,
        text = "", font_size = T.f.text, color = fx.shade(T.c.green, -0.32),
        align = airui.TEXT_ALIGN_RIGHT,
    })
    lbS2 = airui.label({
        parent = base, x = 770, y = 32, w = 240, h = 22,
        text = "", font_size = T.f.mini, color = T.c.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 底部操作栏 ====================
local function build_bar()
    -- 白色的"贴纸条"：浅底上靠描边和投影区分层次，不靠深色
    local bar = airui.container({
        parent = base, x = T.stage.x, y = T.bar.y, w = T.stage.w, h = T.bar.h,
        color = T.c.panel, color_opacity = 255, radius = 16,
        border_color = T.paint.board_ln, border_width = 2,
    })

    local b = T.btn
    local bx = b.x - T.stage.x
    local by = b.y - T.bar.y

    airui.button({
        parent = bar, x = bx, y = by, w = b.w, h = b.h,
        text = "大厅", font_size = T.f.text, style = T.style.btn_main,
        on_click = function() M.open(1) end,
    })
    airui.button({
        parent = bar, x = bx + b.w + b.gap, y = by, w = b.w, h = b.h,
        text = "重玩", font_size = T.f.text, style = T.style.btn_ghost,
        on_click = function() M.restart() end,
    })
    airui.button({
        parent = bar, x = bx + (b.w + b.gap) * 2, y = by, w = b.w, h = b.h,
        text = "玩法", font_size = T.f.text, style = T.style.btn_ghost,
        on_click = function() M.show_rules() end,
    })

    lbTip = airui.label({
        parent = bar,
        x = T.bar_tip.x - T.stage.x, y = 10,
        w = T.bar_tip.w, h = T.bar_tip.h,
        text = "", font_size = T.f.text, color = T.c.dim,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 页面调度 ====================
--[[建立某一页（容器 + shape + label + 游戏对象）
shape 必须先建：LVGL 后创建的子对象画在上层，画布建晚了会盖住页面里所有 label。
]]
local function ensure_page(idx)
    local def = PAGES[idx]
    local root = airui.container({
        parent = stage, x = 0, y = 0, w = T.inner.w, h = T.inner.h,
        color = T.c.deep, color_opacity = 255, radius = 8, border_width = 0,
    })
    local shape = airui.shape({
        parent = root, x = 0, y = 0, w = T.inner.w, h = T.inner.h, items = {},
    })
    local pg = { root = root, shape = shape, pool = fx.pool(), n = 0 }
    pg.obj = def.build(root, T.inner.w, T.inner.h, host)
    log.info("ui_shell", "页面已构建", idx, def.name)
    return pg
end

local function update_hud()
    local pg = pages[cur]
    if not pg or not pg.obj or not pg.obj.stats then return end
    local s1, s2 = pg.obj.stats(pg.obj)
    if s1 then lbS1:set_text(s1) end
    if s2 then lbS2:set_text(s2) end
end

--[[切页
@param number idx 1 = 大厅，2..8 = 七款游戏，9 = 排行榜
]]
function M.open(idx)
    if not built then return end
    if idx < 1 or idx > #PAGES then return end
    overlay.close()

    if cur == idx then return end

    local old = pages[cur]
    if old and old.root then old.root:set_hidden(true) end

    local pg = pages[idx]
    if pg then
        -- 回到上次离开的页面，接着上次的局面玩：
        -- 隐藏期间页面不 update，计时 / 动画 / 电脑思考都自然停住，回来继续跑。
        -- 想换新的一局要走「重玩」按钮或结算弹窗的「再玩一次」，不在这里偷偷重开。
        pg.root:set_hidden(false)
    else
        pg = ensure_page(idx)
        pages[idx] = pg
    end

    local def = PAGES[idx]
    cur = idx
    local acc = def.accent or T.c.cyan
    lbName:set_text(def.name)
    lbName:set_color(fx.shade(acc, -0.32))   -- 主题色当字要压暗，色条保持原色
    lbDesc:set_text(def.desc or "")
    lbTip:set_text(def.tip or "")
    accentBar:set_color(acc, 255)

    -- 已经结束的一局：结算弹窗只在结束那一刻弹一次（再弹会重复写成绩），
    -- 所以这里只把底部提示换成"怎么再来一局"，免得孩子以为界面卡住了。
    if pg.obj.is_over and pg.obj.is_over(pg.obj) then
        lbTip:set_text("这一局已经结束啦，按底下的重玩再来一盘")
    end

    if pg.obj.onEnter then pg.obj.onEnter(pg.obj) end
    update_hud()
    log.info("ui_shell", "进入页面", idx, def.name)
end

function M.restart()
    overlay.close()
    local pg = pages[cur]
    if pg and pg.obj and pg.obj.restart then
        pg.obj.restart(pg.obj)
        local def = PAGES[cur]
        -- 上一局结束时底部提示被换成了"按重玩"，重开后要换回这条玩法提示
        if def and def.tip then lbTip:set_text(def.tip) end
        update_hud()
        log.info("ui_shell", "重开当前局")
    end
end

function M.show_rules()
    local def = PAGES[cur]
    overlay.open({
        title = def.name,
        body = def.rules or "暂无说明",
        color = def.accent or T.c.cyan,
        p1 = "知道啦", f1 = function() overlay.close() end,
        p2 = "回大厅", f2 = function() overlay.close() M.open(1) end,
    })
end

-- ==================== 触摸订阅与手势分发 ====================
local TP_DOWN = airui.TP_DOWN or 1
local TP_UP = airui.TP_UP or 3

local QN = 96                              -- 环形缓冲深度（一次按压的事件也够放）
local qx, qy, qs = {}, {}, {}
local qhead, qtail, qcount = 1, 1, 0

local gesture = { down = false, x = 0, y = 0, t = 0 }

local TAP_DIST = 26
local SWIPE_DIST = 60
local LONG_MS = 450

--[[触摸回调（跑在 LVGL 输入线程）
这里只写三个数字进环形缓冲：不建表、不写控件、不做判定。]]
local function touch_cb(state, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    if qcount >= QN then return end
    qx[qtail] = x
    qy[qtail] = y
    qs[qtail] = state
    qtail = qtail % QN + 1
    qcount = qcount + 1
end

--[[屏幕绝对坐标 -> 舞台内容区相对坐标（页面的坐标系原点在 (inner.x, inner.y)）]]
local function to_stage(x, y)
    local lx, ly = x - T.inner.x, y - T.inner.y
    if lx < 0 or ly < 0 or lx >= T.inner.w or ly >= T.inner.h then return nil end
    return lx, ly
end

local function dispatch(kind, x, y, dir)
    local pg = pages[cur]
    if not pg or not pg.obj then return end
    if kind == "swipe" then
        if pg.obj.onSwipe then pg.obj.onSwipe(pg.obj, dir) end
        return
    end
    local lx, ly = to_stage(x, y)
    if not lx then return end
    if kind == "long" then
        -- 只有扫雷用长按（插旗）；其余页面按住不放也当一次点按，免得"按住没反应"
        if pg.obj.onLongTap then
            pg.obj.onLongTap(pg.obj, lx, ly)
        elseif pg.obj.onTap then
            pg.obj.onTap(pg.obj, lx, ly)
        end
    elseif pg.obj.onTap then
        pg.obj.onTap(pg.obj, lx, ly)
    end
end

local function drain_touch()
    while qcount > 0 do
        local st = qs[qhead]
        local x, y = qx[qhead], qy[qhead]
        qhead = qhead % QN + 1
        qcount = qcount - 1

        if st == TP_DOWN then
            if not gesture.down then
                gesture.down = true
                gesture.x, gesture.y, gesture.t = x, y, now_ms()
            end
        elseif st == TP_UP and gesture.down then
            gesture.down = false
            local ms = tick_diff(now_ms(), gesture.t) / TICKS_PER_MS
            local dx, dy = x - gesture.x, y - gesture.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if overlay.is_open() then
                -- 弹窗期间按钮由 LVGL 自己处理，棋盘手势一律丢弃（防止"透过弹窗点到棋盘"）
            elseif dist >= SWIPE_DIST then
                local dir
                if math.abs(dx) > math.abs(dy) then
                    dir = (dx > 0) and 2 or 4
                else
                    dir = (dy > 0) and 3 or 1
                end
                dispatch("swipe", gesture.x, gesture.y, dir)
            elseif dist <= TAP_DIST and ms >= LONG_MS then
                dispatch("long", gesture.x, gesture.y)
            elseif dist <= TAP_DIST then
                dispatch("tap", gesture.x, gesture.y)
            end
        end
    end
end

local function init_touch()
    if not airui.touch_subscribe then
        log.warn("ui_shell", "固件没有 airui.touch_subscribe，游戏内点按不可用")
        return
    end
    if airui.touch_subscribe(touch_cb) then
        log.info("ui_shell", "触摸订阅成功")
    else
        log.error("ui_shell", "触摸订阅失败，游戏内点按不可用")
    end
end

-- ==================== 搭骨架 ====================
--[[搭建整屏界面（在 airui.init + font_load 之后调用）
@param number SW 屏幕宽
@param number SH 屏幕高
]]
function M.build(SW, SH)
    if built then return end
    built = true

    records.init()

    base = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = T.c.bg, color_opacity = 255, radius = 0, border_width = 0,
    })
    build_hud()

    -- 舞台外框：浅底上的"画框"，靠 2px 暖色描边划出边界
    airui.container({
        parent = base, x = T.stage.x, y = T.stage.y, w = T.stage.w, h = T.stage.h,
        color = T.c.deep, color_opacity = 255, radius = 16,
        border_color = T.paint.board_ln, border_width = 2,
    })
    -- 舞台内容区：所有页面都挂在这里，(0,0) 即页面坐标原点
    stage = airui.container({
        parent = base, x = T.inner.x, y = T.inner.y, w = T.inner.w, h = T.inner.h,
        color = T.c.deep, color_opacity = 255, radius = 10, border_width = 0,
    })

    build_bar()
    overlay.build(base)
    overlay.set_back(function()
        overlay.close()
        M.open(1)
    end)

    -- 大厅点卡片进游戏
    home.on_select(function(i) M.open(i + 1) end)

    M.open(1)
    init_touch()
end

-- ==================== 主循环 ====================
--[[逐帧驱动当前页面（阻塞式，请在独立 task 里调用）
推进时间 -> 分发触摸 -> 页面绘制 -> 节流刷新 HUD -> 补偿式睡眠
]]
function M.run()
    init_timebase()

    local t = 0
    local prev = now_ms()
    local waitMs = T.perf.frame_ms
    local dt = T.perf.frame_ms / 1000
    local textT = 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now

        -- 动画步长用固定值，只有真的挂起过（超过 3 帧）才按真实时间补跳
        if realMs > T.perf.frame_ms * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = T.perf.frame_ms / 1000 end
        else
            dt = T.perf.frame_ms / 1000
        end
        t = t + dt

        drain_touch()

        local pg = pages[cur]
        local cost = 0
        if pg and pg.obj then
            local P = pg.pool
            P:reset()
            local t0 = now_ms()
            local ok, err = pcall(pg.obj.update, pg.obj, P, t, dt)
            if ok then
                pg.n = P:finish()
                pg.shape:set_items(P.items)
            else
                log.error("ui_shell", "页面绘制失败", err)
                sys.wait(1000)
            end
            cost = tick_diff(now_ms(), t0) / TICKS_PER_MS
        end

        textT = textT + realMs / 1000
        if textT >= T.perf.text_ms / 1000 then
            textT = 0
            update_hud()
        end

        -- 补偿式节拍：sys.wait 是"至少睡这么久"，工作越重帧率越低会自我恶化
        local wt = T.perf.frame_ms - cost
        if wt < 2 then wt = 2 end
        waitMs = wt
    end
end

return M
