--[[
@module component_page
@summary exEasyUI组件演示页面模块（480×854竖屏适配版）
@version 1.1
@date 2026.01.26
@author 江访
@usage
本文件为组件演示页面功能模块，已适配480×854竖屏分辨率：
1、创建带上下滚动功能的演示窗口；
2、展示进度条、按钮、复选框、图片轮播等UI组件；
3、演示组件的交互功能和事件处理；
4、提供返回主页的导航功能；

本文件的对外接口有1个：
1、component_page.create()：创建组件演示页面；
]]

local component_page = {}

--[[
创建组件演示页面；

@api component_page.create()
@summary 创建组件演示页面界面
@table ui UI库对象
@return table 组件演示窗口对象

@usage
-- 在子页面工厂中调用创建组件演示页面
local component_page = require("component_page").create()
]]

function component_page.create()
    local win = ui.window({
        background_color = ui.COLOR_WHITE,
        x = 0,
        y = 0,
        w = 480,
        h = 854
    })

    -- 标题（居中显示）
    local title = ui.label({
        x = 160,
        y = 40,
        text = "组件演示",
        color = ui.COLOR_BLACK,
        size = 32
    })

    -- 返回按钮（左上角）
    local btn_back = ui.button({
        x = 20,
        y = 30,
        w = 80,
        h = 50,
        text = "返回",
        text_size = 18,
        on_click = function()
            win:back()
        end
    })

    -- ==================== 1. 进度条组件演示 ====================
    local progress_label = ui.label({
        x = 40,
        y = 100,
        text = "1. 进度条组件:",
        color = ui.COLOR_BLACK,
        size = 24
    })

    local progress_value = 0
    local progress_bar = ui.progress_bar({
        x = 40,
        y = 140,
        w = 320,
        h = 40,
        progress = progress_value,
        show_text = true,
        text = "进度: 0%"
    })

    local btn_progress = ui.button({
        x = 380,
        y = 140,
        w = 70,
        h = 40,
        text = "+10%",
        text_size = 16,
        on_click = function()
            progress_value = progress_value + 10
            if progress_value > 100 then
                progress_value = 0
            end
            progress_bar:set_progress(progress_value)
            progress_bar:set_text("进度: " .. progress_value .. "%")
        end
    })

    -- ==================== 2. 复选框组件演示 ====================
    local checkbox_label = ui.label({
        x = 40,
        y = 210,
        text = "2. 复选框组件:",
        color = ui.COLOR_BLACK,
        size = 24
    })

    local checkbox1 = ui.check_box({
        x = 40,
        y = 250,
        text = "选项A",
        text_size = 20,
        checked = false,
        on_change = function(checked)
            log.info("component_page", "选项A:", checked)
        end
    })

    local checkbox2 = ui.check_box({
        x = 200,
        y = 250,
        text = "选项B",
        text_size = 20,
        checked = true,
        on_change = function(checked)
            log.info("component_page", "选项B:", checked)
        end
    })

    -- ==================== 3. 图片轮播组件演示 ====================
    local picture_label = ui.label({
        x = 40,
        y = 320,
        text = "3. 图片轮播组件:",
        color = ui.COLOR_BLACK,
        size = 24
    })

    local picture = ui.picture({
        x = 176,
        y = 360,
        w = 128,
        h = 128,
        sources = { "/luadb/1.jpg", "/luadb/2.jpg", "/luadb/3.jpg" },
        autoplay = true,
        interval = 2000
    })

    local btn_next = ui.button({
        x = 180,
        y = 520,
        w = 120,
        h = 45,
        text = "下一张",
        text_size = 18,
        on_click = function()
            picture:next()
        end
    })

    -- ==================== 4. 按钮组件演示 ====================
    local button_label = ui.label({
        x = 40,
        y = 620,
        text = "4. 按钮组件:",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 普通按钮
    local normal_btn = ui.button({
        x = 40,
        y = 670,
        w = 120,
        h = 55,
        text = "普通按钮",
        text_size = 18,
        on_click = function()
            log.info("component_page", "普通按钮被点击")
            -- 显示提示
            local hint = ui.label({
                x = 180,
                y = 670,
                text = "已点击",
                color = ui.COLOR_GREEN,
                size = 18
            })
            win:add(hint)
            sys.timerStart(function()
                win:remove(hint)
            end, 1000)
        end
    })

    -- 带颜色的按钮
    local colored_btn = ui.button({
        x = 180,
        y = 670,
        w = 120,
        h = 55,
        text = "蓝色按钮",
        text_size = 18,
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            log.info("component_page", "蓝色按钮被点击")
        end
    })

     -- 图片按钮
    local image_btn = ui.button({
        x = 320,
        y = 670,
        w = 120,
        h = 55,
        src = "/luadb/4.jpg",
        src_toggled = "/luadb/5.jpg",
        toggle = true,
        on_click = function()
            log.info("component_page", "Image button clicked")
        end
    })

    -- 按键操作提示
    local key_tip = ui.label({
        x = 80,
        y = 780,
        text = "上拉: GPIO33切换焦点，GPIO34确认",
        color = ui.COLOR_GRAY,
        size = 16
    })

    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(progress_label)
    win:add(progress_bar)
    win:add(btn_progress)
    win:add(checkbox_label)
    win:add(checkbox1)
    win:add(checkbox2)
    win:add(picture_label)
    win:add(picture)
    win:add(btn_next)
    win:add(button_label)
    win:add(normal_btn)
    win:add(colored_btn)
    win:add(image_btn)
    win:add(key_tip)

    return win
end

return component_page
