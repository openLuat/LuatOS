--[[
@module msgbox_page
@summary 消息框组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.msgbox组件的用法，展示消息提示框功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 加载中文字体
    airui.font_load({
        type = "hzfont",
        path = "/MiSans_gb2312.ttf",
        size = 16,
        cache_size = 2048,
        antialias = 1,
    })

    -- 创建消息框
    local box = airui.msgbox({
        title = "通知",
        text = "2026年你会发财！",
        buttons = { "确定" }
    })
    box:show()  -- 显示消息框

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)