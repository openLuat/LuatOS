--[[
@module  relay_win
@summary 继电器控制页面（485 主站，8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
通过 485（UART11）Modbus RTU 主站控制 4 路继电器模块。
- 2×2 通道卡片，整卡可点击即翻转该路（发布 RELAY_SET_REQ(ch, "toggle")）
- 订阅 RELAY_STATUS_UPDATE 同步各开关与状态文字（通道 0~3）
- 底部保留 全部接通 / 全部断开 / 回读状态

视觉：ui_theme 深色玻璃态（2×2 通道卡片 + 语义色按钮）。

=== v2.1 修复：点击无响应 ===
现象：进入本页后点击通道开关没有任何反应（或状态来回跳一下就复原）。
两个叠加原因：
  1) 点击回调首行用 exwin.is_active(win_id) 作准入条件，而 win_id 是模块级变量，
     窗口被批量回收（exwin 菜单切换事务）或多实例并存时会被旧实例的 on_destroy
     置为 nil，导致屏幕上本实例的判定恒为 false，点击在入口被静默丢弃；
  2) 原来的开关由「轨道 + 滑块」两个容器组成，二者都绑定了同一次点击回调，
     一次点击被触发两次 → 翻两次 → 视觉上等于没反应。
修复：
  1) 开关改为只读指示器（theme.switch 的 readonly 模式），点击统一由外层卡片承接，
     一次点击只触发一次；
  2) 准入条件改用本地存活性标志 ui_alive（on_create 置真 / on_destroy 置假）；
  3) open_handler 增加单实例保护；
  4) 点击时打印日志，便于现场定位。

=== v2.2 修复：按钮不灵敏 + 回读覆盖本地回显 ===
现象：通道卡片「按钮很不好用」，需点很精确的位置才有反应；点不中时毫无反馈；
      偶发「刚点亮的通道被刷回原位」。
两个原因：
  1) 点击命中面太窄：本页用 theme.card 建卡，卡内两个 label 与开关（readonly）
     都没有绑回调。airui 的触摸命中不会从子元素回传给父容器，点到文字 / 开关图形
     区域的触摸被直接吞掉，只剩卡片空白缝隙可点 → 表现为「非常不灵敏」。
  2) 回读覆盖：relay_ctrl 是「RELAY_SET_REQ 入队 + 常驻协程串行执行」的异步模型。
     点击后本地先回显，485 异步执行完成再用 RELAY_STATUS_UPDATE 回写；若通信失败
     或时序错开，回写会把用户刚翻转的开关刷回原位 → 表现为「点了没反应 / 跳回」。
修复：
  1) 卡片改用 theme.tap_card，把同一去重回调 tap 绑到卡片、两个 label、
     以及开关的轨道与滑块（switch 新增 o.tap 透传）→ 整卡任意处可点，且一次点击只翻转一次；
  2) 新增「本地操作保护窗口」LOCAL_GUARD_MS：点击后在该窗口内忽略该通道的回读结果，
     窗口过后恢复正常同步（最终一致），避免刚点的状态被即时刷回。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local ch_state_labels = {}      -- 每路状态文字 label
local ch_switches = {}          -- 每路开关句柄（ui_theme.switch，只读指示器）

-- 本页 UI 存活性标志：只由 on_create / on_destroy 维护
local ui_alive = false

-- 通道数量（与 relay_ctrl.CH_COUNT 保持一致）
local CH_COUNT = 4

--[[本地操作保护窗口（ms）
relay_ctrl 是「RELAY_SET_REQ 入队 + 常驻协程串行执行」的异步模型：点击后本地先回显，
485 执行完成再用 RELAY_STATUS_UPDATE 回写。若回写用的是尚未更新的旧值（通信失败 /
时序错开），就会把用户刚翻转的开关即时刷回，表现为「点了没反应 / 跳回」。
故：点击后在该通道上开一个保护窗口，窗口内忽略回读结果，窗口过后恢复正常同步（最终一致）。]]
local LOCAL_GUARD_MS = 1200
local ch_guard = {}          -- ch_guard[idx] = true 表示该通道处于本地保护期
local ch_guard_timer = {}    -- 保护期定时器 id，用于重复点击时重置计时
for i = 1, CH_COUNT do
    ch_guard[i] = false
    ch_guard_timer[i] = nil
end

-- 布局常量（内容区 464×210）
local CARD_W   = 228
local CARD_H   = 66
local CARD_GAP = 6
local SW_W     = 44
local SW_H     = 24

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not ui_alive then return end
    exwin.close(win_id)
end

--[[开启某通道的本地保护窗口
重复点击会重置计时，保证「最后一次点击」之后仍完整保护一个窗口期。
@local
@function set_guard
@param idx number 1-based 通道索引
]]
local function set_guard(idx)
    if ch_guard_timer[idx] then sys.timerStop(ch_guard_timer[idx]) end
    ch_guard[idx] = true
    ch_guard_timer[idx] = sys.timerStart(function()
        ch_guard[idx] = false
        ch_guard_timer[idx] = nil
    end, LOCAL_GUARD_MS)
end

--[[刷新某通道的状态文字与颜色
@local
@function update_label
@param idx number 1-based 通道索引
@param on boolean 是否接通
]]
local function update_label(idx, on)
    local lbl = ch_state_labels[idx]
    if not lbl then return end
    if on then
        lbl:set_text("接通")
        lbl:set_color(theme.SEM.success)
    else
        lbl:set_text("断开")
        lbl:set_color(theme.C.t2)
    end
end

--[[
继电器状态更新回调：同步各通道状态文字与开关位置

@local
@function on_relay_status_update
@param state table 继电器状态数组（1-based，state[i]=1 表示接通）
]]
local function on_relay_status_update(state)
    if not ui_alive then return end
    if type(state) ~= "table" then return end
    for i = 1, CH_COUNT do
        -- 本地保护期内跳过该通道：避免用户刚翻转的开关被异步回读即时刷回
        if not ch_guard[i] then
            local on = (state[i] == 1)
            update_label(i, on)
            -- 开关为只读指示器：set_state 只更新显示，不会反向触发点击回调
            if ch_switches[i] then
                ch_switches[i]:set_state(on)
            end
        end
    end
end

--[[
通道切换（整卡点击）：本地先回显，再下发翻转指令由 relay_ctrl 执行

@local
@function on_ch_click
@param ch number 通道号（0~3）
]]
local function on_ch_click(ch)
    if not ui_alive then
        log.warn("relay_win", "点击被丢弃 通道" .. ch .. " ui_alive=", ui_alive, "win_id=", win_id)
        return
    end
    local idx = ch + 1
    local handle = ch_switches[idx]
    if not handle then return end
    local target = not handle:get_state()
    handle:set_state(target)
    update_label(idx, target)
    set_guard(idx)                    -- 进入本地保护期，避免被异步回读刷回
    sys.publish("RELAY_SET_REQ", ch, "toggle")
    log.info("relay_win", "通道" .. ch .. " 请求翻转 ->", target and "接通" or "断开")
end

-- 各通道卡片点击回调（组件回调必须为具名函数）
local function on_ch0_click() on_ch_click(0) end
local function on_ch1_click() on_ch_click(1) end
local function on_ch2_click() on_ch_click(2) end
local function on_ch3_click() on_ch_click(3) end

local card_funcs = { on_ch0_click, on_ch1_click, on_ch2_click, on_ch3_click }

-- 全部接通
local function on_all_open_click()
    if not ui_alive then return end
    for i = 1, CH_COUNT do set_guard(i) end   -- 全量操作同样进入本地保护期
    sys.publish("RELAY_SET_REQ", nil, "all_open")
    log.info("relay_win", "请求全部接通")
end

-- 全部断开
local function on_all_close_click()
    if not ui_alive then return end
    for i = 1, CH_COUNT do set_guard(i) end
    sys.publish("RELAY_SET_REQ", nil, "all_close")
    log.info("relay_win", "请求全部断开")
end

-- 回读状态
local function on_read_click()
    if not ui_alive then return end
    sys.publish("RELAY_SET_REQ", nil, "read")
    log.info("relay_win", "请求回读状态")
end

--[[
创建继电器控制 UI

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "继电器控制 (485)", on_back = on_back_click })
    main_container = ctx.base

    for i = 1, CH_COUNT do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = ctx.x + col * (CARD_W + CARD_GAP)
        local y = ctx.y + row * (CARD_H + CARD_GAP)

        --[[点击贯通：卡片用 tap_card 取出去重回调 tap，再绑到卡内每个可见子元素。
        airui 的触摸命中不会从子元素回传给父容器，若子元素不绑回调，
        点到文字 / 开关图形区域的触摸会被吞掉 → 整卡可点区域被压到极小的空白缝隙。]]
        local card, tap = theme.tap_card(ctx.base, {
            x = x, y = y, w = CARD_W, h = CARD_H,
            on_click = card_funcs[i],
        })

        theme.label(card, {
            x = 12, y = 8, w = 120, h = 19,
            text = "通道 " .. (i - 1), px_size = 16, color = theme.C.t3,
            on_click = tap })

        ch_state_labels[i] = theme.label(card, {
            x = 12, y = 32, w = 120, h = 21,
            text = "未知", px_size = 18, color = theme.C.t2,
            on_click = tap })

        ch_switches[i] = theme.switch(card, {
            x = CARD_W - SW_W - 14, y = math.floor((CARD_H - SW_H) / 2),
            w = SW_W, h = SW_H, checked = false,
            readonly = true,          -- 只读：不自行翻转，点击由外层卡片承接
            tap = tap,                -- 轨道与滑块也命中同一去重回调（点击贯通）
        })
    end

    -- 底部批量操作按钮（三枚等宽）
    local btn_y = ctx.y + 2 * (CARD_H + CARD_GAP) + 6
    local btn_w = 150
    local btn_h = 32
    local btn_gap = 7
    theme.btn(ctx.base, {
        x = ctx.x, y = btn_y, w = btn_w, h = btn_h, text = "全部接通",
        bg = theme.C.green, fg = 0x06231A, on_click = on_all_open_click })
    theme.btn(ctx.base, {
        x = ctx.x + btn_w + btn_gap, y = btn_y, w = btn_w, h = btn_h, text = "全部断开",
        bg = theme.C.rose, fg = 0x2A0A10, on_click = on_all_close_click })
    theme.btn(ctx.base, {
        x = ctx.x + 2 * (btn_w + btn_gap), y = btn_y, w = btn_w, h = btn_h, text = "回读状态",
        on_click = on_read_click })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    ui_alive = true
    create_ui()
    sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    -- 打开页面时主动回读一次状态
    sys.publish("RELAY_SET_REQ", nil, "read")
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    -- 先失效点击准入，再释放组件
    ui_alive = false
    -- 清掉本地保护窗口的定时器，避免页面销毁后回调仍触碰已释放的组件
    for i = 1, CH_COUNT do
        if ch_guard_timer[i] then
            sys.timerStop(ch_guard_timer[i])
            ch_guard_timer[i] = nil
        end
        ch_guard[i] = false
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    ch_state_labels = {}
    ch_switches = {}
    sys.unsubscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    if not ui_alive then return end
    sys.publish("RELAY_SET_REQ", nil, "read")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_RELAY_WIN 消息处理器

单实例保护：已在栈顶的本页实例直接忽略重复请求；
若存在残留的非活动实例则先回收，保证同一时刻只有一个本页实例。

@local
@function open_handler
]]
local function open_handler()
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RELAY_WIN", open_handler)
