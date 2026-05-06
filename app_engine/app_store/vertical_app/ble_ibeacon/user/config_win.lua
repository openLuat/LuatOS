--[[
@module  config_win
@summary BLE iBeacon配置页面
@version 1.0.0
@date    2026.04.07
@author  王世豪
]]

local ble_manager = require "ble_manager"
local config_win = {}

-- UI控件
local ui_controls = {}

-- 键盘引用（共享一个键盘）
local shared_keyboard = nil

-- 当前绑定的输入框
local current_input = nil

-- 当前配置
local current_config = {}

-- 获取fskv键定义
local fskv_keys = ble_manager.get_fskv_keys()

-- 关闭错误对话框
local function close_error_dialog(error_dialog, error_mask)
    if error_dialog then
        error_dialog:destroy()
    end
    if error_mask then
        error_mask:destroy()
    end
end

-- 错误对话框确定按钮点击
local function on_error_dialog_ok(error_dialog, error_mask)
    close_error_dialog(error_dialog, error_mask)
end

-- 取消重启按钮点击
local function on_cancel_reboot_click(confirm_dialog, confirm_mask)
    close_error_dialog(confirm_dialog, confirm_mask)
end

-- 确认重启按钮点击
local function on_confirm_reboot_click(confirm_dialog, confirm_mask)
    close_error_dialog(confirm_dialog, confirm_mask)
    pm.reboot()
end

-- 键盘提交回调
local function on_keyboard_commit()
    log.info("Config", "键盘提交 - 当前输入: ", current_input and current_input:get_text() or "nil")
    -- 点击 √ 按钮时手动隐藏键盘
    if shared_keyboard and shared_keyboard.hide then
        log.info("Config", "点击 √ 按钮，隐藏键盘")
        shared_keyboard:hide()
    end
end

-- 加载配置
local function load_config()
    local config = ble_manager.get_config()
    
    if not fskv then
        log.warn("Config", "fskv不可用，使用默认配置")
        return config
    end
    
    ble_manager.fskv_init()
    
    local manufacturer_id = fskv.get(fskv_keys.manufacturer_id)
    if manufacturer_id then
        config.manufacturer_id = tonumber(manufacturer_id) or config.manufacturer_id
    end
    
    local uuid = fskv.get(fskv_keys.uuid)
    if uuid and uuid ~= "" then
        config.uuid = uuid
    end
    
    local major = fskv.get(fskv_keys.major)
    if major then
        config.major = tonumber(major) or config.major
    end
    
    local minor = fskv.get(fskv_keys.minor)
    if minor then
        config.minor = tonumber(minor) or config.minor
    end
    
    local tx_power = fskv.get(fskv_keys.tx_power)
    if tx_power then
        config.tx_power = tonumber(tx_power) or config.tx_power
    end
    
    local adv_interval = fskv.get(fskv_keys.adv_interval)
    if adv_interval then
        config.adv_interval = tonumber(adv_interval) or config.adv_interval
    end
    
    return config
end

-- 保存配置
local function save_config(config)
    if not fskv then
        log.error("Config", "fskv不可用，保存失败")
        return false
    end
    
    if not ble_manager.fskv_init() then
        return false
    end
    
    local ok = true
    ok = ok and fskv.set(fskv_keys.manufacturer_id, tostring(config.manufacturer_id))
    ok = ok and fskv.set(fskv_keys.uuid, config.uuid)
    ok = ok and fskv.set(fskv_keys.major, tostring(config.major))
    ok = ok and fskv.set(fskv_keys.minor, tostring(config.minor))
    ok = ok and fskv.set(fskv_keys.tx_power, tostring(config.tx_power))
    ok = ok and fskv.set(fskv_keys.adv_interval, tostring(config.adv_interval))
    
    if ok then
        log.info("Config", "配置保存成功")
    else
        log.error("Config", "配置保存失败")
    end
    
    return ok
end


-- 显示确认重启对话框
local function show_confirm_reboot_dialog()
    local confirm_dialog = nil
    local confirm_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x000000,
        alpha = 80
    })

    confirm_dialog = airui.container({
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
        on_click = function()
            on_cancel_reboot_click(confirm_dialog, confirm_mask)
        end
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
        on_click = function()
            on_confirm_reboot_click(confirm_dialog, confirm_mask)
        end
    })
end

-- 验证UUID格式
local function validate_uuid(uuid)
    -- UUID格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    local pattern = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    return uuid:match(pattern) ~= nil
end

-- 验证数字
local function validate_number(value, min, max)
    local num = tonumber(value)
    if not num then return false end
    if min and num < min then return false end
    if max and num > max then return false end
    return true
end

-- 将十进制转换为十六进制字符串（大写，不带前缀）
local function dec_to_hex(dec)
    local hex = string.format("%X", dec)
    return hex
end

-- 将十六进制字符串转换为十进制
local function hex_to_dec(hex)
    local num = tonumber(hex, 16)
    return num
end

-- 验证十六进制数字（0-65535）
local function validate_hex(value, min, max)
    -- 去除空白
    value = value:gsub("%s+", "")
    -- 检查是否都是十六进制字符
    if not value:match("^%x+$") then
        return false
    end
    local num = tonumber(value, 16)
    if not num then return false end
    if min and num < min then return false end
    if max and num > max then return false end
    return true, num
end

-- 存储输入框和值
local input_values = {}
local keyboards = {}

-- 获取输入框文本
local function get_input_text(key, default_value)
    -- 优先从 textarea 获取
    if ui_controls[key] and ui_controls[key].get_text then
        local text = ui_controls[key]:get_text()
        if text and text ~= "" then
            return text
        end
    end
    -- 其次从 input_values 获取
    if input_values[key] and input_values[key] ~= "" then
        return input_values[key]
    end
    return default_value
end

-- 保存按钮点击处理
local function on_save_click()
    log.info("Config", "点击保存按钮")

    -- 获取输入值
    local manufacturer_id_hex = get_input_text("manufacturer_id", dec_to_hex(current_config.manufacturer_id))
    local uuid = get_input_text("uuid", current_config.uuid)
    local major = get_input_text("major", current_config.major)
    local minor = get_input_text("minor", current_config.minor)
    local tx_power = get_input_text("tx_power", current_config.tx_power)
    local adv_interval = get_input_text("adv_interval", current_config.adv_interval)

    log.info("Config", "获取到的值 - Manufacturer ID (hex): ", manufacturer_id_hex)
    log.info("Config", "获取到的值 - UUID: ", uuid)
    log.info("Config", "获取到的值 - Major: ", major)


-- 显示错误对话框
local function show_error_dialog(title, message)
    local error_dialog = nil
    local error_mask = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x000000,
        alpha = 80
    })

    error_dialog = airui.container({
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
        on_click = on_error_dialog_ok
    })
end

    -- 验证Manufacturer ID (十六进制，0-FFFF)
    local ok, manufacturer_id = validate_hex(manufacturer_id_hex, 0, 0xFFFF)
    if not ok then
        show_error_dialog("输入错误", "Manufacturer ID必须是十六进制，范围 0-FFFF (0-65535)")
        return
    end

    -- 验证UUID
    if not validate_uuid(uuid) then
        show_error_dialog("输入错误", "UUID格式错误，请使用标准UUID格式\n格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
        return
    end

    -- 验证Major (0-65535)
    if not validate_number(major, 0, 65535) then
        show_error_dialog("输入错误", "Major必须是0-65535之间的数字")
        return
    end

    -- 验证Minor (0-65535)
    if not validate_number(minor, 0, 65535) then
        show_error_dialog("输入错误", "Minor必须是0-65535之间的数字")
        return
    end

    -- 验证发射功率 (-128到127)
    if not validate_number(tx_power, -128, 127) then
        show_error_dialog("输入错误", "发射功率必须是-128到127之间的数字")
        return
    end

    -- 验证广播间隔 (20-10240)
    if not validate_number(adv_interval, 20, 10240) then
        show_error_dialog("输入错误", "广播间隔必须是20-10240之间的数字")
        return
    end

    -- 构建配置
    local new_config = {
        manufacturer_id = tonumber(manufacturer_id),
        uuid = uuid,
        major = tonumber(major),
        minor = tonumber(minor),
        tx_power = tonumber(tx_power),
        adv_interval = tonumber(adv_interval)
    }

    -- 保存配置
    if save_config(new_config) then
        log.info("Config", "配置保存成功")
        show_confirm_reboot_dialog()
    else
        log.error("Config", "配置保存失败")
        show_error_dialog("保存失败", "配置保存失败，请重试")
    end
end

-- 创建共享键盘（只创建一次，所有输入框共用）
local function create_shared_keyboard(parent_container)
    if shared_keyboard then
        log.info("Config", "键盘已存在，跳过创建")
        return
    end
    log.info("Config", "开始创建键盘")
    shared_keyboard = airui.keyboard({
        parent = parent_container,
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
    log.info("Config", "键盘创建完成: ", shared_keyboard and "成功" or "失败")
end

-- 创建输入框（使用共享键盘）
local function create_input_field(parent_container, content_y, label, value, hint, key)
    -- 标签
    airui.label({
        parent = parent_container,
        x = 20, y = content_y, w = 440, h = 24,
        text = label,
        font_size = 13,
        color = 0x333333
    })

    -- 输入框背景
    local input_bg = airui.container({
        parent = parent_container,
        x = 20, y = content_y + 26, w = 440, h = 40,
        color = 0xF5F5F5,
        radius = 6
    })

    -- 使用textarea，绑定共享键盘（背景透明，使用父容器背景色，文字黑色）
    local input = airui.textarea({
        parent = input_bg,
        x = 10, y = 2, w = 420, h = 36,
        text = value .. "",
        font_size = 14,
        color = 0x333333,
        bg_color = 0x00000000,
        max_length = 100,
        keyboard = shared_keyboard,
        editable = true
    })

    -- 存储初始值和控件引用
    input_values[key] = value .. ""
    ui_controls[key] = input
    keyboards[key] = shared_keyboard

    return input
end

-- 创建设置页面
function config_win.create(parent_container)
    log.info("Config", "创建设置页面")

    -- 加载当前配置
    current_config = load_config()

    -- 创建内容容器（不使用scroll，直接放在parent_container中）
    local content = airui.container({
        parent = parent_container,
        x = 0, y = 0, w = 480, h = 652,
        color = 0xFFFFFF
    })

    -- 创建共享键盘（只创建一次）
    create_shared_keyboard(content)

    -- 标题
    airui.label({
        parent = content,
        x = 20, y = 16, w = 440, h = 36,
        text = "iBeacon配置",
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    local y_offset = 60

    -- Manufacturer ID输入
    ui_controls.manufacturer_id_input = create_input_field(
        content, y_offset,
        "厂商ID (hex 0-FFFF)",
        dec_to_hex(current_config.manufacturer_id),
        "FFFF",
        "manufacturer_id"
    )
    y_offset = y_offset + 78

    -- UUID输入
    ui_controls.uuid_input = create_input_field(
        content, y_offset,
        "UUID",
        current_config.uuid,
        "01020304-0506-0708-090A-0B0C0D0E0F10",
        "uuid"
    )
    y_offset = y_offset + 78

    -- Major输入
    ui_controls.major_input = create_input_field(
        content, y_offset,
        "Major",
        current_config.major,
        "1",
        "major"
    )
    y_offset = y_offset + 78

    -- Minor输入
    ui_controls.minor_input = create_input_field(
        content, y_offset,
        "Minor",
        current_config.minor,
        "2",
        "minor"
    )
    y_offset = y_offset + 78

    -- 发射功率输入
    ui_controls.tx_power_input = create_input_field(
        content, y_offset,
        "发射功率",
        current_config.tx_power,
        "-64",
        "tx_power"
    )
    y_offset = y_offset + 78

    -- 广播间隔输入
    ui_controls.adv_interval_input = create_input_field(
        content, y_offset,
        "广播间隔",
        current_config.adv_interval,
        "120",
        "adv_interval"
    )
    y_offset = y_offset + 78

    -- 保存按钮（放在右下角）
    airui.button({
        parent = content,
        x = 280, y = y_offset + 10, w = 180, h = 48,
        text = "保存配置",
        style = {
            bg_color = 0xE91E63,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = on_save_click
    })

    log.info("Config", "设置页面创建完成")
    return content
end

-- 销毁页面
function config_win.destroy()
    log.info("Config", "销毁设置页面")
    ui_controls = {}
    current_config = {}
    input_values = {}
    keyboards = {}
    shared_keyboard = nil
    current_input = nil
end

return config_win
