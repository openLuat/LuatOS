--[[
@module image_page
@summary 图片组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.image组件的用法，展示图片显示功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建可点击图片
    local img = airui.image({
        src = "/luadb/dingwei_50x50.png",
        x = 100,
        y = 176,
        w = 128,
        h = 128,
        opacity = 100, -- 透明度
        on_click = function(self)
            log.info("image", "图片被点击了")
        end
    })

    -- 创建半透明图片
    local img1 = airui.image({
        src = "/luadb/logo.jpg",
        x = 20,
        y = 20,
        w = 80,
        h = 80,
    })

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)