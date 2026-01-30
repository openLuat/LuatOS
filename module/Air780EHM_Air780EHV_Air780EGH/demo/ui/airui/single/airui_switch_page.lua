--[[
@module switch_page_demo
@summary 页面切换功能演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示如何使用容器组件实现多页面切换功能。
]]

local current_page = 1
local total_pages = 3
local pages = {}

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 加载中文字体
    airui.font_load({
        type = "hzfont",
        path = nil,
        size = 14, -- 减小字体以适应竖屏
        cache_size = 2048,
        antialias = 4,
    })

    -- 创建主容器（竖屏尺寸）
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 320, -- 改为320
        h = 480, -- 保持480
        color = 0xF8F9FA,
    })

    -- 创建标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320, -- 改为320
        h = 60,  -- 缩小高度
        color = 0x007AFF,
    })

    local title_label = airui.label({
        parent = title_bar,
        text = "页面切换演示",
        x = 10,
        y = 15,
        w = 200,
        h = 30,
    })

    local page_indicator = airui.label({
        parent = title_bar,
        text = "第1页/共3页",
        x = 220,
        y = 15,
        w = 90,
        h = 30,
    })

    -- 创建内容区域
    local content_area = airui.container({
        parent = main_container,
        x = 10,     -- 左边距
        y = 70,     -- 标题栏下方
        w = 300,    -- 改为300
        h = 300,    -- 减小高度，为导航栏留空间
        color = 0xFFFFFF,
        radius = 8, -- 圆角
    })

    -- 创建三个页面
    for i = 1, total_pages do
        pages[i] = airui.container({
            parent = content_area,
            x = 0,
            y = 0,
            w = 300, -- 改为300
            h = 300,
            color = 0xFFFFFF,
        })

        -- 设置页面初始状态（只显示第一个页面）
        if i ~= 1 then
            pages[i]:set_hidden(true)
        end

        -- 为每个页面添加不同的内容
        if i == 1 then
            -- 第一页：欢迎页面
            local welcome_label = airui.label({
                parent = pages[i],
                text = "欢迎使用页面切换演示",
                x = 0,
                y = 40,
                w = 300,
                h = 40,
            })

            local desc_label = airui.label({
                parent = pages[i],
                text = "这是一个演示多页面切换功能的示例\n使用容器组件实现页面切换\n点击下方按钮切换页面",
                x = 0,
                y = 100,
                w = 300,
                h = 80,
            })
        elseif i == 2 then
            -- 第二页：设置页面
            airui.label({
                parent = pages[i],
                text = "设置页面",
                x = 0,
                y = 20,
                w = 300,
                h = 30,
            })

            -- 设置项目1 - 开关
            local setting1_container = airui.container({
                parent = pages[i],
                x = 20,
                y = 60,
                w = 260,
                h = 40,
                color = 0xFFFFFF,
            })

            airui.label({
                parent = setting1_container,
                text = "开关设置",
                x = 0,
                y = 10,
                w = 120,
                h = 30,
            })

            local switch1 = airui.switch({
                parent = setting1_container,
                x = 130,
                y = 5,
                w = 60,
                h = 30,
                checked = true,
                on_change = function()
                    log.info("page2", "开关1状态改变")
                end
            })

            -- 设置项目2 - 进度条
            local setting2_container = airui.container({
                parent = pages[i],
                x = 20,
                y = 110,
                w = 260,
                h = 50,
                color = 0xFFFFFF,
            })

            airui.label({
                parent = setting2_container,
                text = "亮度调节",
                x = 0,
                y = 15,
                w = 120,
                h = 30,
            })

            local brightness_bar = airui.bar({
                parent = setting2_container,
                x = 130,
                y = 15,
                w = 120,
                h = 20,
                value = 75,
                indicator_color = 0xFF9800,
            })

            -- 设置项目3 - 下拉框
            local setting3_container = airui.container({
                parent = pages[i],
                x = 20,
                y = 170,
                w = 260,
                h = 60,
                color = 0xFFFFFF,
            })

            airui.label({
                parent = setting3_container,
                text = "模式选择",
                x = 0,
                y = 20,
                w = 120,
                h = 30,
            })

            local mode_dropdown = airui.dropdown({
                parent = setting3_container,
                x = 130,
                y = 15,
                w = 120,
                h = 40,
                options = { "自动模式", "手动模式", "节能模式" },
                default_index = 0,
            })
        elseif i == 3 then
            -- 第三页：数据页面
            airui.label({
                parent = pages[i],
                text = "数据展示",
                x = 0,
                y = 20,
                w = 300,
                h = 30,
            })

            -- 创建数据表格（适配竖屏）
            local data_table = airui.table({
                parent = pages[i],
                x = 10,
                y = 60,
                w = 280, -- 减小宽度
                h = 220,
                rows = 5,
                cols = 4,
                col_width = { 70, 70, 70, 70 },
                border_color = 0xCCCCCC
            })

            -- 设置表头
            data_table:set_cell_text(0, 0, "设备")
            data_table:set_cell_text(0, 1, "温度")
            data_table:set_cell_text(0, 2, "湿度")
            data_table:set_cell_text(0, 3, "状态")

            -- 设置数据
            data_table:set_cell_text(1, 0, "传感器1")
            data_table:set_cell_text(1, 1, "25°C")
            data_table:set_cell_text(1, 2, "65%")
            data_table:set_cell_text(1, 3, "正常")

            data_table:set_cell_text(2, 0, "传感器2")
            data_table:set_cell_text(2, 1, "28°C")
            data_table:set_cell_text(2, 2, "70%")
            data_table:set_cell_text(2, 3, "正常")

            data_table:set_cell_text(3, 0, "传感器3")
            data_table:set_cell_text(3, 1, "22°C")
            data_table:set_cell_text(3, 2, "60%")
            data_table:set_cell_text(3, 3, "正常")

            data_table:set_cell_text(4, 0, "传感器4")
            data_table:set_cell_text(4, 1, "30°C")
            data_table:set_cell_text(4, 2, "75%")
            data_table:set_cell_text(4, 3, "警告")
        end
    end

    -- 创建底部导航栏
    local nav_bar = airui.container({
        parent = main_container,
        x = 10,
        y = 380, -- 调整位置
        w = 300,
        h = 90,  -- 增加高度以适应竖屏按钮排列
        color = 0xFFFFFF,
    })

    -- 创建导航按钮容器
    local btn_container = airui.container({
        parent = nav_bar,
        x = 0,
        y = 0,
        w = 300,
        h = 90,
        color = 0xFFFFFF,
    })

    -- 创建上一页和下一页按钮（横向排列）
    local prev_next_container = airui.container({
        parent = btn_container,
        x = 0,
        y = 0,
        w = 300,
        h = 40,
        color = 0xFFFFFF,
    })

    local prev_btn = airui.button({
        parent = prev_next_container,
        x = 0,
        y = 0,
        w = 140,
        h = 40,
        text = "上一页",
        on_click = function()
            if current_page > 1 then
                -- 隐藏当前页面
                pages[current_page]:set_hidden(true)
                current_page = current_page - 1
                -- 显示新页面
                pages[current_page]:set_hidden(false)
                page_indicator:set_text("第" .. current_page .. "页/共3页")
                log.info("page_switch", "切换到第 " .. current_page .. " 页")
            end
        end
    })

    local next_btn = airui.button({
        parent = prev_next_container,
        x = 160,
        y = 0,
        w = 140,
        h = 40,
        text = "下一页",
        on_click = function()
            if current_page < total_pages then
                -- 隐藏当前页面
                pages[current_page]:set_hidden(true)
                current_page = current_page + 1
                -- 显示新页面
                pages[current_page]:set_hidden(false)
                page_indicator:set_text("第" .. current_page .. "页/共3页")
                log.info("page_switch", "切换到第 " .. current_page .. " 页")
            end
        end
    })

    -- 创建页面快速跳转按钮（横向排列）
    local page_btn_container = airui.container({
        parent = btn_container,
        x = 0,
        y = 50,
        w = 300,
        h = 40,
        color = 0xFFFFFF,
    })

    local page_btn_x = 0
    for i = 1, total_pages do
        local btn_text = "第" .. i .. "页"
        local btn_width = 90 -- 每个按钮宽度

        local page_btn = airui.button({
            parent = page_btn_container,
            x = page_btn_x,
            y = 0,
            w = btn_width,
            h = 40,
            text = btn_text,
            on_click = function()
                -- 隐藏所有页面
                for j = 1, total_pages do
                    pages[j]:set_hidden(true)
                end
                -- 显示选中的页面
                current_page = i
                pages[current_page]:set_hidden(false)
                page_indicator:set_text("第" .. current_page .. "页/共3页")
                log.info("page_switch", "跳转到第 " .. current_page .. " 页")
            end
        })
        page_btn_x = page_btn_x + btn_width + 10 -- 按钮间距
    end

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)
