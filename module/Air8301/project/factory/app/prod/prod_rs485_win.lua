--[[
@module  prod_rs485_win
@summary RS485双端口终端页面（产测模式），双端口同屏显示，无选项卡
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_RS485_WIN，避免与业务页面冲突

@usage
双端口(Port1=UART1, Port2=UART11)同屏上下排列，各自有接收历史、输入框和发送按钮。
监听 RS485_DATA_RECEIVED 消息追加历史(最新数据置顶显示)，发布 RS485_SEND_REQUEST 发送（由 prod_rs485_app 处理）。
产测用途：配合 U485_TEST 观察 1 号发 2 号收的原始数据，也可手动发数据验证。

视觉：ui_theme 深色玻璃态（两块端口面板，面板内含标题行、接收历史、输入框与发送按钮）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local port1_history = {}
local port2_history = {}
local input_area_port1, input_area_port2
local history_label_port1, history_label_port2
local kb = nil                 -- 软键盘实例（全页共用；旧实现两个端口各建一个且从不销毁）

-- 历史缓存上限（缓存 8 条，受面板高度限制仅显示最新 2 条）
local HISTORY_MAX  = 8
local HISTORY_SHOW = 2

-- 端口面板几何（内容区 464×210：102 + 6 + 102 = 210）
local BLOCK_H   = 102
local BLOCK_GAP = 6

--[[
获取软键盘单例

键盘是独立组件（parent 默认 airui.screen），不属于任何页面容器，
main_container:destroy() 不会连带销毁它。若模块不自行持有引用，
退出页面后键盘（含 preview 预览框）会残留在屏幕上，直到再次触摸屏幕
触发 auto_hide 才消失——这正是「退出应用后键盘遗留」的原因。

@local
@function ensure_keyboard
@return userdata 键盘对象
]]
local function ensure_keyboard()
    if kb then return kb end
    kb = airui.keyboard({
        x = 0, y = 0,          -- 0 = 键盘下边缘贴屏幕底部（官方语义），向上展开 h 像素
        w = theme.SCREEN_W, h = 90,
        mode = "text",
        preview = false,       -- 关闭预览框：部分 airui 版本下预览框不随键盘一起销毁
        auto_hide = true,
    })
    return kb
end

--[[
隐藏并销毁软键盘（页面销毁时必须调用，且必须在容器销毁之前）

airui 的键盘不属于页面容器；且 textarea 实际绑定的键盘未必等于外部创建的那个
（官方文档把该参数定性为「键盘样式」）。因此做「双保险」：
  1) 通过输入框 get_keyboard() 取真实键盘并销毁；
  2) 再销毁本模块创建的实例（同一对象则跳过）。
全部 pcall 包裹，任一步失败不影响页面其余销毁流程。

@local
@function destroy_keyboard
]]
local function destroy_keyboard()
    local function kill(k)
        if not k then return end
        pcall(function() k:hide() end)      -- 先隐藏，避免销毁瞬间残留一帧
        pcall(function() k:destroy() end)
    end

    local tas = { input_area_port1, input_area_port2 }
    for i = 1, #tas do
        local ta = tas[i]
        if ta then
            local ok, k = pcall(function() return ta:get_keyboard() end)
            if ok and k and k ~= kb then kill(k) end
        end
    end

    kill(kb)
    kb = nil
end

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
        sys.publish("RS485_SEND_REQUEST", 1, data)
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
        sys.publish("RS485_SEND_REQUEST", 2, data)
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
把历史缓存拼成显示文本（只取最新 HISTORY_SHOW 条）

@local
@function build_history_text
@param list table 历史缓存
@return string 显示文本
]]
local function build_history_text(list)
    local n = #list
    if n == 0 then return "暂无数据" end
    local lines = {}
    local show = n < HISTORY_SHOW and n or HISTORY_SHOW
    for i = 1, show do
        lines[i] = list[i]
    end
    return table.concat(lines, "\n")
end

--[[
接收RS485数据消息
数据始终入历史缓存(即使窗口未激活), 窗口存在时立即刷新label

@local
@function on_rs485_data_received
@param port number 端口号(1或2)
@param data string 接收到的数据
]]
local function on_rs485_data_received(port, data)
    local display = data_to_display(data)
    if port == 1 then
        -- 最新数据置顶
        table.insert(port1_history, 1, display)
        if #port1_history > HISTORY_MAX then
            table.remove(port1_history)
        end
        if history_label_port1 then
            history_label_port1:set_text(build_history_text(port1_history))
        end
    elseif port == 2 then
        table.insert(port2_history, 1, display)
        if #port2_history > HISTORY_MAX then
            table.remove(port2_history)
        end
        if history_label_port2 then
            history_label_port2:set_text(build_history_text(port2_history))
        end
    end
end

--[[
创建单个端口的面板(标题行 + 接收历史 + 输入框 + 发送按钮)

@local
@function create_port_block
@param parent userdata 父容器
@param x number X 坐标
@param y number Y 坐标
@param w number 宽度
@param title string 端口标题
@param send_click function 发送按钮回调
@return history_label userdata 接收历史label
@return input_area userdata 输入框
]]
local function create_port_block(parent, x, y, w, title, send_click)
    local card = theme.card(parent, {
        x = x, y = y, w = w, h = BLOCK_H,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft,
    })

    -- 端口标题行
    theme.label(card, {
        x = 12, y = 5, w = w - 24, h = 19,
        text = title, px_size = 16, color = theme.C.t3,
    })

    -- 接收历史（最新置顶）
    local history_label = theme.label(card, {
        x = 12, y = 27, w = w - 24, h = 38,
        text = "暂无数据", px_size = 16, color = theme.C.t1,
    })

    -- 输入框（含软键盘）
    local input_w = w - 12 * 2 - 96 - 8
    local input_area = theme.input(card, {
        x = 12, y = 67, w = input_w, h = 30,
        placeholder = "输入要发送的数据...",
        px_size = 16,
        keyboard = ensure_keyboard(),
    })

    -- 发送按钮
    theme.btn(card, {
        x = 12 + input_w + 8, y = 67, w = 96, h = 30,
        text = "发送", on_click = send_click,
    })

    return history_label, input_area
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "RS485", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- Port1 面板 (UART1)
    history_label_port1, input_area_port1 = create_port_block(
        ctx.base, ctx.x, ctx.y, ctx.w, "Port1 | UART1", on_send_port1_click)

    -- Port2 面板 (UART11)
    history_label_port2, input_area_port2 = create_port_block(
        ctx.base, ctx.x, ctx.y + BLOCK_H + BLOCK_GAP, ctx.w,
        "Port2 | UART11", on_send_port2_click)

    -- 若有历史缓存, 立即显示
    if #port1_history > 0 and history_label_port1 then
        history_label_port1:set_text(build_history_text(port1_history))
    end
    if #port2_history > 0 and history_label_port2 then
        history_label_port2:set_text(build_history_text(port2_history))
    end
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("RS485_DATA_RECEIVED", on_rs485_data_received)
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    -- ⚠ 顺序要求：先清软键盘（此时 textarea 仍有效），再释放页面容器。
    --   容器一旦销毁，textarea 随之失效，就再也拿不到它实际绑定的键盘实例。
    destroy_keyboard()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    input_area_port1 = nil
    input_area_port2 = nil
    history_label_port1 = nil
    history_label_port2 = nil
    sys.unsubscribe("RS485_DATA_RECEIVED", on_rs485_data_received)
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
        history_label_port1:set_text(build_history_text(port1_history))
    end
    if history_label_port2 and #port2_history > 0 then
        history_label_port2:set_text(build_history_text(port2_history))
    end
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus()
    -- 失焦即收起键盘，避免键盘跨页面残留
    if kb then pcall(function() kb:hide() end) end
end

--[[
OPEN_PROD_RS485_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    -- 单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）
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

sys.subscribe("OPEN_PROD_RS485_WIN", open_handler)
