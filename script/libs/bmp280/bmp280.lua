--[[
@module bmp280
@summary bmp280 驱动
@version 1.0
@date    2022.03.12
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local bmp280 = require "bmp280"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    bmp280.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local bmp280_data = bmp280.get_data()
        log.info("bmp280_data.temp:"..(bmp280_data.temp).."℃")
        log.info("bmp280_data.press:"..(bmp280_data.press).."hPa")
        log.info("bmp280_data.high:"..(bmp280_data.high).."m")
        sys.wait(1000)
    end
end)
]]


local bmp280 = {}

local sys = require "sys"

local i2cid
local BMP280_ADDRESS_ADR

local BMP280_ADDRESS_ADR_LOW        =   0x76
local BMP280_ADDRESS_ADR_HIGH       =   0x77

---器件所用地址
local BMP280_CHIP_ID_CHECK			=   0xD0	
local BMP280_CHIP_ID                =   0x58

local BMP280_RESET			        =   0xE0
local BMP280_RESET_VALUE		    =   0xB6

local BMS280_T1_ADDR				=   0x88
local BMS280_T2_ADDR				=   0x8A
local BMS280_T3_ADDR				=   0x8C
local BMS280_P1_ADDR				=   0x8E
local BMS280_P2_ADDR				=   0x90
local BMS280_P3_ADDR				=   0x90
local BMS280_P4_ADDR				=   0x94
local BMS280_P5_ADDR				=   0x96
local BMS280_P6_ADDR				=   0x98
local BMS280_P7_ADDR				=   0x9A
local BMS280_P8_ADDR				=   0x9C
local BMS280_P9_ADDR				=   0x9E

local BMP280_STATUS_ADDR		    =   0xF3 --状态寄存器
local BMP280_CTRL_ADDR		        =   0xF4 --控制寄存器
local BMP280_CONFIG_ADDR		    =   0xF5 --配置寄存器

local BMP280_SLEEP_MODE             =   0x00 
local BMP280_FORCED_MODE            =   0x01 
local BMP280_NORMAL_MODE            =   0x03 

local BMP280_P_MODE_SKIP            =   0x00 --skipped
local BMP280_P_MODE_1               =   0x01 --x1
local BMP280_P_MODE_2               =   0x02 --x2
local BMP280_P_MODE_3               =   0x03 --x4
local BMP280_P_MODE_4               =   0x04 --x8
local BMP280_P_MODE_5               =   0x05 --x16
local BMP280_T_MODE_SKIP            =   0x00 --skipped
local BMP280_T_MODE_1               =   0x01 --x1
local BMP280_T_MODE_2               =   0x02 --x2
local BMP280_T_MODE_3               =   0x03 --x4
local BMP280_T_MODE_4               =   0x04 --x8
local BMP280_T_MODE_5               =   0x05 --x16

local BMP280_FILTER_OFF             =   0x00 --filter off
local BMP280_FILTER_MODE_1		    =   0x01 --0.223*ODR     x2
local BMP280_FILTER_MODE_2		    =   0x02 --0.092*ODR     x4
local BMP280_FILTER_MODE_3		    =   0x03 --0.042*ODR     x8
local BMP280_FILTER_MODE_4		    =   0x04 --0.021*ODR     x16

local BMP280_T_SB1                  =   0x00 --0.5ms
local BMP280_T_SB2			        =   0x01 --62.5ms
local BMP280_T_SB3			        =   0x02 --125ms
local BMP280_T_SB4			        =   0x03 --250ms
local BMP280_T_SB5			        =   0x04 --500ms
local BMP280_T_SB6			        =   0x05 --1000ms
local BMP280_T_SB7			        =   0x06 --2000ms
local BMP280_T_SB8			        =   0x07 --4000ms

local BMP280_SPI_DISABLE			=   0x00
local BMP280_SPI_ENABLE			    =   0x01

--按照官方手册配置一种模式,此处可自行修改
local osrs_t                        =   BMP280_T_MODE_1
local osrs_p                        =   BMP280_P_MODE_3
local mode                          =   BMP280_NORMAL_MODE
local t_sb                          =   BMP280_T_SB1
local filter                        =   BMP280_FILTER_MODE_4
local spi_en                        =   BMP280_SPI_DISABLE

local ctrl_meas                     =   bit.bor(bit.lshift(osrs_t,5), bit.lshift(osrs_p, 2), mode)
local config                        =   bit.bor(bit.lshift(t_sb,5), bit.lshift(filter, 2), spi_en)

local BMP180_CTRL_TEMP		        =   0x2E --转换温度 4.5MS
local BMP180_CTRL_POSS0		        =   0x34 --转换大气压 4.5ms
local BMP180_CTRL_POSS1		        =   0x74 --转换大气压 7.5ms
local BMP180_CTRL_POSS2		        =   0xB4 --转换大气压 13.5ms
local BMP180_CTRL_POSS3		        =   0xF4 --转换大气压 25.5ms

local BMP280_PRESS_MSB			    =   0xF7
local BMP280_PRESS_LSB			    =   0xF8
local BMP280_PRESS_XLSB			    =   0xF9

local BMP280_TEMP_MSB			    =   0xFA
local BMP280_TEMP_LSB			    =   0xFB
local BMP280_TEMP_XLSB			    =   0xFC

local PRESSURE_OF_SEA			    =   101325	-- 参考海平面压强

local T1,T2,T3,P1,P2,P3,P4,P5,P6,P7,P8,P9

--器件ID检测
local function bmp280_check()
    i2c.send(i2cid, BMP280_ADDRESS_ADR_LOW, BMP280_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, BMP280_ADDRESS_ADR_LOW, 1)
    if revData:byte() ~= nil then
        BMP280_ADDRESS_ADR = BMP280_ADDRESS_ADR_LOW
    else
        i2c.send(i2cid, BMP280_ADDRESS_ADR_HIGH, BMP280_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, BMP280_ADDRESS_ADR_HIGH, 1)
        if revData:byte() ~= nil then
            BMP280_ADDRESS_ADR = BMP280_ADDRESS_ADR_HIGH
        else
            log.info("i2c", "Can't find device")
            return false
        end
    end
    i2c.send(i2cid, BMP280_ADDRESS_ADR, BMP280_CHIP_ID_CHECK)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, BMP280_ADDRESS_ADR, 1)
    if revData:byte() == BMP280_CHIP_ID then
        log.info("Device i2c id is: bmp280")
    else
        log.info("i2c", "Can't find device")
        return false
    end
    return true
end

--[[
bmp280初始化
@api bmp280.init(i2c_id)
@number i2c_id i2c_id
@return bool   成功返回true
@usage
bmp280.init(0)
]]
function bmp280.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    if bmp280_check() then
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_T1_ADDR)
        _,T1 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<H")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_T2_ADDR)
        _,T2 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_T3_ADDR)
        _,T3 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P1_ADDR)
        _,P1 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<H")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P2_ADDR)
        _,P2 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P3_ADDR)
        _,P3 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P4_ADDR)
        _,P4 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P5_ADDR)
        _,P5 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P6_ADDR)
        _,P6 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P7_ADDR)
        _,P7 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P8_ADDR)
        _,P8 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, BMS280_P9_ADDR)
        _,P9 = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 2), "<h")
        i2c.send(i2cid, BMP280_ADDRESS_ADR, {BMP280_RESET,BMP280_RESET_VALUE})--软复位
        sys.wait(20)
        i2c.send(i2cid, BMP280_ADDRESS_ADR, {BMP280_CTRL_ADDR,ctrl_meas})
        i2c.send(i2cid, BMP280_ADDRESS_ADR, {BMP280_CONFIG_ADDR,config})
        log.info("bmp280 init_ok")
        return true
    end
    return false
end

--获取温度的原始数据
local function bmp280_get_temp_raw()
    i2c.send(i2cid, BMP280_ADDRESS_ADR,BMP280_TEMP_MSB)
    local _, MSB = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 1), "b")
    i2c.send(i2cid, BMP280_ADDRESS_ADR,BMP280_TEMP_LSB)
    local _, LSB = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 1), "b")
    i2c.send(i2cid, BMP280_ADDRESS_ADR,BMP280_TEMP_XLSB)
    local _, XLSB = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 1), "b")
    local temp_raw = bit.bor(bit.lshift(MSB,12), bit.lshift(LSB, 4), bit.rshift(XLSB, 4))
    return temp_raw or 0
end

--获取气压的原始数据
local function bmp280_get_pressure_raw()
    i2c.send(i2cid, BMP280_ADDRESS_ADR,BMP280_PRESS_MSB)
    local _, MSB = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 1), "b")
    i2c.send(i2cid, BMP280_ADDRESS_ADR,BMP280_PRESS_LSB)
    local _, LSB = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 1), "b")
    i2c.send(i2cid, BMP280_ADDRESS_ADR,BMP280_PRESS_XLSB)
    local _, XLSB = pack.unpack(i2c.recv(i2cid, BMP280_ADDRESS_ADR, 1), "b")
    local pressure_raw = bit.bor(bit.lshift(MSB,12), bit.lshift(LSB, 4), bit.rshift(XLSB, 4))
    return pressure_raw or 0
end

--[[
获取bmp280数据
@api bmp280.get_data()
@return table bmp280数据
@usage
local bmp280_data = bmp280.get_data()
log.info("bmp280_data.temp:"..(bmp280_data.temp).."℃")
log.info("bmp280_data.press:"..(bmp280_data.press).."hPa")
log.info("bmp280_data.high:"..(bmp280_data.high).."m")
]]
function bmp280.get_data()
    local bmp280_data={temp=nil,press=nil,high=nil}
    local temp_raw = bmp280_get_temp_raw()
    local pressure_raw = bmp280_get_pressure_raw()
    local var1 = (temp_raw/16384.0 - T1/1024.0) * T2
	local var2 = ((temp_raw/131072.0 - T1/8192.0) *(temp_raw/131072.0 - T1/8192.0)) * T3
	local t_fine = var1 + var2
	bmp280_data.temp = (var1 + var2) / 5120.0

    var1 = t_fine/2.0 - 64000.0
	var2 = var1 * var1 * P6 / 32768.0
	var2 = var2 + var1 * P5 * 2.0
	var2 = var2 / 4.0 + P4 * 65536.0
	var1 = (P3 * var1 * var1 / 524288.0 + P2 * var1) / 524288.0
	var1 = (1.0 + var1 / 32768.0)*P1
    local p = 1048576.0 - pressure_raw
    p = (p - (var2 / 4096.0)) * 6250.0 / var1
    var1 = P9 * p * p / 2147483648.0
    var2 = p * P8 / 32768.0
    p = p + (var1 + var2 + P7) / 16.0
    bmp280_data.press = p /100
    bmp280_data.high = 44330 * (1 - math.pow((p / PRESSURE_OF_SEA), (1.0 / 5.255)))
    return bmp280_data
end

return bmp280



