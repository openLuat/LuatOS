-- Button 组件测试脚本
PROJECT = "airui"
VERSION = "1.0.0"

sys.taskInit(function()

    -- 1. 初始化 AIRUI
    -- airui.init(w, h, buff_size, buff_mode)
    -- w: 屏幕宽,可选,默认480
    -- h: 屏幕高,可选,默认320
    -- color_format: 颜色格式,可选,默认ARGB8888
    --                   可用值：airui.COLOR_FORMAT_RGB565（默认,嵌入式，节省内存）
    --                          airui.COLOR_FORMAT_ARGB8888（pc，高质量）
    local ret = airui.init(800, 600, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("airui", "init failed")
        return
    end

    -- 加载hzfont字库，从而支持中文显示
    airui.font_load({
        type = "hzfont", -- 字体类型，可选 "hzfont" 或 "bin"
        path = nil, -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
        size = 16, -- 字体大小，默认 16
        cache_size = 2048, -- 缓存字数大小，默认 2048
        antialias = 4, -- 抗锯齿等级，默认 4
    })

    local label = airui.label({
        text = "Hello, World!",
        x = 20, y = 80, w = 500, h = 500,
    })

    local label2 = airui.label({
        parent = label,
        text = "你好,世界!\n你好,宇宙!\n你好,人类!",
        x = 20, y = 60, w = 300, h = 200,
    })

    while true do
        airui.refresh()
        sys.wait(10)
    end

end)

sys.run()

