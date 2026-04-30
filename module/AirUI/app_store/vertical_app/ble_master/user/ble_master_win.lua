--[[
@module  ble_master_win
@summary BLE主机应用主界面
@version 1.0.0
@date    2026.04.10
@author  王世豪
@usage
BLE主机应用主界面，负责显示和控制BLE主机功能
--]]

-- ==================== 模块导入 ====================
local ble_manager = require "ble_manager"

-- ==================== 工具函数 ====================
local function round(num)
    return math.floor(num + 0.5)
end

-- 解析特征值属性为可读字符串
local function parse_properties(props)
    local props_list = {}
    if (props & 0x01) ~= 0 then table.insert(props_list, "Broadcast") end
    if (props & 0x02) ~= 0 then table.insert(props_list, "Read") end
    if (props & 0x04) ~= 0 then table.insert(props_list, "WriteNR") end
    if (props & 0x08) ~= 0 then table.insert(props_list, "Write") end
    if (props & 0x10) ~= 0 then table.insert(props_list, "Notify") end
    if (props & 0x20) ~= 0 then table.insert(props_list, "Indicate") end
    if (props & 0x40) ~= 0 then table.insert(props_list, "Auth") end
    if (props & 0x80) ~= 0 then table.insert(props_list, "ExtProp") end
    return table.concat(props_list, " / ")
end

-- 格式化UUID为带横杠的标准格式
local function format_uuid(uuid)
    if not uuid or #uuid ~= 32 then
        return uuid
    end
    -- 格式: 8-4-4-4-12
    return string.format("%s-%s-%s-%s-%s",
        uuid:sub(1, 8),
        uuid:sub(9, 12),
        uuid:sub(13, 16),
        uuid:sub(17, 20),
        uuid:sub(21, 32)
    )
end

-- ==================== 模块定义 ====================
local ble_master_win = {}

-- ==================== 常量定义 ====================
local MAX_LOGS = 50
local MAX_DEVICE_ITEMS = 20
local DEVICES_PER_PAGE = 6  -- 每页显示设备数

-- ==================== 状态变量 ====================
local win_id = nil
local current_page = "scan"
local is_scanning = false
local device_count = 0
local conn_count = 0
local rx_count = 0
local device_page_index = 1  -- 当前设备页码

-- ==================== UI刷新节流控制 ====================
local last_device_update_time = 0
local DEVICE_UPDATE_INTERVAL = 300  -- 设备列表刷新间隔(ms)，300ms平衡流畅度和性能
local pending_device_update = false  -- 是否有待处理的刷新

-- ==================== UI控件 ====================
local ui_controls = {}
local device_items = {}

-- ==================== 共享键盘 ====================
local shared_keyboard = nil
local settings_shared_keyboard = nil

-- ==================== 数据存储 ====================
local discovered_devices = {}

-- ==================== 数据传输页面变量（提前定义，供回调使用） ====================
local data_transfer_vars = {
    is_connected = false,
    notify_enabled = false,
    rx_bytes = 0,
    rx_packets = 0,
    tx_bytes = 0,
    tx_packets = 0,
    rx_service_uuid = nil,
    rx_char_uuid = nil,
    tx_service_uuid = nil,
    tx_char_uuid = nil,
    discovered_services = {},
    service_char_map = {}
}

-- ==================== 回调对象 ====================
local ble_callbacks = {}

-- ==================== 颜色常量 ====================
local COLORS = {
    PRIMARY = 0x3F51B5,
    PRIMARY_LIGHT = 0x90CAF9,
    SUCCESS = 0x4CAF50,
    WARNING = 0xFF9800,
    DANGER = 0xFF5252,
    TEXT_PRIMARY = 0x333333,
    TEXT_SECONDARY = 0x888888,
    TEXT_LIGHT = 0xAAAAAA,
    BG_GRAY = 0xF8F9FA,
    WHITE = 0xFFFFFF,
    DIVIDER = 0xEEEEEE
}

-- ==================== 工具函数 ====================

local function update_nav_buttons()
    if ui_controls.nav_scan_label then
        ui_controls.nav_scan_label:set_color(current_page == "scan" and COLORS.PRIMARY or COLORS.TEXT_SECONDARY)
    end
    if ui_controls.nav_transfer_label then
        ui_controls.nav_transfer_label:set_color(current_page == "data" and COLORS.PRIMARY or COLORS.TEXT_SECONDARY)
    end
    if ui_controls.nav_settings_label then
        ui_controls.nav_settings_label:set_color(current_page == "settings" and COLORS.PRIMARY or COLORS.TEXT_SECONDARY)
    end
end

local function update_scan_button()
    if not ui_controls.scan_btn then return end
    
    if is_scanning then
        ui_controls.scan_btn:set_text("停止扫描")
        ui_controls.scan_btn:set_style({
            bg_color = COLORS.WARNING
        })
    else
        ui_controls.scan_btn:set_text("开始扫描")
        ui_controls.scan_btn:set_style({
            bg_color = COLORS.SUCCESS
        })
    end
end

local function update_status_panel()
    if ui_controls.device_count_label then
        ui_controls.device_count_label:set_text(tostring(device_count))
    end
end

-- ==================== 键盘回调函数 ====================
local function on_keyboard_commit()
    log.info("BLE_MASTER_WIN", "键盘提交")
    if shared_keyboard and shared_keyboard.hide then
        shared_keyboard:hide()
    end
end

local function on_input_click_show_keyboard()
    if shared_keyboard and shared_keyboard.show then
        shared_keyboard:show()
    end
end

-- 连接状态弹窗相关变量
local connecting_dialog = nil
local connecting_mask = nil

-- 显示连接中弹窗
local function show_connecting_dialog(device_name)
    if connecting_mask then
        connecting_mask:destroy()
        connecting_mask = nil
    end
    if connecting_dialog then
        connecting_dialog:destroy()
        connecting_dialog = nil
    end
    
    connecting_mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000,
        alpha = 80
    })
    
    connecting_dialog = airui.container({
        parent = connecting_mask,
        x = 40,
        y = 280,
        w = 400,
        h = 140,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = connecting_dialog,
        x = 0,
        y = 20,
        w = 400,
        h = 24,
        text = "连接中...",
        font_size = 18,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = connecting_dialog,
        x = 0,
        y = 55,
        w = 400,
        h = 20,
        text = "正在连接: " .. (device_name or "Unknown"),
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 添加旋转动画指示器（使用简单的圆点表示）
    airui.label({
        parent = connecting_dialog,
        x = 0,
        y = 90,
        w = 400,
        h = 30,
        text = "请稍候",
        font_size = 12,
        color = COLORS.PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 显示连接成功弹窗
local function show_connect_success_dialog(callback)
    if connecting_mask then
        connecting_mask:destroy()
        connecting_mask = nil
    end
    if connecting_dialog then
        connecting_dialog:destroy()
        connecting_dialog = nil
    end
    
    local mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000,
        alpha = 80
    })
    
    local dialog = airui.container({
        parent = mask,
        x = 40,
        y = 280,
        w = 400,
        h = 140,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = dialog,
        x = 0,
        y = 25,
        w = 400,
        h = 30,
        text = "连接成功",
        font_size = 20,
        color = COLORS.SUCCESS,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = dialog,
        x = 0,
        y = 70,
        w = 400,
        h = 20,
        text = "正在跳转到传输页面...",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 1秒后自动关闭并执行回调
    local function auto_close_timer()
        mask:destroy()
        if callback then
            callback()
        end
    end
    sys.timerStart(auto_close_timer, 1000)
end

-- 关闭连接弹窗
local function close_connecting_dialog()
    if connecting_mask then
        connecting_mask:destroy()
        connecting_mask = nil
    end
    if connecting_dialog then
        connecting_dialog:destroy()
        connecting_dialog = nil
    end
end

-- 显示连接确认弹窗
local function show_connect_dialog(device)
    local mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000,
        alpha = 80
    })
    
    local dialog = airui.container({
        parent = mask,
        x = 40,
        y = 250,
        w = 400,
        h = 200,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = dialog,
        x = 0,
        y = 20,
        w = 400,
        h = 24,
        text = "连接设备",
        font_size = 18,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = dialog,
        x = 20,
        y = 60,
        w = 360,
        h = 40,
        text = "设备: " .. device.name .. "\nMAC: " .. device.mac,
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local function on_cancel_click()
        mask:destroy()
    end
    
    local cancel_btn = airui.button({
        parent = dialog,
        x = 40,
        y = 130,
        w = 140,
        h = 44,
        text = "取消",
        style = {
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_PRIMARY,
            radius = 8
        },
        on_click = on_cancel_click
    })
    
    local function on_connect_click()
        mask:destroy()
        -- 显示连接中弹窗
        show_connecting_dialog(device.name)
        -- 开始连接，确保addr_type是数字类型
        local addr_type_num = tonumber(device.addr_type) or 0
        ble_manager.connect_device(device.mac, addr_type_num)
    end
    
    local connect_btn = airui.button({
        parent = dialog,
        x = 220,
        y = 130,
        w = 140,
        h = 44,
        text = "连接",
        style = {
            bg_color = COLORS.PRIMARY,
            text_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_connect_click
    })
end

-- 设备项点击回调
local function on_device_item_click(device)
    log.info("BLE_MASTER_WIN", "点击设备:", device.name, device.mac)
    show_connect_dialog(device)
end

local function create_device_item(parent, y, device)
    local function on_item_click()
        on_device_item_click(device)
    end
    
    local item = airui.button({
        parent = parent,
        x = 0,
        y = y,
        w = 480,
        h = 68,
        style = {
            bg_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_item_click
    })

    airui.image({
        parent = item,
        x = 12,
        y = 2,
        w = 48,
        h = 48,
        src = "/luadb/slave.png"
    })

    airui.label({
        parent = item,
        x = 72,
        y = 4,
        w = 220,
        h = 22,
        text = device.name,
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = item,
        x = 72,
        y = 30,
        w = 220,
        h = 16,
        text = device.mac,
        font_size = 12,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    local rssi_color = device.rssi > -70 and COLORS.SUCCESS or
                       (device.rssi > -85 and COLORS.WARNING or COLORS.DANGER)
    airui.label({
        parent = item,
        x = 320,
        y = 10,
        w = 100,
        h = 18,
        text = device.rssi .. " dBm",
        font_size = 15,
        color = rssi_color,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = item,
        x = 320,
        y = 30,
        w = 100,
        h = 14,
        text = "信号强度",
        font_size = 10,
        color = COLORS.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    return item
end

-- 存储设备项与MAC的映射关系，用于增量更新
local device_item_map = {}

-- 添加单个设备项到列表（用于增量更新）
local function add_single_device_item(device)
    if not ui_controls.device_list_container then return end
    
    -- 检查是否已存在
    if device_item_map[device.mac] then
        -- 更新现有项的RSSI显示
        local existing_item = device_item_map[device.mac]
        -- 这里可以通过存储引用更新标签，简化处理：重新创建该项
        existing_item:destroy()
    end
    
    -- 计算当前列表中的位置
    local current_count = #device_items
    if current_count >= DEVICES_PER_PAGE then
        -- 当前页已满，不添加新项，只更新页码信息
        local devices_array = {}
        for mac, dev in pairs(discovered_devices) do
            table.insert(devices_array, dev)
        end
        local total_pages = math.ceil(#devices_array / DEVICES_PER_PAGE)
        if ui_controls.page_info_label then
            ui_controls.page_info_label:set_text(string.format("%d/%d", device_page_index, total_pages))
        end
        -- 更新下一页按钮状态
        if ui_controls.next_page_btn then
            ui_controls.next_page_btn:set_style({
                bg_color = device_page_index < total_pages and COLORS.PRIMARY or 0xCCCCCC,
                text_color = COLORS.WHITE
            })
        end
        return
    end
    
    -- 创建新设备项
    local y = current_count * 72
    local item = create_device_item(ui_controls.device_list_container, y, device)
    table.insert(device_items, item)
    device_item_map[device.mac] = item
    
    -- 更新页码显示
    local devices_array = {}
    for mac, dev in pairs(discovered_devices) do
        table.insert(devices_array, dev)
    end
    local total_pages = math.ceil(#devices_array / DEVICES_PER_PAGE)
    if ui_controls.page_info_label then
        ui_controls.page_info_label:set_text(string.format("%d/%d", device_page_index, total_pages))
    end
end

-- 清空设备项映射
local function clear_device_item_map()
    device_item_map = {}
end

local function update_device_list()
    for _, item in ipairs(device_items) do
        if item then
            item:destroy()
        end
    end
    device_items = {}
    clear_device_item_map()  -- 清空设备项映射

    if not ui_controls.device_list_container then return end

    -- 将设备转换为数组以便分页
    local devices_array = {}
    for mac, device in pairs(discovered_devices) do
        table.insert(devices_array, device)
    end

    -- 处理无设备情况
    if #devices_array == 0 then
        if ui_controls.page_info_label then
            ui_controls.page_info_label:set_text("0/0")
        end
        if ui_controls.prev_page_btn then
            ui_controls.prev_page_btn:set_style({
                bg_color = 0xCCCCCC,
                text_color = COLORS.WHITE
            })
        end
        if ui_controls.next_page_btn then
            ui_controls.next_page_btn:set_style({
                bg_color = 0xCCCCCC,
                text_color = COLORS.WHITE
            })
        end
        return
    end

    -- 计算总页数
    local total_pages = math.ceil(#devices_array / DEVICES_PER_PAGE)
    if device_page_index > total_pages then
        device_page_index = total_pages
    end
    if device_page_index < 1 then
        device_page_index = 1
    end

    -- 更新页码显示
    if ui_controls.page_info_label then
        ui_controls.page_info_label:set_text(string.format("%d/%d", device_page_index, total_pages))
    end

    -- 更新按钮状态
    if ui_controls.prev_page_btn then
        ui_controls.prev_page_btn:set_style({
            bg_color = device_page_index > 1 and COLORS.PRIMARY or 0xCCCCCC,
            text_color = COLORS.WHITE
        })
    end
    if ui_controls.next_page_btn then
        ui_controls.next_page_btn:set_style({
            bg_color = device_page_index < total_pages and COLORS.PRIMARY or 0xCCCCCC,
            text_color = COLORS.WHITE
        })
    end

    -- 显示当前页的设备
    local start_index = (device_page_index - 1) * DEVICES_PER_PAGE + 1
    local end_index = math.min(start_index + DEVICES_PER_PAGE - 1, #devices_array)

    local y = 0
    for i = start_index, end_index do
        local device = devices_array[i]
        if device then
            local item = create_device_item(ui_controls.device_list_container, y, device)
            table.insert(device_items, item)
            y = y + 72
        end
    end
end

-- 上一页按钮点击
local function on_prev_page_click()
    if device_count == 0 then return end
    if device_page_index > 1 then
        device_page_index = device_page_index - 1
        update_device_list()
    end
end

-- 下一页按钮点击
local function on_next_page_click()
    if device_count == 0 then return end
    local devices_array = {}
    for mac, device in pairs(discovered_devices) do
        table.insert(devices_array, device)
    end
    local total_pages = math.ceil(#devices_array / DEVICES_PER_PAGE)
    if device_page_index < total_pages then
        device_page_index = device_page_index + 1
        update_device_list()
    end
end

local function on_scan_state_change(scanning)
    log.info("BLE_MASTER_WIN", "扫描状态变化:", scanning)
    is_scanning = scanning
    update_scan_button()
end

-- 更新Notify按钮显示
local function update_notify_button()
    if not ui_controls.notify_btn then return end

    local has_notify = false
    local rx_svc = data_transfer_vars.rx_service_uuid
    local rx_char = data_transfer_vars.rx_char_uuid
    if rx_svc and rx_char and data_transfer_vars.service_char_map[rx_svc] and data_transfer_vars.service_char_map[rx_svc][rx_char] then
        local props = data_transfer_vars.service_char_map[rx_svc][rx_char]
        has_notify = (props & 0x40) ~= 0
    end

    if not has_notify then
        ui_controls.notify_btn:set_text("Notify:关")
        ui_controls.notify_btn:set_style({
            bg_color = 0xCCCCCC,
            text_color = COLORS.WHITE
        })
    else
        ui_controls.notify_btn:set_text(data_transfer_vars.notify_enabled and "Notify:开" or "Notify:关")
        ui_controls.notify_btn:set_style({
            bg_color = data_transfer_vars.notify_enabled and COLORS.SUCCESS or 0x999999,
            text_color = COLORS.WHITE
        })
    end
end

-- 更新连接状态卡片
local function update_conn_status_card()
    if not ui_controls.conn_status_card then return end

    if data_transfer_vars.is_connected then
        ui_controls.conn_status_text:set_text("已连接到从机")
        if ui_controls.transfer_status_text then
            ui_controls.transfer_status_text:set_text("数据传输中")
        end
    else
        ui_controls.conn_status_text:set_text("未连接到从机")
        if ui_controls.transfer_status_text then
            ui_controls.transfer_status_text:set_text("等待连接")
        end
        data_transfer_vars.notify_enabled = false
    end
    update_notify_button()
end

-- 带节流的设备列表刷新
local function throttle_update_device_list()
    local current_time = mcu.ticks and mcu.ticks() or (os.time() * 1000)
    
    if current_time - last_device_update_time >= DEVICE_UPDATE_INTERVAL then
        -- 立即刷新
        last_device_update_time = current_time
        pending_device_update = false
        update_device_list()
    else
        -- 延迟刷新，避免频繁更新UI
        if not pending_device_update then
            pending_device_update = true
            local delay = DEVICE_UPDATE_INTERVAL - (current_time - last_device_update_time)
            local function delayed_update()
                pending_device_update = false
                last_device_update_time = mcu.ticks and mcu.ticks() or (os.time() * 1000)
                update_device_list()
            end
            sys.timerStart(delayed_update, delay)
        end
    end
end

local function on_device_found(device)
    log.info("BLE_MASTER_WIN", "发现设备:", device.name)
    local is_new_device = discovered_devices[device.mac] == nil
    discovered_devices[device.mac] = device
    device_count = ble_manager.get_device_count()
    update_status_panel()
    
    -- 方案2：如果是新设备且当前页未满，只添加单个项
    if is_new_device and #device_items < DEVICES_PER_PAGE then
        add_single_device_item(device)
    else
        -- 方案1：使用节流刷新
        throttle_update_device_list()
    end
end

-- 跳转到传输页面的函数
local function switch_to_transfer_page()
    ble_master_win.switch_page("data")
end

local function on_conn_state_change(connected)
    log.info("BLE_MASTER_WIN", "连接状态变化:", connected)
    conn_count = connected and 1 or 0
    data_transfer_vars.is_connected = connected
    update_status_panel()
    update_conn_status_card()

    if connected then
        -- 连接成功，等待GATT发现完成后再显示成功弹窗
        log.info("BLE_MASTER_WIN", "连接成功，等待GATT服务发现...")
        -- GATT发现完成后会在 on_services_discovered 中处理
    else
        -- 断开连接时清空UUID选择
        data_transfer_vars.rx_service_uuid = nil
        data_transfer_vars.rx_char_uuid = nil
        data_transfer_vars.tx_service_uuid = nil
        data_transfer_vars.tx_char_uuid = nil
        data_transfer_vars.notify_enabled = false

        -- 关闭任何打开的连接弹窗
        close_connecting_dialog()
    end
end

-- 更新数据统计显示
local function update_data_stats()
    if ui_controls.rx_bytes_label then
        ui_controls.rx_bytes_label:set_text(tostring(data_transfer_vars.rx_bytes))
    end
    if ui_controls.rx_packets_label then
        ui_controls.rx_packets_label:set_text(tostring(data_transfer_vars.rx_packets))
    end
    if ui_controls.tx_bytes_label then
        ui_controls.tx_bytes_label:set_text(tostring(data_transfer_vars.tx_bytes))
    end
    if ui_controls.tx_packets_label then
        ui_controls.tx_packets_label:set_text(tostring(data_transfer_vars.tx_packets))
    end
end

-- 接收数据历史缓冲区
local rx_data_history = {}
local MAX_RX_HISTORY = 100  -- 最多保留100条记录

-- 分割文本为多行（每行最大长度）
local function split_text_to_lines(text, max_len)
    local lines = {}
    local start = 1
    while start <= #text do
        local line = text:sub(start, start + max_len - 1)
        table.insert(lines, line)
        start = start + max_len
    end
    if #lines == 0 then
        table.insert(lines, "")
    end
    return lines
end

-- 刷新接收数据显示
local function refresh_rx_display()
    if not ui_controls.rx_data_area or not ui_controls.rx_border then return end

    -- 保存父容器引用
    local parent = ui_controls.rx_border

    -- 清除旧容器
    ui_controls.rx_data_area:destroy()

    -- 创建新的显示容器（白底）
    ui_controls.rx_data_area = airui.container({
        parent = parent,
        x = 2,
        y = 2,
        w = 420,
        h = 276,
        color = 0xFFFFFF,
        radius = 6
    })

    -- 显示日志（每行16px，容器高276px，最多显示17行）
    local max_display_lines = 17
    local current_line = 0
    local start_index = 1

    -- 从后向前遍历，找到能显示完整日志的起始位置
    for i = #rx_data_history, 1, -1 do
        local log_item = rx_data_history[i]
        local lines_needed = math.ceil(#log_item / 50)
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
    for i = start_index, #rx_data_history do
        local log_item = rx_data_history[i]
        local text_lines = split_text_to_lines(log_item, 50)
        for _, line_text in ipairs(text_lines) do
            if current_line >= max_display_lines then break end
            airui.label({
                parent = ui_controls.rx_data_area,
                x = 8,
                y = 6 + current_line * 16,
                w = 404,
                h = 14,
                text = line_text,
                font_size = 11,
                color = 0x333333
            })
            current_line = current_line + 1
        end
    end
end

-- 添加接收数据到显示区域
local function add_rx_data_to_display(data)
    if not data then return end

    data_transfer_vars.rx_bytes = data_transfer_vars.rx_bytes + #data
    data_transfer_vars.rx_packets = data_transfer_vars.rx_packets + 1
    update_data_stats()

    -- 转换为可显示字符串
    local data_str = ""
    for i = 1, #data do
        local byte = string.byte(data, i)
        if byte >= 32 and byte <= 126 then
            data_str = data_str .. string.char(byte)
        else
            data_str = data_str .. "."
        end
    end

    local time_str = os.date("%H:%M:%S")
    local log_entry = string.format("[%s] %s | %s", time_str, data:toHex(), data_str)

    -- 添加到历史缓冲区
    table.insert(rx_data_history, log_entry)
    -- 限制历史记录数量
    if #rx_data_history > MAX_RX_HISTORY then
        table.remove(rx_data_history, 1)
    end

    -- 刷新显示
    refresh_rx_display()
end

local function on_data_received(data)
    log.info("BLE_MASTER_WIN", "收到数据:", data and data:toHex() or "nil")
    rx_count = rx_count + 1
    update_status_panel()
    add_rx_data_to_display(data)
end

local function on_back_click()
    log.info("BLE_MASTER_WIN", "返回按钮点击")
    
    -- 关闭当前窗口（参考ble_slave做法）
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    
    -- 发送打开主菜单事件
    sys.publish("OPEN_MAIN_MENU_WIN")
end

local function on_scan_btn_click()
    log.info("BLE_MASTER_WIN", "扫描按钮点击")
    if is_scanning then
        ble_manager.stop_scan()
    else
        ble_manager.start_scan()
    end
end

local function on_nav_scan_click()
    ble_master_win.switch_page("scan")
end

local function on_nav_data_click()
    ble_master_win.switch_page("data")
end

local function on_nav_settings_click()
    ble_master_win.switch_page("settings")
end

function ble_master_win.switch_page(page_name)
    current_page = page_name
    
    if ui_controls.scan_page then
        ui_controls.scan_page:set_hidden(true)
    end
    if ui_controls.data_page then
        ui_controls.data_page:set_hidden(true)
    end
    if ui_controls.settings_page then
        ui_controls.settings_page:set_hidden(true)
    end
    
    if page_name == "scan" and ui_controls.scan_page then
        ui_controls.scan_page:set_hidden(false)
    elseif page_name == "data" and ui_controls.data_page then
        ui_controls.data_page:set_hidden(false)
    elseif page_name == "settings" and ui_controls.settings_page then
        ui_controls.settings_page:set_hidden(false)
    end
    
    update_nav_buttons()
end

local function create_scan_page(parent)
    local page = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = 480,
        h = 652,
        color = COLORS.BG_GRAY
    })
    
    local control_area = airui.container({
        parent = page,
        x = 0,
        y = 0,
        w = 480,
        h = 100,
        color = COLORS.WHITE
    })
    
    ui_controls.scan_btn = airui.button({
        parent = control_area,
        x = 100,
        y = 24,
        w = 280,
        h = 52,
        text = "开始扫描",
        style = {
            bg_color = COLORS.SUCCESS,
            text_color = COLORS.WHITE,
            radius = 26
        },
        on_click = on_scan_btn_click
    })
    
    local list_area = airui.container({
        parent = page,
        x = 0,
        y = 100,
        w = 480,
        h = 524,  -- 36(标题栏) + 432(设备列表) + 56(分页控制)
        color = COLORS.BG_GRAY
    })
    
    local title_bar = airui.container({
        parent = list_area,
        x = 0,
        y = 0,
        w = 480,
        h = 40,
        color = COLORS.BG_GRAY
    })
    
    airui.container({
        parent = title_bar,
        x = 20,
        y = 12,
        w = 4,
        h = 16,
        color = COLORS.PRIMARY,
        radius = 2
    })
    
    airui.label({
        parent = title_bar,
        x = 32,
        y = 10,
        w = 100,
        h = 20,
        text = "附近设备",
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 发现设备计数（移到标题栏右侧）
    airui.label({
        parent = title_bar,
        x = 320,
        y = 10,
        w = 60,
        h = 20,
        text = "发现:",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    ui_controls.device_count_label = airui.label({
        parent = title_bar,
        x = 380,
        y = 10,
        w = 40,
        h = 20,
        text = "0",
        font_size = 16,
        color = COLORS.PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    ui_controls.device_list_container = airui.container({
        parent = list_area,
        x = 0,
        y = 36,
        w = 480,
        h = 432,  -- 6个设备 × 72高度 = 432
        color = COLORS.BG_GRAY
    })

    -- 分页控制区域
    local page_control_area = airui.container({
        parent = list_area,
        x = 0,
        y = 468,  -- 36 + 432 = 468
        w = 480,
        h = 56,
        color = COLORS.WHITE
    })

    -- 上一页按钮
    ui_controls.prev_page_btn = airui.button({
        parent = page_control_area,
        x = 20,
        y = 8,
        w = 80,
        h = 40,
        text = "上一页",
        font_size = 14,
        style = {
            bg_color = 0xCCCCCC,
            text_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_prev_page_click
    })

    -- 页码显示
    ui_controls.page_info_label = airui.label({
        parent = page_control_area,
        x = 200,
        y = 16,
        w = 80,
        h = 24,
        text = "0/0",
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 下一页按钮
    ui_controls.next_page_btn = airui.button({
        parent = page_control_area,
        x = 380,
        y = 8,
        w = 80,
        h = 40,
        text = "下一页",
        font_size = 14,
        style = {
            bg_color = 0xCCCCCC,
            text_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_next_page_click
    })

    ui_controls.empty_state = airui.container({
        parent = ui_controls.device_list_container,
        x = 0,
        y = 100,
        w = 480,
        h = 200,
        color = COLORS.BG_GRAY
    })
    
    airui.container({
        parent = ui_controls.empty_state,
        x = 0,
        y = 40,
        w = 480,
        h = 64
    })
    
    airui.label({
        parent = ui_controls.empty_state,
        x = 0,
        y = 120,
        w = 480,
        h = 20,
        text = "点击\"开始扫描\"搜索附近BLE设备",
        font_size = 14,
        color = COLORS.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    return page
end

-- ==================== 数据传输页面回调 ====================
local function on_disconnect_click()
    log.info("BLE_MASTER_WIN", "断开连接按钮点击")
    ble_manager.disconnect()
end

local function on_notify_toggle_click()
    log.info("BLE_MASTER_WIN", "Notify开关点击")
    if not data_transfer_vars.is_connected then
        log.warn("BLE_MASTER_WIN", "设备未连接，无法切换Notify")
        return
    end
    
    if not data_transfer_vars.rx_char_uuid then
        log.warn("BLE_MASTER_WIN", "未选择接收UUID，无法切换Notify")
        return
    end
    
    -- 检查是否有notify属性
    local has_notify = false
    local rx_svc = data_transfer_vars.rx_service_uuid
    local rx_char = data_transfer_vars.rx_char_uuid
    if data_transfer_vars.service_char_map[rx_svc] and data_transfer_vars.service_char_map[rx_svc][rx_char] then
        local props = data_transfer_vars.service_char_map[rx_svc][rx_char]
        has_notify = (props & 0x40) ~= 0
    end
    
    if not has_notify then
        log.info("BLE_MASTER_WIN", "当前UUID没有Notify属性，无法开启")
        return
    end
    
    data_transfer_vars.notify_enabled = not data_transfer_vars.notify_enabled
    ble_manager.set_notify_enable(data_transfer_vars.rx_service_uuid, data_transfer_vars.rx_char_uuid, data_transfer_vars.notify_enabled)
    update_notify_button()
end

local function on_read_click()
    log.info("BLE_MASTER_WIN", "读取按钮点击")
    if not data_transfer_vars.is_connected then
        log.warn("BLE_MASTER_WIN", "设备未连接，无法读取")
        return
    end
    
    if not data_transfer_vars.rx_char_uuid then
        log.warn("BLE_MASTER_WIN", "未选择接收UUID，无法读取")
        return
    end
    
    ble_manager.read_value(data_transfer_vars.rx_service_uuid, data_transfer_vars.rx_char_uuid)
end

local function on_clear_rx_click()
    log.info("BLE_MASTER_WIN", "清空接收数据")
    data_transfer_vars.rx_bytes = 0
    data_transfer_vars.rx_packets = 0
    update_data_stats()
    -- 清空历史缓冲区
    rx_data_history = {}
    -- 刷新显示
    refresh_rx_display()
end

local function on_send_click()
    log.info("BLE_MASTER_WIN", "发送文本按钮点击")
    if not data_transfer_vars.is_connected then
        log.warn("BLE_MASTER_WIN", "设备未连接，无法发送")
        return
    end
    
    if not data_transfer_vars.tx_char_uuid then
        log.warn("BLE_MASTER_WIN", "未选择发送UUID，无法发送")
        return
    end
    
    -- 从输入框获取文本
    local text = ""
    if ui_controls.send_input then
        text = ui_controls.send_input:get_text() or ""
    end
    
    if text == "" then
        log.warn("BLE_MASTER_WIN", "输入框为空")
        return
    end
    
    -- 发送文本数据
    local data = text
    local result = ble_manager.write_value(data_transfer_vars.tx_service_uuid, data_transfer_vars.tx_char_uuid, data)
    if result then
        log.info("BLE_MASTER_WIN", "文本发送成功")
        -- 更新统计
        data_transfer_vars.tx_bytes = data_transfer_vars.tx_bytes + #data
        data_transfer_vars.tx_packets = data_transfer_vars.tx_packets + 1
        update_data_stats()
        -- 清空输入框
        ui_controls.send_input:set_text("")
    else
        log.error("BLE_MASTER_WIN", "文本发送失败")
    end
end

-- 发送HEX按钮点击处理
local function on_send_hex_click()
    log.info("BLE_MASTER_WIN", "发送HEX按钮点击")
    if not data_transfer_vars.is_connected then
        log.warn("BLE_MASTER_WIN", "设备未连接，无法发送")
        return
    end
    
    if not data_transfer_vars.tx_char_uuid then
        log.warn("BLE_MASTER_WIN", "未选择发送UUID，无法发送")
        return
    end
    
    -- 从输入框获取HEX字符串
    local hex_str = ""
    if ui_controls.send_input then
        hex_str = ui_controls.send_input:get_text() or ""
    end
    
    if hex_str == "" then
        log.warn("BLE_MASTER_WIN", "输入框为空")
        return
    end
    
    -- 解析HEX字符串
    local data = ""
    for hex_byte in hex_str:gmatch("%x%x") do
        data = data .. string.char(tonumber(hex_byte, 16))
    end
    
    if #data == 0 then
        log.warn("BLE_MASTER_WIN", "无效的HEX数据")
        return
    end
    
    -- 发送HEX数据
    local result = ble_manager.write_value(data_transfer_vars.tx_service_uuid, data_transfer_vars.tx_char_uuid, data)
    if result then
        log.info("BLE_MASTER_WIN", "HEX发送成功")
        -- 更新统计
        data_transfer_vars.tx_bytes = data_transfer_vars.tx_bytes + #data
        data_transfer_vars.tx_packets = data_transfer_vars.tx_packets + 1
        update_data_stats()
        -- 清空输入框
        ui_controls.send_input:set_text("")
    else
        log.error("BLE_MASTER_WIN", "HEX发送失败")
    end
end

local function on_clear_tx_click()
    log.info("BLE_MASTER_WIN", "清空发送数据")
    data_transfer_vars.tx_bytes = 0
    data_transfer_vars.tx_packets = 0
    update_data_stats()
    -- 清空输入框
    if ui_controls.send_input then
        ui_controls.send_input:set_text("")
    end
end

-- 显示UUID选择器
local function show_uuid_selector(type)
    log.info("BLE_MASTER_WIN", "显示UUID选择器:", type)

    if not data_transfer_vars.is_connected then
        log.warn("BLE_MASTER_WIN", "设备未连接，无法选择UUID")
        return
    end

    -- 获取已发现的服务和特征值
    local services, char_map = ble_manager.get_discovered_services()

    if not services or #services == 0 then
        log.warn("BLE_MASTER_WIN", "未发现GATT服务")
        return
    end

    -- 创建弹窗背景遮罩
    local mask = nil
    local dialog = nil

    mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000,
        alpha = 128
    })

    -- 创建弹窗容器（增大尺寸以容纳长UUID）
    dialog = airui.container({
        parent = airui.screen,
        x = 20,
        y = 80,
        w = 440,
        h = 600,
        color = COLORS.WHITE,
        radius = 12
    })

    -- 标题
    airui.label({
        parent = dialog,
        x = 0,
        y = 15,
        w = 440,
        h = 30,
        text = type == "rx" and "选择接收UUID" or "选择发送UUID",
        font_size = 18,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 关闭按钮
    local function on_close_click()
        if mask then
            mask:destroy()
            mask = nil
        end
        if dialog then
            dialog:destroy()
            dialog = nil
        end
    end
    
    airui.button({
        parent = dialog,
        x = 390,
        y = 10,
        w = 40,
        h = 40,
        text = "×",
        style = {
            bg_color = 0xFF5722,
            text_color = COLORS.WHITE,
            radius = 20
        },
        on_click = on_close_click
    })

    -- 创建可滚动的UUID列表区域
    local list_area = airui.container({
        parent = dialog,
        x = 10,
        y = 60,
        w = 420,
        h = 530,
        color = COLORS.BG_GRAY,
        radius = 8
    })

    local y_offset = 10
    local has_items = false

    -- 创建选择按钮点击回调（工厂函数）
    local function create_select_click_handler(sel_type, svc_uuid, chr_uuid, m, d)
        return function()
            if sel_type == "rx" then
                data_transfer_vars.rx_service_uuid = svc_uuid
                data_transfer_vars.rx_char_uuid = chr_uuid
            else
                data_transfer_vars.tx_service_uuid = svc_uuid
                data_transfer_vars.tx_char_uuid = chr_uuid
            end
            -- 关闭弹窗
            if m then
                m:destroy()
            end
            if d then
                d:destroy()
            end
            update_notify_button()
        end
    end

    -- 遍历所有服务和特征值
    for _, service_uuid in ipairs(services) do
        local chars = char_map[service_uuid]
        if chars and next(chars) then
            -- 服务标题（使用格式化后的UUID）
            airui.label({
                parent = list_area,
                x = 10,
                y = y_offset,
                w = 400,
                h = 24,
                text = "服务: " .. format_uuid(service_uuid),
                font_size = 14,
                color = 0x2196F3
            })
            y_offset = y_offset + 30

            -- 特征值列表
            for char_uuid, props in pairs(chars) do
                local can_read = (props & 0x08) ~= 0
                local can_write = (props & 0x10) ~= 0 or (props & 0x80) ~= 0
                local can_notify = (props & 0x40) ~= 0

                -- 检查是否匹配当前类型
                local is_valid = false
                if type == "rx" and (can_read or can_notify) then
                    is_valid = true
                elseif type == "tx" and can_write then
                    is_valid = true
                end

                if is_valid then
                    has_items = true

                    -- 特征值项背景（增大宽度）
                    local item_bg = airui.container({
                        parent = list_area,
                        x = 10,
                        y = y_offset,
                        w = 400,
                        h = 80,
                        color = COLORS.WHITE,
                        radius = 6
                    })

                    -- 特征值UUID（使用格式化后的UUID，缩小字体）
                    airui.label({
                        parent = item_bg,
                        x = 10,
                        y = 8,
                        w = 380,
                        h = 20,
                        text = format_uuid(char_uuid),
                        font_size = 11,
                        color = COLORS.TEXT_PRIMARY
                    })

                    -- 属性标签颜色
                    local prop_color = COLORS.TEXT_SECONDARY
                    if can_write and can_notify then
                        prop_color = 0x4CAF50  -- 绿色：可读写
                    elseif can_write then
                        prop_color = 0x2196F3  -- 蓝色：可写
                    elseif can_notify or can_read then
                        prop_color = 0xFF9800  -- 橙色：可接收
                    end

                    -- 属性标签
                    airui.label({
                        parent = item_bg,
                        x = 10,
                        y = 32,
                        w = 280,
                        h = 16,
                        text = parse_properties(props),
                        font_size = 10,
                        color = prop_color
                    })

                    -- 检查是否已选中
                    local is_selected = false
                    if type == "rx" then
                        is_selected = (data_transfer_vars.rx_service_uuid == service_uuid and
                                       data_transfer_vars.rx_char_uuid == char_uuid)
                    else
                        is_selected = (data_transfer_vars.tx_service_uuid == service_uuid and
                                       data_transfer_vars.tx_char_uuid == char_uuid)
                    end

                    -- 选择按钮
                    airui.button({
                        parent = item_bg,
                        x = 320,
                        y = 20,
                        w = 70,
                        h = 40,
                        text = is_selected and "已选" or "选择",
                        style = {
                            bg_color = is_selected and 0x4CAF50 or 0x2196F3,
                            text_color = COLORS.WHITE,
                            radius = 20
                        },
                        on_click = create_select_click_handler(type, service_uuid, char_uuid, mask, dialog)
                    })

                    y_offset = y_offset + 90
                end
            end
        end
    end

    -- 如果没有可用特征值
    if not has_items then
        airui.label({
            parent = list_area,
            x = 0,
            y = 200,
            w = 420,
            h = 20,
            text = "没有可用的特征值",
            font_size = 14,
            color = COLORS.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

-- 服务发现回调
local function on_services_discovered(services, char_map)
    log.info("BLE_MASTER_WIN", "服务发现完成，共发现", #services, "个服务")

    data_transfer_vars.discovered_services = services
    data_transfer_vars.service_char_map = char_map

    -- 自动选择第一个可用的UUID
    for _, service_uuid in ipairs(services) do
        local chars = char_map[service_uuid]
        if chars then
            for char_uuid, props in pairs(chars) do
                local can_read = (props & 0x08) ~= 0
                local can_write = (props & 0x10) ~= 0 or (props & 0x80) ~= 0
                local can_notify = (props & 0x40) ~= 0

                -- 自动选择接收UUID（支持Read或Notify）
                if not data_transfer_vars.rx_char_uuid and (can_read or can_notify) then
                    data_transfer_vars.rx_service_uuid = service_uuid
                    data_transfer_vars.rx_char_uuid = char_uuid
                end

                -- 自动选择发送UUID（支持Write）
                if not data_transfer_vars.tx_char_uuid and can_write then
                    data_transfer_vars.tx_service_uuid = service_uuid
                    data_transfer_vars.tx_char_uuid = char_uuid
                end
            end
        end
    end

    update_notify_button()

    -- GATT发现完成后，关闭连接中弹窗，显示连接成功弹窗并跳转
    if data_transfer_vars.is_connected then
        close_connecting_dialog()
        show_connect_success_dialog(switch_to_transfer_page)
    end
end

-- 选择接收UUID点击处理
local function on_select_rx_uuid_click()
    log.info("BLE_MASTER_WIN", "选择接收UUID")
    show_uuid_selector("rx")
end

-- 选择发送UUID点击处理
local function on_select_tx_uuid_click()
    log.info("BLE_MASTER_WIN", "选择发送UUID")
    show_uuid_selector("tx")
end

-- 创建数据传输页面
local function create_data_page(parent)
    local page = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = 480,
        h = 652,
        color = COLORS.BG_GRAY,
        hidden = true
    })
    
    -- 创建共享键盘（用于传输页面输入，初始位置在屏幕外）
    if not shared_keyboard then
        shared_keyboard = airui.keyboard({
            parent = page,
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
        log.info("BLE_MASTER_WIN", "传输页面键盘创建完成")
    end
    
    -- 连接状态卡片（绿色主题，与ble_slave一致）
    ui_controls.conn_status_card = airui.container({
        parent = page,
        x = 20,
        y = 16,
        w = 440,
        h = 80,
        color = 0x4CAF50,
        radius = 12
    })
    
    ui_controls.conn_status_text = airui.label({
        parent = ui_controls.conn_status_card,
        x = 16,
        y = 8,
        w = 200,
        h = 20,
        text = "未连接到从机",
        font_size = 14,
        color = COLORS.WHITE
    })
    
    -- 状态点
    ui_controls.transfer_status_dot = airui.container({
        parent = ui_controls.conn_status_card,
        x = 200,
        y = 14,
        w = 8,
        h = 8,
        color = 0xBDBDBD,
        radius = 4
    })
    
    ui_controls.transfer_status_text = airui.label({
        parent = ui_controls.conn_status_card,
        x = 220,
        y = 8,
        w = 100,
        h = 20,
        text = "等待连接",
        font_size = 14,
        color = COLORS.WHITE
    })
    
    -- 断开连接按钮（红色，参考ble_slave）
    ui_controls.disconnect_btn = airui.button({
        parent = ui_controls.conn_status_card,
        x = 340,
        y = 20,
        w = 80,
        h = 36,
        text = "断开",
        font_size = 13,
        style = {
            bg_color = 0xF44336,
            text_color = 0xFFFFFF,
            radius = 18
        },
        on_click = on_disconnect_click,
        hidden = true
    })

    -- UUID选择区域（两个按钮挨着放，橙色背景）
    -- 接收UUID选择按钮
    airui.button({
        parent = ui_controls.conn_status_card,
        x = 16,
        y = 48,
        w = 80,
        h = 26,
        text = "接收UUID",
        font_size = 11,
        style = {
            bg_color = 0xFF9800,
            text_color = 0xFFFFFF,
            radius = 13
        },
        on_click = on_select_rx_uuid_click
    })

    -- 发送UUID选择按钮（挨着接收UUID按钮）
    airui.button({
        parent = ui_controls.conn_status_card,
        x = 106,
        y = 48,
        w = 80,
        h = 26,
        text = "发送UUID",
        font_size = 11,
        style = {
            bg_color = 0xFF9800,
            text_color = 0xFFFFFF,
            radius = 13
        },
        on_click = on_select_tx_uuid_click
    })
    
    -- 接收数据卡片（参考ble_slave样式，高度320）
    ui_controls.rx_card = airui.container({
        parent = page,
        x = 20,
        y = 106,
        w = 440,
        h = 320,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = ui_controls.rx_card,
        x = 16,
        y = 12,
        w = 100,
        h = 20,
        text = "接收数据",
        font_size = 16,
        color = COLORS.TEXT_PRIMARY
    })

    -- Notify按钮（下移避免与显示区域重叠）
    ui_controls.notify_btn = airui.button({
        parent = ui_controls.rx_card,
        x = 200,
        y = 10,
        w = 70,
        h = 24,
        text = "Notify:关",
        font_size = 12,
        style = {
            bg_color = 0x9E9E9E,
            text_color = COLORS.WHITE,
            radius = 12
        },
        on_click = on_notify_toggle_click
    })

    -- 读取按钮
    ui_controls.read_btn = airui.button({
        parent = ui_controls.rx_card,
        x = 278,
        y = 10,
        w = 50,
        h = 24,
        text = "读取",
        font_size = 12,
        style = {
            bg_color = 0x2196F3,
            text_color = COLORS.WHITE,
            radius = 12
        },
        on_click = on_read_click
    })

    -- 清空按钮
    airui.button({
        parent = ui_controls.rx_card,
        x = 336,
        y = 10,
        w = 50,
        h = 24,
        text = "清空",
        font_size = 12,
        style = {
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_SECONDARY,
            radius = 12
        },
        on_click = on_clear_rx_click
    })
    
    -- 接收数据外框（蓝色边框）
    ui_controls.rx_border = airui.container({
        parent = ui_controls.rx_card,
        x = 8,
        y = 40,
        w = 424,
        h = 280,
        color = 0x2196F3,  -- 蓝色边框
        radius = 8
    })

    -- 接收数据显示区域（白色背景，内部用label显示日志）
    ui_controls.rx_data_area = airui.container({
        parent = ui_controls.rx_border,
        x = 2,
        y = 2,
        w = 420,
        h = 276,
        color = 0xFFFFFF,  -- 白色背景
        radius = 6
    })
    
    -- 发送数据卡片（参考ble_slave样式）
    local tx_card = airui.container({
        parent = page,
        x = 20,
        y = 436,
        w = 440,
        h = 200,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = tx_card,
        x = 16,
        y = 12,
        w = 100,
        h = 20,
        text = "发送数据",
        font_size = 16,
        color = COLORS.TEXT_PRIMARY
    })

    -- 输入框背景
    local input_bg = airui.container({
        parent = tx_card,
        x = 16,
        y = 40,
        w = 408,
        h = 56,
        color = 0xF5F5F5,
        radius = 6
    })

    -- 输入框（绑定共享键盘）
    ui_controls.send_input = airui.textarea({
        parent = input_bg,
        x = 10,
        y = 4,
        w = 388,
        h = 48,
        text = "",
        font_size = 14,
        color = COLORS.TEXT_PRIMARY,
        bg_color = 0x00000000,
        max_length = 100,
        keyboard = shared_keyboard,
        editable = true
    })
    
    -- 点击输入框显示键盘
    if ui_controls.send_input and ui_controls.send_input.on_click then
        ui_controls.send_input.on_click = on_input_click_show_keyboard
    end

    -- 按钮区域
    local btn_area = airui.container({
        parent = tx_card,
        x = 16,
        y = 102,
        w = 408,
        h = 40,
        color = COLORS.WHITE,
        alpha = 0
    })
    
    -- 发送文本按钮
    airui.button({
        parent = btn_area,
        x = 0,
        y = 0,
        w = 100,
        h = 40,
        text = "发送文本",
        style = {
            bg_color = 0x4CAF50,
            text_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_send_click
    })
    
    -- 发送HEX按钮
    airui.button({
        parent = btn_area,
        x = 120,
        y = 0,
        w = 100,
        h = 40,
        text = "发送HEX",
        style = {
            bg_color = 0x2196F3,
            text_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_send_hex_click
    })
    
    -- 清空按钮
    airui.button({
        parent = btn_area,
        x = 240,
        y = 0,
        w = 80,
        h = 40,
        text = "清空",
        style = {
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_SECONDARY,
            radius = 8
        },
        on_click = on_clear_tx_click
    })
    
    -- 数据统计（接收和发送并排显示，参考ble_slave样式）
    local stats_container = airui.container({
        parent = tx_card,
        x = 0,
        y = 150,
        w = 440,
        h = 20,
        color = COLORS.WHITE
    })

    -- 接收统计（左侧）
    airui.label({
        parent = stats_container,
        x = 20,
        y = 2,
        w = 32,
        h = 16,
        text = "接收:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.rx_bytes_label = airui.label({
        parent = stats_container,
        x = 52,
        y = 2,
        w = 45,
        h = 16,
        text = "0",
        font_size = 11,
        color = 0x333333
    })

    airui.label({
        parent = stats_container,
        x = 97,
        y = 2,
        w = 24,
        h = 16,
        text = "字节",
        font_size = 11,
        color = 0x888888
    })

    airui.label({
        parent = stats_container,
        x = 128,
        y = 2,
        w = 28,
        h = 16,
        text = "包数:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.rx_packets_label = airui.label({
        parent = stats_container,
        x = 156,
        y = 2,
        w = 35,
        h = 16,
        text = "0",
        font_size = 11,
        color = 0x333333
    })

    -- 发送统计（右侧）
    airui.label({
        parent = stats_container,
        x = 205,
        y = 2,
        w = 32,
        h = 16,
        text = "发送:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.tx_bytes_label = airui.label({
        parent = stats_container,
        x = 237,
        y = 2,
        w = 45,
        h = 16,
        text = "0",
        font_size = 11,
        color = 0x333333
    })

    airui.label({
        parent = stats_container,
        x = 282,
        y = 2,
        w = 24,
        h = 16,
        text = "字节",
        font_size = 11,
        color = 0x888888
    })

    airui.label({
        parent = stats_container,
        x = 313,
        y = 2,
        w = 28,
        h = 16,
        text = "包数:",
        font_size = 11,
        color = 0x888888
    })

    ui_controls.tx_packets_label = airui.label({
        parent = stats_container,
        x = 341,
        y = 2,
        w = 35,
        h = 16,
        text = "0",
        font_size = 11,
        color = 0x333333
    })
    
    return page
end

-- ==================== 设置页面变量 ====================
local settings_vars = {
    scan_interval = 1600,  -- 默认扫描间隔1600 (0.625ms单位)
    scan_window = 160,     -- 默认扫描窗口160
    scan_type = 1  -- 1: 主动扫描, 0: 被动扫描
}

-- 设置键盘提交回调
local function on_settings_keyboard_commit()
    log.info("BLE_MASTER_WIN", "设置键盘提交")
    if settings_shared_keyboard and settings_shared_keyboard.hide then
        settings_shared_keyboard:hide()
    end
    
    -- 从输入框同步值到 settings_vars
    if ui_controls.scan_interval_input then
        local text = ui_controls.scan_interval_input:get_text() or ""
        local val = tonumber(text)
        if val then
            -- 限制范围 20-10240
            val = math.max(20, math.min(10240, val))
            settings_vars.scan_interval = val
            log.info("BLE_MASTER_WIN", "扫描间隔已更新:", val)
            
            -- 更新显示
            ui_controls.scan_interval_input:set_text(tostring(val))
            if ui_controls.scan_interval_ms_label then
                ui_controls.scan_interval_ms_label:set_text(tostring(round(val * 0.625)))
            end
        end
    end
    
    if ui_controls.scan_window_input then
        local text = ui_controls.scan_window_input:get_text() or ""
        local val = tonumber(text)
        if val then
            -- 限制范围 20-10240
            val = math.max(20, math.min(10240, val))
            settings_vars.scan_window = val
            log.info("BLE_MASTER_WIN", "扫描窗口已更新:", val)
            
            -- 更新显示
            ui_controls.scan_window_input:set_text(tostring(val))
            if ui_controls.scan_window_ms_label then
                ui_controls.scan_window_ms_label:set_text(tostring(round(val * 0.625)))
            end
        end
    end
end

-- 显示确认重启对话框
local function show_reboot_confirm_dialog()
    local mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000,
        alpha = 128
    })

    local dialog = airui.container({
        parent = mask,
        x = 40,
        y = 280,
        w = 400,
        h = 180,
        color = COLORS.WHITE,
        radius = 12
    })
    
    local function on_reboot_cancel_click()
        mask:destroy()
    end
    
    local function on_reboot_confirm_click()
        mask:destroy()
        pm.reboot()
    end

    airui.label({
        parent = dialog,
        x = 0,
        y = 20,
        w = 400,
        h = 24,
        text = "确认重启",
        font_size = 18,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = dialog,
        x = 20,
        y = 60,
        w = 360,
        h = 40,
        text = "修改配置需要重启生效，请确认是否重启？",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local cancel_btn = airui.button({
        parent = dialog,
        x = 40,
        y = 120,
        w = 140,
        h = 44,
        text = "取消",
        style = {
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_PRIMARY,
            radius = 8
        },
        on_click = on_reboot_cancel_click
    })

    local reboot_btn = airui.button({
        parent = dialog,
        x = 220,
        y = 120,
        w = 140,
        h = 44,
        text = "确认重启",
        style = {
            bg_color = 0xE91E63,
            text_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_reboot_confirm_click
    })
end

-- ==================== 设置页面回调 ====================
local function on_save_settings_click()
    log.info("BLE_MASTER_WIN", "保存设置")
    
    -- 验证范围：扫描间隔和窗口的有效范围是 20-10240 (0.625ms单位，对应 12.5ms-6400ms)
    local interval = math.max(20, math.min(10240, settings_vars.scan_interval))
    local window = math.max(20, math.min(10240, settings_vars.scan_window))
    
    settings_vars.scan_interval = interval
    settings_vars.scan_window = window
    
    -- 更新到ble_manager
    ble_manager.set_scan_config({
        scan_interval = interval,
        scan_window = window,
        scan_mode = settings_vars.scan_type == 1 and ble.SCAN_ACTIVE or ble.SCAN_PASSIVE
    })
    
    -- 保存到fskv
    if fskv then
        fskv.set("ble_master_scan_interval", tostring(interval))
        fskv.set("ble_master_scan_window", tostring(window))
        fskv.set("ble_master_scan_type", tostring(settings_vars.scan_type))
        log.info("BLE_MASTER_WIN", "设置已保存到fskv")
    end
    
    -- 显示确认重启对话框
    show_reboot_confirm_dialog()
end

local function on_reset_settings_click()
    log.info("BLE_MASTER_WIN", "恢复默认设置")

    settings_vars.scan_interval = 1600
    settings_vars.scan_window = 160
    settings_vars.scan_type = 1

    -- 更新UI
    if ui_controls.scan_interval_input then
        ui_controls.scan_interval_input:set_text("1600")
    end
    if ui_controls.scan_window_input then
        ui_controls.scan_window_input:set_text("160")
    end
    if ui_controls.scan_interval_ms_label then
        ui_controls.scan_interval_ms_label:set_text("1000")
    end
    if ui_controls.scan_window_ms_label then
        ui_controls.scan_window_ms_label:set_text("100")
    end

    -- 更新扫描类型按钮
    if ui_controls.scan_type_passive and ui_controls.scan_type_active then
        ui_controls.scan_type_passive:set_style({
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_SECONDARY
        })
        ui_controls.scan_type_active:set_style({
            bg_color = COLORS.PRIMARY,
            text_color = COLORS.WHITE
        })
    end

    -- 更新到ble_manager
    ble_manager.set_scan_config({
        scan_interval = 1600,
        scan_window = 160,
        scan_mode = ble.SCAN_ACTIVE
    })

    -- 保存到fskv
    if fskv then
        fskv.set("ble_master_scan_interval", "1600")
        fskv.set("ble_master_scan_window", "160")
        fskv.set("ble_master_scan_type", "1")
        log.info("BLE_MASTER_WIN", "默认设置已保存到fskv")
    end

    -- 显示确认重启对话框
    show_reboot_confirm_dialog()
end

-- 显示提示对话框
local function show_alert_dialog(title, message)
    local mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000,
        alpha = 128
    })

    local dialog = airui.container({
        parent = mask,
        x = 40,
        y = 280,
        w = 400,
        h = 180,
        color = COLORS.WHITE,
        radius = 12
    })

    airui.label({
        parent = dialog,
        x = 0,
        y = 20,
        w = 400,
        h = 24,
        text = title,
        font_size = 18,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = dialog,
        x = 20,
        y = 60,
        w = 360,
        h = 40,
        text = message,
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local function on_alert_confirm_click()
        mask:destroy()
    end
    
    airui.button({
        parent = dialog,
        x = 130,
        y = 120,
        w = 140,
        h = 44,
        text = "确定",
        style = {
            bg_color = COLORS.PRIMARY,
            text_color = COLORS.WHITE,
            radius = 8
        },
        on_click = on_alert_confirm_click
    })
end

-- 加载设置
local function load_settings()
    if not fskv then return end

    local has_invalid_value = false
    local invalid_msg = ""

    local interval = fskv.get("ble_master_scan_interval")
    if interval then
        local val = tonumber(interval)
        -- 检查范围有效性，无效则使用默认值
        if val and val >= 20 and val <= 10240 then
            settings_vars.scan_interval = val
        else
            log.warn("BLE_MASTER_WIN", "扫描间隔值无效:", interval, "使用默认值1600")
            has_invalid_value = true
            invalid_msg = "扫描间隔值 " .. tostring(interval) .. " 无效，已使用默认值1600"
        end
    end

    local window = fskv.get("ble_master_scan_window")
    if window then
        local val = tonumber(window)
        -- 检查范围有效性，无效则使用默认值
        if val and val >= 20 and val <= 10240 then
            settings_vars.scan_window = val
        else
            log.warn("BLE_MASTER_WIN", "扫描窗口值无效:", window, "使用默认值160")
            has_invalid_value = true
            invalid_msg = invalid_msg .. (invalid_msg ~= "" and "\n" or "") .. "扫描窗口值 " .. tostring(window) .. " 无效，已使用默认值160"
        end
    end

    local scan_type = fskv.get("ble_master_scan_type")
    if scan_type then
        settings_vars.scan_type = tonumber(scan_type) or 1
    end

    log.info("BLE_MASTER_WIN", "设置已加载:", settings_vars.scan_interval, settings_vars.scan_window, settings_vars.scan_type)

    -- 如果有无效值，显示提示
    if has_invalid_value then
        local function show_invalid_alert()
            show_alert_dialog("配置已重置", invalid_msg)
        end
        sys.timerStart(show_invalid_alert, 500)
    end
end

local function create_settings_page(parent)
    -- 加载保存的设置
    load_settings()

    local page = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = 480,
        h = 652,
        color = COLORS.BG_GRAY,
        hidden = true
    })

    -- 创建设置页面专用键盘（数字模式，初始位置在屏幕外）
    if not settings_shared_keyboard then
        settings_shared_keyboard = airui.keyboard({
            parent = page,
            x = 0,
            y = -20,
            w = 480,
            h = 200,
            mode = "number",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = on_settings_keyboard_commit
        })
        log.info("BLE_MASTER_WIN", "设置页面键盘创建完成")
    end
    
    -- 扫描间隔设置项
    local interval_item = airui.container({
        parent = page,
        x = 20,
        y = 16,
        w = 440,
        h = 100,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = interval_item,
        x = 16,
        y = 12,
        w = 200,
        h = 20,
        text = "扫描间隔 (Scan Interval)",
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = interval_item,
        x = 16,
        y = 36,
        w = 400,
        h = 16,
        text = "设置两次扫描之间的时间间隔，单位：0.625ms，范围：20-10240",
        font_size = 12,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 使用可编辑输入框，绑定数字键盘
    ui_controls.scan_interval_input = airui.textarea({
        parent = interval_item,
        x = 16,
        y = 60,
        w = 80,
        h = 32,
        text = tostring(settings_vars.scan_interval),
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        bg_color = 0xF5F5F5,
        align = airui.TEXT_ALIGN_CENTER,
        max_length = 4,
        keyboard = settings_shared_keyboard,
        editable = true
    })
    
    airui.label({
        parent = interval_item,
        x = 140,
        y = 68,
        w = 120,
        h = 16,
        text = "× 0.625ms =",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    ui_controls.scan_interval_ms_label = airui.label({
        parent = interval_item,
        x = 250,
        y = 68,
        w = 60,
        h = 16,
        text = tostring(round(settings_vars.scan_interval * 0.625)),
        font_size = 14,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = interval_item,
        x = 310,
        y = 68,
        w = 40,
        h = 16,
        text = "ms",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 扫描窗口设置项
    local window_item = airui.container({
        parent = page,
        x = 20,
        y = 128,
        w = 440,
        h = 100,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = window_item,
        x = 16,
        y = 12,
        w = 200,
        h = 20,
        text = "扫描窗口",
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = window_item,
        x = 16,
        y = 36,
        w = 400,
        h = 16,
        text = "设置每次扫描的持续时间，单位：0.625ms，范围：20-10240",
        font_size = 12,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 使用可编辑输入框，绑定数字键盘
    ui_controls.scan_window_input = airui.textarea({
        parent = window_item,
        x = 16,
        y = 60,
        w = 80,
        h = 32,
        text = tostring(settings_vars.scan_window),
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        bg_color = 0xF5F5F5,
        align = airui.TEXT_ALIGN_CENTER,
        max_length = 4,
        keyboard = settings_shared_keyboard,
        editable = true
    })
    
    airui.label({
        parent = window_item,
        x = 140,
        y = 68,
        w = 120,
        h = 16,
        text = "× 0.625ms =",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    ui_controls.scan_window_ms_label = airui.label({
        parent = window_item,
        x = 250,
        y = 68,
        w = 60,
        h = 16,
        text = tostring(round(settings_vars.scan_window * 0.625)),
        font_size = 14,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = window_item,
        x = 310,
        y = 68,
        w = 40,
        h = 16,
        text = "ms",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 扫描类型设置项（增加高度避免滑动框）
    local type_item = airui.container({
        parent = page,
        x = 20,
        y = 240,
        w = 440,
        h = 100,
        color = COLORS.WHITE,
        radius = 12
    })
    
    airui.label({
        parent = type_item,
        x = 16,
        y = 12,
        w = 200,
        h = 20,
        text = "扫描类型 (Scan Type)",
        font_size = 16,
        color = COLORS.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = type_item,
        x = 16,
        y = 36,
        w = 400,
        h = 16,
        text = "选择主动扫描或被动扫描",
        font_size = 12,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 扫描类型选择按钮组
    local type_btn_group = airui.container({
        parent = type_item,
        x = 16,
        y = 56,
        w = 300,
        h = 36,
        color = COLORS.WHITE,
        alpha = 0
    })
    
    local function on_passive_scan_click()
        settings_vars.scan_type = 0
        ui_controls.scan_type_passive:set_style({
            bg_color = COLORS.PRIMARY,
            text_color = COLORS.WHITE
        })
        ui_controls.scan_type_active:set_style({
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_SECONDARY
        })
    end
    
    ui_controls.scan_type_passive = airui.button({
        parent = type_btn_group,
        x = 0,
        y = 0,
        w = 100,
        h = 32,
        text = "被动扫描",
        style = {
            bg_color = settings_vars.scan_type == 0 and COLORS.PRIMARY or COLORS.BG_GRAY,
            text_color = settings_vars.scan_type == 0 and COLORS.WHITE or COLORS.TEXT_SECONDARY,
            radius = 8
        },
        on_click = on_passive_scan_click
    })
    
    local function on_active_scan_click()
        settings_vars.scan_type = 1
        ui_controls.scan_type_active:set_style({
            bg_color = COLORS.PRIMARY,
            text_color = COLORS.WHITE
        })
        ui_controls.scan_type_passive:set_style({
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_SECONDARY
        })
    end
    
    ui_controls.scan_type_active = airui.button({
        parent = type_btn_group,
        x = 110,
        y = 0,
        w = 100,
        h = 32,
        text = "主动扫描",
        style = {
            bg_color = settings_vars.scan_type == 1 and COLORS.PRIMARY or COLORS.BG_GRAY,
            text_color = settings_vars.scan_type == 1 and COLORS.WHITE or COLORS.TEXT_SECONDARY,
            radius = 8
        },
        on_click = on_active_scan_click
    })
    
    -- 操作按钮（放到页面底部）
    local action_container = airui.container({
        parent = page,
        x = 20,
        y = 560,
        w = 440,
        h = 60,
        color = COLORS.WHITE,
        alpha = 0
    })
    
    local save_btn = airui.button({
        parent = action_container,
        x = 0,
        y = 0,
        w = 210,
        h = 48,
        text = "保存设置",
        style = {
            bg_color = COLORS.SUCCESS,
            text_color = COLORS.WHITE,
            radius = 10
        },
        on_click = on_save_settings_click
    })
    
    local reset_btn = airui.button({
        parent = action_container,
        x = 230,
        y = 0,
        w = 210,
        h = 48,
        text = "恢复默认",
        style = {
            bg_color = COLORS.BG_GRAY,
            text_color = COLORS.TEXT_SECONDARY,
            radius = 10
        },
        on_click = on_reset_settings_click
    })
    
    return page
end

local function create_bottom_nav(parent)
    local nav = airui.container({
        parent = parent,
        x = 0,
        y = 728,
        w = 480,
        h = 72,
        color = COLORS.WHITE
    })
    
    -- 扫描按钮（图标形式，参考ble_slave）
    ui_controls.nav_scan_icon = airui.image({
        parent = nav,
        x = 56,
        y = 8,
        w = 48,
        h = 48,
        src = "/luadb/scan.png",
        on_click = on_nav_scan_click
    })
    ui_controls.nav_scan_label = airui.label({
        parent = nav,
        x = 0,
        y = 56,
        w = 160,
        h = 16,
        text = "扫描",
        font_size = 14,
        color = COLORS.PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 传输按钮（图标形式，参考ble_slave）
    ui_controls.nav_transfer_icon = airui.image({
        parent = nav,
        x = 216,
        y = 8,
        w = 48,
        h = 48,
        src = "/luadb/transfer.png",
        on_click = on_nav_data_click
    })
    ui_controls.nav_transfer_label = airui.label({
        parent = nav,
        x = 160,
        y = 56,
        w = 160,
        h = 16,
        text = "传输",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 设置按钮（图标形式，参考ble_slave）
    ui_controls.nav_settings_icon = airui.image({
        parent = nav,
        x = 376,
        y = 8,
        w = 48,
        h = 48,
        src = "/luadb/setting.png",
        on_click = on_nav_settings_click
    })
    ui_controls.nav_settings_label = airui.label({
        parent = nav,
        x = 320,
        y = 56,
        w = 160,
        h = 16,
        text = "设置",
        font_size = 14,
        color = COLORS.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    return nav
end

function ble_master_win.on_create()
    log.info("BLE_MASTER_WIN", "窗口创建")
    
    ble_callbacks = {
        on_scan_state_change = on_scan_state_change,
        on_device_found = on_device_found,
        on_conn_state_change = on_conn_state_change,
        on_data_received = on_data_received,
        on_services_discovered = on_services_discovered
    }
    ble_manager.register_callback(ble_callbacks)
    
    local result = ble_manager.init()
    if not result then
        log.error("BLE_MASTER_WIN", "BLE初始化失败")
    end
    
    ui_controls.main_container = airui.container({
        x = 0, y = 0, w = 480, h = 800,
        color = COLORS.WHITE,
        parent = airui.screen
    })
    
    -- 标题栏（高度68px，无时间显示，保持蓝色主题）
    local header = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 0, w = 480, h = 68,
        color = COLORS.PRIMARY
    })

    -- 返回按钮
    airui.button({
        parent = header,
        x = 16, y = 14, w = 40, h = 40,
        text = "←",
        style = {
            bg_color = COLORS.PRIMARY_LIGHT,
            text_color = COLORS.WHITE,
            radius = 20
        },
        on_click = on_back_click
    })

    -- 标题（往下移动一点）
    airui.label({
        parent = header,
        x = 72, y = 20, w = 300, h = 40,
        text = "BLE主机",
        font_size = 20,
        color = COLORS.WHITE
    })

    ui_controls.content_area = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 68, w = 480, h = 660,
        color = 0xFFFFFF
    })
    
    ui_controls.scan_page = create_scan_page(ui_controls.content_area)
    ui_controls.data_page = create_data_page(ui_controls.content_area)
    ui_controls.settings_page = create_settings_page(ui_controls.content_area)
    
    create_bottom_nav(ui_controls.main_container)
    
    current_page = "scan"
    ble_master_win.switch_page("scan")
    
    log.info("BLE_MASTER_WIN", "界面创建完成")
end

function ble_master_win.on_destroy()
    log.info("BLE_MASTER_WIN", "窗口销毁")

    ble_manager.deinit()

    device_items = {}
    clear_device_item_map()  -- 清空设备项映射
    discovered_devices = {}

    -- 隐藏键盘
    if shared_keyboard and shared_keyboard.hide then
        shared_keyboard:hide()
    end
    if settings_shared_keyboard and settings_shared_keyboard.hide then
        settings_shared_keyboard:hide()
    end

    -- 清理键盘引用
    shared_keyboard = nil
    settings_shared_keyboard = nil

    if ui_controls.main_container then
        ui_controls.main_container:destroy()
        ui_controls.main_container = nil
    end

    ui_controls = {}
    
    -- 清理窗口ID
    win_id = nil
end

local function open_handler()
    log.info("BLE_MASTER_WIN", "接收到打开窗口事件")
    
    win_id = exwin.open({
        on_create = ble_master_win.on_create,
        on_destroy = ble_master_win.on_destroy,
    })
end

sys.subscribe("OPEN_BLE_MASTER_WIN", open_handler)

_G.ble_master_win = ble_master_win

return ble_master_win
