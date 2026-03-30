--[[
@module qrcode_page
@summary 二维码组件演示
@version 1.0
@date 2026.03.09
@author 江访
@usage
本文件演示airui.qrcode组件的用法，展示二维码生成。
]]

local function ui_main()
    -- 初始化硬件


    -- 创建二维码
    local qrcode = airui.qrcode({
        x = 40,
        y = 40,
        size = 220,                     -- 正方形尺寸
        data = "https://docs.openluat.com/",    -- 二维码内容
        dark_color = 0x000000,          -- 深色模块颜色
        light_color = 0xFFFFFF,         -- 浅色模块颜色
        quiet_zone = true                -- 四周留白
    })

    if not qrcode then
        log.error("qrcode", "创建二维码失败")
        return
    end

    -- 添加一个标签说明
    airui.label({
        x = 40,
        y = 280,
        w = 720,
        h = 40,
        text = "扫描上方二维码访问 LuatOS 官网",
        font_size = 20,
        color = 0x333333
    })
end

sys.taskInit(ui_main)