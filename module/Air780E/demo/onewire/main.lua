
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "onewire"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")


sys.taskInit(function()
    sys.wait(3000)

    -- 这里以Air103的接线为例
    -- 其他bsp不一定有pin库, 直接填具体的GPIO号就行
    local ds18b20_pin = pin.PB20
    local dht11_pin = pin.PB10
    while 1 do
        log.info("开始读取ds18b20", "单位0.1摄氏度")
        if onewire then
            local temp = onewire.ds18b20(ds18b20_pin, true, onewire.GPIO)
            log.info("温度值", "onewire库", "ds18b20", temp)
            sys.wait(1000)
        end
        
        if sensor then
            local temp = sensor.ds18b20(ds18b20_pin, true)
            log.info("温度值", "sensor库", "ds18b20", temp)
            sys.wait(1000)
        end

        
        log.info("开始读取dht11", "单位0.01摄氏度和0.01%相对湿度")

        if onewire then
            local hm,temp = onewire.dht1x(dht11_pin, true, onewire.GPIO)
            log.info("温度值", "onewire库", "dht11", temp)
            log.info("湿度", "onewire库", "dht11", hm)
            sys.wait(1000)
        end
        
        if sensor then
            local hm,temp = sensor.dht1x(dht11_pin, true)
            log.info("温度值", "sensor库", "dht11", temp)
            log.info("湿度", "sensor库", "dht11", hm)
            sys.wait(1000)
        end

        if not onewire and not sensor then
            log.warn("固件不含onewire库和sensor库,无法演示")
            sys.wait(1000)
        end
    end

end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
