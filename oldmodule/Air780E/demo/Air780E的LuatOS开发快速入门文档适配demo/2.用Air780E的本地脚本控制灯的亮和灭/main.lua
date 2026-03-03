PROJECT = "GPIO_TEST_DEMO"
VERSION = "1.0.0"

--除了sys和sysplus库需要require，其他的底层库不需要require了
sys = require("sys")

--[[
    @param1 引脚号
    @param2 配置输入输出模式，0是输出模式
    @param3 配置上下拉，gpio.PULLUP是上拉模式
]]
gpio.setup(27, 0, gpio.PULLUP)

sys.taskInit(function()
    while 1 do
        --翻转引脚27的电平状态
        gpio.toggle(27)
        --延时1000ms
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
