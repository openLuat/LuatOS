--[[
@module input_page
@summary 输入框和键盘演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.textarea和airui.keyboard组件的用法，展示文本输入功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 加载中文字体
    -- Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255号中文显示
    airui.font_load({
        type = "hzfont",   -- 字体类型，可选 "hzfont" 或 "bin"
        path = nil,        -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
        size = 20,         -- 字体大小，默认 16
        cache_size = 2048, -- 缓存字数大小，默认 2048
        antialias = 1,     -- 抗锯齿等级，默认 4
    })

    -- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
    -- airui.font_load({
    --     type = "hzfont",             -- 字体类型，可选 "hzfont" 或 "bin"
    --     path = "/MiSans_gb2312.ttf", -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
    --     size = 20,                   -- 字体大小，默认 16
    --     cache_size = 2048,           -- 缓存字数大小，默认 2048
    --     antialias = 1,               -- 抗锯齿等级，默认 4
    -- })

    -- 创建文本输入框
    local textarea = airui.textarea({
        x = 10,
        y = 50,
        w = 300,   
        h = 100,
        max_len = 512,
        text = "在这里输入文字",
        placeholder = "点击输入...",
    })

    -- 创建虚拟键盘
    local keyboard = airui.keyboard({
        x = 0,
        y = -10,    
        w = 320,
        h = 200,
        mode = "text",
        target = textarea,
        auto_hide = true,
        on_commit = function()
            log.info("input", "输入内容: ", textarea:get_text())
        end,
    })

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)