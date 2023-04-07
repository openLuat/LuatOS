--[[
@module tsl2561
@summary tsl2561 光强传感器 
@version 1.0
@date    2022.04.11
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local tsl2561 = require "tsl2561"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    tsl2561.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local tsl2561_data = tsl2561.get_data()
        log.info("tsl2561_data", tsl2561_data.."Lux")
        sys.wait(1000)
    end
end)
]]


local tsl2561 = {}
local sys = require "sys"
local i2cid

local TSL2561_ADDRESS_ADR

local TSL2561_ADDRESS_ADR_LOW     =   0x29
local TSL2561_ADDRESS_ADR_FLOAT   =   0x39
local TSL2561_ADDRESS_ADR_LOW     =   0x49

local TSL2561_CHIP_ID_CHECK       =   0x0A

---器件所用地址

local TSL2561_CONTROL             =   0x80 --Control of basic functions
local TSL2561_TIMING              =   0x81 --Integration time/gain control
local TSL2561_THRESHLOWLOW        =   0x82 --Low byte of low interrupt threshold
local TSL2561_THRESHLOWHIGH       =   0x83 --High byte of low interrupt threshold
local TSL2561_THRESHHIGHLOW       =   0x84 --Low byte of high interrupt threshold
local TSL2561_THRESHHIGHHIGH      =   0x85 --High byte of high interrupt threshold
local TSL2561_INTERRUPT           =   0x86 --Interrupt control
local TSL2561_CRC                 =   0x88 --Factory test — not a user register
local TSL2561_ID                  =   0x8A --Part number/ Rev ID
local TSL2561_DATA0LOW            =   0x8C --Low byte of ADC channel 0
local TSL2561_DATA0HIGH           =   0x8D --High byte of ADC channel 0
local TSL2561_DATA1LOW            =   0x8E --Low byte of ADC channel 1
local TSL2561_DATA1HIGH           =   0x8F --High byte of ADC channel 1

local TSL2561_PowerUp             =   0x03
local TSL2561_PowerDown           =   0x00

--最后两位设置积分时间，NOMINAL INTEGRATION TIME 13.7ms 101ms 402ms
local TSL2561_TIMING_13MS	      =   0x00	--积分时间13.7ms
local TSL2561_TIMING_101MS	      =   0x01  --积分时间101ms
local TSL2561_TIMING_402MS	      =   0x02  --积分时间402ms

local TSL2561_TIMING_GAIN_1X      =   0x00 --增益1
local TSL2561_TIMING_GAIN_16X     =   0x10 --增益16倍

--器件ID检测
local function chip_check()
    i2c.send(i2cid, TSL2561_ADDRESS_ADR_LOW, TSL2561_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, TSL2561_ADDRESS_ADR_LOW, 1)
    if revData:byte() ~= nil then
        TSL2561_ADDRESS_ADR = TSL2561_ADDRESS_ADR_LOW
    else
        i2c.send(i2cid, TSL2561_ADDRESS_ADR_LOW, TSL2561_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, TSL2561_ADDRESS_ADR_LOW, 1)
        if revData:byte() ~= nil then
            TSL2561_ADDRESS_ADR = TSL2561_ADDRESS_ADR_LOW
        else
            i2c.send(i2cid, TSL2561_ADDRESS_ADR_FLOAT, TSL2561_CHIP_ID_CHECK)--读器件地址
            sys.wait(50)
            local revData = i2c.recv(i2cid, TSL2561_ADDRESS_ADR_FLOAT, 1)
            if revData:byte() ~= nil then
                TSL2561_ADDRESS_ADR = TSL2561_ADDRESS_ADR_FLOAT
            else
                log.info("i2c", "Can't find tsl2561 device")
                return false
            end
        end
    end
    sys.wait(50)
    i2c.send(i2cid, TSL2561_ADDRESS_ADR, TSL2561_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, TSL2561_ADDRESS_ADR, 1)
    local id = revData:toHex()
    log.info("Device i2c id is:",id)
    return true
end

--[[
tsl2561 初始化
@api tsl2561.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
tsl2561.init(0)
]]
function tsl2561.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)--20 毫秒等待设备稳定
    if chip_check() then
        i2c.send(i2cid, TSL2561_ADDRESS_ADR, {TSL2561_CONTROL,TSL2561_PowerUp})
        i2c.send(i2cid, TSL2561_ADDRESS_ADR, {TSL2561_TIMING,TSL2561_TIMING_402MS|TSL2561_TIMING_GAIN_16X})
        log.info("tsl2561 init_ok")
        sys.wait(20)
        return true
    end
    return false
end

--[[
获取 tsl2561 数据
@api tsl2561.get_data()
@return table tsl2561 数据
@usage
local tsl2561_data = tsl2561.get_data()
log.info("tsl2561_data", tsl2561_data.."Lux")
]]
function tsl2561.get_data()
    local Lux
    i2c.send(i2cid, TSL2561_ADDRESS_ADR,TSL2561_DATA0LOW)
    local _, ch0, ch1 = pack.unpack(i2c.recv(i2cid, TSL2561_ADDRESS_ADR, 4),"<HH")
    if 0.0 < ch1/ch0 and ch1/ch0 <= 0.50 then
		Lux = 0.0304*ch0 - 0.062*ch0*math.pow(ch1/ch0,1.4)
    end
    if 0.50 < ch1/ch0 and ch1/ch0 <= 0.61 then
        Lux = 0.0224*ch0 - 0.031*ch1
    end
    if 0.61 < ch1/ch0 and ch1/ch0 <= 0.80 then
        Lux = 0.0128*ch0 - 0.0153*ch1
    end
    if 0.80 < ch1/ch0 and ch1/ch0 <= 1.30 then
        Lux = 0.00146*ch0 - 0.00112*ch1
    end
    if ch1/ch0 > 1.30 then
        Lux = 0;
    end
    return Lux or 0
end

return tsl2561


