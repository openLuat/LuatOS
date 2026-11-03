--[[
@module  ui_calendar
@summary 情绪日历主界面：当月日历 + 心情指数面板 + 底部按钮
@author  蒋骞
@version 1.0
@date    2026.10.30

=== 布局（1024x600 横屏）===
顶栏 0..96         标题「情绪日历」+ 今天日期星期 + 今日心情
导航 104..144      上月 / 年月 / 下月 + 五档心情图例
日历 150..536      7 列 x 6 行固定 42 格，每格 88x56
                   第一行：公历日；第二行左：农历/节日，右：心情名
底部 546..594      「本月心情」「今天心情」+ 操作提示
右面板 676..1000   心情指数卡 + 给你的一句话卡

=== 节假日 ===
法定 / 传统节日当天：淡红底 + 酒红日期 + 第二行显示节日名（如「国庆」「中秋」）。
平时第二行显示农历日（如「廿一」），闰月会带「闰」字。
农历数据覆盖 2020-2040，超出范围就不显示农历，其余功能不受影响。

=== 交互 ===
点任意「今天及以前」的格子 -> 弹心情选择浮层（ui_picker）
点「本月心情」             -> 弹月度报告浮层（ui_report）
点「今天心情」             -> 直接弹出今天的选择
翻页只能往前，不能翻到未来月份。

=== 刷新策略 ===
app_main 每秒调 M.refresh()，但只有「日期变了」才真正重画：
LVGL 每次 set_text / set_color 都会标脏重绘，每秒无脑刷会掉帧。
]]
local conf = require "conf"
local theme = require "theme"
local du = require "date_util"
local rtc_util = require "rtc_util"
local mood_store = require "mood_store"
local mood_stat = require "mood_stat"
local lunar = require "lunar"

local M = {}

local C = theme.C
local SW, SH = conf.W, conf.H
local MOODS = conf.moods

-- ==================== 布局常量 ====================
local GRID_X, GRID_Y = 24, 180      -- 第一格左上角
local CELL_W, CELL_H = 88, 56       -- 单格尺寸
local COL_STEP, ROW_STEP = 92, 60   -- 含 4px 间隙

-- ==================== 状态 ====================
local root = nil
local cells = {}                    -- [1..42] { box, lb_day, lb_mood, day, clickable }

local lb_sub, lb_today, lb_month
local lb_idx_title, lb_idx_num, lb_idx_word, lb_idx_days
local lb_bless

local data = {}                     -- 当前显示月份的记录 { [day] = score }
local cur_y, cur_m                  -- 当前显示的月份
local cache_day                     -- "2026-10-30"，用于跨天判断

-- 由 ui_main 注入
M.on_pick = nil                     -- function(y, m, d, score)
M.on_report = nil                   -- function(y, m, summary, bless)

-- ==================== 工具 ====================
local function is_current_month(y, m)
    local t = rtc_util.now()
    return t and t.year == y and t.month == m
end

--[[顶栏副标题：公历 + 星期 + 农历
农历拿不到（超出 2020-2040）就只有前半段，不会留个孤零零的分隔符。
]]
local function fmt_date(t)
    local s = string.format("%04d年%02d月%02d日  星期%s", t.year, t.month, t.day, du.week_cn(t.wday))
    local l = lunar.full(t.year, t.month, t.day)
    if l ~= "" then s = s .. "  " .. l end
    return s
end

-- ==================== 构建 ====================
local function build_header()
    theme.label(root, 32, 14, 420, 54, "情绪日历", 38, C.ink)
    lb_sub = theme.label(root, 34, 66, 560, 30, "", 20, C.ink2)
    lb_today = theme.label(root, 600, 26, 400, 30, "", 18, C.ink2, airui.TEXT_ALIGN_RIGHT)
end

local function build_nav()
    theme.button(root, 24, 104, 44, 40, "<", 20, function()
        theme.defer(function() M.step_month(-1) end)
    end)
    lb_month = theme.label(root, 78, 106, 200, 40, "", 28, C.ink)
    theme.button(root, 286, 104, 44, 40, ">", 20, function()
        theme.defer(function() M.step_month(1) end)
    end)

    -- 心情图例：告诉用户格子的颜色代表什么
    for i = 1, #MOODS do
        local m = MOODS[i]
        local x = 356 + (i - 1) * 60
        theme.box(root, x, 118, 12, 12, m.color, 6, 255)
        theme.label(root, x + 16, 108, 42, 28, m.name, 14, C.ink2)
    end
end

local function build_grid()
    -- 星期抬头（周日打头，跟人习惯一致）
    for i = 0, 6 do
        local col = (i == 0) and C.today or C.ink3
        theme.label(root, GRID_X + i * COL_STEP, 150, CELL_W, 26,
            du.WEEK_CN[i + 1], 16, col, airui.TEXT_ALIGN_CENTER)
    end

    -- 42 个格子：容器负责底色和边框，两个 label 分别放日期和心情名
    for i = 0, 41 do
        local c, r = i % 7, math.floor(i / 7)
        local x = GRID_X + c * COL_STEP
        local y = GRID_Y + r * ROW_STEP
        local box = airui.container({
            parent = root, x = x, y = y, w = CELL_W, h = CELL_H,
            color = C.card, radius = 12, border_color = C.line, border_width = 1,
        })
        -- 第一行公历日；第二行左农历/节日、右心情名（12 号字刚好放得下 3 个字）
        local lb_day = theme.label(box, 8, 3, CELL_W - 16, 24, "", 18, C.ink)
        local lb_lunar = theme.label(box, 7, 27, 42, 22, "",
            12, C.ink3, airui.TEXT_ALIGN_LEFT)
        local lb_mood = theme.label(box, 48, 27, 36, 22, "",
            12, C.ink2, airui.TEXT_ALIGN_RIGHT)

        local idx = i + 1
        box:set_on_click(function()
            local cell = cells[idx]
            if not cell or not cell.day or not cell.clickable then return end
            local y0, m0, d0 = cur_y, cur_m, cell.day
            local score = data[d0]
            theme.defer(function()
                if M.on_pick then M.on_pick(y0, m0, d0, score) end
            end)
        end)

        cells[idx] = { box = box, lb_day = lb_day, lb_lunar = lb_lunar, lb_mood = lb_mood }
    end
end

local function build_bottom()
    theme.button(root, 24, 546, 200, 48, "本月心情", 22, function()
        theme.defer(function() M.open_report() end)
    end)
    theme.button(root, 236, 546, 200, 48, "今天心情", 22, function()
        theme.defer(function() M.pick_today() end)
    end)
    theme.label(root, 452, 556, 212, 36, "点一个日子，记下当天心情", 14, C.ink3)
end

local function build_panel()
    -- 指数卡
    theme.card(root, 676, 104, 324, 236, C.card, 18, C.line, 1)
    lb_idx_title = theme.label(root, 696, 116, 284, 26, "", 17, C.ink2)
    lb_idx_num = theme.label(root, 692, 140, 180, 84, "--", 60,
        C.ink3)
    theme.label(root, 856, 186, 60, 30, "/ 5", 20, C.ink3)
    lb_idx_word = theme.label(root, 696, 228, 284, 32, "", 22, C.ink)
    lb_idx_days = theme.label(root, 696, 286, 284, 26, "", 15, C.ink2)

    -- 祝福语卡
    theme.card(root, 676, 352, 324, 242, C.panel, 18, C.line, 1)
    theme.label(root, 696, 364, 284, 26, "给你的话", 17, C.ink2)
    lb_bless = theme.label(root, 696, 392, 284, 190, "", 16, C.ink)
end

-- ==================== 绘制 ====================
--[[画一个格子
@param cell 格子控件组
@param score number|nil 当天分数
@param is_today boolean
@param future boolean 是否未来日期
@param ltxt string 第二行左侧（农历日 / 节日名）
@param lfest boolean 这一天是不是节日
]]
local function paint_cell(cell, score, is_today, future, ltxt, lfest)
    local box = cell.box
    local m = score and mood_stat.mood(score) or nil

    -- 底色优先级：已记录心情 > 未来 > 节假日 > 普通
    -- 心情优先，因为那是用户自己填的内容，不能被节日盖掉
    if m then
        box:set_color(theme.tint(m.color, 0.74), 255)
        box:set_border_color(m.color, 1)
        cell.lb_day:set_color(theme.shade(m.color, 0.62))
        cell.lb_mood:set_text(m.name)
        cell.lb_mood:set_color(theme.shade(m.color, 0.45))
    elseif future then
        box:set_color(C.panel, 255)
        box:set_border_color(C.line, 1)
        cell.lb_day:set_color(C.ink3)
        cell.lb_mood:set_text("")
    elseif lfest then
        box:set_color(C.fest_bg, 255)
        box:set_border_color(C.fest_line, 1)
        cell.lb_day:set_color(C.fest)
        cell.lb_mood:set_text("")
    else
        box:set_color(C.card, 255)
        box:set_border_color(C.line, 1)
        cell.lb_day:set_color(C.ink)
        cell.lb_mood:set_text("")
    end

    -- 第二行左半：节日名一直用酒红（未来月份也能提前看到放假），平时是灰色农历
    cell.lb_lunar:set_text(ltxt or "")
    cell.lb_lunar:set_color(lfest and C.fest or C.ink3)

    -- 今天永远给一圈强调描边，方便一眼找到自己在哪
    if is_today then
        box:set_border_color(C.today, 2)
    end
end

local function refresh_today_tag()
    local t = rtc_util.now()
    if not t then return end
    local s
    if cur_y == t.year and cur_m == t.month then
        s = data[t.day]
    else
        s = mood_store.load(t.year, t.month)[t.day]
    end
    if s then
        local m = mood_stat.mood(s)
        lb_today:set_text(string.format("今天   %s   %d 分", m.name, s))
        lb_today:set_color(theme.shade(m.color, 0.35))
    else
        lb_today:set_text("今天   还没记录心情")
        lb_today:set_color(C.ink3)
    end
end

local function refresh_index()
    local sum = mood_stat.summary(data, cur_y, cur_m)

    if sum.avg then
        lb_idx_num:set_text(string.format("%.1f", sum.avg))
        lb_idx_num:set_color(C.accent)
    else
        lb_idx_num:set_text("--")
        lb_idx_num:set_color(C.ink3)
    end

    lb_idx_word:set_text(mood_stat.word(sum.avg))
    lb_idx_days:set_text(mood_stat.summary_line(sum))
    lb_bless:set_text(mood_stat.join(mood_stat.compliment(sum)))
    return sum
end

--[[重画整个月份（翻月 / 跨天 / 改了记录时调用）]]
local function draw()
    lb_month:set_text(string.format("%04d年%02d月", cur_y, cur_m))
    lb_idx_title:set_text(string.format("%d月心情指数", cur_m))

    local grid = du.month_grid(cur_y, cur_m)
    local t = rtc_util.now()
    local today_ts = du.midnight(t.year, t.month, t.day)

    for i = 1, 42 do
        local it = grid[i]
        local cell = cells[i]
        if it.cur then
            local ts = du.midnight(cur_y, cur_m, it.day)
            local future = ts > today_ts
            local ltxt, lfest = lunar.cell_text(cur_y, cur_m, it.day)
            cell.day = it.day
            cell.clickable = not future
            cell.lb_day:set_text(tostring(it.day))
            paint_cell(cell, data[it.day], ts == today_ts, future, ltxt, lfest)
        else
            -- 上月 / 下月的补位格：整个格子变全透明，也不响应点击
            cell.day = nil
            cell.clickable = false
            cell.lb_day:set_text("")
            cell.lb_lunar:set_text("")
            cell.lb_mood:set_text("")
            cell.box:set_color(C.bg1, 0)
            cell.box:set_border_color(C.bg1, 0)
        end
    end

    refresh_index()
    refresh_today_tag()
end

-- ==================== 对外接口 ====================
--[[翻月：delta = -1 上月，+1 下月；不允许翻到未来]]
function M.step_month(delta)
    local y, m = cur_y, cur_m + delta
    if m < 1 then y, m = y - 1, 12 end
    if m > 12 then y, m = y + 1, 1 end

    local t = rtc_util.now()
    if t and (y * 12 + m) > (t.year * 12 + t.month) then
        log.info("calendar", "不能翻到未来的月份")
        return
    end

    cur_y, cur_m = y, m
    data = mood_store.load(cur_y, cur_m)
    draw()
    log.info("calendar", "翻月", string.format("%04d-%02d", cur_y, cur_m))
end

--[[跳到真实当月（点「本月心情」「今天心情」前先对齐月份）]]
function M.show_current_month()
    local t = rtc_util.now()
    if not t then return end
    if cur_y ~= t.year or cur_m ~= t.month then
        cur_y, cur_m = t.year, t.month
        data = mood_store.load(cur_y, cur_m)
        draw()
    end
end

--[[写一条记录（分数传 nil 表示清除当天）]]
function M.set_score(y, m, day, score)
    local t = mood_store.load(y, m)
    t[day] = score
    mood_store.save(y, m, t)

    if y == cur_y and m == cur_m then
        data = t
        draw()
    end
    log.info("calendar", "记录心情", string.format("%04d-%02d-%02d", y, m, day),
        score and (mood_stat.mood(score).name .. " " .. score .. "分") or "清除")
end

--[[弹出月度报告]]
function M.open_report()
    M.show_current_month()
    local sum = mood_stat.summary(data, cur_y, cur_m)
    local bless = mood_stat.compliment(sum)
    log.info("calendar", "月度报告", string.format("%04d-%02d", cur_y, cur_m),
        "记录", sum.n, "平均", sum.avg and string.format("%.1f", sum.avg) or "无")
    if M.on_report then M.on_report(cur_y, cur_m, sum, bless) end
end

--[[直接记录今天的心情]]
function M.pick_today()
    M.show_current_month()
    local t = rtc_util.now()
    if not t then return end
    if M.on_pick then M.on_pick(t.year, t.month, t.day, data[t.day]) end
end

--[[每秒调用：只有跨天才真正干活]]
function M.refresh()
    local t = rtc_util.now()
    if not t then return end
    local key = string.format("%04d-%02d-%02d", t.year, t.month, t.day)
    if key == cache_day then return end
    cache_day = key

    lb_sub:set_text(fmt_date(t))
    -- 跨天：今天之后的那格从「未来」变成「可点」，必须重画
    if cur_y == t.year and cur_m == t.month then
        data = mood_store.load(cur_y, cur_m)
        draw()
    else
        refresh_today_tag()
    end
end

function M.build(parent)
    root = theme.plain(parent, 0, 0, SW, SH)
    build_header()
    build_nav()
    build_grid()
    build_bottom()
    build_panel()

    local t = rtc_util.now() or { year = 2026, month = 1, day = 1 }
    cur_y, cur_m = t.year, t.month
    data = mood_store.load(cur_y, cur_m)
    cache_day = nil
    M.refresh()
    return root
end

return M
