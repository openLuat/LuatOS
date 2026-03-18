--[[
@module     image_win
@summary    图片组件演示窗口
@version    1.1.0
@date       2026.03.17
@author     江访
@usage      本文件是图片组件的演示窗口，采用exwin窗口管理扩展库。
            展示图片的各种用法，通过消息机制打开和关闭。
            注意：需要确保图片文件存在于设备中。
]]

-- 窗口ID
local win_id = nil

-- 窗口UI元素
local main_container   = nil
local scroll_container = nil


-- 辅助函数：创建带标题的容器

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
        font_size = 14,
    })

    return container
end


-- 辅助函数：创建控制面板

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
        font_size = 12,
    })

    return panel
end


-- 创建UI
local function create_ui()
    main_container = airui.container({
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
        font_size = 16,
        color = 0xFFFFFF,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function(self)
            exwin.close(win_id)
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

    local current_y = 10

    ----
    -- 示例1: 基本图片显示
    ----
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
        font_size = 12,
    })

    local basic_image = airui.image({
        parent = demo1_container,
        x = 20,
        y = 60,
        w = 120,
        h = 100,
        src = "/luadb/test1.png",
        on_click = function(self)
            log.info("image", "基本图片被点击")
            local msg = airui.msgbox({
                text = "基本图片被点击",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label)
                    self:hide()
                end
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
        font_size = 12,
    })

    airui.label({
        parent = demo1_container,
        text = "格式: PNG",
        x = 150,
        y = 95,
        w = 140,
        h = 20,
        color = 0x333333,
        font_size = 12,
    })

    airui.label({
        parent = demo1_container,
        text = "支持点击事件",
        x = 150,
        y = 120,
        w = 140,
        h = 20,
        color = 0x333333,
        font_size = 12,
    })

    ----
    -- 示例2: 图片透明度控制
    ----
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
        font_size = 12,
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
            on_click = function(self)
                local opacity_value = btn_info.value
                png_image:set_opacity(opacity_value)
                opacity_label:set_text("当前: " .. opacity_value)
                local percent = math.floor((opacity_value / 255) * 100)
                log.info("image", "透明度设置为: " .. percent .. "%")
            end
        })
    end

    ----
    -- 示例3: 图片缩放控制
    ----
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
        font_size = 12,
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
            on_click = function(self)
                local zoom_value = btn_info.value
                zoom_image:set_zoom(zoom_value)
                local percent = math.floor((zoom_value / 256) * 100)
                zoom_label:set_text("当前: " .. percent .. "%")
                log.info("image", "缩放设置为: " .. percent .. "%")
            end
        })
    end

    ----
    -- 示例4: 图片切换演示
    ----
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
        font_size = 12,
    })

    local switch_btn = airui.button({
        parent = demo4_container,
        x = 150,
        y = 80,
        w = 100,
        h = 35,
        text = "切换图片",
        on_click = function(self)
            image_index = image_index % #image_paths + 1
            switch_image:set_src(image_paths[image_index])
            image_info_label:set_text("当前: " .. image_names[image_index])
            log.info("image", "切换到图片: " .. image_names[image_index])

            local msg = airui.msgbox({
                text = "已切换到: " .. image_names[image_index],
                buttons = { "确定" },
                timeout = 1000,
                on_action = function(self, label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    ----
    -- 示例5: 动态创建图片
    ----
    local demo5_container = create_demo_container(scroll_container, "示例5: 动态创建图片", 10, current_y, 300, 200)
    current_y = current_y + 200 + 10

    airui.label({
        parent = demo5_container,
        text = "动态创建和销毁图片",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        font_size = 12,
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
        on_click = function(self)
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
        on_click = function(self)
            for _, img in ipairs(dynamic_images) do
                img:destroy()
            end
            dynamic_images = {}
            log.info("image", "清除所有动态图片")
        end
    })

    ----
    -- 示例6: 图片旋转 (V1.1.0 新增)
    ----
    local demo6_container = create_demo_container(scroll_container, "示例6: 图片旋转", 10, current_y, 300, 220)
    current_y = current_y + 220 + 10

    airui.label({
        parent = demo6_container,
        text = "点击按钮旋转PNG图片（支持0.1度单位）",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })

    local rotate_image = airui.image({
        parent = demo6_container,
        x = 60,
        y = 60,
        w = 120,
        h = 120,
        src = "/luadb/test1.png",   -- 必须是PNG
        rotation = 900,                -- V1.1.0 旋转角度 (0.1度单位)
        pivot = {x=0.5, y=0.5},      -- 旋转中心
    })

    local rotation_label = airui.label({
        parent = demo6_container,
        text = "当前角度: 90°",
        x = 20,
        y = 170,
        w = 120,
        h = 20,
        color = 0x333333,
        font_size = 12,
    })

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "提示: 支持PNG透明度、缩放、旋转、点击事件等功能",
        x = 10,
        y = 450,
        w = 300,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })
end

-- 窗口创建回调
local function on_create()
    create_ui()
end

-- 窗口销毁回调
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    scroll_container = nil
    win_id = nil
    log.info("image_win", "窗口销毁")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("image_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("image_win", "窗口失去焦点")
end

-- 订阅打开图片窗口消息
sys.subscribe("OPEN_IMAGE_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("image_win", "窗口打开，ID:", win_id)
    end
end)