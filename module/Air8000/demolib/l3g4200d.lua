--[[
@module l3g4200d
@summary l3g4200d 三轴数字陀螺仪传感器
@version 1.0
@date    2022.04.12
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local l3g4200d = require "l3g4200d"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    l3g4200d.init(i2cid)--初始化,传入i2c_id
    while 1 do
    local l3g4200d_data = l3g4200d.get_data()
    log.info("l3g4200d_data", l3g4200d_data.x,l3g4200d_data.y,l3g4200d_data.z)
        sys.wait(1000)
    end
end)
]]


local l3g4200d = {}
local sys = require "sys"
local i2cid

local L3G4200D_ADDRESS_ADR

local L3G4200D_ADDRESS_ADR_LOW       =   0x68
local L3G4200D_ADDRESS_ADR_HIGH      =   0x69

local L3G4200D_CHIP_ID_CHECK         =   0x0F
local L3G4200D_CHIP_ID               =   0xD3

---器件所用地址

local L3G4200D_CTRL_REG1             =   0x20
local L3G4200D_CTRL_REG2             =   0x21
local L3G4200D_CTRL_REG3             =   0x22
local L3G4200D_CTRL_REG4             =   0x23
local L3G4200D_CTRL_REG5             =   0x24
local L3G4200D_REFERENCE             =   0x25
local L3G4200D_OUT_TEMP              =   0x26
local L3G4200D_STATUS_REG            =   0x27
local L3G4200D_OUT_X_L               =   0x28
local L3G4200D_OUT_X_H               =   0x29
local L3G4200D_OUT_Y_L               =   0x2A
local L3G4200D_OUT_Y_H               =   0x2B
local L3G4200D_OUT_Z_L               =   0x2C
local L3G4200D_OUT_Z_H               =   0x2D
local L3G4200D_FIFO_CTRL_REG         =   0x2E
local L3G4200D_FIFO_SRC_REG          =   0x2F
local L3G4200D_INT1_CFG              =   0x30
local L3G4200D_INT1_SRC              =   0x31
local L3G4200D_INT1_TSH_XH           =   0x32
local L3G4200D_INT1_TSH_XL           =   0x33
local L3G4200D_INT1_TSH_YH           =   0x34
local L3G4200D_INT1_TSH_YL           =   0x35
local L3G4200D_INT1_TSH_ZH           =   0x36
local L3G4200D_INT1_TSH_ZL           =   0x37
local L3G4200D_INT1_DURATION         =   0x38

--器件ID检测
local function chip_check()
    i2c.send(i2cid, L3G4200D_ADDRESS_ADR_HIGH, L3G4200D_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, L3G4200D_ADDRESS_ADR_HIGH, 1)
    if revData:byte() ~= nil then
        L3G4200D_ADDRESS_ADR = L3G4200D_ADDRESS_ADR_HIGH
    else
        i2c.send(i2cid, L3G4200D_ADDRESS_ADR_LOW, L3G4200D_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, L3G4200D_ADDRESS_ADR_LOW, 1)
        if revData:byte() ~= nil then
            L3G4200D_ADDRESS_ADR = L3G4200D_ADDRESS_ADR_LOW
        else
            log.info("Can't find L3G4200D device")
            return false
        end
    end

    i2c.send(i2cid, L3G4200D_ADDRESS_ADR, L3G4200D_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, L3G4200D_ADDRESS_ADR, 1)
    if revData:byte() == L3G4200D_CHIP_ID then
        log.info("Device i2c id is: L3G4200D")
        return true
    else
        log.info("Can't find L3G4200D device")
        return false
    end
end

--[[
l3g4200d 初始化
@api l3g4200d.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
l3g4200d.init(0)
]]
function l3g4200d.init(i2c_id)
    i2cid = i2c_id
    if chip_check() then
        i2c.send(i2cid, L3G4200D_ADDRESS_ADR, {L3G4200D_CTRL_REG1,0x0F})
        i2c.send(i2cid, L3G4200D_ADDRESS_ADR, {L3G4200D_CTRL_REG2,0x00})
        i2c.send(i2cid, L3G4200D_ADDRESS_ADR, {L3G4200D_CTRL_REG3,0x08})
        i2c.send(i2cid, L3G4200D_ADDRESS_ADR, {L3G4200D_CTRL_REG4,0x30})
        i2c.send(i2cid, L3G4200D_ADDRESS_ADR, {L3G4200D_CTRL_REG5,0x00})
    end
    return true
end

--[[
获取 l3g4200d 数据
@api l3g4200d.get_data()
@return table l3g4200d 数据
@usage
local l3g4200d_data = l3g4200d.get_data()
log.info("l3g4200d_data", l3g4200d_data.x,l3g4200d_data.y,l3g4200d_data.z)
]]
function l3g4200d.get_data()
    local l3g4200d_data = {}
    i2c.send(i2cid, L3G4200D_ADDRESS_ADR,L3G4200D_OUT_X_L)
    local data = i2c.recv(i2cid, L3G4200D_ADDRESS_ADR, 6)
    _, l3g4200d_data.x, l3g4200d_data.y, l3g4200d_data.z = pack.unpack(data, "<h3")
    return l3g4200d_data
end

return l3g4200d


