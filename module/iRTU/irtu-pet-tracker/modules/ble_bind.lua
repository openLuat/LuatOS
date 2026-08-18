--[[
@module ble_bind
@summary 蓝牙模块
@version 2.2
@date    2026.07.22
@usage
蓝牙广播名称由服务端配置 (config.BLE_CONFIG) 控制：
  - adv_name_prefix: "irtu-"
  - adv_name_suffix: "imei_last6"
服务端配置为空时使用默认值 "irtu-IMEI后六位"
]]

local ble_bind = {}

local air5101_uart = require("air5101_uart")
local config = require("config")

-- 蓝牙模块电源控制引脚
local POWER_PIN = 27          -- 5101蓝牙模块供电使能引脚
local UART_LEVEL_PIN = 24     -- 串口电平转换电路上拉使能引脚（与DA267供电共用）

-- 蓝牙状态
local state = {
    powered_on = false,
    initialized = false,
    advertising = false,
    device_name = "",
    bind_mode = false
}

-- 生成蓝牙设备名称
-- 规则：服务端配置的 prefix + IMEI 后缀
-- 例: irtu-366606
local function generate_device_name()
    local imei = mobile.imei() or "000000000000000"
    local ble_cfg = config.BLE_CONFIG or {}
    local prefix = ble_cfg.adv_name_prefix or "irtu-"
    local suffix_rule = ble_cfg.adv_name_suffix or "imei_last6"

    -- 处理后缀规则
    local suffix
    if suffix_rule == "imei_last6" then
        suffix = string.sub(imei, -6)
    elseif suffix_rule == "imei_last4" then
        suffix = string.sub(imei, -4)
    elseif suffix_rule == "imei_all" then
        suffix = imei
    else
        suffix = string.sub(imei, -6)  -- 默认后6位
    end

    local name = prefix .. suffix
    log.info("ble_bind", "设备名称:", name, "(规则:", prefix .. "+" .. suffix_rule .. ")")
    return name
end

--[[
打开蓝牙模块电源并初始化
@return boolean
]]
function ble_bind.open()
    if state.powered_on and state.initialized then
        return true
    end

    log.info("ble", "打开蓝牙电源")

    -- 打开5101蓝牙模块供电
    gpio.setup(POWER_PIN, 1)

    -- 打开串口电平转换电路上拉（IO24同时也是DA267的供电引脚）
    gpio.setup(UART_LEVEL_PIN, 1)

    -- 初始化Air5101模块
    local ok = air5101_uart.init()
    if not ok then
        ble_bind.close()
        return false
    end

    state.powered_on = true
    state.initialized = true
    return true
end

--[[
关闭蓝牙模块电源
]]
function ble_bind.close()
    log.info("ble", "关闭蓝牙电源")

    -- 断开连接
    air5101_uart.stop()

    -- 关闭串口
    uart.close(1)

    -- 关闭5101蓝牙模块供电
    gpio.setup(POWER_PIN, 0)

    -- 关闭串口电平转换上拉
    gpio.setup(UART_LEVEL_PIN, 0)

    state.powered_on = false
    state.initialized = false
    state.advertising = false
    state.bind_mode = false
end

--[[
检查蓝牙是否已开启
@return boolean
]]
function ble_bind.is_powered()
    return state.powered_on
end

--[[
开启蓝牙广播
@param name 设备名称，可选，不传则自动生成
@param interval_ms 广播间隔（毫秒），可选
@return boolean
]]
function ble_bind.start(name, interval_ms)
    if not state.initialized then
        log.error("ble", "蓝牙未初始化")
        return false
    end

    local adv_name = name or generate_device_name()
    local interval = 100

    local success = air5101_uart.start_broadcast(adv_name, interval)
    if success then
        state.advertising = true
        state.device_name = adv_name
    end
    return success
end

--[[
停止蓝牙广播
]]
function ble_bind.stop()
    air5101_uart.stop()
    state.advertising = false
    state.bind_mode = false
end

--[[
获取广播状态
@return boolean
]]
function ble_bind.is_advertising()
    return state.advertising
end

--[[
进入绑定模式
开机后自动调用，开启蓝牙广播供APP发现
@return boolean
]]
function ble_bind.start_bind_mode()
    if not state.initialized then
        if not ble_bind.open() then
            return false
        end
    end

    state.bind_mode = true
    local name = generate_device_name()
    ble_bind.start(name)
    return true
end

--[[
进入寻宠物模式
]]
function ble_bind.start_find_pet_mode()
    if not state.initialized then
        ble_bind.open()
    end

    state.bind_mode = false
    local name = generate_device_name()
    ble_bind.start(name)
    sys.publish("FIND_PET_MODE_START")
end

--[[
退出寻宠物模式
]]
function ble_bind.stop_find_pet_mode()
    ble_bind.stop()
    ble_bind.close()
    sys.publish("FIND_PET_MODE_STOP")
end

return ble_bind