--[[
@module  rs232_win
@summary RS232双端口终端页面，双端口同屏显示，无选项卡
@version 2.0.0
@date    2026.08.14
@author  合宙 Air8301
@usage
双端口(Port1=UART2, Port2=UART12)同屏上下排列，各自有接收历史、输入框和发送按钮。
监听 RS232_DATA_RECEIVED 消息追加历史(最新数据置顶显示)，发布 RS232_SEND_REQUEST 发送。
接收数据无论窗口是否激活都会缓存到历史，打开页面时展示最近数据。
]]

local win_id = nil
local main_container, content
local port1_history = {}
local port2_history = {}
local input_area_port1, input_area_port2
local history_label_port1, history_label_port2

-- 历史条数上限
local HISTORY_MAX = 8

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
Port1 发送按钮点击

@local
@function on_send_port1_click
]]
local function on_send_port1_click()
    if not exwin.is_active(win_id) then return end
    if not input_area_port1 then return end
    local data = input_area_port1:get_text()
    if data and #data > 0 then
        sys.publish("RS232_SEND_REQUEST", 1, data)
        input_area_port1:set_text("")
    end
end

--[[
Port2 发送按钮点击

@local
@function on_send_port2_click
]]
local function on_send_port2_click()
    if not exwin.is_active(win_id) then return end
    if not input_area_port2 then return end
    local data = input_area_port2:get_text()
    if data and #data > 0 then
        sys.publish("RS232_SEND_REQUEST", 2, data)
        input_area_port2:set_text("")
    end
end

--[[
将接收数据转为可显示字符串:
- 纯可打印ASCII直接显示
- 含二进制/不可打印字符时转十六进制, 避免渲染空白或乱码

@local
@function data_to_display
@param data string 原始数据
@return string 可显示字符串
]]
local function data_to_display(data)
    if not data or #data == 0 then return "" end
    local printable = true
    for i = 1, #data do
        local b = data:byte(i)
        if b < 32 or b > 126 then
            printable = false
            break
        end
    end
    if printable then
        return data
    end
    -- LuatOS string 扩展提供 toHex()
    local hex = data:toHex()
    if hex and #hex > 0 then
        return hex
    end
    return "(不可显示数据)"
end

--[[
接收RS232数据消息
数据始终入历史缓存(即使窗口未激活), 窗口存在时立即刷新label

@local
@function on_rs232_data_received
@param port number 端口号(1或2)
@param data string 接收到的数据
]]
local function on_rs232_data_received(port, data)
    local display = data_to_display(data)
    if port == 1 then
        -- 最新数据置顶
        table.insert(port1_history, 1, display)
        if #port1_history > HISTORY_MAX then
            table.remove(port1_history)
        end
        if history_label_port1 then
            history_label_port1:set_text(table.concat(port1_history, "\n"))
        end
    elseif port == 2 then
        table.insert(port2_history, 1, display)
        if #port2_history > HISTORY_MAX then
            table.remove(port2_history)
        end
        if history_label_port2 then
            history_label_port2:set_text(table.concat(port2_history, "\n"))
        end
    end
end

--[[
创建单个端口的UI块(接收历史+输入框+发送按钮)

@local
@function create_port_block
@param parent userdata 父容器
@param x number
@param y number
@param w number
@param h number
@param title string 端口标题
@param send_click function 发送按钮回调
@return history_label userdata 接收历史label
@return input_area userdata 输入框
]]
local function create_port_block(parent, x, y, w, h, title, send_click)
    -- 卡片容器
    local card = airui.container({
        parent = parent,
        x = x, y = y, w = w, h = h,
        color = T.COLOR_CARD,
        radius = T.CARD_RADIUS
    })

    -- 端口标题
    airui.label({
        parent = card,
        x = 8, y = 3, w = 220, h = 20,
        text = title,
        font_size = T.FONT_SMALL,
        color = T.COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 接收历史(最新数据置顶)
    local history_label = airui.label({
        parent = card,
        x = 8, y = 21, w = w - 16, h = 46,
        text = "暂无数据",
        font_size = T.FONT_CARD_TITLE,
        color = T.COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 输入框
    local input_area = airui.textarea({
        parent = card,
        x = 8, y = 70, w = w - 16 - 104, h = 30,
        placeholder = "输入要发送的数据...",
        font_size = T.FONT_SMALL,
        keyboard = airui.keyboard({
            x = 0,
            y = 0,
            w = T.SCREEN_W,
            h = 100,
            mode = "text",
            preview = true,
            auto_hide = true,
        })
    })

    -- 发送按钮
    T.btn_primary(card, w - 104, 70, 96, 30, "发送", send_click)

    return history_label, input_area
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    -- 顶部标题栏
    T.titlebar(main_container, "RS232", on_back_click)

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H,
        color = T.COLOR_BG
    })

    -- Port1 块 (UART2)
    history_label_port1, input_area_port1 = create_port_block(
        content, 5, 4, 470, 104,
        "Port1 (UART2)", on_send_port1_click)

    -- Port2 块 (UART12)
    history_label_port2, input_area_port2 = create_port_block(
        content, 5, 112, 470, 104,
        "Port2 (UART12)", on_send_port2_click)

    -- 若有历史缓存, 立即显示
    if #port1_history > 0 and history_label_port1 then
        history_label_port1:set_text(table.concat(port1_history, "\n"))
    end
    if #port2_history > 0 and history_label_port2 then
        history_label_port2:set_text(table.concat(port2_history, "\n"))
    end
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("RS232_DATA_RECEIVED", on_rs232_data_received)
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
    input_area_port1 = nil
    input_area_port2 = nil
    history_label_port1 = nil
    history_label_port2 = nil
    sys.unsubscribe("RS232_DATA_RECEIVED", on_rs232_data_received)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    -- 刷新历史显示
    if history_label_port1 and #port1_history > 0 then
        history_label_port1:set_text(table.concat(port1_history, "\n"))
    end
    if history_label_port2 and #port2_history > 0 then
        history_label_port2:set_text(table.concat(port2_history, "\n"))
    end
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus()
    -- 不需要特殊处理
end

--[[
OPEN_RS232_WIN 消息处理器

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

sys.subscribe("OPEN_RS232_WIN", open_handler)
