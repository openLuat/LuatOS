--[[
@module  rs485_win
@summary RS485 终端页面（8301出厂固件·业务模式）
@version 3.0
@date    2026.10.08
@author  江访

@usage
业务模式只保留 Port1（RS485-1 / UART1，隔离口）。
  8301 的 RS485-2（UART11，非隔离口）在业务模式下已被 relay_ctrl 用作
  Modbus RTU 主站（4 路继电器专用，见 relay_ctrl.lua 注释），
  不再作为通用串口终端开放，故本页移除 Port2，改为单口全宽布局，
  接收区更高、输入框与按钮更大（更易触摸）。

监听 RS485_DATA_RECEIVED 消息追加历史（最新数据置顶显示），
发布 RS485_SEND_REQUEST 发送。接收数据无论窗口是否激活都会缓存，
打开页面时展示最近数据。

视觉：ui_theme 深色玻璃态（单块端口面板：标题行 + 接收历史 + 输入框与发送按钮）。

=== v3.0 修复：退出后软键盘遗留 ===
现象：点开输入框弹出键盘后退出页面，键盘仍留在屏幕上，需再点一下屏幕才消失。
根因：
  1) 软键盘是挂在本页容器之外的独立组件，main_container:destroy() 不会连带销毁它；
  2) textarea 的 keyboard 参数在官方文档中的定位是「键盘样式」，
     输入框实际使用的键盘实例不一定等于外部创建并传入的那个，
     因此只销毁自己创建的对象未必命中屏幕上真正的键盘；
  3) 原 on_destroy 先销毁容器、后销毁键盘，此时 textarea 已失效，
     无法再通过 get_keyboard() 取到真实键盘。
修复：退出时「先清键盘、再释放容器」——此时 textarea 仍然有效，
      逐个输入框 get_keyboard() 取真实键盘并 hide + destroy，
      再销毁本模块创建的实例；全过程 pcall 包裹，任一步失败都不影响其余销毁流程。
      同时关闭 preview（预览框在部分 airui 版本下不会随键盘一起销毁）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local port1_history = {}
local input_area_port1
local history_label_port1
local kb = nil                 -- 软键盘实例（本页共用；退出时必须显式销毁）

-- 历史缓存上限（缓存 12 条，单口布局下显示最新 5 条）
local HISTORY_MAX  = 12
local HISTORY_SHOW = 5

-- 端口面板几何（内容区 464×210，单口全宽）
local BLOCK_H = 210

-- 本页 UI 存活性标志：只由 on_create / on_destroy 维护，点击回调据此准入
local ui_alive = false

--[[
获取软键盘单例

键盘是独立组件（parent 默认 airui.screen），不属于任何页面容器，
main_container:destroy() 不会连带销毁它。若模块不自行持有引用，
退出页面后键盘会残留在屏幕上，直到再次触摸屏幕触发 auto_hide 才消失。

@local
@function ensure_keyboard
@return userdata 键盘对象
]]
local function ensure_keyboard()
    if kb then return kb end
    kb = airui.keyboard({
        x = 0,
        y = 0,                 -- 0 = 键盘下边缘贴屏幕底部（官方语义），向上展开 h 像素
        w = theme.SCREEN_W,
        h = 90,
        mode = "text",
        preview = false,       -- 关闭预览框：部分 airui 版本下预览框不随键盘销毁
        auto_hide = true,
    })
    return kb
end

--[[
关闭并销毁软键盘（页面销毁时必须调用）

airui 的键盘不属于页面容器，且输入框实际绑定的键盘未必等于外部创建的那个。
因此这里做「双保险」，且必须在本页容器销毁之前调用（之后 textarea 已失效）：
  1) 通过输入框的 get_keyboard() 取到它实际使用的键盘并销毁；
  2) 再销毁本模块自己创建的实例（若与上一步是同一对象则跳过）。

@local
@function destroy_keyboard
]]
local function destroy_keyboard()
    local function kill(k)
        if not k then return end
        pcall(function() k:hide() end)      -- 先隐藏，避免销毁瞬间残留一帧
        pcall(function() k:destroy() end)
    end

    -- 1) 输入框实际绑定的键盘
    if input_area_port1 then
        local ok, k = pcall(function() return input_area_port1:get_keyboard() end)
        if ok and k and k ~= kb then kill(k) end
    end

    -- 2) 本模块创建的键盘
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
发送按钮点击

@local
@function on_send_click
]]
local function on_send_click()
    if not ui_alive then return end
    if not input_area_port1 then return end
    local data = input_area_port1:get_text()
    if data and #data > 0 then
        sys.publish("RS485_SEND_REQUEST", 1, data)
        input_area_port1:set_text("")
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
    -- 本页只展示 Port1（RS485-1/UART1）；Port2 在业务模式由继电器主站占用
    if port ~= 1 then return end
    local display = data_to_display(data)
    table.insert(port1_history, 1, display)   -- 最新数据置顶
    if #port1_history > HISTORY_MAX then
        table.remove(port1_history)
    end
    if history_label_port1 then
        history_label_port1:set_text(build_history_text(port1_history))
    end
end

--[[
创建端口面板(标题行 + 接收历史 + 输入框 + 发送按钮)

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
        x = 12, y = 8, w = w - 24, h = 19,
        text = title, px_size = 16, color = theme.C.t3,
    })

    -- 接收历史（最新置顶，最多 5 行）
    local history_label = theme.label(card, {
        x = 12, y = 30, w = w - 24, h = 96,
        text = "暂无数据", px_size = 16, color = theme.C.t1,
    })

    -- 输入框（含软键盘）：位置抬到键盘上方，避免被弹出的键盘遮挡
    local input_w = w - 12 * 2 - 100 - 8
    local input_area = theme.input(card, {
        x = 12, y = 138, w = input_w, h = 38,
        placeholder = "输入要发送的数据...",
        px_size = 16,
        keyboard = ensure_keyboard(),
    })

    -- 发送按钮
    theme.btn(card, {
        x = 12 + input_w + 8, y = 138, w = 100, h = 38,
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

    -- 单口：RS485-1（UART1，隔离口）
    history_label_port1, input_area_port1 = create_port_block(
        ctx.base, ctx.x, ctx.y, ctx.w, "RS485-1 | UART1", on_send_click)

    -- 若有历史缓存, 立即显示
    if #port1_history > 0 and history_label_port1 then
        history_label_port1:set_text(build_history_text(port1_history))
    end
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("rs485_win", "[UI-MARK] RS485 终端页 v3.0 已加载（单口 + 键盘显式销毁）")
    ui_alive = true
    create_ui()
    sys.subscribe("RS485_DATA_RECEIVED", on_rs485_data_received)
end

--[[
窗口销毁回调

⚠ 顺序要求：必须先销毁软键盘，再销毁页面容器。
  容器一旦销毁，textarea 随之失效，就再也拿不到它实际绑定的键盘实例了
  —— 这正是「退出后键盘遗留」的直接原因。

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
    history_label_port1 = nil
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
OPEN_RS485_WIN 消息处理器

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

sys.subscribe("OPEN_RS485_WIN", open_handler)
