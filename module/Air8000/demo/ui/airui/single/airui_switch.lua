--[[
@module switch_page
@summary 开关组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.switch组件的用法，展示开关切换功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建标签显示状态
    local label = airui.label({
        text = "当前状态: 开",
        x = 20,
        y = 80,
        w = 150,
        h = 40,
    })

    -- 创建开关
-- 使用一个变量来跟踪当前状态
    local is_on = true -- 初始为ON，与switch的checked=true对应
    local sw = airui.switch({
        x = 20,
        y = 120,
        checked = true,
        on_change = function()
            -- 切换状态
            is_on = not is_on
            -- 根据状态更新文本
            if is_on then
                label:set_text("当前状态: 开")
            else
                label:set_text("当前状态: 关")
            end
        end
    })

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)