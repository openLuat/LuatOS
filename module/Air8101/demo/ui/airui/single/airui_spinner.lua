--[[
@module spinner_page
@summary 加载指示器组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.spinner组件的用法，展示旋转加载动画。
]]

local function ui_main()
    -- 初始化硬件

    -- 标题
    airui.label({
        text = "Spinner 加载指示器演示",
        x = 0,
        y = 40,
        w = 800,
        h = 30,
        font_size = 24,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 默认样式加载指示器
    local spinner1 = airui.spinner({
        x = 150,
        y = 120,
        w = 40,
        h = 40,
        duration = 1000,
        arc_angle = 200,
        style = {
            color = 0x00b4ff,
            track_color = 0xd0d0d0,
            line_width = 4,
            opa = 255,
        }
    })

    -- 橙色大号加载指示器
    local spinner2 = airui.spinner({
        x = 270,
        y = 100,
        w = 80,
        h = 80,
        duration = 800,        -- 更快旋转
        arc_angle = 260,       -- 更长弧线
        style = {
            color = 0xff7a00,
            track_color = 0x33261a,
            line_width = 6,
            opa = 255,
        }
    })

    -- 绿色小号加载指示器
    local spinner3 = airui.spinner({
        x = 420,
        y = 120,
        w = 40,
        h = 40,
        duration = 1500,        -- 慢速旋转
        arc_angle = 160,
        style = {
            color = 0x22c55e,
            track_color = 0x1a3522,
            line_width = 4,
            opa = 255,
        }
    })

    -- 半透明加载指示器
    local spinner4 = airui.spinner({
        x = 530,
        y = 110,
        w = 60,
        h = 60,
        duration = 1200,
        arc_angle = 220,
        style = {
            color = 0xa855f7,
            track_color = 0x2a1a35,
            line_width = 5,
            opa = 180,
        }
    })

    -- 提示文字
    airui.label({
        text = "点击按钮切换加载样式",
        x = 0,
        y = 280,
        w = 800,
        h = 30,
        font_size = 16,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 切换样式按钮
    airui.button({
        x = 300,
        y = 330,
        w = 200,
        h = 40,
        text = "切换配色",
        on_click = function()
            spinner1:set_style({
                color = 0xff3b30,
                track_color = 0x2a1515,
                line_width = 4,
                opa = 255,
            })
            spinner2:set_style({
                color = 0x00b4ff,
                track_color = 0x1a2a35,
                line_width = 5,
                opa = 200,
            })
            log.info("spinner", "样式已切换")
        end
    })

    -- 加速旋转按钮
    airui.button({
        x = 300,
        y = 390,
        w = 200,
        h = 40,
        text = "加速旋转",
        on_click = function()
            spinner2:set_anim_params(400, 280)
            spinner3:set_anim_params(600, 240)
            log.info("spinner", "旋转加速")
        end
    })

end

sys.taskInit(ui_main)
