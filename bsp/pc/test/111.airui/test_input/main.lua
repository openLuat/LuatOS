-- Textarea + 虚拟键盘输入测试
PROJECT = "airui"
VERSION = "1.0.0"

sys.taskInit(function()
    -- 初始化 AIRUI，800x600 分辨率，使用 ARGB8888（PC 模拟）
    local ret = airui.init(800, 600, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("airui", "init failed")
        return
    end

    -- 创建 textarea，通过虚拟键盘输入文本
    local textarea = airui.textarea({
        parent = airui.screen, -- 父对象，可选，默认当前屏幕
        x = 20, y = 20, w = 760, h = 180,
        max_len = 256, -- 最大字符数，默认 256
        text = "Hello, World!", -- 初始文本
        placeholder = "Please input text, the virtual keyboard will auto bind"
    })

    -- 注册虚拟键盘，将 textarea 作为目标，并监听确认事件
    local keyboard = airui.keyboard({
        x = 0, y = 0, w = 760, h = 220, -- x, y, 从左边下方开始计算
        mode = "text", -- 键盘模式，可选 "text"/"upper"/"special"/"numeric"
        target = textarea, -- 关联的 Textarea 对象，可选
        on_commit = function() -- 确认事件回调，只有在按下确认键时才会触发
            log.info("keyboard", "commit -> " .. (textarea:get_text() or ""))
        end
    })

    -- 持续打印 textarea 变化状态
    textarea:set_on_text_change(function()
        log.info("textarea", "text changed -> " .. (textarea:get_text() or ""))
    end)

    while true do
        airui.refresh()
        sys.wait(10)
    end
end)

sys.run()

