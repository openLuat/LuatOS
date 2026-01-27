local main_page = {}

local tcp_page = require("tcp_page")
local setting_page = require("setting_page")

local container

function main_page.create_page()
    if container then
        return container
    end

    tcp_page.create_page()
    setting_page.create_page()

    container = airui.container({
        x = 0, y = 0, w = 320, h = 480,
        color = 0xffffff,
    })

    airui.label({
        parent = container,
        text = "iRTU 控制面板",
        x = 20, y = 10, w = 280, h = 32,
        font_size = 24,
    })

    airui.label({
        parent = container,
        text = "请选择测试功能",
        x = 20, y = 50, w = 280, h = 24,
    })

    airui.button({
        parent = container,
        text = "远程 TCP 测试",
        x = 60, y = 100, w = 200, h = 50,
        on_click = function()
            tcp_page.show_page()
        end,
    })

    airui.button({
        parent = container,
        text = "参数设置查看",
        x = 60, y = 170, w = 200, h = 50,
        on_click = function()
            log.info("main_page", "show setting page")
            setting_page.show_page()
        end,
    })

    container:hide()
    return container
end

function main_page.show_page()
    if not container then
        main_page.create_page()
    end
    container:open()
end

return main_page

