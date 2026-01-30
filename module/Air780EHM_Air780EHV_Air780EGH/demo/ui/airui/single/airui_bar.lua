--[[
@module bar_page
@summary 进度条组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.bar组件的用法，展示动态变化的进度条。
]]

local direction = 1 -- 变化方向
local current = 0   -- 当前值

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建进度条
    local progress = airui.bar({
        x = 20,
        y = 200,
        w = 280,
        value = 30
    })

    -- 主循环
    while true do
        airui.refresh()

        -- 更新进度条值
        current = current + direction
        if current >= 100 then
            direction = -1
        elseif current <= 0 then
            direction = 1
        end

        progress:set_value(current, true)
        sys.wait(50)
    end
end

sys.taskInit(ui_main)