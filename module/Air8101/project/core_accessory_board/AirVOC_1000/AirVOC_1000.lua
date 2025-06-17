--本文件中的主机是指I2C主机，具体指Air8101
--本文件中的从机是指I2C从机，具体指AirVOC_1000配件板上的ags02ma VOC(挥发性有机化合物)气体传感器芯片

local AirVOC_1000 = 
{
    -- i2c_id：主机的i2c id；
}   

-- 从机地址为0x1A
local slave_address = 0x1A

-- TVOC数据的寄存器地址
local DATA_REG_ADDR = 0x00
-- TVOC数据的长度
local DATA_REG_LEN = 0x05


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


-- 读取AirVOC_1000的寄存器中指定长度的数据

--reg：number类型；
--         表示AirVOC_1000上的寄存器地址；
--         必须传入，不允许为空；

--返回值：失败返回false；成功返回读取到的指定长度的数据（string类型）
local function read_register(reg, len)
    -- 发送寄存器地址
    i2c.send(AirVOC_1000.i2c_id, slave_address, reg)

    -- sys.wait(20)

    -- 读取应答的数据
    local data = i2c.recv(AirVOC_1000.i2c_id, slave_address, len)

    -- log.info("read_register", data:toHex())

    -- 读取到的数据为指定的长度，则表示读取成功
    -- 否则读取失败
    if type(data)=="string" and data:len()==len then
        return data
    else
        log.error("AirVOC_1000 read_register error", type(data), type(data)=="string" and data:len() or "invalid type", len)
        return false
    end
end


--打开AirVOC_1000；

--i2c_id：number类型；
--        主机使用的I2C ID，用来控制AirVOC_1000；
--        取值范围：仅支持0和1；
--        如果没有传入此参数，则默认为0；

--返回值：成功返回true，失败返回false
function AirVOC_1000.open(i2c_id)
    --如果i2c_id为nil，则赋值为默认值0
    if i2c_id==nil then i2c_id=0 end

    --检查参数的合法性
    if not (i2c_id == 0 or i2c_id == 1) then
        log.error("AirVOC_1000.open", "invalid i2c_id", i2c_id)
        return false
    end

    AirVOC_1000.i2c_id = i2c_id
    
    --初始化I2C
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("AirVOC_1000.open", "i2c.setup error", i2c_id)
        return false
    end

    return true
end

--读取TVOC的ppb值；
--ppb： 代表 parts per billion，即 十亿分之一。 1 ppb TVOC 表示在每 10 亿个体积单位的空气中，含有 1 个体积单位的 TVOC

--返回值：失败返回false；
--       成功返回ppb值（number类型）
function AirVOC_1000.get_ppb()
    --从寄存器DATA_REG_ADDR中读取DATA_REG_LEN长度的数据
    local raw = read_register(DATA_REG_ADDR, DATA_REG_LEN)

    --读取数据出错
    if not raw then
        log.error("AirVOC_1000.get_ppb", "read_register error")
        return false
    end

    --检查校验值
    if crc8({raw:byte(1), raw:byte(2), raw:byte(3), raw:byte(4)}) ~= raw:byte(5) then
        log.error("AirVOC_1000.get_ppb", "crc error")
        return false
    end

    --解析数据: 大端格式
    local tvoc = (raw:byte(2) << 16) | 
                 (raw:byte(3) << 8) | 
                 raw:byte(4)
    
    return tvoc
end

--读取TVOC的ppm值；
--ppm： 代表 parts per million，即 百万分之一。 1 ppm TVOC 表示在每 100 万个体积单位的空气中，含有 1 个体积单位的 TVOC

--返回值：失败返回false；
--       成功返回ppb值（number类型）
function AirVOC_1000.get_ppm()
    --读取ppb值
    local ppb = AirVOC_1000.get_ppb()

    --如果ppb读取失败
    if not ppb then
        log.error("AirVOC_1000.get_ppm", "get_ppb error")
        return false
    end

    --ppb = ppm*1000
    return ppb/1000
    
end

--读取TVOC的空气质量等级；
-- 根据 TVOC 浓度（通常以 ppb 或 ppm 表示）划分的等级，用于评估室内空气质量的优劣和对人体健康的潜在风险;
-- 不同国家、地区或机构的标准可能略有差异，但核心划分逻辑相似：浓度越低，等级越好，风险越低。

--返回值：失败返回false；
--       成功返回空气质量等级值（number类型，数值越小，表示空气质量越好）和空气质量描述（string类型，例如优、良好、轻度污染、中度污染、重度污染）
--           1：表示优
--           2：表示良好
--           3：表示轻度污染
--           4：表示中度污染
--           5：表示重度污染
function AirVOC_1000.get_quality_level()
    --读取ppb值
    local ppb = AirVOC_1000.get_ppb()

    --如果ppb读取失败
    if not ppb then
        log.error("AirVOC_1000.get_qulity_level", "get_ppb error")
        return false
    end

    --根据ppb值计算空气质量等级
    if ppb < 200 then
        return 1,"优"
    elseif ppb < 1000 then
        return 2,"良好"
    elseif ppb < 3000 then
        return 3,"轻度污染"
    elseif ppb < 5000 then
        return 4,"中度污染"
    else
        return 5,"重度污染"
    end 
end


--关闭AirVOC_1000

--返回值：成功返回true，失败返回false
function AirVOC_1000.close()
    --close接口没有返回值，理论上不会关闭失败
    i2c.close(AirVOC_1000.i2c_id)

    return true
end


return AirVOC_1000
