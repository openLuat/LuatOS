
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink"
VERSION = "1.0.4"

-- Air724UG要用SPI1, CS选GPIO10, RDY选GPIO22

airlink.config(airlink.CONF_SPI_ID, 1) -- SPI1
airlink.config(airlink.CONF_SPI_CS, 10) -- GPIO10
airlink.config(airlink.CONF_SPI_RDY, 18) -- GPIO18
airlink.config(airlink.CONF_SPI_SPEED, 20*1000000) -- 20MHz速度

sys.taskInit(function()
    log.info("5秒后开始测试")
    gpio.setup(10, 1, gpio.PULLUP) -- CS
    sys.wait(5000)
    -- airlink.init()
    -- sys.wait(10)
    -- airlink.start(1)
    -- sys.wait(800)
    -- log.info("Airlink初始化完成")
    -- airlink.pause(1)

    local result = spi.setup(
        1,--spi id
        nil,
        1,--CPHA
        1,--CPOL
        8,--数据宽度
        20000000--,--波特率
    )
    sys.wait(1000)
    while 1 do
        gpio.setup(10, 0)
        spi.send(1, "12345678901234567890") -- 发送一个字节, 这里可以是任意值, 只是为了测试SPI通信
        gpio.setup(10, 1)
        sys.wait(100)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
