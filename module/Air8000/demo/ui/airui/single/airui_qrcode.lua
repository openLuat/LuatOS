--[[
@module qrcode_page
@summary 二维码组件演示
@version 1.0
@date 2026.03.09
@author 江访
@usage
本文件演示airui.qrcode组件的用法，展示二维码生成与切换。
]]

local function ui_main()
    -- 初始化硬件


    -- 标题
    airui.label({
        text = "二维码演示",
        x = 10, y = 10, w = 300, h = 30,
        color = 0x000000,
        font_size = 18,
    })

    -- 创建二维码
    local qr = airui.qrcode({
        x = 50, y = 60,
        size = 220,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    if not qr then
        log.error("qrcode", "创建失败")
        return
    end

    -- 状态变量，用于切换内容
    local is_luatos = true

    -- 切换内容的按钮
    local btn_switch = airui.button({
        x = 80, y = 300, w = 160, h = 40,
        text = "切换二维码",
        on_click = function()
            if is_luatos then
                -- 切换到WIFI配置信息
                local ok = qr:set_data("WIFI:T:WPA;S:AirUI_Demo;P:12345678;;")
                if ok then
                    log.info("qrcode", "已切换到WIFI配置")
                    is_luatos = false
                else
                    log.error("qrcode", "数据过长，切换失败")
                end
            else
                -- 切换docs资料站
                qr:set_data("https://docs.openluat.com/")
                is_luatos = true
            end
        end
    })

    -- 提示标签
    airui.label({
        text = "点击按钮切换二维码内容",
        x = 10, y = 360, w = 300, h = 20,
        font_size = 14,
        color = 0x666666,
    })
end

sys.taskInit(ui_main)