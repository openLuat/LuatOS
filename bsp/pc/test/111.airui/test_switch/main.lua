-- Switch 组件测试脚本
PROJECT = "airui"
VERSION = "1.0.0"

sys.taskInit(function()
    local ret = airui.init(800, 600, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("airui", "switch init failed")
        return
    end

    -- 开关组件
    local sw = airui.switch({
        parent = airui.screen,
        checked = true, -- 初始状态，默认 false
        x = 40, y = 120, w = 120, h = 60, -- x, y, w, h
        style = "success", -- 预设样式，如 "danger"/"success"
        on_change = function(self) -- 状态变更回调
            log.info("switch", "state changed", self:get_state())
        end
    })

    while true do
        airui.refresh()
        sys.wait(10)
    end
end)

sys.run()

