local function spiTest(id)
    local txlen = 20480
    local txbuff = zbuff.create(txlen)
    local rxbuff = zbuff.create(txlen)
    local cbTopic = "SPI" .. id .. "DONE"
    local result, devid, succ, errorCode
    if id ~= spi.HSPI_0 then
        spi.setup(id, nil, 0, 0, 8, 24000000)
    else
        spi.setup(id, nil, 0, 0, 8, 48000000)
        log.info("hspi")
    end
    while true do
        log.info("spi"..id, "传输开始")
        result = spi.xfer(id,txbuff,rxbuff,txlen,cbTopic)
        if result then
            result, devid, succ, errorCode = sys.waitUntil(cbTopic, 1000)
        end
        if not result or not succ then
            log.info("spi"..id, "传输失败")
        else
            result,errorCode =  txbuff:isEqual(nil, rxbuff, nil, txlen)
            if not result  then
                log.info("spi"..id, "传输发生错误", errorCode, txbuff[errorCode], rxbuff[errorCode])
            else
                log.info("spi"..id, "传输成功")
            end
        end
        sys.wait(1000)
    end
end

sys.taskInit(spiTest, spi.SPI_1)
sys.taskInit(spiTest, spi.SPI_2)
sys.taskInit(spiTest, spi.HSPI_0)
