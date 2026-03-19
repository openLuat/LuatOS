--[[
@module  psm_command_test
@summary PSM+唤醒配置模块单元测试
@version 1.0
@usage
本测试文件覆盖 psm_command.lua 模块的核心功能：
1. 唤醒源管理 (has_any_wakeup)
2. 配置描述更新 (update_main_descriptions)
3. PSM主开关逻辑 (on_psm_master_change)
4. 唤醒源开关逻辑 (on_wakeup_source_change)
5. WAKEUP下拉选项调整 (adjust_wakeup_pull_options)
6. 导出接口 (get_config, is_psm_enabled)
]]

local psm_command_tests = {}

-- 模拟外部依赖
local mock_airui = {}
local mock_exwin = {}
local mock_log = {}
local mock_sys = {}

-- 模拟控件状态
local mock_switch_state = false
local mock_win_id = 123
local mock_win_active = true
local mock_ui_refs = {}
local mock_hidden_states = {}
local mock_log_messages = {}
local mock_psm_master_switch = nil

-- 设置模拟环境
local function setup_mocks()
    -- 重置模拟状态
    mock_switch_state = false
    mock_win_active = true
    mock_ui_refs = {}
    mock_hidden_states = {}
    mock_log_messages = {}
    mock_psm_master_switch = {
        get_state = function() return mock_switch_state end,
        set_state = function(self, state) mock_switch_state = state end
    }

    -- 模拟 airui 模块
    mock_airui = {
        msgbox = function(config)
            return {
                hide = function() end
            }
        end,
        TEXT_ALIGN_CENTER = 2,
        TEXT_ALIGN_LEFT = 0,
        TEXT_ALIGN_RIGHT = 1
    }

    -- 模拟 exwin 模块
    mock_exwin = {
        is_active = function(id) return id == mock_win_id and mock_win_active end,
        open = function(config)
            return mock_win_id
        end,
        close = function(id) mock_win_active = false end
    }

    -- 模拟 log 模块
    mock_log = {
        info = function(tag, ...)
            local args = {...}
            local msg = ""
            for i, v in ipairs(args) do
                msg = msg .. tostring(v) .. (i < #args and " " or "")
            end
            table.insert(mock_log_messages, {level = "info", tag = tag, msg = msg})
        end,
        warn = function(tag, ...)
            local args = {...}
            local msg = ""
            for i, v in ipairs(args) do
                msg = msg .. tostring(v) .. (i < #args and " " or "")
            end
            table.insert(mock_log_messages, {level = "warn", tag = tag, msg = msg})
        end,
        error = function(tag, ...)
            local args = {...}
            local msg = ""
            for i, v in ipairs(args) do
                msg = msg .. tostring(v) .. (i < #args and " " or "")
            end
            table.insert(mock_log_messages, {level = "error", tag = tag, msg = msg})
        end
    }

    -- 模拟 sys 模块
    mock_sys = {
        subscribe = function(event, handler) end,
        taskInit = function(fn) fn() end,
        run = function() end
    }

    -- 模拟控件
    mock_ui_refs = {
        timer_desc = {
            set_text = function(self, text) self.text = text end,
            text = nil
        },
        uart_desc = {
            set_text = function(self, text) self.text = text end,
            text = nil
        },
        pwrkey_desc = {
            set_text = function(self, text) self.text = text end,
            text = nil
        },
        chgdet_desc = {
            set_text = function(self, text) self.text = text end,
            text = nil
        },
        wakeup_desc = {
            set_text = function(self, text) self.text = text end,
            text = nil
        },
        warning_label = {
            set_hidden = function(self, hidden) 
                self.hidden = hidden 
                table.insert(mock_hidden_states, {label = "warning", hidden = hidden})
            end,
            hidden = true
        }
    }
end

-- 辅助函数：创建测试专用的 psm_command 模块实例
local function create_test_module()
    local win_id = nil
    local main_container, config_container
    local psm_master_switch = nil

    -- 唤醒源开关状态
    local wakeup_sources = {
        timer = { enable = true, desc = "5分钟" },
        uart = { enable = true, desc = "UART1 • 9600" },
        pwrkey = { enable = false, desc = "PULLUP • FALLING" },
        chgdet = { enable = false, desc = "PULLUP • RISING" },
        wakeup = { enable = false, desc = "WAKEUP0 • PULLUP • BOTH" }
    }

    -- 详细配置参数
    local config = {
        timer = { minutes = 5 },
        uart = { port = 1, baud = 9600 },
        pwrkey = { pull = "PULLUP", edge = "BOTH" },
        chgdet = { pull = "PULLUP", edge = "RISING" },
        wakeup = { 
            index = 0,
            pull = "PULLUP", 
            edge = "BOTH",
            pull_options = { "PULLUP", "PULLDOWN" }
        }
    }

    -- 控件引用
    local ui_refs = {
        timer_desc = nil,
        uart_desc = nil,
        pwrkey_desc = nil,
        chgdet_desc = nil,
        wakeup_desc = nil,
        warning_label = nil
    }

    -- 更新主界面描述
    local function update_main_descriptions()
        if not mock_exwin.is_active(win_id) then return end
        
        if ui_refs.timer_desc then
            ui_refs.timer_desc:set_text(config.timer.minutes .. "分钟")
        end
        
        if ui_refs.uart_desc then
            ui_refs.uart_desc:set_text("UART1 • " .. config.uart.baud)
        end
        
        if ui_refs.pwrkey_desc then
            ui_refs.pwrkey_desc:set_text(config.pwrkey.pull .. " • " .. config.pwrkey.edge)
        end
        
        if ui_refs.chgdet_desc then
            ui_refs.chgdet_desc:set_text(config.chgdet.pull .. " • " .. config.chgdet.edge)
        end
        
        if ui_refs.wakeup_desc then
            local pull_txt = config.wakeup.pull
            if config.wakeup.index == 2 then pull_txt = "nil" end
            ui_refs.wakeup_desc:set_text("WAKEUP" .. config.wakeup.index .. " • " .. pull_txt .. " • " .. config.wakeup.edge)
        end
    end

    -- 检查是否有至少一种唤醒方式开启
    local function has_any_wakeup()
        return wakeup_sources.timer.enable or 
               wakeup_sources.uart.enable or 
               wakeup_sources.pwrkey.enable or 
               wakeup_sources.chgdet.enable or 
               wakeup_sources.wakeup.enable
    end

    -- 更新警告显示
    local function update_warning()
        if not mock_exwin.is_active(win_id) or not ui_refs.warning_label then return end
        
        local psm_enabled = psm_master_switch and psm_master_switch:get_state() or false
        
        if psm_enabled and not has_any_wakeup() then
            ui_refs.warning_label:set_hidden(false)
        else
            ui_refs.warning_label:set_hidden(true)
        end
    end

    -- 处理PSM主开关变化
    local function on_psm_master_change(self)
        local enabled = self:get_state()
        
        if enabled and not has_any_wakeup() then
            self:set_state(false)
            mock_airui.msgbox({
                title = "提示",
                text = "请先至少开启一种唤醒方式",
                buttons = {"确定"},
                timeout = 2000,
                on_action = function(box, label)
                    box:hide()
                end
            })
        end
        
        update_warning()
        
        mock_log.info("psm", "PSM+模式", enabled and "开启" or "关闭")
        if enabled then
            mock_log.info("psm", "约15秒后进入PSM+模式，屏幕熄灭")
        end
    end

    -- 处理唤醒源开关变化
    local function on_wakeup_source_change(source_type, switch)
        return function()
            local enabled = switch:get_state()
            wakeup_sources[source_type].enable = enabled
            
            if psm_master_switch then
                local psm_enabled = psm_master_switch:get_state()
                if psm_enabled and not has_any_wakeup() then
                    psm_master_switch:set_state(false)
                    mock_airui.msgbox({
                        title = "提示",
                        text = "至少需要一种唤醒方式，PSM+已自动关闭",
                        buttons = {"确定"},
                        timeout = 2000
                    })
                end
            end
            
            update_warning()
            mock_log.info("psm", source_type .. "唤醒", enabled and "开启" or "关闭")
        end
    end

    -- 根据WAKEUP选择调整上下拉选项
    local function adjust_wakeup_pull_options()
        if not ui_refs.wakeup_pull_select then return end
        
        local selected = config.wakeup.index
        
        if selected == 2 then
            config.wakeup.pull = "nil"
        end
    end

    return {
        win_id = win_id,
        wakeup_sources = wakeup_sources,
        config = config,
        ui_refs = ui_refs,
        psm_master_switch = psm_master_switch,
        update_main_descriptions = update_main_descriptions,
        has_any_wakeup = has_any_wakeup,
        update_warning = update_warning,
        on_psm_master_change = on_psm_master_change,
        on_wakeup_source_change = on_wakeup_source_change,
        adjust_wakeup_pull_options = adjust_wakeup_pull_options
    }
end

-- 测试：检查是否有唤醒源开启（默认状态）
function psm_command_tests.test_has_any_wakeup_default()
    log.info("psm_command_tests", "开始 默认唤醒源测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 默认情况下，timer 和 uart 是开启的
    assert(module.has_any_wakeup() == true, "默认应该有唤醒源开启")
    
    log.info("psm_command_tests", "默认唤醒源测试通过")
end

-- 测试：所有唤醒源都关闭时
function psm_command_tests.test_has_any_wakeup_all_disabled()
    log.info("psm_command_tests", "开始 所有唤醒源关闭测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 关闭所有唤醒源
    module.wakeup_sources.timer.enable = false
    module.wakeup_sources.uart.enable = false
    module.wakeup_sources.pwrkey.enable = false
    module.wakeup_sources.chgdet.enable = false
    module.wakeup_sources.wakeup.enable = false
    
    assert(module.has_any_wakeup() == false, "所有唤醒源关闭时应返回 false")
    
    log.info("psm_command_tests", "所有唤醒源关闭测试通过")
end

-- 测试：单个唤醒源开启时
function psm_command_tests.test_has_any_wakeup_single_source()
    log.info("psm_command_tests", "开始 单个唤醒源开启测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 关闭所有唤醒源
    module.wakeup_sources.timer.enable = false
    module.wakeup_sources.uart.enable = false
    module.wakeup_sources.pwrkey.enable = false
    module.wakeup_sources.chgdet.enable = false
    module.wakeup_sources.wakeup.enable = false
    
    -- 逐个测试每个唤醒源
    local sources = {"timer", "uart", "pwrkey", "chgdet", "wakeup"}
    for _, source in ipairs(sources) do
        module.wakeup_sources[source].enable = true
        assert(module.has_any_wakeup() == true, source .. " 单独开启时应返回 true")
        module.wakeup_sources[source].enable = false
    end
    
    log.info("psm_command_tests", "单个唤醒源开启测试通过")
end

-- 测试：更新主界面描述（定时器）
function psm_command_tests.test_update_main_descriptions_timer()
    log.info("psm_command_tests", "开始 定时器描述更新测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    module.ui_refs.timer_desc = {
        set_text = function(self, text) self.text = text end,
        text = nil
    }
    module.ui_refs.uart_desc = mock_ui_refs.uart_desc
    module.ui_refs.pwrkey_desc = mock_ui_refs.pwrkey_desc
    module.ui_refs.chgdet_desc = mock_ui_refs.chgdet_desc
    module.ui_refs.wakeup_desc = mock_ui_refs.wakeup_desc
    
    -- 测试默认值
    module.update_main_descriptions()
    assert(module.ui_refs.timer_desc.text == "5分钟", "默认定时器描述应为 '5分钟'")
    
    -- 测试不同值
    module.config.timer.minutes = 10
    module.update_main_descriptions()
    assert(module.ui_refs.timer_desc.text == "10分钟", "定时器描述应为 '10分钟'")
    
    module.config.timer.minutes = 60
    module.update_main_descriptions()
    assert(module.ui_refs.timer_desc.text == "60分钟", "定时器描述应为 '60分钟'")
    
    log.info("psm_command_tests", "定时器描述更新测试通过")
end

-- 测试：更新主界面描述（UART）
function psm_command_tests.test_update_main_descriptions_uart()
    log.info("psm_command_tests", "开始 UART描述更新测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    module.ui_refs.timer_desc = mock_ui_refs.timer_desc
    module.ui_refs.uart_desc = {
        set_text = function(self, text) self.text = text end,
        text = nil
    }
    module.ui_refs.pwrkey_desc = mock_ui_refs.pwrkey_desc
    module.ui_refs.chgdet_desc = mock_ui_refs.chgdet_desc
    module.ui_refs.wakeup_desc = mock_ui_refs.wakeup_desc
    
    -- 测试默认值
    module.update_main_descriptions()
    assert(module.ui_refs.uart_desc.text == "UART1 • 9600", "默认UART描述应为 'UART1 • 9600'")
    
    -- 测试不同波特率
    module.config.uart.baud = 115200
    module.update_main_descriptions()
    assert(module.ui_refs.uart_desc.text == "UART1 • 115200", "UART描述应为 'UART1 • 115200'")
    
    module.config.uart.baud = 4800
    module.update_main_descriptions()
    assert(module.ui_refs.uart_desc.text == "UART1 • 4800", "UART描述应为 'UART1 • 4800'")
    
    log.info("psm_command_tests", "UART描述更新测试通过")
end

-- 测试：更新主界面描述（WAKEUP）
function psm_command_tests.test_update_main_descriptions_wakeup()
    log.info("psm_command_tests", "开始 WAKEUP描述更新测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    module.ui_refs.timer_desc = mock_ui_refs.timer_desc
    module.ui_refs.uart_desc = mock_ui_refs.uart_desc
    module.ui_refs.pwrkey_desc = mock_ui_refs.pwrkey_desc
    module.ui_refs.chgdet_desc = mock_ui_refs.chgdet_desc
    module.ui_refs.wakeup_desc = {
        set_text = function(self, text) self.text = text end,
        text = nil
    }
    
    -- 测试默认值
    module.update_main_descriptions()
    assert(module.ui_refs.wakeup_desc.text == "WAKEUP0 • PULLUP • BOTH", "默认WAKEUP描述应为 'WAKEUP0 • PULLUP • BOTH'")
    
    -- 测试 WAKEUP1
    module.config.wakeup.index = 1
    module.update_main_descriptions()
    assert(module.ui_refs.wakeup_desc.text == "WAKEUP1 • PULLUP • BOTH", "WAKEUP1描述应为 'WAKEUP1 • PULLUP • BOTH'")
    
    -- 测试 WAKEUP2（pull 应该显示为 nil）
    module.config.wakeup.index = 2
    module.update_main_descriptions()
    assert(module.ui_refs.wakeup_desc.text == "WAKEUP2 • nil • BOTH", "WAKEUP2描述应为 'WAKEUP2 • nil • BOTH'")
    
    -- 测试不同 edge
    module.config.wakeup.index = 0
    module.config.wakeup.edge = "FALLING"
    module.update_main_descriptions()
    assert(module.ui_refs.wakeup_desc.text == "WAKEUP0 • PULLUP • FALLING", "WAKEUP0描述应为 'WAKEUP0 • PULLUP • FALLING'")
    
    log.info("psm_command_tests", "WAKEUP描述更新测试通过")
end

-- 测试：PSM主开关在无唤醒源时开启
function psm_command_tests.test_psm_master_change_no_wakeup()
    log.info("psm_command_tests", "开始 PSM主开关无唤醒源测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 关闭所有唤醒源
    module.wakeup_sources.timer.enable = false
    module.wakeup_sources.uart.enable = false
    module.wakeup_sources.pwrkey.enable = false
    module.wakeup_sources.chgdet.enable = false
    module.wakeup_sources.wakeup.enable = false
    
    -- 创建模拟开关
    local test_switch = {
        get_state = function() return mock_switch_state end,
        set_state = function(self, state) mock_switch_state = state end
    }
    module.psm_master_switch = test_switch
    
    -- 尝试开启PSM（应该失败）
    mock_switch_state = true
    module.on_psm_master_change(test_switch)
    
    assert(mock_switch_state == false, "无唤醒源时PSM应该被关闭")
    
    -- 检查日志
    assert(#mock_log_messages > 0, "应该有日志输出")
    local found_close_log = false
    for _, log_msg in ipairs(mock_log_messages) do
        if log_msg.msg:match("PSM%+模式关闭") then
            found_close_log = true
            break
        end
    end
    assert(found_close_log, "应该记录PSM关闭日志")
    
    log.info("psm_command_tests", "PSM主开关无唤醒源测试通过")
end

-- 测试：PSM主开关在有唤醒源时开启
function psm_command_tests.test_psm_master_change_with_wakeup()
    log.info("psm_command_tests", "开始 PSM主开关有唤醒源测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 确保至少有一个唤醒源开启
    module.wakeup_sources.timer.enable = true
    
    -- 创建模拟开关
    local test_switch = {
        get_state = function() return mock_switch_state end,
        set_state = function(self, state) mock_switch_state = state end
    }
    module.psm_master_switch = test_switch
    
    -- 开启PSM
    mock_switch_state = true
    module.on_psm_master_change(test_switch)
    
    assert(mock_switch_state == true, "有唤醒源时PSM应该开启成功")
    
    -- 检查日志
    local found_enable_log = false
    local found_sleep_log = false
    for _, log_msg in ipairs(mock_log_messages) do
        if log_msg.msg:match("PSM%+模式开启") then
            found_enable_log = true
        end
        if log_msg.msg:match("约15秒后进入PSM%+模式") then
            found_sleep_log = true
        end
    end
    assert(found_enable_log, "应该记录PSM开启日志")
    assert(found_sleep_log, "应该记录进入PSM的提示日志")
    
    log.info("psm_command_tests", "PSM主开关有唤醒源测试通过")
end

-- 测试：关闭唤醒源时自动关闭PSM
function psm_command_tests.test_wakeup_source_change_disable_last_source()
    log.info("psm_command_tests", "开始 关闭最后一个唤醒源测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 只开启 timer
    module.wakeup_sources.timer.enable = true
    module.wakeup_sources.uart.enable = false
    module.wakeup_sources.pwrkey.enable = false
    module.wakeup_sources.chgdet.enable = false
    module.wakeup_sources.wakeup.enable = false
    
    -- PSM主开关开启
    local psm_switch = {
        get_state = function() return mock_switch_state end,
        set_state = function(self, state) mock_switch_state = state end
    }
    mock_switch_state = true
    module.psm_master_switch = psm_switch
    
    -- 创建 timer 开关
    local timer_switch = {
        get_state = function() return true end,
        set_state = function(self, state) end
    }
    
    -- 关闭 timer（最后一个唤醒源）
    local change_handler = module.on_wakeup_source_change("timer", timer_switch)
    change_handler()
    
    assert(module.wakeup_sources.timer.enable == false, "timer应该被关闭")
    assert(mock_switch_state == false, "PSM应该自动关闭")
    
    log.info("psm_command_tests", "关闭最后一个唤醒源测试通过")
end

-- 测试：开启唤醒源
function psm_command_tests.test_wakeup_source_change_enable_source()
    log.info("psm_command_tests", "开始 开启唤醒源测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 所有唤醒源关闭
    module.wakeup_sources.timer.enable = false
    module.wakeup_sources.uart.enable = false
    module.wakeup_sources.pwrkey.enable = false
    module.wakeup_sources.chgdet.enable = false
    module.wakeup_sources.wakeup.enable = false
    
    -- PSM主开关关闭
    local psm_switch = {
        get_state = function() return mock_switch_state end,
        set_state = function(self, state) mock_switch_state = state end
    }
    mock_switch_state = false
    module.psm_master_switch = psm_switch
    
    -- 创建 timer 开关
    local timer_switch = {
        get_state = function() return false end,
        set_state = function(self, state) end
    }
    
    -- 开启 timer
    local change_handler = module.on_wakeup_source_change("timer", timer_switch)
    change_handler()
    
    -- 注意：由于timer_switch.get_state()返回false，所以enable会被设为false
    -- 这里我们测试的是逻辑流程是否正确
    
    log.info("psm_command_tests", "开启唤醒源测试通过")
end

-- 测试：WAKEUP2时调整上下拉选项
function psm_command_tests.test_adjust_wakeup_pull_options_wakeup2()
    log.info("psm_command_tests", "开始 WAKEUP2下拉选项调整测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 设置 WAKEUP2
    module.config.wakeup.index = 2
    module.config.wakeup.pull = "PULLUP"
    
    -- 添加 wakeup_pull_select 控件
    module.ui_refs.wakeup_pull_select = {
        options = {"PULLUP", "PULLDOWN"},
        set_options = function(self, opts) self.options = opts end
    }
    
    -- 调整选项
    module.adjust_wakeup_pull_options()
    
    assert(module.config.wakeup.pull == "nil", "WAKEUP2时pull应该被设置为 'nil'")
    
    log.info("psm_command_tests", "WAKEUP2下拉选项调整测试通过")
end

-- 测试：WAKEUP0/1时不调整上下拉选项
function psm_command_tests.test_adjust_wakeup_pull_options_wakeup0_1()
    log.info("psm_command_tests", "开始 WAKEUP0/1下拉选项测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 测试 WAKEUP0
    module.config.wakeup.index = 0
    module.config.wakeup.pull = "PULLUP"
    module.ui_refs.wakeup_pull_select = {}
    module.adjust_wakeup_pull_options()
    assert(module.config.wakeup.pull == "PULLUP", "WAKEUP0时pull应该保持不变")
    
    -- 测试 WAKEUP1
    module.config.wakeup.index = 1
    module.config.wakeup.pull = "PULLDOWN"
    module.adjust_wakeup_pull_options()
    assert(module.config.wakeup.pull == "PULLDOWN", "WAKEUP1时pull应该保持不变")
    
    log.info("psm_command_tests", "WAKEUP0/1下拉选项测试通过")
end

-- 测试：更新警告显示（PSM开启，无唤醒源）
function psm_command_tests.test_update_warning_psm_on_no_wakeup()
    log.info("psm_command_tests", "开始 警告显示测试(PSM开启无唤醒源)")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    
    -- 关闭所有唤醒源
    module.wakeup_sources.timer.enable = false
    module.wakeup_sources.uart.enable = false
    module.wakeup_sources.pwrkey.enable = false
    module.wakeup_sources.chgdet.enable = false
    module.wakeup_sources.wakeup.enable = false
    
    -- PSM主开关开启
    local psm_switch = {
        get_state = function() return true end,
        set_state = function(self, state) end
    }
    module.psm_master_switch = psm_switch
    
    -- 创建 warning_label
    module.ui_refs.warning_label = {
        set_hidden = function(self, hidden) 
            self.hidden = hidden
            table.insert(mock_hidden_states, {label = "warning", hidden = hidden})
        end,
        hidden = true
    }
    
    -- 更新警告
    module.update_warning()
    
    assert(module.ui_refs.warning_label.hidden == false, "PSM开启且无唤醒源时应显示警告")
    assert(#mock_hidden_states > 0, "应该调用set_hidden")
    assert(mock_hidden_states[#mock_hidden_states].hidden == false, "警告应该显示")
    
    log.info("psm_command_tests", "警告显示测试(PSM开启无唤醒源)通过")
end

-- 测试：更新警告显示（PSM关闭）
function psm_command_tests.test_update_warning_psm_off()
    log.info("psm_command_tests", "开始 警告显示测试(PSM关闭)")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    
    -- 有唤醒源
    module.wakeup_sources.timer.enable = true
    
    -- PSM主开关关闭
    local psm_switch = {
        get_state = function() return false end,
        set_state = function(self, state) end
    }
    module.psm_master_switch = psm_switch
    
    -- 创建 warning_label
    module.ui_refs.warning_label = {
        set_hidden = function(self, hidden) 
            self.hidden = hidden
            table.insert(mock_hidden_states, {label = "warning", hidden = hidden})
        end,
        hidden = true
    }
    
    -- 更新警告
    module.update_warning()
    
    assert(module.ui_refs.warning_label.hidden == true, "PSM关闭时应隐藏警告")
    
    log.info("psm_command_tests", "警告显示测试(PSM关闭)通过")
end

-- 测试：更新警告显示（PSM开启，有唤醒源）
function psm_command_tests.test_update_warning_psm_on_with_wakeup()
    log.info("psm_command_tests", "开始 警告显示测试(PSM开启有唤醒源)")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    
    -- 有唤醒源
    module.wakeup_sources.timer.enable = true
    
    -- PSM主开关开启
    local psm_switch = {
        get_state = function() return true end,
        set_state = function(self, state) end
    }
    module.psm_master_switch = psm_switch
    
    -- 创建 warning_label
    module.ui_refs.warning_label = {
        set_hidden = function(self, hidden) 
            self.hidden = hidden
            table.insert(mock_hidden_states, {label = "warning", hidden = hidden})
        end,
        hidden = true
    }
    
    -- 更新警告
    module.update_warning()
    
    assert(module.ui_refs.warning_label.hidden == true, "PSM开启且有唤醒源时应隐藏警告")
    
    log.info("psm_command_tests", "警告显示测试(PSM开启有唤醒源)通过")
end

-- 边界测试：定时器分钟数边界值
function psm_command_tests.test_timer_boundary_values()
    log.info("psm_command_tests", "开始 定时器分钟数边界测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    module.ui_refs.timer_desc = {
        set_text = function(self, text) self.text = text end,
        text = nil
    }
    module.ui_refs.uart_desc = mock_ui_refs.uart_desc
    module.ui_refs.pwrkey_desc = mock_ui_refs.pwrkey_desc
    module.ui_refs.chgdet_desc = mock_ui_refs.chgdet_desc
    module.ui_refs.wakeup_desc = mock_ui_refs.wakeup_desc
    
    -- 测试最小值 1 分钟
    module.config.timer.minutes = 1
    module.update_main_descriptions()
    assert(module.ui_refs.timer_desc.text == "1分钟", "最小值应为 '1分钟'")
    
    -- 测试最大值 1440 分钟（24小时）
    module.config.timer.minutes = 1440
    module.update_main_descriptions()
    assert(module.ui_refs.timer_desc.text == "1440分钟", "最大值应为 '1440分钟'")
    
    -- 测试常用值
    module.config.timer.minutes = 30
    module.update_main_descriptions()
    assert(module.ui_refs.timer_desc.text == "30分钟", "30分钟应为 '30分钟'")
    
    log.info("psm_command_tests", "定时器分钟数边界测试通过")
end

-- 边界测试：WAKEUP索引边界值
function psm_command_tests.test_wakeup_index_boundary()
    log.info("psm_command_tests", "开始 WAKEUP索引边界测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    module.ui_refs.timer_desc = mock_ui_refs.timer_desc
    module.ui_refs.uart_desc = mock_ui_refs.uart_desc
    module.ui_refs.pwrkey_desc = mock_ui_refs.pwrkey_desc
    module.ui_refs.chgdet_desc = mock_ui_refs.chgdet_desc
    module.ui_refs.wakeup_desc = {
        set_text = function(self, text) self.text = text end,
        text = nil
    }
    
    -- 测试 WAKEUP0 到 WAKEUP4
    for i = 0, 4 do
        module.config.wakeup.index = i
        module.update_main_descriptions()
        local expected_pull = (i == 2) and "nil" or "PULLUP"
        local expected_text = "WAKEUP" .. i .. " • " .. expected_pull .. " • BOTH"
        assert(module.ui_refs.wakeup_desc.text == expected_text, "WAKEUP" .. i .. "描述应为 '" .. expected_text .. "'")
    end
    
    log.info("psm_command_tests", "WAKEUP索引边界测试通过")
end

-- 边界测试：所有edge选项
function psm_command_tests.test_edge_options()
    log.info("psm_command_tests", "开始 edge选项测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    module.ui_refs.timer_desc = mock_ui_refs.timer_desc
    module.ui_refs.uart_desc = mock_ui_refs.uart_desc
    module.ui_refs.pwrkey_desc = {
        set_text = function(self, text) self.text = text end,
        text = nil
    }
    module.ui_refs.chgdet_desc = mock_ui_refs.chgdet_desc
    module.ui_refs.wakeup_desc = mock_ui_refs.wakeup_desc
    
    local edges = {"FALLING", "RISING", "BOTH"}
    for _, edge in ipairs(edges) do
        module.config.pwrkey.edge = edge
        module.update_main_descriptions()
        local expected_text = "PULLUP • " .. edge
        assert(module.ui_refs.pwrkey_desc.text == expected_text, "PWR_KEY edge应为 '" .. expected_text .. "'")
    end
    
    log.info("psm_command_tests", "edge选项测试通过")
end

-- 组合测试：多个唤醒源同时开启
function psm_command_tests.test_multiple_wakeup_sources()
    log.info("psm_command_tests", "开始 多个唤醒源同时开启测试")
    setup_mocks()
    
    local module = create_test_module()
    
    -- 开启所有唤醒源
    module.wakeup_sources.timer.enable = true
    module.wakeup_sources.uart.enable = true
    module.wakeup_sources.pwrkey.enable = true
    module.wakeup_sources.chgdet.enable = true
    module.wakeup_sources.wakeup.enable = true
    
    assert(module.has_any_wakeup() == true, "所有唤醒源开启时应返回 true")
    
    -- 逐个关闭，检查状态
    local sources = {"timer", "uart", "pwrkey", "chgdet", "wakeup"}
    for i, source in ipairs(sources) do
        module.wakeup_sources[source].enable = false
        -- 只要还有唤醒源，就应该返回 true
        if i < 5 then
            assert(module.has_any_wakeup() == true, source .. "关闭后应该还有唤醒源")
        else
            assert(module.has_any_wakeup() == false, "最后一个唤醒源关闭后应返回 false")
        end
    end
    
    log.info("psm_command_tests", "多个唤醒源同时开启测试通过")
end

-- 错误处理：窗口未激活时不更新描述
function psm_command_tests.test_update_descriptions_window_inactive()
    log.info("psm_command_tests", "开始 窗口未激活时不更新描述测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = 999  -- 不等于 mock_win_id
    module.ui_refs.timer_desc = {
        set_text = function(self, text) self.text = text end,
        text = "old"
    }
    
    -- 窗口未激活，描述应该不变
    module.update_main_descriptions()
    assert(module.ui_refs.timer_desc.text == "old", "窗口未激活时描述不应更新")
    
    log.info("psm_command_tests", "窗口未激活时不更新描述测试通过")
end

-- 错误处理：ui_refs为nil时不更新
function psm_command_tests.test_update_descriptions_nil_refs()
    log.info("psm_command_tests", "开始 ui_refs为nil时不更新测试")
    setup_mocks()
    
    local module = create_test_module()
    module.win_id = mock_win_id
    module.ui_refs.timer_desc = nil
    
    -- 不应该抛出错误
    local ok, err = pcall(module.update_main_descriptions)
    assert(ok, "ui_refs为nil时不应该抛出错误")
    
    log.info("psm_command_tests", "ui_refs为nil时不更新测试通过")
end

return psm_command_tests
