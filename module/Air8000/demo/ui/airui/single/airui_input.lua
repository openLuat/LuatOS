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

    -- 创建虚拟键盘
    local keyboard = airui.keyboard({
        x = 0,
        y = -10,
        w = 320,
        h = 200,
        mode = "text",
        auto_hide = true,
    })

    -- 创建文本输入框
    local textarea = airui.textarea({
        x = 10,
        y = 50,
        w = 300,
        h = 100,
        max_len = 512,
        text = "在这里输入文字",
        placeholder = "点击输入...",
        keyboard = keyboard
    })

        -- 创建按钮
    local btn = airui.button({
        x = 20,
        y = 180,
        text = "提交",
        on_click = function()
            airui.msgbox({
                title = "提交内容为",
                text = textarea:get_text(),
                buttons = { "确定" },
                on_action = function(self, label)
                    if label == "确定" then
                        self:hide()
                    end
                end
            })
        end
    })
end

sys.taskInit(ui_main)
