--[[
@module  ibeacon_win
@summary BLE iBeacon应用主界面
@version 1.0.0
@date    2026.04.07
@author  王世豪
]]

local ble_manager = require "ble_manager"
local config_win = require "config_win"
local ibeacon_win = {}

-- 窗口ID
local win_id = nil

-- UI控件
local ui_controls = {}

-- 当前页面状态
ibeacon_win.current_page = "broadcast"

-- 获取广播状态
local function get_broadcast_state()
    if ble_manager and ble_manager.get_broadcast_status then
        return ble_manager.get_broadcast_status()
    end
    return false
end

-- 创建界面
function ibeacon_win.on_create()
    log.info("iBeacon", "创建iBeacon界面")
    
    -- 初始化BLE管理器
    if ble_manager and ble_manager.init then
        ble_manager.init()
    end
    
    -- 创建主容器
    ui_controls.main_container = airui.container({
        x = 0, y = 0, w = 480, h = 800, 
        color = 0x2C3E50, 
        parent = airui.screen
    })
    
    -- 创建标题栏 (92px，包含系统状态栏区域)
    local header = airui.container({ 
        parent = ui_controls.main_container, 
        x = 0, y = 0, w = 480, h = 92, 
        color = 0xC2185B 
    })
    
    -- 返回按钮 (与标题垂直居中对齐)
    airui.button({
        parent = header,
        x = 16, y = 20, w = 40, h = 40,
        text = "←",
        style = {
            bg_color = 0xE91E63,
            text_color = 0xFFFFFF,
            radius = 20
        },
        on_click = ibeacon_win.go_back
    })
    
    -- 标题 (往下移，与返回按钮对齐)
    airui.label({ 
        parent = header, 
        x = 72, y = 26, w = 300, h = 40, 
        text = "iBeacon", 
        font_size = 20, 
        color = 0xFFFFFF
    })
    
    -- 创建内容区域 (800 - 92 - 56 = 652px)
    ui_controls.content_area = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 92, w = 480, h = 652,
        color = 0xFFFFFF
    })
    
    -- 创建底部导航 (56px)
    ui_controls.bottom_nav = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 744, w = 480, h = 56,
        color = 0xFFFFFF
    })
    
    -- 导航按钮点击 - 广播
local function on_nav_broadcast_click()
    log.info("iBeacon", "点击广播按钮")
    ibeacon_win.switch_page("broadcast")
end

-- 导航按钮点击 - 配置
local function on_nav_config_click()
    log.info("iBeacon", "点击配置按钮")
    ibeacon_win.switch_page("config")
end

-- 导航按钮点击 - 关于
local function on_nav_about_click()
    log.info("iBeacon", "点击关于按钮")
    ibeacon_win.switch_page("about")
end

-- 广播按钮
ui_controls.nav_broadcast = airui.button({
    parent = ui_controls.bottom_nav,
    x = 0, y = 0, w = 160, h = 56,
    text = "广播",
    style = {
        bg_color = 0xFFFFFF,
        text_color = 0xE91E63,
    },
    on_click = on_nav_broadcast_click
})

-- 配置按钮
ui_controls.nav_config = airui.button({
    parent = ui_controls.bottom_nav,
    x = 160, y = 0, w = 160, h = 56,
    text = "配置",
    style = {
        bg_color = 0xFFFFFF,
        text_color = 0x888888,
    },
    on_click = on_nav_config_click
})

-- 关于按钮
ui_controls.nav_about = airui.button({
    parent = ui_controls.bottom_nav,
    x = 320, y = 0, w = 160, h = 56,
    text = "关于",
    style = {
        bg_color = 0xFFFFFF,
        text_color = 0x888888,
    },
    on_click = on_nav_about_click
})
    
    -- 默认显示广播页面
    ibeacon_win.switch_page("broadcast")
    
    log.info("iBeacon", "界面创建完成")
end

-- 清除内容区域
function ibeacon_win.clear_content_area()
    log.info("iBeacon", "清除内容区域")
    if ui_controls.content_area then
        -- 销毁内容区域容器
        ui_controls.content_area:destroy()
        ui_controls.content_area = nil
    end
    -- 重新创建内容区域容器
    ui_controls.content_area = airui.container({
        parent = ui_controls.main_container,
        x = 0, y = 92, w = 480, h = 652,
        color = 0xFFFFFF
    })
end

-- 切换页面
function ibeacon_win.switch_page(page_name)
    log.info("iBeacon", "切换到页面: ", page_name)
    
    -- 先销毁当前页面的资源
    if ibeacon_win.current_page == "config" and config_win and config_win.destroy then
        log.info("iBeacon", "销毁配置页面资源")
        config_win.destroy()
    end
    
    -- 清除当前内容
    ibeacon_win.clear_content_area()
    
    -- 重置导航状态
    if ui_controls.nav_broadcast then
        ui_controls.nav_broadcast:set_style({ text_color = 0x888888 })
    end
    if ui_controls.nav_config then
        ui_controls.nav_config:set_style({ text_color = 0x888888 })
    end
    if ui_controls.nav_about then
        ui_controls.nav_about:set_style({ text_color = 0x888888 })
    end
    
    -- 根据页面名称创建对应内容
    if page_name == "broadcast" then
        log.info("iBeacon", "创建广播页面内容")
        ibeacon_win.create_broadcast_content()
        if ui_controls.nav_broadcast then
            ui_controls.nav_broadcast:set_style({ text_color = 0xE91E63 })
        end
    elseif page_name == "config" then
        log.info("iBeacon", "创建配置页面内容")
        ibeacon_win.create_config_content()
        if ui_controls.nav_config then
            ui_controls.nav_config:set_style({ text_color = 0xE91E63 })
        end
    elseif page_name == "about" then
        log.info("iBeacon", "创建关于页面内容")
        ibeacon_win.create_about_content()
        if ui_controls.nav_about then
            ui_controls.nav_about:set_style({ text_color = 0xE91E63 })
        end
    end
    
    ibeacon_win.current_page = page_name
end

-- 创建广播页面内容
function ibeacon_win.create_broadcast_content()
    -- 获取当前配置
    local config = ble_manager.get_config()
    local adv_interval = config and config.adv_interval or 120
    
    -- 主控制区
    local main_control = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 0, w = 480, h = 200,
        color = 0xFFFFFF
    })
    
    -- iBeacon图标
    ui_controls.beacon_circle = airui.image({
        parent = main_control,
        x = 208, y = 18, w = 64, h = 64,
        src = "/luadb/iBeacon.png",
        opacity = 255
    })
    
    -- 广播按钮
    local is_broadcasting = get_broadcast_state()
    ui_controls.broadcast_btn = airui.button({
        parent = main_control,
        x = 100, y = 140, w = 280, h = 48,
        text = is_broadcasting and "停止广播" or "开始广播",
        style = {
            bg_color = is_broadcasting and 0x757575 or 0xE91E63,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = ibeacon_win.toggle_broadcast
    })
    
    -- 状态面板
    local status_panel = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 200, w = 480, h = 100,
        color = 0xF8F9FA
    })
    
    -- 广播状态卡片
    local status_card1 = airui.container({
        parent = status_panel,
        x = 16, y = 20, w = 216, h = 80,
        color = 0xFFFFFF,
        radius = 12
    })
    
    airui.label({
        parent = status_card1,
        x = 0, y = 16, w = 216, h = 20,
        text = "广播状态",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    ui_controls.broadcast_status = airui.label({
        parent = status_card1,
        x = 0, y = 40, w = 216, h = 30,
        text = is_broadcasting and "广播中" or "已停止",
        font_size = 18,
        color = is_broadcasting and 0xE91E63 or 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 广播间隔卡片
    local status_card2 = airui.container({
        parent = status_panel,
        x = 248, y = 20, w = 216, h = 80,
        color = 0xFFFFFF,
        radius = 12
    })
    
    airui.label({
        parent = status_card2,
        x = 0, y = 16, w = 216, h = 20,
        text = "广播间隔",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = status_card2,
        x = 0, y = 40, w = 216, h = 30,
        text = adv_interval .. "ms",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 数据包展示区域
    local packet_section = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 300, w = 480, h = 352,
        color = 0xFFFFFF
    })
    
    airui.label({
        parent = packet_section,
        x = 20, y = 20, w = 440, h = 20,
        text = "广播数据包",
        font_size = 16,
        color = 0x333333
    })
    
    local packet_card = airui.container({
        parent = packet_section,
        x = 20, y = 50, w = 440, h = 270,
        color = 0x263238,
        radius = 12
    })
    
    airui.label({
        parent = packet_card,
        x = 16, y = 16, w = 408, h = 20,
        text = "Manufacturer Specific Data (iBeacon)",
        font_size = 14,
        color = 0x90A4AE
    })
    
    -- 根据当前配置生成数据包十六进制显示
    local config = ble_manager.get_config()
    
    -- Manufacturer ID (小端序)
    local manuf_id = config.manufacturer_id or 0xFFFF
    local manuf_id_low = string.format("%02X", manuf_id % 256)
    local manuf_id_high = string.format("%02X", math.floor(manuf_id / 256))
    
    -- UUID 转换为十六进制数组，每行8字节
    local uuid_str = config.uuid:gsub("-", "")
    local uuid_lines = {}
    for i = 1, #uuid_str, 16 do
        local line_str = uuid_str:sub(i, i + 15)
        local hex_parts = {}
        for j = 1, #line_str, 2 do
            table.insert(hex_parts, line_str:sub(j, j + 1))
        end
        table.insert(uuid_lines, table.concat(hex_parts, " "))
    end
    
    -- Major (大端序)
    local major = config.major or 1
    local major_high = string.format("%02X", math.floor(major / 256))
    local major_low = string.format("%02X", major % 256)
    
    -- Minor (大端序)
    local minor = config.minor or 2
    local minor_high = string.format("%02X", math.floor(minor / 256))
    local minor_low = string.format("%02X", minor % 256)
    
    -- Tx Power (转换为无符号字节十六进制)
    local tx_power = config.tx_power or -64
    local tx_power_byte = tx_power < 0 and (tx_power + 256) or tx_power
    local tx_power_hex = string.format("%02X", tx_power_byte)
    
    -- 构建显示行
    local packet_lines = {
        manuf_id_low .. " " .. manuf_id_high .. " // Manufacturer ID (" .. string.format("0x%04X", manuf_id) .. ")",
        "02 // iBeacon Type",
        "15 // Data Length (21 bytes)"
    }
    
    for i, line in ipairs(uuid_lines) do
        table.insert(packet_lines, line .. " // UUID" .. (i > 1 and " (cont)" or ""))
    end
    
    table.insert(packet_lines, major_high .. " " .. major_low .. " // Major (" .. major .. ")")
    table.insert(packet_lines, minor_high .. " " .. minor_low .. " // Minor (" .. minor .. ")")
    table.insert(packet_lines, tx_power_hex .. " // Tx Power (" .. tx_power .. " dBm)")
    
    -- 显示数据包
    for i, line in ipairs(packet_lines) do
        airui.label({
            parent = packet_card,
            x = 16, y = 40 + (i-1)*28, w = 408, h = 22,
            text = line,
            font_size = 14,
            color = 0xAED581
        })
    end

    -- 保存数据包容器引用，方便更新
    ui_controls.packet_section = packet_section
    ui_controls.packet_card = packet_card
end

-- 创建配置页面内容
-- 创建配置页面内容
function ibeacon_win.create_config_content()
    if config_win and config_win.create then
        config_win.create(ui_controls.content_area)
    else
        log.error("iBeacon", "config_win模块加载失败")
        airui.label({
            parent = ui_controls.content_area,
            x = 20, y = 100, w = 440, h = 40,
            text = "配置页面加载失败",
            font_size = 16,
            color = 0xE91E63,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

-- 创建关于页面内容
function ibeacon_win.create_about_content()
    local about_section = airui.container({
        parent = ui_controls.content_area,
        x = 0, y = 0, w = 480, h = 652,
        color = 0xFFFFFF
    })
    
    airui.label({
        parent = about_section,
        x = 20, y = 20, w = 440, h = 20,
        text = "关于 BLE iBeacon",
        font_size = 16,
        color = 0x333333
    })
    
    local about_card = airui.container({
        parent = about_section,
        x = 20, y = 50, w = 440, h = 120,
        color = 0xFFFFFF,
        radius = 12
    })
    
    local about_items = {
        {label = "版本", value = "v1.0.0"},
        {label = "协议", value = "Bluetooth 5.4"}
    }
    
    for i, item in ipairs(about_items) do
        local y_pos = 20 + (i-1)*50
        
        if i > 1 then
            airui.container({
                parent = about_card,
                x = 0, y = y_pos - 10, w = 440, h = 1,
                color = 0xF0F0F0
            })
        end
        
        airui.label({
            parent = about_card,
            x = 20, y = y_pos, w = 100, h = 30,
            text = item.label,
            font_size = 15,
            color = 0x666666
        })
        
        airui.label({
            parent = about_card,
            x = 140, y = y_pos, w = 280, h = 30,
            text = item.value,
            font_size = 15,
            color = 0x333333
        })
    end
    
    airui.label({
        parent = about_section,
        x = 20, y = 190, w = 440, h = 20,
        text = "功能说明",
        font_size = 16,
        color = 0x333333
    })
    
    local function_card = airui.container({
        parent = about_section,
        x = 20, y = 220, w = 440, h = 120,
        color = 0xFFFFFF,
        radius = 12
    })
    
    local function_items = {
        {label = "广播功能", value = "支持iBeacon协议广播"},
        {label = "配置管理", value = "支持UUID/Major/Minor配置"}
    }
    
    for i, item in ipairs(function_items) do
        local y_pos = 20 + (i-1)*50
        
        if i > 1 then
            airui.container({
                parent = function_card,
                x = 0, y = y_pos - 10, w = 440, h = 1,
                color = 0xF0F0F0
            })
        end
        
        airui.label({
            parent = function_card,
            x = 20, y = y_pos, w = 100, h = 30,
            text = item.label,
            font_size = 14,
            color = 0x666666
        })
        
        airui.label({
            parent = function_card,
            x = 140, y = y_pos, w = 280, h = 30,
            text = item.value,
            font_size = 13,
            color = 0x333333
        })
    end
    
    airui.label({
        parent = about_section,
        x = 20, y = 360, w = 440, h = 20,
        text = "技术支持",
        font_size = 16,
        color = 0x333333
    })
    
    local support_card = airui.container({
        parent = about_section,
        x = 20, y = 390, w = 440, h = 60,
        color = 0xFFFFFF,
        radius = 12
    })
    
    airui.label({
        parent = support_card,
        x = 20, y = 15, w = 100, h = 30,
        text = "官方网站",
        font_size = 14,
        color = 0x666666
    })
    
    airui.label({
        parent = support_card,
        x = 140, y = 15, w = 280, h = 30,
        text = "docs.openluat.com",
        font_size = 13,
        color = 0x333333
    })
end

-- 更新广播UI状态
function ibeacon_win.update_broadcast_status(is_broadcasting)
    log.info("iBeacon", "===== 更新广播UI状态 =====")
    log.info("iBeacon", "is_broadcasting=", is_broadcasting)
    log.info("iBeacon", "检查 ui_controls.broadcast_btn: ", ui_controls.broadcast_btn ~= nil)
    log.info("iBeacon", "检查 ui_controls.broadcast_status: ", ui_controls.broadcast_status ~= nil)
    
    -- 更新按钮文字和颜色
    if ui_controls.broadcast_btn then
        local btn_text = is_broadcasting and "停止广播" or "开始广播"
        local btn_color = is_broadcasting and 0x757575 or 0xE91E63
        ui_controls.broadcast_btn:set_text(btn_text)
        ui_controls.broadcast_btn:set_style({
            bg_color = btn_color,
            text_color = 0xFFFFFF,
            radius = 24
        })
    else
        log.error("iBeacon", "ui_controls.broadcast_btn 不存在!")
    end
    
    -- 更新状态标签
    if ui_controls.broadcast_status then
        local status_text = is_broadcasting and "广播中" or "已停止"
        ui_controls.broadcast_status:set_text(status_text)
        -- label 控件不支持 set_style，只能通过重新创建来改变颜色
    else
        log.error("iBeacon", "ui_controls.broadcast_status 不存在!")
    end
end

-- 切换广播状态
function ibeacon_win.toggle_broadcast()
    log.info("iBeacon", "===== 切换广播状态 =====")
    log.info("iBeacon", "点击切换按钮，当前状态: ", get_broadcast_state())
    log.info("iBeacon", "检查ble_manager: ", ble_manager ~= nil)
    
    local is_broadcasting = get_broadcast_state()
    
    if is_broadcasting then
        log.info("iBeacon", "准备停止广播")
        -- 停止广播
        if ble_manager and ble_manager.stop_broadcast then
            local result = ble_manager.stop_broadcast()
            log.info("iBeacon", "停止广播结果: ", result)
        else
            log.error("iBeacon", "ble_manager 或 stop_broadcast 不存在")
        end
    else
        -- 开始广播
        if ble_manager and ble_manager.start_broadcast then
            local result = ble_manager.start_broadcast()
            log.info("iBeacon", "开始广播结果: ", result)
        else
            log.error("iBeacon", "ble_manager 或 start_broadcast 不存在")
        end
    end
end

-- 返回上一页或首页
function ibeacon_win.go_back()
    log.info("iBeacon", "返回上一页，当前页面: ", ibeacon_win.current_page)
    
    -- 如果当前不在广播页，先返回广播页
    if ibeacon_win.current_page ~= "broadcast" then
        ibeacon_win.switch_page("broadcast")
        return
    end
    
    -- 在广播页时，关闭窗口返回首页
    log.info("iBeacon", "关闭窗口返回首页")
    -- 停止广播
    if ble_manager and ble_manager.stop_broadcast then
        ble_manager.stop_broadcast()
    end
    -- 关闭窗口
    if win_id then
        exwin.close(win_id)
    end
end

-- 销毁界面
function ibeacon_win.on_destroy()
    log.info("iBeacon", "销毁iBeacon界面")
    
    if ui_controls.main_container then
        ui_controls.main_container:destroy()
        ui_controls.main_container = nil
    end
    
    if ble_manager and ble_manager.stop_broadcast then
        ble_manager.stop_broadcast()
    end
    
    win_id = nil
end

-- 失去焦点
function ibeacon_win.on_lose_focus()
    log.info("iBeacon", "失去焦点")
end

-- 获得焦点
function ibeacon_win.on_get_focus()
    log.info("iBeacon", "获得焦点")
end

-- 打开窗口处理函数
local function open_handler()
    win_id = exwin.open({
        on_create = ibeacon_win.on_create,
        on_destroy = ibeacon_win.on_destroy,
        on_lose_focus = ibeacon_win.on_lose_focus,
        on_get_focus = ibeacon_win.on_get_focus,
    })
end

-- 订阅打开窗口事件
sys.subscribe("OPEN_IBEACON_WIN", open_handler)

-- 设为全局变量，供 ble_manager 回调使用
_G.ibeacon_win = ibeacon_win

return ibeacon_win
