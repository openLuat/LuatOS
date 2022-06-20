-- 测试SHT30，addr脚接地
--7bit地址，不包含最后一位读写位
local addr = 0x44
-- 按照实际芯片更改编号哦
local i2cid = 0

sys.taskInit(function()
    i2c.setup(0, i2c.SLOW)
    local cbTopic = "I2CDONE"
    local txbuff = zbuff.create(8)
    local rxbuff = zbuff.create(8)
    txbuff:pack(">H", 0x2c0d)-- 单次中等精度测量命令
    local result, devid, succ, errorcode, crc1, crc2, buff,T,H
    while true do
        result = i2c.xfer(i2cid,addr,txbuff,nil,0,cbTopic,100)
        if result then 
            result, devid, succ, errorcode = sys.waitUntil(cbTopic) 
        else
            log.error("启动i2c失败")
        end
        if not result or not succ then 
            log.error("sht30不存在", errorcode)
            sys.wait(1000)
        else
            sys.wait(1000)
            result = i2c.xfer(i2cid, addr, nil, rxbuff, 6, cbTopic, 100)
            if result then 
                result, devid, succ, errorcode = sys.waitUntil(cbTopic) 
            end
            if not result or not succ then 
                log.error("sht30获取数据失败", errorcode)
            else
                crc1 = crypto.crc8(rxbuff:query(0,2), 0x31, 0xff, false)
                crc2 = crypto.crc8(rxbuff:query(3,2), 0x31, 0xff, false)
                if crc1 == rxbuff[2] and crc2 == rxbuff[5] then
                    T = rxbuff:query(0, 2, true) * 175.0 / 65535.0 - 45.0
                    H = rxbuff:query(3, 2, true) * 100.0 /65535.0
                    log.info("温度", T, "湿度", H)
                else
                    log.error("sht30 数据校验错误")
                end
            end
        end
        --log.info(os.date("%Y-%m-%d %H:%M:%S"))
    end

end)