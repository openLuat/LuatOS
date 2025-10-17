
local eeprom = {}

--[[ 
    向EEPEOM中写入一个数据
    @number i2c的id号
    @number 设备地址
    @number 要写入的寄存器地址
    @number 要写入的数据
]]
function eeprom.writebyte(i2cid,EEPROM_DEVICE_ADDRESS,EEPROM_RegAddr,data)
    local result = i2c.transfer(i2cid, EEPROM_DEVICE_ADDRESS, EEPROM_RegAddr .. data, nil, 0)
    sys.wait(5)  -- 等待写入完成
    return result
end

--[[ 
    从EEPEOM中读出一个数据
    @number i2c的id号
    @number 设备地址
    @number 要读出的寄存器地址
    @number 要读出的长度
]]
function eeprom.readbyte(i2cid,EEPROM_DEVICE_ADDRESS,EEPROM_RegAddr,DATA_LEN)
    local result, rxdata = i2c.transfer(i2cid, EEPROM_DEVICE_ADDRESS, EEPROM_RegAddr, nil, DATA_LEN)
    log.info("transfer read: ",rxdata:toHex())
    return result,rxdata  -- 返回读取到的数据
end

return eeprom

