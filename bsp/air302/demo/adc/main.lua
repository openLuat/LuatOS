
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "adcdemo"
VERSION = "1.0.0"

-- 一定要添加sys.lua !!!!
local sys = require "sys"

-- 网络灯 GPIO19, NETLED脚
local NETLED = gpio.setup(19, 0)     -- 初始化GPIO19, 并设置为低电平



sys.taskInit(function()
    while 1 do
        log.info("LED", "Go Go Go")
        NETLED(0) -- 低电平,熄灭
        sys.wait(1000)
        NETLED(1) -- 高电平,亮起
        sys.wait(1000)

        adc.open(0) -- CPU温度
        adc.open(1) -- VBAT电压
        adc.open(2) -- 模块上的ADC0脚, 0-1.8v,不要超过范围使用!!!
        --sys.wait(50)

        log.debug("adc", "adc0", adc.read(0)) -- adc.read 会返回两个值
        log.debug("adc", "adc1", adc.read(1))
        log.debug("adc", "adc2", adc.read(2))

        -- 使用完毕后关闭,可以使得休眠电流更低.
        adc.close(0)
        adc.close(1)
        adc.close(2)
    end
    
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
