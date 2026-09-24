--[[
@module  app_main
@summary 业务编排层（数据状态汇总与调度）（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage
本文件为业务逻辑编排层，负责汇总设备运行状态（温湿度/继电器/定位），
订阅各数据源更新事件并缓存，提供统一的设备状态查询接口。

对外接口：
1、app_main.get_state()  → 获取当前设备状态汇总表
]]

local relay_ctrl = require "relay_ctrl"

local M = {}

-- 继电器状态初始数组：按实际路数动态构造（路数唯一来源为 relay_ctrl.CH_COUNT），
-- 换 8 路模块时此处无需改动
local init_relay = {}
for i = 1, relay_ctrl.get_channel_count() do init_relay[i] = 0 end

-- 设备状态汇总表
local state = {
    temperature = 0,               -- 温度
    humidity = 0,                  -- 湿度
    relay = init_relay,            -- 继电器状态数组（1-based，长度 = 实际路数）
    lat = "",                      -- 纬度
    lng = "",                      -- 经度
}

--[[
温湿度更新回调

@local
@function on_temp_humidity_update
@param temp number 温度
@param humi number 湿度
]]
local function on_temp_humidity_update(temp, humi)
    state.temperature = temp
    state.humidity = humi
end

--[[
继电器状态更新回调

@local
@function on_relay_status_update
@param new_state table 继电器状态数组
]]
local function on_relay_status_update(new_state)
    if type(new_state) == "table" then
        state.relay = new_state
    end
end

--[[
定位更新回调

@local
@function on_location_update
@param new_lat string 纬度
@param new_lng string 经度
]]
local function on_location_update(new_lat, new_lng)
    state.lat = new_lat or ""
    state.lng = new_lng or ""
end

-- 订阅温湿度更新
sys.subscribe("TEMP_HUMIDITY_UPDATE", on_temp_humidity_update)

-- 订阅继电器状态更新
sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)

-- 订阅定位更新
sys.subscribe("Airlbs_LOCATION_UPDATE", on_location_update)

--[[
获取当前设备状态汇总

@return table 设备状态汇总表
]]
function M.get_state()
    return state
end

return M
