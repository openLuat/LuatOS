local win_id = nil
local main_container
local psm_master_switch

-- 默认配置常量
local DEFAULT_CONFIG = {
    timer = {
        minutes = 5
    },
    uart = {
        port = 1,
        baud = 9600,
        baud_mode = "any"
    },
    pwrkey = {
        pull = "PULLUP",
        edge = "BOTH"
    },
    chgdet = {
        pull = "PULLUP",
        edge = "RISING"
    },
    wakeup = {
        index = 0,
        pull = "PULLUP",
        edge = "BOTH",
        pull_options = {"PULLUP", "PULLDOWN"}
    }
}

-- 默认唤醒源状态
local DEFAULT_WAKEUP_SOURCES = {
    timer = {
        enable = true,
        desc = "5分钟"
    },
    uart = {
        enable = false,
        desc = "UART1 • 9600 (任意波特率可唤醒)"
    },
    pwrkey = {
        enable = false,
        desc = "PULLUP • BOTH"
    },
    chgdet = {
        enable = false,
        desc = "PULLUP • RISING"
    },
    wakeup = {
        enable = false,
        desc = "WAKEUP0 • PULLUP • BOTH"
    }
}

-- 唤醒源开关状态
local wakeup_sources = {}

-- 详细配置参数
local config = {}

-- 获取当前模组型号
local module = hmeta.model()
log.info("psm", "当前模组型号:", module)

-- 重置所有配置为默认值
local function reset_to_default()
    config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        if type(v) == "table" then
            config[k] = {}
            for k2, v2 in pairs(v) do
                config[k][k2] = v2
            end
        else
            config[k] = v
        end
    end
    
    wakeup_sources = {}
    for k, v in pairs(DEFAULT_WAKEUP_SOURCES) do
        if type(v) == "table" then
            wakeup_sources[k] = {}
            for k2, v2 in pairs(v) do
                wakeup_sources[k][k2] = v2
            end
        else
            wakeup_sources[k] = v
        end
    end
    
    log.info("psm", "配置已重置为默认值")
end

reset_to_default()

-- 控件引用
local ui_refs = {
    timer_main_switch = nil,
    uart_main_switch = nil,
    pwrkey_main_switch = nil,
    chgdet_main_switch = nil,
    wakeup_main_switch = nil,
    timer_desc = nil,
    uart_desc = nil,
    pwrkey_desc = nil,
    chgdet_desc = nil,
    wakeup_desc = nil,
    warning_text = nil,
    timer_minutes_input = nil,
    uart_baud_input = nil,
    pwrkey_pull_select = nil,
    pwrkey_edge_select = nil,
    chgdet_pull_select = nil,
    chgdet_edge_select = nil,
    wakeup_pull_select = nil,
    wakeup_select = nil,
    wakeup_edge_select = nil,
    numeric_keyboard = nil,
}

-- 创建数字键盘（用于定时器和波特率输入）
local function create_numeric_keyboard()
    if ui_refs.numeric_keyboard then
        return ui_refs.numeric_keyboard
    end
    
    local screen_height = 320
    local keyboard_height = 120
    
    local kb = airui.keyboard({
        x = 0,
        y = 0,
        w = 480,
        h = keyboard_height,
        mode = "numeric",
        popovers = true,
        auto_hide = true,
        bg_color = 0x333333,
        on_commit = function()
            log.info("psm", "数字键盘提交")
        end
    })
    
    ui_refs.numeric_keyboard = kb
    log.info("psm", "数字键盘创建成功")
    return kb
end

-- 更新主界面描述
local function update_main_descriptions()
    if not exwin.is_active(win_id) then
        return
    end

    if ui_refs.timer_desc then
        ui_refs.timer_desc:set_text(config.timer.minutes .. "分钟")
    end

    if ui_refs.uart_desc then
        ui_refs.uart_desc:set_text("UART1 • " .. config.uart.baud .. " (任意波特率可唤醒)")
    end

    if ui_refs.pwrkey_desc then
        ui_refs.pwrkey_desc:set_text(config.pwrkey.pull .. " • " .. config.pwrkey.edge)
    end

    if ui_refs.chgdet_desc then
        ui_refs.chgdet_desc:set_text(config.chgdet.pull .. " • " .. config.chgdet.edge)
    end

    if ui_refs.wakeup_desc then
        local pull_txt = config.wakeup.pull
        if config.wakeup.index == 2 then
            pull_txt = "nil"
        end
        ui_refs.wakeup_desc:set_text("WAKEUP" .. config.wakeup.index .. " • " .. pull_txt .. " • " .. config.wakeup.edge)
    end
end

-- 更新所有开关的状态
local function update_all_switches()
    if not exwin.is_active(win_id) then
        return
    end
    
    if ui_refs.timer_main_switch then
        ui_refs.timer_main_switch:set_state(wakeup_sources.timer.enable)
    end
    if ui_refs.uart_main_switch then
        ui_refs.uart_main_switch:set_state(wakeup_sources.uart.enable)
    end
    if ui_refs.pwrkey_main_switch then
        ui_refs.pwrkey_main_switch:set_state(wakeup_sources.pwrkey.enable)
    end
    if ui_refs.chgdet_main_switch then
        ui_refs.chgdet_main_switch:set_state(wakeup_sources.chgdet.enable)
    end
    if ui_refs.wakeup_main_switch then
        ui_refs.wakeup_main_switch:set_state(wakeup_sources.wakeup.enable)
    end
end

-- 检查是否有至少一种唤醒方式开启
local function has_any_wakeup()
    if not wakeup_sources then
        return false
    end
    
    return (wakeup_sources.timer and wakeup_sources.timer.enable) or
           (wakeup_sources.uart and wakeup_sources.uart.enable) or
           (wakeup_sources.pwrkey and wakeup_sources.pwrkey.enable) or
           (wakeup_sources.chgdet and wakeup_sources.chgdet.enable) or
           (wakeup_sources.wakeup and wakeup_sources.wakeup.enable)
end

-- 更新警告显示
local function update_warning()
    if not exwin.is_active(win_id) then
        return
    end
    
    if not ui_refs or not ui_refs.warning_text then
        return
    end

    local psm_enabled = psm_master_switch and psm_master_switch:get_state() or false

    if ui_refs.warning_text and type(ui_refs.warning_text.set_hidden) == "function" then
        if psm_enabled and not has_any_wakeup() then
            ui_refs.warning_text:set_hidden(false)
        else
            ui_refs.warning_text:set_hidden(true)
        end
    end
end

-- 将GPIO边沿类型转换为gpio常量
local function edge_to_gpio_const(edge)
    if edge == "FALLING" then
        return gpio.FALLING
    elseif edge == "RISING" then
        return gpio.RISING
    else
        return gpio.BOTH
    end
end

-- 将上下拉类型转换为gpio常量
local function pull_to_gpio_const(pull)
    if pull == "PULLUP" then
        return gpio.PULLUP
    else
        return gpio.PULLDOWN
    end
end

-- 实际配置PSM+模式
local function apply_psm_config()
    log.info("psm", "开始配置PSM+模式...")
    
    -- 定义唤醒中断处理函数
    local function psm_wakeup_func(level, id)
        log.info("psm_wakeup", "触发唤醒", "电平:", level, "ID:", id)
    end
    
    -- 配置深度休眠定时器唤醒
    if wakeup_sources.timer.enable then
        local timer_ms = config.timer.minutes * 60 * 1000
        pm.dtimerStart(0, timer_ms)
        log.info("psm", "定时器唤醒已配置:", config.timer.minutes, "分钟")
    end
    
    -- 配置UART1唤醒
    if wakeup_sources.uart.enable then
        uart.setup(config.uart.port, config.uart.baud, 8, 1)
        log.info("psm", "UART唤醒已配置: 端口", config.uart.port, "波特率", config.uart.baud)
    end
    
    -- 配置PWR_KEY唤醒
    if wakeup_sources.pwrkey.enable then
        -- PWR_KEY只能配置为PULLUP
        local edge_const = edge_to_gpio_const(config.pwrkey.edge)
        -- 防抖配置（PSM+模式下防抖无效，但保持配置一致性）
        gpio.debounce(gpio.PWR_KEY, 200)
        gpio.setup(gpio.PWR_KEY, psm_wakeup_func, gpio.PULLUP, edge_const)
        log.info("psm", "PWR_KEY唤醒已配置:", config.pwrkey.pull, config.pwrkey.edge)
    end
    
    -- 配置CHG_DET唤醒
    if wakeup_sources.chgdet.enable then
        local edge_const = edge_to_gpio_const(config.chgdet.edge)
        gpio.debounce(gpio.CHG_DET, 1000)
        gpio.setup(gpio.CHG_DET, psm_wakeup_func, gpio.PULLUP, edge_const)
        log.info("psm", "CHG_DET唤醒已配置:", config.chgdet.pull, config.chgdet.edge)
    end
    
    -- 配置WAKEUP引脚唤醒
    if wakeup_sources.wakeup.enable then
        local wakeup_pin = nil
        if config.wakeup.index == 0 then
            wakeup_pin = gpio.WAKEUP0
        elseif config.wakeup.index == 1 then
            wakeup_pin = gpio.WAKEUP1
        elseif config.wakeup.index == 2 then
            wakeup_pin = gpio.WAKEUP2
        elseif config.wakeup.index == 3 then
            wakeup_pin = gpio.WAKEUP3
        elseif config.wakeup.index == 4 then
            wakeup_pin = gpio.WAKEUP4
        end
        
        if wakeup_pin then
            local pull_const = pull_to_gpio_const(config.wakeup.pull)
            local edge_const = edge_to_gpio_const(config.wakeup.edge)
            
            -- 对于WAKEUP2，如果是包含GSensor的模组且有特殊处理
            if config.wakeup.index == 2 then
                local module = hmeta.model()
                if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or 
                   module == "Air8000AB" or module == "Air8000D" or module == "Air8000DB" then
                    -- 这些模组的WAKEUP2用于GSensor中断，需要特殊处理
                    -- 这里需要确保GSensor已初始化
                    log.info("psm", "WAKEUP2用于GSensor中断，需要确保GSensor已配置")
                end
            end
            
            gpio.debounce(wakeup_pin, 1000)
            gpio.setup(wakeup_pin, psm_wakeup_func, pull_const, edge_const)
            log.info("psm", "WAKEUP唤醒已配置: WAKEUP" .. config.wakeup.index, config.wakeup.pull, config.wakeup.edge)
        end
    end
    
    log.info("psm", "PSM+配置完成")
end

-- 配置PSM+模式下的功能项（降低功耗）
local function apply_psm_func_config()
    log.info("psm", "开始配置PSM+功能项...")
    
    -- 根据drv_psm.lua中的建议，配置以下功能项以降低功耗
    
    -- WiFi芯片配置（如果模组包含WiFi）
    if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or 
       module == "Air8000AB" or module == "Air8000W" then
        if pm.WIFI then
            pm.power(pm.WIFI, 0)
            log.info("psm", "WiFi芯片已关闭")
        else
            gpio.setup(23, nil, gpio.PULLDOWN)
            log.info("psm", "WiFi芯片已关闭(GPIO23)")
        end
    end
    
    -- GNSS备电和GSensor电源配置（如果模组包含GNSS/GSensor）
    if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or 
       module == "Air8000AB" or module == "Air8000D" or module == "Air8000DB" then
        gpio.setup(24, nil, gpio.PULLDOWN)
        log.info("psm", "GNSS备电和GSensor电源已关闭")
    end
    
    -- 未使用的WAKEUP引脚配置为输入下拉以降低功耗
    -- WAKEUP0: 如果未启用，配置为输入下拉
    if not wakeup_sources.wakeup.enable or config.wakeup.index ~= 0 then
        gpio.setup(gpio.WAKEUP0, nil, gpio.PULLDOWN)
    end
    
    -- WAKEUP1(VBUS): 如果未启用，配置为输入下拉
    if not wakeup_sources.wakeup.enable or config.wakeup.index ~= 1 then
        gpio.setup(gpio.WAKEUP1, nil, gpio.PULLDOWN)
    end
    
    -- WAKEUP3: 如果未启用，配置为输入下拉
    if not wakeup_sources.wakeup.enable or config.wakeup.index ~= 3 then
        gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)
    end
    
    -- WAKEUP4: 如果未启用，配置为输入下拉
    if not wakeup_sources.wakeup.enable or config.wakeup.index ~= 4 then
        gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)
    end
    
    -- WAKEUP5: 根据模组型号决定是否配置
    if module == "Air8000D" or module == "Air8000DB" or module == "Air8000T" then
        if not wakeup_sources.wakeup.enable or config.wakeup.index ~= 5 then
            gpio.setup(gpio.WAKEUP5, nil, gpio.PULLDOWN)
        end
    end
    
    log.info("psm", "PSM+功能项配置完成")
end

-- PSM+任务函数
local function psm_task()
    log.info("psm_task", "进入PSM+任务")
    
    -- 应用唤醒配置
    apply_psm_config()
    
    -- 应用功耗优化配置
    apply_psm_func_config()
    
    -- 延时10秒用于调试（开发时可取消注释）
    -- sys.wait(10000)

    gpio.setup(1, 0)
    lcd.sleep()
    
    -- 配置最低功耗模式为PSM+模式
    log.info("psm_task", "准备进入PSM+模式...")
    pm.power(pm.WORK_MODE, 3)
    
    -- 等待80秒，如果未能进入PSM+则重启
    sys.wait(80000)
    log.info("psm_task", "进入PSM+失败，系统重启")
    rtos.reboot()
end

-- 启动PSM+模式
local function start_psm_mode()
    log.info("psm", "启动PSM+模式")
    sys.taskInit(psm_task)
end

-- 处理唤醒源开关变化
local function on_wakeup_source_change(source_type)
    return function(self)
        local enabled = self:get_state()
        wakeup_sources[source_type].enable = enabled
        
        if psm_master_switch then
            local psm_enabled = psm_master_switch:get_state()
            if psm_enabled and not has_any_wakeup() then
                psm_master_switch:set_state(false)
                if exwin.is_active(win_id) then
                    airui.msgbox({
                        title = "提示",
                        text = "至少需要一种唤醒方式，PSM+已自动关闭",
                        buttons = {"确定"},
                        button_align = "left",
                        timeout = 2000
                    })
                end
            end
        end

        update_warning()
        log.info("psm", source_type .. "唤醒", enabled and "开启" or "关闭")
    end
end

-- 创建主界面UI
local function create_main_ui(parent)
    local master_card = airui.container({
        parent = parent,
        x = 20,
        y = 70,
        w = 440,
        h = 380,
        color = 0xaed6ef,
        radius = 40
    })

    local y_pos = 20
    local strip_height = 50
    local strip_spacing = 10

    -- 定时器唤醒条
    local timer_strip = airui.container({
        parent = master_card,
        x = 18,
        y = y_pos,
        w = 404,
        h = strip_height,
        color = 0xFFFFFF,
        radius = 28
    })

    airui.label({
        parent = timer_strip,
        x = 15,
        y = 5,
        w = 120,
        h = 20,
        text = "定时器唤醒",
        font_size = 16,
        color = 0x1D4F7C
    })

    ui_refs.timer_desc = airui.label({
        parent = timer_strip,
        x = 15,
        y = 28,
        w = 120,
        h = 18,
        text = wakeup_sources.timer.desc,
        font_size = 13,
        color = 0x6184AA
    })

    local timer_switch = airui.switch({
        parent = timer_strip,
        x = 340,
        y = 10,
        w = 58,
        h = 30,
        checked = wakeup_sources.timer.enable,
        on_change = on_wakeup_source_change("timer")
    })
    ui_refs.timer_main_switch = timer_switch
    y_pos = y_pos + strip_height + strip_spacing

    -- UART唤醒条
    local uart_strip = airui.container({
        parent = master_card,
        x = 18,
        y = y_pos,
        w = 404,
        h = strip_height,
        color = 0xFFFFFF,
        radius = 28
    })

    airui.label({
        parent = uart_strip,
        x = 15,
        y = 5,
        w = 120,
        h = 20,
        text = "UART唤醒",
        font_size = 16,
        color = 0x1D4F7C
    })

    ui_refs.uart_desc = airui.label({
        parent = uart_strip,
        x = 15,
        y = 28,
        w = 250,
        h = 18,
        text = wakeup_sources.uart.desc,
        font_size = 13,
        color = 0x6184AA
    })

    local uart_switch = airui.switch({
        parent = uart_strip,
        x = 340,
        y = 10,
        w = 58,
        h = 30,
        checked = wakeup_sources.uart.enable,
        on_change = on_wakeup_source_change("uart")
    })
    ui_refs.uart_main_switch = uart_switch
    y_pos = y_pos + strip_height + strip_spacing

    -- PWR_KEY唤醒条
    local pwrkey_strip = airui.container({
        parent = master_card,
        x = 18,
        y = y_pos,
        w = 404,
        h = strip_height,
        color = 0xFFFFFF,
        radius = 28
    })

    airui.label({
        parent = pwrkey_strip,
        x = 15,
        y = 5,
        w = 140,
        h = 20,
        text = "PWR_KEY唤醒",
        font_size = 16,
        color = 0x1D4F7C
    })

    ui_refs.pwrkey_desc = airui.label({
        parent = pwrkey_strip,
        x = 15,
        y = 28,
        w = 180,
        h = 18,
        text = wakeup_sources.pwrkey.desc,
        font_size = 13,
        color = 0x6184AA
    })

    local pwrkey_switch = airui.switch({
        parent = pwrkey_strip,
        x = 340,
        y = 10,
        w = 58,
        h = 30,
        checked = wakeup_sources.pwrkey.enable,
        on_change = on_wakeup_source_change("pwrkey")
    })
    ui_refs.pwrkey_main_switch = pwrkey_switch
    y_pos = y_pos + strip_height + strip_spacing

    -- CHG_DET唤醒条
    local chgdet_strip = airui.container({
        parent = master_card,
        x = 18,
        y = y_pos,
        w = 404,
        h = strip_height,
        color = 0xFFFFFF,
        radius = 28
    })

    airui.label({
        parent = chgdet_strip,
        x = 15,
        y = 5,
        w = 140,
        h = 20,
        text = "CHG_DET唤醒",
        font_size = 16,
        color = 0x1D4F7C
    })

    ui_refs.chgdet_desc = airui.label({
        parent = chgdet_strip,
        x = 15,
        y = 28,
        w = 180,
        h = 18,
        text = wakeup_sources.chgdet.desc,
        font_size = 13,
        color = 0x6184AA
    })

    local chgdet_switch = airui.switch({
        parent = chgdet_strip,
        x = 340,
        y = 10,
        w = 58,
        h = 30,
        checked = wakeup_sources.chgdet.enable,
        on_change = on_wakeup_source_change("chgdet")
    })
    ui_refs.chgdet_main_switch = chgdet_switch
    y_pos = y_pos + strip_height + strip_spacing

    -- WAKEUP唤醒条
    local wakeup_strip = airui.container({
        parent = master_card,
        x = 18,
        y = y_pos,
        w = 404,
        h = strip_height,
        color = 0xFFFFFF,
        radius = 28
    })

    airui.label({
        parent = wakeup_strip,
        x = 15,
        y = 5,
        w = 140,
        h = 20,
        text = "WAKEUP唤醒",
        font_size = 16,
        color = 0x1D4F7C
    })

    ui_refs.wakeup_desc = airui.label({
        parent = wakeup_strip,
        x = 15,
        y = 28,
        w = 250,
        h = 18,
        text = wakeup_sources.wakeup.desc,
        font_size = 13,
        color = 0x6184AA
    })

    local wakeup_switch = airui.switch({
        parent = wakeup_strip,
        x = 340,
        y = 10,
        w = 58,
        h = 30,
        checked = wakeup_sources.wakeup.enable,
        on_change = on_wakeup_source_change("wakeup")
    })
    ui_refs.wakeup_main_switch = wakeup_switch
    y_pos = y_pos + strip_height + strip_spacing

    -- 进入详细配置入口
    local config_entry = airui.container({
        parent = master_card,
        x = 18,
        y = y_pos,
        w = 404,
        h = 50,
        color = 0xEAF1FB,
        radius = 60,
        on_click = function(self)
            log.info("psm", "点击配置入口")
            
            if psm_master_switch and psm_master_switch:get_state() then
                if exwin.is_active(win_id) then
                    airui.msgbox({
                        title = "提示",
                        text = "请先关闭PSM+模式再配置唤醒参数",
                        buttons = {"确定"},
                        timeout = 2000
                    })
                end
                return
            end

            sys.publish("OPEN_CONFIG_WIN")
        end
    })

    airui.label({
        parent = config_entry,
        x = 20,
        y = 16,
        w = 250,
        h = 26,
        text = "配置详细参数",
        font_size = 18,
        color = 0x1F4E7A
    })

    airui.label({
        parent = config_entry,
        x = 360,
        y = 15,
        w = 30,
        h = 26,
        text = ">>",
        font_size = 24,
        color = 0x1F6DA0
    })

    -- PSM+ 主开关区域
    local psm_footer = airui.container({
        parent = parent,
        x = 20,
        y = 460,
        w = 440,
        h = 83,
        color = 0xaed6ef,
        radius = 35
    })

    airui.label({
        parent = psm_footer,
        x = 30,
        y = 20,
        w = 180,
        h = 40,
        text = "PSM+ 模式",
        font_size = 28,
        color = 0x0D3A5C
    })

    ui_refs.warning_text = airui.label({
        parent = psm_footer,
        x = 30,
        y = 52,
        w = 300,
        h = 30,
        text = "请至少开启一种唤醒方式",
        font_size = 14,
        color = 0xB4520C,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    if ui_refs.warning_text and type(ui_refs.warning_text.set_hidden) == "function" then
        ui_refs.warning_text:set_hidden(true)
    end

    psm_master_switch = airui.switch({
        parent = psm_footer,
        x = 340,
        y = 15,
        w = 70,
        h = 40,
        checked = false,
        on_change = function(self)
            local state_psm = self:get_state()
            
            if state_psm then
                if not has_any_wakeup() then
                    self:set_state(false)
                    
                    if exwin.is_active(win_id) then
                        airui.msgbox({
                            title = "提示",
                            text = "请至少打开一种唤醒方式",
                            buttons = {"确定"},
                            button_align = "left",
                            timeout = 0,
                            on_action = function(box, label)
                                box:hide()
                            end
                        })
                    end
                    return
                end
                
                -- 显示确认对话框
                airui.msgbox({
                    title = "确认",
                    text = "开启PSM+模式后将进入深度休眠，屏幕熄灭。\n确认开启？",
                    buttons = {"确定", "取消"},
                    button_align = "left",
                    timeout = 0,
                    on_action = function(box, label)
                        if label == "确定" then
                            -- 启动PSM+模式
                            start_psm_mode()
                            box:hide()
                            log.info("psm", "PSM+模式已开启")
                        elseif label == "取消" then
                            self:set_state(false)
                            box:hide()
                            log.info("psm", "取消开启PSM+模式")
                        end
                    end
                })
            else
                log.info("psm", "PSM+模式关闭")
            end
            
            update_warning()
        end
    })

    airui.label({
        parent = parent,
        x = 160,
        y = 543,
        w = 300,
        h = 20,
        text = "开启后将进入PSM+，屏幕熄灭",
        font_size = 14,
        color = 0x5F7FA3,
        align = airui.TEXT_ALIGN_RIGHT
    })
end

-- ==================== 配置窗口模块 ====================
local config_win_id = nil
local config_container
local wakeup_pull_group = nil

-- 重新创建WAKEUP上下拉下拉框
local function recreate_wakeup_pull_dropdown()
    if not wakeup_pull_group then
        return
    end
    
    if ui_refs.wakeup_pull_select then
        ui_refs.wakeup_pull_select:destroy()
        ui_refs.wakeup_pull_select = nil
    end
    
    local selected_index = config.wakeup.index
    local options = {"PULLUP", "PULLDOWN"}
    local default_index = 0
    
    if selected_index == 2 then
        options = {"nil"}
        default_index = 0
        config.wakeup.pull = "nil"
    else
        if config.wakeup.pull == "PULLUP" then
            default_index = 0
        elseif config.wakeup.pull == "PULLDOWN" then
            default_index = 1
        else
            config.wakeup.pull = "PULLUP"
            default_index = 0
        end
    end
    
    ui_refs.wakeup_pull_select = airui.dropdown({
        parent = wakeup_pull_group,
        x = 300,
        y = 62,
        w = 120,
        h = 25,
        options = options,
        default_index = default_index,
        on_change = function(self, idx)
            if config.wakeup.index == 2 then
                config.wakeup.pull = "nil"
            else
                local opts = {"PULLUP", "PULLDOWN"}
                config.wakeup.pull = opts[idx + 1]
            end
            local pull_txt = config.wakeup.pull
            if config.wakeup.index == 2 then
                pull_txt = "nil"
            end
            wakeup_sources.wakeup.desc = "WAKEUP" .. config.wakeup.index .. " • " .. pull_txt .. " • " .. config.wakeup.edge
        end
    })
end

-- 更新WAKEUP上下拉选项
local function update_wakeup_pull_options()
    recreate_wakeup_pull_dropdown()
end

-- 初始化配置窗口
local function init_config_dropdowns()
    if not config_container then
        return
    end
    
    -- 创建数字键盘
    local numeric_kb = create_numeric_keyboard()
    
    -- 定时器分钟数输入框
    if ui_refs.timer_minutes_input then
        ui_refs.timer_minutes_input:set_text(tostring(config.timer.minutes))
        if numeric_kb then
            ui_refs.timer_minutes_input:attach_keyboard(numeric_kb)
        end
    end
    
    -- UART波特率输入框
    if ui_refs.uart_baud_input then
        ui_refs.uart_baud_input:set_text(tostring(config.uart.baud))
        if numeric_kb then
            ui_refs.uart_baud_input:attach_keyboard(numeric_kb)
        end
    end
    
    if ui_refs.pwrkey_pull_select then
        ui_refs.pwrkey_pull_select:set_selected(0)
    end
    
    if ui_refs.pwrkey_edge_select then
        local edge_index = 2
        if config.pwrkey.edge == "FALLING" then
            edge_index = 0
        elseif config.pwrkey.edge == "RISING" then
            edge_index = 1
        elseif config.pwrkey.edge == "BOTH" then
            edge_index = 2
        end
        ui_refs.pwrkey_edge_select:set_selected(edge_index)
    end
    
    if ui_refs.chgdet_pull_select then
        ui_refs.chgdet_pull_select:set_selected(0)
    end
    
    if ui_refs.chgdet_edge_select then
        local edge_index = 1
        if config.chgdet.edge == "FALLING" then
            edge_index = 0
        elseif config.chgdet.edge == "RISING" then
            edge_index = 1
        elseif config.chgdet.edge == "BOTH" then
            edge_index = 2
        end
        ui_refs.chgdet_edge_select:set_selected(edge_index)
    end
    
    if ui_refs.wakeup_select then
        ui_refs.wakeup_select:set_selected(config.wakeup.index)
    end
    
    update_wakeup_pull_options()
    
    if ui_refs.wakeup_edge_select then
        local edge_index = 2
        if config.wakeup.edge == "FALLING" then
            edge_index = 0
        elseif config.wakeup.edge == "RISING" then
            edge_index = 1
        elseif config.wakeup.edge == "BOTH" then
            edge_index = 2
        end
        ui_refs.wakeup_edge_select:set_selected(edge_index)
    end
end

-- 配置窗口的创建函数
local function on_config_create()
    log.info("psm", "创建配置窗口")
    
    config_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0xF8FCFF
    })

    -- 顶部标题栏
    local header = airui.container({
        parent = config_container,
        x = 0,
        y = 0,
        w = 480,
        h = 55,
        color = 0x3F51B5
    })

    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 10,
        y = 7,
        w = 50,
        h = 41,
        color = 0x2195F6,
        radius = 20,
        on_click = function()
            log.info("psm", "返回主界面")
            if ui_refs.numeric_keyboard then
                ui_refs.numeric_keyboard:hide()
            end
            exwin.close(config_win_id)
        end
    })
    
    airui.label({
        parent = back_btn,
        x = 8,
        y = 12,
        w = 35,
        h = 21,
        text = "<<",
        font_size = 16,
        color = 0xFEFEFE,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = header,
        x = 50,
        y = 12,
        w = 200,
        h = 32,
        text = "唤醒详细配置",
        font_size = 24,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 配置内容区域
    local content = airui.container({
        parent = config_container,
        x = 0,
        y = 60,
        w = 480,
        h = 210,
        color = 0xF8FCFF
    })

    local y_offset = 0
    local group_height = 80
    local group_spacing = 10

    -- 定时器配置组
    local timer_group = airui.container({
        parent = content,
        x = 20,
        y = y_offset,
        w = 440,
        h = 60,
        color = 0xDBE6F2,
        radius = 30
    })

    airui.label({
        parent = timer_group,
        x = 16,
        y = 8,
        w = 200,
        h = 24,
        text = "定时器唤醒",
        font_size = 18,
        color = 0x124773
    })

    airui.label({
        parent = timer_group,
        x = 16,
        y = 35,
        w = 80,
        h = 20,
        text = "间隔(分钟)",
        font_size = 14,
        color = 0x1A4A78
    })

    ui_refs.timer_minutes_input = airui.textarea({
        parent = timer_group,
        x = 300,
        y = 28,
        w = 80,
        h = 25,
        text = tostring(config.timer.minutes),
        placeholder = "5",
        keyboard = nil,
    })

    airui.label({
        parent = timer_group,
        x = 390,
        y = 32,
        w = 40,
        h = 20,
        text = "分钟",
        font_size = 13,
        color = 0x3B6B99
    })

    y_offset = y_offset + 60 + group_spacing

    -- UART配置组
    local uart_group = airui.container({
        parent = content,
        x = 20,
        y = y_offset,
        w = 440,
        h = 70,
        color = 0xDBE6F2,
        radius = 30
    })

    airui.label({
        parent = uart_group,
        x = 16,
        y = 8,
        w = 200,
        h = 24,
        text = "UART唤醒",
        font_size = 18,
        color = 0x124773
    })

    airui.label({
        parent = uart_group,
        x = 16,
        y = 36,
        w = 80,
        h = 20,
        text = "波特率",
        font_size = 14,
        color = 0x1A4A78
    })

    ui_refs.uart_baud_input = airui.textarea({
        parent = uart_group,
        x = 300,
        y = 32,
        w = 120,
        h = 25,
        text = tostring(config.uart.baud),
        placeholder = "9600",
        keyboard = nil,
    })

    y_offset = y_offset + 70 + group_spacing

    -- PWR_KEY配置组
    local pwrkey_group = airui.container({
        parent = content,
        x = 20,
        y = y_offset,
        w = 440,
        h = 70,
        color = 0xDBE6F2,
        radius = 30
    })

    airui.label({
        parent = pwrkey_group,
        x = 16,
        y = 8,
        w = 200,
        h = 24,
        text = "PWR_KEY唤醒",
        font_size = 18,
        color = 0x124773
    })

    airui.label({
        parent = pwrkey_group,
        x = 16,
        y = 36,
        w = 80,
        h = 20,
        text = "触发方式",
        font_size = 14,
        color = 0x1A4A78
    })

    ui_refs.pwrkey_edge_select = airui.dropdown({
        parent = pwrkey_group,
        x = 300,
        y = 32,
        w = 120,
        h = 25,
        options = {"FALLING", "RISING", "BOTH"},
        default_index = 2,
        on_change = function(self, idx)
            local options = {"FALLING", "RISING", "BOTH"}
            config.pwrkey.edge = options[idx + 1]
            wakeup_sources.pwrkey.desc = config.pwrkey.pull .. " • " .. config.pwrkey.edge
        end
    })

    y_offset = y_offset + 70 + group_spacing

    -- CHG_DET配置组
    local chgdet_group = airui.container({
        parent = content,
        x = 20,
        y = y_offset,
        w = 440,
        h = 70,
        color = 0xDBE6F2,
        radius = 30
    })

    airui.label({
        parent = chgdet_group,
        x = 16,
        y = 8,
        w = 200,
        h = 24,
        text = "CHG_DET唤醒",
        font_size = 18,
        color = 0x124773
    })

    airui.label({
        parent = chgdet_group,
        x = 16,
        y = 36,
        w = 80,
        h = 20,
        text = "触发方式",
        font_size = 14,
        color = 0x1A4A78
    })

    ui_refs.chgdet_edge_select = airui.dropdown({
        parent = chgdet_group,
        x = 300,
        y = 32,
        w = 120,
        h = 25,
        options = {"FALLING", "RISING", "BOTH"},
        default_index = 1,
        on_change = function(self, idx)
            local options = {"FALLING", "RISING", "BOTH"}
            config.chgdet.edge = options[idx + 1]
            wakeup_sources.chgdet.desc = config.chgdet.pull .. " • " .. config.chgdet.edge
        end
    })

    y_offset = y_offset + 70 + group_spacing

    -- WAKEUP配置组
    wakeup_pull_group = airui.container({
        parent = content,
        x = 20,
        y = y_offset,
        w = 440,
        h = 120,
        color = 0xDBE6F2,
        radius = 30
    })

    airui.label({
        parent = wakeup_pull_group,
        x = 16,
        y = 8,
        w = 200,
        h = 24,
        text = "WAKEUP唤醒",
        font_size = 18,
        color = 0x124773
    })

    airui.label({
        parent = wakeup_pull_group,
        x = 16,
        y = 36,
        w = 80,
        h = 20,
        text = "唤醒源",
        font_size = 14,
        color = 0x1A4A78
    })

    ui_refs.wakeup_select = airui.dropdown({
        parent = wakeup_pull_group,
        x = 300,
        y = 32,
        w = 120,
        h = 25,
        options = {"WAKEUP0", "WAKEUP1", "WAKEUP2", "WAKEUP3", "WAKEUP4"},
        default_index = config.wakeup.index,
        on_change = function(self, idx)
            config.wakeup.index = idx
            update_wakeup_pull_options()
            local pull_txt = config.wakeup.pull
            if idx == 2 then
                pull_txt = "nil"
            end
            wakeup_sources.wakeup.desc = "WAKEUP" .. config.wakeup.index .. " • " .. pull_txt .. " • " .. config.wakeup.edge
        end
    })

    airui.label({
        parent = wakeup_pull_group,
        x = 16,
        y = 66,
        w = 80,
        h = 20,
        text = "上下拉",
        font_size = 14,
        color = 0x1A4A78
    })

    ui_refs.wakeup_pull_select = nil

    airui.label({
        parent = wakeup_pull_group,
        x = 16,
        y = 91,
        w = 80,
        h = 20,
        text = "触发方式",
        font_size = 14,
        color = 0x1A4A78
    })

    ui_refs.wakeup_edge_select = airui.dropdown({
        parent = wakeup_pull_group,
        x = 300,
        y = 87,
        w = 120,
        h = 25,
        options = {"FALLING", "RISING", "BOTH"},
        default_index = 2,
        on_change = function(self, idx)
            local options = {"FALLING", "RISING", "BOTH"}
            config.wakeup.edge = options[idx + 1]
            local pull_txt = config.wakeup.pull
            if config.wakeup.index == 2 then
                pull_txt = "nil"
            end
            wakeup_sources.wakeup.desc = "WAKEUP" .. config.wakeup.index .. " • " .. pull_txt .. " • " .. config.wakeup.edge
        end
    })

    -- 保存按钮
    local save_btn = airui.button({
        parent = config_container,
        x = 40,
        y = 275,
        w = 400,
        h = 40,
        text = "保存唤醒配置",
        on_click = function()
            local timer_val = tonumber(ui_refs.timer_minutes_input:get_text()) or 5
            if timer_val < 1 then
                timer_val = 1
            end
            if timer_val > 1440 then
                timer_val = 1440
            end
            
            -- 检查定时器唤醒时间是否小于75秒（即1.25分钟）
            -- 如果小于75秒，弹出提示弹窗，用户点击确定后弹窗关闭，不保存配置
            if timer_val * 60 < 75 then
                airui.msgbox({
                    title = "提示",
                    text = "建议唤醒时间不要小于75秒",
                    buttons = {"确定"},
                    button_align = "left",
                    timeout = 0,
                    on_action = function(box, label)
                        box:hide()
                    end
                })
                return
            end
            
            config.timer.minutes = timer_val

            local baud_val = tonumber(ui_refs.uart_baud_input:get_text()) or 9600
            if baud_val < 300 then
                baud_val = 300
            end
            if baud_val > 921600 then
                baud_val = 921600
            end
            config.uart.baud = baud_val

            if exwin.is_active(config_win_id) then
                airui.msgbox({
                    title = "提示",
                    text = "保存唤醒配置？",
                    buttons = {"确定", "取消"},
                    button_align = "left",
                    timeout = 0,
                    on_action = function(box, label)
                        if label == "确定" then
                            update_main_descriptions()
                            box:hide()
                            if ui_refs.numeric_keyboard then
                                ui_refs.numeric_keyboard:hide()
                            end
                            exwin.close(config_win_id)
                            log.info("psm", "配置已保存")
                        elseif label == "取消" then
                            box:hide()
                            log.info("psm", "取消保存")
                        end
                    end
                })
            end
        end
    })
    
    -- 创建数字键盘并绑定输入框
    local numeric_kb = create_numeric_keyboard()
    if numeric_kb then
        if ui_refs.timer_minutes_input then
            ui_refs.timer_minutes_input:attach_keyboard(numeric_kb)
        end
        if ui_refs.uart_baud_input then
            ui_refs.uart_baud_input:attach_keyboard(numeric_kb)
        end
    end
    
    recreate_wakeup_pull_dropdown()
    init_config_dropdowns()
end

-- 配置窗口的销毁函数
local function on_config_destroy()
    log.info("psm", "销毁配置窗口")
    if ui_refs.numeric_keyboard then
        ui_refs.numeric_keyboard:hide()
        ui_refs.numeric_keyboard:destroy()
        ui_refs.numeric_keyboard = nil
    end
    if config_container then
        config_container:destroy()
        config_container = nil
    end
    config_win_id = nil
    wakeup_pull_group = nil
end

-- 配置窗口的获得焦点函数
local function on_config_get_focus()
    log.info("psm", "配置窗口获得焦点")
    init_config_dropdowns()
end

-- 配置窗口的失去焦点函数
local function on_config_lose_focus()
    log.info("psm", "配置窗口失去焦点")
    if ui_refs.numeric_keyboard then
        ui_refs.numeric_keyboard:hide()
    end
end

-- 订阅打开配置窗口的消息
local function open_config_handler()
    log.info("psm", "收到打开配置窗口消息")
    if not exwin.is_active(config_win_id) then
        config_win_id = exwin.open({
            on_create = on_config_create,
            on_destroy = on_config_destroy,
            on_get_focus = on_config_get_focus,
            on_lose_focus = on_config_lose_focus,
        })
        log.info("psm", "配置窗口ID:", config_win_id)
    else
        init_config_dropdowns()
    end
end

sys.subscribe("OPEN_CONFIG_WIN", open_config_handler)

-- ==================== 主窗口模块 ====================

local function on_create()
    log.info("psm", "创建PSM配置窗口")
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0xFFFFF0
    })

    local header = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 55,
        color = 0x3F51B5
    })

    local back_btn = airui.container({
        parent = header,
        x = 10,
        y = 7,
        w = 50,
        h = 41,
        color = 0x2195F6,
        radius = 20,
        on_click = function()
            log.info("psm", "关闭窗口")
            exwin.close(win_id)
        end
    })

    airui.label({
        parent = back_btn,
        x = 8,
        y = 12,
        w = 35,
        h = 21,
        text = "<<",
        font_size = 22,
        color = 0xFFFFF0,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = header,
        x = 53,
        y = 17,
        w = 200,
        h = 28,
        text = "PSM+ 模式控制",
        font_size = 25,
        color = 0xFFFFF0,
        align = airui.TEXT_ALIGN_CENTER
    })

    create_main_ui(main_container)

    update_main_descriptions()
    update_all_switches()
    update_warning()
end

local function on_destroy()
    log.info("psm", "销毁PSM配置窗口")
    reset_to_default()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    psm_master_switch = nil
    ui_refs = {}
    win_id = nil
end

local function on_get_focus()
    log.info("psm", "窗口获得焦点")
    update_main_descriptions()
    update_all_switches()
    update_warning()
end

local function on_lose_focus()
    log.info("psm", "窗口失去焦点")
end

local function open_handler()
    log.info("psm", "收到打开窗口消息")
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus
        })
        log.info("psm", "主窗口ID:", win_id)
    else
        log.info("psm", "窗口已存在")
    end
end

sys.subscribe("OPEN_PSM_WIN", open_handler)

return {
    get_config = function()
        return config
    end,
    get_wakeup_sources = function()
        return wakeup_sources
    end,
    is_psm_enabled = function()
        return psm_master_switch and psm_master_switch:get_state() or false
    end
}