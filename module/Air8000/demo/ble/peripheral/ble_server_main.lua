
--[[
@module  ble_server_main
@summary ble server 主应用功能模块
@version 1.0
@date    2025.08.29
@author  王世豪
@usage
本文件为ble server 主应用功能模块，核心业务逻辑为：
1. 初始化BLE功能
2. 创建GATT数据库
3. 设置广播内容并开始广播
4. 处理各类BLE事件（连接、断开连接、写入请求等）
5. 接收并处理来自其他模块的请求
6. 依赖模块
    - ble_server_receiver: 用于处理接收到的BLE数据
    - ble_server_sender: 用于发送BLE数据
]]
local ble_server_receiver = require "ble_server_receiver"
local ble_server_sender = require "ble_server_sender"

-- ble_server_main的任务名
local TASK_NAME = ble_server_sender.TASK_NAME_PREFIX.."main"

-- 配置参数
config = {
    device_name = "LuatOS",          -- 设备名称
    service_uuid = "FA00",           -- 服务UUID
    char_uuid1 = "EA01",             -- Characteristic 1
    char_uuid2 = "EA02",             -- Characteristic 2
    char_uuid3 = "EA03",             -- Characteristic 3
}

local bluetooth_device = nil
local ble_device = nil
local adv_create = nil
local gatt_create = nil

-- GATT数据库定义
local att_db = { 
    string.fromHex(config.service_uuid), -- Service UUID
    -- Characteristic
    { -- Characteristic 1 (Notify + Read + Write)
        string.fromHex(config.char_uuid1),
        ble.NOTIFY | ble.READ | ble.WRITE
    }, { -- Characteristic 2 (Write)
        string.fromHex(config.char_uuid2),
        ble.WRITE
    }, { -- Characteristic 3 (Read)
        string.fromHex(config.char_uuid3),
        ble.READ
    }
}

-- 事件回调函数
local function ble_event_cb(ble_device, ble_event, ble_param)
    -- 连接中心设备成功
    if ble_event == ble.EVENT_CONN then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "CONNECT", ble_param)

    -- 连接断开
    elseif ble_event == ble.EVENT_DISCONN then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "DISCONNECTED", ble_param.reason)

    -- 收到中心设备的写请求
    elseif ble_event == ble.EVENT_WRITE then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "WRITE_REQ", ble_param)
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

    -- 创建GATT
    gatt_create = gatt_create or ble_device:gatt_create(att_db)
    if not gatt_create then
        log.error("BLE", "BLE创建GATT失败")
        return false
    end

    -- 设置广播内容
    adv_create = adv_create or ble_device:adv_create({
        addr_mode = ble.PUBLIC, -- 广播地址模式, 可选值: ble.PUBLIC, ble.RANDOM, ble.RPA, ble.NRPA
        channel_map = ble.CHNLS_ALL, -- 广播的通道, 可选值: ble.CHNLS_37, ble.CHNLS_38, ble.CHNLS_39, ble.CHNLS_ALL
        intv_min = 120, -- 广播间隔最小值, 单位为0.625ms, 最小值为20, 最大值为10240
        intv_max = 120, -- 广播间隔最大值, 单位为0.625ms, 最小值为20, 最大值为10240
        adv_data = {    -- 支持表格形式, 也支持字符串形式(255字节以内)
            {ble.FLAGS, string.char(0x06)}, -- 广播标志位, 0x06: 支持LE Limited Discoverable Mode, 0x04: 支持LE General Discoverable Mode
            {ble.COMPLETE_LOCAL_NAME, config.device_name}, -- 广播本地名称
        }
    })
    if not adv_create then
        log.error("BLE", "BLE创建广播失败")
        return false
    end

    -- 开始广播
    ble_device:adv_start()

    return true
end

-- 主任务处理函数
local function ble_server_main_task_func()
    local result,msg

    while true do
        result = ble_init()
        if not result then
            log.error("ble_main_task_func", "ble_init error")
            goto EXCEPTION_PROC
        end

        while true do
            msg = sys.waitMsg(TASK_NAME, "BLE_EVENT")

            if not msg then
                log.error("ble_client_main_task_func", "waitMsg timeout")
                goto EXCEPTION_PROC
            end
    
            if msg[2] == "CONNECT" then
                local conn_param = msg[3]
                log.info("BLE", "设备连接成功: " .. conn_param.addr:toHex())
                sys.sendMsg(ble_server_sender.TASK_NAME, "BLE_EVENT", "CONNECT_OK", ble_device)
            elseif msg[2] == "DISCONNECTED" then
                log.info("BLE", "设备断开连接，原因: " .. msg[3])
                break
            -- 收到中心设备的写请求,将写的数据发给ble_server_receiver模块处理
            elseif msg[2] == "WRITE_REQ" then
                local ble_param = msg[3]
                log.info("BLE", "收到写请求: " .. ble_param.uuid_service:toHex() .. " " .. ble_param.uuid_characteristic:toHex() .. " " .. ble_param.data:toHex())
                ble_server_receiver.proc(ble_param.uuid_service:toHex(), ble_param.uuid_characteristic:toHex(), ble_param.data)
            end
        end

        ::EXCEPTION_PROC::
        log.error("ble_server_main_task_func", "异常退出, 5秒后重新开启广播")
        
        -- 停止广播
        ble_device:adv_stop()

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)

        -- 通知ble sender数据发送应用模块的task，ble连接已经断开
        sys.sendMsg(ble_server_sender.TASK_NAME, "BLE_EVENT", "DISCONNECTED")

        -- 5秒后跳转到循环体开始位置，自动发起重连
        sys.wait(5000)
    end
end

-- 启动主任务
sys.taskInitEx(ble_server_main_task_func, TASK_NAME)
