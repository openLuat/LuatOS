--[[
@module  win_page
@summary 窗口组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是窗口组件的演示页面，展示窗口的各种用法。
]]

local win_page = {}

-- 页面UI元素
local main_container = nil
local demo_windows = {}

-- 创建UI
function win_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 1024,
        h = 600,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = 0x009688,
    })

    airui.label({
        parent = title_bar,
        text = "窗口组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        size = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 70,
        w = 1024,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 使用两列网格布局
    local left_column_x = 20
    local right_column_x = 522
    local y_offset = 10
    local card_width = 480
    local card_height = 220
    local card_gap_y = 20

    -- 示例1: 基本窗口（左列）
    local card1 = airui.container({
        parent = scroll_container,
        x = left_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card1,
        text = "示例1: 基本窗口",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card1,
        text = "创建带标题和关闭按钮的基本窗口",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local basic_win_btn = airui.button({
        parent = card1,
        x = 150,
        y = 80,
        w = 180,
        h = 50,
        text = "打开基本窗口",
        size = 16,
        on_click = function()
            -- 清理之前的窗口
            for _, win in ipairs(demo_windows) do
                if win then win:close() end
            end
            demo_windows = {}
            
            local win = airui.win({
                parent = airui.screen,
                title = "基本窗口",
                x = 250,
                y = 150,
                w = 500,
                h = 350,
                close_btn = true,
                on_close = function(self)
                    log.info("win_page", "基本窗口已关闭")
                    -- 从列表中移除
                    for i, w in ipairs(demo_windows) do
                        if w == self then
                            table.remove(demo_windows, i)
                            break
                        end
                    end
                end
            })
            
            -- 添加到窗口列表
            table.insert(demo_windows, win)

            -- 添加窗口内容
            airui.label({
                parent = win,
                text = "这是一个基本窗口演示",
                x = 30,
                y = 30,
                w = 440,
                h = 40,
                size = 16,
            })

            airui.label({
                parent = win,
                text = "窗口支持移动、调整大小和关闭操作",
                x = 30,
                y = 80,
                w = 440,
                h = 30,
                size = 14,
            })

            -- 关闭按钮
            local close_btn = airui.button({
                parent = win,
                text = "关闭窗口",
                x = 180,
                y = 150,
                w = 140,
                h = 50,
                size = 16,
                on_click = function()
                    win:close()
                end
            })

            -- 更多内容
            airui.label({
                parent = win,
                text = "窗口特性:",
                x = 30,
                y = 220,
                w = 440,
                h = 25,
                size = 14,
            })

            local feature1 = airui.switch({
                parent = win,
                x = 30,
                y = 250,
                w = 60,
                h = 30,
                checked = true,
                on_change = function(state)
                    log.info("win_page", "特性1: " .. tostring(state))
                end
            })

            airui.label({
                parent = win,
                text = "可移动",
                x = 100,
                y = 255,
                w = 80,
                h = 20,
                size = 12,
            })

            local feature2 = airui.switch({
                parent = win,
                x = 190,
                y = 250,
                w = 60,
                h = 30,
                checked = true,
                on_change = function(state)
                    log.info("win_page", "特性2: " .. tostring(state))
                end
            })

            airui.label({
                parent = win,
                text = "可调整大小",
                x = 260,
                y = 255,
                w = 100,
                h = 20,
                size = 12,
            })

            local feature3 = airui.switch({
                parent = win,
                x = 370,
                y = 250,
                w = 60,
                h = 30,
                checked = false,
                on_change = function(state)
                    log.info("win_page", "特性3: " .. tostring(state))
                end
            })

            airui.label({
                parent = win,
                text = "置顶显示",
                x = 440,
                y = 255,
                w = 80,
                h = 20,
                size = 12,
            })
        end
    })

    -- 示例2: 模态窗口（右列）
    local card2 = airui.container({
        parent = scroll_container,
        x = right_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card2,
        text = "示例2: 模态窗口",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card2,
        text = "创建阻止背景交互的模态窗口",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local modal_win_btn = airui.button({
        parent = card2,
        x = 150,
        y = 80,
        w = 180,
        h = 50,
        text = "打开模态窗口",
        size = 16,
        on_click = function()
            -- 清理之前的窗口
            for _, win in ipairs(demo_windows) do
                if win then win:close() end
            end
            demo_windows = {}
            
            local win = airui.win({
                parent = airui.screen,
                title = "模态窗口",
                x = 300,
                y = 180,
                w = 400,
                h = 280,
                close_btn = true,
                modal = true,
                on_close = function(self)
                    log.info("win_page", "模态窗口已关闭")
                    for i, w in ipairs(demo_windows) do
                        if w == self then
                            table.remove(demo_windows, i)
                            break
                        end
                    end
                end
            })
            
            table.insert(demo_windows, win)

            airui.label({
                parent = win,
                text = "这是一个模态窗口",
                x = 30,
                y = 30,
                w = 340,
                h = 40,
                size = 16,
            })

            airui.label({
                parent = win,
                text = "模态窗口会阻止背景的交互操作",
                x = 30,
                y = 80,
                w = 340,
                h = 30,
                size = 14,
            })

            airui.label({
                parent = win,
                text = "请先关闭此窗口才能操作其他部分",
                x = 30,
                y = 120,
                w = 340,
                h = 30,
                size = 14,
            })

            local confirm_btn = airui.button({
                parent = win,
                text = "确认",
                x = 100,
                y = 170,
                w = 90,
                h = 45,
                size = 14,
                on_click = function()
                    win:close()
                end
            })

            local cancel_btn = airui.button({
                parent = win,
                text = "取消",
                x = 210,
                y = 170,
                w = 90,
                h = 45,
                size = 14,
                on_click = function()
                    win:close()
                end
            })
        end
    })

    y_offset = y_offset + card_height + card_gap_y

    -- 示例3: 多个窗口（左列）
    local card3 = airui.container({
        parent = scroll_container,
        x = left_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card3,
        text = "示例3: 多个窗口",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card3,
        text = "同时创建和管理多个窗口",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local multi_win_btn = airui.button({
        parent = card3,
        x = 50,
        y = 80,
        w = 180,
        h = 50,
        text = "窗口1",
        size = 16,
        on_click = function()
            local win = airui.win({
                parent = airui.screen,
                title = "窗口1",
                x = 100 + #demo_windows * 20,
                y = 100 + #demo_windows * 20,
                w = 350,
                h = 250,
                close_btn = true,
                on_close = function(self)
                    log.info("win_page", "窗口1已关闭")
                    for i, w in ipairs(demo_windows) do
                        if w == self then
                            table.remove(demo_windows, i)
                            break
                        end
                    end
                end
            })
            
            table.insert(demo_windows, win)

            airui.label({
                parent = win,
                text = "这是窗口1",
                x = 30,
                y = 30,
                w = 290,
                h = 40,
                size = 16,
            })

            airui.label({
                parent = win,
                text = "窗口ID: " .. #demo_windows,
                x = 30,
                y = 80,
                w = 290,
                h = 30,
                size = 14,
            })

            local close_btn = airui.button({
                parent = win,
                text = "关闭",
                x = 130,
                y = 130,
                w = 90,
                h = 45,
                size = 14,
                on_click = function()
                    win:close()
                end
            })
        end
    })

    local multi_win_btn2 = airui.button({
        parent = card3,
        x = 250,
        y = 80,
        w = 180,
        h = 50,
        text = "窗口2",
        size = 16,
        on_click = function()
            local win = airui.win({
                parent = airui.screen,
                title = "窗口2",
                x = 150 + #demo_windows * 20,
                y = 150 + #demo_windows * 20,
                w = 400,
                h = 300,
                close_btn = true,
                on_close = function(self)
                    log.info("win_page", "窗口2已关闭")
                    for i, w in ipairs(demo_windows) do
                        if w == self then
                            table.remove(demo_windows, i)
                            break
                        end
                    end
                end
            })
            
            table.insert(demo_windows, win)

            airui.label({
                parent = win,
                text = "这是窗口2",
                x = 30,
                y = 30,
                w = 340,
                h = 40,
                size = 16,
            })

            airui.label({
                parent = win,
                text = "支持更多内容显示",
                x = 30,
                y = 80,
                w = 340,
                h = 30,
                size = 14,
            })

            -- 添加一些控件
            local switch1 = airui.switch({
                parent = win,
                x = 30,
                y = 130,
                w = 60,
                h = 30,
                checked = true,
                on_change = function(state)
                    log.info("win_page", "窗口2开关1: " .. tostring(state))
                end
            })

            airui.label({
                parent = win,
                text = "选项1",
                x = 100,
                y = 135,
                w = 80,
                h = 20,
                size = 12,
            })

            local switch2 = airui.switch({
                parent = win,
                x = 30,
                y = 170,
                w = 60,
                h = 30,
                checked = false,
                on_change = function(state)
                    log.info("win_page", "窗口2开关2: " .. tostring(state))
                end
            })

            airui.label({
                parent = win,
                text = "选项2",
                x = 100,
                y = 175,
                w = 80,
                h = 20,
                size = 12,
            })

            local close_btn = airui.button({
                parent = win,
                text = "关闭窗口",
                x = 150,
                y = 220,
                w = 100,
                h = 45,
                size = 14,
                on_click = function()
                    win:close()
                end
            })
        end
    })

    -- 窗口管理按钮
    local close_all_btn = airui.button({
        parent = card3,
        x = 50,
        y = 150,
        w = 180,
        h = 45,
        text = "关闭所有窗口",
        size = 14,
        on_click = function()
            for _, win in ipairs(demo_windows) do
                if win then win:close() end
            end
            demo_windows = {}
            log.info("win_page", "已关闭所有窗口")
        end
    })

    local count_btn = airui.button({
        parent = card3,
        x = 250,
        y = 150,
        w = 180,
        h = 45,
        text = "统计窗口数",
        size = 14,
        on_click = function()
            local msg = airui.msgbox({
                text = "当前打开窗口数: " .. #demo_windows,
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    -- 示例4: 窗口控制（右列）
    local card4 = airui.container({
        parent = scroll_container,
        x = right_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card4,
        text = "示例4: 窗口控制",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card4,
        text = "动态控制窗口的位置和大小",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local control_win_btn = airui.button({
        parent = card4,
        x = 150,
        y = 80,
        w = 180,
        h = 50,
        text = "创建可控窗口",
        size = 16,
        on_click = function()
            -- 清理之前的窗口
            for _, win in ipairs(demo_windows) do
                if win then win:close() end
            end
            demo_windows = {}
            
            local win = airui.win({
                parent = airui.screen,
                title = "可控窗口",
                x = 300,
                y = 150,
                w = 400,
                h = 300,
                close_btn = true,
                on_close = function(self)
                    log.info("win_page", "可控窗口已关闭")
                    for i, w in ipairs(demo_windows) do
                        if w == self then
                            table.remove(demo_windows, i)
                            break
                        end
                    end
                end
            })
            
            table.insert(demo_windows, win)

            airui.label({
                parent = win,
                text = "可控窗口演示",
                x = 30,
                y = 30,
                w = 340,
                h = 40,
                size = 16,
            })

            airui.label({
                parent = win,
                text = "使用下方按钮控制窗口",
                x = 30,
                y = 80,
                w = 340,
                h = 30,
                size = 14,
            })

            -- 控制按钮
            local move_btn = airui.button({
                parent = win,
                text = "移动窗口",
                x = 30,
                y = 130,
                w = 100,
                h = 40,
                size = 12,
                on_click = function()
                    win:move(350, 200)
                    log.info("win_page", "窗口移动到(350, 200)")
                end
            })

            local resize_btn = airui.button({
                parent = win,
                text = "调整大小",
                x = 150,
                y = 130,
                w = 100,
                h = 40,
                size = 12,
                on_click = function()
                    win:resize(450, 350)
                    log.info("win_page", "窗口大小调整为450x350")
                end
            })

            local hide_btn = airui.button({
                parent = win,
                text = "隐藏窗口",
                x = 270,
                y = 130,
                w = 100,
                h = 40,
                size = 12,
                on_click = function()
                    win:hide()
                    log.info("win_page", "窗口已隐藏")
                end
            })

            local show_btn = airui.button({
                parent = win,
                text = "显示窗口",
                x = 30,
                y = 180,
                w = 100,
                h = 40,
                size = 12,
                on_click = function()
                    win:show()
                    log.info("win_page", "窗口已显示")
                end
            })

            local minimize_btn = airui.button({
                parent = win,
                text = "最小化",
                x = 150,
                y = 180,
                w = 100,
                h = 40,
                size = 12,
                on_click = function()
                    log.info("win_page", "最小化窗口")
                    -- 这里需要根据AirUI的API实现最小化功能
                end
            })

            local maximize_btn = airui.button({
                parent = win,
                text = "最大化",
                x = 270,
                y = 180,
                w = 100,
                h = 40,
                size = 12,
                on_click = function()
                    log.info("win_page", "最大化窗口")
                    -- 这里需要根据AirUI的API实现最大化功能
                end
            })
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 窗口支持移动、调整大小、模态显示和多窗口管理",
        x = 20,
        y = 560,
        w = 600,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function win_page.init(params)
    demo_windows = {}
    win_page.create_ui()
end

-- 清理页面
function win_page.cleanup()
    -- 清理所有打开的窗口
    for _, win in ipairs(demo_windows) do
        if win then win:close() end
    end
    demo_windows = {}
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return win_page