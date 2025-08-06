--[[
@module ak8963
@summary ak8963 地磁传感器
@version 1.0
@date    2023.06.07
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local ak8963 = require "ak8963"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    ak8963.init(i2cid)--初始化,传入i2c_id
    while 1 do
        sys.wait(100)
        local mag = ak8963.get_mag()--获取地磁仪
        log.info("ak8963 mag", "mag.x",mag.x,"mag.y",mag.y,"mag.z",mag.z)
    end
end)
]]


local ak8963 = {}
local sys = require "sys"
local i2cid
local i2cslaveaddr
local deviceid

local AK8963_ADDRESS_AD0_LOW     =   0x0C  
local AK8963_ADDRESS_AD0_HIGH    =   0x0D  

---器件通讯地址
local AK8963_WHO_AM_I            =   0x48 -- AK8963

---AK8963所用地址
-- Read-only Reg
local AK8963_RA_WHO_AM_I         =   0x00
local AK8963_REG_INFO            =   0x01
local AK8963_REG_ST1             =   0x02
local AK8963_REG_HXL             =   0x03
local AK8963_REG_HXH             =   0x04
local AK8963_REG_HYL             =   0x05
local AK8963_REG_HYH             =   0x06
local AK8963_REG_HZL             =   0x07
local AK8963_REG_HZH             =   0x08
local AK8963_REG_ST2             =   0x09
-- Write/Read Reg
local AK8963_REG_CNTL1           =   0x0A
local AK8963_REG_CNTL2           =   0x0B
local AK8963_REG_ASTC            =   0x0C
local AK8963_REG_TS1             =   0x0D
local AK8963_REG_TS2             =   0x0E
local AK8963_REG_I2CDIS          =   0x0F
-- Read-only Reg (ROM)
local AK8963_REG_ASAX            =   0x10
local AK8963_REG_ASAY            =   0x11
local AK8963_REG_ASAZ            =   0x12
-- Status
local AK8963_STATUS_DRDY         =   0x01
local AK8963_STATUS_DOR          =   0x02
local AK8963_STATUS_HOFL         =   0x08

local AK8963_ASAX
local AK8963_ASAY
local AK8963_ASAZ

--器件ID检测
local function ak8963_check()
    i2c.send(i2cid, AK8963_ADDRESS_AD0_LOW, AK8963_RA_WHO_AM_I)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, AK8963_ADDRESS_AD0_LOW, 1)
    if revData:byte() ~= nil then
        i2cslaveaddr = AK8963_ADDRESS_AD0_LOW
    else
        i2c.send(i2cid, AK8963_ADDRESS_AD0_HIGH, AK8963_RA_WHO_AM_I)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, AK8963_ADDRESS_AD0_HIGH, 1)
        if revData:byte() ~= nil then
            i2cslaveaddr = AK8963_ADDRESS_AD0_HIGH
        else
            log.info("i2c", "Can't find device")
            return false
        end
    end
    i2c.send(i2cid, i2cslaveaddr, AK8963_RA_WHO_AM_I)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, i2cslaveaddr, 1)
    log.info("Device i2c address is:", revData:toHex())
    if revData:byte() == AK8963_WHO_AM_I then
        deviceid = AK8963_WHO_AM_I
        log.info("Device i2c id is: AK8963")
    else
        log.info("i2c", "Can't find device")
        return false
    end
    return true
end

--[[
ak8963初始化
@api ak8963.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
ak8963.init(0)
]]
function ak8963.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    if ak8963_check() then
        i2c.send(i2cid, i2cslaveaddr, {AK8963_REG_CNTL1, 0x0F})
        i2c.send(i2cid, i2cslaveaddr,AK8963_REG_ASAX)
        AK8963_ASAX = i2c.recv(i2cid, i2cslaveaddr, 1):byte()
        i2c.send(i2cid, i2cslaveaddr,AK8963_REG_ASAY)
        AK8963_ASAY = i2c.recv(i2cid, i2cslaveaddr, 1):byte()
        i2c.send(i2cid, i2cslaveaddr,AK8963_REG_ASAZ)
        AK8963_ASAZ = i2c.recv(i2cid, i2cslaveaddr, 1):byte()
        i2c.send(i2cid, i2cslaveaddr, {AK8963_REG_CNTL1, 0x10})
        sys.wait(10)
        log.info("ak8963 init_ok")
        return true
    end
    return false
end

--获取地磁计的原始数据
local function ak8963_get_mag_raw()
    local mag={x=nil,y=nil,z=nil}
    i2c.send(i2cid, i2cslaveaddr,AK8963_REG_HXL)
    local x = i2c.recv(i2cid, i2cslaveaddr, 2)
    _,mag.x = pack.unpack(x,"<h")
    i2c.send(i2cid, i2cslaveaddr,AK8963_REG_HYL)
    local y = i2c.recv(i2cid, i2cslaveaddr, 2)
    _,mag.y = pack.unpack(y,"<h")
    i2c.send(i2cid, i2cslaveaddr,AK8963_REG_HZL)
    local z = i2c.recv(i2cid, i2cslaveaddr, 2)
    _,mag.z = pack.unpack(z,"<h")
    return mag or 0
end


--[[
获取地磁仪的数据
@api ak8963.get_mag()
@return table 地磁仪数据
@usage
local mag = ak8963.get_mag()--获取地磁仪
log.info("ak8963 mag", "mag.x",mag.x,"mag.y",mag.y,"mag.z",mag.z)
]]
function ak8963.get_mag()
    local mag={x=nil,y=nil,z=nil}
    i2c.send(i2cid, i2cslaveaddr, {AK8963_REG_CNTL1, 0x11})
    sys.wait(10)
    local tmp = ak8963_get_mag_raw()
    mag.x = tmp.x*((AK8963_ASAX-128)*0.5/128+1)
    mag.y = tmp.y*((AK8963_ASAY-128)*0.5/128+1)
    mag.z = tmp.z*((AK8963_ASAZ-128)*0.5/128+1)
    return mag
end

return ak8963


