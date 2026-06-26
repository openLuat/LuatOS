--[[
@module  win_switch_page
@summary 页面切换演示模块
@version 1.0.0
@date    2025.12.9
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

    -- 创建页面标题
    local title = ui.label({ 
        x = 250, y = 30,
        w = 300, h = 60,
        text = "消息框页面",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 创建"弹出消息框"按钮
    local btn = ui.button({
        x = 300, y = 150,
        w = 200, h = 60,
        text = "弹出消息框",
        size = 18,
        on_click = function()
            -- 创建消息框
            local box = ui.message_box({
                x = 200, y = 150,
                w = 400, h = 180,
                title = "提示",
                message = "这是一条演示消息\n点击按钮查看效果",
                buttons = { "确定", "取消" },
                on_result = function(result)
                    log.info("message_box", "用户点击了:", result)
                end
            })
            ui.add(box)
        end
    })

    -- 创建"返回"按钮
    local back = ui.button({
        x = 300, y = 250,
        w = 200, h = 60,
        text = "返回主页",
        size = 18,
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
    local title = ui.label({ 
        x = 250, y = 30,
        w = 300, h = 60,
        text = "复选框页面", 
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    -- 创建三个复选框
    local cb1 = ui.check_box({ x = 300, y = 120, text = "选项A", size = 18 })
    local cb2 = ui.check_box({ x = 300, y = 180, text = "选项B", checked = true, size = 18 })
    local cb3 = ui.check_box({ x = 300, y = 240, text = "选项C", size = 18 })
    local cb4 = ui.check_box({ x = 300, y = 300, text = "选项D", size = 18 })
    
    -- 创建返回按钮
    local back = ui.button({
        x = 300, y = 380,
        w = 200, h = 60,
        text = "返回主页",
        size = 18,
        on_click = function()
            win:back()
        end
    })

    -- 添加组件到窗口
    win:add(title)
    win:add(cb1)
    win:add(cb2)
    win:add(cb3)
    win:add(cb4)
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

    -- 添加主页面标题
    local main_title = ui.label({
        x = 250, y = 30,
        text = "页面切换演示",
        color = ui.COLOR_BLACK,
        size = 24
    })
    home:add(main_title)

    -- 创建导航按钮1：进入复选框示例页面
    local btn1 = ui.button({
        x = 300, y = 100,
        w = 200, h = 60,
        text = "复选框示例",
        size = 18,
        on_click = function()
            home:show_subpage("page2")
        end
    })
    
    -- 创建导航按钮2：进入消息框示例页面  
    local btn2 = ui.button({
        x = 300, y = 180,
        w = 200, h = 60,
        text = "消息框示例",
        size = 18,
        on_click = function()
            home:show_subpage("page1")
        end
    })

    -- 创建功能按钮：移除复选框子界面（演示销毁功能）
    local btnRemove = ui.button({
        x = 300, y = 260,
        w = 200, h = 60,
        text = "移除复选框页面",
        size = 18,
        bg_color = ui.COLOR_RED,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            -- 强制销毁缓存的check_box子页面，释放内存
            home:close_subpage("page2", { destroy = true })
        end
    })

    -- 添加提示标签
    local hint = ui.label({
        x = 250, y = 350,
        text = "点击按钮切换不同页面",
        color = ui.COLOR_GRAY,
        size = 16
    })
    home:add(hint)

    -- 添加按钮到主页面
    home:add(btn1)
    home:add(btn2)
    home:add(btnRemove)

    -- 注册主页面到UI系统
    ui.add(home)

end

sys.taskInit(ui_main)