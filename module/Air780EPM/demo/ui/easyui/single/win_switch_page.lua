--[[
@module  win_switch_page
@summary 页面切换演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为页面切换演示模块，核心业务逻辑为：
1、创建主页面窗口容器；
2、配置多个子页面工厂函数；
3、实现页面间切换导航功能；
4、演示消息框页面和复选框页面；
5、实现子页面销毁和内存管理；
6、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

-- 创建消息框演示页面
local function msgbox_page()

    local win = ui.window({ background_color = ui.COLOR_WHITE })

    -- 创建页面标题（使用无按钮的消息框）
    local title = ui.message_box({ 
        x = 10, y = 10,
        w = 300, h = 80,
        title = "Message Box Page",
        message = "Click button to show message box",
        buttons = {}  -- 空按钮数组，不显示按钮
    })

    -- 创建"弹出消息框"按钮
    local btn = ui.button({
        x = 20, y = 140,
        w = 180, h = 50,
        text = "Show Message Box",
        on_click = function()
            -- 创建消息框
            local box = ui.message_box({
                x = 40, y = 210,
                w = 240, h = 120,
                title = "Info",
                message = "This is a message",
                buttons = { "OK", "Cancel" },
                on_result = function()
                    -- 处理按钮点击逻辑
                end
            })
            ui.add(box)
        end
    })

    -- 创建"返回"按钮
    local back = ui.button({
        x = 220, y = 140,
        w = 80, h = 50,
        text = "Back",
        on_click = function()
            win:back()  -- 返回主页
        end
    })

    -- 添加组件到窗口
    win:add(title)
    win:add(btn)
    win:add(back)
    
    return win
end

-- 创建复选框演示页面
local function check_box_page()
    local win = ui.window({ background_color = ui.COLOR_WHITE })
    
    -- 创建页面标题
    local title = ui.message_box({ 
        x = 10, y = 10,
        w = 300, h = 80,
        title = "Check Box Page", 
        message = "Demonstrating multiple check_boxes", 
        buttons = {} 
    })
    
    -- 创建三个复选框
    local cb1 = ui.check_box({ x = 20, y = 120, text = "Option A" })
    local cb2 = ui.check_box({ x = 20, y = 160, text = "Option B", checked = true })
    local cb3 = ui.check_box({ x = 20, y = 200, text = "Option C" })
    
    -- 创建返回按钮
    local back = ui.button({
        x = 20, y = 260,
        w = 120, h = 40,
        text = "Back to Home",
        on_click = function()
            win:back()
        end
    })

    -- 添加组件到窗口
    win:add(title)
    win:add(cb1)
    win:add(cb2)
    win:add(cb3)
    win:add(back)
    
    return win
end

-- 主程序入口函数
local function ui_main()

    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建主页面
    local home = ui.window({ background_color = ui.COLOR_WHITE })

    -- 配置子页面工厂函数
    home:configure_subpages({ 
        page1 = msgbox_page,   -- 消息框演示页面
        page2 = check_box_page  -- 复选框演示页面
    })

    -- 创建导航按钮1：进入复选框示例页面
    local btn1 = ui.button({
        x = 20, y = 60,
        w = 280, h = 50,
        text = "Check Box Demo",
        on_click = function()
            home:show_subpage("page2")
        end
    })
    
    -- 创建导航按钮2：进入消息框示例页面  
    local btn2 = ui.button({
        x = 20, y = 130,
        w = 280, h = 50,
        text = "Message Box Demo",
        on_click = function()
            home:show_subpage("page1")
        end
    })

    -- 创建功能按钮：移除复选框子界面（演示销毁功能）
    local btnRemove = ui.button({
        x = 20, y = 200,
        w = 280, h = 50,
        text = "Remove Check Box Page",
        on_click = function()
            -- 强制销毁缓存的check_box子页面，释放内存
            home:close_subpage("page2", { destroy = true })
        end
    })

    -- 添加按钮到主页面
    home:add(btn1)
    home:add(btn2)
    home:add(btnRemove)

    -- 注册主页面到UI系统
    ui.add(home)

end

sys.taskInit(ui_main)