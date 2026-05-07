--[[
@module  ble_transfer_win
@summary 蓝牙文件传输窗口模块
@version 1.0.0
@date    2026.04.23
@usage
蓝牙文件传输应用，支持：
1. 主从模式切换
2. 文件发送和接收
3. 文件列表显示
4. 日志记录
]]

-- ==================== 模块定义 ====================
local ble_transfer_win = {}

log.info("ble_transfer", "ble_transfer_win 模块开始加载...")

-- ==================== 常量定义 ====================
-- 屏幕尺寸和边距
local SCREEN_W_DEFAULT, SCREEN_H_DEFAULT = 480, 800
local MARGIN_RATIO = 0.03  -- 边距占屏幕宽度的比例

-- 颜色常量
local COLOR_PRIMARY = 0x673AB7      -- 主色调（紫色）
local COLOR_SUCCESS = 0x4caf50      -- 成功色（绿色）
local COLOR_ERROR = 0xf44336        -- 错误色（红色）
local COLOR_WARNING = 0xff9800      -- 警告色（橙色）
local COLOR_INFO = 0x2196F3         -- 信息色（蓝色）
local COLOR_TEXT_PRIMARY = 0x333333 -- 主要文本颜色
local COLOR_TEXT_SECONDARY = 0x666666 -- 次要文本颜色
local COLOR_TEXT_HINT = 0x888888    -- 提示文本颜色
local COLOR_BG = 0xf5f7fa           -- 背景色

-- ==================== 模块级变量 ====================
-- 窗口和容器
local win_id = nil
local main_container = nil

-- 屏幕尺寸
local screen_w, screen_h = SCREEN_W_DEFAULT, SCREEN_H_DEFAULT
local margin = 15

-- 状态变量
local is_master = false
local is_connected = false
local device_name = "未连接设备"
local device_state = "等待连接"
local is_broadcasting = false
local is_scanning = false

-- 传输状态
local is_transferring = false  -- 是否正在传输中

-- 数据存储
local log_entries = {}
local file_list = {}
local scan_devices = {}

-- UI组件引用
local subtitle_label, device_name_label, device_state_label, state_dot
local connect_btn, disconnect_btn
local file_list_container, log_container, log_card, receive_card
local empty_state_label  -- 空状态标签（接收时显示进度）
local send_hint_label    -- 发送区域提示标签（发送时显示进度）
local modal_mask, modal_dialog
local toggle_text_label, toggle_knob_container

-- 扫描弹窗相关
local scan_modal_content = nil
local scan_btn = nil

-- 刷新节流相关
local last_update_time = 0
local UPDATE_INTERVAL = 500  -- 最小刷新间隔（毫秒）

-- 定时器
local connection_check_timer = nil

-- BLE管理器
local ble_manager = require("ble_manager")

-- ==================== 工具函数区 ====================

--[[
更新屏幕尺寸
根据当前屏幕旋转状态计算实际可用宽度和高度
]]
local function update_screen_size()
    local phys_w, phys_h = lcd.getSize()
    local rotation = airui.get_rotation()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * MARGIN_RATIO)
end

--[[
格式化文件大小
将字节数转换为人类可读的格式（B/KB/MB）
@param size 文件大小（字节）
@return 格式化后的字符串
]]
local function format_file_size(size)
    if size < 1024 then
        return size .. " B"
    elseif size < 1024 * 1024 then
        return string.format("%.1f KB", size / 1024)
    else
        return string.format("%.1f MB", size / (1024 * 1024))
    end
end

--[[
格式化文件大小（详细版，保留2位小数）
@param size 文件大小（字节）
@return 格式化后的字符串
]]
local function format_file_size_detailed(size)
    if size < 1024 then
        return size .. " B"
    elseif size < 1024 * 1024 then
        return string.format("%.2f KB", size / 1024)
    else
        return string.format("%.2f MB", size / (1024 * 1024))
    end
end

-- ==================== 日志管理区 ====================

--[[
添加日志条目
@param message 日志消息
@param level 日志级别（"info"/"success"/"warning"/"error"）
]]
local function add_log(message, level)
    level = level or "info"
    local timestamp = os.time()
    local time_str = string.format("%02d:%02d:%02d", timestamp // 3600 % 24, timestamp // 60 % 60, timestamp % 60)
    
    table.insert(log_entries, 1, {
        time = time_str,
        message = message,
        level = level
    })
    
    -- 限制日志条目数量
    if #log_entries > 20 then
        table.remove(log_entries)
    end
    
    -- 更新UI显示
    if log_container then
        update_log_display()
    end
    
    log.info("ble_transfer_ui", time_str, message)
end

-- ==================== 弹窗管理区 ====================

--[[
关闭当前弹窗
销毁遮罩层和对话框，清理引用
]]
local function close_modal()
    if modal_mask then
        modal_mask:destroy()
        modal_mask = nil
    end
    if modal_dialog then
        modal_dialog:destroy()
        modal_dialog = nil
    end
    -- 清理扫描弹窗内容引用
    scan_modal_content = nil
end

--[[
关闭扫描设备弹窗
停止扫描并清理相关资源
]]
local function close_scan_modal()
    close_modal()
    is_scanning = false
    scan_btn = nil
    last_update_time = 0  -- 重置节流时间戳
    ble_manager.stop_scan()
    
    -- 同步更新主页面连接按钮状态
    if connect_btn and is_master and not is_connected then
        connect_btn:set_text("开始扫描")
    end
end

--[[
处理连接按钮点击事件（设备行内）
@param device 设备信息表
]]
local function handle_device_connect_click(device)
    add_log("正在连接: " .. (device.name or "未知设备"))
    ble_manager.connect(device.addr, function(success, conn_addr)
        if success then
            add_log("连接成功: " .. (device.name or "未知设备"), "success")
            close_scan_modal()
        else
            add_log("连接失败", "error")
        end
    end)
end

--[[
更新扫描弹窗中的设备列表
使用节流机制避免频繁刷新
]]
local function update_scan_modal()
    if not scan_modal_content then return end
    if not modal_dialog then return end

    -- 节流检查
    local current_time = mcu.ticks()
    if current_time - last_update_time < UPDATE_INTERVAL then
        return
    end
    last_update_time = current_time

    -- 重新创建设备列表容器
    scan_modal_content:destroy()
    scan_modal_content = airui.container({
        parent = modal_dialog,
        x = 10,
        y = 60,
        w = screen_w - 20,
        h = screen_h - 70,
        color = 0xf5f7fa,
        radius = 8
    })

    -- 无设备时显示提示
    if #scan_devices == 0 then
        airui.label({
            parent = scan_modal_content,
            x = 0,
            y = (screen_h - 70) / 2 - 10,
            w = screen_w - 20,
            h = 20,
            text = is_scanning and "正在扫描..." or "扫描已停止，点击开始扫描按钮继续",
            font_size = 14,
            color = COLOR_TEXT_HINT,
            align = airui.TEXT_ALIGN_CENTER
        })
        return
    end

    -- 显示设备列表
    for i, device in ipairs(scan_devices) do
        if i > 10 then break end

        local row_width = screen_w - 40
        local btn_width = 60
        local btn_spacing = 10
        local icon_size = 40
        local icon_spacing = 12

        -- 设备行容器
        local device_row = airui.container({
            parent = scan_modal_content,
            x = 10,
            y = 10 + (i - 1) * 70,
            w = row_width,
            h = 65,
            color = 0xffffff,
            radius = 8
        })

        -- 设备图标
        airui.image({
            parent = device_row,
            x = 10,
            y = 12,
            w = icon_size,
            h = icon_size,
            src = "/luadb/ble_device.png"
        })

        -- 设备名称
        airui.label({
            parent = device_row,
            x = icon_size + icon_spacing + 10,
            y = 8,
            w = row_width - icon_size - icon_spacing - btn_width - 3 * btn_spacing - 100,
            h = 20,
            text = device.name or "未知设备",
            font_size = 15,
            color = COLOR_TEXT_PRIMARY,
            font_weight = 1
        })

        -- MAC地址
        airui.label({
            parent = device_row,
            x = icon_size + icon_spacing + 10,
            y = 32,
            w = row_width - icon_size - icon_spacing - btn_width - 3 * btn_spacing - 100,
            h = 16,
            text = device.addr or "Unknown",
            font_size = 11,
            color = COLOR_TEXT_HINT
        })

        -- 信号强度颜色（根据RSSI值）
        local rssi_color = (device.rssi or -100) > -70 and COLOR_SUCCESS or
                          ((device.rssi or -100) > -85 and 0xff9800 or COLOR_ERROR)
        
        airui.label({
            parent = device_row,
            x = row_width - btn_width - btn_spacing - 90,
            y = 12,
            w = 80,
            h = 18,
            text = (device.rssi or -100) .. " dBm",
            font_size = 13,
            color = rssi_color,
            align = airui.TEXT_ALIGN_RIGHT
        })

        airui.label({
            parent = device_row,
            x = row_width - btn_width - btn_spacing - 90,
            y = 32,
            w = 80,
            h = 14,
            text = "信号强度",
            font_size = 10,
            color = 0xaaaaaa,
            align = airui.TEXT_ALIGN_RIGHT
        })

        -- 连接按钮
        airui.button({
            parent = device_row,
            x = row_width - btn_width - btn_spacing,
            y = 16,
            w = btn_width,
            h = 32,
            text = "连接",
            font_size = 13,
            style = {
                bg_color = COLOR_SUCCESS,
                pressed_bg_color = 0x45a049,
                text_color = 0xffffff,
                radius = 16
            },
            on_click = function() handle_device_connect_click(device) end
        })
    end
end

--[[
更新扫描按钮状态
根据当前扫描状态更新按钮文字和样式
]]
local function update_scan_btn()
    log.info("ble_transfer", "update_scan_btn 被调用，scan_btn:", scan_btn and "存在" or "nil", "is_scanning:", is_scanning)
    if scan_btn then
        local new_text = is_scanning and "停止扫描" or "开始扫描"
        log.info("ble_transfer", "更新按钮文字为:", new_text)
        scan_btn:set_text(new_text)
        scan_btn:set_style({
            bg_color = is_scanning and COLOR_ERROR or COLOR_SUCCESS,
            pressed_bg_color = is_scanning and 0xd32f2f or 0x45a049,
            text_color = 0xffffff,
            radius = 6
        })
    else
        log.warn("ble_transfer", "scan_btn 为 nil，无法更新按钮状态")
    end
end

--[[
停止扫描（仅停止，不关闭弹窗）
]]
local function stop_scan_only()
    is_scanning = false
    ble_manager.stop_scan()
    update_scan_btn()
    update_scan_modal()
    
    -- 同步更新主页面连接按钮状态
    if connect_btn and is_master and not is_connected then
        connect_btn:set_text("开始扫描")
    end
end

--[[
开始扫描（仅开始，更新UI）
]]
local function start_scan_only()
    is_scanning = true
    scan_devices = {}
    update_scan_btn()
    update_scan_modal()
    ble_manager.start_scan(function(device)
        if not is_scanning then return end
        -- 检查是否已存在
        for _, d in ipairs(scan_devices) do
            if d.addr == device.addr then
                d.rssi = device.rssi
                update_scan_modal()
                return
            end
        end
        -- 新设备插入到列表最前面
        table.insert(scan_devices, 1, device)
        update_scan_modal()
    end)
end

--[[
处理扫描按钮点击事件
根据当前扫描状态切换开始/停止扫描
]]
local function handle_scan_btn_click()
    log.info("ble_transfer", "扫描按钮被点击，当前扫描状态:", is_scanning)
    if is_scanning then
        log.info("ble_transfer", "调用 stop_scan_only()")
        stop_scan_only()
    else
        log.info("ble_transfer", "调用 start_scan_only()")
        start_scan_only()
    end
end

--[[
显示扫描设备弹窗
]]
local function show_scan_devices_modal()
    close_modal()
    scan_devices = {}
    
    -- 创建遮罩层
    modal_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        alpha = 128,
        on_click = close_scan_modal
    })
    
    -- 创建对话框（全屏）
    modal_dialog = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xffffff,
        radius = 0
    })
    
    -- 标题栏
    local header = airui.container({
        parent = modal_dialog,
        x = 0, y = 0,
        w = screen_w, h = 50,
        color = COLOR_PRIMARY
    })
    
    airui.label({
        parent = header,
        x = 20, y = 15,
        w = screen_w - 200,
        h = 20,
        text = "扫描到的设备",
        font_size = 16,
        color = 0xffffff,
        font_weight = 1
    })

    -- 停止/开始扫描按钮
    scan_btn = airui.button({
        parent = header,
        x = screen_w - 155,
        y = 10,
        w = 75, h = 30,
        text = is_scanning and "停止扫描" or "开始扫描",
        font_size = 13,
        style = {
            bg_color = is_scanning and COLOR_ERROR or COLOR_SUCCESS,
            pressed_bg_color = is_scanning and 0xd32f2f or 0x45a049,
            text_color = 0xffffff,
            radius = 6
        },
        on_click = handle_scan_btn_click
    })

    -- 关闭按钮
    airui.button({
        parent = header,
        x = screen_w - 75,
        y = 10,
        w = 55, h = 30,
        text = "关闭",
        font_size = 14,
        style = {
            bg_color = 0xffffff,
            pressed_bg_color = 0xf0f0f0,
            text_color = COLOR_PRIMARY,
            radius = 6
        },
        on_click = close_scan_modal
    })
    
    -- 内容区域
    scan_modal_content = airui.container({
        parent = modal_dialog,
        x = 10, y = 60,
        w = screen_w - 20, h = screen_h - 70,
        color = 0xf5f7fa,
        radius = 8
    })
    
    airui.label({
        parent = scan_modal_content,
        x = 0, y = 140,
        w = screen_w - 90, h = 20,
        text = "正在扫描...",
        font_size = 14,
        color = COLOR_TEXT_HINT,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
显示通用信息弹窗
@param title 弹窗标题
@param content 弹窗内容（多行文本）
]]
local function show_modal(title, content)
    close_modal()
    
    -- 创建遮罩层
    modal_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        alpha = 128,
        on_click = close_modal
    })
    
    -- 创建对话框（全屏）
    modal_dialog = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xffffff,
        radius = 0
    })
    
    -- 标题栏
    local header = airui.container({
        parent = modal_dialog,
        x = 0, y = 0,
        w = screen_w, h = 50,
        color = COLOR_PRIMARY,
        radius = 0
    })
    
    airui.label({
        parent = header,
        x = 0, y = 15,
        w = screen_w, h = 20,
        text = title,
        font_size = 16,
        color = 0xffffff,
        font_weight = 1,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 关闭按钮
    airui.button({
        parent = header,
        x = screen_w - 65, y = 10,
        w = 55, h = 30,
        text = "关闭",
        font_size = 14,
        style = {
            bg_color = 0xffffff,
            pressed_bg_color = 0xf0f0f0,
            text_color = COLOR_PRIMARY,
            radius = 6
        },
        on_click = close_modal
    })
    
    -- 内容容器
    local content_container = airui.container({
        parent = modal_dialog,
        x = 20, y = 65,
        w = screen_w - 40, h = screen_h - 85,
        color = 0xf5f7fa,
        radius = 8
    })
    
    -- 解析并显示多行内容
    local lines = {}
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    
    for i, line in ipairs(lines) do
        if i <= 10 then
            airui.label({
                parent = content_container,
                x = 12, y = 12 + (i - 1) * 20,
                w = screen_w - 128, h = 20,
                text = line,
                font_size = 14,
                color = COLOR_TEXT_PRIMARY
            })
        end
    end
end

--[[
显示连接模式弹窗
根据当前模式显示对应的连接模式说明
]]
local function show_usage_modal()
    local content
    if is_master then
        content = "1. 当前为主机模式，主动扫描连接其他设备\n2. 连接成功后即可互相收发文件\n3. 点击\"扫描设备\"查找附近的从机设备"
    else
        content = "1. 当前为从机模式，等待主机连接\n2. 连接成功后即可互相收发文件\n3. 点击\"开始广播\"让其他设备发现"
    end
    show_modal("连接模式", content)
end

--[[
处理文件查看按钮点击
@param file 文件信息表
]]
local function handle_view_file_click(file)
    add_log("查看文件: " .. file.name, "info")
    show_file_content_modal(file.path, file.name)
end

--[[
处理文件发送按钮点击
@param file 文件信息表
]]
local function handle_send_file_click(file)
    if not is_connected then
        add_log("未连接设备，请先建立连接", "warning")
        show_modal("提示", "未连接设备，请先建立连接后再发送文件")
        return
    end
    close_modal()
    add_log("准备发送文件: " .. file.name)
    -- 在协程中执行发送
    sys.taskInit(function()
        ble_manager.send_file(file.path)
    end)
end

--[[
显示文件选择弹窗
列出可发送的文件供用户选择
]]
local function show_file_select_modal()
    close_modal()
    
    log.info("ble_transfer", "调用 ble_manager.get_sendable_files()")
    local sendable_files = ble_manager.get_sendable_files()
    log.info("ble_transfer", "获取到可发送文件:", #sendable_files, "个")
    
    -- 创建遮罩层
    modal_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        alpha = 128,
        on_click = close_modal
    })
    
    -- 创建对话框
    modal_dialog = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xffffff,
        radius = 0
    })
    
    -- 标题栏
    local header = airui.container({
        parent = modal_dialog,
        x = 0, y = 0,
        w = screen_w, h = 50,
        color = COLOR_PRIMARY
    })
    
    airui.label({
        parent = header,
        x = 20, y = 15,
        w = 200, h = 20,
        text = "选择要发送的文件",
        font_size = 16,
        color = 0xffffff,
        font_weight = 1
    })
    
    airui.button({
        parent = header,
        x = screen_w - 70, y = 10,
        w = 60, h = 30,
        text = "关闭",
        font_size = 12,
        style = {
            bg_color = 0xffffff,
            pressed_bg_color = 0xf0f0f0,
            text_color = COLOR_PRIMARY,
            radius = 6
        },
        on_click = close_modal
    })
    
    -- 内容区域
    local content_area = airui.container({
        parent = modal_dialog,
        x = 10, y = 60,
        w = screen_w - 20, h = screen_h - 70,
        color = 0xf5f5f5,
        radius = 8
    })
    
    -- 无文件时显示提示
    if #sendable_files == 0 then
        airui.label({
            parent = content_area,
            x = 0, y = (screen_h - 70) / 2 - 20,
            w = screen_w - 20, h = 40,
            text = "暂无可发送的文件\n(支持: txt, lua, json, csv, log, md, zip)",
            font_size = 14,
            color = 0x999999,
            align = airui.TEXT_ALIGN_CENTER
        })
        return
    end
    
    -- 显示文件列表
    for i, file in ipairs(sendable_files) do
        if i > 10 then break end
        
        local row_width = screen_w - 40
        local btn_width = 50
        local btn_spacing = 10
        
        -- 文件行容器
        local file_row = airui.container({
            parent = content_area,
            x = 10, y = (i - 1) * 50 + 10,
            w = row_width, h = 45,
            color = 0xffffff,
            radius = 6
        })
        
        -- 文件名标签
        local name_label_width = row_width - 2 * btn_width - 3 * btn_spacing
        airui.label({
            parent = file_row,
            x = 10, y = 8,
            w = name_label_width, h = 14,
            text = file.name,
            font_size = 13,
            color = COLOR_TEXT_PRIMARY
        })
        
        -- 文件大小
        airui.label({
            parent = file_row,
            x = 10, y = 24,
            w = 100, h = 12,
            text = format_file_size(file.size),
            font_size = 11,
            color = 0x999999
        })
        
        -- 查看按钮
        airui.button({
            parent = file_row,
            x = row_width - 2 * btn_width - 2 * btn_spacing, y = 8,
            w = btn_width, h = 28,
            text = "查看",
            font_size = 12,
            style = {
                bg_color = COLOR_INFO,
                pressed_bg_color = 0x1976d2,
                text_color = 0xffffff,
                radius = 4
            },
            on_click = function() handle_view_file_click(file) end
        })
        
        -- 发送按钮
        airui.button({
            parent = file_row,
            x = row_width - btn_width - btn_spacing, y = 8,
            w = btn_width, h = 28,
            text = "发送",
            font_size = 12,
            style = {
                bg_color = COLOR_SUCCESS,
                pressed_bg_color = 0x45a049,
                text_color = 0xffffff,
                radius = 4
            },
            on_click = function() handle_send_file_click(file) end
        })
    end
end

--[[
显示文件内容弹窗
用于预览文件内容
@param file_path 文件路径
@param file_name 文件名
]]
local function show_file_content_modal(file_path, file_name)
    close_modal()

    -- 读取文件内容
    local file = io.open(file_path, "rb")
    local content = ""
    local is_binary = false
    local file_size = 0

    if file then
        -- 获取文件大小
        file:seek("end")
        file_size = file:seek()
        file:seek("set", 0)
        
        -- 最多读取2000字节用于预览
        content = file:read(2000) or ""
        file:close()

        -- 检测是否为二进制文件
        for i = 1, math.min(#content, 100) do
            local byte = content:byte(i)
            if byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then
                is_binary = true
                break
            end
        end

        -- 格式化内容
        if is_binary then
            content = "[二进制文件，无法文本预览]\n文件大小: " .. file_size .. " 字节"
        elseif #content == 0 then
            content = "[空文件]"
        else
            content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
            if file_size > 2000 then
                content = content .. "\n\n[文件过长，仅显示前2000字节，总大小: " .. file_size .. " 字节]"
            end
        end
    else
        content = "[无法读取文件: " .. file_path .. "]"
    end
    
    -- 创建遮罩层
    modal_mask = airui.container({
        parent = win_id,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        alpha = 180
    })
    
    -- 创建弹窗（全屏）
    local modal_w, modal_h = screen_w, screen_h
    
    modal_dialog = airui.container({
        parent = win_id,
        x = 0, y = 0,
        w = modal_w, h = modal_h,
        color = 0xffffff,
        radius = 0
    })
    
    -- 标题栏
    airui.container({
        parent = modal_dialog,
        x = 0, y = 0,
        w = modal_w, h = 60,
        color = COLOR_SUCCESS,
        radius = 0
    })
    
    -- 标题
    airui.label({
        parent = modal_dialog,
        x = 20, y = 20,
        w = modal_w - 80, h = 20,
        text = file_name,
        font_size = 18,
        color = 0xffffff
    })
    
    -- 关闭按钮
    airui.button({
        parent = modal_dialog,
        x = modal_w - 75, y = 15,
        w = 55, h = 30,
        text = "关闭",
        font_size = 14,
        style = {
            bg_color = 0xffffff,
            pressed_bg_color = 0xf0f0f0,
            text_color = COLOR_SUCCESS,
            radius = 6
        },
        on_click = close_modal
    })

    -- 文件信息
    airui.label({
        parent = modal_dialog,
        x = 20, y = 65,
        w = modal_w - 40, h = 20,
        text = "大小: " .. format_file_size_detailed(file_size) .. " | 路径: " .. file_path,
        font_size = 12,
        color = COLOR_TEXT_SECONDARY
    })

    -- 内容区域背景
    local content_bg = airui.container({
        parent = modal_dialog,
        x = 15, y = 90,
        w = modal_w - 30, h = modal_h - 105,
        color = 0xf5f5f5,
        radius = 8
    })
    
    -- 文件内容
    airui.label({
        parent = content_bg,
        x = 10, y = 10,
        w = modal_w - 50, h = modal_h - 125,
        text = content,
        font_size = 12,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT,
        line_wrap = true
    })
end

--[[
显示使用说明弹窗
包含下载链接和二维码
]]
local function show_mode_modal()
    close_modal()

    -- 创建遮罩层
    modal_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        alpha = 180,
        on_click = close_modal
    })

    -- 创建对话框（全屏）
    modal_dialog = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xffffff,
        radius = 0
    })

    -- 标题栏
    local header = airui.container({
        parent = modal_dialog,
        x = 0, y = 0,
        w = screen_w, h = 50,
        color = COLOR_WARNING,
        radius = 0
    })

    airui.label({
        parent = header,
        x = 0, y = 15,
        w = screen_w, h = 20,
        text = "使用说明",
        font_size = 16,
        color = 0xffffff,
        font_weight = 1,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 关闭按钮
    airui.button({
        parent = header,
        x = screen_w - 65, y = 10,
        w = 55, h = 30,
        text = "关闭",
        font_size = 14,
        style = {
            bg_color = 0xffffff,
            pressed_bg_color = 0xf0f0f0,
            text_color = COLOR_WARNING,
            radius = 6
        },
        on_click = close_modal
    })

    -- 内容区域
    local content_y = 65

    -- 使用说明
    airui.label({
        parent = modal_dialog,
        x = 20, y = content_y,
        w = screen_w - 40, h = 60,
        text = "• 设备 <-> 设备：一个主机，一个从机\n• 设备 <-> 电脑/手机：电脑/手机作为主机，设备作为从机",
        font_size = 13,
        color = COLOR_TEXT_PRIMARY
    })

    content_y = content_y + 70

    -- 分隔线
    airui.container({
        parent = modal_dialog,
        x = 20, y = content_y,
        w = screen_w - 40, h = 1,
        color = 0xe0e0e0
    })

    content_y = content_y + 15

    -- 电脑端下载说明
    airui.label({
        parent = modal_dialog,
        x = 20, y = content_y,
        w = screen_w - 40, h = 20,
        text = "电脑端/手机端下载",
        font_size = 15,
        color = COLOR_TEXT_PRIMARY,
        font_weight = 1
    })

    content_y = content_y + 28

    airui.label({
        parent = modal_dialog,
        x = 20, y = content_y,
        w = screen_w - 40, h = 40,
        text = "请访问以下链接下载蓝牙文件传输的电脑端或手机端：",
        font_size = 12,
        color = COLOR_TEXT_SECONDARY
    })

    content_y = content_y + 45

    -- 链接显示框
    local link_bg = airui.container({
        parent = modal_dialog,
        x = 20, y = content_y,
        w = screen_w - 40, h = 70,
        color = 0xf5f5f5,
        radius = 8
    })

    airui.label({
        parent = link_bg,
        x = 10, y = 8,
        w = screen_w - 60, h = 54,
        text = "https://gitee.com/openLuat/LuatOS/blob/master/module/AirUI/app_store/vertical_app/ble_transfer/ble_transfer_pc.html",
        font_size = 10,
        color = COLOR_INFO
    })

    content_y = content_y + 80

    -- 二维码提示
    airui.label({
        parent = modal_dialog,
        x = 20, y = content_y,
        w = screen_w - 40, h = 20,
        text = "请扫描二维码访问下载页面：",
        font_size = 12,
        color = COLOR_TEXT_SECONDARY
    })

    content_y = content_y + 35

    -- 二维码区域
    local qr_size = 150
    local qr_x = (screen_w - qr_size) / 2

    -- 二维码边框
    airui.container({
        parent = modal_dialog,
        x = qr_x - 5, y = content_y - 5,
        w = qr_size + 10, h = qr_size + 10,
        color = 0xffffff,
        border_width = 2,
        border_color = 0xe0e0e0,
        radius = 8
    })

    -- 动态生成二维码
    airui.qrcode({
        parent = modal_dialog,
        x = qr_x, y = content_y,
        size = qr_size,
        data = "https://gitee.com/openLuat/LuatOS/blob/master/module/AirUI/app_store/vertical_app/ble_transfer/ble_transfer_pc.html",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    -- 二维码下方提示
    airui.label({
        parent = modal_dialog,
        x = 20, y = content_y + qr_size + 10,
        w = screen_w - 40, h = 20,
        text = "（如二维码无法显示，请手动复制上方链接）",
        font_size = 10,
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
处理模式切换确认
@param target_mode 目标模式（true=主机，false=从机）
]]
local function handle_mode_switch_confirm(target_mode)
    close_modal()
    add_log("模式切换，准备重启设备...", "warning")
    
    -- 保存模式到fskv
    if fskv then
        local ok, err = pcall(fskv.init)
        if not ok then
            log.error("ble_transfer", "fskv初始化失败:", err)
        end
        fskv.set("ble_transfer_mode", target_mode and "master" or "slave")
        log.info("ble_transfer", "模式已保存:", target_mode and "master" or "slave")
    end
    
    -- 延迟重启
    sys.timerStart(function()
        rtos.reboot()
    end, 1000)
end

--[[
显示模式切换确认弹窗
@param target_mode 目标模式（true=主机，false=从机）
]]
local function show_mode_switch_confirm(target_mode)
    close_modal()
    
    local current_mode_name = is_master and "主机模式" or "从机模式"
    local target_mode_name = target_mode and "主机模式" or "从机模式"
    
    -- 创建遮罩层
    modal_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        alpha = 180
    })
    
    -- 创建对话框
    modal_dialog = airui.container({
        parent = airui.screen,
        x = 40, y = 100,
        w = screen_w - 80, h = 220,
        color = 0xffffff,
        radius = 12
    })
    
    -- 标题栏
    local header = airui.container({
        parent = modal_dialog,
        x = 0, y = 0,
        w = screen_w - 80, h = 50,
        color = 0xFF5722,
        radius = {12, 12, 0, 0}
    })
    
    airui.label({
        parent = header,
        x = 0, y = 15,
        w = screen_w - 80, h = 20,
        text = "确认切换模式",
        font_size = 16,
        color = 0xffffff,
        font_weight = 1,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 提示内容
    local content_text = string.format("切换到%s需要重启设备。\n\n当前模式：%s\n目标模式：%s\n\n确定要切换吗？", 
        target_mode_name, current_mode_name, target_mode_name)
    
    airui.label({
        parent = modal_dialog,
        x = 20, y = 65,
        w = screen_w - 120, h = 100,
        text = content_text,
        font_size = 14,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 取消按钮
    airui.button({
        parent = modal_dialog,
        x = 30, y = 170,
        w = (screen_w - 140) / 2, h = 40,
        text = "取消",
        font_size = 14,
        style = {
            bg_color = 0xe0e0e0,
            pressed_bg_color = 0xd0d0d0,
            text_color = COLOR_TEXT_PRIMARY,
            radius = 8
        },
        on_click = close_modal
    })
    
    -- 确认按钮
    airui.button({
        parent = modal_dialog,
        x = 30 + (screen_w - 140) / 2 + 10, y = 170,
        w = (screen_w - 140) / 2, h = 40,
        text = "确认重启",
        font_size = 14,
        style = {
            bg_color = 0xFF5722,
            pressed_bg_color = 0xE64A19,
            text_color = 0xffffff,
            radius = 8
        },
        on_click = function() handle_mode_switch_confirm(target_mode) end
    })
end

-- ==================== UI更新函数区 ====================

--[[
更新日志显示
]]
function update_log_display()
    if not log_container or not log_card then return end
    
    -- 重新创建日志容器
    log_container:destroy()
    log_container = airui.container({
        parent = log_card,
        x = 20, y = 52,
        w = screen_w - 2 * margin - 40, h = 130,
        color = 0x263238,
        radius = 12
    })
    
    -- 显示日志条目
    for i, entry in ipairs(log_entries) do
        if i > 6 then break end
        
        -- 根据级别选择颜色
        local color = 0xb0bec5
        if entry.level == "error" then
            color = 0xff5252
        elseif entry.level == "success" then
            color = 0x69f0ae
        elseif entry.level == "warning" then
            color = 0xffd740
        end
        
        -- 日志条目容器
        local log_entry = airui.container({
            parent = log_container,
            x = 16, y = 10 + (i - 1) * 20,
            w = screen_w - 2 * margin - 72, h = 20
        })
        
        -- 时间戳
        airui.label({
            parent = log_entry,
            x = 0, y = 0,
            w = 60, h = 20,
            text = entry.time,
            font_size = 12,
            color = 0x78909c
        })
        
        -- 消息内容
        airui.label({
            parent = log_entry,
            x = 65, y = 0,
            w = screen_w - 2 * margin - 137, h = 20,
            text = entry.message,
            font_size = 12,
            color = color
        })
    end
end

--[[
处理接收文件列表中的查看按钮点击
@param file 文件信息表
]]
local function handle_received_file_view(file)
    add_log("打开文件: " .. file.name, "info")
    show_file_content_modal(file.path, file.name)
end

--[[
处理接收文件列表中的删除按钮点击
@param file 文件信息表
]]
local function handle_received_file_delete(file)
    add_log("删除文件: " .. file.name, "info")
    local result = ble_manager.delete_received_file(file.name)
    if result then
        add_log("文件已删除: " .. file.name, "success")
    else
        add_log("删除失败: " .. file.name, "error")
    end
    update_file_list()
end

--[[
更新接收文件列表
]]
local function update_file_list()
    log.info("ble_transfer", "update_file_list: 被调用")
    
    if not file_list_container then
        log.warn("ble_transfer", "update_file_list: file_list_container 未初始化")
        return
    end
    
    if not receive_card then
        log.warn("ble_transfer", "update_file_list: receive_card 未初始化")
        return
    end
    
    -- 获取文件列表
    file_list = ble_manager.get_received_files()
    log.info("ble_transfer", "update_file_list: 获取到 " .. #file_list .. " 个文件")
    
    -- 如果正在传输中且文件列表为空，保留当前的进度显示，不刷新
    if is_transferring and #file_list == 0 then
        log.info("ble_transfer", "传输进行中，跳过空状态刷新")
        return
    end
    
    -- 重新创建文件列表容器
    file_list_container:destroy()
    file_list_container = airui.container({
        parent = receive_card,
        x = 20, y = 52,
        w = screen_w - 2 * margin - 40, h = 110
    })
    
    -- 无文件时显示空状态
    if #file_list == 0 then
        local empty_container = airui.container({
            parent = file_list_container,
            x = 0, y = 15,
            w = screen_w - 2 * margin - 40, h = 80
        })
        
        airui.image({
            parent = empty_container,
            x = (screen_w - 2 * margin - 40) / 2 - 24, y = 0,
            w = 48, h = 48,
            src = "/luadb/folder.png"
        })
        
        empty_state_label = airui.label({
            parent = empty_container,
            x = 0, y = 50,
            w = screen_w - 2 * margin - 40, h = 20,
            text = "暂无接收到的文件",
            font_size = 14,
            color = 0xaaaaaa,
            align = airui.TEXT_ALIGN_CENTER
        })
        return
    end
    
    -- 显示文件列表
    for i, file in ipairs(file_list) do
        if i > 3 then break end
        
        local row_width = screen_w - 2 * margin - 40
        local btn_width = 50
        local btn_spacing = 10
        
        -- 文件行容器
        local file_row = airui.container({
            parent = file_list_container,
            x = 0, y = (i - 1) * 35,
            w = row_width, h = 32,
            color = 0xf5f5f5,
            radius = 6
        })
        
        -- 文件名
        airui.label({
            parent = file_row,
            x = 10, y = 6,
            w = row_width - 10 - 2 * btn_width - btn_spacing, h = 20,
            text = file.name,
            font_size = 13,
            color = COLOR_TEXT_PRIMARY
        })
        
        -- 查看按钮
        airui.button({
            parent = file_row,
            x = row_width - 2 * btn_width - btn_spacing, y = 4,
            w = btn_width, h = 24,
            text = "查看",
            font_size = 10,
            style = {
                bg_color = COLOR_INFO,
                pressed_bg_color = 0x1976d2,
                text_color = 0xffffff,
                radius = 4
            },
            on_click = function() handle_received_file_view(file) end
        })

        -- 删除按钮
        airui.button({
            parent = file_row,
            x = row_width - btn_width, y = 4,
            w = btn_width, h = 24,
            text = "删除",
            font_size = 10,
            style = {
                bg_color = 0xff4444,
                pressed_bg_color = 0xcc0000,
                text_color = 0xffffff,
                radius = 4
            },
            on_click = function() handle_received_file_delete(file) end
        })
    end
end

--[[
更新连接状态显示
@param connected 是否已连接
@param name 设备名称
@param state 状态描述
]]
local function update_connection_status(connected, name, state)
    log.info("ble_transfer", "update_connection_status 被调用:", connected, name, state)
    
    is_connected = connected
    device_name = name or "未连接设备"
    device_state = state or (connected and "已连接" or "等待连接")
    
    -- 更新设备名称标签
    if device_name_label then
        device_name_label:set_text(device_name)
        log.info("ble_transfer", "device_name_label 已更新为:", device_name)
    end
    
    -- 更新设备状态标签
    if device_state_label then
        device_state_label:set_text(device_state)
        device_state_label:set_color(connected and COLOR_SUCCESS or COLOR_TEXT_HINT)
        log.info("ble_transfer", "device_state_label 已更新为:", device_state)
    end
    
    -- 更新状态点
    if state_dot then
        state_dot:set_color(connected and COLOR_SUCCESS or 0xcccccc)
    end
    
    -- 更新连接按钮文字
    if connect_btn then
        if is_master then
            connect_btn:set_text(is_scanning and "停止扫描" or "开始扫描")
        else
            connect_btn:set_text(is_broadcasting and "停止广播" or "开始广播")
        end
    end
end

-- ==================== UI创建函数区 ====================

--[[
创建切换开关的滑块
@param is_right 是否显示在右侧（主机模式）
]]
local function create_toggle_knob(is_right)
    if toggle_knob_container then
        toggle_knob_container:destroy()
    end
    toggle_knob_container = airui.container({
        parent = toggle_bg,
        x = is_right and 56 or 4,
        y = 2,
        w = 28, h = 28,
        color = 0xffffff,
        radius = 14
    })
end

--[[
创建切换开关的文字
@param is_master_mode 是否主机模式
]]
local function create_toggle_text(is_master_mode)
    if toggle_text_label then
        toggle_text_label:destroy()
    end
    toggle_text_label = airui.label({
        parent = toggle_bg,
        x = is_master_mode and 8 or 35,
        y = 8,
        w = 50, h = 16,
        text = is_master_mode and "主机" or "从机",
        font_size = 12,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
处理模式切换点击
]]
local function handle_mode_toggle_click()
    if is_connected then
        add_log("请先断开当前连接再切换模式", "warning")
        return
    end
    
    local target_mode = not is_master
    show_mode_switch_confirm(target_mode)
end

--[[
创建页面头部
@param parent 父容器
@return 头部容器
]]
local function create_header(parent)
    -- 头部背景
    local header = airui.container({
        parent = parent,
        x = 0, y = 0,
        w = screen_w, h = 70,
        color = COLOR_PRIMARY
    })

    -- 返回按钮
    airui.button({
        parent = header,
        x = 10, y = 19,
        w = 40, h = 32,
        text = "<-",
        font_size = 16,
        style = {
            bg_color = 0xffffff,
            pressed_bg_color = 0xf0f0f0,
            text_color = COLOR_PRIMARY,
            radius = 16
        },
        on_click = function() ble_transfer_win.go_back() end
    })

    -- 标题容器
    local title_container = airui.container({
        parent = header,
        x = 60, y = 10,
        w = 200, h = 50
    })

    -- 主标题
    airui.label({
        parent = title_container,
        x = 0, y = 0,
        w = 200, h = 25,
        text = "蓝牙文件传输",
        font_size = 18,
        color = 0xffffff,
        font_weight = 1
    })

    -- 副标题
    subtitle_label = airui.label({
        parent = title_container,
        x = 0, y = 30,
        w = 200, h = 20,
        text = is_master and "主机模式 - 等待连接" or "从机模式 - 等待连接",
        font_size = 11,
        color = 0xffffffcc
    })

    -- 模式切换区域
    local role_container = airui.container({
        parent = header,
        x = screen_w - 150, y = 19,
        w = 135, h = 32
    })

    airui.label({
        parent = role_container,
        x = 0, y = 8,
        w = 40, h = 24,
        text = "模式",
        font_size = 14,
        color = 0xffffffcc
    })

    -- 切换开关背景
    toggle_bg = airui.container({
        parent = role_container,
        x = 45, y = 0,
        w = 90, h = 32,
        color = COLOR_SUCCESS,
        radius = 16
    })
    
    -- 创建滑块和文字
    create_toggle_knob(is_master)
    create_toggle_text(is_master)
    
    -- 点击区域
    airui.container({
        parent = role_container,
        x = 45, y = 0,
        w = 90, h = 32,
        on_click = handle_mode_toggle_click
    })

    return header
end

--[[
创建帮助按钮区域
@param parent 父容器
@param y 垂直位置
@return 下一个元素的Y坐标
]]
local function create_help_buttons(parent, y)
    local container = airui.container({
        parent = parent,
        x = margin, y = y,
        w = screen_w - 2 * margin, h = 50
    })

    local btn_w = (screen_w - 2 * margin - 10) / 2

    -- 使用说明按钮
    airui.button({
        parent = container,
        x = 0, y = 0,
        w = btn_w, h = 50,
        text = "使用说明",
        font_size = 14,
        font_weight = 1,
        style = {
            bg_color = 0xe8eaf6,
            pressed_bg_color = 0xc5cae9,
            radius = 12
        },
        on_click = show_mode_modal
    })

    -- 连接模式按钮
    airui.button({
        parent = container,
        x = btn_w + 10, y = 0,
        w = btn_w, h = 50,
        text = "连接模式",
        font_size = 14,
        font_weight = 1,
        style = {
            bg_color = 0xfff3e0,
            pressed_bg_color = 0xffe0b2,
            radius = 12
        },
        on_click = show_usage_modal
    })

    return y + 50 + 10
end

--[[
处理主连接按钮点击
]]
local function handle_connect_btn_click()
    if not ble_manager.init() then
        add_log("蓝牙初始化失败", "error")
        return
    end
    
    -- 已连接状态下，点击按钮断开连接
    if is_connected then
        add_log("断开连接...")
        ble_manager.disconnect()
        ble_manager.stop_slave()
        update_connection_status(false, "等待连接", is_broadcasting and "广播中..." or "未广播")
        return
    end
    
    -- 主机模式：扫描/停止扫描
    if is_master then
        if is_scanning then
            add_log("停止扫描设备")
            is_scanning = false
            connect_btn:set_text("开始扫描")
            ble_manager.stop_scan()
        else
            add_log("开始扫描设备...")
            is_scanning = true
            connect_btn:set_text("停止扫描")
            show_scan_devices_modal()
            ble_manager.start_scan(function(device)
                table.insert(scan_devices, device)
                update_scan_modal()
            end)
        end
        return
    end
    
    -- 从机模式：广播/停止广播
    if is_broadcasting then
        add_log("停止从机广播")
        is_broadcasting = false
        connect_btn:set_text("开始广播")
        ble_manager.stop_slave()
        update_connection_status(false, "等待连接", "未广播")
    else
        add_log("开始从机广播...")
        is_broadcasting = true
        connect_btn:set_text("停止广播")
        local result = ble_manager.start_slave("LuatOS-BLE-Transfer")
        if result then
            add_log("从机广播已启动", "success")
            update_connection_status(false, "等待连接", "广播中...")
        else
            add_log("广播启动失败", "error")
            is_broadcasting = false
            connect_btn:set_text("开始广播")
        end
    end
end

--[[
处理断开按钮点击
]]
local function handle_disconnect_btn_click()
    ble_manager.disconnect()
    ble_manager.stop_slave()
    update_connection_status(false)
    add_log("已断开连接")
end

--[[
创建连接状态卡片
@param parent 父容器
@param y 垂直位置
@return 下一个元素的Y坐标
]]
local function create_connect_card(parent, y)
    -- 卡片容器
    local card = airui.container({
        parent = parent,
        x = margin, y = y,
        w = screen_w - 2 * margin, h = 120,
        color = 0xffffff,
        radius = 16
    })

    -- 状态信息容器
    local status_container = airui.container({
        parent = card,
        x = 20, y = 20,
        w = screen_w - 2 * margin - 40, h = 50
    })

    -- 设备名称
    device_name_label = airui.label({
        parent = status_container,
        x = 0, y = 0,
        w = screen_w - 2 * margin - 40, h = 22,
        text = "未连接设备",
        font_size = 16,
        color = COLOR_TEXT_PRIMARY,
        font_weight = 1
    })

    -- 状态容器
    local state_container = airui.container({
        parent = status_container,
        x = 0, y = 28,
        w = screen_w - 2 * margin - 40, h = 22
    })

    -- 状态指示点
    state_dot = airui.container({
        parent = state_container,
        x = 0, y = 7,
        w = 8, h = 8,
        color = 0xcccccc,
        radius = 4
    })

    -- 状态文字
    device_state_label = airui.label({
        parent = state_container,
        x = 14, y = 0,
        w = screen_w - 2 * margin - 54, h = 22,
        text = "等待连接",
        font_size = 13,
        color = COLOR_TEXT_HINT
    })

    -- 按钮容器
    local btn_container = airui.container({
        parent = card,
        x = 20, y = 80,
        w = screen_w - 2 * margin - 40, h = 40
    })

    local btn_w = (screen_w - 2 * margin - 40 - 12) / 2

    -- 连接/扫描/广播按钮
    connect_btn = airui.button({
        parent = btn_container,
        x = 0, y = 0,
        w = btn_w, h = 40,
        text = is_master and "开始扫描" or "开始广播",
        font_size = 14,
        font_weight = 1,
        style = {
            bg_color = COLOR_PRIMARY,
            pressed_bg_color = 0x5e35a8,
            text_color = 0xffffff,
            radius = 20
        },
        on_click = handle_connect_btn_click
    })

    -- 断开按钮
    disconnect_btn = airui.button({
        parent = btn_container,
        x = btn_w + 12, y = 0,
        w = btn_w, h = 40,
        text = "断开",
        font_size = 14,
        font_weight = 1,
        style = {
            bg_color = COLOR_ERROR,
            pressed_bg_color = 0xd32f2f,
            text_color = 0xffffff,
            radius = 20
        },
        on_click = handle_disconnect_btn_click
    })

    return y + 120 + 16
end

--[[
处理发送区域点击
]]
local function handle_send_area_click()
    if not is_connected then
        add_log("请先连接设备", "warning")
        return
    end
    show_file_select_modal()
end

--[[
创建发送文件卡片
@param parent 父容器
@param y 垂直位置
@return 下一个元素的Y坐标
]]
local function create_send_card(parent, y)
    -- 卡片容器
    local card = airui.container({
        parent = parent,
        x = margin, y = y,
        w = screen_w - 2 * margin, h = 200,
        color = 0xffffff,
        radius = 16
    })

    -- 标题容器
    local title_container = airui.container({
        parent = card,
        x = 20, y = 15,
        w = screen_w - 2 * margin - 40, h = 32
    })

    -- 图标
    airui.image({
        parent = title_container,
        x = 0, y = 0,
        w = 32, h = 32,
        src = "/luadb/send_file.png"
    })

    -- 标题
    airui.label({
        parent = title_container,
        x = 42, y = 6,
        w = screen_w - 2 * margin - 82, h = 22,
        text = "发送文件",
        font_size = 16,
        color = COLOR_TEXT_PRIMARY,
        font_weight = 1
    })

    -- 限制提示
    local limit_container = airui.container({
        parent = card,
        x = 20, y = 52,
        w = screen_w - 2 * margin - 40, h = 32,
        color = 0xfff3e0,
        radius = 8
    })

    airui.label({
        parent = limit_container,
        x = 12, y = 10,
        w = screen_w - 2 * margin - 64, h = 12,
        text = "文件大小限制：最大1MB(104固件)/3MB(106固件)",
        font_size = 12,
        color = 0xe65100
    })

    -- 选择区域
    local select_area = airui.container({
        parent = card,
        x = 20, y = 90,
        w = screen_w - 2 * margin - 40, h = 90,
        color = 0xfafafa,
        radius = 12,
        border_width = 2,
        border_color = 0xd1c4e9,
        on_click = handle_send_area_click
    })

    -- 文件夹图标
    airui.image({
        parent = select_area,
        x = (screen_w - 2 * margin - 40) / 2 - 20, y = 15,
        w = 40, h = 40,
        src = "/luadb/folder.png"
    })

    -- 提示文字（发送时显示进度）
    send_hint_label = airui.label({
        parent = select_area,
        x = 10, y = 55,
        w = screen_w - 2 * margin - 60, h = 20,
        text = "请在连接成功后，点击选择文件",
        font_size = 14,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    return y + 200 + 16
end

--[[
处理刷新按钮点击
]]
local function handle_refresh_click()
    update_file_list()
    add_log("文件列表已刷新")
end

--[[
创建接收文件卡片
@param parent 父容器
@param y 垂直位置
@return 下一个元素的Y坐标
]]
local function create_receive_card(parent, y)
    -- 计算卡片高度
    local content_height = screen_h - 85
    local used_height = 66 + 136 + 216
    local card_height = content_height - used_height - 16 - 20
    
    if card_height < 120 then
        card_height = 120
    end
    
    -- 卡片容器
    receive_card = airui.container({
        parent = parent,
        x = margin, y = y,
        w = screen_w - 2 * margin, h = card_height,
        color = 0xffffff,
        radius = 16
    })

    -- 标题容器
    local title_container = airui.container({
        parent = receive_card,
        x = 20, y = 15,
        w = screen_w - 2 * margin - 40, h = 32
    })

    -- 图标
    airui.image({
        parent = title_container,
        x = 0, y = 0,
        w = 32, h = 32,
        src = "/luadb/receive_file.png"
    })

    -- 标题
    airui.label({
        parent = title_container,
        x = 42, y = 0,
        w = 200, h = 18,
        text = "接收文件",
        font_size = 16,
        color = COLOR_TEXT_PRIMARY,
        font_weight = 1
    })

    -- 自动保存提示
    airui.label({
        parent = title_container,
        x = 42, y = 18,
        w = 200, h = 14,
        text = "已自动保存",
        font_size = 10,
        color = COLOR_SUCCESS
    })

    -- 刷新按钮
    airui.button({
        parent = title_container,
        x = screen_w - 2 * margin - 110, y = 2,
        w = 60, h = 28,
        text = "刷新",
        font_size = 12,
        style = {
            bg_color = 0xf3f4f6,
            pressed_bg_color = 0xe5e7eb,
            text_color = 0x374151,
            radius = 8
        },
        on_click = handle_refresh_click
    })

    -- 文件区域高度 = 卡片高度 - 标题区域高度(52) - 底部边距(20)
    local file_area_height = card_height - 52 - 20
    
    -- 文件区域背景
    airui.container({
        parent = receive_card,
        x = 20, y = 52,
        w = screen_w - 2 * margin - 40, h = file_area_height,
        color = 0xfafafa,
        radius = 12,
        border_width = 2,
        border_color = 0xd1c4e9
    })

    -- 文件列表容器
    file_list_container = airui.container({
        parent = receive_card,
        x = 20, y = 52,
        w = screen_w - 2 * margin - 40, h = file_area_height
    })

    return y + card_height + 16
end

--[[
处理BLE连接回调
@param addr 连接的设备地址
]]
local function handle_ble_connect(addr)
    log.info("ble_transfer", "UI on_connect 回调已触发，addr:", addr)
    -- 更新广播状态为停止（连接成功后广播自动停止）
    is_broadcasting = false
    is_connected = true
    log.info("ble_transfer", "UI 调用 update_connection_status, device_name_label:", device_name_label and "存在" or "nil")
    update_connection_status(true, addr or "已连接", "已连接")
    add_log("设备已连接: " .. (addr or "未知设备"), "success")
end

--[[
处理BLE断开回调
@param addr 断开的设备地址
]]
local function handle_ble_disconnect(addr)
    -- 检查窗口是否还存在（防止应用关闭后访问已销毁的UI）
    if not win_id or not main_container then
        log.info("ble_transfer", "窗口已销毁，跳过断开连接UI更新")
        return
    end
    
    -- 更新广播状态（断开后广播通常也会停止）
    is_broadcasting = false
    is_connected = false
    update_connection_status(false, "等待连接", "未连接")
    add_log("设备已断开", "warning")
end

--[[
处理文件传输开始回调
@param name 文件名
@param size 文件大小
@param direction 传输方向 "send" 或 "receive"
]]
local function handle_transfer_start(name, size, direction)
    -- 检查窗口是否还存在
    if not win_id or not main_container then
        return
    end
    
    direction = direction or "send"  -- 默认发送方向
    add_log("开始传输: " .. name .. " (" .. size .. " bytes, " .. direction .. ")")
    
    -- 标记传输开始
    is_transferring = true
    
    -- 根据传输方向更新对应的区域
    if direction == "send" then
        -- 传输开始时，重置发送提示标签
        if send_hint_label then
            send_hint_label:set_text("准备发送...")
            send_hint_label:set_color(COLOR_PRIMARY)
        end
    elseif direction == "receive" then
        -- 传输开始时，如果接收文件列表为空，重置空状态标签
        log.info("ble_transfer", "传输开始(接收): empty_state_label=", empty_state_label and "存在" or "nil", "file_list长度=", #file_list)
        if empty_state_label and #file_list == 0 then
            log.info("ble_transfer", "设置空状态标签为: 准备接收...")
            empty_state_label:set_text("准备接收...")
            empty_state_label:set_color(COLOR_PRIMARY)
        else
            log.warn("ble_transfer", "无法设置空状态标签: empty_state_label=", empty_state_label and "存在" or "nil", "file_list长度=", #file_list)
        end
    end
end

--[[
处理文件传输进度回调
@param progress 进度百分比
@param current 当前字节数
@param total 总字节数
@param direction 传输方向 "send" 或 "receive"
]]
local function handle_transfer_progress(progress, current, total, direction)
    -- 检查窗口是否还存在
    if not win_id or not main_container then
        log.warn("ble_transfer", "handle_transfer_progress: 窗口不存在，跳过")
        return
    end
    
    direction = direction or "send"  -- 默认发送方向
    log.info("ble_transfer", "handle_transfer_progress 被调用: progress=", progress, "current=", current, "total=", total, "direction=", direction)
    
    -- 格式化进度显示
    local current_kb = current // 1024
    local total_kb = total // 1024
    local progress_text = string.format("传输进度: %d%% (%dKB/%dKB)", progress, current_kb, total_kb)
    
    -- 每10%或最后100%才打印日志，避免日志过多
    if progress % 10 == 0 or progress == 100 then
        add_log(progress_text, "info")
    end
    
    -- 更新设备状态标签显示进度
    if device_state_label and is_connected then
        device_state_label:set_text(string.format("传输中 %d%%", progress))
    end
    
    -- 根据传输方向更新对应的区域
    if direction == "send" then
        -- 更新发送区域提示标签显示进度
        if send_hint_label then
            if progress > 0 and progress < 100 then
                send_hint_label:set_text(string.format("正在发送 %d%% (%dKB/%dKB)", progress, current_kb, total_kb))
                send_hint_label:set_color(COLOR_PRIMARY)
            elseif progress >= 100 then
                send_hint_label:set_text("发送完成")
                send_hint_label:set_color(COLOR_SUCCESS)
                -- 3秒后恢复默认文本
                sys.timerStart(function()
                    if send_hint_label then
                        send_hint_label:set_text("请在连接成功后，点击选择文件")
                        send_hint_label:set_color(COLOR_TEXT_SECONDARY)
                    end
                end, 3000)
            end
        end
    elseif direction == "receive" then
        -- 更新接收文件区域的空状态标签显示进度（当没有文件时）
        log.info("ble_transfer", "检查接收区域进度显示: empty_state_label=", empty_state_label and "存在" or "nil", "file_list长度=", #file_list, "is_transferring=", is_transferring)
        if empty_state_label then
            if #file_list == 0 then
                if progress > 0 and progress < 100 then
                    log.info("ble_transfer", "【接收区域】更新进度: 正在接收 ", progress, "%")
                    empty_state_label:set_text(string.format("正在接收 %d%% (%dKB/%dKB)", progress, current_kb, total_kb))
                    empty_state_label:set_color(COLOR_PRIMARY)
                elseif progress >= 100 then
                    log.info("ble_transfer", "【接收区域】更新进度: 接收完成")
                    empty_state_label:set_text("接收完成")
                    empty_state_label:set_color(COLOR_SUCCESS)
                    -- 3秒后恢复默认文本
                    sys.timerStart(function()
                        if empty_state_label and #file_list == 0 then
                            empty_state_label:set_text("暂无接收到的文件")
                            empty_state_label:set_color(0xaaaaaa)
                        end
                    end, 3000)
                end
            else
                log.info("ble_transfer", "【接收区域】文件列表不为空(", #file_list, "个)，跳过更新")
            end
        else
            log.warn("ble_transfer", "【接收区域】empty_state_label 为 nil，无法更新")
        end
    end
end

--[[
处理文件传输完成回调
@param name 文件名
@param size 文件大小
]]
local function handle_transfer_complete(name, size)
    -- 检查窗口是否还存在
    if not win_id or not main_container then
        return
    end
    add_log("传输完成: " .. name .. " (" .. size .. " 字节)", "success")
    log.info("ble_transfer", "on_transfer_complete 回调触发:", name, size)
    
    -- 标记传输结束
    is_transferring = false
    
    -- 恢复设备状态标签
    if device_state_label and is_connected then
        device_state_label:set_text("已连接")
    end
    
    -- 传输完成后，重置发送提示标签
    if send_hint_label then
        send_hint_label:set_text("请在连接成功后，点击选择文件")
        send_hint_label:set_color(COLOR_TEXT_SECONDARY)
    end
    
    -- 传输完成后，如果文件列表仍为空，重置空状态标签
    if empty_state_label and #file_list == 0 then
        empty_state_label:set_text("暂无接收到的文件")
        empty_state_label:set_color(0xaaaaaa)
    end
    
    update_file_list()
end

--[[
处理文件传输错误回调
@param err 错误信息
]]
local function handle_transfer_error(err)
    -- 检查窗口是否还存在
    if not win_id or not main_container then
        return
    end
    add_log("传输错误: " .. err, "error")
    
    -- 标记传输结束
    is_transferring = false
    
    -- 恢复设备状态标签
    if device_state_label and is_connected then
        device_state_label:set_text("已连接")
    end
    
    -- 传输错误时，重置发送提示标签
    if send_hint_label then
        send_hint_label:set_text("请在连接成功后，点击选择文件")
        send_hint_label:set_color(COLOR_TEXT_SECONDARY)
    end
    
    -- 传输错误时，重置空状态标签
    if empty_state_label and #file_list == 0 then
        empty_state_label:set_text("暂无接收到的文件")
        empty_state_label:set_color(0xaaaaaa)
    end
end

--[[
处理文件接收完成回调
@param path 文件路径
@param name 文件名
@param size 文件大小
]]
local function handle_file_received(path, name, size)
    -- 检查窗口是否还存在
    if not win_id or not main_container then
        return
    end
    add_log("收到文件: " .. name .. " (" .. size .. " 字节)", "success")
    log.info("ble_transfer", "on_file_received 回调触发:", path, name, size)
    -- 延迟更新文件列表，确保文件系统已写入
    sys.timerStart(function()
        if win_id and main_container then
            update_file_list()
        end
    end, 100)
end

--[[
检查连接状态
定期检查BLE连接状态并更新UI
]]
local function check_connection_state()
    -- 检查窗口是否还存在
    if not win_id or not main_container then
        log.info("ble_transfer", "窗口已销毁，停止连接状态检查")
        connection_check_timer = nil
        return
    end
    
    if ble_manager.is_connected and ble_manager.is_connected() and not is_connected then
        -- 检测到已连接但 UI 未更新
        log.info("ble_transfer", "定时器检测到已连接，更新 UI")
        is_connected = true
        is_broadcasting = false
        update_connection_status(true, "已连接", "已连接")
        add_log("设备已连接", "success")
    elseif not ble_manager.is_connected() and is_connected then
        -- 检测到已断开但 UI 未更新
        log.info("ble_transfer", "定时器检测到已断开，更新 UI")
        is_connected = false
        is_broadcasting = false
        update_connection_status(false, "等待连接", "未连接")
        add_log("设备已断开", "warning")
    end
    -- 继续定时器
    if connection_check_timer then
        sys.timerStart(check_connection_state, 500)  -- 每500ms检查一次
    end
end

--[[
创建UI
初始化并创建所有UI组件
]]
local function create_ui()
    update_screen_size()
    
    -- 初始化并加载 fskv 保存的模式
    if fskv then
        -- 初始化 fskv
        local ok, err = pcall(fskv.init)
        if not ok then
            log.error("ble_transfer", "fskv初始化失败:", err)
        else
            log.info("ble_transfer", "fskv初始化成功")
        end
        
        -- 从 fskv 加载保存的模式
        local saved_mode = fskv.get("ble_transfer_mode")
        if saved_mode == "master" then
            is_master = true
            log.info("ble_transfer", "从fskv加载模式: 主机模式")
        elseif saved_mode == "slave" then
            is_master = false
            log.info("ble_transfer", "从fskv加载模式: 从机模式")
        else
            -- 首次运行，默认从机模式并保存到fskv
            is_master = false
            fskv.set("ble_transfer_mode", "slave")
            log.info("ble_transfer", "首次运行，默认从机模式并保存")
        end
    else
        log.warn("ble_transfer", "fskv不可用，使用默认从机模式")
        is_master = false
    end

    -- 主容器
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_BG
    })

    local y = 0

    -- 创建头部
    create_header(main_container)

    y = 70 + 15

    -- 内容容器（可滚动）
    local content_container = airui.container({
        parent = main_container,
        x = 0, y = y,
        w = screen_w, h = screen_h - y,
        scrollable = true
    })

    local scroll_y = 0

    -- 创建各个卡片
    scroll_y = create_help_buttons(content_container, scroll_y)
    scroll_y = create_connect_card(content_container, scroll_y)
    scroll_y = create_send_card(content_container, scroll_y)
    scroll_y = create_receive_card(content_container, scroll_y)
    
    -- 初始化文件列表
    update_file_list()
    add_log("系统就绪，等待连接设备...")
    
    -- 设置BLE回调
    ble_manager.set_callback("on_connect", handle_ble_connect)
    ble_manager.set_callback("on_disconnect", handle_ble_disconnect)
    ble_manager.set_callback("on_transfer_start", handle_transfer_start)
    ble_manager.set_callback("on_transfer_progress", handle_transfer_progress)
    ble_manager.set_callback("on_transfer_complete", handle_transfer_complete)
    ble_manager.set_callback("on_transfer_error", handle_transfer_error)
    ble_manager.set_callback("on_file_received", handle_file_received)
    
    -- UI 打开后，直接检查当前连接状态，不要等回调
    if ble_manager.is_connected and ble_manager.is_connected() then
        log.info("ble_transfer", "UI 打开时检测到已连接，直接更新状态")
        is_connected = true
        is_broadcasting = false
        update_connection_status(true, "已连接", "已连接")
        add_log("设备已连接", "success")
    end
    
    -- 启动连接状态检查定时器
    connection_check_timer = sys.timerStart(check_connection_state, 500)
end

--[[
处理窗口获得焦点
]]
local function handle_window_focus()
    log.info("ble_transfer", "蓝牙文件传输窗口获得焦点")
end

--[[
处理窗口失去焦点
]]
local function handle_window_blur()
    log.info("ble_transfer", "蓝牙文件传输窗口失去焦点")
end

--[[
处理窗口销毁
清理资源，停止定时器
]]
local function handle_window_destroy()
    -- 先清理BLE管理器，防止回调访问已销毁的UI
    if ble_manager and ble_manager.cleanup then
        ble_manager.cleanup()
    end
    
    -- 停止连接状态检查定时器
    if connection_check_timer then
        sys.timerStop(connection_check_timer)
        connection_check_timer = nil
    end
    
    -- 关闭弹窗
    close_modal()
    
    -- 断开BLE连接
    ble_manager.disconnect()
    ble_manager.stop_slave()
    
    -- 销毁主容器
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    win_id = nil
    log.info("ble_transfer", "蓝牙文件传输窗口已销毁")
end

--[[
打开窗口
创建并显示蓝牙文件传输窗口
]]
local function open_window()
    log.info("ble_transfer", "开始打开窗口...")
    
    if not exwin then
        log.error("ble_transfer", "exwin 模块未加载")
        return
    end
    
    win_id = exwin.open({
        on_create = function()
            create_ui()
            log.info("ble_transfer", "蓝牙文件传输窗口创建完成")
        end,
        on_destroy = handle_window_destroy,
        on_get_focus = handle_window_focus,
        on_lose_focus = handle_window_blur
    })
end

-- ==================== 模块导出 ====================

--[[
返回上一页
]]
function ble_transfer_win.go_back()
    -- 先清理BLE管理器，防止回调访问已销毁的UI
    if ble_manager and ble_manager.cleanup then
        ble_manager.cleanup()
    end
    if win_id then
        exwin.close(win_id)
    end
end

-- 订阅打开窗口事件
log.info("ble_transfer", "正在订阅 OPEN_BLE_TRANSFER_WIN 事件...")
sys.subscribe("OPEN_BLE_TRANSFER_WIN", function()
    log.info("ble_transfer", "收到 OPEN_BLE_TRANSFER_WIN 事件")
    open_window()
end)
log.info("ble_transfer", "OPEN_BLE_TRANSFER_WIN 事件订阅完成")

-- 导出模块
_G.ble_transfer_win = ble_transfer_win

log.info("ble_transfer", "ble_transfer_win 模块加载完成")

-- 返回模块接口
return {
    open = open_window,
    go_back = ble_transfer_win.go_back
}