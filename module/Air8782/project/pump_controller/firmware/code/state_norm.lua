--[[
@module  state_norm
@summary 数据规整（倍率换算 + 停机/故障置零 + 时间戳）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md 5.2/5.3：
1. 按 modbus_map 的换算系数把原始寄存器值转为实际值；
2. 当 devstate 为“停止(3)”或“故障(5)”时，将 outA/outV/setHz/outkw/outHz 置 0；
3. 补充 timestamp（os.time()）。
本模块有对外接口，末尾 return M。
]]

local modbus_map = require("modbus_map")

local M = {}

--[[
把原始寄存器值规整为上报数据表
@param raw table 形如 { [key]=原始值 }（某项采集失败则为 nil）
@return table 上报数据表 { outHz, setHz, ..., devstate, timestamp }
]]
function M.normalize(raw)
    local data = {}

    -- 1. 倍率换算
    for _, f in ipairs(modbus_map.fields) do
        local v = raw[f.key]
        if v ~= nil then
            data[f.key] = v * f.scale
        end
    end

    -- 2. 停机/故障置零
    local ds = data.devstate
    if ds == 3 or ds == 5 then
        data.outA  = 0
        data.outV  = 0
        data.setHz = 0
        data.outkw = 0
        data.outHz = 0
    end

    -- 3. 时间戳
    data.timestamp = os.time()
    return data
end

return M
