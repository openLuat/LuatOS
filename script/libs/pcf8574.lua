--[[
@module pcf8574
@summary pcf8574 IO扩展
@version 1.0
@date    2022.07.29
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local pcf8574 = require "pcf8574"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    pcf8574.init(i2cid)--初始化,传入i2c_id
    for i=0,7 do
        print(pcf8574.pin(i))
    end
    pcf8574.pin(0,1)
    for i=0,7 do
        print(pcf8574.pin(i))
    end
end)
]]


local pcf8574 = {}
local sys = require "sys"
local i2cid

local PCF8574_ADDRESS
local PCF8574_ADDRESS_ADR       =   0x20   -- 0x20-0x27
local PCF8574A_ADDRESS_ADR      =   0x38   -- 0x38-0x3F
local PCF8574_DATA

--器件ID检测
local function chip_check()
    for i=0,7 do
        local revData = i2c.recv(i2cid, PCF8574_ADDRESS_ADR+i, 1)
        if revData:byte() ~= nil then
            PCF8574_ADDRESS = PCF8574_ADDRESS_ADR+i
            PCF8574_DATA = revData:byte()
            break
        end
    end
    if PCF8574_ADDRESS==nil then
        for i=0,7 do
            local revData = i2c.recv(i2cid, PCF8574A_ADDRESS_ADR+i, 1)
            if revData:byte() ~= nil then
                PCF8574_ADDRESS = PCF8574A_ADDRESS_ADR+i
                PCF8574_DATA = revData:byte()
                break
            end
        end
    end
    if PCF8574_ADDRESS then
        log.info("i2c", "Device is: pcf8574")
    else
        log.info("i2c", "Can't find pcf8574 device")
        return false
    end
    return true
end

--[[
pcf8574初始化
@api pcf8574.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
pcf8574.init(0)
]]
function pcf8574.init(i2c_id)
    i2cid = i2c_id
    sys.wait(40)--40 毫秒等待设备稳定
    chip_check()
    log.info("pcf8574 init_ok")
    return true
end

--[[
pcf8574 pin控制
@api pcf8574.pin(pin,val)
@number pin 0-7
@number val 0/1 可选,不填则读取电平
@return number 如val未填则返回读取电平
@usage
pcf8574.pin(0，1)
print(pcf8574.pin(0))
]]
function pcf8574.pin(pin,val)
    if val then
        if val==0 then
            PCF8574_DATA = PCF8574_DATA&~(1<<pin)
        else
            PCF8574_DATA = PCF8574_DATA|val<<pin
        end
        i2c.send(i2cid, PCF8574_ADDRESS,string.char(PCF8574_DATA))
    else
        local revData = i2c.recv(i2cid, PCF8574_ADDRESS, 1)
        PCF8574_DATA = revData:byte()
        return (PCF8574_DATA&(1<<pin))>>pin
    end
end

return pcf8574


