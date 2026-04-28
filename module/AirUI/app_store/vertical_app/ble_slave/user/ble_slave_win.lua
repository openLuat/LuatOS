--[[
@module  ble_slave_win
@summary BLE从机应用主界面
@version 1.0.0
@date    2026.04.09
@author  王世豪
@usage
BLE从机应用主界面，负责显示和控制BLE从机功能
--]]

-- ==================== 模块导入 ====================
local ble_manager = require "ble_manager"

-- ==================== 模块定义 ====================
local ble_slave_win = {}

-- ==================== 常量定义 ====================
local MAX_LOGS = 50          -- 广播页面数据日志最大条数
local MAX_TRANSFER_LOGS = 50 -- 传输页面数据日志最大条数

-- ==================== 状态变量 ====================
-- 窗口ID
local win_id = nil

-- 当前页面
local current_page = "adv"

-- 数据计数
local rx_bytes = 0
tx_bytes = 0
local rx_packets = 0
local tx_packets = 0

-- 当前使用的UUID
local tx_service_uuid = nil
local tx_char_uuid = nil
local tx_char_props = nil

-- ==================== UI控件 ====================
local ui_controls = {}

-- ==================== 数据存储 ====================
local data_logs = {}
local transfer_data_logs = {}

-- ==================== 弹窗和键盘 ====================
local uuid_selector_dialog = nil
local shared_keyboard = nil

-- ==================== 设置页面变量 ====================
local settings_shared_keyboard = nil
local input_values = {}
local settings_ui_controls = {}

-- ==================== 工具函数 ====================

-- 关闭对话框
local function close_dialog(dialog, mask)
    if dialog then
        dialog:destroy()
    end
    if mask then
        mask:destroy()
    end
end

-- 验证数字
local function validate_number(value, min, max)
    local num = tonumber(value)
    if not num then return false end
    if min and num < min then return false end
    if max and num > max then return false end
    return true
end

-- ==================== 事件回调函数 ====================

-- 键盘提交回调
local function on_keyboard_commit()
    log.info("BLE Slave", "键盘提交")
    if shared_keyboard and shared_keyboard.hide then
        shared_keyboard:hide()
    end
end

-- 键盘提交回调（设置页面）
local function on_settings_keyboard_commit()
    log.info("BLE Slave Settings", "键盘提交")
    if settings_shared_keyboard and settings_shared_keyboard.hide then
        settings_shared_keyboard:hide()
    end
end

-- 获取输入框文本
local function get_settings_input(key, default_value)
    if settings_ui_controls[key] and settings_ui_controls[key].get_text then
        local text = settings_ui_controls[key]:get_text()
        if text and text ~= "" then
            return text
        end
    end
    if input_values[key] and input_values[key] ~= "" then
        return input_values[key]
    end
    return tostring(default_value)
end

-- 错误对话框确定按钮点击
local function on_error_dialog_click(error_dialog, error_mask)
    close_dialog(error_dialog, error_mask)
end

-- 重启对话框取消按钮点击
local function on_reboot_cancel_click(confirm_dialog, confirm_mask)
    close_dialog(confirm_dialog, confirm_mask)
end

-- 重启对话框确认按钮点击
local function on_reboot_confirm_click(confirm_dialog, confirm_mask)
    close_dialog(confirm_dialog, confirm_mask)
    pm.reboot()
end

-- 底部导航-广播按钮点击
local function on_nav_adv_click()
    ble_slave_win.switch_page("adv")
end

-- 底部导航-传输按钮点击
local function on_nav_transfer_click()
    ble_slave_win.switch_page("transfer")
end

-- 底部导航-设置按钮点击
local function on_nav_settings_click()
    ble_slave_win.switch_page("settings")
end

-- UUID选择按钮点击
local function on_select_uuid_click()
    if shared_keyboard and shared_keyboard.hide then
        shared_keyboard:hide()
    end
    ble_slave_win.show_uuid_selector()
end

-- 输入框点击显示键盘
local function on_input_click_show_keyboard()
    if shared_keyboard and shared_keyboard.show then
        shared_keyboard:show()
    end
end

-- 键盘隐藏按钮点击
local function on_keyboard_hide_click()
    if shared_keyboard and shared_keyboard.hide then
        shared_keyboard:hide()
    end
end

-- UUID选择项点击处理函数
local function on_uuid_item_select(item, mask)
    -- 设置发送UUID
    tx_service_uuid = "FA00"
    tx_char_uuid = item.uuid
    tx_char_props = item.props
    log.info("BLE Slave", "设置发送UUID:", tx_service_uuid, tx_char_uuid, "属性:", string.format("0x%02X", tx_char_props))
    
    -- 更新显示
    ble_slave_win.update_uuid_display()
    
    -- 关闭弹窗
    if uuid_selector_dialog then
        uuid_selector_dialog:destroy()
        uuid_selector_dialog = nil
    end
    if mask then
        mask:destroy()
    end
end

-- 显示错误对话框
local function show_error_dialog(title, message)
    local error_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x000000,
        alpha = 80
    })

    local error_dialog = airui.container({
        parent = error_mask,
        x = 40, y = 226, w = 400, h = 200,
        color = 0xFFFFFF,
        radius = 12
    })

    airui.label({
        parent = error_dialog,
        x = 20, y = 20, w = 360, h = 30,
        text = title,
        font_size = 16,
        color = 0x333333
    })

    airui.container({
        parent = error_dialog,
        x = 20, y = 60, w = 360, h = 80,
        color = 0xF5F5F5,
        radius = 8
    })

    airui.label({
        parent = error_dialog,
        x = 30, y = 70, w = 340, h = 60,
        text = message,
        font_size = 14,
        color = 0x666666
    })

    airui.button({
        parent = error_dialog,
        x = 260, y = 140, w = 100, h = 40,
        text = "确定",
        style = {
            bg_color = 0xE91E63,
            text_color = 0xFFFFFF,
            radius = 20
        },
        on_click = function() on_error_dialog_click(error_dialog, error_mask) end
    })
end

-- 显示确认重启对话框
local function show_confirm_reboot_dialog()
    local confirm_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x000000,
        alpha = 80
    })

    local confirm_dialog = airui.container({
        parent = confirm_mask,
        x = 40, y = 226, w = 400, h = 200,
        color = 0xFFFFFF,
        radius = 12
    })

    airui.label({
        parent = confirm_dialog,
        x = 20, y = 20, w = 360, h = 30,
        text = "确认重启",
        font_size = 16,
        color = 0x333333
    })

    airui.label({
        parent = confirm_dialog,
        x = 30, y = 70, w = 340, h = 60,
        text = "修改配置需要重启生效，请确认是否重启？",
        font_size = 14,
        color = 0x666666
    })

    airui.button({
        parent = confirm_dialog,
        x = 140, y = 140, w = 100, h = 40,
        text = "取消",
        style = {
            bg_color = 0xCCCCCC,
            text_color = 0x333333,
            radius = 20
        },
        on_click = function() on_reboot_cancel_click(confirm_dialog, confirm_mask) end
    })

    airui.button({
        parent = confirm_dialog,
        x = 260, y = 140, w = 100, h = 40,
        text = "确认重启",
        style = {
            bg_color = 0xE91E63,
            text_color = 0xFFFFFF,
            radius = 20
        },
        on_click = function() on_reboot_confirm_click(confirm_dialog, confirm_mask) end
    })
end

-- ==================== 界面创建函数 ====================

-- 创建界面
function ble_slave_win.on_create()
    -- 初始化BLE管理器
    if ble_manager and ble_manager.init then
        ble_manager.init()
    end
    
    -- 设置回调
    ble_manager.on_state_change = ble_slave_win.on_state_change
    ble_manager.on_data = ble_slave_win.on_data
    
    -- 创建主容器
    ui_controls.main_container = airui.container({
        x = 0, y = 0, w = 480, h = 800,
        color = 0xFFFFFF,
        parent = airui.screen
    })
    
    -- 创建标题栏 (68px)
    local header = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 0, w = 480, h = 68,
        color = 0x00796B
    })
    
    -- 返回按钮
    airui.button({
        parent = header,
        x = 16, y = 14, w = 40, h = 40,
        text = "←",
        style = {
            bg_color = 0x009688,
            text_color = 0xFFFFFF,
            radius = 20
        },
        on_click = ble_slave_win.go_back
    })
    
    -- 标题
    airui.label({
        parent = header,
        x = 72, y = 14, w = 300, h = 40,
        text = "BLE从机",
        font_size = 20,
        color = 0xFFFFFF
    })
    
    -- 创建内容区域
    ui_controls.content_area = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 68, w = 480, h = 660,
        color = 0xFFFFFF
    })
    
    -- 创建底部导航
    ui_controls.bottom_nav = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 728, w = 480, h = 72,
        color = 0xFFFFFF
    })

    -- 广播按钮（图标形式）
    ui_controls.nav_adv = airui.image({
        parent = ui_controls.bottom_nav,
        x = 56, y = 8, w = 48, h = 48,
        src = "/luadb/broad.png",
        on_click = on_nav_adv_click
    })
    ui_controls.nav_adv_label = airui.label({
        parent = ui_controls.bottom_nav,
        x = 0, y = 56, w = 160, h = 16,
        text = "广播",
        font_size = 14,
        color = 0x00796B,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 数据传输按钮（图标形式）
    ui_controls.nav_transfer = airui.image({
        parent = ui_controls.bottom_nav,
        x = 216, y = 8, w = 48, h = 48,
        src = "/luadb/transfer.png",
        on_click = on_nav_transfer_click
    })
    ui_controls.nav_transfer_label = airui.label({
        parent = ui_controls.bottom_nav,
        x = 160, y = 56, w = 160, h = 16,
        text = "传输",
        font_size = 14,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 设置按钮（图标形式）
    ui_controls.nav_settings = airui.image({
        parent = ui_controls.bottom_nav,
        x = 376, y = 8, w = 48, h = 48,
        src = "/luadb/setting.png",
        on_click = on_nav_settings_click
    })
    ui_controls.nav_settings_label = airui.label({
        parent = ui_controls.bottom_nav,
        x = 320, y = 56, w = 160, h = 16,
        text = "设置",
        font_size = 14,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 默认显示广播页面
    ble_slave_win.switch_page("adv")
    
    log.info("BLE Slave", "界面创建完成")
end

-- 清除内容区域
function ble_slave_win.clear_content_area()
    -- 隐藏键盘
    if shared_keyboard and shared_keyboard.hide then
        shared_keyboard:hide()
    end
    if settings_shared_keyboard and settings_shared_keyboard.hide then
        settings_shared_keyboard:hide()
    end
    
    -- 销毁content_area前清理键盘引用（因为键盘是content_area的子元素）
    shared_keyboard = nil
    settings_shared_keyboard = nil
    
    if ui_controls.content_area then
        ui_controls.content_area:destroy()
        ui_controls.content_area = nil
    end
    
    -- ========== 清理所有页面相关的控件引用（防止访问已销毁控件导致死机） ==========
    -- 广播页面控件
    ui_controls.status_icon = nil
    ui_controls.status_text = nil
    ui_controls.adv_btn = nil
    ui_controls.adv_status = nil
    ui_controls.conn_status = nil
    ui_controls.rx_count = nil
    ui_controls.tx_count = nil
    ui_controls.log_section = nil
    ui_controls.log_display = nil
    
    -- 传输页面控件
    ui_controls.conn_status_card = nil
    ui_controls.transfer_conn_status = nil
    ui_controls.transfer_status_dot = nil
    ui_controls.transfer_status_text = nil
    ui_controls.disconnect_btn = nil
    ui_controls.rx_card = nil
    ui_controls.rx_display = nil
    ui_controls.rx_bytes = nil
    ui_controls.rx_packets = nil
    ui_controls.send_input = nil
    ui_controls.tx_bytes = nil
    ui_controls.tx_packets = nil
    ui_controls.tx_uuid_label = nil
    ui_controls.tx_uuid_btn = nil
    
    -- 设置页面控件
    settings_ui_controls = {}
    input_values = {}
    -- ============================================================================
    
    ui_controls.content_area = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 68, w = 480, h = 676,
        color = 0xFFFFFF
    })
end

-- 切换页面
function ble_slave_win.switch_page(page_name)
    log.info("BLE Slave", "切换到页面: " .. page_name)
    
    ble_slave_win.clear_content_area()

    -- 重置导航状态（标签颜色变灰）
    if ui_controls.nav_adv_label then
        ui_controls.nav_adv_label:set_color(0x888888)
    end
    if ui_controls.nav_transfer_label then
        ui_controls.nav_transfer_label:set_color(0x888888)
    end
    if ui_controls.nav_settings_label then
        ui_controls.nav_settings_label:set_color(0x888888)
    end

    -- 显示目标页面
    if page_name == "adv" then
        ble_slave_win.create_adv_content()
        if ui_controls.nav_adv_label then
            ui_controls.nav_adv_label:set_color(0x00796B)
        end
    elseif page_name == "transfer" then
        ble_slave_win.create_transfer_content()
        if ui_controls.nav_transfer_label then
            ui_controls.nav_transfer_label:set_color(0x00796B)
        end
    elseif page_name == "settings" then
        ble_slave_win.create_settings_content()
        if ui_controls.nav_settings_label then
            ui_controls.nav_settings_label:set_color(0x00796B)
        end
    end
    
    current_page = page_name
end

-- ==================== 页面内容创建 ====================

-- 创建广播页面内容
function ble_slave_win.create_adv_content()
    local config = ble_manager.get_config()
    local adv_interval = config and config.adv_interval or 100
    
    -- 主控制区
    local main_control = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 0, w = 480, h = 200,
        color = 0xFFFFFF
    })
    
    -- 状态图标（使用图片）
    ui_controls.status_icon = airui.image({
        parent = main_control,
        x = 180, y = 20, w = 120, h = 120,
        src = "/luadb/ble_close.png"
    })
    
    -- 广播按钮
    ui_controls.adv_btn = airui.button({
        parent = main_control,
        x = 100, y = 150, w = 280, h = 48,
        text = "开始广播",
        style = {
            bg_color = 0x4CAF50,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = ble_slave_win.toggle_adv
    })
    
    -- 状态面板
    local status_panel = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 200, w = 480, h = 120,
        color = 0xF8F9FA
    })
    
    -- 广播状态卡片
    local status_card1 = airui.container({
        parent = status_panel,
        x = 16, y = 20, w = 104, h = 80,
        color = 0xFFFFFF,
        radius = 12
    })
    
    airui.label({
        parent = status_card1,
        x = 0, y = 16, w = 104, h = 20,
        text = "广播状态",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    ui_controls.adv_status = airui.label({
        parent = status_card1,
        x = 0, y = 40, w = 104, h = 30,
        text = "已停止",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 连接状态卡片
    local status_card2 = airui.container({
        parent = status_panel,
        x = 136, y = 20, w = 104, h = 80,
        color = 0xFFFFFF,
        radius = 12
    })
    
    airui.label({
        parent = status_card2,
        x = 0, y = 16, w = 104, h = 20,
        text = "连接状态",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    ui_controls.conn_status = airui.label({
        parent = status_card2,
        x = 0, y = 40, w = 104, h = 30,
        text = "未连接",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 接收数据卡片
    local status_card3 = airui.container({
        parent = status_panel,
        x = 256, y = 20, w = 104, h = 80,
        color = 0xFFFFFF,
        radius = 12
    })
    
    airui.label({
        parent = status_card3,
        x = 0, y = 16, w = 104, h = 20,
        text = "接收",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    ui_controls.rx_count = airui.label({
        parent = status_card3,
        x = 0, y = 40, w = 104, h = 30,
        text = tostring(rx_bytes),
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 发送数据卡片
    local status_card4 = airui.container({
        parent = status_panel,
        x = 376, y = 20, w = 88, h = 80,
        color = 0xFFFFFF,
        radius = 12
    })
    
    airui.label({
        parent = status_card4,
        x = 0, y = 16, w = 88, h = 20,
        text = "发送",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    ui_controls.tx_count = airui.label({
        parent = status_card4,
        x = 0, y = 40, w = 88, h = 30,
        text = tostring(tx_bytes),
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 数据日志区域
    ui_controls.log_section = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 320, w = 480, h = 332,
        color = 0xFFFFFF
    })
    
    airui.label({
        parent = ui_controls.log_section,
        x = 20, y = 20, w = 440, h = 20,
        text = "数据日志",
        font_size = 16,
        color = 0x333333
    })
    
    -- 日志显示区域
    ui_controls.log_display = airui.container({
        parent = ui_controls.log_section,
        x = 20, y = 50, w = 440, h = 262,
        color = 0x263238,
        radius = 12
    })
    
    -- 添加初始日志
    ble_slave_win.add_log("[系统] BLE从机已就绪", 0xB0BEC5)
    ble_slave_win.add_log("[系统] 等待广播启动...", 0xB0BEC5)
end

-- 创建数据传输页面内容
function ble_slave_win.create_transfer_content()
    local transfer_section = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 0, w = 480, h = 676,
        color = 0xFFFFFF
    })

    -- 创建共享键盘（使用transfer_section作为父容器）
    if not shared_keyboard then
        shared_keyboard = airui.keyboard({
            parent = transfer_section,
            x = 0,
            y = -20,
            w = 480,
            h = 200,
            mode = "text",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = on_keyboard_commit
        })
        log.info("BLE Slave", "传输页面键盘创建完成")
    end

    -- 连接状态卡片（下移避免和状态栏重叠）
    ui_controls.conn_status_card = airui.container({
        parent = transfer_section,
        x = 20, y = 16, w = 440, h = 80,
        color = 0x4CAF50,
        radius = 12
    })

    local conn_status_card = ui_controls.conn_status_card

    ui_controls.transfer_conn_status = airui.label({
        parent = conn_status_card,
        x = 16, y = 8, w = 200, h = 20,
        text = ble_manager.get_conn_state() and "已连接到主机" or "未连接到主机",
        font_size = 14,
        color = 0xFFFFFF
    })

    -- 状态点和文字
    ui_controls.transfer_status_dot = airui.container({
        parent = conn_status_card,
        x = 200, y = 14, w = 8, h = 8,
        color = ble_manager.get_conn_state() and 0xFFFFFF or 0xBDBDBD,
        radius = 4
    })

    ui_controls.transfer_status_text = airui.label({
        parent = conn_status_card,
        x = 220, y = 8, w = 100, h = 20,
        text = ble_manager.get_conn_state() and "数据传输中" or "等待连接",
        font_size = 14,
        color = 0xFFFFFF
    })

    -- 添加断开连接按钮（优化样式：红色背景+白色文字，更醒目）
    ui_controls.disconnect_btn = airui.button({
        parent = conn_status_card,
        x = 340, y = 20, w = 80, h = 36,
        text = "断开",
        font_size = 13,
        style = {
            bg_color = 0xF44336,
            text_color = 0xFFFFFF,
            radius = 18
        },
        on_click = ble_slave_win.disconnect_conn
    })

    -- UUID选择按钮区域
    -- 发送UUID选择按钮（橙色背景，与发送标签对齐）
    local select_tx_uuid_btn = airui.button({
        parent = conn_status_card,
        x = 16, y = 48, w = 80, h = 26,
        text = "发送UUID",
        font_size = 11,
        style = {
            bg_color = 0xFF9800,
            text_color = 0xFFFFFF,
            radius = 13
        },
        on_click = on_select_uuid_click
    })
    
    -- 发送UUID显示
    ui_controls.tx_uuid_label = airui.label({
        parent = conn_status_card,
        x = 105, y = 54, w = 130, h = 18,
        text = "发送: EA01",
        font_size = 11,
        color = 0xFFFFFF
    })
    
    -- 初始化默认UUID
    if not tx_char_uuid then
        tx_char_uuid = "EA01"
        tx_service_uuid = "FA00"
    end

    -- 接收数据卡片（同步下移）
    ui_controls.rx_card = airui.container({
        parent = transfer_section,
        x = 20, y = 106, w = 440, h = 320,
        color = 0xFFFFFF,
        radius = 12
    })
    local rx_card = ui_controls.rx_card

    airui.label({
        parent = rx_card,
        x = 0, y = 4, w = 280, h = 20,
        text = "接收数据",
        font_size = 16,
        color = 0x333333
    })

    airui.button({
        parent = rx_card,
        x = 350, y = 2, w = 60, h = 24,
        text = "清空",
        font_size = 14,
        style = {
            bg_color = 0xFFFFFF,
            text_color = 0x2196F3,
            border_color = 0x2196F3,
            border_width = 1,
            radius = 10
        },
        on_click = ble_slave_win.clear_rx
    })

    ui_controls.rx_display = airui.container({
        parent = rx_card,
        x = 0, y = 30, w = 440, h = 290,
        color = 0x263238,
        radius = 8,
        font_size = 14
    })

    ble_slave_win.add_transfer_log("[系统] 等待接收数据...", 0xB0BEC5)

    -- 发送数据卡片（同步下移）
    local tx_card = airui.container({
        parent = transfer_section,
        x = 20, y = 436, w = 440, h = 190,
        color = 0xFFFFFF,
        radius = 12
    })

    airui.label({
        parent = tx_card,
        x = 0, y = 0, w = 200, h = 20,
        text = "发送数据到指定特征值",
        font_size = 16,
        color = 0x333333
    })

    -- 输入框背景
    local input_bg = airui.container({
        parent = tx_card,
        x = 0, y = 26, w = 440, h = 56,
        color = 0xF5F5F5,
        radius = 6
    })

    -- 输入框（使用textarea，绑定共享键盘）
    ui_controls.send_input = airui.textarea({
        parent = input_bg,
        x = 10, y = 4, w = 420, h = 48,
        text = "",
        font_size = 14,
        color = 0x333333,
        bg_color = 0x00000000,
        max_length = 100,
        keyboard = shared_keyboard,
        editable = true
    })
    
    -- 点击textarea时显示键盘
    if ui_controls.send_input and ui_controls.send_input.on_click then
        ui_controls.send_input.on_click = on_input_click_show_keyboard
    end

    -- 按钮区域
    local btn_area = airui.container({
        parent = tx_card,
        x = 0, y = 90, w = 440, h = 44,
        color = 0xFFFFFF
    })

    airui.button({
        parent = btn_area,
        x = 0, y = 0, w = 100, h = 40,
        text = "发送文本",
        style = {
            bg_color = 0x4CAF50,
            text_color = 0xFFFFFF,
            radius = 8,
            font_size = 14,
        },
        on_click = ble_slave_win.send_text
    })

    airui.button({
        parent = btn_area,
        x = 120, y = 0, w = 100, h = 40,
        text = "发送HEX",
        style = {
            bg_color = 0x2196F3,
            text_color = 0xFFFFFF,
            radius = 8,
            font_size = 14,
        },
        on_click = ble_slave_win.send_hex
    })

    -- 数据统计（接收和发送并排显示）
    local stats_container = airui.container({
        parent = tx_card,
        x = 0, y = 150, w = 440, h = 20,
        color = 0xFFFFFF
    })

    -- 接收统计（左侧）
    airui.label({
        parent = stats_container,
        x = 0, y = 2, w = 32, h = 16,
        text = "接收:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.rx_bytes = airui.label({
        parent = stats_container,
        x = 32, y = 2, w = 45, h = 16,
        text = tostring(rx_bytes),
        font_size = 11,
        color = 0x333333
    })

    airui.label({
        parent = stats_container,
        x = 77, y = 2, w = 24, h = 16,
        text = "字节",
        font_size = 11,
        color = 0x888888
    })

    airui.label({
        parent = stats_container,
        x = 108, y = 2, w = 28, h = 16,
        text = "包数:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.rx_packets = airui.label({
        parent = stats_container,
        x = 136, y = 2, w = 35, h = 16,
        text = tostring(rx_packets),
        font_size = 11,
        color = 0x333333
    })

    -- 发送统计（右侧）
    airui.label({
        parent = stats_container,
        x = 185, y = 2, w = 32, h = 16,
        text = "发送:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.tx_bytes = airui.label({
        parent = stats_container,
        x = 217, y = 2, w = 45, h = 16,
        text = tostring(tx_bytes),
        font_size = 11,
        color = 0x333333
    })

    airui.label({
        parent = stats_container,
        x = 262, y = 2, w = 24, h = 16,
        text = "字节",
        font_size = 11,
        color = 0x888888
    })

    airui.label({
        parent = stats_container,
        x = 293, y = 2, w = 28, h = 16,
        text = "包数:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.tx_packets = airui.label({
        parent = stats_container,
        x = 321, y = 2, w = 35, h = 16,
        text = tostring(tx_packets),
        font_size = 11,
        color = 0x333333
    })
end

-- 创建设置页面内容
function ble_slave_win.create_settings_content()
    local settings_section = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 0, w = 480, h = 652,
        color = 0xFFFFFF
    })

    -- 创建共享键盘（参考ble_ibeacon实现，使用settings_section作为父容器）
    if not settings_shared_keyboard then
        settings_shared_keyboard = airui.keyboard({
            parent = settings_section,
            x = 0,
            y = -20,
            w = 480,
            h = 200,
            mode = "text",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = on_settings_keyboard_commit
        })
        log.info("BLE Slave", "设置页面键盘创建完成")
    end

    local y_offset = 20
    local config = ble_manager.get_config()

    -- GATT服务信息小标题
    airui.label({
        parent = settings_section,
        x = 20, y = y_offset, w = 440, h = 40,
        text = "GATT服务信息",
        font_size = 16,
        color = 0x333333
    })
    y_offset = y_offset + 28

    -- GATT服务信息卡片（带边框）
    local gatt_card = airui.container({
        parent = settings_section,
        x = 20, y = y_offset, w = 440, h = 150,
        color = 0xF5F5F5,
        radius = 12
    })

    airui.label({
        parent = gatt_card,
        x = 16, y = 16, w = 80, h = 20,
        text = "服务 UUID:",
        font_size = 12,
        color = 0x333333
    })

    airui.label({
        parent = gatt_card,
        x = 100, y = 16, w = 100, h = 20,
        text = "FA00",
        font_size = 12,
        color = 0x00796B
    })

    airui.container({
        parent = gatt_card,
        x = 16, y = 40, w = 408, h = 1,
        color = 0xE0E0E0
    })

    airui.label({
        parent = gatt_card,
        x = 16, y = 48, w = 80, h = 20,
        text = "EA01",
        font_size = 12,
        color = 0x333333
    })

    airui.label({
        parent = gatt_card,
        x = 200, y = 48, w = 220, h = 20,
        text = "NOTIFY | READ | WRITE",
        font_size = 10,
        color = 0x666666
    })

    airui.container({
        parent = gatt_card,
        x = 16, y = 72, w = 408, h = 1,
        color = 0xE0E0E0
    })

    airui.label({
        parent = gatt_card,
        x = 16, y = 80, w = 80, h = 20,
        text = "EA02",
        font_size = 12,
        color = 0x333333
    })

    airui.label({
        parent = gatt_card,
        x = 200, y = 80, w = 220, h = 20,
        text = "WRITE | WRITE_CMD",
        font_size = 10,
        color = 0x666666
    })

    airui.container({
        parent = gatt_card,
        x = 16, y = 104, w = 408, h = 1,
        color = 0xE0E0E0
    })

    airui.label({
        parent = gatt_card,
        x = 16, y = 112, w = 80, h = 20,
        text = "EA03",
        font_size = 12,
        color = 0x333333
    })

    airui.label({
        parent = gatt_card,
        x = 200, y = 112, w = 220, h = 20,
        text = "READ",
        font_size = 10,
        color = 0x666666
    })

    y_offset = y_offset + 170

    -- 广播参数小标题
    airui.label({
        parent = settings_section,
        x = 20, y = y_offset + 10, w = 440, h = 20,
        text = "广播参数",
        font_size = 16,
        color = 0x333333
    })
    y_offset = y_offset + 38

    -- 广播参数卡片（带边框）
    local param_card = airui.container({
        parent = settings_section,
        x = 20, y = y_offset, w = 440, h = 180,
        color = 0xF5F5F5,
        radius = 12
    })

    -- 广播间隔输入
    airui.label({
        parent = param_card,
        x = 16, y = 16, w = 200, h = 20,
        text = "广播间隔 (ms, 20-10240)",
        font_size = 13,
        color = 0x333333
    })

    local adv_input_bg = airui.container({
        parent = param_card,
        x = 16, y = 42, w = 408, h = 40,
        color = 0xFFFFFF,
        radius = 6
    })

    local adv_input = airui.textarea({
        parent = adv_input_bg,
        x = 10, y = 2, w = 388, h = 36,
        text = tostring(config.adv_interval),
        font_size = 14,
        color = 0x333333,
        bg_color = 0x00000000,
        max_length = 10,
        keyboard = settings_shared_keyboard,
        editable = true
    })

    input_values["adv_interval"] = tostring(config.adv_interval)
    settings_ui_controls["adv_interval"] = adv_input

    -- 设备名称输入
    airui.label({
        parent = param_card,
        x = 16, y = 95, w = 200, h = 20,
        text = "设备名称",
        font_size = 13,
        color = 0x333333
    })

    local name_input_bg = airui.container({
        parent = param_card,
        x = 16, y = 121, w = 408, h = 40,
        color = 0xFFFFFF,
        radius = 6
    })

    local name_input = airui.textarea({
        parent = name_input_bg,
        x = 10, y = 2, w = 388, h = 36,
        text = config.device_name,
        font_size = 14,
        color = 0x333333,
        bg_color = 0x00000000,
        max_length = 20,
        keyboard = settings_shared_keyboard,
        editable = true
    })

    input_values["device_name"] = config.device_name
    settings_ui_controls["device_name"] = name_input

    y_offset = y_offset + 200

    -- 保存按钮
    airui.button({
        parent = settings_section,
        x = 140, y = y_offset, w = 200, h = 48,
        text = "保存配置",
        style = {
            bg_color = 0x00796B,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = ble_slave_win.on_settings_save_click
    })
end

-- 保存配置点击
function ble_slave_win.on_settings_save_click()
    log.info("BLE Slave Settings", "点击保存按钮")

    local config = ble_manager.get_config()

    -- 获取输入值
    local adv_interval_str = get_settings_input("adv_interval", config.adv_interval)
    local device_name = get_settings_input("device_name", config.device_name)

    -- 验证广播间隔
    if not validate_number(adv_interval_str, 20, 10240) then
        show_error_dialog("输入错误", "广播间隔必须是20-10240之间的数字")
        return
    end

    -- 验证设备名称
    if not device_name or device_name == "" then
        show_error_dialog("输入错误", "设备名称不能为空")
        return
    end

    if #device_name > 20 then
        show_error_dialog("输入错误", "设备名称长度不能超过20个字符")
        return
    end

    -- 构建新配置
    local new_config = {
        adv_interval = tonumber(adv_interval_str),
        device_name = device_name
    }

    -- 保存配置
    if ble_manager.save_config(new_config) then
        log.info("BLE Slave Settings", "配置保存成功")
        show_confirm_reboot_dialog()
    else
        log.error("BLE Slave Settings", "配置保存失败")
        show_error_dialog("保存失败", "配置保存失败，请重试")
    end
end

-- ==================== BLE 控制函数 ====================

-- 切换广播
function ble_slave_win.toggle_adv()
    local is_adv = ble_manager.get_adv_state()
    
    if is_adv then
        -- 停止广播
        if ble_manager.stop_adv() then
            ble_slave_win.update_adv_ui(false)
            ble_slave_win.add_log("[系统] 广播已停止", 0xB0BEC5)
        end
    else
        -- 开始广播
        if ble_manager.start_adv() then
            ble_slave_win.update_adv_ui(true)
            ble_slave_win.add_log("[系统] 广播已启动", 0xB0BEC5)
        end
    end
end

-- 更新广播UI
function ble_slave_win.update_adv_ui(is_adv)
    -- 更新状态图标
    if ui_controls.status_icon then
        local icon_path = is_adv and "/luadb/ble_open.png" or "/luadb/ble_close.png"
        ui_controls.status_icon:set_src(icon_path)
    end
    if ui_controls.adv_btn then
        ui_controls.adv_btn:set_text(is_adv and "停止广播" or "开始广播")
        local btn_color = is_adv and 0xF44336 or 0x4CAF50
        ui_controls.adv_btn:set_style({ bg_color = btn_color, text_color = 0xFFFFFF, radius = 24 })
    end
    if ui_controls.adv_status then
        ui_controls.adv_status:set_text(is_adv and "广播中" or "已停止")
    end
end

-- 状态变化回调
function ble_slave_win.on_state_change(state_type, state)
    log.info("BLE Slave", "状态变化:", state_type, state)
    
    if state_type == "adv" then
        ble_slave_win.update_adv_ui(state)
    elseif state_type == "conn" then
        -- 先更新广播页面的连接状态
        if ui_controls.conn_status then
            if state then
                ui_controls.conn_status:set_text("已连接")
                ble_slave_win.add_log("[系统] 主机已连接", 0x4CAF50)
            else
                ui_controls.conn_status:set_text("未连接")
                ble_slave_win.add_log("[系统] 主机已断开", 0xFF9800)
            end
        end
        
        -- 更新传输页面连接状态显示（只在当前是传输页面时更新）
        if current_page == "transfer" then
            if ui_controls.transfer_conn_status then
                ui_controls.transfer_conn_status:set_text(state and "已连接到主机" or "未连接到主机")
            end
            if ui_controls.transfer_status_text then
                ui_controls.transfer_status_text:set_text(state and "数据传输中" or "等待连接")
            end
            -- 状态点是container，没有set_style方法，需要销毁重建
            if ui_controls.transfer_status_dot and ui_controls.conn_status_card then
                ui_controls.transfer_status_dot:destroy()
                ui_controls.transfer_status_dot = airui.container({
                    parent = ui_controls.conn_status_card,
                    x = 200, y = 14, w = 8, h = 8,
                    color = state and 0xFFFFFF or 0xBDBDBD,
                    radius = 4
                })
            end
        end
        
        -- 连接成功后自动跳转到数据传输页面（使用sys.publish避免在回调中直接操作UI）
        if state and current_page ~= "transfer" then
            log.info("BLE Slave", "连接成功，发布跳转事件")
            sys.publish("BLE_SLAVE_GOTO_TRANSFER")
        end
    end
end

-- ==================== 数据处理函数 ====================

-- 数据回调（在BLE中断中执行，只发布事件，不直接操作UI）
function ble_slave_win.on_data(data_type, data)
    log.info("BLE Slave", "数据:", data_type, data, type(data))
    
    if data_type == "rx" then
        -- 将数据转换为hex字符串传递（避免传递userdata）
        local hex_data = ""
        if type(data) == "string" then
            for i = 1, #data do
                hex_data = hex_data .. string.format("%02X", string.byte(data, i))
            end
        elseif data and data.toHex then
            hex_data = data:toHex()
        end
        
        -- 发布事件到主循环处理，避免在中断中操作UI
        sys.publish("BLE_SLAVE_RX_DATA", hex_data)
    elseif data_type == "tx" then
        sys.publish("BLE_SLAVE_TX_DATA")
    end
end

-- 处理接收数据（在主循环中执行）
local function handle_rx_data(hex_data)
    -- 检查窗口是否还存在
    if not win_id then
        log.info("BLE Slave", "handle_rx_data: win_id不存在，跳过")
        return
    end
    
    log.info("BLE Slave", "handle_rx_data: 当前页面=" .. current_page .. ", hex_data长度=" .. tostring(#hex_data))
    log.info("BLE Slave", "handle_rx_data: ui_controls.rx_count=" .. tostring(ui_controls.rx_count ~= nil))
    log.info("BLE Slave", "handle_rx_data: ui_controls.rx_display=" .. tostring(ui_controls.rx_display ~= nil))
    
    local rx, tx = ble_manager.get_data_count()
    -- 更新广播页面统计（控件存在时才更新）
    if ui_controls.rx_count then
        ui_controls.rx_count:set_text(tostring(rx))
    end
    
    if hex_data and #hex_data > 0 then
        rx_bytes = rx_bytes + (#hex_data // 2)
        rx_packets = rx_packets + 1
        
        -- 转换为可显示字符
        local data_str = ""
        for i = 1, #hex_data, 2 do
            local byte_hex = hex_data:sub(i, i+1)
            local byte = tonumber(byte_hex, 16) or 0
            if byte >= 32 and byte <= 126 then
                data_str = data_str .. string.char(byte)
            else
                data_str = data_str .. "."
            end
        end
        
        -- 广播页面显示 HEX + 字符串
        local display_str = data_str:gsub("[%c%z]", ".") -- 替换控制字符
        ble_slave_win.add_log(string.format("[接收] %s | %s", hex_data, display_str), 0x81D4FA)
        ble_slave_win.add_transfer_log(string.format("[接收] %s | %s", hex_data, display_str), 0x81D4FA)
        ble_slave_win.update_transfer_stats()
    end
end

-- 处理发送数据（在主循环中执行）
local function handle_tx_data()
    log.info("12121212121212",win_id)
    -- 检查窗口是否还存在
    if not win_id then
        return
    end
    
    local rx, tx = ble_manager.get_data_count()
    -- 更新广播页面统计（控件存在时才更新）
    if ui_controls.tx_count then
        ui_controls.tx_count:set_text(tostring(tx))
    end
    ble_slave_win.add_log("[发送] 数据已发送", 0xAED581)
end

-- 断开连接
function ble_slave_win.disconnect_conn()
    log.info("BLE Slave", "用户点击断开连接")
    if ble_manager and ble_manager.disconnect then
        ble_manager.disconnect()
        ble_slave_win.add_log("[系统] 用户断开连接", 0xFF9800)
    else
        log.error("BLE Slave", "ble_manager 或 disconnect 不存在")
    end
end

-- 将长文本分割成多行（每行最多max_chars个字符）
local function split_text_to_lines(text, max_chars)
    local lines = {}
    local start = 1
    while start <= #text do
        local line_end = math.min(start + max_chars - 1, #text)
        table.insert(lines, text:sub(start, line_end))
        start = line_end + 1
    end
    return lines
end

-- 添加日志
function ble_slave_win.add_log(message, color)
    table.insert(data_logs, {msg = message, color = color or 0xB0BEC5})
    
    -- 限制日志数量
    if #data_logs > MAX_LOGS then
        table.remove(data_logs, 1)
    end
    
    -- 更新日志显示 - 只有当前在广播页面，log_section 和 log_display 都存在时才更新
    if current_page == "adv" and ui_controls.log_section and ui_controls.log_display then
        -- 清除旧日志
        ui_controls.log_display:destroy()
        ui_controls.log_display = airui.container({
            parent = ui_controls.log_section,
            x = 20, y = 50, w = 440, h = 262,
            color = 0x263238,
            radius = 12
        })
        
        -- 显示日志（支持长文本自动换行，每行22px，容器高262px，最多显示12行）
        local max_display_lines = 12
        local current_line = 0
        local start_index = 1
        -- 从后向前遍历，找到能显示完整日志的起始位置
        for i = #data_logs, 1, -1 do
            local log_item = data_logs[i]
            local lines_needed = math.ceil(#log_item.msg / 50)
            if lines_needed < 1 then lines_needed = 1 end
            current_line = current_line + lines_needed
            if current_line > max_display_lines then
                start_index = i + 1
                break
            end
            start_index = i
        end
        
        -- 显示日志（从起始位置开始）
        current_line = 0
        for i = start_index, #data_logs do
            local log_item = data_logs[i]
            local text_lines = split_text_to_lines(log_item.msg, 50)
            for _, line_text in ipairs(text_lines) do
                if current_line >= max_display_lines then break end
                airui.label({
                    parent = ui_controls.log_display,
                    x = 16, y = 10 + current_line * 22, w = 408, h = 20,
                    text = line_text,
                    font_size = 12,
                    color = log_item.color
                })
                current_line = current_line + 1
            end
        end
    end
end

-- ==================== 日志函数 ====================

-- 添加传输日志
function ble_slave_win.add_transfer_log(message, color)
    table.insert(transfer_data_logs, {msg = message, color = color or 0xB0BEC5})
    
    -- 限制日志数量
    if #transfer_data_logs > MAX_TRANSFER_LOGS then
        table.remove(transfer_data_logs, 1)
    end
    
    -- 更新日志显示 - 只有当前在传输页面，rx_display 和 rx_card 都存在时才更新
    if current_page == "transfer" then
        ble_slave_win.refresh_transfer_log_display()
    end
end

-- 刷新传输日志显示
function ble_slave_win.refresh_transfer_log_display()
    if current_page == "transfer" and ui_controls.rx_display and ui_controls.rx_card then
        -- 保存父容器引用
        local parent = ui_controls.rx_card
        
        -- 清除旧日志容器
        ui_controls.rx_display:destroy()
        
        -- 创建新的日志显示容器（高度与create_transfer_content中一致）
        ui_controls.rx_display = airui.container({
            parent = parent,
            x = 0, y = 30, w = 440, h = 290,
            color = 0x263238,
            radius = 8
        })
        
        -- 显示日志（支持长文本自动换行，每行18px，容器高290px，最多显示16行）
        local max_display_lines = 16
        local current_line = 0
        local start_index = 1
        -- 从后向前遍历，找到能显示完整日志的起始位置
        for i = #transfer_data_logs, 1, -1 do
            local log_item = transfer_data_logs[i]
            local lines_needed = math.ceil(#log_item.msg / 55)
            if lines_needed < 1 then lines_needed = 1 end
            current_line = current_line + lines_needed
            if current_line > max_display_lines then
                start_index = i + 1
                break
            end
            start_index = i
        end
        
        -- 显示日志（从起始位置开始）
        current_line = 0
        for i = start_index, #transfer_data_logs do
            local log_item = transfer_data_logs[i]
            local text_lines = split_text_to_lines(log_item.msg, 55)
            for _, line_text in ipairs(text_lines) do
                if current_line >= max_display_lines then break end
                airui.label({
                    parent = ui_controls.rx_display,
                    x = 10, y = 8 + current_line * 18, w = 420, h = 16,
                    text = line_text,
                    font_size = 11,
                    color = log_item.color
                })
                current_line = current_line + 1
            end
        end
    end
end

-- 清空接收数据
function ble_slave_win.clear_rx()
    transfer_data_logs = {}
    rx_bytes = 0
    rx_packets = 0
    
    -- 只有当前在传输页面，控件都存在时才更新
    if current_page == "transfer" and ui_controls.rx_display and ui_controls.rx_card then
        ui_controls.rx_display:destroy()
        ui_controls.rx_display = airui.container({
            parent = ui_controls.rx_card,
            x = 0, y = 30, w = 440, h = 290,
            color = 0x263238,
            radius = 8
        })
        ble_slave_win.add_transfer_log("[系统] 等待接收数据...", 0xB0BEC5)
    end
    if current_page == "transfer" and ui_controls.rx_bytes then
        ui_controls.rx_bytes:set_text("0")
    end
    if current_page == "transfer" and ui_controls.rx_packets then
        ui_controls.rx_packets:set_text("0")
    end
end

-- 获取输入框文本
local function get_send_input_text()
    if ui_controls.send_input and ui_controls.send_input.get_text then
        return ui_controls.send_input:get_text()
    end
    return ""
end

-- 设置输入框文本
local function set_send_input_text(text)
    if ui_controls.send_input and ui_controls.send_input.set_text then
        ui_controls.send_input:set_text(text)
    end
end

-- ==================== 数据发送函数 ====================

-- 发送文本数据
function ble_slave_win.send_text()
    if not ui_controls.send_input then return end
    
    local text = get_send_input_text()
    if not text or text == "" then return end
    
    -- 使用选择的发送UUID
    local _, target_char_uuid, target_char_props = ble_slave_win.get_tx_uuid()
    if not target_char_uuid then
        target_char_uuid = "EA01"
        target_char_props = 0x40 | 0x08 | 0x10
    end
    
    if ble_manager.send_data(text, target_char_uuid, target_char_props) then
        tx_bytes = tx_bytes + #text
        tx_packets = tx_packets + 1
        ble_slave_win.update_transfer_stats()
        ble_slave_win.add_transfer_log("[发送] " .. text, 0xAED581)
        set_send_input_text("")
    else
        ble_slave_win.add_transfer_log("[错误] 发送失败", 0xF44336)
    end
end

-- 发送HEX数据
function ble_slave_win.send_hex()
    if not ui_controls.send_input then return end
    
    local hex_str = get_send_input_text()
    if not hex_str or hex_str == "" then return end
    
    -- 移除空格
    hex_str = hex_str:gsub("%s+", "")
    
    -- 检查是否是有效的HEX
    if #hex_str % 2 ~= 0 then
        ble_slave_win.add_transfer_log("[错误] HEX长度必须是偶数", 0xF44336)
        return
    end
    
    local data = string.fromHex(hex_str)
    
    -- 转换为ASCII显示
    local ascii_str = ""
    for i = 1, #data do
        local byte = string.byte(data, i)
        if byte >= 32 and byte <= 126 then
            ascii_str = ascii_str .. string.char(byte)
        else
            ascii_str = ascii_str .. "."
        end
    end
    
    -- 使用选择的发送UUID
    local _, target_char_uuid, target_char_props = ble_slave_win.get_tx_uuid()
    if not target_char_uuid then
        target_char_uuid = "EA01"
        target_char_props = 0x40 | 0x08 | 0x10
    end
    
    if ble_manager.send_data(data, target_char_uuid, target_char_props) then
        tx_bytes = tx_bytes + #data
        tx_packets = tx_packets + 1
        ble_slave_win.update_transfer_stats()
        ble_slave_win.add_transfer_log(string.format("[发送] %s | %s", hex_str, ascii_str), 0xAED581)
        set_send_input_text("")
    else
        ble_slave_win.add_transfer_log("[错误] 发送失败", 0xF44336)
    end
end

-- ==================== 统计和导航函数 ====================

-- 更新传输统计
function ble_slave_win.update_transfer_stats()
    -- 只要控件存在就更新（不管当前在哪个页面，确保统计数据实时同步）
    if ui_controls.rx_bytes then
        ui_controls.rx_bytes:set_text(tostring(rx_bytes))
    end
    if ui_controls.rx_packets then
        ui_controls.rx_packets:set_text(tostring(rx_packets))
    end
    if ui_controls.tx_bytes then
        ui_controls.tx_bytes:set_text(tostring(tx_bytes))
    end
    if ui_controls.tx_packets then
        ui_controls.tx_packets:set_text(tostring(tx_packets))
    end
end

-- 返回
function ble_slave_win.go_back()
    log.info("BLE Slave", "返回上一页，当前页面: ", current_page)
    
    -- 如果当前不在广播页，先返回广播页
    if current_page ~= "adv" then
        ble_slave_win.switch_page("adv")
        return
    end
    
    -- 在广播页时，关闭窗口返回首页
    log.info("BLE Slave", "关闭窗口返回首页")

    if ble_manager and ble_manager.deinit then
        ble_manager.deinit()
    end
    -- 关闭窗口
    if win_id then
        exwin.close(win_id)
    end
end

-- ==================== 生命周期函数 ====================

-- 销毁
function ble_slave_win.on_destroy()
    log.info("BLE Slave", "销毁界面")
    
    if ble_manager and ble_manager.deinit then
        ble_manager.deinit()
    end
    
    -- 销毁键盘
    if shared_keyboard then
        shared_keyboard:destroy()
        shared_keyboard = nil
    end
    if settings_shared_keyboard then
        settings_shared_keyboard:destroy()
        settings_shared_keyboard = nil
    end
    
    if ui_controls.main_container then
        ui_controls.main_container:destroy()
        ui_controls.main_container = nil
    end
end

-- 打开窗口
local function open_handler()
    log.info("BLE Slave", "打开窗口")
    
    win_id = exwin.open({
        on_create = ble_slave_win.on_create,
        on_destroy = ble_slave_win.on_destroy,
    })
end

-- 解析属性为可读字符串
local function parse_properties(properties)
    local prop_map = {
        [0x08] = "Read",
        [0x10] = "Write",
        [0x20] = "Indicate",
        [0x40] = "Notify",
        [0x80] = "WriteCmd"
    }
    local result = {}
    for bit, name in pairs(prop_map) do
        if properties & bit ~= 0 then
            table.insert(result, name)
        end
    end
    return table.concat(result, ", ")
end

-- ==================== UUID 选择弹窗 ====================

-- 显示UUID选择弹窗
function ble_slave_win.show_uuid_selector()
    
    -- 如果弹窗已存在，先销毁
    if uuid_selector_dialog then
        uuid_selector_dialog:destroy()
        uuid_selector_dialog = nil
    end
    
    -- 创建弹窗背景遮罩
    local mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x000000,
        alpha = 128
    })
    
    -- 创建弹窗容器
    uuid_selector_dialog = airui.container({
        parent = airui.screen,
        x = 40, y = 150, w = 400, h = 500,
        color = 0xFFFFFF,
        radius = 12
    })
    
    -- 标题
    airui.label({
        parent = uuid_selector_dialog,
        x = 0, y = 15, w = 400, h = 30,
        text = "选择发送UUID",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 关闭按钮
    local close_btn = airui.button({
        parent = uuid_selector_dialog,
        x = 350, y = 10, w = 40, h = 40,
        text = "×",
        style = {
            bg_color = 0xFF5722,
            text_color = 0xFFFFFF,
            radius = 20
        },
        on_click = function()
            on_keyboard_hide_click()
            if uuid_selector_dialog then
                uuid_selector_dialog:destroy()
                uuid_selector_dialog = nil
            end
            if mask then
                mask:destroy()
            end
        end
    })
    
    -- 创建可滚动的UUID列表区域
    local list_area = airui.container({
        parent = uuid_selector_dialog,
        x = 10, y = 60, w = 380, h = 430,
        color = 0xF5F5F5,
        radius = 8
    })
    
    -- GATT数据库定义（从ble_manager获取）
    local att_db = {
        {uuid = "FA00", name = "主服务"},
        {uuid = "EA01", name = "特征值1 (Notify/Read/Write)", props = 0x40 | 0x08 | 0x10},
        {uuid = "EA02", name = "特征值2 (Write/WriteCmd)", props = 0x10 | 0x80},
        {uuid = "EA03", name = "特征值3 (Read)", props = 0x08}
    }
    
    local y_offset = 10
    
    -- 服务标题
    airui.label({
        parent = list_area,
        x = 10, y = y_offset, w = 360, h = 24,
        text = "服务: FA00",
        font_size = 14,
        color = 0x2196F3
    })
    y_offset = y_offset + 30
    
    -- 特征值列表
    for i = 2, #att_db do
        local item = att_db[i]
        local has_write = (item.props & 0x10) ~= 0 or (item.props & 0x80) ~= 0
        local has_notify = (item.props & 0x40) ~= 0
        local has_read = (item.props & 0x08) ~= 0
        
        -- 特征值项背景
        local item_bg = airui.container({
            parent = list_area,
            x = 10, y = y_offset, w = 360, h = 70,
            color = 0xFFFFFF,
            radius = 6
        })
        
        -- 特征值UUID
        airui.label({
            parent = item_bg,
            x = 10, y = 8, w = 200, h = 20,
            text = item.uuid,
            font_size = 14,
            color = 0x333333
        })
        
        -- 属性标签
        local prop_color = 0x999999
        if has_write and has_notify then
            prop_color = 0x4CAF50  -- 绿色：可读写
        elseif has_write then
            prop_color = 0x2196F3  -- 蓝色：可写
        elseif has_notify then
            prop_color = 0xFF9800  -- 橙色：可接收
        end
        
        airui.label({
            parent = item_bg,
            x = 10, y = 32, w = 240, h = 16,
            text = parse_properties(item.props),
            font_size = 11,
            color = prop_color
        })
        
        -- 检查是否已选中
        local is_selected = (tx_char_uuid == item.uuid)
        
        -- 选择按钮
        local select_btn = airui.button({
            parent = item_bg,
            x = 280, y = 15, w = 70, h = 40,
            text = is_selected and "已选" or "选择",
            style = {
                bg_color = is_selected and 0x4CAF50 or 0x2196F3,
                text_color = 0xFFFFFF,
                radius = 20
            },
            on_click = function() on_uuid_item_select(item, mask) end
        })
        
        y_offset = y_offset + 80
    end
end

-- 更新UUID显示
function ble_slave_win.update_uuid_display()
    if ui_controls.tx_uuid_label then
        local tx_text = tx_char_uuid and string.format("发送: %s", tx_char_uuid) or "发送: 未选择"
        ui_controls.tx_uuid_label:set_text(tx_text)
    end
end

-- 获取发送UUID
function ble_slave_win.get_tx_uuid()
    return tx_service_uuid, tx_char_uuid, tx_char_props
end

-- ==================== 模块初始化 ====================

-- 订阅打开窗口事件
sys.subscribe("OPEN_BLE_SLAVE_WIN", open_handler)

-- 订阅跳转到传输页面事件（避免在BLE回调中直接操作UI）
sys.subscribe("BLE_SLAVE_GOTO_TRANSFER", function()
    -- 检查窗口是否还存在
    if not win_id then
        return
    end
    log.info("BLE Slave", "收到跳转事件，当前页面:", current_page)
    if current_page ~= "transfer" and ble_slave_win and ble_slave_win.switch_page then
        sys.timerStart(function()
            if win_id and ble_slave_win.switch_page then
                ble_slave_win.switch_page("transfer")
            end
        end, 100)
    end
end)

-- 订阅数据处理事件（避免在BLE中断中直接操作UI）
sys.subscribe("BLE_SLAVE_RX_DATA", handle_rx_data)
sys.subscribe("BLE_SLAVE_TX_DATA", handle_tx_data)

-- 设为全局变量
_G.ble_slave_win = ble_slave_win

return ble_slave_win
