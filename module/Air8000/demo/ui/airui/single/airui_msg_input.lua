--[[
@module msg_input_demo
@summary 容器模拟消息框内嵌输入框示例
@version 1.0
@date 2026.03.11
@author 江访
@usage
点击主界面按钮弹出自定义对话框，输入内容后提交，用 msgbox 显示结果。
]]

local function ui_main()
    -- 初始化硬件（根据实际驱动调整）
    lcd_drv.init()
    tp_drv.init()

    -- 创建全局虚拟键盘（自动隐藏）
    local keyboard = airui.keyboard({
        x = 0,
        y = -10,           -- 底部留边距
        w = 320,
        h = 200,
        mode = "numeric",
        auto_hide = true,
    })

    -- 用于保存当前打开的对话框容器
    local current_dlg = nil

    -- 主界面按钮，点击时弹出自定义对话框
    local btn_open = airui.button({
        x = 80,
        y = 200,
        w = 160,
        h = 50,
        text = "打开输入框",
        on_click = function()
            -- 如果已有对话框，先销毁（避免重叠）
            if current_dlg and current_dlg.destroy then
                current_dlg:destroy()
                current_dlg = nil
            end

            -- 创建一个半透明的背景遮罩（覆盖全屏，阻止点击穿透）
            local mask = airui.container({
                parent = airui.screen,
                x = 0, y = 0,
                w = 320,        -- 假设屏幕宽度 320，可根据实际调整
                h = 480,        -- 假设屏幕高度 480
                color = 0x000000,
                color_opacity = 180,  -- 半透明黑色
                -- 不设置点击回调，用于捕获触摸防止穿透，但子组件仍可点击
            })

            -- 创建对话框主体容器（居中显示）
            local dlg = airui.container({
                parent = mask,   -- 放在遮罩上
                x = 20, y = 120,
                w = 280, h = 240,
                color = 0xFFFFFF,
                radius = 10,     -- 圆角
                border_width = 1,
                border_color = 0xCCCCCC,
            })

            -- 标题文本
            local title = airui.label({
                parent = dlg,
                text = "请输入信息",
                x = 10, y = 10,
                w = 260, h = 30,
                color = 0x000000,
                font_size = 18,
                align = airui.TEXT_ALIGN_CENTER,
            })

            -- 文本输入框
            local ta = airui.textarea({
                parent = dlg,
                x = 10, y = 50,
                w = 260, h = 100,
                max_len = 256,
                placeholder = "点击此处输入...",
                keyboard = keyboard,
                bg_color = 0xF8F8F8,
                border_color = 0xAAAAAA,
                border_width = 1,
            })

            -- 提交按钮
            local btn_submit = airui.button({
                parent = dlg,
                x = 90, y = 180,
                w = 100, h = 40,
                text = "提交",
                on_click = function()
                    -- 获取输入内容
                    local input_text = ta:get_text()
                    if input_text == "" then
                        input_text = "(空输入)"
                    end

                    -- 销毁整个对话框（遮罩和容器）
                    if mask and mask.destroy then
                        mask:destroy()
                    end
                    current_dlg = nil

                    -- 用 msgbox 显示提交结果
                    local msg = airui.msgbox({
                        title = "提交结果",
                        text = "您输入的内容是：\n" .. input_text,
                        buttons = { "确定" },
                        on_action = function(self, label)
                            if label == "确定" then
                                self:hide()
                            end
                        end
                    })
                    msg:show()
                end
            })

            -- 关闭按钮（可选，点击后仅关闭对话框）
            local btn_close = airui.button({
                parent = dlg,
                x = 250, y = 5,
                w = 25, h = 25,
                text = "×",
                on_click = function()
                    if mask and mask.destroy then
                        mask:destroy()
                    end
                    current_dlg = nil
                end
            })

            -- 保存当前对话框引用
            current_dlg = mask   -- 保存遮罩即可，销毁遮罩会自动销毁其子容器
        end
    })
end

sys.taskInit(ui_main)