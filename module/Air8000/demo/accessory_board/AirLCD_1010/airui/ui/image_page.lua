--[[
@module     image_page
@summary    图片组件演示页面
@version    1.0.0
@date       2026.01.30
@author     江访
@usage      本文件是图片组件的演示页面，展示图片的各种用法。
            注意：需要确保图片文件存在于设备中。
]]

local image_page = {}

----------------------------------------------------------------
-- 页面UI元素
----------------------------------------------------------------
local main_container   = nil
local scroll_container = nil

----------------------------------------------------------------
-- 辅助函数：创建带标题的容器
----------------------------------------------------------------
local function create_demo_container(parent, title, x, y, width, height)
    local container = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = width,
        h = height,
        color = 0xFFFFFF,
        radius = 8,
    })

    airui.label({
        parent = container,
        text = title,
        x = 10,
        y = 5,
        w = width - 20,
        h = 25,
        color = 0x333333,
        size = 14,
    })

    return container
end

----------------------------------------------------------------
-- 辅助函数：创建控制面板
----------------------------------------------------------------
local function create_control_panel(parent, title, x, y, width, height)
    local panel = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = width,
        h = height,
        color = 0xF8F9FA,
        radius = 6,
    })

    airui.label({
        parent = panel,
        text = title,
        x = 8,
        y = 5,
        w = width - 16,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    return panel
end

----------------------------------------------------------------
-- 创建UI
----------------------------------------------------------------
function image_page.create_ui()
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
        color = 0x8BC34A,
    })

    airui.label({
        parent = title_bar,
        text = "图片组件演示",
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
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = 320,
        h = 430,
        color = 0xF5F5F5,
    })

    -- 当前y坐标位置
    local current_y = 10

    --------------------------------------------------------------------
    -- 示例1: 基本图片显示
    --------------------------------------------------------------------
    local demo1_container = create_demo_container(scroll_container, "示例1: 基本图片显示", 10, current_y, 300, 180)
    current_y = current_y + 180 + 10

    airui.label({
        parent = demo1_container,
        text = "显示静态图片，支持JPG和PNG格式",
        x = 10,
        y = 35,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local basic_image = airui.image({
        parent = demo1_container,
        x = 20,
        y = 60,
        w = 120,
        h = 100,
        src = "/luadb/test1.png",
        on_click = function()
            log.info("image", "基本图片被点击")
            local msg = airui.msgbox({
                text = "基本图片被点击",
                buttons = { "确定" },
                timeout = 1500
            })
            msg:show()
        end
    })

    airui.label({
        parent = demo1_container,
        text = "尺寸: 120x100",
        x = 150,
        y = 70,
        w = 140,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    airui.label({
        parent = demo1_container,
        text = "格式: PNG",
        x = 150,
        y = 95,
        w = 140,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    airui.label({
        parent = demo1_container,
        text = "支持点击事件",
        x = 150,
        y = 120,
        w = 140,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    --------------------------------------------------------------------
    -- 示例2: 图片透明度控制
    --------------------------------------------------------------------
    local demo2_container = create_demo_container(scroll_container, "示例2: 图片透明度控制", 10, current_y, 300, 200)
    current_y = current_y + 200 + 10

    local png_image = airui.image({
        parent = demo2_container,
        x = 20,
        y = 40,
        w = 100,
        h = 100,
        src = "/luadb/test2.png",
        zoom = 256,
        opacity = 255,
    })

    local opacity_panel = create_control_panel(demo2_container, "透明度控制", 130, 40, 160, 150)

    local opacity_label = airui.label({
        parent = opacity_panel,
        text = "当前: 255",
        x = 10,
        y = 25,
        w = 140,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    local opacity_buttons = {
        { text = "100%", value = 255 },
        { text = "75%",  value = 191 },
        { text = "50%",  value = 127 },
        { text = "25%",  value = 64 },
    }

    for i, btn_info in ipairs(opacity_buttons) do
        airui.button({
            parent = opacity_panel,
            x = 10 + ((i - 1) % 2) * 70,
            y = 50 + math.floor((i - 1) / 2) * 30,
            w = 60,
            h = 25,
            text = btn_info.text,
            on_click = function()
                local opacity_value = btn_info.value
                png_image:set_opacity(opacity_value)
                opacity_label:set_text("当前: " .. opacity_value)
                local percent = math.floor((opacity_value / 255) * 100)
                log.info("image", "透明度设置为: " .. percent .. "%")
            end
        })
    end

    --------------------------------------------------------------------
    -- 示例3: 图片缩放控制
    --------------------------------------------------------------------
    local demo3_container = create_demo_container(scroll_container, "示例3: 图片缩放控制", 10, current_y, 300, 200)
    current_y = current_y + 200 + 10

    local zoom_image = airui.image({
        parent = demo3_container,
        x = 20,
        y = 40,
        w = 120,
        h = 120,
        src = "/luadb/test1.png",
        zoom = 256,
    })

    local zoom_panel = create_control_panel(demo3_container, "缩放控制", 150, 40, 140, 150)

    local zoom_label = airui.label({
        parent = zoom_panel,
        text = "当前: 100%",
        x = 10,
        y = 25,
        w = 120,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    local zoom_buttons = {
        { text = "50%",  value = 128 },
        { text = "100%", value = 256 },
        { text = "150%", value = 384 },
        { text = "200%", value = 512 },
    }

    for i, btn_info in ipairs(zoom_buttons) do
        airui.button({
            parent = zoom_panel,
            x = 10 + ((i - 1) % 2) * 55,
            y = 50 + math.floor((i - 1) / 2) * 30,
            w = 50,
            h = 25,
            text = btn_info.text,
            on_click = function()
                local zoom_value = btn_info.value
                zoom_image:set_zoom(zoom_value)
                local percent = math.floor((zoom_value / 256) * 100)
                zoom_label:set_text("当前: " .. percent .. "%")
                log.info("image", "缩放设置为: " .. percent .. "%")
            end
        })
    end

    --------------------------------------------------------------------
    -- 示例4: 图片切换演示
    --------------------------------------------------------------------
    local demo4_container = create_demo_container(scroll_container, "示例4: 图片切换演示", 10, current_y, 300, 180)
    current_y = current_y + 180 + 10

    local image_index   = 1
    local image_paths   = { "/luadb/test1.png", "/luadb/test2.png" }
    local image_names   = { "测试图片1", "测试图片2" }

    local switch_image = airui.image({
        parent = demo4_container,
        x = 20,
        y = 40,
        w = 120,
        h = 100,
        src = image_paths[1],
    })

    local image_info_label = airui.label({
        parent = demo4_container,
        text = "当前: " .. image_names[1],
        x = 150,
        y = 50,
        w = 140,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    local switch_btn = airui.button({
        parent = demo4_container,
        x = 150,
        y = 80,
        w = 100,
        h = 35,
        text = "切换图片",
        on_click = function()
            image_index = image_index % #image_paths + 1
            switch_image:set_src(image_paths[image_index])
            image_info_label:set_text("当前: " .. image_names[image_index])
            log.info("image", "切换到图片: " .. image_names[image_index])

            local msg = airui.msgbox({
                text = "已切换到: " .. image_names[image_index],
                buttons = { "确定" },
                timeout = 1000
            })
            msg:show()
        end
    })

    --------------------------------------------------------------------
    -- 示例5: 动态创建图片
    --------------------------------------------------------------------
    local demo5_container = create_demo_container(scroll_container, "示例5: 动态创建图片", 10, current_y, 300, 200)

    airui.label({
        parent = demo5_container,
        text = "动态创建和销毁图片",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local dynamic_images = {}
    local img_positions = { {x = 20, y = 60}, {x = 90, y = 60}, {x = 160, y = 60} }

    airui.button({
        parent = demo5_container,
        x = 20,
        y = 130,
        w = 100,
        h = 35,
        text = "创建图片",
        on_click = function()
            local count = #dynamic_images + 1
            if count <= 3 then
                local pos = img_positions[count]
                local img = airui.image({
                    parent = demo5_container,
                    x = pos.x,
                    y = pos.y,
                    w = 50,
                    h = 50,
                    src = "/luadb/test1.png",
                })
                table.insert(dynamic_images, img)
                log.info("image", "创建第 " .. count .. " 张图片")
            end
        end
    })

    airui.button({
        parent = demo5_container,
        x = 170,
        y = 130,
        w = 100,
        h = 35,
        text = "清除图片",
        on_click = function()
            for _, img in ipairs(dynamic_images) do
                img:destroy()
            end
            dynamic_images = {}
            log.info("image", "清除所有动态图片")
        end
    })

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "提示: 支持PNG透明度、图片缩放、点击事件等功能",
        x = 10,
        y = 450,
        w = 300,
        h = 20,
        color = 0x666666,
        size = 12,
    })
end

----------------------------------------------------------------
-- 初始化页面
----------------------------------------------------------------
function image_page.init(params)
    image_page.create_ui()
end

----------------------------------------------------------------
-- 清理页面
----------------------------------------------------------------
function image_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container   = nil
        scroll_container = nil
    end
end

return image_page