
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart11"
VERSION = "1.0.5"

--[[
注意!!!
这个demo演示的是外挂一个GNSS模组, 不是使用Air8000里面的GNSS芯片
]]

-- 通过boot按键方便刷Air8000S
function PWR8000S(val)
    gpio.set(23, val)
end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

sys.taskInit(function()
    
    -- 首先, 初始化uart11
    uart.setup(11, 115200)
    libgnss.bind(11)
    libgnss.debug(true) -- 调试开关,非必须,生产环境要关掉
    while 1 do
        -- 这段代码是演示注入假数据的, 真实接GNSS模组的话, 这段代码不需要
        log.info("uart11", "注入假的GNSS数据")
        uart.write(11, "$GPGGA,055258.000,3027.4932,N,11424.2381,E,1,06,2.9,101.9,M,-13.6,M,,0000*7E\r\n")
        uart.write(11, "$GPGSA,A,3,28,06,57,58,30,02,,,,,,,4.1,2.9,2.9*35\r\n")
        uart.write(11, "$GPRMC,055258.000,A,3027.4932,N,11424.2381,E,0.00,15.90,120620,,,A*5B\r\n")

        -- 打印定位信息
        log.info("RMC", json.encode(libgnss.getRmc(2) or {}, "7f"))
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
