-- Msgbox component test script
PROJECT = "easylvgl"
VERSION = "1.0.0"

sys.taskInit(function()
    local ret = easylvgl.init(800, 600, easylvgl.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("easylvgl", "msgbox init failed")
        return
    end

    -- 消息框组件
    local msgbox = easylvgl.msgbox({
        title = "Notice", -- 标题文本，可选
        text = "Please select an action button", -- 内容文本，可选
        buttons = {"OK", "Cancel", "Close"}, -- 按钮标签数组，默认 ["OK"]
        timeout = 0, -- 自动关闭时间（毫秒），默认 0
        auto_center = true, -- 是否自动居中，默认 true
        on_action = function(self, text) -- 按钮点击回调
            log.info("msgbox", "action", text)
            self:release()
        end,
    })

    while true do
        easylvgl.refresh()
        sys.wait(10)
    end
end)

sys.run()

