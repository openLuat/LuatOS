--[[
@module ina226
@summary ina226 驱动
@version 1.0
@date    2023.04.06
@author  Dozingfiretruck
@usage
--注意:校准和算法根据自己设计情况进行调节
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local ina226 = require "ina226"

local i2cid = 0
sys.taskInit(function()
    i2c.setup(i2cid, i2c.FAST)
    ina226.init(i2cid)
    while 1 do
        local ina226_data = ina226.get_data()
        log.info("ina226_data", "shunt_voltage",ina226_data.shunt_voltage,"bus_voltage",ina226_data.bus_voltage,"power",ina226_data.power,"current",ina226_data.current)
        sys.wait(1000)
    end
end)
]]
local ina226 = {}
local sys = require "sys"
local i2cid


local INA226_ADDRESS_ADR        =   0x40

--寄存器
local INA226_CONFIG_REG         =   0x00    -- 配置
local INA226_SHUNT_VOL_REG      =   0x01    -- 分压电压
local INA226_BUS_VOL_REG        =   0x02    -- 总线电压
local INA226_POWER_REG          =   0x03    -- 功率
local INA226_CURRENT_REG        =   0x04    -- 电流
local INA226_CALIBRA_REG        =   0x05    -- 校准
local INA226_MASK_REG           =   0x06    -- 屏蔽  启用
local INA226_ALERT_REG          =   0x07    -- 警报
local INA226_MANUFACTURER_ID_REG=   0xFE    -- 制造商ID
local INA226_DIE_ID_REG         =   0xFF    -- 器件ID

local INA226_MANUFACTURER_ID    =   0x5449
local INA226_DIE_ID             =   0x2260

local function ina226_send(...)
    i2c.send(i2cid, INA226_ADDRESS_ADR, {...})
end

local function ina226_recv_short(...)
    i2c.send(i2cid, INA226_ADDRESS_ADR, {...})
    local _, read_data = pack.unpack(i2c.recv(0, INA226_ADDRESS_ADR, 2), ">H")
    return read_data
end

--器件ID检测
local function chip_check()
    if ina226_recv_short(INA226_MANUFACTURER_ID_REG) == INA226_MANUFACTURER_ID and ina226_recv_short(INA226_DIE_ID_REG) == INA226_DIE_ID then
        log.info("Device i2c id is: INA226")
        return true
    else
        log.info("Can't find INA226 device")
    end
end

--[[
ina226初始化
@api ina226.init(ina226_i2c, conf, cal)
@number 挂载ina226的i2c总线id
@table 配置数据, 默认值 {0x47,0x27}, 即0100 0111 0010 0111
@table 校准数据, 默认值 {0x0A,0x00}, 即5.12 / (0.1 * 0.02)
@return bool   成功返回true
@usage
-- 使用默认值进行初始化
ina226.init(0)
]]
function ina226.init(ina226_i2c, conf, cal)
    i2cid = ina226_i2c
    if not conf then
        conf = {0x47,0x27}
    end
    if not cal then
        cal =  {0x0A,0x00}
    end
    if chip_check() then
        ina226_send(INA226_CONFIG_REG,0x80,0x00)
        sys.wait(20)
        ina226_send(INA226_CONFIG_REG, table.unpack(conf))-- 0100 0111 0010 0111
        ina226_send(INA226_CALIBRA_REG, table.unpack(cal))--5.12 / (0.1 * 0.02)
        return true
    end
end

--[[
获取 ina226 分压电压数据
@api ina226.get_data()
@return table ina226 数据
@usage
local ina226_data = ina226.get_data()
log.info("ina226_data", "shunt_voltage",ina226_data.shunt_voltage,"bus_voltage",ina226_data.bus_voltage,"power",ina226_data.power,"current",ina226_data.current)
]]
function ina226.get_data()
    local ina226_data = {}
    local shunt = ina226_recv_short(INA226_SHUNT_VOL_REG)
    -- print("shunt",shunt)
    if shunt == 0 then ina226_data.shunt_voltage = 0 else ina226_data.shunt_voltage = shunt*0.0025 end

    local bus = ina226_recv_short(INA226_BUS_VOL_REG)
    -- print("bus",bus)
    if bus == 0 then ina226_data.bus_voltage = 0 else ina226_data.bus_voltage = bus*1.25 end

    local power = ina226_recv_short(INA226_POWER_REG)
    -- print("power",power)
    if power == 0 then ina226_data.power = 0 else ina226_data.power = power*0.5 end

    local current = ina226_recv_short(INA226_CURRENT_REG)
    -- print("current",current)
    if current == 0 then ina226_data.current = 0 else ina226_data.current = current*0.02 end
    return ina226_data
end

return ina226


