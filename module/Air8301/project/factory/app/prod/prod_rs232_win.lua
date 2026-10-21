--[[
@module  prod_rs232_win
@summary RS232双端口终端页面（产测模式），双端口同屏显示，无选项卡
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_RS232_WIN，避免与业务页面冲突

@usage
双端口(Port1=UART2, Port2=UART12)同屏上下排列，各自有接收历史、输入框和发送按钮。
监听 RS232_DATA_RECEIVED 消息追加历史(最新数据置顶显示)，发布 RS232_SEND_REQUEST 发送（由 prod_rs232_app 处理）。
产测用途：配合 U232_TEST,1/2# 观察 TX-RX 短接自回环数据。

视觉：ui_theme 深色玻璃态（两块端口面板，面板内含标题行、接收历史、输入框与发送按钮）。

=== v3.0 修复：退出后软键盘遗留（本页是变更 9 的遗漏项） ===
现象：点开输入框弹出键盘后退出页面，键盘残留在屏幕上，需再点一下屏幕才消失。
根因（三重叠加）：
  1) 旧实现在 create_port_block 内**内联** airui.keyboard({...})，而该函数被调用两次
     → 一次进入页面就创建了 **2 个键盘实例**，且模块未持有任何引用，无从销毁；
  2) 键盘是挂在本页容器之外的独立组件，main_container:destroy() 不会连带销毁它；
  3) 旧 on_destroy 先销毁容器、后才（其实完全没有）处理键盘，
     此时 textarea 已失效，无法再通过 get_keyboard() 取到真实键盘。
修复：
  1) 改为模块级单例 ensure_keyboard()：两个端口共用一个键盘（不再建 2 个）；
  2) destroy_keyboard() 做双保险 —— 先取输入框 get_keyboard() 的实际键盘销毁，
     再销毁本模块创建的实例；全部 pcall 包裹；
  3) on_destroy 改为「先清键盘、再释放容器」（顺序是关键）；
  4) on_lose_focus 收起键盘；关闭 preview（部分 airui 版本下预览框不随键盘销毁）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local port1_history = {}
local port2_history = {}
local input_area_port1, input_area_port2
local history_label_port1, history_label_port2
local kb = nil                 -- 软键盘实例（全页共用；退出时必须显式销毁）

-- 历史缓存上限（缓存 8 条，受面板高度限制仅显示最新 2 条）
local HISTORY_MAX  = 8
local HISTORY_SHOW = 2

-- 端口面板几何（内容区 464×210：102 + 6 + 102 = 210）
local BLOCK_H   = 102
local BLOCK_GAP = 6

-- 本页 UI 存活性标志：只由 on_create / on_destroy 维护，点击回调据此准入
local ui_alive = false

--[[
获取软键盘单例（两个端口共用一个，避免重复创建与无法销毁）

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
    if not ui_alive then return end
    exwin.close(win_id)
end

--[[
Port1 发送按钮点击

@local
@function on_send_port1_click
]]
local function on_send_port1_click()
    if not ui_alive then return end
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
    if not ui_alive then return end
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

⚠ 输入框的键盘使用模块级单例 ensure_keyboard()，切勿在此内联创建，
   否则每次调用都会新建一个键盘且无人销毁 —— 这正是旧版键盘遗留的根源。

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

    -- 输入框（共用单例软键盘）
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
    local ctx = theme.page({ title = "RS232", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- Port1 面板 (UART2)
    history_label_port1, input_area_port1 = create_port_block(
        ctx.base, ctx.x, ctx.y, ctx.w, "Port1 | UART2", on_send_port1_click)

    -- Port2 面板 (UART12)
    history_label_port2, input_area_port2 = create_port_block(
        ctx.base, ctx.x, ctx.y + BLOCK_H + BLOCK_GAP, ctx.w,
        "Port2 | UART12", on_send_port2_click)

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
    log.info("prod_rs232_win", "[UI-MARK] 产测 RS232 页 v3.0 已加载（键盘单例 + 显式销毁）")
    ui_alive = true
    create_ui()
    sys.subscribe("RS232_DATA_RECEIVED", on_rs232_data_received)
end

--[[
窗口销毁回调

⚠ 顺序要求：必须先销毁软键盘，再销毁页面容器。
  容器一旦销毁，textarea 随之失效，就再也拿不到它实际绑定的键盘实例。

@local
@function on_destroy
]]
local function on_destroy()
    ui_alive = false
    -- 1) 先清软键盘（此时 textarea 仍有效）
    destroy_keyboard()
    -- 2) 再释放页面组件
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
OPEN_PROD_RS232_WIN 消息处理器

单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）

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

sys.subscribe("OPEN_PROD_RS232_WIN", open_handler)
