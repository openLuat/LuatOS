--[[
@module  mqtt_client_win
@summary MQTT 多客户端管理器 主窗口模块
@version 1.0.0
@date    2026.05.19
@usage
本模块为 MQTT 客户端管理器的主窗口，负责 UI 渲染与用户交互。
订阅 "OPEN_MQTT_CLIENT_WIN" 事件打开窗口。
]]

-- 加载业务逻辑模块（mqtt_client_app 负责 MQTT 连接管理、发布队列、接收分发）
require "mqtt_client_app"

-- ========================================
-- 所有参数放在文件开头
-- ========================================

-- 颜色常量，与 HTML UI 设计稿保持一致
local COLOR_BG = 0xE8E9EB            -- 页面整体背景色
local COLOR_TITLE_BG = 0x1A3A5C      -- 标题栏背景色（深蓝）
local COLOR_TAB_BAR_BG = 0xE8ECF1    -- Tab 栏背景色
local COLOR_CARD_BG = 0xFFFFFF       -- 卡片背景色（白色）
local COLOR_TEXT_PRIMARY = 0x333333  -- 主要文字颜色
local COLOR_TEXT_SECONDARY = 0x666666 -- 次要文字颜色
local COLOR_TEXT_WHITE = 0xFFFFFF    -- 白色文字
local COLOR_TEXT_GREEN = 0x4CAF50    -- 绿色文字
local COLOR_BTN_GREEN = 0x4CAF50     -- 连接/订阅按钮 绿色
local COLOR_BTN_RED = 0xFF5722       -- 断开/删除按钮 红色
local COLOR_BTN_BLUE = 0x2563EB      -- 发布/发送按钮 蓝色
local COLOR_BTN_ORANGE = 0xED8936    -- 订阅按钮 橙色
local COLOR_BTN_GRAY = 0x9E9E9E      -- 取消按钮 灰色
local COLOR_LOG_BG = 0x1E1E1E        -- 日志容器背景色（终端暗色）
local COLOR_STATUS_DISCONNECTED = 0x9E9E9E  -- 未连接状态圆点颜色
local COLOR_STATUS_CONNECTED = 0x4CAF50     -- 已连接状态圆点颜色
local COLOR_TAB_ACTIVE_BG = 0xFFFFFF         -- Tab 激活态背景色
local COLOR_TAB_INACTIVE_BG = 0xD0D8E0       -- Tab 未激活态背景色
local COLOR_TAB_ACTIVE_TEXT = 0x1A73E8       -- Tab 激活态文字颜色（蓝色）
local COLOR_TAB_INACTIVE_TEXT = 0x888888      -- Tab 未激活态文字颜色（灰色）
local COLOR_TAB_DELETE_BTN = 0xFF5252        -- Tab 删除按钮颜色

-- 布局常量
local SCREEN_W = 320                  -- 屏幕宽度
local SCREEN_H = 480                  -- 屏幕高度
local TITLE_BAR_H = 44                -- 标题栏高度
local TAB_BAR_H = 34                  -- Tab 栏高度
local TAB_BAR_Y = 44                  -- Tab 栏起始 Y
local CONTENT_Y = 78                  -- 内容区起始 Y（44 + 34）
local CONTENT_H = 402                 -- 内容区高度（480 - 78）
local CARD_MARGIN_X = 10              -- 卡片水平边距
local CARD_W = 300                    -- 卡片宽度
local FORM_LABEL_W = 50               -- 表单标签宽度
local FORM_INPUT_X = 50               -- 表单输入框起始 X
local FORM_INPUT_W = 230              -- 表单输入框宽度
local FORM_ROW_H = 35                 -- 表单行高度
local FORM_INPUT_H = 25               -- 输入框高度
local CARD_GAP = 5                    -- 卡片垂直间距
local CARD_PADDING = 5               -- 卡片内边距
local FORM_ROW_GAP = 4               -- 表单行间距
local MAX_CLIENTS = 6                 -- 最多 6 个客户端
local MAX_LOGS = 50                   -- 单个客户端最多 50 条日志
local LOG_CARD_H = 145                -- 日志卡片高度
local LOG_ROW_H = 18                  -- 每行日志高度

-- ========================================
-- 模块级变量
-- ========================================

local win_id = nil                    -- 窗口 ID，exwin.open() 返回
local main_container = nil            -- 主容器（根容器，parent=airui.screen）
local title_bar = nil                 -- 标题栏容器
local tab_bar = nil                   -- Tab 栏容器
local tab_containers = {}            -- Tab 容器数组，tab_containers[i] = tab_container
local btn_new_client = nil            -- 标题栏新建按钮
local content_area = nil              -- 内容区容器（滚动容器）
local shared_keyboard = nil           -- 共享键盘实例
local log_body = nil                  -- 日志内容容器（支持滚动）
local log_row_labels = {}            -- 日志行 label 数组
local log_empty_label = nil          -- 空状态 label
local log_card_container = nil        -- 日志卡片容器

-- ========================================
-- 数据模型
-- ========================================

local clients = {}                    -- 客户端数据数组，clients[i] 为第 i 个客户端配置表
local active_client_index = 1         -- 当前激活的客户端索引（1-based）

-- ========================================
-- 配置卡片组件引用
-- ========================================

local config_card_container = nil     -- 配置卡片外层容器（白色圆角卡片）
local config_card_title = nil         -- 配置卡片标题栏
local config_card_body = nil          -- 配置卡片内容容器（折叠目标）
local config_collapsed = false        -- 配置卡片折叠状态
local config_toggle_label = nil       -- 折叠箭头 label（∨/>）
local config_status_dot = nil         -- 连接状态圆点 label
local config_status_text = nil        -- 连接状态文本 label

-- 配置卡片表单组件引用
local input_host = nil                -- 服务器地址输入框
local input_port = nil                -- 端口输入框
local input_client_id = nil           -- 客户端 ID 输入框
local input_user = nil                -- 用户名输入框
local input_password = nil            -- 密码输入框
local input_will_topic = nil          -- 遗嘱主题输入框
local input_will_payload = nil        -- 遗嘱消息输入框
local input_keepalive = nil           -- 心跳间隔输入框
local dropdown_will_qos = nil         -- 遗嘱 QoS 下拉框
local switch_will_retain = nil        -- 遗嘱 Retain 开关
local btn_connect = nil               -- 连接按钮
local btn_disconnect = nil            -- 断开按钮

-- ========================================
-- 发布卡片组件引用
-- ========================================
local publish_card_container = nil    -- 发布卡片外层容器
local input_pub_topic = nil           -- 发布主题输入框
local input_pub_payload = nil         -- 发布消息输入框
local dropdown_pub_qos = nil          -- 发布 QoS 下拉框
local btn_send = nil                  -- 发送按钮

-- ========================================
-- 订阅卡片组件引用
-- ========================================
local subscribe_card_container = nil   -- 订阅卡片外层容器
local input_sub_topic = nil           -- 订阅主题输入框
local dropdown_sub_qos = nil          -- 订阅 QoS 下拉框
local btn_subscribe = nil             -- 订阅按钮

-- ========================================
-- 已订阅列表卡片组件引用
-- ========================================
local sub_list_card_container = nil   -- 已订阅列表卡片外层容器
local sub_list_card_body = nil        -- 已订阅列表卡片内容容器
local sub_list_rows = {}             -- 已订阅列表行组件数组

-- 前置声明函数（解决先调用后定义问题）
local switch_client = nil
local delete_client = nil

-- ========================================
-- 窗口关闭处理
-- ========================================

-- 返回按钮点击：关闭当前窗口，返回主菜单
local function go_back()
    exwin.close(win_id)
end

-- ========================================
-- 数据模型操作
-- ========================================

-- 初始化默认客户端（索引从 1 开始）
local function init_default_client()
    clients[1] = {
        id = 1,
        connected = false,
        host = "lbsmqtt.airm2m.com",
        port = "1884",
        client_id = "",
        user = "",
        password = "",
        will_topic = "",
        will_payload = "",
        will_qos = 0,
        will_retain = false,
        pub_topic = "",                  -- 发布主题
        pub_payload = "",                -- 发布消息
        pub_qos = 0,                    -- 发布 QoS
        subscriptions = {},               -- 已订阅主题列表：{topic, qos}
        logs = {},                        -- 通讯日志缓冲：{type, msg}
    }
    active_client_index = 1
    -- 同步到 app 模块
    sys.publish("MQTT_NEW_CLIENT", {
        index = 1,
        host = clients[1].host,
        port = clients[1].port,
        client_id = clients[1].client_id,
        user = clients[1].user,
        password = clients[1].password,
        will_topic = clients[1].will_topic,
        will_payload = clients[1].will_payload,
        will_qos = clients[1].will_qos,
        will_retain = clients[1].will_retain
    })
end

-- ========================================
-- 重建已订阅列表（动态创建/销毁行组件）
-- ========================================

-- 销毁已订阅列表全部行
local function destroy_sub_list_rows()
    for i = 1, #sub_list_rows do
        if sub_list_rows[i] then
            sub_list_rows[i]:destroy()
            sub_list_rows[i] = nil
        end
    end
end

-- 重建已订阅列表
local function refresh_sub_list()
    destroy_sub_list_rows()
    local c = clients[active_client_index]
    if not c or not c.subscriptions then return end

    local subs = c.subscriptions
    if #subs == 0 then
        -- 空状态提示
        airui.label({
            parent = sub_list_card_body,
            x = 0,
            y = 5,
            w = CARD_W,
            h = 20,
            text = "暂无订阅",
            font_size = 11,
            color = COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_CENTER
        })
        return
    end

    local row_y = 5
    for i = 1, #subs do
        local sub = subs[i]
        local row_h = 22

        -- 行背景容器（用于分割线）
        local row_container = airui.container({
            parent = sub_list_card_body,
            x = 0,
            y = row_y,
            w = CARD_W,
            h = row_h,
            color = COLOR_CARD_BG
        })

        -- 订阅主题文字
        airui.label({
            parent = row_container,
            x = 8,
            y = 3,
            w = 150,
            h = 16,
            text = sub.topic or "",
            font_size = 11,
            color = 0x2B6CB0,
            align = airui.TEXT_ALIGN_LEFT
        })

        -- QoS 徽章
        airui.label({
            parent = row_container,
            x = 250,
            y = 3,
            w = 28,
            h = 16,
            text = "Q" .. tostring(sub.qos or 0),
            font_size = 10,
            color = COLOR_TEXT_GREEN,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 删除按钮
        airui.label({
            parent = row_container,
            x = CARD_W - 30,
            y = 1,
            w = 20,
            h = 20,
            text = "×",
            font_size = 14,
            color = COLOR_BTN_RED,
            align = airui.TEXT_ALIGN_CENTER,
            on_click = function()
                -- 发布 MQTT 取消订阅事件
                sys.publish("MQTT_UNSUBSCRIBE", {
                    index = active_client_index,
                    topic = sub.topic
                })
            end
        })

        sub_list_rows[i] = row_container
        row_y = row_y + row_h + 2
    end
end

-- ========================================
-- 通讯日志
-- ========================================

-- 销毁所有日志行
local function destroy_log_rows()
    for i = 1, #log_row_labels do
        if log_row_labels[i] then
            log_row_labels[i]:destroy()
            log_row_labels[i] = nil
        end
    end
    -- 销毁空状态 label
    if log_empty_label then
        log_empty_label:destroy()
        log_empty_label = nil
    end
end

local function refresh_log_content()
    if not log_body then return end
    local c = clients[active_client_index]
    if not c then return end

    -- 销毁旧行
    destroy_log_rows()

    local logs = c.logs or {}
    if #logs == 0 then
        -- 空状态提示
        log_empty_label = airui.label({
            parent = log_body,
            x = 0,
            y = 0,
            w = CARD_W - 10,
            h = LOG_ROW_H,
            text = "暂无日志",
            font_size = 11,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
        return
    end

    -- 创建每行日志
    local row_y = 5
    for i = 1, #logs do
        local entry = logs[i]
        -- 日志格式：[类型] 消息
        local prefix = "[SYS]"
        local text_color = 0x888888  -- 灰色（system）
        if entry.type == "send" then
            prefix = "[SEND]"
            text_color = 0x00FF00    -- 绿色
        elseif entry.type == "receive" then
            prefix = "[RCVD]"
            text_color = 0x00AAFF    -- 蓝色
        elseif entry.type == "error" then
            prefix = "[ERR]"
            text_color = 0xFF4444    -- 红色
        end

        local full_text = prefix .. " " .. entry.msg
        -- 估算文本需要几行（font_size=11，约 8px/字符，280px 宽约 35 字符/行）
        local chars_per_line = 35
        local lines = math.ceil(#full_text / chars_per_line)
        local row_h = math.max(LOG_ROW_H, lines * 16)  -- 至少一行高，每行 16px

        log_row_labels[i] = airui.label({
            parent = log_body,
            x = 5,
            y = row_y,
            w = CARD_W - 20,
            h = row_h,
            text = full_text,
            font_size = 11,
            color = text_color,
            align = airui.TEXT_ALIGN_LEFT
        })

        row_y = row_y + row_h + 2  -- 实际行高 + 行间距
    end
end

-- 添加日志
-- @param msg string 日志消息
-- @param log_type string 日志类型：send/receive/error/system（默认 system）
local function add_log(msg, log_type)
    local c = clients[active_client_index]
    if not c then return end

    -- 初始化日志数组
    if not c.logs then
        c.logs = {}
    end

    -- 添加日志条目
    table.insert(c.logs, {
        msg = msg,
        type = log_type or "system"
    })

    -- 限制日志数量
    while #c.logs > MAX_LOGS do
        table.remove(c.logs, 1)
    end

    -- 更新显示
    refresh_log_content()
end

-- 清空日志
local function clear_log()
    local c = clients[active_client_index]
    if not c then return end
    c.logs = {}
    refresh_log_content()
end

-- 创建日志卡片
local function create_log_card(parent, y_offset)
    log_card_container = airui.container({
        parent = parent,
        x = CARD_MARGIN_X,
        y = y_offset,
        w = CARD_W,
        h = LOG_CARD_H,
        color = COLOR_CARD_BG,
        radius = 8
    })

    -- 标题栏
    airui.label({
        parent = log_card_container,
        x = 10,
        y = 4,
        w = CARD_W - 80,
        h = 20,
        text = "通讯日志",
        font_size = 14,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 清除按钮
    airui.button({
        parent = log_card_container,
        x = CARD_W - 70,
        y = 2,
        w = 60,
        h = 24,
        text = "清除",
        font_size = 12,
        style = {
            bg_color = COLOR_BTN_RED,
            border_color = COLOR_BTN_RED,
            text_color = COLOR_TEXT_WHITE,
            radius = 4,
            border_width = 0
        },
        on_click = function()
            clear_log()
        end
    })

    -- 日志内容区（支持滚动）
    log_body = airui.container({
        parent = log_card_container,
        x = 0,
        y = 28,
        w = CARD_W,
        h = LOG_CARD_H - 28,
        color = 0x1A1A1A  -- 深色背景
    })

    -- 初始显示日志
    refresh_log_content()
end

-- ========================================
-- 连接状态 UI 更新
-- ========================================

-- 根据连接状态更新圆点颜色和状态文本
local function update_status_ui(connected)
    if not config_status_dot or not config_status_text then return end
    if connected then
        config_status_dot:set_text("●")
        config_status_dot:set_color(COLOR_STATUS_CONNECTED)
        config_status_text:set_text("已连接")
        config_status_text:set_color(COLOR_STATUS_CONNECTED)
        -- 已连接：连接按钮置灰，断开按钮可用
        if btn_connect then btn_connect:set_disabled(true) end
        if btn_disconnect then btn_disconnect:set_disabled(false) end
    else
        config_status_dot:set_text("●")
        config_status_dot:set_color(COLOR_STATUS_DISCONNECTED)
        config_status_text:set_text("未连接")
        config_status_text:set_color(COLOR_STATUS_DISCONNECTED)
        -- 未连接：连接按钮可用，断开按钮置灰
        if btn_connect then btn_connect:set_disabled(false) end
        if btn_disconnect then btn_disconnect:set_disabled(true) end
    end
end

-- 将当前激活客户端的配置写入 UI 表单控件
-- 阶段 3 实现 Tab 切换后扩展为 load_client_to_form(index)
local function load_client_to_form()
    local c = clients[active_client_index]
    if not c then return end

    if input_host then input_host:set_text(c.host or "") end
    if input_port then input_port:set_text(tostring(c.port or "")) end
    if input_client_id then input_client_id:set_text(c.client_id or "") end
    if input_user then input_user:set_text(c.user or "") end
    if input_password then input_password:set_text(c.password or "") end
    if input_will_topic then input_will_topic:set_text(c.will_topic or "") end
    if input_will_payload then input_will_payload:set_text(c.will_payload or "") end
    if dropdown_will_qos then dropdown_will_qos:set_selected(c.will_qos or 0) end
    if switch_will_retain then
        if (c.will_retain) then
            switch_will_retain:set_state(true)
        else
            switch_will_retain:set_state(false)
        end
    end
    if input_keepalive then input_keepalive:set_text(c.keepalive or "240") end
    -- 发布区数据
    if input_pub_topic then input_pub_topic:set_text(c.pub_topic or "") end
    if input_pub_payload then input_pub_payload:set_text(c.pub_payload or "") end
    if dropdown_pub_qos then dropdown_pub_qos:set_selected(c.pub_qos or 0) end
    -- 订阅区数据
    if input_sub_topic then input_sub_topic:set_text("") end
    if dropdown_sub_qos then dropdown_sub_qos:set_selected(0) end
    update_status_ui(c.connected)
    -- 重建已订阅列表
    refresh_sub_list()
    -- 刷新日志显示
    refresh_log_content()
end

-- 从 UI 表单控件读取数据，保存到当前激活客户端
local function save_form_to_client()
    local c = clients[active_client_index]
    if not c then return end

    if input_host then c.host = input_host:get_text() or "" end
    if input_port then c.port = input_port:get_text() or "1884" end
    if input_client_id then c.client_id = input_client_id:get_text() or "" end
    if input_user then c.user = input_user:get_text() or "" end
    if input_password then c.password = input_password:get_text() or "" end
    if input_will_topic then c.will_topic = input_will_topic:get_text() or "" end
    if input_will_payload then c.will_payload = input_will_payload:get_text() or "" end
    if dropdown_will_qos then c.will_qos = dropdown_will_qos:get_selected() or 0 end
    if switch_will_retain then c.will_retain = switch_will_retain:get_state() or false end
    if input_keepalive then c.keepalive = input_keepalive:get_text() or "240" end
    -- 发布区数据
    if input_pub_topic then c.pub_topic = input_pub_topic:get_text() or "" end
    if input_pub_payload then c.pub_payload = input_pub_payload:get_text() or "" end
    if dropdown_pub_qos then c.pub_qos = dropdown_pub_qos:get_selected() or 0 end
end

-- ========================================
-- 配置卡片折叠/展开
-- ========================================

-- 重置所有卡片到原始位置（切换客户端时调用）
local function reset_card_positions()
    -- 固定 X 坐标为 CARD_MARGIN_X，与创建时一致
    local fixed_x = CARD_MARGIN_X

    -- 如果配置卡片处于折叠状态，先展开
    if config_collapsed and config_card_body then
        config_card_body:open()
        if config_toggle_label then config_toggle_label:set_text("∨") end
        config_collapsed = false
    end

    -- 计算各卡片原始位置（与 create_content_area 中一致）
    -- 配置卡片 y=8+h=400 → 底部 y=408，间距 5 → 发布卡片 y=413
    local publish_y = 413
    if publish_card_container then
        publish_card_container:set_pos(fixed_x, publish_y)
    end

    -- 订阅卡片原始 y=541
    local subscribe_y = 541
    if subscribe_card_container then
        subscribe_card_container:set_pos(fixed_x, subscribe_y)
    end

    -- 已订阅列表原始 y=642
    local sub_list_y = 642
    if sub_list_card_container then
        sub_list_card_container:set_pos(fixed_x, sub_list_y)
    end

    -- 日志卡片原始 y=800
    local log_y = 800
    if log_card_container then
        log_card_container:set_pos(fixed_x, log_y)
    end
end

local function toggle_config_card()
    if not config_card_body then return end
    config_collapsed = not config_collapsed

    -- 固定 X 坐标
    local fixed_x = CARD_MARGIN_X
    -- 卡片展开状态下的原始 Y 坐标
    local publish_y = 413
    local subscribe_y = 541
    local sub_list_y = 642
    local log_y = 800  -- 日志卡片原始 Y
    -- 配置卡片折叠后，其他卡片的起始 Y 坐标
    local collapsed_start_y = 48

    if config_collapsed then
        -- 折叠：隐藏内容区，其他卡片上移到折叠位置
        config_card_body:hide()
        if config_toggle_label then config_toggle_label:set_text(">") end

        -- 折叠后其他卡片的 Y 坐标
        if publish_card_container then
            publish_card_container:set_pos(fixed_x, collapsed_start_y)
        end
        if subscribe_card_container then
            subscribe_card_container:set_pos(fixed_x, collapsed_start_y + 115 + 13)
        end
        if sub_list_card_container then
            sub_list_card_container:set_pos(fixed_x, collapsed_start_y + 115 + 13 + 88 + 13)
        end
        -- 日志卡片折叠后位置
        if log_card_container then
            log_card_container:set_pos(fixed_x, collapsed_start_y + 115 + 13 + 88 + 13 + 145 + 13)
        end
    else
        -- 展开：显示内容区，其他卡片下移回原位
        config_card_body:open()
        if config_toggle_label then config_toggle_label:set_text("∨") end
        if publish_card_container then
            publish_card_container:set_pos(fixed_x, publish_y)
        end
        if subscribe_card_container then
            subscribe_card_container:set_pos(fixed_x, subscribe_y)
        end
        if sub_list_card_container then
            sub_list_card_container:set_pos(fixed_x, sub_list_y)
        end
        -- 日志卡片回到原位
        if log_card_container then
            log_card_container:set_pos(fixed_x, log_y)
        end
    end
end

-- ========================================
-- Tab 容器销毁（切换/删除前调用）
-- ========================================

local function destroy_tabs()
    for i = 1, MAX_CLIENTS do
        if tab_containers[i] then
            tab_containers[i]:destroy()
            tab_containers[i] = nil
        end
    end
end

-- ========================================
-- Tab 栏渲染（动态创建客户端 Tab）
-- ========================================

-- 创建单个 Tab 组件
local function create_single_tab(idx)
    local c = clients[idx]
    if not c then return end

    -- 计算逻辑顺序（前面有效客户端的数量，用于位置计算）
    local order = 0
    for i = 1, MAX_CLIENTS do
        if i == idx then
            order = order + 1
            break
        end
        if clients[i] then
            order = order + 1
        end
    end

    local tab_x = (order - 1) * 95 + 10  -- 每个 Tab 宽 90，间距 5
    local is_active = (idx == active_client_index)

    -- Tab 背景容器
    local tab_container = airui.container({
        parent = tab_bar,
        x = tab_x,
        y = 2,
        w = 90,
        h = 30,
        color = is_active and COLOR_TAB_ACTIVE_BG or COLOR_TAB_INACTIVE_BG,
        radius = 6,
        on_click = function()
            if idx ~= active_client_index then
                if switch_client then switch_client(idx) end
            end
        end
    })

    -- Tab 标题文字
    local tab_text = "客户端" .. idx
    if c.connected then
        tab_text = tab_text .. " ●"
    end
    airui.label({
        parent = tab_container,
        x = 4,
        y = 5,
        w = 64,
        h = 20,
        text = tab_text,
        font_size = 12,
        color = is_active and COLOR_TAB_ACTIVE_TEXT or COLOR_TAB_INACTIVE_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 删除按钮（仅有效客户端数 > 1 时显示）
    local valid_count = 0
    for i = 1, MAX_CLIENTS do
        if clients[i] then valid_count = valid_count + 1 end
    end
    if valid_count > 1 then
        airui.label({
            parent = tab_container,
            x = 72,
            y = 7,
            w = 14,
            h = 16,
            text = "×",
            font_size = 14,
            color = COLOR_TAB_DELETE_BTN,
            align = airui.TEXT_ALIGN_CENTER,
            on_click = function()
                -- 阻止事件冒泡到 Tab 容器
                airui.msgbox({
                    title = "删除确认",
                    text = "确定删除 " .. tab_text .. " 吗？",
                    buttons = { "取消", "删除" },
                    on_action = function(self, label)
                        log.info("删除确认点击: " .. label)
                        if label == "删除" then
                            if delete_client then delete_client(idx) end
                        end
                        self:hide()
                    end
                })
            end
        })
    end

    tab_containers[idx] = tab_container
end

-- 渲染全部 Tab（先销毁旧的，再重建）
local function render_tabs()
    destroy_tabs()
    for i = 1, MAX_CLIENTS do
        if clients[i] then
            create_single_tab(i)
        end
    end
end

-- ========================================
-- 客户端切换/新建/删除
-- ========================================

-- 切换到指定索引的客户端
switch_client = function(idx)
    if idx < 1 or idx > MAX_CLIENTS then return end
    if not clients[idx] then return end
    -- 保存当前客户端配置到 app 模块
    save_form_to_client()
    local c = clients[active_client_index]
    if c then
        sys.publish("MQTT_SYNC_CLIENT", {
            index = active_client_index,
            host = c.host,
            port = c.port,
            client_id = c.client_id,
            user = c.user,
            password = c.password,
            will_topic = c.will_topic,
            will_payload = c.will_payload,
            will_qos = c.will_qos,
            will_retain = c.will_retain,
            keepalive = c.keepalive
        })
    end
    -- 切换索引
    active_client_index = idx
    -- 重置所有卡片到原始位置
    reset_card_positions()
    -- 重新渲染 Tab 栏
    render_tabs()
    -- 加载目标客户端配置到表单
    load_client_to_form()
end

-- 新建客户端
local function create_client()
    -- 保存当前客户端配置
    save_form_to_client()
    -- 检查是否所有槽位都已满（直接让新建逻辑处理，不需要提前检查）
    -- 创建新客户端数据（查找第一个空位置）
    local new_idx = nil
    for i = 1, MAX_CLIENTS do
        if not clients[i] then
            new_idx = i
            break
        end
    end
    if not new_idx then
        airui.msgbox({
            title = "提示",
            text = "最多支持 " .. MAX_CLIENTS .. " 个客户端",
            buttons = { "好的" },
            on_action = function(self, label)
                self:hide()
            end
        })
        return
    end
    clients[new_idx] = {
        id = new_idx,
        connected = false,
        host = "lbsmqtt.airm2m.com",
        port = "1884",
        client_id = "",
        user = "",
        password = "",
        will_topic = "",
        will_payload = "",
        will_qos = 0,
        will_retain = false,
        keepalive = "240",
        pub_topic = "",
        pub_payload = "",
        pub_qos = 0,
        subscriptions = {},
        logs = {},
    }
    -- 发布 MQTT 新建客户端事件
    sys.publish("MQTT_NEW_CLIENT", {
        index = new_idx,
        host = clients[new_idx].host,
        port = clients[new_idx].port,
        client_id = clients[new_idx].client_id,
        user = clients[new_idx].user,
        password = clients[new_idx].password,
        will_topic = clients[new_idx].will_topic,
        will_payload = clients[new_idx].will_payload,
        will_qos = clients[new_idx].will_qos,
        will_retain = clients[new_idx].will_retain,
        keepalive = clients[new_idx].keepalive
    })
    -- 切换到新客户端并渲染
    switch_client(new_idx)
end

-- 删除指定索引的客户端（不重排，索引位置置空）
delete_client = function(idx)
    if idx < 1 or idx > MAX_CLIENTS then return end
    if not clients[idx] then return end
    -- 检查是否只有一个有效客户端
    local valid_count = 0
    for i = 1, MAX_CLIENTS do
        if clients[i] then valid_count = valid_count + 1 end
    end
    if valid_count <= 1 then return end
    -- 发布 MQTT 删除客户端事件
    sys.publish("MQTT_DEL_CLIENT", {index = idx})

    -- 销毁旧 Tab
    destroy_tabs()

    -- 直接置空，不重排
    clients[idx] = nil

    -- 调整激活索引（如果删除的是当前激活的，切换到下一个有效客户端）
    if active_client_index == idx then
        for i = 1, MAX_CLIENTS do
            if clients[i] then
                active_client_index = i
                break
            end
        end
    end

    -- 重新渲染 Tab
    render_tabs()

    -- 加载新当前客户端配置到表单
    load_client_to_form()
end

-- ========================================
-- 创建发布卡片
-- ========================================

local function create_publish_card(parent, y_offset)
    publish_card_container = airui.container({
        parent = parent,
        x = CARD_MARGIN_X,
        y = y_offset,
        w = CARD_W,
        h = 115,
        color = COLOR_CARD_BG,
        color_opacity = 255,
        radius = 8
    })

    -- 卡片标题
    airui.label({
        parent = publish_card_container,
        x = 10,
        y = 5,
        w = CARD_W - 20,
        h = 18,
        text = "发布消息",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 第 0 行：发布主题
    airui.label({
        parent = publish_card_container,
        x = 10,
        y = 28,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "主题",
        font_size = 12,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_pub_topic = airui.textarea({
        parent = publish_card_container,
        x = FORM_INPUT_X,
        y = 25,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "如 /device/data",
        max_len = 64,
        keyboard = shared_keyboard
    })

    -- 第 1 行：发布消息
    airui.label({
        parent = publish_card_container,
        x = 10,
        y = 55,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "消息",
        font_size = 12,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_pub_payload = airui.textarea({
        parent = publish_card_container,
        x = FORM_INPUT_X,
        y = 52,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "消息内容",
        max_len = 128,
        keyboard = shared_keyboard
    })

    -- 第 2 行：QoS + 发送按钮
    airui.label({
        parent = publish_card_container,
        x = 10,
        y = 82,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "QoS",
        font_size = 12,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    dropdown_pub_qos = airui.dropdown({
        parent = publish_card_container,
        x = FORM_INPUT_X,
        y = 79,
        w = 60,
        h = 26,
        options = { "0", "1", "2" },
        default_index = 0
    })
    btn_send = airui.button({
        parent = publish_card_container,
        x = CARD_W - 80,
        y = 79,
        w = 70,
        h = 26,
        text = "发送",
        font_size = 12,
        style = {
            bg_color = COLOR_BTN_BLUE,
            border_color = COLOR_BTN_BLUE,
            text_color = COLOR_TEXT_WHITE,
            radius = 4,
            border_width = 0
        },
        on_click = function()
            -- 检查连接状态
            local c = clients[active_client_index]
            if not c or not c.connected then
                airui.msgbox({
                    title = "提示",
                    text = "请先连接服务器",
                    buttons = { "确定" },
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                return
            end
            local topic = ""
            local payload = ""
            if input_pub_topic then topic = input_pub_topic:get_text() or "" end
            if input_pub_payload then payload = input_pub_payload:get_text() or "" end
            local qos = 0
            if dropdown_pub_qos then qos = dropdown_pub_qos:get_selected() or 0 end
            if topic == "" then
                airui.msgbox({
                    title = "提示",
                    text = "请输入发布主题",
                    buttons = { "确定" },
                    on_action = function(self, label)
                        log.info("订阅确认点击: " .. label)
                        self:hide()
                    end
                })
                return
            end
            -- 发布 MQTT 发布事件
            sys.publish("MQTT_PUBLISH", {
                index = active_client_index,
                topic = topic,
                payload = payload,
                qos = qos
            })
        end
    })
end

-- ========================================
-- 创建订阅卡片
-- ========================================

local function create_subscribe_card(parent, y_offset)
    subscribe_card_container = airui.container({
        parent = parent,
        x = CARD_MARGIN_X,
        y = y_offset,
        w = CARD_W,
        h = 88,
        color = COLOR_CARD_BG,
        color_opacity = 255,
        radius = 8
    })

    -- 卡片标题
    airui.label({
        parent = subscribe_card_container,
        x = 10,
        y = 5,
        w = CARD_W - 20,
        h = 18,
        text = "订阅管理",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 第 0 行：订阅主题
    airui.label({
        parent = subscribe_card_container,
        x = 10,
        y = 28,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "主题",
        font_size = 12,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_sub_topic = airui.textarea({
        parent = subscribe_card_container,
        x = FORM_INPUT_X,
        y = 25,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "如 /device/down",
        max_len = 64,
        keyboard = shared_keyboard
    })

    -- 第 1 行：QoS + 订阅按钮
    airui.label({
        parent = subscribe_card_container,
        x = 10,
        y = 55,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "QoS",
        font_size = 12,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    dropdown_sub_qos = airui.dropdown({
        parent = subscribe_card_container,
        x = FORM_INPUT_X,
        y = 52,
        w = 60,
        h = 26,
        options = { "0", "1", "2" },
        default_index = 0
    })
    btn_subscribe = airui.button({
        parent = subscribe_card_container,
        x = CARD_W - 80,
        y = 52,
        w = 70,
        h = 26,
        text = "订阅",
        font_size = 12,
        style = {
            bg_color = COLOR_BTN_ORANGE,
            border_color = COLOR_BTN_ORANGE,
            text_color = COLOR_TEXT_WHITE,
            radius = 4,
            border_width = 0
        },
        on_click = function()
            -- 检查连接状态
            local c = clients[active_client_index]
            if not c or not c.connected then
                airui.msgbox({
                    title = "提示",
                    text = "请先连接服务器",
                    buttons = { "确定" },
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                return
            end
            local topic = ""
            if input_sub_topic then topic = input_sub_topic:get_text() or "" end
            if topic == "" then
                airui.msgbox({
                    title = "提示",
                    text = "请输入订阅主题",
                    buttons = { "确定" },
                    on_action = function(self, label)
                        log.info("订阅确认点击: " .. label)
                        self:hide()
                    end
                })
                return
            end
            local qos = 0
            if dropdown_sub_qos then qos = dropdown_sub_qos:get_selected() or 0 end
            -- 发布 MQTT 订阅事件（订阅逻辑由 app 模块处理）
            sys.publish("MQTT_SUBSCRIBE", {
                index = active_client_index,
                topic = topic,
                qos = qos
            })
            -- 清空输入框
            if input_sub_topic then input_sub_topic:set_text("") end
            if dropdown_sub_qos then dropdown_sub_qos:set_selected(0) end
        end
    })
end

-- ========================================
-- 创建已订阅列表卡片
-- ========================================

local function create_sub_list_card(parent, y_offset)
    sub_list_card_container = airui.container({
        parent = parent,
        x = CARD_MARGIN_X,
        y = y_offset,
        w = CARD_W,
        h = 145,
        color = COLOR_CARD_BG,
        color_opacity = 255,
        radius = 8
    })

    -- 标题
    airui.label({
        parent = sub_list_card_container,
        x = 10,
        y = 4,
        w = CARD_W - 20,
        h = 20,
        text = "已订阅主题",
        font_size = 14,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 内容区
    sub_list_card_body = airui.container({
        parent = sub_list_card_container,
        x = 0,
        y = 28,
        w = CARD_W,
        h = 117,
        color = COLOR_CARD_BG
    })

    -- 初始渲染订阅列表
    refresh_sub_list()
end

-- ========================================
-- 创建配置卡片
-- ========================================

local function create_config_card(parent, y_offset)
    -- 卡片外层容器：白色背景、完全透明、圆角
    config_card_container = airui.container({
        parent = parent,
        x = CARD_MARGIN_X,
        y = y_offset,
        w = CARD_W,
        h = 400,
        color = COLOR_CARD_BG,
        color_opacity = 0,
        radius = 8
    })

    -- ---- 卡片标题栏：状态圆点 + 标题 + 折叠箭头 ----
    config_card_title = airui.container({
        parent = config_card_container,
        x = 0,
        y = 0,
        w = CARD_W,
        h = 30,
        color = COLOR_CARD_BG
    })

    -- 连接状态圆点
    config_status_dot = airui.label({
        parent = config_card_title,
        x = 10,
        y = 7,
        w = 14,
        h = 16,
        text = "●",
        font_size = 14,
        color = COLOR_STATUS_DISCONNECTED,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 连接状态文本
    config_status_text = airui.label({
        parent = config_card_title,
        x = 26,
        y = 7,
        w = 50,
        h = 16,
        text = "未连接",
        font_size = 12,
        color = COLOR_STATUS_DISCONNECTED,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 卡片标题：居中显示（(CARD_W - 150) / 2 = 75）
    airui.label({
        parent = config_card_title,
        x = 75,
        y = 5,
        w = 150,
        h = 20,
        text = "客户端配置",
        font_size = 14,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 折叠箭头（点击切换折叠状态）
    config_toggle_label = airui.label({
        parent = config_card_title,
        x = CARD_W - 30,
        y = 5,
        w = 20,
        h = 20,
        text = "∨",
        font_size = 14,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = function()
            toggle_config_card()
        end
    })

    -- 整行可点击（折叠/展开）
    config_card_title.on_click = function()
        toggle_config_card()
    end

    -- ---- 卡片内容区（可折叠） ----
    config_card_body = airui.container({
        parent = config_card_container,
        x = 0,
        y = 32,
        w = CARD_W,
        h = 360,
        color = COLOR_CARD_BG
    })

    -- 第 0 行：服务器地址（y=5）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 13,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "地址",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_host = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X,
        y = 5,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "mqtt服务器地址",
        max_len = 64,
        keyboard = shared_keyboard
    })

    -- 第 1 行：端口 + 客户端 ID（y=40）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 48,
        w = FORM_LABEL_W - 20,
        h = FORM_INPUT_H,
        text = "端口",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_port = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X,
        y = 40,
        w = FORM_INPUT_W - 170,
        h = FORM_INPUT_H,
        placeholder = "1884",
        max_len = 5,
        keyboard = shared_keyboard
    })
    airui.label({
        parent = config_card_body,
        x = 115,
        y = 48,
        w = FORM_LABEL_W + 25,
        h = FORM_INPUT_H,
        text = "客户端ID",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_client_id = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X + 130,
        y = 40,
        w = FORM_LABEL_W + 50,
        h = FORM_INPUT_H,
        placeholder = "自定义ID",
        max_len = 32,
        keyboard = shared_keyboard
    })

    -- 第 2 行：用户名（y=75）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 83,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "用户名",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_user = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X,
        y = 75,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "可选",
        max_len = 32,
        keyboard = shared_keyboard
    })

    -- 第 3 行：密码（y=110）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 118,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "密码",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_password = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X,
        y = 110,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "可选",
        max_len = 32,
        keyboard = shared_keyboard
    })

    -- 遗嘱消息分隔标题（y=150）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 152,
        w = 280,
        h = 20,
        text = "遗嘱消息（可选）",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 第 5 行：遗嘱主题（y=175）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 183,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "主题",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_will_topic = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X,
        y = 175,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "遗嘱主题，空为不启用",
        max_len = 64,
        keyboard = shared_keyboard
    })

    -- 第 6 行：遗嘱消息（y=210）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 218,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "消息",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    input_will_payload = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X,
        y = 210,
        w = FORM_INPUT_W,
        h = FORM_INPUT_H,
        placeholder = "遗嘱消息内容",
        max_len = 128,
        keyboard = shared_keyboard
    })

    -- 第 7 行：遗嘱 QoS（y=245）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 253,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "QoS",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    dropdown_will_qos = airui.dropdown({
        parent = config_card_body,
        x = FORM_INPUT_X,
        y = 245,
        w = 60,
        h = 28,
        options = { "0", "1", "2" },
        default_index = 0
    })

    -- Keepalive 标签
    airui.label({
        parent = config_card_body,
        x = FORM_INPUT_X + 70,
        y = 253,
        w = 90,
        h = FORM_INPUT_H,
        text = "心跳时间（秒）",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- Keepalive 输入框
    input_keepalive = airui.textarea({
        parent = config_card_body,
        x = FORM_INPUT_X + 160,
        y = 245,
        w = 70,
        h = FORM_INPUT_H,
        placeholder = "240",
        max_len = 5,
        keyboard = shared_keyboard
    })

    -- 第 8 行：遗嘱 Retain（y=280）
    airui.label({
        parent = config_card_body,
        x = 10,
        y = 288,
        w = FORM_LABEL_W,
        h = FORM_INPUT_H,
        text = "Retain",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    switch_will_retain = airui.switch({
        parent = config_card_body,
        x = FORM_INPUT_X + 10,
        y = 283,
        w = 50,
        h = 25,
        checked = false
    })

    -- 第 9 行：连接/断开按钮（y=320）
    btn_connect = airui.button({
        parent = config_card_body,
        x = 10,
        y = 322,
        w = 130,
        h = 30,
        text = "连接",
        font_size = 14,
        style = {
            bg_color = COLOR_BTN_GREEN,
            border_color = COLOR_BTN_GREEN,
            text_color = COLOR_TEXT_WHITE,
            radius = 4,
            border_width = 0
        },
        on_click = function()
            -- 保存并同步当前客户端配置
            save_form_to_client()
            local c = clients[active_client_index]
            if c then
                sys.publish("MQTT_SYNC_CLIENT", {
                    index = active_client_index,
                    host = c.host,
                    port = c.port,
                    client_id = c.client_id,
                    user = c.user,
                    password = c.password,
                    will_topic = c.will_topic,
                    will_payload = c.will_payload,
                    will_qos = c.will_qos,
                    will_retain = c.will_retain,
                    keepalive = c.keepalive
                })
            end
            -- 发布 MQTT 连接事件
            sys.publish("MQTT_CONNECT", {index = active_client_index})
        end
    })
    btn_disconnect = airui.button({
        parent = config_card_body,
        x = 160,
        y = 322,
        w = 130,
        h = 30,
        text = "断开",
        font_size = 14,
        style = {
            bg_color = COLOR_BTN_RED,
            border_color = COLOR_BTN_RED,
            text_color = COLOR_TEXT_WHITE,
            radius = 4,
            border_width = 0
        },
        on_click = function()
            -- 发布 MQTT 断开事件
            sys.publish("MQTT_DISCONNECT", {index = active_client_index})
        end
    })
    -- 初始状态：未连接，断开按钮置灰（load_client_to_form 会再次统一设置）
    btn_disconnect:set_disabled(true)
end

-- ========================================
-- 创建标题栏
-- 布局：[← 返回按钮]  "MQTT 客户端"  [+ 新建按钮]
-- ========================================

local function create_title_bar(parent)
    title_bar = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = TITLE_BAR_H,
        color = COLOR_TITLE_BG
    })

    -- 返回按钮：白色圆形底板 + 文字箭头
    local back_btn = airui.container({
        parent = title_bar,
        x = 5,
        y = 11,
        w = 22,
        h = 22,
        color = COLOR_TEXT_WHITE,
        radius = 11,
        on_click = function()
            go_back()
        end
    })
    airui.label({
        parent = back_btn,
        x = 0,
        y = 3,
        w = 22,
        h = 10,
        text = "←",
        font_size = 18,
        color = COLOR_TITLE_BG,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题文字：居中显示
    airui.label({
        parent = title_bar,
        x = 40,
        y = 16,
        w = 240,
        h = 20,
        text = "MQTT 客户端",
        font_size = 17,
        color = COLOR_TEXT_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 新建按钮：右侧 "+ 新建"
    btn_new_client = airui.button({
        parent = title_bar,
        x = 270,
        y = 10,
        w = 45,
        h = 24,
        text = "+ 新建",
        font_size = 11,
        style = {
            bg_color = 0x2A6EB0,
            border_color = 0x2A6EB0,
            text_color = COLOR_TEXT_WHITE,
            radius = 4,
            border_width = 0
        },
        on_click = function()
            create_client()
        end
    })
end

-- ========================================
-- 创建 Tab 栏（阶段 1 仅占位，阶段 3 实现动态渲染）
-- ========================================

local function create_tab_bar(parent)
    tab_bar = airui.container({
        parent = parent,
        x = 0,
        y = TAB_BAR_Y,
        w = SCREEN_W,
        h = TAB_BAR_H,
        color = COLOR_TAB_BAR_BG
    })
    -- Tab 动态渲染由 render_tabs() 在 on_create 中调用
end

-- ========================================
-- 创建内容区
-- ========================================

local function create_content_area(parent)
    content_area = airui.container({
        parent = parent,
        x = 0,
        y = CONTENT_Y,
        w = SCREEN_W,
        h = CONTENT_H,
        color = COLOR_BG
    })

    -- 按顺序创建各卡片，计算展开态下的 Y 坐标
    -- 注意：content_area (y=78, h=402) 高度有限，内容超出时自动滚动
    local card_y = 8

    -- 1. 配置卡片（容器 y=8, h=400 → 底部 y=408，间距 5）
    create_config_card(content_area, card_y)
    card_y = 413  -- 配置卡片底部 y=408 + 间距 5

    -- 2. 发布卡片（h=115）
    create_publish_card(content_area, card_y)
    card_y = card_y + 115 + 13  -- 与订阅卡片间距 13

    -- 3. 订阅卡片（h=88）
    create_subscribe_card(content_area, card_y)
    card_y = card_y + 88 + 13  -- 与已订阅列表间距 13

    -- 4. 已订阅列表卡片（h=145）
    create_sub_list_card(content_area, card_y)
    card_y = card_y + 145 + 13  -- 与日志卡片间距 13

    -- 5. 日志卡片（h=145）
    create_log_card(content_area, card_y)
end

-- ========================================
-- 构建全部 UI
-- ========================================

local function create_ui()
    -- 创建主容器作为根容器，所有子组件 parent 都指向它
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLOR_BG
    })

    -- 创建共享键盘（多个 textarea 共用，减少内存）
    shared_keyboard = airui.keyboard({
        parent = main_container,
        x = 0,
        y = -10,
        w = SCREEN_W,
        h = 120,
        mode = "pinyin_26",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        on_commit = function(self)
            self:hide()
        end
    })

    create_title_bar(main_container)
    create_tab_bar(main_container)
    create_content_area(main_container)
end

-- ========================================
-- 窗口生命周期回调
-- ========================================

-- 窗口创建回调：初始化 UI 和默认客户端数据
local function on_create()
    log.info("mqtt_client_win", "窗口创建")

    -- 初始化默认客户端数据
    init_default_client()

    -- 构建 UI
    create_ui()

    -- 渲染 Tab 栏
    render_tabs()

    -- 将默认客户端配置加载到表单控件
    load_client_to_form()
end

-- 窗口销毁回调：先停止定时器（如有），再销毁主容器
local function on_destroy()
    log.info("mqtt_client_win", "窗口销毁")

    -- 销毁已订阅列表行
    destroy_sub_list_rows()

    -- 销毁所有 Tab
    destroy_tabs()

    -- 销毁主容器（自动递归销毁内部所有子组件）
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    -- 释放模块级引用
    title_bar = nil
    tab_bar = nil
    tab_containers = {}
    btn_new_client = nil
    content_area = nil
    shared_keyboard = nil
    config_card_container = nil
    config_card_title = nil
    config_card_body = nil
    config_toggle_label = nil
    config_status_dot = nil
    config_status_text = nil
    input_host = nil
    input_port = nil
    input_client_id = nil
    input_user = nil
    input_password = nil
    input_will_topic = nil
    input_will_payload = nil
    input_keepalive = nil
    dropdown_will_qos = nil
    switch_will_retain = nil
    btn_connect = nil
    btn_disconnect = nil
    -- 发布卡片
    publish_card_container = nil
    input_pub_topic = nil
    input_pub_payload = nil
    dropdown_pub_qos = nil
    btn_send = nil
    -- 订阅卡片
    subscribe_card_container = nil
    input_sub_topic = nil
    dropdown_sub_qos = nil
    btn_subscribe = nil
    -- 已订阅列表卡片
    sub_list_card_container = nil
    sub_list_card_body = nil
    sub_list_rows = {}
    -- 日志卡片
    destroy_log_rows()
    log_body = nil
    log_card_container = nil
    clients = {}
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("mqtt_client_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("mqtt_client_win", "窗口失去焦点")
end

-- ========================================
-- 打开窗口的事件处理函数
-- ========================================

local function open_handler()
    if win_id then
        log.info("mqtt_client_win", "窗口已存在，跳过重复创建")
        return
    end

    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
    log.info("mqtt_client_win", "窗口已打开", "win_id=" .. tostring(win_id))
end

-- ========================================
-- 事件订阅
-- ========================================

sys.subscribe("OPEN_MQTT_CLIENT_WIN", open_handler)

-- MQTT 状态变更事件
sys.subscribe("MQTT_STATUS", function(data)
    local idx = data.index
    local connected = data.connected

    -- 更新客户端连接状态
    if clients[idx] then
        clients[idx].connected = connected
    end

    -- 如果是当前激活客户端，更新 UI
    if idx == active_client_index then
        update_status_ui(connected)
    end

    -- 刷新 Tab 栏（更新圆点颜色）
    if active_client_index == idx then
        render_tabs()
    end
end)

-- MQTT 日志事件
sys.subscribe("MQTT_LOG", function(data)
    -- 只处理当前激活客户端的日志
    if data.index == active_client_index then
        add_log(data.text, data.log_type)
    end
end)

-- MQTT 订阅列表变更事件
sys.subscribe("MQTT_SUB_LIST_CHANGE", function(data)
    -- 只处理当前激活客户端的订阅列表
    if data.index == active_client_index then
        clients[active_client_index].subscriptions = data.subs
        refresh_sub_list()
    end
end)

-- MQTT 接收数据事件
sys.subscribe("MQTT_RECV_DATA", function(data)
    -- 日志已通过 MQTT_LOG 显示，无需额外处理
end)
