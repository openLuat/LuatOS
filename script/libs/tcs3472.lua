--[[
@module tcs3472
@summary tcs3472 颜色传感器
@version 1.0
@date    2022.03.14
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local tcs3472 = require "tcs3472"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    tcs3472.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local rgb_date = tcs3472.get_rgb()
        log.info("rgb_date.R:",rgb_date.R)
        log.info("rgb_date.G:",rgb_date.G)
        log.info("rgb_date.B:",rgb_date.B)
        log.info("rgb_date.C:",rgb_date.C)
        local lux_date = tcs3472.get_lux(rgb_date)
        log.info("lux_date:",lux_date)
        sys.wait(1000)
    end
end)
]]


local tcs3472 = {}

local sys = require "sys"

local i2cid

local TCS3472_ADDRESS_ADR           =   0x29

---器件所用地址
local TCS3472_CMD_BIT               =   0x80
local TCS3472_CMD_Read_Byte         =   0x00
local TCS3472_CMD_Read_Word         =   0x20
local TCS3472_CMD_Clear_INT         =   0x66    -- RGBC Interrupt flag clear

local TCS3472_ENABLE                =   0x00     
local TCS3472_ENABLE_AIEN           =   0x10    -- RGBC Interrupt Enable 
local TCS3472_ENABLE_WEN            =   0x08    -- Wait enable - Writing 1 activates the wait timer 
local TCS3472_ENABLE_AEN            =   0x02    -- RGBC Enable - Writing 1 actives the ADC, 0 disables it 
local TCS3472_ENABLE_PON            =   0x01    -- Power on - Writing 1 activates the internal oscillator, 0 disables it 

local TCS3472_ATIME                 =   0x01    -- Integration time 
local TCS3472_WTIME                 =   0x03    -- Wait time (if TCS34725_ENABLE_WEN is asserted) 
local TCS3472_WTIME_2_4MS           =   0xFF    -- WLONG0 = 2.4ms   WLONG1 = 0.029s 
local TCS3472_WTIME_204MS           =   0xAB    -- WLONG0 = 204ms   WLONG1 = 2.45s  
local TCS3472_WTIME_614MS           =   0x00    -- WLONG0 = 614ms   WLONG1 = 7.4s   

local TCS3472_AILTL                 =   0x04    -- Clear channel lower interrupt threshold 
local TCS3472_AILTH                 =   0x05
local TCS3472_AIHTL                 =   0x06    -- Clear channel upper interrupt threshold 
local TCS3472_AIHTH                 =   0x07

local TCS3472_PERS                  =   0x0C    -- Persistence register - basic SW filtering mechanism for interrupts 
local TCS3472_PERS_NONE             =   0x00    -- Every RGBC cycle generates an interrupt                                
local TCS3472_PERS_1_CYCLE          =   0x01    -- 1 clean channel value outside threshold range generates an interrupt   
local TCS3472_PERS_2_CYCLE          =   0x02    -- 2 clean channel values outside threshold range generates an interrupt  
local TCS3472_PERS_3_CYCLE          =   0x03    -- 3 clean channel values outside threshold range generates an interrupt  
local TCS3472_PERS_5_CYCLE          =   0x04    -- 5 clean channel values outside threshold range generates an interrupt  
local TCS3472_PERS_10_CYCLE         =   0x05    -- 10 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_15_CYCLE         =   0x06    -- 15 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_20_CYCLE         =   0x07    -- 20 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_25_CYCLE         =   0x08    -- 25 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_30_CYCLE         =   0x09    -- 30 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_35_CYCLE         =   0x0a    -- 35 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_40_CYCLE         =   0x0b    -- 40 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_45_CYCLE         =   0x0c    -- 45 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_50_CYCLE         =   0x0d    -- 50 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_55_CYCLE         =   0x0e    -- 55 clean channel values outside threshold range generates an interrupt 
local TCS3472_PERS_60_CYCLE         =   0x0f    -- 60 clean channel values outside threshold range generates an interrupt 

local TCS3472_CONFIG                =   0x0D
local TCS3472_CONFIG_WLONG          =   0x02    -- Choose between short and long (12x) wait times via TCS34725_WTIME 

local TCS3472_CONTROL               =   0x0F    -- Set the gain level for the sensor 
local TCS3472_CHIP_ID_CHECK         =   0x12    -- 0x44 = TCS34721/TCS34725, 0x4D = TCS34723/TCS34727 
local TCS34721_TCS34725_CHIP_ID     =   0x44
local TCS34723_TCS34727_CHIP_ID     =   0x4D

local TCS3472_STATUS                =   0x13
local TCS3472_STATUS_AINT           =   0x10    -- RGBC Clean channel interrupt 
local TCS3472_STATUS_AVALID         =   0x01    -- Indicates that the RGBC channels have completed an integration cycle 

local TCS3472_CDATAL                =   0x14    -- Clear channel data 
local TCS3472_CDATAH                =   0x15
local TCS3472_RDATAL                =   0x16    -- Red channel data 
local TCS3472_RDATAH                =   0x17
local TCS3472_GDATAL                =   0x18    -- Green channel data 
local TCS3472_GDATAH                =   0x19
local TCS3472_BDATAL                =   0x1A    -- Blue channel data 
local TCS3472_BDATAH                =   0x1B

-- Offset and Compensated
local TCS3472_R_Coef                =   0.136 
local TCS3472_G_Coef                =   1.000
local TCS3472_B_Coef                =   -0.444
local TCS3472_GA                    =   1.0
local TCS3472_DF                    =   310.0
local TCS3472_CT_Coef               =   3810.0
local TCS3472_CT_Offset             =   1391.0

-- Integration Time
local TCS3472_INTEGRATIONTIME_2_4MS =   0xFF    -- 2.4ms - 1 cycle    - Max Count: 1024  
local TCS3472_INTEGRATIONTIME_24MS  =   0xF6    -- 24ms  - 10 cycles  - Max Count: 10240 
local TCS3472_INTEGRATIONTIME_50MS  =   0xEB    -- 50ms  - 20 cycles  - Max Count: 20480 
local TCS3472_INTEGRATIONTIME_101MS =   0xD5    -- 101ms - 42 cycles  - Max Count: 43008 
local TCS3472_INTEGRATIONTIME_154MS =   0xC0    -- 154ms - 64 cycles  - Max Count: 65535 
local TCS3472_INTEGRATIONTIME_700MS =   0x00    -- 700ms - 256 cycles - Max Count: 65535 

--Gain
local TCS3472_GAIN_1X               =   0x00    -- No gain  
local TCS3472_GAIN_4X               =   0x01    -- 4x gain  
local TCS3472_GAIN_16X              =   0x02    -- 16x gain 
local TCS3472_GAIN_60X              =   0x03    -- 60x gain 

local integrationTime_t,gain_t

--[[ 
    Writes an 8-bit value to the specified register/address
]]
local function tcs3472_writebyte(add, data)
    i2c.send(i2cid, TCS3472_ADDRESS_ADR, {bit.bor(add,TCS3472_CMD_BIT), data})
end

--[[ 
    Read an unsigned byte from the I2C device
]]
local function tcs3472_readbyte(add)
    i2c.send(i2cid, TCS3472_ADDRESS_ADR, bit.bor(add,TCS3472_CMD_BIT))
    local revData = i2c.recv(i2cid, TCS3472_ADDRESS_ADR, 1)
    return revData:byte()
end
--[[ 
    Read an unsigned word from the I2C device
]]
local function tcs3472_readword(add)
    i2c.send(i2cid, TCS3472_ADDRESS_ADR, bit.bor(add,TCS3472_CMD_BIT))
    local _,revData = pack.unpack(i2c.recv(i2cid, TCS3472_ADDRESS_ADR, 2), "<H")
    return revData
end

--[[ 
function:   TCS3472 wake up
]]
local function tcs3472_enable()
    tcs3472_writebyte(TCS3472_ENABLE, TCS3472_ENABLE_PON)
    -- sys.wait(3)
    tcs3472_writebyte(TCS3472_ENABLE, bit.bor(TCS3472_ENABLE_PON,TCS3472_ENABLE_AEN))
    sys.wait(3)
end

--[[ 
function:   TCS3472 Sleep
]]
local function tcs3472_disable()
    --Turn the device off to save power
    local reg = tcs3472_readbyte(TCS3472_ENABLE)
    tcs3472_writebyte(TCS3472_ENABLE, bit.band(reg,bit.bnot(bit.bor(TCS3472_ENABLE_PON,TCS3472_ENABLE_AEN))))
end

--[[ 
function:   TCS3472 Set Integration Time
]]
local function tcs3472_set_integration_time(time)
    --Update the timing register
    tcs3472_writebyte(TCS3472_ATIME, time);
    integrationTime_t = time;
end

--[[ 
function:   TCS3472 Set gain
]]
local function tcs3472_set_gain(gain)
    tcs3472_writebyte(TCS3472_CONTROL, gain)
    gain_t = gain;
end

--[[ 
function:   Interrupt Enable
]]
local function tcs3472_interrupt_enable()
    local data = tcs3472_readbyte(TCS3472_ENABLE);
    tcs3472_writebyte(TCS3472_ENABLE, bit.bor(data,TCS3472_ENABLE_AIEN))
end

--[[ 
function:   Interrupt Disable
]]
local function tcs3472_interrupt_disable()
    local data = tcs3472_readbyte(TCS3472_ENABLE);
    tcs3472_writebyte(TCS3472_ENABLE, bit.band(data,bit.bnot(TCS3472_ENABLE_AIEN)))
end

--[[ 
function:   Set Interrupt Persistence register, Interrupts need to be maintained 
            for several cycles
]]
local function tcs3472_set_interrupt_persistence_reg(tcs3472_per)
    if tcs3472_per < 0x10 then
        tcs3472_writebyte(TCS3472_PERS, tcs3472_per)
    else 
        tcs3472_writebyte(TCS3472_PERS, TCS3472_PERS_60_CYCLE)
    end
end

--[[ 
function:   Set Interrupt Threshold
parameter	:
    Threshold_H,Threshold_L: 
    Two 16-bit interrupt threshold registers allow the user to set limits 
    below and above a desired light level. An interrupt can be generated 
    when the Clear data (CDATA) is less than the Clear interrupt low 
    threshold (AILTx) or is greater than the Clear interrupt high 
    threshold (AIHTx)(Clear is the Clear ADC Channel Data Registers)
]]
local function tcs3472_set_interrupt_threshold(threshold_h, threshold_l)
    tcs3472_writebyte(TCS3472_AILTL, bit.band(threshold_l,0xff))
    tcs3472_writebyte(TCS3472_AILTH, bit.rshift(threshold_l, 8))
    tcs3472_writebyte(TCS3472_AIHTL, bit.band(threshold_h,0xff))
    tcs3472_writebyte(TCS3472_AIHTH, bit.rshift(threshold_h, 8))
end

--[[ 
function:   Clear interrupt flag
]]
local function tcs3472_Clear_Interrupt_Flag()
    tcs3472_writebyte(TCS3472_CMD_Clear_INT, 0x00)
end

--器件ID检测
local function tcs3472_check()
    local chip_id = tcs3472_readbyte(TCS3472_CHIP_ID_CHECK)--读器件地址
    if chip_id == TCS34721_TCS34725_CHIP_ID then
        log.info("Device i2c id is: TCS34721/TCS34725")
    elseif chip_id == TCS34723_TCS34727_CHIP_ID then
        log.info("Device i2c id is: TCS34723/TCS34727")
    else
        log.info("i2c", "Can't find TCS3472")
        return false
    end
    return true
end

--[[
tcs3472初始化
@api tcs3472.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
tcs3472.init(0)
]]
function tcs3472.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    if tcs3472_check() then
        --- Set the integration time and gain
        tcs3472_set_integration_time(TCS3472_INTEGRATIONTIME_2_4MS)
	    tcs3472_set_gain(TCS3472_GAIN_60X);
        --- Set Interrupt
        -- tcs3472_set_interrupt_threshold(0xff00, 0x00ff)--Interrupt upper and lower threshold
        -- tcs3472_set_interrupt_persistence_reg(TCS3472_PERS_2_CYCLE)
        tcs3472_enable()
        -- tcs3472_interrupt_enable()

        sys.wait(800)
        log.info("tsc3472 init_ok")
        return true
    end
    return false
end

--[[
获取RGB的数据
@api tcs3472.get_rgb()
@return table tcs3472 rgb数据
@usage
local rgb_date = tcs3472.get_rgb()
log.info("rgb_date.R:",rgb_date.R)
log.info("rgb_date.G:",rgb_date.G)
log.info("rgb_date.B:",rgb_date.B)
log.info("rgb_date.C:",rgb_date.C)
]]
function tcs3472.get_rgb()
    local status = TCS3472_STATUS_AVALID;
    local rgb_date={R=nil,G=nil,B=nil,C=nil}
    status = tcs3472_readbyte(TCS3472_CDATAL)
    if bit.band(status,TCS3472_STATUS_AVALID) then
        rgb_date.C = tcs3472_readword(TCS3472_CDATAL)
        rgb_date.R = tcs3472_readword(TCS3472_RDATAL)
        rgb_date.G = tcs3472_readword(TCS3472_GDATAL)
        rgb_date.B = tcs3472_readword(TCS3472_BDATAL)
    end
    
    if integrationTime_t== TCS3472_INTEGRATIONTIME_2_4MS then
        sys.wait(3)
    elseif integrationTime_t== TCS3472_INTEGRATIONTIME_24MS then
        sys.wait(24)
    elseif integrationTime_t== TCS3472_INTEGRATIONTIME_50MS then
        sys.wait(50)
    elseif integrationTime_t== TCS3472_INTEGRATIONTIME_101MS then
        sys.wait(101)
    elseif integrationTime_t== TCS3472_INTEGRATIONTIME_154MS then
        sys.wait(154)
    elseif integrationTime_t== TCS3472_INTEGRATIONTIME_700MS then
        sys.wait(700)
    end
    return rgb_date
end

--[[
获取lux的数据
@api tcs3472.get_lux()
@table  rgb_data rgb数据
@return number lux数据
@usage
local lux_date = tcs3472.get_lux(rgb_date)
log.info("lux_date:",lux_date)
]]
function tcs3472.get_lux(rgb)
    local lux,cpl,atime_ms
    local gain_temp=1
    local ir=1
    local r_comp,g_comp,b_comp
    atime_ms = ((256 - integrationTime_t) * 2.4)
    if rgb.R + rgb.G + rgb.B > rgb.C then
        ir = (rgb.R + rgb.G + rgb.B - rgb.C) / 2
    else
        ir = 0
    end
    r_comp = rgb.R - ir
    g_comp = rgb.G - ir
    b_comp = rgb.B - ir
    if gain_t == TCS3472_GAIN_1X then
        gain_temp = 1
    elseif gain_t == TCS3472_GAIN_4X then
        gain_temp = 4
    elseif gain_t == TCS3472_GAIN_16X then
        gain_temp = 16
    elseif gain_t == TCS3472_GAIN_60X then
        gain_temp = 60
    end
    cpl = (atime_ms * gain_temp) / (TCS3472_GA * TCS3472_DF)
    lux = (TCS3472_R_Coef * r_comp + TCS3472_G_Coef * g_comp +  TCS3472_B_Coef * b_comp) / cpl
    return lux
end

return tcs3472
