PROJECT = "plcui_pump_station"
VERSION = "0.1.0"

local sys = require("sys")
local xml

-- 演示数据：泵是否运行、目标液位。实际项目可改为读取 PLC 数据。
local running = true
local target_level = 75.0

-- 根据业务数据更新首页，组件 ID 对应 main.xml 中的 id。
local function update_main()
    -- 状态灯的默认图为 RUNNING，checked 图为 STOPPED，所以这里取反。
    xml:find("main", "pump_status"):set_checked(not running)
    xml:find("main", "start"):set_checked(running)
    xml:find("main", "stop"):set_disabled(not running)
    xml:find("main", "pump_speed"):set_text(running and "1,450 rpm" or "0 rpm")
    xml:find("main", "flow"):set_text(running and "12.4 m3/h" or "0.0 m3/h")
    xml:find("main", "setpoint"):set_text(string.format("%.1f", target_level))
end

sys.taskInit(function()
    -- XML 负责界面布局和图片，handlers 对应 XML 中的事件名称。
    plcui.init({ width = 800, height = 480 })
    xml = plcui.load("/luadb/main.xml", { handlers = {
        motor_start = function()
            running = true
            update_main()
            xml:find("main", "feedback"):set_text("Pump started")
        end,
        motor_stop = function()
            running = false
            update_main()
            xml:find("main", "feedback"):set_text("Pump stopped")
        end,
        setpoint_submit = function(event)
            -- event.text 是键盘提交的文本，目标液位只允许 0～100%。
            local value = tonumber(event.text)
            if value and value >= 0 and value <= 100 then
                target_level = value
                xml:find("main", "feedback"):set_text("Target saved: " .. value .. " %")
            else
                xml:find("main", "setpoint"):set_text(string.format("%.1f", target_level))
                xml:find("main", "feedback"):set_text("Target range: 0-100 %")
            end
        end,
        setpoint_cancel = function()
            -- plcui 已自动恢复编辑前的值，这里只更新提示文字。
            xml:find("main", "feedback"):set_text("Edit cancelled")
        end,
        show_details = function()
            xml:show("details")
            -- 回调中的切页会延后执行，下一轮刷新后再访问新页面。
            sys.timerStart(function()
                xml:find("details", "detail_status"):set_checked(not running)
                xml:find("details", "motor_current"):set_text(running and "3.8 A" or "0.0 A")
            end, 30)
        end,
        show_main = function()
            xml:show("main")
            sys.timerStart(update_main, 30)
        end
    }})

    update_main()
    -- plcui.init() 已自动启动显示和输入调度，目标刷新率为 60Hz。

    -- 每秒改变一次模拟读数，只更新当前已创建的首页组件。
    local step = 0
    sys.timerLoopStart(function()
        step = (step + 1) % 10
        if plcui.status().page == "main" then
            xml:find("main", "temperature"):set_text(string.format("%.1f C", 24.6 + step / 10))
            xml:find("main", "level"):set_text(string.format("%.1f %%", 68.0 + step / 10))
        end
    end, 1000)
end)

sys.run()
