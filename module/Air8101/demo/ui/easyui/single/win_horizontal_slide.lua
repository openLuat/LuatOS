--[[
@module  win_horizontal_slide
@summary 横向滑动页面演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为横向滑动页面演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、启用横向滑动功能；
3、创建两页内容并水平排列；
4、实现横向滑动切换页面效果；
5、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local function ui_main()

    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local win = ui.window({ background_color = ui.COLOR_WHITE })

    -- 启用横向滚动，将两页内容并排布置
    local page_w, page_h = lcd.getSize()
    local totalW = page_w * 2

    -- 创建横向滑动窗口
    win:enable_scroll({ 
        direction = "horizontal", 
        content_width = totalW, 
        threshold = 8, 
        page_width = page_w 
    })

    -- 创建网格按钮函数
    local function makeGrid(offset_x, label_prefix)
        local cols, rows = 3, 4
        local bw, bh = 200, 80
        local mx, my = (page_w - cols * bw - (cols-1) * 20) / 2 + offset_x, 80
        local gapx, gapy = 20, 20
        local n = 1
        
        -- 添加页面标题
        local page_title = ui.label({
            x = mx, y = my - 50,
            text = "页面 " .. label_prefix,
            color = ui.COLOR_BLACK,
            size = 22
        })
        win:add(page_title)
        
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                local x = mx + c * (bw + gapx)
                local y = my + r * (bh + gapy)
                local btn = ui.button({ 
                    x = x, y = y, 
                    w = bw, h = bh, 
                    text = string.format("%s-按钮%d", label_prefix, n),
                    size = 16
                })
                win:add(btn)
                n = n + 1
            end
        end
    end

    -- 创建总标题
    local title = ui.label({
        x = 250, y = 30,
        text = "横向滑动页面演示",
        color = ui.COLOR_BLACK,
        size = 24
    })
    win:add(title)

    -- 创建左页和右页内容
    makeGrid(0, "一")  -- 第一页
    makeGrid(page_w, "二")  -- 第二页

    -- 添加提示标签
    local hint = ui.label({
        x = 600, y = 50,
        text = "← 左右滑动切换页面 →",
        color = ui.COLOR_GRAY,
        size = 16
    })
    win:add(hint)

    -- 注册窗口到UI系统
    ui.add(win)

    -- 启动exeasyui刷新主循环
    while true do
        ui.refresh()
        sys.wait(30)
    end
end

sys.taskInit(ui_main)