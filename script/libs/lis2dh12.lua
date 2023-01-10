--[[
@module lis2dh12
@summary lis2dh12 三轴传感器
@version 1.0
@date    2022.04.20
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local lis2dh12 = require "lis2dh12"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    lis2dh12.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local lis2dh12_data = lis2dh12.get_data()
        log.info("lis2dh12_data", "lis2dh12_data.x"..(lis2dh12_data.x),"lis2dh12_data.y"..(lis2dh12_data.y),"lis2dh12_data.z"..(lis2dh12_data.z),"lis2dh12_data.temp"..(lis2dh12_data.temp))
        sys.wait(1000)
    end
end)
]]


local lis2dh12 = {}

local sys = require "sys"

local i2cid
local LIS2DH12_ADDRESS_ADR

local LIS2DH12_ADDRESS_ADR_LOW      =   0x18
local LIS2DH12_ADDRESS_ADR_HIGH     =   0x19

local LIS2DH12_CHIP_ID_CHECK        =   0x0F
local LIS2DH12_CHIP_ID              =   0x33


---器件所用地址
local LIS2DH12_STATUS_REG_AUX		=   0x07

local LIS2DH12_OUT_TEMP_L           =   0x0C
local LIS2DH12_OUT_TEMP_H           =   0x0D

local LIS2DH12_CTRL_REG0		    =   0x1E
local LIS2DH12_TEMP_CFG_REG		    =   0x1F

local LIS2DH12_CTRL_REG1			=   0x20
local LIS2DH12_CTRL_REG2			=   0x21
local LIS2DH12_CTRL_REG3			=   0x22
local LIS2DH12_CTRL_REG4			=   0x23
local LIS2DH12_CTRL_REG5			=   0x24
local LIS2DH12_CTRL_REG6			=   0x25
local LIS2DH12_REFERENCE			=   0x26
local LIS2DH12_STATUS_REG			=   0x27
local LIS2DH12_OUT_X_L			    =   0x28
local LIS2DH12_OUT_X_H			    =   0x29
local LIS2DH12_OUT_Y_L			    =   0x2A
local LIS2DH12_OUT_Y_H			    =   0x2B
local LIS2DH12_OUT_Z_L			    =   0x2C
local LIS2DH12_OUT_Z_H			    =   0x2D
local LIS2DH12_FIFO_CTRL_REG		=   0x2E
local LIS2DH12_FIFO_SRC_REG		    =   0x2F

local LIS2DH12_INT1_CFG			    =   0x30
local LIS2DH12_INT1_SRC			    =   0x31
local LIS2DH12_INT1_THS			    =   0x32
local LIS2DH12_INT1_DURATION		=   0x33
local LIS2DH12_INT2_CFG			    =   0x34
local LIS2DH12_INT2_SRC			    =   0x35
local LIS2DH12_INT2_THS			    =   0x36

local LIS2DH12_INT2_DURATION	    =   0x37
local LIS2DH12_CLICK_CFG			=   0x38
local LIS2DH12_CLICK_SRC			=   0x39
local LIS2DH12_CLICK_THS		    =   0x3A
local LIS2DH12_TIME_LIMIT			=   0x3B
local LIS2DH12_TIME_LATENCY			=   0x3C
local LIS2DH12_TIME_WINDOW			=   0x3D
local LIS2DH12_ACT_THS			    =   0x3E
local LIS2DH12_ACT_DUR			    =   0x3F

local  LIS2DH12_POWER_DOWN        = 0
local  LIS2DH12_ODR_1Hz           = 1
local  LIS2DH12_ODR_10Hz          = 2
local  LIS2DH12_ODR_25Hz          = 3
local  LIS2DH12_ODR_50Hz          = 4
local  LIS2DH12_ODR_100Hz         = 5
local  LIS2DH12_ODR_200Hz         = 6
local  LIS2DH12_ODR_400Hz         = 7
local  LIS2DH12_ODR_1kHz620_LP    = 8
local  LIS2DH12_ODR_5kHz376_LP    = 9
local  LIS2DH12_ODR_1kHz344_NM_HP = 9

local  LIS2DH12_2g   = 0
local  LIS2DH12_4g   = 1
local  LIS2DH12_8g   = 2
local  LIS2DH12_16g  = 3

local LIS2DH12_HR_12bit   = 0
local LIS2DH12_NM_10bit   = 1
local LIS2DH12_LP_8bit    = 2

local PROPERTY_DISABLE  = 0
local PROPERTY_ENABLE   = 1

local LIS2DH12_TEMP_DISABLE  = 0
local LIS2DH12_TEMP_ENABLE   = 3

--器件ID检测
local function chip_check()
    i2c.send(i2cid, LIS2DH12_ADDRESS_ADR_LOW, LIS2DH12_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, LIS2DH12_ADDRESS_ADR_LOW, 1)
    if revData:byte() ~= nil then
        LIS2DH12_ADDRESS_ADR = LIS2DH12_ADDRESS_ADR_LOW
    else
        i2c.send(i2cid, LIS2DH12_ADDRESS_ADR_HIGH, LIS2DH12_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, LIS2DH12_ADDRESS_ADR_HIGH, 1)
        if revData:byte() ~= nil then
            LIS2DH12_ADDRESS_ADR = LIS2DH12_ADDRESS_ADR_HIGH
        else
            log.info("i2c", "Can't find lis2dh12 device")
            return false
        end
    end
    i2c.send(i2cid, LIS2DH12_ADDRESS_ADR, LIS2DH12_CHIP_ID_CHECK)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, LIS2DH12_ADDRESS_ADR, 1)
    if revData:byte() == LIS2DH12_CHIP_ID then
        log.info("Device i2c id is: lis2dh12")
    else
        log.info("i2c", "Can't find lis2dh12 device")
        return false
    end
    return true
end

local function lis2dh12_read_reg(reg)
    i2c.send(i2cid, LIS2DH12_ADDRESS_ADR,reg)
    return i2c.recv(i2cid, LIS2DH12_ADDRESS_ADR, 1):byte(1)
end

local function lis2dh12_write_reg(reg,val)
    i2c.send(i2cid, LIS2DH12_ADDRESS_ADR,{reg,val})
end

local function lis2dh12_block_data_update_set(val)
    local rdval = lis2dh12_read_reg(LIS2DH12_CTRL_REG4)
    val   = (val==1) and 0x80 or 0x00
    rdval = bit.band(rdval,0x7F)
    rdval = bit.bor(rdval, val)
    lis2dh12_write_reg(LIS2DH12_CTRL_REG4,rdval)
end

local function lis2dh12_data_rate_set(val)
    val = bit.lshift(bit.band(val,0x0F),4)
    local rdval = lis2dh12_read_reg(LIS2DH12_CTRL_REG1)
    rdval = bit.band(rdval,0x0F)
    rdval = bit.bor(rdval, val)
    lis2dh12_write_reg(LIS2DH12_CTRL_REG1,rdval)
end

local function lis2dh12_full_scale_set(val)
    val = bit.lshift(bit.band(val,0x03),4)
    local rdval = lis2dh12_read_reg(LIS2DH12_CTRL_REG4)
    rdval = bit.band(rdval,0xCF)
    rdval = bit.bor(rdval, val)
    lis2dh12_write_reg(LIS2DH12_CTRL_REG4,rdval)
end

local function lis2dh12_temperature_meas_set( val)
    val = bit.lshift(bit.band(val,0x03),6)
    local rdval = lis2dh12_read_reg(LIS2DH12_TEMP_CFG_REG)
    rdval = bit.band(rdval,0x3F)
    rdval = bit.bor(rdval, val)
    lis2dh12_write_reg(LIS2DH12_TEMP_CFG_REG,rdval)
end

local function lis2dh12_operating_mode_set(val)
    local rdval, lpen, hr
    if  val == LIS2DH12_HR_12bit then
        lpen = 0x00
        hr   = 0x08
    elseif val == LIS2DH12_NM_10bit then
        lpen = 0x00
        hr   = 0x00
    elseif val == LIS2DH12_LP_8bit then 
        lpen = 0x80
        hr   = 0x00
    end
    rdval = lis2dh12_read_reg(LIS2DH12_CTRL_REG1)
    rdval = bit.band(rdval,0xF7)
    rdval = bit.bor(rdval, lpen)
    lis2dh12_write_reg(LIS2DH12_CTRL_REG1,rdval)

    rdval = lis2dh12_read_reg(LIS2DH12_CTRL_REG4)
    rdval = bit.band(rdval,0xF7)
    rdval = bit.bor(rdval, hr)
    lis2dh12_write_reg(LIS2DH12_CTRL_REG4,rdval)
end

local function lis2dh12_status_get()
    return lis2dh12_read_reg(LIS2DH12_STATUS_REG)
end

local function lis2dh12_temp_data_ready_get()
    local rdval = lis2dh12_read_reg(LIS2DH12_STATUS_REG_AUX)
    return bit.band(rdval,0x20)
end

local function lis2dh12_acceleration_raw_get()
    local xl,xh,yl,yh,zl,zh,x,y,z
    xl = lis2dh12_read_reg(LIS2DH12_OUT_X_L)
    xh = lis2dh12_read_reg(LIS2DH12_OUT_X_H)
    yl = lis2dh12_read_reg(LIS2DH12_OUT_Y_L)
    yh = lis2dh12_read_reg(LIS2DH12_OUT_Y_H)
    zl = lis2dh12_read_reg(LIS2DH12_OUT_Z_L)
    zh = lis2dh12_read_reg(LIS2DH12_OUT_Z_H)
    x = xh * 256 + xl
    y = yh * 256 + yl
    z = zh * 256 + zl
    return x,y,z
end

local function  lis2dh12_temperature_raw_get()
    local tl,th
    tl = lis2dh12_read_reg(LIS2DH12_OUT_TEMP_L)
    th = lis2dh12_read_reg(LIS2DH12_OUT_TEMP_H)
    return  th * 256 + tl

end

--器件初始化
function lis2dh12.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    if chip_check() then
        lis2dh12_block_data_update_set(PROPERTY_ENABLE)
        lis2dh12_data_rate_set(LIS2DH12_ODR_10Hz)
        lis2dh12_full_scale_set(LIS2DH12_2g)
    
        lis2dh12_temperature_meas_set(LIS2DH12_TEMP_ENABLE)
        lis2dh12_operating_mode_set(LIS2DH12_HR_12bit)
        sys.wait(20)--跳过首次数据
        log.info("lis2dh12 init_ok")
        return true
    end
    return false
end

local function LIS2DH12_FROM_FS_2g_HR_TO_mg(lsb)   return (bit.rshift(lsb,4)) * 1.0  end
local function LIS2DH12_FROM_FS_4g_HR_TO_mg(lsb)   return (bit.rshift(lsb,4)) * 2.0  end
local function LIS2DH12_FROM_FS_8g_HR_TO_mg(lsb)   return (bit.rshift(lsb,4)) * 4.0  end
local function LIS2DH12_FROM_FS_16g_HR_TO_mg(lsb)  return (bit.rshift(lsb,4)) * 12.0 end
local function LIS2DH12_FROM_LSB_TO_degC_HR(lsb)   return (bit.rshift(lsb,6)) / 4.0  +25.0  end

--[[
获取lis2dh12数据
@api lis2dh12.get_data()
@return table lis2dh12数据
@usage
local lis2dh12_data = lis2dh12.get_data()
log.info("lis2dh12_data", "lis2dh12_data.x"..(lis2dh12_data.x),"lis2dh12_data.y"..(lis2dh12_data.y),"lis2dh12_data.z"..(lis2dh12_data.z),"lis2dh12_data.temp"..(lis2dh12_data.temp))
]]

function lis2dh12.get_data()
    local lis2dh12_data={}
    lis2dh12_data.raw_x,lis2dh12_data.raw_y,lis2dh12_data.raw_z = lis2dh12_acceleration_raw_get()
    if lis2dh12_temp_data_ready_get() >0 then
        local temp_raw = lis2dh12_temperature_raw_get()
        lis2dh12_data.temp = LIS2DH12_FROM_LSB_TO_degC_HR(temp_raw)
    end
	-- x, y, z 轴加速度
	local acc_x = math.abs(LIS2DH12_FROM_FS_2g_HR_TO_mg(lis2dh12_data.raw_x))
	local acc_y = math.abs(LIS2DH12_FROM_FS_2g_HR_TO_mg(lis2dh12_data.raw_y))
	local acc_z = math.abs(LIS2DH12_FROM_FS_2g_HR_TO_mg(lis2dh12_data.raw_z))
	
    lis2dh12_data.x = acc_x
    lis2dh12_data.y = acc_y
    lis2dh12_data.z = acc_z

	-- 重力加速度
	lis2dh12_data.acc_g = math.sqrt(math.pow(acc_x, 2) + math.pow(acc_y, 2) + math.pow(acc_z, 2))

    if acc_z > lis2dh12_data.acc_g then
        acc_z = lis2dh12_data.acc_g
    end

	-- angle_z/90 = asin(acc_z/acc_g)/π/2
	local angle_z = math.asin(acc_z/lis2dh12_data.acc_g) * 2 / 3.14 * 90
	angle_z = 90 - angle_z
    if angle_z < 0 then
        angle_z = 0
    end
    lis2dh12_data.angle_z = angle_z

    return lis2dh12_data
end

return lis2dh12



