-- Switch 组件测试脚本
PROJECT = "easylvgl"
VERSION = "1.0.0"

sys.taskInit(function()
    local ret = easylvgl.init(800, 600, easylvgl.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("easylvgl", "switch init failed")
        return
    end

    -- 开关组件
    local sw = easylvgl.switch({
        parent = easylvgl.screen,
        checked = true, -- 初始状态，默认 false
        x = 40, y = 120, w = 120, h = 60, -- x, y, w, h
        style = "success", -- 预设样式，如 "danger"/"success"
        on_change = function(self) -- 状态变更回调
            log.info("switch", "state changed", self:get_state())
        end
    })

    while true do
        easylvgl.refresh()
        sys.wait(10)
    end
end)

sys.run()

