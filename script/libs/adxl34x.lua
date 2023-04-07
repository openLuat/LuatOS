--[[
@module adxl34x
@summary adxl34x 3轴加速度计 目前支持 adxl345 adxl346
@version 1.0
@date    2022.04.11
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local adxl34x = require "adxl34x"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    adxl34x.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local adxl34x_data = adxl34x.get_data()
        log.info("adxl34x_data", "adxl34x_data.x"..(adxl34x_data.x),"adxl34x_data.y"..(adxl34x_data.y),"adxl34x_data.z"..(adxl34x_data.z))
        sys.wait(1000)
    end
end)
]]


local adxl34x = {}
local sys = require "sys"
local i2cid

local ADXL34X_ADDRESS_ADR

local ADXL34X_ADDRESS_ADR_LOW     =   0x53
local ADXL34X_ADDRESS_ADR_HIGH    =   0x1D

local ADXL34X_CHIP_ID_CHECK       =   0x00
local ADXL345_CHIP_ID             =   0xE5
local ADXL346_CHIP_ID             =   0xE6

---器件所用地址

local ADXL34X_THRESH_TAP          =   0x1D --敲击阈值
local ADXL34X_OFSX                =   0x1E --X轴偏移
local ADXL34X_OFSY                =   0x1F --Y轴偏移
local ADXL34X_OFSZ                =   0x20 --Z轴偏移
local ADXL34X_DUR                 =   0x21 --敲击持续时间
local ADXL34X_Latent              =   0x22 --敲击延迟
local ADXL34X_Window              =   0x23 --敲击窗口
local ADXL34X_THRESH_ACT          =   0x24 --活动阈值
local ADXL34X_THRESH_INACT        =   0x25 --静止阈值
local ADXL34X_TIME_INACT          =   0x26 --静止时间
local ADXL34X_ACT_INACT_CTL       =   0x27 --轴使能控制活动和静止检测
local ADXL34X_THRESH_FF           =   0x28 --自由落体阈值
local ADXL34X_TIME_FF             =   0x29 --自由落体时间
local ADXL34X_TAP_AXES            =   0x2A --单击/双击轴控制
local ADXL34X_ACT_TAP_STATUS      =   0x2B --单击/双击源
local ADXL34X_BW_RATE             =   0x2C --数据速率及功率模式控制
local ADXL34X_POWER_CTL           =   0x2D --省电特性控制
local ADXL34X_INT_ENABLE          =   0x2E --中断使能控制
local ADXL34X_INT_MAP             =   0x2F --中断映射控制
local ADXL34X_INT_SOURCE          =   0x30 --中断源
local ADXL34X_DATA_FORMAT         =   0x31 --数据格式控制
local ADXL34X_DATAX0              =   0x32 --X轴数据0
local ADXL34X_DATAX1              =   0x33 --X轴数据1
local ADXL34X_DATAY0              =   0x34 --Y轴数据0
local ADXL34X_DATAY1              =   0x35 --Y轴数据1
local ADXL34X_DATAZ0              =   0x36 --Z轴数据0
local ADXL34X_DATAZ1              =   0x37 --Z轴数据1
local ADXL34X_FIFO_CTL            =   0x38 --FIFO控制
local ADXL34X_FIFO_STATUS         =   0x39 --FIFO状态

local ADXL346_TAP_SIGN            =   0x3A --单击/双击的符号和来源
local ADXL346_ORIENT_CONF         =   0x3B --方向配置
local ADXL346_Orient              =   0x3C --方向状态

--器件ID检测
local function chip_check()
    i2c.send(i2cid, ADXL34X_ADDRESS_ADR_LOW, ADXL34X_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, ADXL34X_ADDRESS_ADR_LOW, 1)
    if revData:byte() ~= nil then
        ADXL34X_ADDRESS_ADR = ADXL34X_ADDRESS_ADR_LOW
    else
        i2c.send(i2cid, ADXL34X_ADDRESS_ADR_HIGH, ADXL34X_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, ADXL34X_ADDRESS_ADR_HIGH, 1)
        if revData:byte() ~= nil then
            ADXL34X_ADDRESS_ADR = ADXL34X_ADDRESS_ADR_HIGH
        else
            log.info("i2c", "Can't find adxl34x device")
            return false
        end
    end
    i2c.send(i2cid, ADXL34X_ADDRESS_ADR, ADXL34X_CHIP_ID_CHECK)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, ADXL34X_ADDRESS_ADR, 1)
    if revData:byte() == ADXL345_CHIP_ID then
        log.info("Device i2c id is: ADXL345")
    elseif revData:byte() == ADXL346_CHIP_ID then
        log.info("Device i2c id is: ADXL346")
    else
        log.info("i2c", "Can't find adxl34x device")
        return false
    end
    return true
end

--[[
adxl34x 初始化
@api adxl34x.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
adxl34x.init(0)
]]
function adxl34x.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)--20 毫秒等待设备稳定
    if chip_check() then
        i2c.send(i2cid, ADXL34X_ADDRESS_ADR, {ADXL34X_BW_RATE,0X0D})
        i2c.send(i2cid, ADXL34X_ADDRESS_ADR, {ADXL34X_POWER_CTL,0X08})
        i2c.send(i2cid, ADXL34X_ADDRESS_ADR, {ADXL34X_DATA_FORMAT,0X09})
        log.info("adxl34x init_ok")
        sys.wait(20)
        return true
    end
    return false
end

--[[
获取 adxl34x 数据
@api adxl34x.get_data()
@return table adxl34x 数据
@usage
local adxl34x_data = adxl34x.get_data()
log.info("adxl34x_data", "adxl34x_data.x"..(adxl34x_data.x),"adxl34x_data.y"..(adxl34x_data.y),"adxl34x_data.z"..(adxl34x_data.z))
]]
function adxl34x.get_data()
    local accel={x=nil,y=nil,z=nil}
    i2c.send(i2cid, ADXL34X_ADDRESS_ADR,ADXL34X_DATAX0)
    _,accel.x = pack.unpack(i2c.recv(i2cid, ADXL34X_ADDRESS_ADR, 2),">h")
    i2c.send(i2cid, ADXL34X_ADDRESS_ADR,ADXL34X_DATAY0)
    _,accel.y = pack.unpack(i2c.recv(i2cid, ADXL34X_ADDRESS_ADR, 2),">h")
    i2c.send(i2cid, ADXL34X_ADDRESS_ADR,ADXL34X_DATAZ0)
    _,accel.z = pack.unpack(i2c.recv(i2cid, ADXL34X_ADDRESS_ADR, 2),">h")
    return accel
end

return adxl34x


