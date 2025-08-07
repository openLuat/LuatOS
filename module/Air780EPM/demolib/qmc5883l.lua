--[[
@module qmc5883l
@summary qmc5883l 地磁传感器
@version 1.0
@date    2022.04.12
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local qmc5883l = require "qmc5883l"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    qmc5883l.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local qmc5883l_data = qmc5883l.get_data()
        log.info("qmc5883l_data", qmc5883l_data.x,qmc5883l_data.y,qmc5883l_data.z,qmc5883l_data.heading,qmc5883l_data.headingDegrees)
        sys.wait(1000)
    end
end)
]]


local qmc5883l = {}
local sys = require "sys"
local i2cid

local QMC5883L_ADDRESS_ADR

local QMC5883L_ADDRESS_ADR_LOW   =   0x0C
local QMC5883L_ADDRESS_ADR_HIGH  =   0x0D

local QMC5883L_CHIP_ID_CHECK     =   0x0D
local QMC5883L_CHIP_ID           =   0xFF

---器件所用地址

local QMC5883L_X_LSB             =   0x00
local QMC5883L_X_MSB             =   0x01
local QMC5883L_Y_LSB             =   0x02
local QMC5883L_Y_MSB             =   0x03
local QMC5883L_Z_LSB             =   0x04
local QMC5883L_Z_MSB             =   0x05
local QMC5883L_STATUS            =   0x06
local QMC5883L_T_LSB             =   0x07
local QMC5883L_T_MSB             =   0x08
local QMC5883L_CONTROL1          =   0x09
local QMC5883L_CONTROL2          =   0x0A
local QMC5883L_PERIOD            =   0x0B

--器件ID检测
local function chip_check()
    i2c.send(i2cid, QMC5883L_ADDRESS_ADR_HIGH, QMC5883L_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, QMC5883L_ADDRESS_ADR_HIGH, 1)
    if revData:byte() ~= nil then
        QMC5883L_ADDRESS_ADR = QMC5883L_ADDRESS_ADR_HIGH
    else
        i2c.send(i2cid, QMC5883L_ADDRESS_ADR_LOW, QMC5883L_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, QMC5883L_ADDRESS_ADR_LOW, 1)
        if revData:byte() ~= nil then
            QMC5883L_ADDRESS_ADR = QMC5883L_ADDRESS_ADR_LOW
        else
            log.info("Can't find QMC5883L device")
            return false
        end
    end

    i2c.send(i2cid, QMC5883L_ADDRESS_ADR, QMC5883L_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, QMC5883L_ADDRESS_ADR, 1)
    if revData:byte() == QMC5883L_CHIP_ID then
        log.info("Device i2c id is: QMC5883L")
        return true
    else
        log.info("Can't find QMC5883L device")
        return false
    end
end

--[[
qmc5883l 初始化
@api qmc5883l.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
qmc5883l.init(0)
]]
function qmc5883l.init(i2c_id)
    i2cid = i2c_id
    if chip_check() then
        i2c.send(i2cid, QMC5883L_ADDRESS_ADR, {QMC5883L_PERIOD,0x01})
        i2c.send(i2cid, QMC5883L_ADDRESS_ADR, {QMC5883L_CONTROL1,0x1D})
    end
    return true
end

--[[
获取 qmc5883l 数据
@api qmc5883l.get_data()
@return table qmc5883l 数据
@usage
local qmc5883l_data = qmc5883l.get_data()
log.info("qmc5883l_data", qmc5883l_data.x,qmc5883l_data.y,qmc5883l_data.z,qmc5883l_data.heading,qmc5883l_data.headingDegrees)
]]
function qmc5883l.get_data()
    local qmc5883l_data = {}
    i2c.send(i2cid, QMC5883L_ADDRESS_ADR,QMC5883L_X_LSB)
    local data = i2c.recv(i2cid, QMC5883L_ADDRESS_ADR, 6)
    _, qmc5883l_data.x, qmc5883l_data.y, qmc5883l_data.z = pack.unpack(data, "<h3")
    local heading = math.atan (qmc5883l_data.y ,qmc5883l_data.x)
    qmc5883l_data.heading = heading
    local declinationAngle = 0.0404
    heading = heading+declinationAngle
    if heading < 0 then heading = heading+2*math.pi end
    if heading > 2*math.pi then heading = heading-2*math.pi end
    qmc5883l_data.headingDegrees = heading * 180/math.pi
    return qmc5883l_data
end

return qmc5883l


