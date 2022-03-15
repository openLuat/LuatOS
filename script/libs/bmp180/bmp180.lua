--[[
@module bmp180
@summary bmp180 驱动
@version 1.0
@date    2022.03.11
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local bmp180 = require "bmp180"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    bmp180.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local bmp180_data = bmp180.get_data()
        log.info("bmp180_data.temp:"..(bmp180_data.temp).."℃")
        log.info("bmp180_data.press:"..(bmp180_data.press).."hPa")
        log.info("bmp180_data.high:"..(bmp180_data.high).."m")
        sys.wait(1000)
    end
end)
]]


local bmp180 = {}

local sys = require "sys"

local i2cid

local BMP180_ADDRESS_ADR            =   0x77

---器件所用地址
local BMP180_CHIP_ID_CHECK			=   0xD0	
local BMP180_CHIP_ID                =   0x55

local BMP180_RESET			        =   0xE0
local BMP180_RESET_VALUE		    =   0xB6

local BMS180_AC1_ADDR				=   0xAA
local BMP180_AC2_ADDR               =   0xAC  
local BMP180_AC3_ADDR               =   0xAE  
local BMP180_AC4_ADDR               =   0xB0  
local BMP180_AC5_ADDR               =   0xB2  
local BMP180_AC6_ADDR               =   0xB4
local BMP180_B1_ADDR                =   0xB6  
local BMP180_B2_ADDR                =   0xB8  
local BMP180_MB_ADDR                =   0xBA  
local BMP180_MC_ADDR                =   0xBC  
local BMP180_MD_ADDR                =   0xBE

local BMP180_CTRL_ADDR		        =   0xF4 --控制寄存器
local BMP180_CTRL_TEMP		        =   0x2E --转换温度 4.5MS
local BMP180_CTRL_POSS0		        =   0x34 --转换大气压 4.5ms
local BMP180_CTRL_POSS1		        =   0x74 --转换大气压 7.5ms
local BMP180_CTRL_POSS2		        =   0xB4 --转换大气压 13.5ms
local BMP180_CTRL_POSS3		        =   0xF4 --转换大气压 25.5ms

local BMP180_AD_MSB			        =   0xF6 --ADC输出高8位
local BMP180_AD_LSB			        =   0xF7 --ADC输出低8位
local BMP180_AD_XLSB			    =   0xF8 --19位测量时，ADC输出最低3位


local PRESSURE_OF_SEA			    =   101325	-- 参考海平面压强

local AC1,AC2,AC3,AC4,AC5,AC6,B1,B2,MB,MC,MD

--[[
bmp180初始化
@api bmp180.init(i2c_id)
@number i2c_id i2c_id
@return bool   成功返回true
@usage
bmp180.init(0)
]]
function bmp180.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    i2c.send(i2cid, BMP180_ADDRESS_ADR, {BMP180_RESET,BMP180_RESET_VALUE})--软复位
    sys.wait(20)
    i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_CHIP_ID_CHECK)
    local data = i2c.recv(i2cid, BMP180_ADDRESS_ADR, 1)
    if data:byte() == BMP180_CHIP_ID then
        log.info("bmp180 is ok")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMS180_AC1_ADDR)
        _,AC1 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_AC2_ADDR)
        _,AC2 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_AC3_ADDR)
        _,AC3 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_AC4_ADDR)
        _,AC4 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">H")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_AC5_ADDR)
        _,AC5 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">H")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_AC6_ADDR)
        _,AC6 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">H")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_B1_ADDR)
        _,B1 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_B2_ADDR)
        _,B2 = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_MB_ADDR)
        _,MB = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_MC_ADDR)
        _,MC = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        i2c.send(i2cid, BMP180_ADDRESS_ADR, BMP180_MD_ADDR)
        _,MD = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2), ">h")
        return true
    end
    log.info("Can't find bmp180")
    return false
end

--获取温度的原始数据
local function bmp180_get_temp_raw()
    i2c.send(i2cid, BMP180_ADDRESS_ADR,{BMP180_CTRL_ADDR,BMP180_CTRL_TEMP})
    sys.wait(5)
    i2c.send(i2cid, BMP180_ADDRESS_ADR,BMP180_AD_MSB)
    local buffer = i2c.recv(i2cid, BMP180_ADDRESS_ADR, 2)--获取2字节
    local _, temp_raw = pack.unpack(buffer, ">h")
    return temp_raw or 0
end

--获取气压的原始数据
local function bmp180_get_pressure_raw()
    i2c.send(i2cid, BMP180_ADDRESS_ADR,{BMP180_CTRL_ADDR,BMP180_CTRL_POSS3})
    sys.wait(26)
    i2c.send(i2cid, BMP180_ADDRESS_ADR,BMP180_AD_MSB)
    local _, MSB = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 1), "b")
    i2c.send(i2cid, BMP180_ADDRESS_ADR,BMP180_AD_LSB)
    local _, LSB = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 1), "b")
    i2c.send(i2cid, BMP180_ADDRESS_ADR,BMP180_AD_XLSB)
    local _, XLSB = pack.unpack(i2c.recv(i2cid, BMP180_ADDRESS_ADR, 1), "b")
    local pressure_raw = bit.rshift((bit.lshift(MSB, 16)+bit.lshift(LSB, 8)+XLSB),5)
    return pressure_raw or 0
end

--[[
获取bmp180数据
@api bmp180.get_data()
@return table bmp180数据
@usage
local bmp180_data = bmp180.get_data()
log.info("bmp180_data.temp:"..(bmp180_data.temp).."℃")
log.info("bmp180_data.press:"..(bmp180_data.press).."hPa")
log.info("bmp180_data.high:"..(bmp180_data.high).."m")
]]
function bmp180.get_data()
    local bmp180_data={temp=nil,press=nil,high=nil}
    local temp_raw = bmp180_get_temp_raw()
    local pressure_raw = bmp180_get_pressure_raw()
    local P = 0
    local X1 = ((temp_raw - AC6) * AC5) / 32768
    local X2 = (MC * 2048) / (X1 + MD)
    local B5 = X1 + X2 
    temp_raw  = (B5 + 8)/16
    bmp180_data.temp = temp_raw/10
    local B6 = B5 - 4000
    X1 = (B2 * (B6 * B6 /4096))/2048
    X2 = AC2 * B6/2048
    local X3 = X1 + X2 
    local B3 = (((AC1 * 4 + X3)*8) + 2) /4
    X1 = (AC3 * B6)/8192
    X2 = (B1 * (B6 * B6 /4096))/65536
    X3 = ((X1 + X2) + 2)/4
    local B4 = AC4 * (X3 + 32768)/32768
    local B7 = (pressure_raw - B3) * (50000/8)
    if (B7 < 0x80000000)then
        P = (B7 * 2) / B4 
    else
        P = (B7 / B4) * 2
    end
    X1 = (P/256) * (P/256)
    X1 = (X1 * 3038)/65536
    X2 = (-7357 * P)/65536
    P = P + ((X1 + X2 + 3791)/16)
    bmp180_data.press = P /100
    bmp180_data.high = 44330 * (1 - math.pow((P / PRESSURE_OF_SEA), (1.0 / 5.255)))
    return bmp180_data
end

return bmp180



