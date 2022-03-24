local testdisp = {}

local sys = require "sys"

----------------------------------------------------------------------
-- 对接SSD1306
local function display_str(str)
    disp.clear()
    disp.drawStr(str, 1, 18)
    disp.update()
end

local function ui_update()
    disp.clear() -- 清屏
    disp.drawStr(os.date("%Y-%m-%d %H:%M:%S"), 1, 12) -- 写日期
    disp.drawStr("Luat@" .. rtos.bsp().." " .. _VERSION, 1, 24) -- 写版本号
    disp.update()
end

local function display_init()
    -- 初始化显示屏
    log.info("disp", "init ssd1306") -- log库是内置库,内置库均不需要require
    --此处使用硬件i2c0,具体引脚查看手册
    i2c.setup(0, i2c.FAST)
    disp.init({mode="i2c_hw", i2c_id=0})
    disp.setFont(1) -- 启用中文字体,文泉驿点阵宋体 12x12
    display_str("启动中 ...")
end

sys.taskInit(function()
    display_init()
    while 1 do
        sys.wait(1000)
        log.info("disp", "ui update", rtos.meminfo()) -- rtos是也是内置库
        ui_update()
    end
    
end)

return testdisp