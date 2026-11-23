--[[
界面编排：层次靠创建顺序固定，运行期不调 z-order

  root(1024×600)
    ├ bg 图（整屏烤图，切主题才换）
    ├ stage(88,58,936×412)      ← 页面都在这里，永远在 chrome 之下
    │   ├ page_wall（常驻，只刷新）
    │   └ page_detail（进详情才建，返回即销毁）
    └ chrome（左轴 / 顶栏 / 场景条，常驻）

设置弹层已移除：主题切换改成左轴一个按钮直接换，亮度固定 100%，
少一整棵"点开就重建、关掉就销毁"的控件树。

操作反馈不再用底部黑色提示条：它压住场景条上方，纸面主题下尤其突兀，
而且每次弹出/收起都要重绘 440×46 一块再加一个 1.8s 定时器。
状态变化本身就有视觉反馈（卡片刻度、场景条高亮、徽标文字、整屏换装），够用了。

销毁动作一律走定时器（T2），回调栈里不销毁对象。
]]

local T = require "ui_theme"
local W = require "ui_widget"
local CFG = require "app_config"
local S = require "app_state"
local ut = require "ui_touch"
local HW = require "hardware"
local CH = require "ui_chrome"
local WALL = require "ui_wall"
local DETAIL = require "ui_detail"

local M = {}

local root, stage, chrome, wall, detail
-- 前置声明：build_screen 里要调 tick_clock 并重置 last_date，
-- 这两个都必须在 build_screen 之前就声明为 local，否则写进全局 → 重建后日期不再刷新
local tick_clock
local last_date = ""

local WDAY = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }

--------------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------------
local function later(fn, ms)
    sys.timerStart(fn, ms or 16)
end

--[[
计时用毫秒时钟。两个坑：
  1) 不能用 os.clock：该平台返回整秒，400ms 的建树会打印成 0ms；
  2) 不能把 mcu.ticks() 的原始差值当毫秒：它返回的是 tick 数，
     每秒多少 tick 由 mcu.hz() 决定，本平台不是 1000。
     实测「35 tick」对应日志时间戳 713ms → 1 tick ≈ 20ms（hz ≈ 50），
     直接当毫秒用会少报 20 倍 —— 之前 open/rebuild 那些数字全是这么错的。
]]
local TICK_MS = nil      -- 每个 tick 多少毫秒
local function tick_ms()
    if not TICK_MS then
        local hz = 1000
        if mcu and mcu.hz then
            local ok, v = pcall(mcu.hz)
            if ok and type(v) == "number" and v > 0 then hz = v end
        end
        TICK_MS = 1000 / hz
    end
    return TICK_MS
end

local function now_ms()
    if mcu and mcu.ticks then
        local ok, v = pcall(mcu.ticks)
        if ok and type(v) == "number" then return v * tick_ms() end
    end
    return 0
end

local function kill(node)
    if node then pcall(function() node:destroy() end) end
end

-- 提示条已移除（见文件头），此函数保留为空实现是为了让调用点不用逐条删，
-- 后续要加反馈时在这里统一换成不遮挡内容的形态（如顶栏徽标闪一下）。
local function toast(text)
    log.debug("ui", "hint", text)
end

--------------------------------------------------------------------------
-- 状态 → 视图
--------------------------------------------------------------------------
local function sync_scene_ui()
    if chrome then chrome.set_scene(S.scene) end
    if wall then wall.refresh() end
    if detail then detail.sync() end
end

--[[
落盘策略（P7）：
  场景切换是低频且用户期待"下次开机还在"，立即落盘；
  调档 / 亮度 / 免打扰都是连点操作，走 save_soon() 合并（600ms 一次），
  点击回调里不再出现 flash 写，按压反馈才不会被写盘拖慢。
]]
local function apply_scene(k)
    S.apply_scene(k)
    S.save()
    sync_scene_ui()
    M.back()
    toast(string.format(CFG.txt.toast_scene, CFG.SCENES[k].name))
end

local function set_level(i, v)
    if S.set_level(i, v) then
        S.save_soon()
        sync_scene_ui()
    end
end

--------------------------------------------------------------------------
-- 主题切换（原设置弹层里的两个选项之一，现在直接挂左轴按钮）
--------------------------------------------------------------------------
--[[
一周目是一次整屏重建（控件换色 + 背景图换装），实测 ~700ms 的刷屏成本
无法避免；但它现在只在用户主动点「主题」时发生，不再有"打开设置也要
重建一遍"的额外开销。
]]
local function toggle_theme()
    S.theme = (S.theme == "night") and "paper" or "night"
    S.save()
    T.apply(S.theme)
    later(function() M.rebuild() end, 24)
end

--------------------------------------------------------------------------
-- 页面切换
--------------------------------------------------------------------------
function M.back()
    if not detail then
        ut.set_active("wall")
        return
    end
    local t0 = now_ms()
    S.view = "wall"
    local d = detail
    detail = nil
    ut.release()          -- 高亮层即将随页面销毁，先把按压态撤掉
    ut.drop("detail")
    later(function()
        pcall(function() d.page:destroy() end)
        -- 兜底：drop("detail") 依赖 group 匹配，这里再按实例清一次，避免死对象留在表里
    end, 16)
    ut.set_active("wall")
    if chrome then chrome.set_rail("scene") end
    if wall then wall.refresh() end
    log.info("ui", "back " .. (now_ms() - t0) .. "ms")
end

function M.open(i)
    local t0 = now_ms()
    S.device = i
    S.view = "detail"
    local d = detail
    detail = nil
    if d then
        ut.release()      -- 旧详情页要销毁，先撤掉挂在它上面的按压态
        pcall(function() d.page:destroy() end)
    end
    ut.drop("detail")

    -- 详情页是同步建完的：这期间保持墙卡的按压高亮，
    -- 建完再撤 → 视觉上是"按下亮起 → 页面出现 → 高亮退去"，中间不空一帧
    W.set_group("detail")
    detail = DETAIL.build(stage, i, M.cb)
    W.set_group(nil)
    ut.release()
    ut.set_active("detail")
    -- 详情页不属于左轴任何一项：取消高亮，让「场景」变回一个普通按钮的样子。
    -- 原来这里写的是 set_rail("scene")，结果「场景」一直亮着，看着像"我已经在
    -- 场景里了"，反而不像个出口——这是详情页退不出去的主因之一。
    -- 左轴「场景」本身仍然是返回（on_rail 里 scene -> M.back），保留作第二入口。
    if chrome then chrome.set_rail(nil) end
    log.info("ui", "open " .. (now_ms() - t0) .. "ms")
end

--------------------------------------------------------------------------
-- 回调表（交给各页面模块）
--------------------------------------------------------------------------
M.cb = {
    -- 详情页面板底部的「返回场景墙」。走 later 是为了不让销毁动作落在
    -- 点击回调栈里（详情页要整棵销毁，见 M.back）
    on_back = function()
        later(function() M.back() end)
    end,

    on_card = function(i)
        later(function() M.open(i) end)
    end,

    on_scene = function(k)
        later(function() apply_scene(k) end)
    end,

    on_rail = function(key)
        if key == "scene" then
            later(function() M.back() end)
        elseif key == "service" then
            S.bell = true
            chrome.set_badge("已呼叫")
            toast(CFG.txt.toast_bell)
            sys.timerStart(function()
                S.bell = false
                if chrome then chrome.set_badge(CFG.ROOM.badge) end
            end, 4000)
        elseif key == "mute" then
            S.dnd = not S.dnd
            chrome.set_badge(S.dnd and "免打扰" or CFG.ROOM.badge)
            toast(S.dnd and CFG.txt.toast_mute or CFG.txt.toast_unmute)
            S.save_soon()
        elseif key == "theme" then
            later(toggle_theme)
        end
    end,

    on_power = function(i)
        S.toggle(i)
        S.save_soon()
        local d = detail
        if d then d.sync() end
        if wall then wall.refresh() end
        if chrome then chrome.set_scene(S.scene) end
    end,

    on_step = function(i, delta)
        set_level(i, (S.levels[i] or 0) + delta)
    end,

    on_quick = function(i, v)
        set_level(i, v)
    end,

}

--------------------------------------------------------------------------
-- 整屏构建
--------------------------------------------------------------------------
local function build_screen()
    W.set_group(nil)
    root = W.box(nil, {
        x = 0, y = 0, w = CFG.W, h = CFG.H,
        color = T.c.bg, border_width = 0, tag = "root",
    })
    W.mark(root, 0, 0)

    -- 背景：整屏一张烤图（1024×600 原尺寸，直接 stretch），两套主题各一张
    W.image(root, {
        x = 0, y = 0, w = CFG.W, h = CFG.H, src = T.bg_img(), fit = "stretch", tag = "bg",
    })

    -- 舞台：页面容器，chrome 之前创建 → 永远压在 chrome 下面
    stage = W.box(root, {
        x = CFG.LAY.stage_x, y = CFG.LAY.stage_y,
        w = CFG.LAY.stage_w, h = CFG.LAY.stage_h,
        color = -1, border_width = 0, tag = "stage",
    })
    -- 不要 W.mark(stage)：box 已按父链记下 (88,58)，再标成 (0,0) 会让
    -- 页面内所有热区整体偏移 88/58，表现为"点左上角才响应"

    W.set_group("wall")
    wall = WALL.build(stage, M.cb)

    -- 框架
    W.set_group(nil)
    chrome = CH.build(root, M.cb)
    chrome.set_scene(S.scene)
    chrome.set_badge(S.dnd and "免打扰" or CFG.ROOM.badge)

    ut.set_active(S.view == "detail" and "detail" or "wall")

    if S.view == "detail" then
        M.open(S.device)
    else
        detail = nil
    end

    -- 重建后日期标签是新的（空串），last_date 必须一起失效，否则当天不再刷新
    last_date = ""
    tick_clock()
end

--------------------------------------------------------------------------
-- 主题切换：全量重建（控件 < 120、有整屏图片要换 → 走路线 A）
--------------------------------------------------------------------------
function M.rebuild()
    -- 换主题一律回到场景墙。详情页是另一整棵控件树（约 40 个控件 + 一张大图），
    -- 留着它就要连它一起重建，切一次主题的构建量直接翻倍；而且换完主题先看
    -- 一眼全局也符合直觉。真机实测这一步能省掉近一半的构建时间。
    -- 埋点：这条日志是"构建耗时"（含 image 创建时的同步解码），不含 LVGL
    -- 刷屏——刷屏发生在下一个 refresh 周期。冷/热两次的值差就是解码成本。
    local t0 = now_ms()
    S.view = "wall"
    -- 控件连同热区一起重来：chrome 的热区登记在 nil 组，drop 删不掉，必须整表清空
    ut.clear()

    -- wall/detail 都是 root 的子孙，销毁 root 即可
    kill(root)
    detail, stage, root, wall, chrome = nil, nil, nil, nil, nil

    build_screen()
    log.info("ui", "rebuild " .. (now_ms() - t0) .. "ms")
end

--------------------------------------------------------------------------
-- 时钟
--------------------------------------------------------------------------
--[[
真 / 假两档。

板子上没有时间源：既没有联网对时，RTC 也从没被写过，os.date 拿回来的是
1970 那种出厂值。界面需要的是"看着正常、会走字"，不是"与世界时间一致"。

  1) 系统时间有效（year >= 2024）→ 用真时间，24 小时制。
     原先那版做 12 小时制换算、又没有 AM/PM 的位置，21:30 被显示成 09:30，
     这才是"右上角时间不对"的原始原因。
  2) 否则 → 假时钟：从 CFG.CLOCK 的钟面起，每秒 +1 推进，跨零点进位到天。

假时钟用秒计数器、不用 mcu.ticks 差值：这里只要"不倒退、不跳"，秒级漂移
无所谓；而 mcu.ticks 在部分固件上拿不到，差值会算出负数让钟面往回走。
]]
local CLK = CFG.CLOCK
local FAKE_BASE = CLK.hour * 3600 + CLK.min * 60   -- 每日起点（秒）
local fake_sec = 0                                  -- 假时钟已走过的秒数
local fake_logged = false

-- 日期进位：假时钟连续跑过零点时把天数推到月，只管月/日，不管年
local function add_days(month, day, n)
    local mdays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    day = day + n
    while day > mdays[month] do
        day = day - mdays[month]
        month = month % 12 + 1
    end
    return month, day
end

tick_clock = function()
    if not chrome then return end

    local t = os.date("*t")
    local hh, mm, date

    if t and t.year and t.year >= 2024 then
        hh, mm = t.hour, t.min
        date = string.format("%d月%d日 · %s", t.month, t.day, WDAY[t.wday] or "")
    else
        fake_sec = fake_sec + 1
        local total = FAKE_BASE + fake_sec
        local days = total // 86400
        local rest = total % 86400
        hh = rest // 3600
        mm = (rest % 3600) // 60
        local mo, dy = add_days(CLK.month, CLK.day, days)
        date = string.format("%d月%d日 · %s", mo, dy, WDAY[(CLK.wday + days - 1) % 7 + 1] or "")
        if not fake_logged then
            fake_logged = true
            log.info("ui", "系统时间无效，顶栏走假时钟", string.format("%02d:%02d", CLK.hour, CLK.min))
        end
    end

    chrome.set_clock(hh, mm)
    if date ~= last_date then           -- 日期一天才变一次，不做每秒重排
        last_date = date
        chrome.set_date(date)
    end
end

--[[
背光点亮延迟（ms）。

背光此前是在 build_screen() 之前就开到 100%，而 RGB 屏从上电起就在持续扫描
帧缓冲，那块 buffer 里是 PSRAM 的未初始化内容。于是从"亮灯"到"首帧画完"
之间（实测建树 + 全屏填充约 700ms）用户看到的是一屏雪花 / 彩色条纹。

这里改成建树之后再等一帧的时间才亮灯。800ms 是实测首帧（614400 px 全屏
填充约 713ms）留的余量；改小会重新露出半张界面，改大只是黑屏时间变长。
]]
local BRIGHT_DELAY_MS = 800

function M.start()
    S.load()
    T.apply(S.theme)
    build_screen()
    -- 兜底分发必须先订阅再收事件；订阅失败/触摸无数据都会在日志里明确写出来
    ut.start()
    tick_clock()
    sys.timerLoopStart(tick_clock, 1000)
    -- 首帧刷出去之后再点背光，观感从"花一下再出界面"变成"先黑一会儿，然后
    -- 界面直接出现"。hits 已就绪，万一只亮了但界面没起来，日志里有"界面已就绪"。
    sys.timerStart(function() HW.set_brightness(100) end, BRIGHT_DELAY_MS)
    log.info("ui", "界面已就绪", S.theme, S.view, "热区", ut.count(),
        "背光", BRIGHT_DELAY_MS .. "ms 后点亮")
    return true
end

return M
