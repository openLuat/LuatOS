-- Button 组件测试脚本
PROJECT = "easylvgl"
VERSION = "1.0.0"

sys.taskInit(function()
    
    -- 1. 初始化 EasyLVGL
    -- easylvgl.init(w, h, buff_size, buff_mode)
    -- w: 屏幕宽,可选,默认480
    -- h: 屏幕高,可选,默认320
    -- color_format: 颜色格式,可选,默认ARGB8888
    --                   可用值：easylvgl.COLOR_FORMAT_RGB565（默认,嵌入式，节省内存）
    --                          easylvgl.COLOR_FORMAT_ARGB8888（pc，高质量）
    local ret = easylvgl.init(800, 600, easylvgl.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("easylvgl", "init failed")
        return
    end
    
    local btn = easylvgl.button({
        text = "LuatOS!",
        x = 20, y = 80, w = 160, h = 48,
        on_click = function(self)
            log.info("Button clicked")
        end
    })

    -- 3. 创建一个任务来动态修改按钮文本
    sys.taskInit(function()
        sys.wait(2000)  -- 等待 2 秒
        btn:set_text("Button1")  -- 修改按钮文本
        
        sys.wait(2000)  -- 再等待 2 秒
        btn:set_text("Button2")  -- 再次修改
    end)

    while true do
        easylvgl.refresh()
        sys.wait(10)
    end

end)

sys.run()

