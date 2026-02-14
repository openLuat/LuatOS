--[[
@module     image_page
@summary    图片组件演示页面
@version    1.0.0
@date       2026.01.30
@author     江访
@usage      本文件是图片组件的演示页面，展示图片的各种用法。
            注意：需要确保图片文件存在于设备中。
]]

local image_page       = {}

----------------------------------------------------------------
-- 页面UI元素
----------------------------------------------------------------
local main_container   = nil
local scroll_container = nil

----------------------------------------------------------------
-- 辅助函数：创建带标题的卡片
----------------------------------------------------------------
local function create_demo_card(parent, title, x, y, width, height)
    local card = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = width,
        h = height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card,
        text = title,
        x = 15,
        y = 10,
        w = width - 30,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    return card
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
        radius = 8,
    })

    airui.label({
        parent = panel,
        text = title,
        x = 10,
        y = 8,
        w = width - 20,
        h = 25,
        color = 0x666666,
        size = 14,
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
        color = 0x8BC34A,
    })

    airui.label({
        parent = title_bar,
        text = "图片组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        color = 0xFFFFFF,
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
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 70,
        w = 1024,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 使用两列网格布局
    local card_width = 480
    local card_height = 200
    local card_gap_x = 30
    local card_gap_y = 20
    local current_y = 10

    --------------------------------------------------------------------
    -- 卡片1: 基本图片显示
    --------------------------------------------------------------------
    local card1 = create_demo_card(scroll_container, "示例1: 基本图片显示", 20, current_y, card_width, card_height)

    airui.label({
        parent = card1,
        text = "显示静态图片，支持JPG和PNG格式",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local basic_image = airui.image({
        parent = card1,
        x = 30,
        y = 80,
        w = 180,
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

    -- 图片信息
    airui.label({
        parent = card1,
        text = "尺寸: 180x100",
        x = 230,
        y = 85,
        w = 220,
        h = 25,
        color = 0x333333,
        size = 14,
    })

    airui.label({
        parent = card1,
        text = "格式: PNG",
        x = 230,
        y = 115,
        w = 220,
        h = 25,
        color = 0x333333,
        size = 14,
    })

    airui.label({
        parent = card1,
        text = "支持点击事件",
        x = 230,
        y = 145,
        w = 220,
        h = 25,
        color = 0x333333,
        size = 14,
    })

    --------------------------------------------------------------------
    -- 卡片2: 图片透明度控制
    --------------------------------------------------------------------
    local card2 = create_demo_card(scroll_container, "示例2: 图片透明度控制", 530, current_y, card_width, card_height)

    local png_image = airui.image({
        parent = card2,
        x = 30,
        y = 80,
        w = 150,
        h = 100,
        src = "/luadb/test2.png",
        zoom = 256,
        opacity = 255,
    })

    local opacity_panel = create_control_panel(card2, "透明度控制", 200, 30, 250, 140)

    local opacity_label = airui.label({
        parent = opacity_panel,
        text = "当前透明度: 100%",
        x = 15,
        y = 35,
        w = 220,
        h = 25,
        color = 0x333333,
        size = 14,
    })

    local opacity_buttons = {
        { text = "100%", value = 255, percent = 100 },
        { text = "75%",  value = 191, percent = 75 },
        { text = "50%",  value = 127, percent = 50 },
        { text = "25%",  value = 64,  percent = 25 },
    }

    for i, btn_info in ipairs(opacity_buttons) do
        airui.button({
            parent = opacity_panel,
            x = 15 + ((i - 1) % 2) * 110,
            y = 65 + math.floor((i - 1) / 2) * 35,
            w = 100,
            h = 30,
            text = btn_info.text,
            size = 14,
            on_click = function()
                local opacity_value = btn_info.value
                png_image:set_opacity(opacity_value)
                opacity_label:set_text("当前透明度: " .. btn_info.percent .. "%")
                log.info("image", "透明度设置为: " .. btn_info.percent .. "%")
            end
        })
    end

    current_y = current_y + card_height + card_gap_y

    --------------------------------------------------------------------
    -- 卡片3: 图片缩放控制
    --------------------------------------------------------------------
    local card3 = create_demo_card(scroll_container, "示例3: 图片缩放控制", 20, current_y, card_width, card_height)

    local zoom_image = airui.image({
        parent = card3,
        x = 30,
        y = 60,
        w = 150,
        h = 100,
        src = "/luadb/test1.png",
        zoom = 256,
    })

    local zoom_panel = create_control_panel(card3, "缩放控制", 200, 30, 250, 140)

    local zoom_label = airui.label({
        parent = zoom_panel,
        text = "当前缩放: 100%",
        x = 15,
        y = 35,
        w = 220,
        h = 25,
        color = 0x333333,
        size = 14,
    })

    local zoom_buttons = {
        { text = "50%",  value = 128, percent = 50 },
        { text = "100%", value = 256, percent = 100 },
        { text = "150%", value = 384, percent = 150 },
        { text = "200%", value = 512, percent = 200 },
    }

    for i, btn_info in ipairs(zoom_buttons) do
        airui.button({
            parent = zoom_panel,
            x = 15 + ((i - 1) % 2) * 110,
            y = 65 + math.floor((i - 1) / 2) * 35,
            w = 100,
            h = 30,
            text = btn_info.text,
            size = 14,
            on_click = function()
                local zoom_value = btn_info.value
                zoom_image:set_zoom(zoom_value)
                zoom_label:set_text("当前缩放: " .. btn_info.percent .. "%")
                log.info("image", "缩放设置为: " .. btn_info.percent .. "%")
            end
        })
    end

    --------------------------------------------------------------------
    -- 卡片4: 图片切换演示
    --------------------------------------------------------------------
    local card4            = create_demo_card(scroll_container, "示例4: 图片切换演示", 530, current_y, card_width, card_height)

    local image_index      = 1
    local image_paths      = { "/luadb/test1.png", "/luadb/test2.png" }
    local image_names      = { "测试图片1", "测试图片2" }

    local switch_image     = airui.image({
        parent = card4,
        x = 30,
        y = 60,
        w = 150,
        h = 100,
        src = image_paths[1],
    })

    local image_info_label = airui.label({
        parent = card4,
        text = "当前图片: " .. image_names[1],
        x = 200,
        y = 65,
        w = 250,
        h = 30,
        color = 0x333333,
        size = 14,
    })

    local switch_btn       = airui.button({
        parent = card4,
        x = 200,
        y = 105,
        w = 150,
        h = 45,
        text = "切换图片",
        size = 16,
        on_click = function()
            image_index = image_index % #image_paths + 1
            switch_image:set_src(image_paths[image_index])
            image_info_label:set_text("当前图片: " .. image_names[image_index])
            log.info("image", "切换到图片: " .. image_names[image_index])

            local msg = airui.msgbox({
                text = "已切换到: " .. image_names[image_index],
                buttons = { "确定" },
                timeout = 1000
            })
            msg:show()
        end
    })

    current_y = current_y + card_height + 20

    --------------------------------------------------------------------
    -- 卡片5: 动态创建图片
    --------------------------------------------------------------------
    local card5 = create_demo_card(scroll_container, "示例5: 动态创建图片", 20, current_y, card_width, card_height + 100)

    airui.label({
        parent = card5,
        text = "动态创建和销毁图片",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local dynamic_images = {}
    local img_positions = {
        { x = 30,  y = 80 },
        { x = 110, y = 80 },
        { x = 190, y = 80 },
        { x = 270, y = 80 },
        { x = 30,  y = 160 },
        { x = 110, y = 160 },
        { x = 190, y = 160 },
        { x = 270, y = 160 }
    }

    local create_btn = airui.button({
        parent = card5,
        x = 40,
        y = 240,
        w = 120,
        h = 45,
        text = "创建图片",
        size = 14,
        on_click = function()
            local count = #dynamic_images + 1
            if count <= 8 then
                local pos = img_positions[count]
                local img = airui.image({
                    parent = card5,
                    x = pos.x,
                    y = pos.y,
                    w = 60,
                    h = 60,
                    src = "/luadb/test1.png",
                })
                table.insert(dynamic_images, img)
                log.info("image", "创建第 " .. count .. " 张图片")
            else
                local msg = airui.msgbox({
                    text = "最多只能创建8张图片",
                    buttons = { "确定" },
                    timeout = 1500
                })
                msg:show()
            end
        end
    })

    local clear_btn = airui.button({
        parent = card5,
        x = 200,
        y = 240,
        w = 120,
        h = 45,
        text = "清除图片",
        size = 14,
        on_click = function()
            for _, img in ipairs(dynamic_images) do
                img:destroy()
            end
            dynamic_images = {}
            log.info("image", "清除所有动态图片")
        end
    })

    --------------------------------------------------------------------
    -- 卡片6: 图片网格展示
    --------------------------------------------------------------------
    local card6 = create_demo_card(scroll_container, "示例6: 图片网格展示", 530, current_y, card_width, card_height + 100)

    airui.label({
        parent = card6,
        text = "可点击图标布局",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    -- 创建3x3图片网格
    local grid_images = {}
    for row = 0, 2 do
        for col = 0, 2 do
            local img = airui.image({
                parent = card6,
                x = 30 + col * 110,
                y = 80 + row * 70,
                w = 90,
                h = 60,
                src = "/luadb/test1.png",
                on_click = function()
                    log.info("image", "网格图片(" .. (row + 1) .. "," .. (col + 1) .. ")被点击")
                    local msg = airui.msgbox({
                        text = "点击了第" .. (row * 3 + col + 1) .. "个图片",
                        buttons = { "确定" },
                        timeout = 1500
                    })
                    msg:show()
                end
            })
            table.insert(grid_images, img)
        end
    end

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "提示: 支持PNG透明度、图片缩放、点击事件和动态管理",
        x = 20,
        y = 560,
        w = 600,
        h = 25,
        color = 0x666666,
        size = 14,
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
