--[[
@module dropdown_page
@summary 下拉框组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.dropdown组件的用法，展示下拉选择功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建标签显示选择结果
    local label = airui.label({
        text = "请选择选项",
        x = 50,
        y = 80,
        w = 200,
        h = 40,
    })

    -- 创建下拉框
    local dd = airui.dropdown({
        x = 50,
        y = 120,
        w = 120,
        h = 40,
        options = { "选项A", "选项B", "选项C" },
        default_index = 1,
        on_change = function(self, index)
            -- 更新标签显示选择结果
            local texts = { "选项A", "选项B", "选项C" }
            label:set_text("选择了: " .. texts[index + 1])
        end
    })

    -- 主循环,V1.0.3已不需要
    -- while true do
    --     airui.refresh()
    --     sys.wait(50)
    -- end
end

sys.taskInit(ui_main)