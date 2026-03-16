--[[
@module image_page
@summary 图片组件演示
@version 1.0
@date 2026.01.27
@author 李源龙
@usage
本文件演示airui.image组件的用法，展示图片显示功能。
]]
-- 加载显示驱动
lcd_drv = require("lcd_drv")
-- 加载触摸驱动
tp_drv = require("tp_drv")


local card_temp, card_hum, card_air, title_temp,main_container
local temp_label, humi_label, voc_label

local function humi_sext_cb(temp,humi)
    temp_label:set_text(temp)
    humi_label:set_text(humi)
end

sys.subscribe("HUMI_TEXT", humi_sext_cb)

local function voc_sext_cb(voc)
    voc_label:set_text(voc)
end

sys.subscribe("VOC_TEXT", voc_sext_cb)

local function ui_main()
    log.info("IMAGE")
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0xF8F9FA,
        parent = airui.screen,
    })

    -- 中间内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,

        h = 320,
        color = 0xF3F4F6,
    })
    title_temp = airui.container({
        parent = content,
        x = 0,
        y = 0, 
        w = 480,
        h = 80,
        -- color = 0xffffff,
        color_opacity = 255,
        radius = 10,
    })
    airui.label({
        parent = title_temp,
        x = 90,
        y = 10,
        w = 300,
        h = 35,
        text = "室内空气质量分析仪",
        font_size = 36,
        align = airui.TEXT_ALIGN_CENTER
    })
    card_temp = airui.container({
        parent = content,
        x = 15,
        y = 100,
        w = 140,
        h = 160,
        color = 0xffffff,
        radius = 10,
    })
    card_hum = airui.container({
        parent = content,
        x = 170,
        y = 100,
        w = 140,
        h = 160,
        color = 0xffffff,
        radius = 10,
    })
    card_air = airui.container({
        parent = content,
        x = 325,
        y = 100,
        w = 140,
        h = 160,
        color = 0xffffff,
        radius = 10,
    })
    -- 温度卡片
    airui.image({ parent = card_temp, x = 35, y = 8, w = 60, h = 60, src = "/luadb/wendu.png" })
    temp_label = airui.label({
        parent = card_temp,
        x = 10,
        y = 100,
        w = 75,
        h = 30,
        text = "0",
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_temp,
        x = 100,
        y = 100,
        w = 30,
        h = 16,
        text = "℃",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_temp,
        x = 0,
        y = 120,
        w = 130,
        h = 20,
        text = "当前温度",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 湿度卡片
    airui.image({ parent = card_hum, x = 35, y = 8, w = 60, h = 60, src = "/luadb/shidu.png" })
    humi_label = airui.label({
        parent = card_hum,
        x = 10,
        y = 100,
        w = 70,
        h = 30,
        text = "0",
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_hum,
        x = 90,
        y = 100,
        w = 40,
        h = 18,
        text = "%RH",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_hum,
        x = 0,
        y = 120,
        w = 130,
        h = 20,
        text = "当前湿度",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 空气质量卡片
    airui.image({ parent = card_air, x = 35, y = 8, w = 60, h = 60, src = "/luadb/voc.png" })
    voc_label = airui.label({
        parent = card_air,
        x = 10,
        y = 100,
        w = 75,
        h = 30,
        text = "0",
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_air,
        x = 95,
        y = 100,
        w = 40,
        h = 20,
        text = "ppb",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_air,
        x = 0,
        y = 120,
        w = 130,
        h = 20,
        text = "空气质量",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })


end

sys.taskInit(ui_main)