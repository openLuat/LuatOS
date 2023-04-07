--[[
@module bh1750
@summary bh1750 数字型光强度传感器
@version 1.0
@date    2022.03.15
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local bh1750 = require "bh1750"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    bh1750.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local bh1750_data = bh1750.read_light()
        log.info("bh1750_read_light", bh1750_data)
        sys.wait(1000)
    end
end)
]]

local bh1750 = {}

local sys = require "sys"

local i2cid

local BH1750_ADDRESS_AD0_LOW     =   0x23 -- address pin low (GND), default for InvenSense evaluation board
local BH1750_ADDRESS_AD0_HIGH    =   0x24 -- address pin high (VCC)

local i2cslaveaddr = BH1750_ADDRESS_AD0_LOW

-- bh1750 registers define
local BH1750_POWER_DOWN   	    =   0x00	-- power down
local BH1750_POWER_ON			=   0x01	-- power on
local BH1750_RESET			    =   0x07	-- reset
local BH1750_CON_H_RES_MODE	    =   0x10	-- Continuously H-Resolution Mode
local BH1750_CON_H_RES_MODE2	=   0x11	-- Continuously H-Resolution Mode2
local BH1750_CON_L_RES_MODE	    =   0x13	-- Continuously L-Resolution Mode
local BH1750_ONE_H_RES_MODE	    =   0x20	-- One Time H-Resolution Mode
local BH1750_ONE_H_RES_MODE2	=   0x21	-- One Time H-Resolution Mode2
local BH1750_ONE_L_RES_MODE	    =   0x23	-- One Time L-Resolution Mode

local function i2c_send(data)
    i2c.send(i2cid, i2cslaveaddr, data)
end

local function i2c_recv(num)
    local revData = i2c.recv(i2cid, i2cslaveaddr, num)
    return revData
end

function bh1750.power_on()
    i2c_send(BH1750_POWER_ON)
end

function bh1750.power_down()
    i2c_send(BH1750_POWER_DOWN)
end

local function bh1750_set_measure_mode(mode,time)
    i2c_send(BH1750_RESET)
    i2c_send(mode)
    sys.wait(time)
end

--[[
bh1750初始化
@api bh1750.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
bh1750.init(0)
]]
function bh1750.init(i2c_id)
    i2cid = i2c_id
    bh1750.power_on()
    log.info("bh1750 init_ok")
    return true
end

--[[
获取bh1750数据
@api bh1750.read_light()
@return number 光照强度数据, 若读取失败会返回nil
@usage
local bh1750_data = bh1750.read_light()
log.info("bh1750_read_light", bh1750_data)
]]
function bh1750.read_light()
    bh1750_set_measure_mode(BH1750_CON_H_RES_MODE, 180)
    -- local _,light = pack.unpack(i2c_recv(2),">h") -- 极端情况下数据溢出导致的光照出现负值, 如string.toHex(i2c_recv(2)) == "FFFF"
    local _,light = pack.unpack(i2c_recv(2),">H")
    if light then
        return light / 1.2
    end
end

return bh1750




