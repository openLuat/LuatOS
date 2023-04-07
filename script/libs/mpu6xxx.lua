--[[
@module mpu6xxx
@summary mpu6xxx 六轴/九轴传感器 支持 mpu6500,mpu6050,mpu9250,icm2068g,icm20608d
@version 1.0
@date    2022.03.10
@author  Dozingfiretruck
@usage
--支持mpu6500,mpu6050,mpu9250,icm2068g,icm20608d,自动判断器件id,只需要配置i2c id就可以
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local mpu6xxx = require "mpu6xxx"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    mpu6xxx.init(i2cid)--初始化,传入i2c_id
    while 1 do
        sys.wait(100)
        local temp = mpu6xxx.get_temp()--获取温度
        log.info("6050temp", temp)
        local accel = mpu6xxx.get_accel()--获取加速度
        log.info("6050accel", "accel.x",accel.x,"accel.y",accel.y,"accel.z",accel.z)
        local gyro = mpu6xxx.get_gyro()--获取陀螺仪
        log.info("6050gyro", "gyro.x",gyro.x,"gyro.y",gyro.y,"gyro.z",gyro.z)
    end
end)
]]


local mpu6xxx = {}
local sys = require "sys"
local i2cid
local i2cslaveaddr
local deviceid

local MPU6XXX_ADDRESS_AD0_LOW     =   0x68 -- address pin low (GND), default for InvenSense evaluation board
local MPU6XXX_ADDRESS_AD0_HIGH    =   0x69 -- address pin high (VCC)

---器件通讯地址
local MPU6050_WHO_AM_I            =   0x68 -- mpu6050
local MPU6500_WHO_AM_I            =   0x70 -- mpu6500
local MPU9250_WHO_AM_I            =   0x71 -- mpu9250
local ICM20608G_WHO_AM_I          =   0xAF -- icm20608G
local ICM20608D_WHO_AM_I          =   0xAE -- icm20608D

---MPU6XXX所用地址
local MPU6XXX_RA_ACCEL_XOUT_H     =   0x3B
local MPU6XXX_RA_ACCEL_XOUT_L     =   0x3C
local MPU6XXX_RA_ACCEL_YOUT_H     =   0x3D
local MPU6XXX_RA_ACCEL_YOUT_L     =   0x3E
local MPU6XXX_RA_ACCEL_ZOUT_H     =   0x3F
local MPU6XXX_RA_ACCEL_ZOUT_L     =   0x40
local MPU6XXX_RA_TEMP_OUT_H       =   0x41
local MPU6XXX_RA_TEMP_OUT_L       =   0x42
local MPU6XXX_RA_GYRO_XOUT_H      =   0x43
local MPU6XXX_RA_GYRO_XOUT_L      =   0x44
local MPU6XXX_RA_GYRO_YOUT_H      =   0x45
local MPU6XXX_RA_GYRO_YOUT_L      =   0x46
local MPU6XXX_RA_GYRO_ZOUT_H      =   0x47
local MPU6XXX_RA_GYRO_ZOUT_L      =   0x48

local MPU6XXX_ACCEL_SEN           =   16384
local MPU6XXX_GYRO_SEN            =   16384

local MPU60X0_TEMP_SEN            =   340
local MPU60X0_TEMP_OFFSET         =   36.5

local MPU6500_TEMP_SEN            =   333.87
local MPU6500_TEMP_OFFSET         =   21

local MPU6XXX_RA_PWR_MGMT_1     =   0x6B	--电源管理，典型值：0x00(正常启用)
local MPU6XXX_RA_SMPLRT_DIV		=   0x19	--陀螺仪采样率，典型值：0x07(125Hz)
local MPU6XXX_RA_CONFIG			=   0x1A	--低通滤波频率，典型值：0x06(5Hz)
local MPU6XXX_RA_GYRO_CONFIG	=   0x1B	--陀螺仪自检及测量范围，典型值：0x18(不自检，2000deg/s)
local MPU6XXX_RA_ACCEL_CONFIG	=   0x1C	--加速计自检、测量范围及高通滤波频率，典型值：0x01(不自检，2G，5Hz)
local MPU6XXX_RA_FIFO_EN        =   0x23    --fifo使能
local MPU6XXX_RA_INT_PIN_CFG    =   0x37    --int引脚有效电平
local MPU6XXX_RA_INT_ENABLE     =   0x38    --中断使能
local MPU6XXX_RA_USER_CTRL      =   0x6A
local MPU6XXX_RA_PWR_MGMT_1     =   0x6B
local MPU6XXX_RA_PWR_MGMT_2     =   0x6C
local MPU6XXX_RA_WHO_AM_I       =   0x75
--器件ID检测
local function mpu6xxx_check()
    i2c.send(i2cid, MPU6XXX_ADDRESS_AD0_LOW, MPU6XXX_RA_WHO_AM_I)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, MPU6XXX_ADDRESS_AD0_LOW, 1)
    if revData:byte() ~= nil then
        i2cslaveaddr = MPU6XXX_ADDRESS_AD0_LOW
    else
        i2c.send(i2cid, MPU6XXX_ADDRESS_AD0_HIGH, MPU6XXX_RA_WHO_AM_I)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, MPU6XXX_ADDRESS_AD0_HIGH, 1)
        if revData:byte() ~= nil then
            i2cslaveaddr = MPU6XXX_ADDRESS_AD0_HIGH
        else
            log.info("i2c", "Can't find device")
            return false
        end
    end
    i2c.send(i2cid, i2cslaveaddr, MPU6XXX_RA_WHO_AM_I)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, i2cslaveaddr, 1)
    log.info("Device i2c address is:", revData:toHex())
    if revData:byte() == MPU6050_WHO_AM_I then
        deviceid = MPU6050_WHO_AM_I
        log.info("Device i2c id is: MPU6050")
    elseif revData:byte() == MPU6500_WHO_AM_I then
        deviceid = MPU6500_WHO_AM_I
        log.info("Device i2c id is: MPU6500")
    elseif revData:byte() == MPU9250_WHO_AM_I then
        deviceid = MPU9250_WHO_AM_I
        log.info("Device i2c id is: MPU9250")
    elseif revData:byte() == ICM20608G_WHO_AM_I then
        deviceid = ICM20608G_WHO_AM_I
        log.info("Device i2c id is: ICM20608G")
    elseif revData:byte() == ICM20608D_WHO_AM_I then
        deviceid = ICM20608D_WHO_AM_I
        log.info("Device i2c id is: ICM20608D")
    else
        log.info("i2c", "Can't find device")
        return false
    end
    return true
end

--[[
mpu6xxx初始化
@api mpu6xxx.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
mpu6xxx.init(0)
]]
function mpu6xxx.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    if mpu6xxx_check() then
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_PWR_MGMT_1, 0x80})--复位
        sys.wait(100)
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_PWR_MGMT_1, 0x00})--唤醒
        sys.wait(100)
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_SMPLRT_DIV, 0x07})--陀螺仪采样率，典型值：0x07(125Hz)
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_CONFIG, 0x06})--低通滤波频率，典型值：0x06(5Hz)
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_GYRO_CONFIG, 0x18})--陀螺仪自检及测量范围，典型值：0x18(不自检，2000deg/s)
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_ACCEL_CONFIG, 0x01})--加速计自检、测量范围及高通滤波频率，典型值：0x01(不自检，2G，5Hz)
        --i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_FIFO_EN, 0x00})--关闭fifo
        --i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_INT_ENABLE, 0x00})--关闭所有中断
        --i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_USER_CTRL, 0x00})--I2C主模式关闭
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_PWR_MGMT_1, 0x01})--设置x轴的pll为参考
        i2c.send(i2cid, i2cslaveaddr, {MPU6XXX_RA_PWR_MGMT_2, 0x00})--加速度计与陀螺仪开启
        log.info("mpu6xxx init_ok")
        return true
    end
    return false
end
--获取温度的原始数据
local function mpu6xxx_get_temp_raw()
    i2c.send(i2cid, i2cslaveaddr,MPU6XXX_RA_TEMP_OUT_H)--获取的地址
    local buffer = i2c.recv(i2cid, i2cslaveaddr, 2)--获取2字节
    local _, temp = pack.unpack(buffer, ">h")
    return temp or 0
end
--获取加速度计的原始数据
local function mpu6xxx_get_accel_raw()
    local accel={x=nil,y=nil,z=nil}
    i2c.send(i2cid, i2cslaveaddr,MPU6XXX_RA_ACCEL_XOUT_H)--获取的地址
    local x = i2c.recv(i2cid, i2cslaveaddr, 2)--获取6字节
    _,accel.x = pack.unpack(x,">h")
    i2c.send(i2cid, i2cslaveaddr,MPU6XXX_RA_ACCEL_YOUT_H)--获取的地址
    local y = i2c.recv(i2cid, i2cslaveaddr, 2)--获取6字节
    _,accel.y = pack.unpack(y,">h")
    i2c.send(i2cid, i2cslaveaddr,MPU6XXX_RA_ACCEL_ZOUT_H)--获取的地址
    local z = i2c.recv(i2cid, i2cslaveaddr, 2)--获取6字节
    _,accel.z = pack.unpack(z,">h")
    return accel or 0
end
--获取陀螺仪的原始数据
local function mpu6xxx_get_gyro_raw()
    local gyro={x=nil,y=nil,z=nil}
    i2c.send(i2cid, i2cslaveaddr,MPU6XXX_RA_GYRO_XOUT_H)--获取的地址
    local x = i2c.recv(i2cid, i2cslaveaddr, 2)--获取6字节
    _,gyro.x = pack.unpack(x,">h")
    i2c.send(i2cid, i2cslaveaddr,MPU6XXX_RA_GYRO_YOUT_H)--获取的地址
    local y = i2c.recv(i2cid, i2cslaveaddr, 2)--获取6字节
    _,gyro.y = pack.unpack(y,">h")
    i2c.send(i2cid, i2cslaveaddr,MPU6XXX_RA_GYRO_ZOUT_H)--获取的地址
    local z = i2c.recv(i2cid, i2cslaveaddr, 2)--获取6字节
    _,gyro.z = pack.unpack(z,">h")
    return gyro or 0
end

--[[
获取温度数据
@api mpu6xxx.get_temp()
@return number 温度数据
@usage
local temp = mpu6xxx.get_temp()--获取温度
log.info("6050temp", temp)
]]
function mpu6xxx.get_temp()
    local temp=nil
    local tmp = mpu6xxx_get_temp_raw()
    if deviceid == MPU6050_WHO_AM_I then
        temp = tmp / MPU60X0_TEMP_SEN + MPU60X0_TEMP_OFFSET
    else
        temp = tmp / MPU6500_TEMP_SEN + MPU6500_TEMP_OFFSET
    end
    return temp
end

--[[
获取加速度计的数据,单位: mg
@api mpu6xxx.get_accel()
@return table 加速度数据
@usage
local accel = mpu6xxx.get_accel()--获取加速度
log.info("6050accel", "accel.x",accel.x,"accel.y",accel.y,"accel.z",accel.z)
]]
function mpu6xxx.get_accel()
    local accel={x=nil,y=nil,z=nil}
    local tmp = mpu6xxx_get_accel_raw()
    accel.x = tmp.x*1000/MPU6XXX_ACCEL_SEN
    accel.y = tmp.y*1000/MPU6XXX_ACCEL_SEN
    accel.z = tmp.z*1000/MPU6XXX_ACCEL_SEN
    return accel
end

--[[
获取陀螺仪的数据，单位: deg / 10s
@api mpu6xxx.get_gyro()
@return table 陀螺仪数据
@usage
local gyro = mpu6xxx.get_gyro()--获取陀螺仪
log.info("6050gyro", "gyro.x",gyro.x,"gyro.y",gyro.y,"gyro.z",gyro.z)
]]
function mpu6xxx.get_gyro()
    local gyro={x=nil,y=nil,z=nil}
    local tmp = mpu6xxx_get_gyro_raw()
    gyro.x = tmp.x*100/MPU6XXX_GYRO_SEN
    gyro.y = tmp.y*100/MPU6XXX_GYRO_SEN
    gyro.z = tmp.z*100/MPU6XXX_GYRO_SEN
    return gyro
end

return mpu6xxx


