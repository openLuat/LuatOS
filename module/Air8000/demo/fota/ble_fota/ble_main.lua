--[[
@module  ble_main
@summary BLE服务主功能模块
@version 1.0
@date    2025.12.08
@author  孟伟
@usage
-- BLE服务主功能模块
-- 提供BLE服务的初始化、配置和事件处理
-- 不包含FOTA业务逻辑，仅处理BLE相关功能

依赖模块:
- ble_file_fota: 用于处理FOTA相关业务逻辑（文件写入方式）
- ble_packet_fota: 用于处理FOTA相关业务逻辑（分段写入方式）
]]

-- 选择FOTA升级方式："file" 或 "packet"
-- 1. file方式：将升级包数据先写入本地文件，然后调用fota.file()进行升级
-- 2. packet方式：直接使用fota.packet()处理分段数据，不写入文件，适合差分升级
local fota_mode = "packet" -- 默认使用file方式

-- 根据选择加载对应的FOTA模块
local ble_fota_main
if fota_mode == "file" then
    ble_fota_main = require "ble_file_fota"
else
    ble_fota_main = require "ble_packet_fota"
end

-- ble_main的任务名
local TASK_NAME = "BLE_MAIN"

-- 配置参数
config = {
    device_name = "Air8000_FOTA", -- 设备广播名称
    service_uuid = "F000",        -- FOTA服务UUID（短格式）
    char_uuid_cmd = "F001",       -- 命令特征值UUID
    char_uuid_data = "F002",      -- 数据特征值UUID
    max_packet_size = 20          -- BLE数据包最大长度（字节）
}

local bluetooth_device = nil
local ble_device = nil
local adv_create = nil
local gatt_create = nil

-- GATT服务数据库定义
-- 这里定义了BLE设备提供的服务和特征值
local att_db = {
    string.fromHex(config.service_uuid), -- Service UUID
    {
        string.fromHex(config.char_uuid_cmd),
        ble.WRITE | ble.WRITE_CMD
    },
    {
        string.fromHex(config.char_uuid_data),
        ble.WRITE | ble.WRITE_CMD
    }
}

-- BLE事件回调函数
local function ble_event_cb(ble_dev, event, param)
    log.info("BLE_EVENT", "收到BLE事件:", event)

    -- 根据LuatOS BLE事件枚举处理不同事件
    if event == ble.EVENT_CONN then
        -- 连接成功事件
        log.info("BLE_EVENT", "设备已连接", "地址:", param.addr and param.addr:toHex() or "未知")
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "CONNECT", param)
    elseif event == ble.EVENT_DISCONN then
        -- 连接断开事件
        log.info("BLE_EVENT", "设备已断开连接", "原因:", param.reason or "未知")
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "DISCONNECTED", param.reason)
    elseif event == ble.EVENT_WRITE then
        -- 写入事件 - 这是关键事件！
        log.info("BLE_EVENT", "处理写入事件")

        -- 检查参数是否完整
        if not param or not param.uuid_service or not param.uuid_characteristic or not param.data then
            log.error("BLE_EVENT", "写入事件参数不完整")
            return
        end

        -- 获取服务UUID和特征值UUID
        local service_uuid = param.uuid_service:toHex()
        local char_uuid = param.uuid_characteristic:toHex()
        local data = param.data

        log.info("BLE_EVENT", "服务UUID:", service_uuid)
        log.info("BLE_EVENT", "特征值UUID:", char_uuid)
        log.info("BLE_EVENT", "数据长度:", #data, "字节")
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "WRITE_REQ", param)
    elseif event == ble.EVENT_READ then
        -- 读取事件 - 外围设备收到主设备读请求
        log.info("BLE_EVENT", "处理读取事件")
    elseif event == ble.EVENT_READ_VALUE then
        -- 读取操作完成事件 - 中心设备读取特征值完成
        log.info("BLE_EVENT", "读取操作完成", "数据:", param.data and param.data:toHex() or "无数据")
    elseif event == ble.EVENT_SCAN_REPORT then
        -- 扫描报告事件 - 中心设备扫描到其他BLE设备
        log.info("BLE_EVENT", "扫描报告", "RSSI:", param.rssi, "地址:", param.adv_addr and param.adv_addr:toHex() or "未知")
    elseif event == ble.EVENT_SCAN_STOP then
        -- 扫描停止事件
        log.info("BLE_EVENT", "扫描停止")
    else
        -- 其他事件
        log.info("BLE_EVENT", "其他事件类型:", event)
        if param then
            -- 尝试打印参数的基本信息，避免直接打印table导致错误
            if type(param) == "table" then
                log.info("BLE_EVENT", "事件参数为table，包含字段:", #param)
                for k, v in pairs(param) do
                    if type(v) == "string" then
                        log.info("BLE_EVENT", "参数字段:", k, "值:", v:toHex())
                    else
                        log.info("BLE_EVENT", "参数字段:", k, "类型:", type(v))
                    end
                end
            else
                log.info("BLE_EVENT", "事件参数类型:", type(param))
            end
        end
    end
end

-- 初始化BLE功能
local function ble_init()
    log.info("BLE_INIT", "开始初始化BLE...")

    -- 初始化蓝牙核心
    bluetooth_device = bluetooth.init()
    if not bluetooth_device then
        log.error("BLE_INIT", "蓝牙核心初始化失败")
        return false
    end
    log.info("BLE_INIT", "蓝牙核心初始化成功")

    -- 初始化BLE功能
    ble_device = bluetooth_device:ble(ble_event_cb)
    if not ble_device then
        log.error("BLE_INIT", "BLE功能初始化失败")
        return false
    end
    log.info("BLE_INIT", "BLE功能初始化成功")

    -- 创建GATT服务
    gatt_create = ble_device:gatt_create(att_db)
    if not gatt_create then
        log.error("BLE_INIT", "GATT服务创建失败")
        return false
    end
    log.info("BLE_INIT", "GATT服务创建成功")

    -- 配置广播数据
    log.info("BLE_INIT", "配置广播数据...")
    adv_create = ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            { ble.FLAGS,               string.char(0x06) },  -- BLE标志
            { ble.COMPLETE_LOCAL_NAME, config.device_name }, -- 设备名称
        }
    })

    if not adv_create then
        log.error("BLE_INIT", "广播配置失败")
        return false
    end
    log.info("BLE_INIT", "广播配置成功")

    -- 开始广播
    ble_device:adv_start()
    log.info("BLE_INIT", "BLE广播已启动，设备名称:", config.device_name)

    return true
end

-- 主任务处理函数
local function ble_main_task_func()
    local result, msg

    while true do
        result = ble_init()
        if not result then
            log.error("ble_main_task_func", "ble_init error")
            goto EXCEPTION_PROC
        end

        while true do
            msg = sys.waitMsg(TASK_NAME, "BLE_EVENT")

            if not msg then
                log.error("ble_main_task_func", "waitMsg timeout")
                goto EXCEPTION_PROC
            end

            if msg[2] == "CONNECT" then
                local conn_param = msg[3]
                log.info("BLE", "设备连接成功: " .. conn_param.addr:toHex())
            elseif msg[2] == "DISCONNECTED" then
                log.info("BLE", "设备断开连接，原因: " .. msg[3])
                -- 通知FOTA模块连接断开
                ble_fota_main.proc_disconnect()
                break
            -- 收到中心设备的写请求,将写的数据发给ble_fota_main模块处理
            elseif msg[2] == "WRITE_REQ" then
                local ble_param = msg[3]
                local service_uuid = ble_param.uuid_service:toHex()
                local char_uuid = ble_param.uuid_characteristic:toHex()
                local data = ble_param.data

                log.info("BLE", "收到写请求: " .. service_uuid .. " " .. char_uuid .. " " .. data:toHex())
                ble_fota_main.proc(service_uuid, char_uuid, data)
            end
        end

        ::EXCEPTION_PROC::
        log.error("ble_main_task_func", "异常退出, 5秒后重新开启广播")

        -- 停止广播
        if ble_device then
            ble_device:adv_stop()
        end

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)

        -- 5秒后跳转到循环体开始位置，自动重试
        sys.wait(5000)
    end
end

-- 启动主任务
sys.taskInitEx(ble_main_task_func, TASK_NAME)
