--[[
@module  relay_win
@summary 继电器控制页面（485 主站，8301出厂固件）
@version 1.1
@date    2026.09.24
@author  江访
@usage
通过 485（UART11）Modbus RTU 主站控制 4 路继电器模块。
- 每路一个 airui.switch 滑动开关，点击即翻转该路（发布 RELAY_SET_REQ）
- 订阅 RELAY_STATUS_UPDATE 同步各开关与状态文字（通道 0~3）
- 底部保留 全部接通 / 全部断开 / 回读状态
]]

local win_id = nil
local main_container, content
local ch_state_labels = {}      -- 每路状态文字 label
local ch_switches = {}          -- 每路开关组件（airui.switch）
local updating_switch = false   -- 程序化同步开关状态时置位，用于屏蔽 on_change 误触发

-- 通道数量（与 relay_ctrl.CH_COUNT 保持一致）
local CH_COUNT = 4

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[
继电器状态更新回调：同步各通道状态文字与开关位置

@local
@function on_relay_status_update
@param state table 继电器状态数组（1-based，state[i]=1 表示接通）
]]
local function on_relay_status_update(state)
    if not exwin.is_active(win_id) then return end
    if type(state) ~= "table" then return end
    -- 同步期间置位标志：set_state 触发的 on_change 回调需要被忽略，避免循环下发指令
    updating_switch = true
    for i = 1, CH_COUNT do
        local on = (state[i] == 1)
        local lbl = ch_state_labels[i]
        if lbl then
            if on then
                lbl:set_text("接通")
                lbl:set_color(T.COLOR_GREEN)
            else
                lbl:set_text("断开")
                lbl:set_color(T.COLOR_TEXT_SECONDARY)
            end
        end
        if ch_switches[i] then
            ch_switches[i]:set_state(on)
        end
    end
    updating_switch = false
end

--[[
通道开关切换处理：发布翻转指令由 relay_ctrl 执行

@local
@function on_ch_switch_change
@param ch number 通道号（0~3）
@param state boolean 开关切换后的目标状态（true=接通）
]]
local function on_ch_switch_change(ch, state)
    if not exwin.is_active(win_id) then return end
    if updating_switch then return end
    log.info("relay_win", "通道" .. ch .. " 开关切换", state and "接通" or "断开")
    sys.publish("RELAY_SET_REQ", ch, "toggle")
end

-- 各通道开关回调（airui 组件回调必须为具名函数）
local function on_ch0_switch(state) on_ch_switch_change(0, state) end
local function on_ch1_switch(state) on_ch_switch_change(1, state) end
local function on_ch2_switch(state) on_ch_switch_change(2, state) end
local function on_ch3_switch(state) on_ch_switch_change(3, state) end

local switch_funcs = { on_ch0_switch, on_ch1_switch, on_ch2_switch, on_ch3_switch }

-- 全部接通
local function on_all_open_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("RELAY_SET_REQ", nil, "all_open")
end

-- 全部断开
local function on_all_close_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("RELAY_SET_REQ", nil, "all_close")
end

-- 回读状态
local function on_read_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("RELAY_SET_REQ", nil, "read")
end

--[[
创建继电器控制 UI

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "继电器控制 (485)", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 4 个通道，2×2 布局，每路一个滑动开关
    local card_w = 232
    local card_h = 68
    local gap_x = 6
    local gap_y = 6
    local start_x = 5
    local start_y = 5

    -- 创建期间屏蔽 on_change：部分 SDK 版本在创建/初始 set_state 时会派发一次 value_changed
    updating_switch = true

    for i = 1, CH_COUNT do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = start_x + col * (card_w + gap_x)
        local y = start_y + row * (card_h + gap_y)

        local card = airui.container({
            parent = content,
            x = x, y = y, w = card_w, h = card_h,
            color = T.COLOR_CARD, radius = T.CARD_RADIUS,
        })

        airui.label({
            parent = card,
            x = 12, y = 6, w = 100, h = 20,
            text = "通道 " .. (i - 1),
            font_size = T.FONT_CARD_TITLE, color = T.COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT,
        })

        ch_state_labels[i] = airui.label({
            parent = card,
            x = 12, y = 30, w = 100, h = 26,
            text = "未知",
            font_size = T.FONT_TITLE, color = T.COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT,
        })

        -- 单路滑动开关：点击切换该路通断
        ch_switches[i] = airui.switch({
            parent = card,
            x = card_w - 68, y = 19, w = 56, h = 30,
            checked = false,
            on_change = switch_funcs[i],
        })
    end

    -- 创建完成，恢复正常的下发逻辑
    updating_switch = false

    -- 底部批量操作按钮
    local btn_y = 156
    T.btn_success(content, 5, btn_y, 150, 32, "全部接通", on_all_open_click)
    T.btn_danger(content, 165, btn_y, 150, 32, "全部断开", on_all_close_click)
    T.btn_primary(content, 325, btn_y, 150, 32, "回读状态", on_read_click)
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
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
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    ch_state_labels = {}
    ch_switches = {}
    updating_switch = false
    sys.unsubscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
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

@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RELAY_WIN", open_handler)
