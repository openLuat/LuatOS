--[[
@module aht10
@summary aht10 温湿度传感器
@version 1.0
@date    2022.03.10
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local aht10 = require "aht10"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    aht10.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local aht10_data = aht10.get_data()
        log.info("aht10_data", "aht10_data.RH:"..(aht10_data.RH*100).."%","aht10_data.T"..(aht10_data.T).."℃")
        sys.wait(1000)
    end
end)
]]


local aht10 = {}
local sys = require "sys"
local i2cid

local AHT10_ADDRESS_ADR_LOW       =   0x38

---器件所用地址
local AHT10_INIT                  =   0xE1 --初始化命令
local AHT10_MEASURE               =   0xAC --触发测量命令
local AHT10_SOFT_RESET            =   0xBA --软复位命令,软复位所需时间不超过20毫秒.

local AHT10_STATE                 =   0x71 --状态字.

--[[
aht10初始化
@api aht10.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
aht10.init(0)
]]
function aht10.init(i2c_id)
    i2cid = i2c_id
    sys.wait(40)--40 毫秒等待设备稳定
    i2c.send(i2cid, AHT10_ADDRESS_ADR_LOW, AHT10_SOFT_RESET)--软复位
    sys.wait(20)
    i2c.send(i2cid, AHT10_ADDRESS_ADR_LOW, AHT10_STATE)
    local data = i2c.recv(i2cid, AHT10_ADDRESS_ADR_LOW, 1)
    local _,state = pack.unpack(data, "b")
    if bit.isclear(state,3) then
        i2c.send(i2cid, AHT10_ADDRESS_ADR_LOW, {AHT10_INIT,0x08,0x00})--初始化
    end
    sys.wait(20)
    log.info("aht10 init_ok")
    return true
end

--获取原始数据
local function aht10_get_raw_data()
    local raw_data={Srh=nil,St=nil}
    i2c.send(i2cid, AHT10_ADDRESS_ADR_LOW, {AHT10_MEASURE, 0x33, 0x00})
    sys.wait(80)--等待80毫秒以上
    i2c.send(i2cid, AHT10_ADDRESS_ADR_LOW, AHT10_STATE)
    local data = i2c.recv(i2cid, AHT10_ADDRESS_ADR_LOW, 1)
    local _,state = pack.unpack(data, "b")
    -- if bit.isclear(state,7) then
        local data = i2c.recv(i2cid, AHT10_ADDRESS_ADR_LOW, 6)
        local _, data1, data2, data3, data4, data5, data6 = pack.unpack(data, "b6")
        raw_data.Srh = bit.bor(bit.bor(bit.rshift(data4, 4), bit.lshift(data3, 4)),bit.lshift(data2, 12))
        raw_data.St = bit.bor(bit.bor(bit.lshift(bit.band(data4, 0x0f), 16), bit.lshift(data5, 8)), data6)
    -- end
    return raw_data or 0
end

--[[
获取aht10数据
@api aht10.get_data()
@return table aht10数据
@usage
local aht10_data = aht10.get_data()
log.info("aht10_data", "aht10_data.RH:"..(aht10_data.RH*100).."%","aht10_data.T"..(aht10_data.T).."℃")
]]
function aht10.get_data()
    local aht10_data={RH=nil,T=nil}
    local raw_data = aht10_get_raw_data()
    aht10_data.RH = raw_data.Srh/1048576
    aht10_data.T = raw_data.St/1048576*200-50
    return aht10_data or 0
end

return aht10


