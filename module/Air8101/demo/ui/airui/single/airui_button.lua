--[[
@module button_page
@summary 按钮组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.button组件的用法，展示可点击按钮。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建按钮
    -- 示例1：创建一个基础按钮
    local btn1 = airui.button({ 
        text = "点我", 
        x = 20, 
        y = 80, 
        on_click = function() 
            log.info("btn", "tap") 
        end 
    })

    -- 示例2：创建一个支持切换显示内容的按钮，V1.0.3更新
    local is_play = false
    local btn2 = airui.button({
        text = "播放",
        x = 20,
        y = 180,
        on_click = function(self)
            if is_play then
                -- 当前是“停止”，点击后切换为“播放”
                self:set_text("播放") 
                is_play = false
            else
                -- 当前是“播放”，点击后切换为“停止”
                self:set_text("停止") 
                is_play = true
            end
        end
    })

    -- 主循环,V1.0.3已不需要
    -- while true do
    --     airui.refresh()
    --     sys.wait(50)
    -- end
end

sys.taskInit(ui_main)