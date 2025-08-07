--[[
@module spl06
@summary spl06_01 气压传感器
@version 1.0
@date    2022.08.01
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local spl06 = require "spl06"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    spl06.init(i2cid)--初始化,传入i2cid
    while 1 do
        local spl06_data = spl06.get_data()
        log.info("spl06_data", "spl06_data.P:"..(spl06_data.P*100),"spl06_data.T"..(spl06_data.T))
        sys.wait(1000)
    end
end)
]]


local spl06 = {}
local sys = require "sys"
local i2cid

local SPL06_ADDRESS_ADR
local SPL06_ADDRESS_ADR_LOW       =   0x76
local SPL06_ADDRESS_ADR_HIGH      =   0x77

---器件所用地址
local SPL06_CHIP_ID_CHECK           = 0x0D
local SPL06_CHIP_ID                 = 0x10

---i2c读数据
local function i2cRead(i2caddr,regaddr,size)
    ---读寄存器
    i2c.send(i2cid,i2caddr,regaddr)
    ---读数据
    --return string.toHex(i2c.recv(i2cId,i2caddr,size))
    local _,data = pack.unpack(i2c.recv(i2cid,i2caddr,size),'b1')
    return data
end

---2个数据和3个数据的高低位顺序不一样---
---i2c读连续地址3个数据
local function i2cReadThreeData(i2caddr,regaddr)
    --log.info("i2cReadThreeData","addr:"..i2caddr.." reg:"..regaddr)
    local msb = i2cRead(i2caddr,regaddr,1)
    local lsb = i2cRead(i2caddr,regaddr+1,1)
    local xlsb = i2cRead(i2caddr,regaddr+2,1)
    if msb == "" or lsb == "" or xlsb == "" or msb == nil or lsb == nil or xlsb == nil then
        msb = 0
        lsb = 0
        xlsb = 0
        log.info("spl06 three data","the data is null")
        --return msb4096+lsb16+xlsb/16
        return msb<<16 + lsb<<8 + xlsb
    else
    --log.info("spl06 three data","msb:"..msb.." lsb:"..lsb.." xlsb:"..xlsb)
        if regaddr ==0x13 then
            return bit.lshift(msb,12) + bit.lshift(lsb,4) + bit.rshift((xlsb&0xF0),4)
        elseif regaddr ==0x15 then
            return bit.lshift((msb&0x0f),16) + bit.lshift(lsb,8) +xlsb
        else
            --return msb4096+lsb16+xlsb/16
            return bit.lshift(msb,16) + bit.lshift(lsb,8) + xlsb
        end
    end
end

---i2c读连续地址2个数据
local function i2cReadTwoData(i2caddr,regaddr)
    local msb = i2cRead(i2caddr,regaddr,1)
    local lsb = i2cRead(i2caddr,regaddr+1,1)
    if lsb == "" or msb == "" or lsb == nil or msb == nil then
        msb = 0
        lsb = 0
        log.info("spl06 two data","the data is null")
        return msb256+lsb
    else
    --log.info("spl06 two data","msb:"..msb.." lsb:"..lsb)
        if regaddr ==0x10 then
            return msb16 + bit.rshift((lsb&0xF0),4)
        elseif regaddr ==0x11 then
            return (msb&0x0f)*256 + lsb
        else
            return msb*256+lsb
        end
    end
end
    

--器件ID检测
local function chip_check()
    i2c.send(i2cid, SPL06_ADDRESS_ADR_HIGH, SPL06_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, SPL06_ADDRESS_ADR_HIGH, 1)
    if revData:byte() ~= nil then
        SPL06_ADDRESS_ADR = SPL06_ADDRESS_ADR_HIGH
    else
        i2c.send(i2cid, SPL06_ADDRESS_ADR_LOW, SPL06_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, SPL06_ADDRESS_ADR_LOW, 1)
        if revData:byte() ~= nil then
            SPL06_ADDRESS_ADR = SPL06_ADDRESS_ADR_LOW
        else
            log.info("i2c", "Can't find adxl34x device")
            return false
        end
    end
    i2c.send(i2cid, SPL06_ADDRESS_ADR, SPL06_CHIP_ID_CHECK)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, SPL06_ADDRESS_ADR, 1)
    if revData:byte() == SPL06_CHIP_ID then
        log.info("Device i2c id is: SPL06")
    else
        log.info("i2c", "Can't find SPL06 device")
        return false
    end
    return true
end

--[[
spl06初始化
@api spl06.init(i2cid)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
spl06.init(0)
]]
function spl06.init(i2cid)
    i2cid = i2c_id
    sys.wait(20)--20 毫秒等待设备稳定
    if chip_check() then
        i2c.send(i2cid, SPL06_ADDRESS_ADR,{0x0c,0x89})--reset
        log.info("spl06 init_ok")
        sys.wait(20)
        return true
    end
    return false
end


--[[
获取spl06数据
@api spl06.get_data()
@return table spl06数据
@usage
local spl06_data = spl06.get_data()
log.info("spl06_data", "spl06_data.P:"..(spl06_data.P*100),"spl06_data.T"..(spl06_data.T))
]]
function spl06.get_data()
    local spl06_data={P=nil,T=nil}
    local Total_Number_24 = 16777216.0
    local Total_Number_20 = 1048576.0
    local Total_Number_16 = 65535.0
    local Total_Number_12 = 4096.0
    ---读取压力补偿值
    local C0  = i2cReadTwoData(SPL06_ADDRESS_ADR,0x10)
    local C1  = i2cReadTwoData(SPL06_ADDRESS_ADR,0x11)
    local C00 = i2cReadThreeData(SPL06_ADDRESS_ADR,0x13)
    local C10 = i2cReadThreeData(SPL06_ADDRESS_ADR,0x15)
    local C01 = i2cReadTwoData(SPL06_ADDRESS_ADR,0x18)
    local C11 = i2cReadTwoData(SPL06_ADDRESS_ADR,0x1a)
    local C20 = i2cReadTwoData(SPL06_ADDRESS_ADR,0x1c)
    local C21 = i2cReadTwoData(SPL06_ADDRESS_ADR,0x1e)
    local C30 = i2cReadTwoData(SPL06_ADDRESS_ADR,0x20)
    if C0>0x800 then
        C0 = C0 - Total_Number_12
    end
    if C1>0x800 then
        C1 = C1 - Total_Number_12
    end
    if C00>0x80000 then
        C00 = C00 - Total_Number_20
    end
    if C10>0x80000 then
        C10 = C10 - Total_Number_20
    end
    if C01>0x8000 then
        C01 = C01 - Total_Number_16
    end
    if C01>0x8000 then
        C11 = C11 - Total_Number_16
    end
    if C20>0x8000 then
        C20 = C20 - Total_Number_16
    end
    if C21>0x8000 then
        C21 = C21 - Total_Number_16
    end
    if C30>0x8000 then
        C30 = C30 - Total_Number_16
    end
    -- log.info("C0 is:",C0)
    -- log.info("C1 is:",C1)
    -- log.info("C00 is:",C00)
    -- log.info("C10 is:",C10)
    -- log.info("C01 is:",C01)
    -- log.info("C11 is:",C11)
    -- log.info("C20 is:",C20)
    -- log.info("C21 is:",C21)
    -- log.info("C30 is:",C30)

    i2c.send(i2cid, SPL06_ADDRESS_ADR,{0x06,0x73})--PRS_CFG PM_RATE_128,TMP_PRC_8
    i2c.send(i2cid, SPL06_ADDRESS_ADR,{0x07,0xF3})--TMP_CFG PM_RATE_128,TMP_PRC_8
    -- id = i2cRead(SPL06_ADDRESS_ADR,0x09,1)
    -- log.info("spl06 id:",id)
    -- i2c.send(i2cid, SPL06_ADDRESS_ADR,{0x09,id|0x08})--oversampling times>8时必须使用
    i2c.send(i2cid, SPL06_ADDRESS_ADR,{0x08,0x07})--连续气压温度测量
    sys.wait(50)

    local adc_P = i2cReadThreeData(SPL06_ADDRESS_ADR,0x00)
    local adc_T = i2cReadThreeData(SPL06_ADDRESS_ADR,0x03)
    if adc_P>0x800000 then
        adc_P = adc_P - Total_Number_24
    end
    if adc_T>0x800000 then
        adc_T = adc_T - Total_Number_24
    end
    --log.info("adc_P is:",adc_P)
    --log.info("adc_T is:",adc_T)
    if adc_P == 0 then
        log.info("adc_P is 0")
        return toint(9996),toint(9996)
    end
    if not adc_P then
        log.info("adc_P is nil")
        return toint(9996),toint(9996)
    end

    local kP = 7864320
    local kT = 7864320
    local Praw_src = adc_P / kP
    local Traw_src = adc_T / kT
    --log.info("Traw_src is:",Traw_src)
    --log.info("Praw_src is:",Praw_src)
    --计算气压
    local qua2 = C10 + Praw_src * (C20 + Praw_src* C30)
    local qua3 = Traw_src * Praw_src * (C11 + Praw_src * C21)
    spl06_data.P = C00 + Praw_src * qua2 + Traw_src * C01 + qua3
    --计算温度
    spl06_data.T = C0*0.5 + Traw_src * C1

    return spl06_data or 0
end

return spl06


