--[[
@module  ble_client_main
@summary ble client 主应用功能模块
@version 1.0
@date    2025.08.20
@author  王世豪
@usage
本文件为ble client 主应用功能模块，核心业务逻辑为：
1. 初始化BLE功能
2. 扫描目标BLE设备（默认名称为"LuatOS"）
3. 建立与目标设备的连接
4. 处理各类BLE事件（连接、断开连接、扫描报告、GATT操作完成等）
5. 接收并处理来自其他模块的请求（如READ_REQ读取请求）
6. 异常处理与自动重连机制
7. 依赖模块
    - ble_client_receiver: 用于处理接收到的BLE数据
    - ble_client_sender: 用于发送BLE数据
8. 事件处理
    通过ble_event_cb函数处理以下BLE事件：
    - EVENT_CONN: 连接成功
    - EVENT_DISCONN: 断开连接
    - EVENT_SCAN_REPORT: 扫描报告
    - EVENT_GATT_DONE: GATT操作完成
    - EVENT_READ_VALUE: 读取特征值完成

本文件没有对外接口，直接在main.lua中require "ble_client_main"就可以加载运行；
]]
local ble_client_receiver = require "ble_client_receiver"
local ble_client_sender = require "ble_client_sender"

-- ble_client_main的任务名
local TASK_NAME = ble_client_sender.TASK_NAME_PREFIX.."main"

-- 配置参数
config = {
    target_device_name = "LuatOS", -- 目标设备名称
    target_service_uuid = "FA00",  -- 目标服务UUID
    target_notify_char = "EA01",   -- 目标通知特征值UUID
    target_write_char = "EA02",    -- 目标写入特征值UUID
    target_read_char = "EA03",     -- 目标读取特征值UUID
    scan_timeout = 10000,          -- 等待SCAN_REPORT超时时间(ms)
    connect_timeout = 5000,        -- 等待CONNECT超时时间(ms)
}

local bluetooth_device = nil
local ble_device = nil
local scan_create = nil
local scan_count = 0
local last_operation = nil

-- WiFi和蓝牙状态 (1=开启, 0=关闭)
local wifi_state = 1

local function wifi_state_change(state)
    wifi_state = state
    log.info("ble_client_main", "收到WiFi状态变化:", state)
    
    if state == 0 then
        -- 释放已创建的BLE资源
        bluetooth_device = nil
        ble_device = nil
        scan_create = nil
        scan_count = 0
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "WIFI_STATE_CLOSE")
    else
        -- WiFi状态打开时发布消息
        sys.publish("WIFI_STATE_OPEN")
    end
end

-- 订阅WiFi和蓝牙状态变化消息
sys.subscribe("WIFI_STATE_CHANGED", wifi_state_change)

-- 设备过滤函数
local function is_target_device(scan_param)
    log.info("scan_param", scan_param.data:toHex())
    -- 检查设备名称是否匹配
    if scan_param.data and scan_param.data:find(config.target_device_name) then
        log.info("BLE", "发现目标设备: " .. config.target_device_name)
        return true
    end
    return false
end

-- 解析特征值属性
local function parse_properties(properties)
    local prop_map = {
        [0x08] = "Read",         -- (0x01 << 3)
        [0x10] = "Write",        -- (0x01 << 4)
        [0x20] = "Indicate",     -- (0x01 << 5)
        [0x40] = "Notify",       -- (0x01 << 6)
        [0x80] = "Write Command"  -- (0x01 << 7)
    }
    local result = ""
    for bit, name in pairs(prop_map) do
        if properties & bit ~= 0 then
            if result ~= "" then
                result = result .. ", "
            end
            result = result .. name
        end
    end
    return result
end

-- 打印GATT信息
local function print_gatt(gatt)
    for k, v in pairs(gatt) do
        if k == 1 and type(v) == 'string' then
            local uuid,uuid_len = v:toHex()
            log.info("server uuid:",uuid,"uuid len:",uuid_len*4)
        else -- Characteristic
            for n, m in pairs(v) do
                if n == 1 and type(m) == 'string' then
                    local uuid,uuid_len = m:toHex()
                    log.info("characteristic uuid:",uuid,"uuid len:",uuid_len*4)
                elseif n == 2 and type(m) == 'number' then
                    -- Properties
                    local prop_str = parse_properties(m)
                    log.info("characteristic properties:", m, "(", prop_str, ")")
                else
                    log.info("", n, type(m), m)
                end
            end
        end
    end
end

-- 事件回调函数
local function ble_event_cb(ble_device, ble_event, ble_param)
    -- 仅表示连接成功，后续读/写/订阅 需等待GATT_DONE事件
    if ble_event == ble.EVENT_CONN then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "CONNECT", ble_param)
    -- 连接断开
    elseif ble_event == ble.EVENT_DISCONN then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "DISCONNECTED", ble_param.reason)
    -- 扫描报告
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "SCAN_REPORT", ble_param)
    -- GATT项处理
    elseif ble_event == ble.EVENT_GATT_ITEM then
        log.info("ble", "gatt item", ble_param)
        print_gatt(ble_param)
    -- GATT操作完成,可进行读/写/订阅操作
    elseif ble_event == ble.EVENT_GATT_DONE then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "GATT_DONE", ble_param)

        -- 开启Notify监听,监听外围设备指定服务和特征值的通知,默认打开
        local notify_params = {
            uuid_service = string.fromHex(config.target_service_uuid),
            uuid_characteristic = string.fromHex(config.target_notify_char)
        }
        if ble_device then
            ble_device:notify_enable(notify_params, true)
        end
    -- 读取特征值完成
    elseif ble_event == ble.EVENT_READ_VALUE then
        -- 通知receiver处理数据
        ble_client_receiver.proc(ble_param.uuid_service:toHex(), ble_param.uuid_characteristic:toHex(), ble_param.data)
    end
end

-- 初始化BLE
local function ble_init()
    -- 初始化蓝牙核心
    bluetooth_device = bluetooth_device or bluetooth.init()
    if not bluetooth_device then
        log.error("BLE", "蓝牙初始化失败")
        return false
    end

    -- 初始化BLE功能
    ble_device = ble_device or bluetooth_device:ble(ble_event_cb)
    if not ble_device then
        log.error("BLE", "当前固件不支持完整的BLE")
        return false
    end

    -- 创建BLE扫描
    scan_create = scan_create or ble_device:scan_create({})
    if not scan_create then -- 默认参数：addr_mode=ble.PUBLIC, scan_interval=100, scan_window=100
        log.error("BLE", "BLE创建扫描失败")
        return false
    end

    -- 启动BLE扫描
    if not ble_device:scan_start() then
        log.error("BLE", "BLE扫描启动失败")
        return false
    end

    last_operation = "scan"
    return true
end

-- 主任务处理函数
local function ble_client_main_task_func()
    local result,msg

    while true do
        -- 检查WiFi状态
        if wifi_state == 0 then
            log.info("ble_client_main", "WiFi关闭，等待WiFi开启...")
            sys.waitUntil("WIFI_STATE_OPEN")
            goto CONTINUE_LOOP
        end

        result = ble_init()
        if not result then
            log.error("ble_client_main_task_func", "ble_init error")
            goto EXCEPTION_PROC
        end

        -- 扫描上报、连接、断开连接、异常等各种事件的处理调度逻辑
        while true do
            -- 根据最后操作设置超时时间
            if last_operation == "scan" then
                timeout = config.scan_timeout
            elseif last_operation == "connect" then
                timeout = config.connect_timeout
            else
                timeout = nil
            end

            msg = sys.waitMsg(TASK_NAME, "BLE_EVENT", timeout)

            if not msg then
                log.error("ble_client_main_task_func", "waitMsg timeout")
                goto EXCEPTION_PROC
            end
    
            if msg[2] == "CONNECT" then
                -- 仅表示连接成功，后续读/写/订阅 需等待GATT_DONE事件
                local conn_param = msg[3]
                log.info("BLE", "设备连接成功: " .. conn_param.addr:toHex())
                last_operation = nil
            elseif msg[2] == "GATT_DONE" then
                -- 连接成功且服务发现完成，后续可执行业务操作（读/写/订阅）
                -- 通知sender模块连接成功
                log.info("BLE", "GATT服务发现完成")
                sys.sendMsg(ble_client_sender.TASK_NAME, "BLE_EVENT", "CONNECT_OK", ble_device)
                last_operation = nil
            elseif msg[2] == "DISCONNECTED" then
                log.info("BLE", "设备断开连接，原因: " .. msg[3])
                break
            elseif msg[2] == "SCAN_REPORT" then
                local ble_param = msg[3]
                log.info("BLE", string.format("扫描报告 | Type: %d | MAC: %s | RSSI: %d | Data: %s ",
                    ble_param.addr_type,        -- 类型（整数）
                    ble_param.adv_addr:toHex(), -- MAC地址（字符串）
                    ble_param.rssi,             -- 信号强度（整数）
                    ble_param.data:toHex()      -- 广播数据（字符串）
                ))
                -- 检查是否为目标设备
                if is_target_device(ble_param) then
                    log.info("ble", "停止扫描, 连接设备", ble_param.adv_addr:toHex(), ble_param.addr_type)
                    ble_device:scan_stop()
                    scan_count = 0
                    ble_device:connect(ble_param.adv_addr, ble_param.addr_type)
                    last_operation = "connect"
                end

                scan_count = scan_count + 1
                if scan_count > 100 then
                    log.info("ble", "扫描次数超过100次, 停止扫描, 10秒后重新开始")
                    scan_count = 0
                    ble_device:scan_stop()
                    sys.sendMsg(TASK_NAME, "BLE_EVENT", "RESTART_SCAN")
                end
            elseif msg[2] == "RESTART_SCAN" then
                -- 5s后重新开始扫描
                sys.wait(5000)
                if ble_device then
                    ble_device:scan_start()
                end
                last_operation = "scan"
            elseif msg[2] == "READ_REQ" then
                -- 从消息中获取传入的UUID参数，若没有则使用默认配置
                local service_uuid = msg[3] or config.target_service_uuid
                local char_uuid = msg[4] or config.target_read_char

                local read_params = {
                    uuid_service = string.fromHex(service_uuid),
                    uuid_characteristic = string.fromHex(char_uuid)
                }
                if ble_device then
                    ble_device:read_value(read_params)
                end
            elseif msg[2] == "WIFI_STATE_CLOSE" then
                -- 收到WiFi状态关闭消息，跳出主循环，等待WiFi开启
                break
            end
        end

        -- 出现异常
        ::EXCEPTION_PROC::
        log.error("ble_client_main_task_func", "异常退出, 5秒后重新扫描连接")

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)

        -- 通知ble sender数据发送应用模块的task，ble连接已经断开
        sys.sendMsg(ble_client_sender.TASK_NAME, "BLE_EVENT", "DISCONNECTED")

        -- 重置扫描计数
        scan_count = 0

        ::CONTINUE_LOOP::
        -- 5秒后跳转到循环体开始位置，自动发起重连
        log.info("ble_server_main", "等待5秒后重新尝试...")
        sys.wait(5000)
    end
end

-- 启动主任务
sys.taskInitEx(ble_client_main_task_func, TASK_NAME)
