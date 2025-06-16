--本文件中的主机是指I2C主机，具体指Air8101
--本文件中的从机是指I2C从机，具体指AirSHT30_1000配件板上的sht30温湿度传感器芯片

local AirSHT30_1000 = 
{
    -- i2c_id：主机的i2c id；
}   

-- 从机地址为0x44
local slave_addr = 0x44



-- 计算数据表data中所有数据元素的crc8校验值
local function crc8(data)
    local crc = 0xFF
    for i = 1, #data do
        crc = bit.bxor(crc, data[i])
        for j = 1, 8 do
            crc = crc * 2
            if crc >= 0x100 then
                crc = bit.band(bit.bxor(crc, 0x31), 0xff)
            end
        end
    end
    return crc
end


--打开AirSHT30_1000；

--i2c_id：number类型；
--        主机使用的I2C ID，用来控制AirSHT30_1000；
--        取值范围：仅支持0和1；
--        如果没有传入此参数，则默认为0；

--返回值：成功返回true，失败返回false
function AirSHT30_1000.open(i2c_id)
    --如果i2c_id为nil，则赋值为默认值0
    if i2c_id==nil then i2c_id=0 end

    --检查参数的合法性
    if not (i2c_id == 0 or i2c_id == 1) then
        log.error("AirSHT30_1000.open", "invalid i2c_id", i2c_id)
        return false
    end

    AirSHT30_1000.i2c_id = i2c_id
    
    --初始化I2C
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("AirSHT30_1000.open", "i2c.setup error", i2c_id)
        return false
    end

    return true
end

--读取温湿度数据；

--返回值：失败返回false；
--       成功返回两个值，第一个为摄氏温度值（number类型，例如23.6表示23.6摄氏度），第二个为百分比湿度值（number类型，例如67表示67%的湿度）
function AirSHT30_1000.read()

    -- 发送启动测量命令（高精度）
    i2c.send(AirSHT30_1000.i2c_id, slave_addr, {0x24, 0x00})
        
    -- 等待测量完成（SHT30高精度测量需~15ms）
    sys.wait(20)
    
    -- 读取6字节数据（温度高/低 + CRC，湿度高/低 + CRC）
    local data = i2c.recv(AirSHT30_1000.i2c_id, slave_addr, 6)

    -- 如果没有读取到6字节数据
    if type(data)~="string" or data:len()~=6 then
        log.error("AirSHT30_1000.read", "i2c.recv error")
        return false
    end

    -- log.info("AirSHT30_1000.read", data:toHex())

    --如果校验值正确
    if crc8({data:byte(1), data:byte(2)}) == data:byte(3) and crc8({data:byte(4), data:byte(5)}) == data:byte(6) then 
        -- 提取原始温度值
        local temp_raw = (data:byte(1) << 8) | data:byte(2)
        -- 提取原始湿度值
        local hum_raw = (data:byte(4) << 8) | data:byte(5)
        
        -- 转换为实际值（根据SHT30数据手册公式）
        local temprature = (-45 + 175 * temp_raw / 65535.0)
        local humidity = (100 * hum_raw / 65535.0)
        
        -- 打印输出结果（保留2位小数）
        -- log.info("AirSHT30_1000.read", "temprature", string.format("%.2f ℃", temprature))
        -- log.info("AirSHT30_1000.read", "temprature", string.format("%.2f %%RH", humidity))

        return temprature, humidity
    else
        log.error("AirSHT30_1000.read", "crc error", i2c_id)
        return false
    end
end


--关闭AirSHT30_1000

--返回值：成功返回true，失败返回false
function AirSHT30_1000.close()
    --close接口没有返回值，理论上不会关闭失败
    i2c.close(AirSHT30_1000.i2c_id)

    return true
end


return AirSHT30_1000
