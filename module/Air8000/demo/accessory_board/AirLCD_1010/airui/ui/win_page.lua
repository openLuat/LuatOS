--[[
@module     win_page
@summary    窗口组件演示页面
@version    1.0.0
@date       2026.01.30
@author     江访
@usage      本文件是窗口组件的演示页面，展示窗口的各种用法。
]]

local win_page = {}

----------------------------------------------------------------
-- 页面UI元素
----------------------------------------------------------------
local main_container = nil
local current_window = nil

-- 开关状态
local switch_states = {
    show_title = true,      -- 显示标题开关
    change_style = false,   -- 更改窗口样式开关
    add_components = false, -- 增加组件开关
    add_cancel_btn = false, -- 增加取消按钮开关
    add_multi_level = false -- 增加多级按钮开关
}

-- 开关组件引用
local title_switch = nil
local style_switch = nil
local components_switch = nil
local cancel_switch = nil
local multi_switch = nil

----------------------------------------------------------------
-- 创建基本窗口
----------------------------------------------------------------
local function create_basic_window()
    -- 如果已有窗口，先关闭
    if current_window then
        current_window:close()
    end

    -- 根据开关状态计算窗口高度
    local window_height = 280 -- 基础高度

    if switch_states.add_components then
        window_height = window_height + 40
    end

    if switch_states.add_multi_level then
        window_height = window_height + 40
    end

    -- 基础窗口配置
    local window_config = {
        parent = main_container,
        x = 40,
        y = 100,
        w = 240,
        h = window_height,
        close_btn = true,
        auto_center = false,
        on_close = function()
            log.info("win", "窗口被关闭")
            current_window = nil
        end
    }

    -- 根据开关状态调整配置
    if switch_states.show_title then
        window_config.title = "基本窗口"
    else
        window_config.title = "" -- 空标题
    end

    if switch_states.change_style then
        window_config.style = { radius = 10, border_width = 2 }
    end

    -- 创建窗口
    current_window = airui.win(window_config)

    -- 添加内容
    local content_y = 20
    local content_label = airui.label({
        text = "这是一个基本窗口",
        x = 20,
        y = content_y,
        w = 160,
        h = 30,
        color = 0x333333,
        size = 14,
    })
    current_window:add_content(content_label)

    content_y = content_y + 40

    -- 根据开关状态添加额外组件
    if switch_states.add_components then
        -- 添加开关组件
        local sample_switch = airui.switch({
            x = 20,
            y = content_y,
            w = 60,
            h = 30,
            checked = true,
            on_change = function(state)
                log.info("win", "窗口内开关: " .. tostring(state))
            end
        })
        current_window:add_content(sample_switch)

        current_window:add_content(airui.label({
            text = "示例开关",
            x = 90,
            y = content_y + 5,
            w = 80,
            h = 20,
            color = 0x333333,
            size = 12,
        }))

        content_y = content_y + 40
    end

    if switch_states.add_multi_level then
        -- 添加多级按钮
        local multi_btn = airui.button({
            text = "点击提示",
            x = 60,
            y = content_y,
            w = 80,
            h = 40,
            on_click = function()
                local msg = airui.msgbox({
                    text = "这是二级提示消息",
                    buttons = { "确定" },
                    timeout = 2000,
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                msg:show()
                log.info("win", "多级按钮被点击")
            end
        })
        current_window:add_content(multi_btn)

        content_y = content_y + 40
    end

    -- 按钮始终在窗口底部
    local button_y = window_height - 160

    if switch_states.add_cancel_btn then
        -- 添加确定和取消按钮
        local ok_btn = airui.button({
            text = "确定",
            x = 20,
            y = button_y,
            w = 80,
            h = 40,
            on_click = function()
                -- 弹出提示消息
                local msg = airui.msgbox({
                    text = "点击了确定按钮",
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                msg:show()
                log.info("win", "确定按钮被点击")
                current_window:close()
            end
        })
        current_window:add_content(ok_btn)

        -- 添加取消按钮
        local cancel_btn = airui.button({
            text = "取消",
            x = 110,
            y = button_y,
            w = 80,
            h = 40,
            on_click = function()
                -- 弹出提示消息
                local msg = airui.msgbox({
                    text = "点击了取消按钮",
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                msg:show()
                log.info("win", "取消按钮被点击")
                current_window:close()
            end
        })
        current_window:add_content(cancel_btn)
    else
        -- 只添加确定按钮
        local ok_btn = airui.button({
            text = "确定",
            x = 60,
            y = button_y,
            w = 80,
            h = 40,
            on_click = function()
                -- 弹出提示消息
                local msg = airui.msgbox({
                    text = "点击了确定按钮",
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                msg:show()
                log.info("win", "确定按钮被点击")
                current_window:close()
            end
        })
        current_window:add_content(ok_btn)
    end
end

----------------------------------------------------------------
-- 创建UI
----------------------------------------------------------------
function win_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0x009688,
    })

    airui.label({
        parent = title_bar,
        text = "窗口组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        color = 0xFFFFFF,
        size = 16,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function()
            go_back()
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 370,
        color = 0xF5F5F5,
    })

    -- 当前y坐标
    local current_y = 10

    -- 说明标签
    airui.label({
        parent = scroll_container,
        text = "开关控制窗口特性",
        x = 10,
        y = current_y,
        w = 300,
        h = 25,
        color = 0x333333,
        size = 14,
    })
    current_y = current_y + 30

    --------------------------------------------------------------------
    -- 开关控制区域
    --------------------------------------------------------------------
    -- 1. 显示标题开关
    airui.label({
        parent = scroll_container,
        text = "显示标题:",
        x = 20,
        y = current_y,
        w = 100,
        h = 30,
        color = 0x333333,
        size = 12,
    })

    title_switch = airui.switch({
        parent = scroll_container,
        x = 120,
        y = current_y,
        w = 60,
        h = 30,
        checked = switch_states.show_title,
        on_change = function(state)
            switch_states.show_title = state
            log.info("win", "显示标题开关: " .. tostring(state))
        end
    })
    current_y = current_y + 40

    -- 2. 更改窗口样式开关
    airui.label({
        parent = scroll_container,
        text = "更改窗口样式:",
        x = 20,
        y = current_y,
        w = 100,
        h = 30,
        color = 0x333333,
        size = 12,
    })

    style_switch = airui.switch({
        parent = scroll_container,
        x = 120,
        y = current_y,
        w = 60,
        h = 30,
        checked = switch_states.change_style,
        on_change = function(state)
            switch_states.change_style = state
            log.info("win", "更改窗口样式开关: " .. tostring(state))
        end
    })
    current_y = current_y + 40

    -- 3. 增加组件开关
    airui.label({
        parent = scroll_container,
        text = "增加组件:",
        x = 20,
        y = current_y,
        w = 100,
        h = 30,
        color = 0x333333,
        size = 12,
    })

    components_switch = airui.switch({
        parent = scroll_container,
        x = 120,
        y = current_y,
        w = 60,
        h = 30,
        checked = switch_states.add_components,
        on_change = function(state)
            switch_states.add_components = state
            log.info("win", "增加组件开关: " .. tostring(state))
        end
    })
    current_y = current_y + 40

    -- 4. 增加取消按钮开关
    airui.label({
        parent = scroll_container,
        text = "增加取消按钮:",
        x = 20,
        y = current_y,
        w = 100,
        h = 30,
        color = 0x333333,
        size = 12,
    })

    cancel_switch = airui.switch({
        parent = scroll_container,
        x = 120,
        y = current_y,
        w = 60,
        h = 30,
        checked = switch_states.add_cancel_btn,
        on_change = function(state)
            switch_states.add_cancel_btn = state
            log.info("win", "增加取消按钮开关: " .. tostring(state))
        end
    })
    current_y = current_y + 40

    -- 5. 增加多级按钮开关
    airui.label({
        parent = scroll_container,
        text = "增加多级按钮:",
        x = 20,
        y = current_y,
        w = 100,
        h = 30,
        color = 0x333333,
        size = 12,
    })

    multi_switch = airui.switch({
        parent = scroll_container,
        x = 120,
        y = current_y,
        w = 60,
        h = 30,
        checked = switch_states.add_multi_level,
        on_change = function(state)
            switch_states.add_multi_level = state
            log.info("win", "增加多级按钮开关: " .. tostring(state))
        end
    })
    current_y = current_y + 50

    --------------------------------------------------------------------
    -- 控制按钮
    --------------------------------------------------------------------
    -- 显示窗口按钮
    local show_window_btn = airui.button({
        parent = scroll_container,
        x = 40,
        y = current_y,
        w = 240,
        h = 50,
        text = "显示窗口",
        on_click = function()
            create_basic_window()
        end
    })
    current_y = current_y + 70

    -- 关闭窗口按钮
    local close_window_btn = airui.button({
        parent = scroll_container,
        x = 40,
        y = current_y,
        w = 100,
        h = 50,
        text = "关闭窗口",
        on_click = function()
            if current_window then
                current_window:close()
                current_window = nil
            else
                local msg = airui.msgbox({
                    text = "没有打开的窗口",
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                msg:show()
            end
        end
    })

    -- 重置开关按钮
    local reset_btn = airui.button({
        parent = scroll_container,
        x = 180,
        y = current_y,
        w = 100,
        h = 50,
        text = "重置所有开关",
        on_click = function()
            -- 重置开关状态
            switch_states = {
                show_title = true,
                change_style = false,
                add_components = false,
                add_cancel_btn = false,
                add_multi_level = false
            }
            -- 更新开关显示，目前V1.0.0 此处会死机，待更新AirUI 版本
            -- title_switch:set_state(switch_states.show_title)
            -- style_switch:set_state(switch_states.change_style)
            -- components_switch:set_state(switch_states.add_components)
            -- cancel_switch:set_state(switch_states.add_cancel_btn)
            -- multi_switch:set_state(switch_states.add_multi_level)
            local msg = airui.msgbox({
                text = "所有开关已重置",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label)
                    log.info("win", "所有开关已重置")
                    self:hide()
                end
            })
            msg:show()
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 使用开关控制窗口特性",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        color = 0x666666,
        size = 12,
    })
end

----------------------------------------------------------------
-- 初始化页面
----------------------------------------------------------------
function win_page.init(params)
    win_page.create_ui()
end

----------------------------------------------------------------
-- 清理页面
----------------------------------------------------------------
function win_page.cleanup()
    if current_window then
        current_window:close()
        current_window = nil
    end

    if main_container then
        main_container:destroy()
        main_container = nil
    end

    -- 清空开关引用
    title_switch = nil
    style_switch = nil
    components_switch = nil
    cancel_switch = nil
    multi_switch = nil
end

return win_page