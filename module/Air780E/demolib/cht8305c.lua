--[[
@module cht8305c
@summary cht8305c 温湿度传感器
@version 1.0
@date    2023.07.21
@author  wendal
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local cht8305c = require "cht8305c"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    cht8305c.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local data = cht8305c.get_data()
        if data and data.RH then
            local tmp = string.format("RH: %.2f T: %.2f ℃", data.RH*100, data.T)
            log.info("cht8305c", tmp)
        else
            log.info("cht8305c", "读取失败")
        end
        sys.wait(1000)
    end
end)
]]


local cht8305c = {}
local sys = require "sys"
local i2cid

local cht8305c_addr       =   0x40

--[[
cht8305c初始化
@api cht8305c.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
cht8305c.init(0)
]]
function cht8305c.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    local Manufacture = i2c.readReg(i2cid, cht8305c_addr, 0xFE, 2)
    -- log.info("cht8305c", "Manufacture", Manufacture and Manufacture:toHex() or "??")
    if Manufacture and Manufacture:byte() == 0x59 then
        log.info("cht8305c init_ok")
        return true
    else
        log.info("cht8305c init_fail")
    end
end

--[[
获取cht8305c数据
@api cht8305c.get_data()
@return table cht8305c数据
]]
function cht8305c.get_data()
    local data={RH=nil,T=nil}
    i2c.send(i2cid, cht8305c_addr, string.char(0))
    sys.wait(22)
    local tmp = i2c.recv(i2cid, cht8305c_addr, 4)
    -- log.info("CHT8305C", tmp and tmp:toHex() or "??")
    if tmp and #tmp == 4 then
        local _, temp, hum = pack.unpack(tmp, ">HH")
        data.T = (165 * temp) / 65535.0 - 40
        data.RH = hum / 65535.0
        -- log.info("CHT8305C", temp, hum)
    end
    return data
end

return cht8305c
