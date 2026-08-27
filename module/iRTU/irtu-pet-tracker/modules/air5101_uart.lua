--[[
@module air5101_uart
@summary Air5101蓝牙模块串口通信库（基于 exril_5101 扩展库）
@version 2.2
@date    2026.07.23
@usage
通过 exril_5101 扩展库控制 Air5101 BLE 模块
支持 AT 指令模式和透传模式，透传模式下可接收手机 BLE 数据
]]

local air5101_uart = {}

-- 蓝牙模块电源控制引脚
local POWER_PIN = 27          -- 5101蓝牙模块供电使能引脚

-- 状态
local state = {
    initialised = false,
    transparent_mode = false,
    ble_data_callback = nil
}

-- 将 ASCII 字符串转为十六进制字符串（用于 scan_rsp_data）
local function ascii_to_hex(str)
    local hex = ""
    for i = 1, #str do
        hex = hex .. string.format("%02X", string.byte(str, i))
    end
    return hex
end

-- 构建扫描响应数据（BLE 广播中显示设备名称的关键）
-- 格式: 长度(1字节) + AD Type(0x09=Complete Local Name) + 名称ASCII
local function build_scan_rsp(name)
    return string.format("%02X09", #name + 1) .. ascii_to_hex(name)
end

-- exril_5101 事件回调
local function ble_event_cb(event, payload)
    if event == "connected" then
        log.info("air5101_uart", "手机 BLE 已连接")
    elseif event == "disconnected" then
        log.info("air5101_uart", "手机 BLE 已断开")
    elseif event == "data" then
        if payload and payload.data then
            log.info("air5101_uart", "收到 BLE 数据:", payload.data)
            if state.ble_data_callback then
                state.ble_data_callback(payload.data)
            end
        end
    elseif event == "error" then
        log.warn("air5101_uart", "BLE 错误:", payload)
    elseif event == "system" then
        log.info("air5101_uart", "BLE 系统事件:", payload)
    end
end

--[[
打开蓝牙模块电源并初始化
@return boolean
]]
function air5101_uart.init()
    if state.initialised then
        return true
    end

    log.info("air5101_uart", "打开蓝牙电源...")

    -- 打开5101蓝牙模块供电
    gpio.setup(POWER_PIN, 1)
    sys.wait(1500)

    -- 加载 exril_5101 扩展库
    local exril_5101 = require("exril_5101")
    if not exril_5101 then
        log.error("air5101_uart", "exril_5101 库加载失败")
        return false
    end

    -- 切换到 AT 模式进行配置
    local ok, err = exril_5101.mode(exril_5101.MODE_AT)
    if not ok then
        log.error("air5101_uart", "切换到 AT 模式失败:", err)
        return false
    end
    log.info("air5101_uart", "已切换到 AT 模式")

    -- 注册事件回调
    exril_5101.on(ble_event_cb)

    state.initialised = true
    log.info("air5101_uart", "蓝牙模块初始化完成")
    return true
end

--[[
关闭蓝牙模块电源
]]
function air5101_uart.close()
    if not state.initialised then
        return
    end

    log.info("air5101_uart", "关闭蓝牙电源")

    state.transparent_mode = false
    state.initialised = false

    gpio.setup(POWER_PIN, 0)
end

--[[
启动蓝牙广播
先断电重启清除旧缓存，再设置新名称 + 扫描响应数据，并保存到 Flash
@param name 设备名称
@param interval_ms 广播间隔（毫秒），可选
@return boolean
]]
function air5101_uart.start_broadcast(name, interval_ms)
    if not state.initialised then
        log.error("air5101_uart", "蓝牙未初始化")
        return false
    end

    local exril_5101 = require("exril_5101")

    -- 先断电重启蓝牙模块，彻底清除旧缓存
    log.info("air5101_uart", "断电重启蓝牙模块，清除旧配置缓存...")
    gpio.setup(POWER_PIN, 0)
    sys.wait(500)
    gpio.setup(POWER_PIN, 1)
    sys.wait(1500)

    -- 重新初始化：切换到 AT 模式
    local ok, err = exril_5101.mode(exril_5101.MODE_AT)
    if not ok then
        log.error("air5101_uart", "重启后切换到 AT 模式失败:", err)
        return false
    end

    -- 重新注册事件回调
    exril_5101.on(ble_event_cb)

    -- 构建扫描响应数据（手机扫描时看到的名称）
    local scan_rsp = build_scan_rsp(name)
    log.info("air5101_uart", "扫描响应数据:", "0x" .. scan_rsp)

    -- 配置设备参数：同时设置设备名称、广播类型、扫描响应数据
    local config = {
        name = name,
        adv_type = exril_5101.ADV_C,  -- 可连接广播
        scan_rsp_data = "0x" .. scan_rsp,
        adv_interval = interval_ms,
    }

    ok, err = exril_5101.set(config)
    if not ok then
        log.error("air5101_uart", "配置广播参数失败:", err)
        return false
    end

    -- 保存到 Flash（掉电不丢失）
    ok, err = exril_5101.save()
    if not ok then
        log.warn("air5101_uart", "保存配置到 Flash 失败:", err)
    end

    log.info("air5101_uart", "广播已启动，设备名称:", name)
    return true
end

--[[
停止广播
]]
function air5101_uart.stop()
    local exril_5101 = require("exril_5101")
    exril_5101.disconnect()
    state.transparent_mode = false
end

--[[
注册 BLE 数据接收回调
]]
function air5101_uart.set_ble_data_callback(cb)
    state.ble_data_callback = cb
end

--[[
获取当前缓存的 BLE 数据（非阻塞）
]]
function air5101_uart.get_ble_data()
    return nil
end

--[[
进入透传模式
]]
function air5101_uart.enter_transparent_mode()
    if state.transparent_mode then
        return true
    end
    if not state.initialised then
        log.error("air5101_uart", "蓝牙未初始化")
        return false
    end

    local exril_5101 = require("exril_5101")
    local ok, err = exril_5101.mode(exril_5101.MODE_UA)
    if not ok then
        log.error("air5101_uart", "进入透传模式失败:", err)
        return false
    end

    state.transparent_mode = true
    log.info("air5101_uart", "已进入透传模式，等待 BLE 数据...")
    return true
end

--[[
退出透传模式
]]
function air5101_uart.exit_transparent_mode()
    if not state.transparent_mode then
        return true
    end

    local exril_5101 = require("exril_5101")
    local ok, err = exril_5101.mode(exril_5101.MODE_AT)
    if not ok then
        log.error("air5101_uart", "退出透传模式失败:", err)
        return false
    end

    state.transparent_mode = false
    log.info("air5101_uart", "已退出透传模式")
    return true
end

--[[
获取蓝牙连接状态
]]
function air5101_uart.get_status()
    if not state.initialised then
        return false
    end

    local exril_5101 = require("exril_5101")
    local ok, status = exril_5101.status()
    if ok and status == "connected" then
        return true
    end
    return false
end

return air5101_uart