--[[
@module spinner_page
@summary 加载指示器组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.spinner组件的用法，展示旋转加载动画。
适用于320x480竖屏。
]]

local function ui_main()
    -- 初始化硬件

    -- 标题
    airui.label({
        text = "Spinner 加载指示器",
        x = 0, y = 20, w = 320, h = 24,
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 默认蓝色spinner
    local spinner1 = airui.spinner({
        x = 70, y = 80, w = 40, h = 40,
        duration = 1000,
        arc_angle = 200,
        style = {
            color = 0x00b4ff,
            track_color = 0xd0d0d0,
            line_width = 4,
            opa = 255,
        }
    })

    -- 橙色大号spinner
    local spinner2 = airui.spinner({
        x = 200, y = 70, w = 60, h = 60,
        duration = 800,
        arc_angle = 260,
        style = {
            color = 0xff7a00,
            track_color = 0x33261a,
            line_width = 5,
            opa = 255,
        }
    })

    -- 绿色慢速spinner
    local spinner3 = airui.spinner({
        x = 70, y = 180, w = 40, h = 40,
        duration = 1500,
        arc_angle = 160,
        style = {
            color = 0x22c55e,
            track_color = 0x1a3522,
            line_width = 4,
            opa = 255,
        }
    })

    -- 紫色半透明spinner
    local spinner4 = airui.spinner({
        x = 200, y = 175, w = 50, h = 50,
        duration = 1200,
        arc_angle = 220,
        style = {
            color = 0xa855f7,
            track_color = 0x2a1a35,
            line_width = 4,
            opa = 180,
        }
    })

    -- 提示文字
    airui.label({
        text = "点击按钮切换效果",
        x = 0, y = 280, w = 320, h = 20,
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 切换配色按钮
    airui.button({
        x = 60, y = 320, w = 200, h = 40,
        text = "切换配色",
        on_click = function()
            spinner1:set_style({
                color = 0xff3b30,
                track_color = 0x2a1515,
                line_width = 4,
                opa = 255,
            })
            log.info("spinner", "样式已切换")
        end
    })

    -- 加速旋转按钮
    airui.button({
        x = 60, y = 380, w = 200, h = 40,
        text = "加速旋转",
        on_click = function()
            spinner2:set_anim_params(400, 280)
            spinner3:set_anim_params(600, 240)
            log.info("spinner", "旋转加速")
        end
    })

end

sys.taskInit(ui_main)
