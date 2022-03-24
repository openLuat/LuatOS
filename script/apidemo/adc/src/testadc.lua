local testAdc = {}

local sys = require "sys"

sys.taskInit(function()
    while 1 do
        adc.open(0) -- 模块上的ADC0脚-PA1, 0~2.4v,不要超过范围使用!!!
        adc.open(1) -- 模块上的ADC1脚-PA4, 0~2.4v,不要超过范围使用!!!
        sys.wait(500)
        log.debug("adc", "adc0", adc.read(0))
        log.debug("adc", "adc1", adc.read(1))
        -- 使用完毕后关闭,可以使得休眠电流更低.
        adc.close(0)
        adc.close(1)
        sys.wait(500)
    end
    
end)

return testAdc