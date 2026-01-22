-- Image 组件测试脚本
PROJECT = "airui"
VERSION = "1.0.0"

sys.taskInit(function()
    local ret = airui.init(800, 600, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("airui", "init failed")
        return
    end

    -- 当前只支持png图片，后续将支持jpg等格式的图片
    test_png = "/luadb/logo.png"
    sunset_png = "/luadb/sunset.png"

    local exists = io.exists(test_png)
    log.info("airui.image", "png exists: %s", exists)

    -- 可点击图片
    local img = airui.image({
        parent = airui.screen, -- 父对象，可选，默认当前屏幕
        src = test_png,
        x = 240, y = 160, w = 80, h = 80,
        zoom = 256, -- 缩放比例，默认 256（100%）
        opacity = 255, -- 透明度，默认 255（不透明），范围 0-255
        on_click = function(self)
            log.info("airui.image", "image clicked")
        end
    })

    -- 不可点击图片
    local img1 = airui.image({
        parent = airui.screen, -- 父对象，可选，默认当前屏幕
        src = test_png,
        x = 400, y = 160, w = 80, h = 80,
        zoom = 256, -- 缩放比例，默认 256（100%）
        opacity = 255, -- 透明度，默认 255（不透明），范围 0-255
    })

    local btn = airui.button({
        parent = airui.screen, -- 父对象，可选，默认当前屏幕
        text = "set src to sunset",
        x = 280, y = 260, w = 160, h = 48,
        on_click = function(self)
            img:set_src(sunset_png)
        end
    })


    while true do
        airui.refresh()
        sys.wait(10)
    end


end)

sys.run()

