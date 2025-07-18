--[[
@module  agpio_test
@summary AGPIO测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板测试对比AGPIO和普通GPIO进入休眠模式前后的区别
本测试需测量核心板功耗，将板载USB旁边的开关拨到off一端，
供电需通过Vbat外接合宙IOTpower或Air9000功耗分析仪的3.8V输出
]]

-- 定义AGPIO端口: GPIO27
local agpio_number = 27
-- 定义普通GPIO端口: GPIO01
local normal_gpio_number = 1

function test_agpio_func()

    -- 配置AGPIO为输出模式，初始输出高电平
    gpio.setup(agpio_number, 1)
    -- 配置普通GPIO为输出模式，初始输出高电平
    gpio.setup(normal_gpio_number, 1)
    
    sys.wait(16000)
    -- 上电模式工作运行16s后关闭USB电源
    pm.power(pm.USB, false)
    -- 进入低功耗模式
    pm.power(pm.WORK_MODE, 3)


    -- 之后按rst键重新复位系统测试
end


--创建并且启动一个task
--运行这个task的主函数 test_agpio_func
sys.taskInit(test_agpio_func)