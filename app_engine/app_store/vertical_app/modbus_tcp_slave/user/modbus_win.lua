--[[
@module  modbus_win
@summary 通讯管理页面模块
@version 1.0
@date    2026.05.11
@usage
本模块为通讯管理页面，显示Modbus TCP 从站配置入口。
订阅"OPEN_MODBUS_WIN"事件打开窗口。
]]

local modbus_tcp_slave = require("modbus_tcp_slave")

local win_id = nil
local main_container = nil
local content_container = nil
local title_bar = nil
local card1_container = nil
local card2_container = nil
local shared_keyboard = nil
local wifi_status_label = nil
local wifi_ip_label = nil
local wifi_netmask_label = nil
local wifi_gateway_label = nil
local wifi_check_timer_id = nil
local tcp_toggle_btn = nil

local tcp_is_open = false
local tcp_config_inputs = {}

local tcp_log_container = nil
local tcp_log_labels = {}
local tcp_reg_table = nil

--[[
内部函数：返回主菜单

@local
@function go_back
@return nil
@usage
-- 点击返回按钮时调用
-- 关闭当前窗口，返回到主菜单
]]
local function go_back()
    exwin.close(win_id)
end

-- ========================================
-- 通用函数：添加日志
-- ========================================
local function add_log(log_container, log_labels, log_text)
    if not log_container then return end

    local line_height = 32
    local max_lines = 6

    local new_label = airui.label({
        parent = log_container,
        x = 5,
        y = #log_labels * line_height,
        w = 280,
        h = line_height,
        text = log_text,
        font_size = 12,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    table.insert(log_labels, new_label)

    if #log_labels > max_lines then
        local old_label = table.remove(log_labels, 1)
        if old_label then
            old_label:destroy()
        end
        for i, label in ipairs(log_labels) do
            label:set_pos(5, (i - 1) * line_height)
        end
    end
end

-- ========================================
-- 通用函数：清空日志
-- ========================================
local function clear_logs(log_container, log_labels)
    if not log_container then return end
    for i = #log_labels, 1, -1 do
        local label = log_labels[i]
        if label then
            label:destroy()
        end
        log_labels[i] = nil
    end
end

-- ========================================
-- 通用函数：创建日志面板
-- ========================================
local function create_log_panel(tab_prefix, parent_container, y_button, y_container, clear_func)
    airui.label({
        parent = parent_container,
        x = 15,
        y = y_button + 5,
        w = 100,
        h = 26,
        text = "实时通讯日志",
        font_size = 16,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.button({
        parent = parent_container,
        x = 245,
        y = y_button,
        w = 60,
        h = 20,
        text = "清空",
        font_size = 14,
        style = {
            bg_color = 0xFF5722,
            border_color  = 0xFF5722,
            text_color = 0xFFFFFF
        },
        on_click = function()
            log.info("清空" .. tab_prefix .. "日志")
            clear_func()
        end
    })

    local card_container = airui.container({
        parent = parent_container,
        x = 10,
        y = y_container,
        w = 300,
        h = 170,
        color = 0xFFFFFF,
        radius = 8
    })

    local log_container = airui.container({
        parent = card_container,
        x = 5,
        y = 5,
        w = 290,
        h = 160,
        color = 0xF5F5F5
    })

    return log_container
end

-- ========================================
-- Modbus TCP 从站配置
-- ========================================

local function tcp_apply_config(config)
    if not content_container then return end

    if not config then return end
    -- 更新UI输入框
    if tcp_config_inputs["self_addr"] and tcp_config_inputs["self_addr"].ui then
        tcp_config_inputs["self_addr"].ui:set_text(tostring(config.self_addr or 1))
    end

    if tcp_config_inputs["listen_port"] and tcp_config_inputs["listen_port"].ui then
        tcp_config_inputs["listen_port"].ui:set_text(tostring(config.listen_port or 502))
    end

    log.info("modbus_tcp", "配置已加载到UI")
end

local function tcp_update_register(data)
    if not tcp_reg_table then return end
    local register_data = data.data or data
    if register_data then
        local reg0 = register_data[0]
        local reg1 = register_data[1]
        local reg2 = register_data[2]
        if reg0 then
            tcp_reg_table:set_cell_text(1, 2, tostring(reg0))
        end
        if reg1 then
            tcp_reg_table:set_cell_text(2, 2, tostring(reg1))
        end
        if reg2 then
            tcp_reg_table:set_cell_text(3, 2, tostring(reg2))
        end
    end
end


local function tcp_validate_config()
    if tcp_is_open then
        local msgbox = airui.msgbox({
            title = "提示",
            text = "请先关闭通讯再进行配置",
            buttons = { "确定" },
            on_action = function(self)
                self:hide()
            end
        })
        msgbox:show()
        return
    end

    local self_addr_input = tcp_config_inputs["self_addr"]
    if not self_addr_input or not self_addr_input.ui then return end
    local self_addr = tonumber(self_addr_input.ui:get_text())
    if not self_addr or self_addr < 1 or self_addr > 247 then
        local msgbox = airui.msgbox({
            title = "提示",
            text = "本机地址必须在1-247范围内",
            buttons = { "确定" },
            on_action = function(self)
                self:hide()
            end
        })
        msgbox:show()
        return
    end

    local listen_port_input = tcp_config_inputs["listen_port"]
    local listen_port = 502
    if listen_port_input and listen_port_input.ui then
        listen_port = tonumber(listen_port_input.ui:get_text()) or 502
    end

    local config = {
        self_addr = self_addr,
        listen_port = listen_port,
    }

    modbus_tcp_slave.save_config(config)

    log.info("modbus_tcp", "配置保存成功", "addr=" .. self_addr, "port=" .. listen_port)
end

--=========================================
-- 寄存器映射表弹窗
--=========================================
local register_dialog = nil
local register_overlay = nil
local register_list = {}
local register_row_map = {}

--[[
@function add_register_row
@summary 添加寄存器行到UI
@param addr number 寄存器地址
@param name string 功能名称
@param value number 初始值
]]
local function add_register_row(addr, name, value)
    -- 根据地址范围限制数值范围
    if addr >= 30001 then
        -- 输入寄存器：0-65535
        value = math.max(0, math.min(65535, value or 0))
    elseif addr >= 10001 then
        -- 离散输入：0-1
        value = math.max(0, math.min(1, value or 0))
    elseif addr >= 40001 then
        -- 保持寄存器：0-65535
        value = math.max(0, math.min(65535, value or 0))
    else
        -- 线圈：0-1
        value = math.max(0, math.min(1, value or 0))
    end

    -- 注册到 modbus_tcp_slave
    modbus_tcp_slave.add_register(addr, name, value)

    -- 检查地址是否已存在
    if register_row_map[addr] then
        -- 地址已存在，更新该行
        local row = register_row_map[addr]
        tcp_reg_table:set_cell_text(row, 1, name)
        tcp_reg_table:set_cell_text(row, 2, tostring(value))
        register_list[row].name = name
        register_list[row].value = value
        return
    end

    -- 地址不存在，添加新行
    local row = #register_list + 1  -- 从标题行之后开始插入
    local addr_str = string.format("%05d", addr)
    local data = {
        addr_str,
        name,
        tostring(value)
    }
    tcp_reg_table:insert("row", row, data)
    table.insert(register_list, {addr = addr, name = name, value = value})
    register_row_map[addr] = row
end

--[[
@function remove_register_row
@summary 从UI移除寄存器行
@param addr number 寄存器地址
]]
local function remove_register_row(addr)
    local row = register_row_map[addr]
    if row then
        tcp_reg_table:remove("row", row)
        table.remove(register_list, row)
        register_row_map[addr] = nil
        for a, r in pairs(register_row_map) do
            if r > row then
                register_row_map[a] = r - 1
            end
        end
    end
end

--[[
@function update_register_row
@summary 更新寄存器行显示
@param addr number 寄存器地址
@param value number 寄存器值
]]
local function update_register_row(addr, value)
    local row = register_row_map[addr]
    if row and tcp_reg_table then
        tcp_reg_table:set_cell_text(row, 2, tostring(value))
        if register_list[row] then
            register_list[row].value = value
        end
    end
end

--[[
@function close_register_dialog
@summary 关闭弹窗
]]
local function close_register_dialog()
    if register_dialog then
        register_dialog:destroy()
        register_dialog = nil
    end
    if register_overlay then
        register_overlay:destroy()
        register_overlay = nil
    end
end

--[[
@function show_create_register_dialog
@summary 显示创建寄存器弹窗
]]
local function show_create_register_dialog()
    register_overlay = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 420,
        color = 0x000000,
        color_opacity = 100
    })

    register_dialog = airui.container({
        parent = main_container,
        x = 20,
        y = 100,
        w = 280,
        h = 200,
        color = 0xFFFFFF,
        radius = 10
    })

    -- 标题
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 10,
        w = 260,
        h = 30,
        text = "创建寄存器",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 逻辑地址输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 50,
        w = 70,
        h = 35,
        text = "逻辑地址：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local addr_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 45,
        w = 190,
        h = 25,
        placeholder = "输入地址，如40001",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "numeric",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end,
        })
    })

    -- 功能名称输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 85,
        w = 70,
        h = 35,
        text = "功能名称：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local name_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 80,
        w = 190,
        h = 25,
        placeholder = "输入功能名称",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "pinyin_26",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end
        })
    })

    -- 数值输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 115,
        w = 70,
        h = 35,
        text = "数值：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local value_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 110,
        w = 190,
        h = 25,
        text = "0",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "numeric",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end
        })
    })

    -- 取消按钮
    airui.button({
        parent = register_dialog,
        x = 30,
        y = 145,
        w = 100,
        h = 30,
        text = "取消",
        font_size = 14,
        style = {
            bg_color = 0x9E9E9E,
            border_color = 0x9E9E9E,
            text_color = 0xFFFFFF
        },
        on_click = close_register_dialog
    })

    -- 确定按钮
    airui.button({
        parent = register_dialog,
        x = 150,
        y = 145,
        w = 100,
        h = 30,
        text = "确定",
        font_size = 14,
        style = {
            bg_color = 0x4CAF50,
            border_color = 0x4CAF50,
            text_color = 0xFFFFFF
        },
        on_click = function()
            local addr = tonumber(addr_input:get_text())
            local name = name_input:get_text() or ""
            local value = tonumber(value_input:get_text()) or 0

            if addr then
                add_register_row(addr, name, value)
            end
            close_register_dialog()
        end
    })
end

--[[
@function show_delete_register_dialog
@summary 显示删除寄存器弹窗
]]
local function show_delete_register_dialog()
    register_overlay = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 420,
        color = 0x000000,
        color_opacity = 100
    })

    register_dialog = airui.container({
        parent = main_container,
        x = 20,
        y = 100,
        w = 280,
        h = 170,
        color = 0xFFFFFF,
        radius = 10
    })

    -- 标题
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 10,
        w = 260,
        h = 30,
        text = "删除寄存器",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 逻辑地址输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 50,
        w = 70,
        h = 35,
        text = "逻辑地址：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local addr_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 45,
        w = 190,
        h = 25,
        placeholder = "输入地址，如40001",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "numeric",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end
        })
    })

    -- 取消按钮
    airui.button({
        parent = register_dialog,
        x = 30,
        y = 120,
        w = 100,
        h = 30,
        text = "取消",
        font_size = 14,
        style = {
            bg_color = 0x9E9E9E,
            border_color = 0x9E9E9E,
            text_color = 0xFFFFFF
        },
        on_click = close_register_dialog
    })

    -- 确定按钮
    airui.button({
        parent = register_dialog,
        x = 150,
        y = 120,
        w = 100,
        h = 30,
        text = "确定",
        font_size = 14,
        style = {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        },
        on_click = function()
            local addr = tonumber(addr_input:get_text())

            if addr and register_row_map[addr] then
                remove_register_row(addr)
                modbus_tcp_slave.remove_register(addr)
            end
            close_register_dialog()
        end
    })
end

sys.subscribe("modbus_log", function(data)
    if data.port_type == "tcp_slave" then
        local time_str = os.date("%H:%M:%S")
        add_log(tcp_log_container, tcp_log_labels, time_str .. " " .. data.message)
    end
end)

sys.subscribe("modbus_data_update", function(data)
    if data.port_type == "tcp_slave" then
        tcp_update_register(data.data)
    end
end)

sys.subscribe("modbus_register_update", function(data)
    if data.port_type == "tcp_slave" then
        update_register_row(data.addr, data.value)
    end
end)


--[[
@function create_config_card
@summary 创建参数配置卡片
@param parent object 父容器
@param y number 起始y坐标
@return nil
]]
local function create_config_card(parent, y)
    airui.label({
        parent = parent,
        x = 15,
        y = y + 5,
        w = 100,
        h = 26,
        text = "参数配置",
        font_size = 16,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.button({
        parent = parent,
        x = 180,
        y = y,
        w = 60,
        h = 20,
        text = "设置",
        font_size = 14,
        style = {
            bg_color = 0x5C6BC0,
            border_color  = 0x5C6BC0,
            text_color = 0xFFFFFF
        },
        on_click = tcp_validate_config
    })

    tcp_toggle_btn = airui.button({
        parent = parent,
        x = 245,
        y = y,
        w = 60,
        h = 20,
        text = tcp_is_open and "关闭" or "打开",
        font_size = 14,
        style = tcp_is_open and {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        } or {
            bg_color = 0x4CAF50,
            border_color = 0x4CAF50,
            text_color = 0xFFFFFF
        },
        on_click = function()
            tcp_is_open = not tcp_is_open

            if tcp_is_open then
                if not wlan.ready() then
                    airui.msgbox({
                        title = "提示",
                        text = "WiFi未连接，请先连接WiFi",
                        buttons = { "确定" },
                        on_action = function(self)
                            self:hide()
                        end
                    }):show()
                    tcp_is_open = false
                    return
                end

                log.info("modbus_tcp", "启动TCP从站")
                local ok, err = modbus_tcp_slave.start("tcp_slave")
                if not ok then
                    local err_msg = (err == "instance_already_exists") and "实例已存在，请先停止"
                        or (err == "exmodbus_create_failed") and "exmodbus创建失败"
                        or "启动失败"
                    airui.msgbox({
                        title = "启动失败",
                        text = err_msg,
                        buttons = { "确定" }
                    }):show()
                    tcp_is_open = false
                else
                    tcp_toggle_btn:set_text("关闭")
                    tcp_toggle_btn:set_style({
                        bg_color = 0xFF5722,
                        border_color = 0xFF5722,
                        text_color = 0xFFFFFF
                    })
                end
            else
                log.info("modbus_tcp", "停止TCP从站")
                local ok, err = modbus_tcp_slave.stop("tcp_slave")
                if not ok then
                    local err_msg = (err == "instance_not_found") and "实例不存在"
                        or "停止失败"
                    airui.msgbox({
                        title = "停止失败",
                        text = err_msg,
                        buttons = { "确定" }
                    }):show()
                    tcp_is_open = true
                else
                    tcp_toggle_btn:set_text("打开")
                    tcp_toggle_btn:set_style({
                        bg_color = 0x4CAF50,
                        border_color = 0x4CAF50,
                        text_color = 0xFFFFFF
                    })
                end
            end
        end
    })

    card1_container = airui.container({
        parent = parent,
        x = 10,
        y = y + 25,
        w = 300,
        h = 170,
        color = 0xFFFFFF,
        radius = 8
    })

    -- 本机地址
    airui.label({
        parent = card1_container,
        x = 10,
        y = 10,
        w = 80,
        h = 35,
        text = "本机地址",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local input_addr = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 5,
        w = 120,
        h = 25,
        text = "1",
        placeholder = "1-247",
        max_len = 10,
        keyboard = shared_keyboard
    })
    tcp_config_inputs["self_addr"] = {ui = input_addr}

    -- 本机端口号
    airui.label({
        parent = card1_container,
        x = 10,
        y = 45,
        w = 80,
        h = 35,
        text = "本机端口",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    tcp_config_inputs["listen_port"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 40,
        w = 120,
        h = 25,
        text = "502",
        placeholder = "请输入",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- WiFi连接状态
    airui.label({
        parent = card1_container,
        x = 10,
        y = 80,
        w = 80,
        h = 30,
        text = "WiFi状态",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_status_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 80,
        w = 120,
        h = 30,
        text = "未连接",
        font_size = 14,
        color = 0xFF5722,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- IP地址（标签显示）
    airui.label({
        parent = card1_container,
        x = 10,
        y = 100,
        w = 80,
        h = 30,
        text = "IP地址",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_ip_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 100,
        w = 120,
        h = 30,
        text = "--",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 子网掩码（标签显示）
    airui.label({
        parent = card1_container,
        x = 10,
        y = 120,
        w = 80,
        h = 30,
        text = "子网掩码",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_netmask_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 120,
        w = 120,
        h = 30,
        text = "--",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 网关（标签显示）
    airui.label({
        parent = card1_container,
        x = 10,
        y = 140,
        w = 80,
        h = 30,
        text = "网关",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_gateway_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 140,
        w = 120,
        h = 30,
        text = "--",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })
end

--[[
@function create_register_table
@summary 创建寄存器映射表
@param parent object 父容器
@param y number 标签y坐标
@return nil
]]
local function create_register_table(parent, y)
    airui.label({
        parent = parent,
        x = 15,
        y = y + 5,
        w = 100,
        h = 26,
        text = "寄存器映射表",
        font_size = 16,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 创建按钮
    airui.button({
        parent = parent,
        x = 180,
        y = y,
        w = 60,
        h = 20,
        text = "创建",
        font_size = 14,
        style = {
            bg_color = 0x4CAF50,
            border_color = 0x4CAF50,
            text_color = 0xFFFFFF
        },
        on_click = show_create_register_dialog
    })

    -- 删除按钮
    airui.button({
        parent = parent,
        x = 245,
        y = y,
        w = 60,
        h = 20,
        text = "删除",
        font_size = 14,
        style = {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        },
        on_click = show_delete_register_dialog
    })

    -- 表格容器
    card2_container = airui.container({
        parent = parent,
        x = 10,
        y = y + 25,
        w = 300,
        h = 170,
        color = 0xFFFFFF,
        radius = 8
    })

    -- 表格（初始只有标题行）
    tcp_reg_table = airui.table({
        parent = card2_container,
        x = 5,
        y = 5,
        w = 290,
        h = 160,
        rows = 1,
        cols = 3,
        col_width = 90,
        row_height = 25,
        style = {
            bg_color = 0xFFFFFF,
            cell_bg_color = 0xFFFFFF,
            cell_border_color = 0xCCCCCC,
            cell_border_width = 1,
            cell_text_color = 0x333333,
            cell_font_size = 12,
            cell_text_align = airui.TEXT_ALIGN_CENTER
        }
    })

    -- 标题行
    tcp_reg_table:set_cell_text(0, 0, "地址")
    tcp_reg_table:set_cell_text(0, 1, "功能")
    tcp_reg_table:set_cell_text(0, 2, "当前值")
end

--[[
@function create_log_card
@summary 创建日志卡片
@param parent object 父容器
@param y_label number 标签y坐标
@param y_container number 容器y坐标
@return nil
]]
local function create_log_card(parent, y_label, y_container)
    tcp_log_container = create_log_panel("modbus_tcp", parent, y_label, y_container, function()
        clear_logs(tcp_log_container, tcp_log_labels)
    end)
end

-- ========================================
-- 主窗口
-- ========================================
--[[
@function create_title_bar
@summary 创建标题栏
@param parent object 父容器
@return nil
]]
local function create_title_bar(parent)
    title_bar = airui.container({ parent = parent, x = 0, y = 0, w = 320, h = 60, color = 0x5C6BC0 })

    local back_btn = airui.container({
        parent = title_bar,
        x = 5,
        y = 15,
        w = 30,
        h = 25,
        color = 0xFFFFFF,
        radius = 20,
        color_opacity = 100,
        on_click = function()
            log.info("返回主菜单")
            go_back()
        end
    })
    airui.label({
        parent = back_btn,
        x = 0,
        y = 5,
        w = 30,
        h = 25,
        text = "←",
        font_size = 20,
        color = 0x5C6BC0,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = title_bar,
        x = 0,
        y = 20,
        w = 320,
        h = 28,
        text = "Modbus TCP 从站配置",
        font_size = 22,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
@function wifi_check_task
@summary WiFi状态检查任务
@return nil
]]
local function wifi_check_task()
    local is_connected = wlan.ready()
    log.info("WiFi状态检查", is_connected)
    if is_connected then
        local ip, netmask, gw = socket.localIP(socket.LWIP_STA)
        if wifi_status_label then
            wifi_status_label:set_text("已连接")
            wifi_status_label:set_color(0x4CAF50)
        end
        if wifi_ip_label then
            wifi_ip_label:set_text(ip or "--")
        end
        if wifi_netmask_label then
            wifi_netmask_label:set_text(netmask or "--")
        end
        if wifi_gateway_label then
            wifi_gateway_label:set_text(gw or "--")
        end
    else
        if wifi_status_label then
            wifi_status_label:set_text("未连接")
            wifi_status_label:set_color(0xFF5722)
        end
        if wifi_ip_label then
            wifi_ip_label:set_text("--")
        end
        if wifi_netmask_label then
            wifi_netmask_label:set_text("--")
        end
        if wifi_gateway_label then
            wifi_gateway_label:set_text("--")
        end
    end
end

local function wifi_disconnect_handler(status)
    if status == "DISCONNECTED" and tcp_is_open then
        log.info("modbus_tcp", "WiFi断开，从站停止")
        modbus_tcp_slave.stop("tcp_slave")
        tcp_is_open = false
        if tcp_toggle_btn then
            tcp_toggle_btn:set_text("打开")
            tcp_toggle_btn:set_style({
                bg_color = 0x4CAF50,
                border_color = 0x4CAF50,
                text_color = 0xFFFFFF
            })
        end
    end
    wifi_check_task()
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 320, h = 480, color = 0xE8E9EB, parent = airui.screen })

    create_title_bar(main_container)

    -- 创建内容容器
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 420,
        color = 0xE8E9EB
    })

    shared_keyboard = airui.keyboard({
        parent = main_container,
        x = 0,
        y = -10,
        w = 320,
        h = 120,
        mode = "numeric",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        on_commit = function(self)
            self:hide()
        end
    })

    create_config_card(content_container, 10)
    create_register_table(content_container, 210)
    create_log_card(content_container, 410, 435)

    wifi_check_timer_id = sys.timerLoopStart(wifi_check_task, 5000)
    wifi_check_task()
end

local function on_create()
    create_ui()
    local config = modbus_tcp_slave.get_config()
    tcp_apply_config(config)

    sys.subscribe("WLAN_STA_INC", wifi_disconnect_handler)
end

local function on_destroy()
    log.info("关闭modbus_win窗口")
    if tcp_is_open then
        log.info("modbus_tcp", "从站正在运行，先停止")
        modbus_tcp_slave.stop("tcp_slave")
        tcp_is_open = false
    end
    sys.unsubscribe("WLAN_STA_INC", wifi_disconnect_handler)
    if wifi_check_timer_id then
        sys.timerStop(wifi_check_timer_id)
        wifi_check_timer_id = nil
    end
    if tcp_reg_table then
        tcp_reg_table:destroy()
        tcp_reg_table = nil
    end
    tcp_log_labels = {}
    tcp_log_container = nil
    tcp_config_inputs = {}
    wifi_status_label = nil
    wifi_ip_label = nil
    wifi_netmask_label = nil
    wifi_gateway_label = nil
    if content_container then
        content_container:destroy()
        content_container = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function on_get_focus()
    log.info("modbus_win", "get_focus")
end

local function on_lose_focus()
    log.info("modbus_win", "lose_focus")
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_MODBUS_WIN", open_handler)