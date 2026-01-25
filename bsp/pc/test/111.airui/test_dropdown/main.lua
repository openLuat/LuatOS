-- Dropdown 组件测试脚本
PROJECT = "airui"
VERSION = "1.0.0"

sys.taskInit(function()
    local ret = airui.init(800, 600, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("airui", "dropdown init failed")
        return
    end

    -- 下拉框组件
    local dropdown = airui.dropdown({
        parent = airui.screen, -- 父对象，可选，默认当前屏幕
        options = {"Option A", "Option B", "Option C"}, -- 选项列表（字符串数组）
        default_index = 2, -- 默认选中项索引，默认 -1
        x = 40, y = 60, w = 180, h = 50,
        on_change = function(self, index) -- 选中项变化回调
            log.info("dropdown", "selected index", index)
        end
    })

    local btn = airui.button({
        parent = airui.screen, -- 父对象，可选，默认当前屏幕
        text = "set selected to A",
        x = 240, y = 60, w = 160, h = 48,
        on_click = function(self)
            local selected = dropdown:get_selected() -- 获取当前选中项索引
            log.info("dropdown", "previous selected index is", selected)
            dropdown:set_selected(0)  -- 设置选中项为1  
            log.info("dropdown", "now set selected to A")
        end
    })
    


    while true do
        airui.refresh()
        sys.wait(10)
    end
end)

sys.run()

