--[[
@module  cc_settings
@summary 智慧冷链监控参数设置页面
@version 1.0.0
@date    2026.05.14
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

-- 获取配置（get）
local function get_settings()
    local file_path = "/data/settings.json"
    
    log.info("cc_settings", "获取设置", file_path)
    
    -- 确保/data目录存在
    if not io.exists("/data") then
        log.info("cc_settings", "/data目录不存在，创建目录")
        io.mkdir("/data")
    end
    
    if io.exists(file_path) then
        log.info("cc_settings", "配置文件存在")
        local content = io.readFile(file_path)
        if content and content ~= "" then
            local loaded_settings = json.decode(content)
            if loaded_settings and type(loaded_settings) == "table" then
                log.info("cc_settings", "配置文件加载成功")
                log.info("cc_settings", "配置内容:", json.encode(loaded_settings))
                log.info("cc_settings", "设备检查间隔值:", loaded_settings.device.check_interval)
                return loaded_settings
            else
                log.error("cc_settings", "JSON解析失败")
            end
        else
            log.error("cc_settings", "配置文件为空")
        end
    else
        log.info("cc_settings", "配置文件不存在，使用默认配置")
    end
    
    log.info("cc_settings", "使用默认配置")
    return {
        temp = {
            upper = 6,
            lower = -2,
            sample_interval = 30,
            alarm_delay = 5,
            humidity_upper = 75,
            humidity_lower = 30
        },
        device = {
            compressor_start = 4,
            compressor_stop = 2,
            defrost_interval = 6,
            defrost_duration = 20,
            fan_delay = 30,
            check_interval = 5
        },
        system = {
            upload_interval = 60,
            auto_defrost = true,
            data_upload = true,
            remote_control = true,
            alarm_sound = true,
            screen_always_on = false
        }
    }
end

-- 保存配置（set）
local function save_settings(data)
    local file_path = "/data/settings.json"
    
    log.info("cc_settings", "保存设置", file_path)
    
    -- 确保/data目录存在
    if not io.exists("/data") then
        log.info("cc_settings", "/data目录不存在，创建目录")
        io.mkdir("/data")
    end
    
    -- 序列化并保存
    local success = io.writeFile(file_path, json.encode(data))
    
    if success then
        log.info("cc_settings", "设置保存成功")
        log.info("cc_settings", "保存的内容:", json.encode(data))
        return true
    else
        log.error("cc_settings", "无法保存设置文件")
        return false
    end
end

-- 定义参数数据结构
local settings = get_settings()

local function create_ui()
    local density = _G.density_scale or 1
    
    log.info("cc_settings", "=== create_ui 开始 ===")
    
    -- 每次创建UI时都重新加载保存的设置，确保显示最新值
    log.info("cc_settings", "重新加载设置")
    settings = get_settings()
    log.info("cc_settings", "当前设置变量内容:", json.encode(settings))
    
    -- 主容器
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x0a1931,
        parent = airui.screen
    })

    -- 数字键盘组件
    local keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density),
        mode = "numeric",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 顶部导航栏
    local header_h = math.floor(50 * density)
    airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x141e30,
        radius = math.floor(8 * density),
    })

    -- 返回按钮
    airui.button({
        parent = main_container,
        x = math.floor(10 * density),
        y = math.floor((header_h - 32 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(32 * density),
        text = "返回",
        style = {
            bg_color = 0x1e2630,
            pressed_bg_color = 0x0d47a1,
            text_color = 0x4fc3f7,
            radius = math.floor(6 * density),
            font_size = math.floor(13 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            log.info("cc_settings", "返回按钮点击")
            exwin.close(win_id)
        end
    })

    -- 标题
    airui.label({
        parent = main_container,
        text = "参数设置",
        x = 0,
        y = math.floor((header_h - 18 * density) / 2),
        w = screen_w,
        h = math.floor(18 * density),
        font_size = math.floor(18 * density),
        color = 0xffffff,
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        text = "系统参数配置与管理",
        x = 0,
        y = math.floor((header_h - 18 * density) / 2) + math.floor(20 * density),
        w = screen_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 时间显示（精确到分钟）
    local time_label = airui.label({
        parent = main_container,
        text = os.date("%H:%M"),
        x = screen_w - math.floor(60 * density),
        y = math.floor((header_h - 16 * density) / 2),
        w = math.floor(50 * density),
        h = math.floor(16 * density),
        font_size = math.floor(16 * density),
        color = 0xffffff,
        font_weight = 500,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 主内容区域 - 增加高度以确保所有参数完全显示
    local content_y = header_h + math.floor(10 * density)
    local content_h = screen_h - header_h - math.floor(50 * density)
    local content_w = screen_w - math.floor(20 * density)

    -- 设置面板
    airui.container({
        parent = main_container,
        x = math.floor(10 * density), y = content_y,
        w = content_w, h = content_h,
        color = 0x141e30,
        radius = math.floor(8 * density),
    })

    -- 列宽度 - 调整为更宽的列以确保内容完全显示
    local col_w = math.floor((content_w - math.floor(20 * density)) / 3)
    local col1_x = math.floor(10 * density)
    local col2_x = col1_x + col_w + math.floor(10 * density)
    local col3_x = col2_x + col_w + math.floor(10 * density)

    -- 温度参数分组
    airui.label({
        parent = main_container,
        text = "温度参数",
        x = col1_x,
        y = content_y + math.floor(10 * density),
        w = col_w,
        h = math.floor(20 * density),
        font_size = math.floor(16 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    local temp_y = content_y + math.floor(50 * density)

    -- 温度上限
    airui.label({
        parent = main_container,
        text = "温度上限 (℃)",
        x = col1_x,
        y = temp_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    log.info("cc_settings", "创建温度上限输入框，值:", settings.temp.upper)
    local temp_upper_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.temp.upper),
        x = col1_x + math.floor(165 * density),
        y = temp_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 温度下限
    temp_y = temp_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "温度下限 (℃)",
        x = col1_x,
        y = temp_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local temp_lower_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.temp.lower),
        x = col1_x + math.floor(165 * density),
        y = temp_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 温度采样间隔
    temp_y = temp_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "温度采样间隔 (秒)",
        x = col1_x,
        y = temp_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local temp_sample_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.temp.sample_interval),
        x = col1_x + math.floor(165 * density),
        y = temp_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 温度告警延迟
    temp_y = temp_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "温度告警延迟 (分钟)",
        x = col1_x,
        y = temp_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local temp_alarm_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.temp.alarm_delay),
        x = col1_x + math.floor(165 * density),
        y = temp_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 湿度上限
    temp_y = temp_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "湿度上限 (%)",
        x = col1_x,
        y = temp_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local humidity_upper_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.temp.humidity_upper),
        x = col1_x + math.floor(165 * density),
        y = temp_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x66bb6a,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 湿度下限
    temp_y = temp_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "湿度下限 (%)",
        x = col1_x,
        y = temp_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local humidity_lower_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.temp.humidity_lower),
        x = col1_x + math.floor(165 * density),
        y = temp_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x66bb6a,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 设备参数分组
    airui.label({
        parent = main_container,
        text = "设备参数",
        x = col2_x,
        y = content_y + math.floor(10 * density),
        w = col_w,
        h = math.floor(20 * density),
        font_size = math.floor(16 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    local device_y = content_y + math.floor(50 * density)

    -- 压缩机启动温度
    airui.label({
        parent = main_container,
        text = "压缩机启动温度 (℃)",
        x = col2_x,
        y = device_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local compressor_start_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.device.compressor_start),
        x = col2_x + math.floor(165 * density),
        y = device_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 压缩机停止温度
    device_y = device_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "压缩机停止温度 (℃)",
        x = col2_x,
        y = device_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local compressor_stop_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.device.compressor_stop),
        x = col2_x + math.floor(165 * density),
        y = device_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 除霜间隔
    device_y = device_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "除霜间隔 (小时)",
        x = col2_x,
        y = device_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local defrost_interval_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.device.defrost_interval),
        x = col2_x + math.floor(165 * density),
        y = device_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 除霜时长
    device_y = device_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "除霜时长 (分钟)",
        x = col2_x,
        y = device_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local defrost_duration_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.device.defrost_duration),
        x = col2_x + math.floor(165 * density),
        y = device_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 风机启动延迟
    device_y = device_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "风机启动延迟 (秒)",
        x = col2_x,
        y = device_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local fan_delay_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.device.fan_delay),
        x = col2_x + math.floor(165 * density),
        y = device_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 设备检查间隔
    device_y = device_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "设备检查间隔 (分钟)",
        x = col2_x,
        y = device_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    log.info("cc_settings", "创建设备检查间隔输入框，值:", settings.device.check_interval)
    local check_interval_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.device.check_interval),
        x = col2_x + math.floor(165 * density),
        y = device_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 系统参数分组
    airui.label({
        parent = main_container,
        text = "系统参数",
        x = col3_x,
        y = content_y + math.floor(10 * density),
        w = col_w,
        h = math.floor(20 * density),
        font_size = math.floor(16 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    local system_y = content_y + math.floor(50 * density)

    -- 数据上传间隔
    airui.label({
        parent = main_container,
        text = "数据上传间隔 (秒)",
        x = col3_x,
        y = system_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local upload_interval_input = airui.textarea({
        parent = main_container,
        text = tostring(settings.system.upload_interval),
        x = col3_x + math.floor(165 * density),
        y = system_y,
        w = math.floor(80 * density),
        h = math.floor(30 * density),
        font_size = math.floor(18 * density),
        color = 0x4fc3f7,
        bg_color = 0x1e2630,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 10,

    })

    -- 自动除霜
    system_y = system_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "自动除霜",
        x = col3_x,
        y = system_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    log.info("cc_settings", "创建自动除霜开关，值:", settings.system.auto_defrost)
    local auto_defrost_check = airui.switch({
        parent = main_container,
        x = col3_x + math.floor(165 * density),
        y = system_y + math.floor(2 * density),
        w = math.floor(60 * density),
        h = math.floor(30 * density),
        checked = settings.system.auto_defrost,
        on_change = function(self)
            settings.system.auto_defrost = self:get_state()
            save_settings(settings)  -- 立即保存到文件系统
        end
    })

    -- 数据上传
    system_y = system_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "数据上传",
        x = col3_x,
        y = system_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local data_upload_check = airui.switch({
        parent = main_container,
        x = col3_x + math.floor(165 * density),
        y = system_y + math.floor(2 * density),
        w = math.floor(60 * density),
        h = math.floor(30 * density),
        checked = settings.system.data_upload,
        on_change = function(self)
            settings.system.data_upload = self:get_state()
            save_settings(settings)  -- 立即保存到文件系统
        end
    })

    -- 远程控制
    system_y = system_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "远程控制",
        x = col3_x,
        y = system_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local remote_control_check = airui.switch({
        parent = main_container,
        x = col3_x + math.floor(165 * density),
        y = system_y + math.floor(2 * density),
        w = math.floor(60 * density),
        h = math.floor(30 * density),
        checked = settings.system.remote_control,
        on_change = function(self)
            settings.system.remote_control = self:get_state()
            save_settings(settings)  -- 立即保存到文件系统
        end
    })

    -- 告警声音
    system_y = system_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "告警声音",
        x = col3_x,
        y = system_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local alarm_sound_check = airui.switch({
        parent = main_container,
        x = col3_x + math.floor(165 * density),
        y = system_y + math.floor(2 * density),
        w = math.floor(60 * density),
        h = math.floor(30 * density),
        checked = settings.system.alarm_sound,
        on_change = function(self)
            settings.system.alarm_sound = self:get_state()
            save_settings(settings)  -- 立即保存到文件系统
        end
    })

    -- 屏幕常亮
    system_y = system_y + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "屏幕常亮",
        x = col3_x,
        y = system_y,
        w = math.floor(160 * density),
        h = math.floor(30 * density),
        font_size = math.floor(15 * density),
        color = 0xcccccc,
    })
    local screen_always_on_check = airui.switch({
        parent = main_container,
        x = col3_x + math.floor(165 * density),
        y = system_y + math.floor(2 * density),
        w = math.floor(60 * density),
        h = math.floor(30 * density),
        checked = settings.system.screen_always_on,
        on_change = function(self)
            settings.system.screen_always_on = self:get_state()
            save_settings(settings)  -- 立即保存到文件系统
        end
    })

    -- 底部按钮区域
    local footer_y = screen_h - math.floor(60 * density)
    airui.container({
        parent = main_container,
        x = math.floor(10 * density), y = footer_y,
        w = screen_w - math.floor(20 * density), h = math.floor(50 * density),
        color = 0x141e30,
        radius = math.floor(8 * density),
    })

    -- 保存按钮（左边）
    airui.button({
        parent = main_container,
        x = math.floor(15 * density),
        y = footer_y + math.floor((50 * density - 32 * density) / 2),
        w = math.floor(100 * density),
        h = math.floor(32 * density),
        text = "保存设置",
        style = {
            bg_color = 0x1e2630,
            pressed_bg_color = 0x1b5e20,
            text_color = 0x66bb6a,
            radius = math.floor(6 * density),
            font_size = math.floor(13 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            log.info("cc_settings", "保存设置")
            
            log.info("cc_settings", "=== 保存设置开始 ===")
            
            -- 直接从输入框获取所有值并更新 settings 变量
            -- 温度参数
            local temp_upper = tonumber(temp_upper_input:get_text())
            local temp_lower = tonumber(temp_lower_input:get_text())
            local temp_sample_interval = tonumber(temp_sample_input:get_text())
            local temp_alarm_delay = tonumber(temp_alarm_input:get_text())
            local humidity_upper = tonumber(humidity_upper_input:get_text())
            local humidity_lower = tonumber(humidity_lower_input:get_text())
            
            -- 设备参数
            local compressor_start = tonumber(compressor_start_input:get_text())
            local compressor_stop = tonumber(compressor_stop_input:get_text())
            local defrost_interval = tonumber(defrost_interval_input:get_text())
            local defrost_duration = tonumber(defrost_duration_input:get_text())
            local fan_delay = tonumber(fan_delay_input:get_text())
            local check_interval = tonumber(check_interval_input:get_text())
            
            -- 系统参数
            local upload_interval = tonumber(upload_interval_input:get_text())
            
            -- 更新 settings 变量
            if temp_upper then settings.temp.upper = temp_upper end
            if temp_lower then settings.temp.lower = temp_lower end
            if temp_sample_interval then settings.temp.sample_interval = temp_sample_interval end
            if temp_alarm_delay then settings.temp.alarm_delay = temp_alarm_delay end
            if humidity_upper then settings.temp.humidity_upper = humidity_upper end
            if humidity_lower then settings.temp.humidity_lower = humidity_lower end
            
            if compressor_start then settings.device.compressor_start = compressor_start end
            if compressor_stop then settings.device.compressor_stop = compressor_stop end
            if defrost_interval then settings.device.defrost_interval = defrost_interval end
            if defrost_duration then settings.device.defrost_duration = defrost_duration end
            if fan_delay then settings.device.fan_delay = fan_delay end
            if check_interval then settings.device.check_interval = check_interval end
            
            if upload_interval then settings.system.upload_interval = upload_interval end
            
            -- 保存到文件
            local success = save_settings(settings)
            
            log.info("cc_settings", "准备保存到 /data/settings.json")
            log.info("cc_settings", "要保存的完整数据:", json.encode(settings))
            
            if success then
                log.info("cc_settings", "设置已保存")
                
                -- 显示保存成功提示
                local msg = airui.msgbox({
                    text = "保存成功",
                    buttons = { "确定" },
                    on_action = function(self) self:hide() end
                })
                msg:show()
            else
                log.error("cc_settings", "无法保存设置文件")
                -- 显示保存失败提示
                local msg = airui.msgbox({
                    text = "保存失败，请检查权限",
                    buttons = { "确定" },
                    on_action = function(self) self:hide() end
                })
                msg:show()
            end
        end
    })

    -- 恢复默认按钮（右边）
    airui.button({
        parent = main_container,
        x = screen_w - math.floor(120 * density),
        y = footer_y + math.floor((50 * density - 32 * density) / 2),
        w = math.floor(100 * density),
        h = math.floor(32 * density),
        text = "恢复默认",
        style = {
            bg_color = 0x1e2630,
            pressed_bg_color = 0xb71c1c,
            text_color = 0xe57373,
            radius = math.floor(6 * density),
            font_size = math.floor(13 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            log.info("cc_settings", "恢复默认")
            -- 恢复默认参数
            local default_settings = {
                temp = {
                    upper = 6,
                    lower = -2,
                    sample_interval = 30,
                    alarm_delay = 5,
                    humidity_upper = 75,
                    humidity_lower = 30
                },
                device = {
                    compressor_start = 4,
                    compressor_stop = 2,
                    defrost_interval = 6,
                    defrost_duration = 20,
                    fan_delay = 30,
                    check_interval = 5
                },
                system = {
                    upload_interval = 60,
                    auto_defrost = true,
                    data_upload = true,
                    remote_control = true,
                    alarm_sound = true,
                    screen_always_on = false
                }
            }
            
            -- 直接更新参数和界面控件
            settings = default_settings
            
            -- 更新所有输入框和开关控件的值
            temp_upper_input:set_text(tostring(settings.temp.upper))
            temp_lower_input:set_text(tostring(settings.temp.lower))
            temp_sample_input:set_text(tostring(settings.temp.sample_interval))
            temp_alarm_input:set_text(tostring(settings.temp.alarm_delay))
            humidity_upper_input:set_text(tostring(settings.temp.humidity_upper))
            humidity_lower_input:set_text(tostring(settings.temp.humidity_lower))
            
            compressor_start_input:set_text(tostring(settings.device.compressor_start))
            compressor_stop_input:set_text(tostring(settings.device.compressor_stop))
            defrost_interval_input:set_text(tostring(settings.device.defrost_interval))
            defrost_duration_input:set_text(tostring(settings.device.defrost_duration))
            fan_delay_input:set_text(tostring(settings.device.fan_delay))
            check_interval_input:set_text(tostring(settings.device.check_interval))
            
            upload_interval_input:set_text(tostring(settings.system.upload_interval))
            auto_defrost_check:set_state(settings.system.auto_defrost)
            data_upload_check:set_state(settings.system.data_upload)
            remote_control_check:set_state(settings.system.remote_control)
            alarm_sound_check:set_state(settings.system.alarm_sound)
            screen_always_on_check:set_state(settings.system.screen_always_on)
            
            -- 显示恢复成功提示
            local msg = airui.msgbox({
                text = "已恢复默认设置",
                buttons = { "确定" },
                on_action = function(self) self:hide() end
            })
            msg:show()
        end
    })
end

local function on_create()
    update_screen_size()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 不重置 win_id，保留窗口 ID 信息以便后续判断
end

local function open()
    -- 简化逻辑，直接打开新窗口，不做 is_active 检查
    log.info("cc_settings", "尝试打开设置窗口，当前 win_id:", win_id)
    
    -- 如果之前有窗口，先关闭它（避免重叠）
    if win_id then
        exwin.close(win_id)
    end
    
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
    log.info("cc_settings", "设置窗口打开成功", win_id)
end

sys.subscribe("OPEN_CC_SETTINGS_WIN", open)
