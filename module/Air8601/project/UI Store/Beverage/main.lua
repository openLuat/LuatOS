PROJECT = "AIR8601_BEVERAGE_UI"
VERSION = "001.003.000"
sys = require "sys"
log.info("main", PROJECT, VERSION)

sys.taskInit(function()
    local ok, err = pcall(function()
        local C = require "config"
        local board = require "board"
        board.init()
        local ui = require "ui"
        local beverage = require "beverage"
        ui.create()
        sys.wait(100)
        board.backlight_on()
        -- 液位保持50ms定时器；小人物由独立的24fps协作任务调度。
        require("mascot").start()
        sys.timerLoopStart(function()
            if beverage.advance(C.TICK_MS) then ui.refresh() end
        end, C.TICK_MS)
        log.info("main", "饮料机UI启动完成；小店员目标24fps，当前为灌注动画演示")
    end)
    if not ok then log.error("main", "初始化失败", err) end
end)

sys.run()
