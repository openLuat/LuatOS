--[[
@module adxl345
@summary adxl345 驱动
@version 1.0
@date    2022.04.11
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local adxl345 = require "adxl345"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    adxl345.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local adxl345_data = adxl345.get_data()
        log.info("adxl345_data", "adxl345_data.x"..(adxl345_data.x),"adxl345_data.y"..(adxl345_data.y),"adxl345_data.z"..(adxl345_data.z))
        sys.wait(1000)
    end
end)
]]


local adxl345 = {}
local sys = require "sys"
local i2cid

local ADXL345_ADDRESS_ADR

local ADXL345_ADDRESS_ADR_LOW     =   0x53
local ADXL345_ADDRESS_ADR_HIGH    =   0x1D

local ADXL345_CHIP_ID_CHECK       =   0x00
local ADXL345_CHIP_ID             =   0xE5

---器件所用地址

local ADXL345_THRESH_TAP          =   0x1D --敲击阈值
local ADXL345_OFSX                =   0x1E --X轴偏移
local ADXL345_OFSY                =   0x1F --Y轴偏移
local ADXL345_OFSZ                =   0x20 --Z轴偏移
local ADXL345_DUR                 =   0x21 --敲击持续时间
local ADXL345_Latent              =   0x22 --敲击延迟
local ADXL345_Window              =   0x23 --敲击窗口
local ADXL345_THRESH_ACT          =   0x24 --活动阈值
local ADXL345_THRESH_INACT        =   0x25 --静止阈值
local ADXL345_TIME_INACT          =   0x26 --静止时间
local ADXL345_ACT_INACT_CTL       =   0x27 --轴使能控制活动和静止检测
local ADXL345_THRESH_FF           =   0x28 --自由落体阈值
local ADXL345_TIME_FF             =   0x29 --自由落体时间
local ADXL345_TAP_AXES            =   0x2A --单击/双击轴控制
local ADXL345_ACT_TAP_STATUS      =   0x2B --单击/双击源
local ADXL345_BW_RATE             =   0x2C --数据速率及功率模式控制
local ADXL345_POWER_CTL           =   0x2D --省电特性控制
local ADXL345_INT_ENABLE          =   0x2E --中断使能控制
local ADXL345_INT_MAP             =   0x2F --中断映射控制
local ADXL345_INT_SOURCE          =   0x30 --中断源
local ADXL345_DATA_FORMAT         =   0x31 --数据格式控制
local ADXL345_DATAX0              =   0x32 --X轴数据0
local ADXL345_DATAX1              =   0x33 --X轴数据1
local ADXL345_DATAY0              =   0x34 --Y轴数据0
local ADXL345_DATAY1              =   0x35 --Y轴数据1
local ADXL345_DATAZ0              =   0x36 --Z轴数据0
local ADXL345_DATAZ1              =   0x37 --Z轴数据1
local ADXL345_FIFO_CTL            =   0x38 --FIFO控制
local ADXL345_FIFO_STATUS         =   0x39 --FIFO状态


--器件ID检测
local function bmp_check()
    i2c.send(i2cid, ADXL345_ADDRESS_ADR_LOW, ADXL345_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, ADXL345_ADDRESS_ADR_LOW, 1)
    if revData:byte() ~= nil then
        ADXL345_ADDRESS_ADR = ADXL345_ADDRESS_ADR_LOW
    else
        i2c.send(i2cid, ADXL345_ADDRESS_ADR_HIGH, ADXL345_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, ADXL345_ADDRESS_ADR_HIGH, 1)
        if revData:byte() ~= nil then
            ADXL345_ADDRESS_ADR = ADXL345_ADDRESS_ADR_HIGH
        else
            log.info("i2c", "Can't find adxl345 device")
            return false
        end
    end
    i2c.send(i2cid, ADXL345_ADDRESS_ADR, ADXL345_CHIP_ID_CHECK)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, ADXL345_ADDRESS_ADR, 1)
    if revData:byte() == ADXL345_CHIP_ID then
        log.info("Device i2c id is: adxl345")
    else
        log.info("i2c", "Can't find adxl345 device")
        return false
    end
    return true
end

--[[
adxl345 初始化
@api adxl345.init(i2c_id)
@number i2c_id i2c_id
@return bool   成功返回true
@usage
adxl345.init(0)
]]
function adxl345.init(i2c_id)
    i2cid = i2c_id
    sys.wait(40)--40 毫秒等待设备稳定
    if bmp_check() then
        i2c.send(i2cid, ADXL345_ADDRESS_ADR, {ADXL345_BW_RATE,0X0D})
        i2c.send(i2cid, ADXL345_ADDRESS_ADR, {ADXL345_POWER_CTL,0X08})
        i2c.send(i2cid, ADXL345_ADDRESS_ADR, {ADXL345_DATA_FORMAT,0X09})
        log.info("adxl345 init_ok")
        return true
    end
    return false
end

--[[
获取adxl345数据
@api adxl345.get_data()
@return table adxl345数据
@usage
local adxl345_data = adxl345.get_data()
log.info("adxl345_data", "adxl345_data.x"..(adxl345_data.x),"adxl345_data.y"..(adxl345_data.y),"adxl345_data.z"..(adxl345_data.z))
]]
function adxl345.get_data()
    local accel={x=nil,y=nil,z=nil}
    i2c.send(i2cid, ADXL345_ADDRESS_ADR,ADXL345_DATAX0)
    _,accel.x = pack.unpack(i2c.recv(i2cid, ADXL345_ADDRESS_ADR, 2),">h")
    i2c.send(i2cid, ADXL345_ADDRESS_ADR,ADXL345_DATAY0)
    _,accel.y = pack.unpack(i2c.recv(i2cid, ADXL345_ADDRESS_ADR, 2),">h")
    i2c.send(i2cid, ADXL345_ADDRESS_ADR,ADXL345_DATAZ0)
    _,accel.z = pack.unpack(i2c.recv(i2cid, ADXL345_ADDRESS_ADR, 2),">h")
    return accel or 0
end

return adxl345


