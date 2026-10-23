--[[
@module  AirVOC_1000
@summary VOC（AGS02MA）空气质量传感器驱动
@version 1.0
@date    2026.10.20
@usage
本文件为 AGS02MA VOC 传感器驱动：
  1. open(i2c_id)：打开 I2C（id 仅支持 0/1）
  2. get_ppb()：读取 TVOC ppb 值
  3. get_ppm()：读取 TVOC ppm 值
  4. get_quality_level()：读取空气质量等级
  5. close()：关闭 I2C
从机地址 0x1A。
]]

local AirVOC_1000 = {}

local slave_address = 0x1A
local DATA_REG_ADDR = 0x00
local DATA_REG_LEN = 0x05

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

local function read_register(reg, len)
    i2c.send(AirVOC_1000.i2c_id, slave_address, reg)
    local data = i2c.recv(AirVOC_1000.i2c_id, slave_address, len)
    if type(data) == "string" and data:len() == len then
        return data
    end
    log.error("AirVOC_1000 read_register error")
    return false
end

function AirVOC_1000.open(i2c_id)
    if i2c_id == nil then i2c_id = 0 end
    if not (i2c_id == 0 or i2c_id == 1) then
        log.error("AirVOC_1000.open", "invalid i2c_id", i2c_id)
        return false
    end
    AirVOC_1000.i2c_id = i2c_id
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("AirVOC_1000.open", "i2c.setup error", i2c_id)
        return false
    end
    return true
end

function AirVOC_1000.get_ppb()
    local raw = read_register(DATA_REG_ADDR, DATA_REG_LEN)
    if not raw then
        log.error("AirVOC_1000.get_ppb", "read_register error")
        return false
    end
    if crc8({raw:byte(1), raw:byte(2), raw:byte(3), raw:byte(4)}) ~= raw:byte(5) then
        log.error("AirVOC_1000.get_ppb", "crc error")
        return false
    end
    local tvoc = (raw:byte(2) << 16) | (raw:byte(3) << 8) | raw:byte(4)
    return tvoc
end

function AirVOC_1000.get_ppm()
    local ppb = AirVOC_1000.get_ppb()
    if not ppb then
        log.error("AirVOC_1000.get_ppm", "get_ppb error")
        return false
    end
    return ppb / 1000
end

function AirVOC_1000.get_quality_level()
    local ppb = AirVOC_1000.get_ppb()
    if not ppb then
        log.error("AirVOC_1000.get_quality_level", "get_ppb error")
        return false
    end
    if ppb < 200 then return 1, "Excellent"
    elseif ppb < 1000 then return 2, "Good"
    elseif ppb < 3000 then return 3, "Light"
    elseif ppb < 5000 then return 4, "Moderate"
    else return 5, "Severe" end
end

function AirVOC_1000.close()
    i2c.close(AirVOC_1000.i2c_id)
    return true
end

return AirVOC_1000
