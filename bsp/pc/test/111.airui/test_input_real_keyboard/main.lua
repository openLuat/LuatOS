-- 使用 PC 物理键盘输入 textarea（不弹虚拟键盘）
PROJECT = "airui"
VERSION = "1.0.0"

sys.taskInit(function()
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

    -- 允许系统键盘事件转发给当前 textarea, 当前只支持pc模拟器中使用
    airui.keyboard_enable_system(true)

    local textarea = airui.textarea({
        x = 20, y = 20,
        w = 760, h = 280,
        max_len = 256,
        placeholder = "Click here and use your physical keyboard input (Windows/SDL)"
    })

    textarea:set_on_text_change(function()
        log.info("textarea", "text -> " .. (textarea:get_text() or ""))
    end)

    while true do
        airui.refresh()
        sys.wait(10)
    end
end)

sys.run()

