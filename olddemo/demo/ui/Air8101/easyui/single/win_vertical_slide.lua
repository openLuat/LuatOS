--[[
@module  win_vertical_slide
@summary 纵向滑动页面演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为纵向滑动页面演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、启用纵向滑动功能；
3、创建两页内容并垂直排列；
4、实现纵向滑动切换页面效果；
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

    -- 启用纵向分页滚动，将两页内容上下排布
    local page_w, page_h = lcd.getSize()
    local total_h = page_h * 2

    -- 创建纵向滑动窗口
    win:enable_scroll({ 
        direction = "vertical", 
        content_height = total_h, 
        threshold = 10, 
        page_height = page_h 
    })

    -- 创建按钮布局函数
    local function makebuttons(offset_y, label_prefix)
        -- 竖直等间距排列：1列4行，水平居中
        local cols, rows = 1, 4
        local bw, bh = 300, 70
        local mx = math.floor((page_w - bw) / 2) -- 居中
        local gap = math.floor((page_h - rows * bh) / (rows + 1))
        if gap < 20 then gap = 20 end
        local n = 1
        
        -- 添加页面标题
        local page_title = ui.label({
            x = mx, y = offset_y + gap - 40,
            text = "页面 " .. label_prefix,
            color = ui.COLOR_BLACK,
            size = 22
        })
        win:add(page_title)
        
        for r = 0, rows - 1 do
            local x = mx
            local y = offset_y + gap + r * (bh + gap)
            local btn = ui.button({ 
                x = x, y = y, 
                w = bw, h = bh, 
                text = string.format("%s-按钮%d", label_prefix, n),
                size = 18
            })
            win:add(btn)
            n = n + 1
        end
    end

    -- 创建总标题
    local title = ui.label({
        x = 320, y = 20,
        text = "纵向滑动页面演示",
        color = ui.COLOR_BLACK,
        size = 24
    })
    win:add(title)

    -- 添加上页和下页内容
    makebuttons(0, "一")  -- 第一页
    makebuttons(page_h, "二")  -- 第二页

    -- 添加提示标签
    local hint = ui.label({
        x = 320, y = 450,
        text = "上下滑动切换页面",
        color = ui.COLOR_GRAY,
        size = 16
    })
    win:add(hint)

    -- 注册窗口到UI系统
    ui.add(win)

end

sys.taskInit(ui_main)