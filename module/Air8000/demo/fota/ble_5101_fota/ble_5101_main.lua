--[[
@module  ble_5101_main
@summary Air5101蓝牙服务主功能模块
@version 1.0
@date    2026.03.04
@author  王世豪
@usage
核心业务逻辑为：
1. 初始化Air5101蓝牙模块
2. 选择FOTA升级模式（file或packet）
3. 注册并处理BLE事件（连接、断开连接、数据接收等）
4. 调用对应模式的处理函数
5. 管理异常处理和重新初始化

依赖模块:
- exril_5101: 用于Air5101蓝牙模块的AT指令封装
- ble_5101_file_fota: 用于处理FOTA相关业务逻辑（文件写入方式）
- ble_5101_packet_fota: 用于处理FOTA相关业务逻辑（分段写入方式）
]]

-- 加载exril_5101扩展库
local exril_5101 = require "exril_5101"

-- 选择FOTA升级方式："file" 或 "packet"
-- 1. file方式：将升级包数据先写入本地文件，然后调用fota.file()进行升级
-- 2. packet方式：直接使用fota.packet()处理分段数据，不写入文件，适合差分升级
local fota_mode = "packet" -- 默认使用packet方式

-- 当前使用的FOTA处理器
local current_fota_handler = nil

-- 根据选择加载对应的FOTA模块
if fota_mode == "file" then
    current_fota_handler = require "ble_5101_file_fota"
else
    current_fota_handler = require "ble_5101_packet_fota"
end

-- 主任务名
local TASK_NAME = "BLE_5101_MAIN"

-- 配置参数
local config = {
    device_name = "Air5101_FOTA",  -- 设备广播名称
}

-- BLE 事件回调函数
local function ble_event_cb(event, payload)    
    -- 连接中心设备成功
    if event == "connected" then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "CONNECTED", payload)
    
    -- 连接断开
    elseif event == "disconnected" then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "DISCONNECTED", payload)
    
    -- 收到数据
    elseif event == "data" then
        sys.sendMsg(TASK_NAME, "BLE_EVENT", "DATA_RECV", payload)
    
    -- 收到错误码（AE 或 UE）
    elseif event == "error" then
        log.warn("ble_5101_main", "收到错误码:", payload.error_type, payload.error_code)
    
    -- 系统事件（如设备重启）
    elseif event == "system" then
        if payload.type == "mac" then
            -- 设备重启后重新初始化
            log.info("ble_5101_main", "设备重启，开始重新初始化...")
            -- 发送消息给主任务，触发重新初始化
            sys.sendMsg(TASK_NAME, "BLE_EVENT", "REBOOT_DETECTED")
        end
    end
end

-- 初始化配置
local function init_config()
    log.info("ble_5101_main", "========== 配置初始化 ==========")
    
    -- 1. 获取当前工作模式
    local success, mode = exril_5101.mode()
    if success then
        log.info("ble_5101_main", "当前工作模式:", mode)
    else
        log.error("ble_5101_main", "获取模式失败:", mode)
        return false
    end
    
    -- 2. 切换到AT模式（确保可以配置参数）
    log.info("ble_5101_main", "切换到AT指令模式...")
    success, mode = exril_5101.mode(exril_5101.MODE_AT)
    if not success then
        log.error("ble_5101_main", "切换AT模式失败:", mode)
        return false
    end
    log.info("ble_5101_main", "已切换到:", mode)
    
    -- 3. 配置设备参数
    log.info("ble_5101_main", "配置设备参数...")
    local config_result, err = exril_5101.set({
        name = config.device_name,
    })
    
    if config_result then
        log.info("ble_5101_main", "参数配置成功")
    else
        log.error("ble_5101_main", "参数配置失败:", err)
    end

    -- 4. 切换到透传模式（用于接收蓝牙数据）
    log.info("ble_5101_main", "切换到透传模式...")
    success, mode = exril_5101.mode(exril_5101.MODE_UA)
    if not success then
        log.error("ble_5101_main", "切换透传模式失败:", mode)
        return false
    end
    log.info("ble_5101_main", "已切换到透传模式:", mode)

    return true
end

-- 主任务处理函数
local function ble_5101_main_task_func()
    local msg

    while true do

        -- 初始化配置
        local result = init_config()
        if not result then
            log.error("ble_5101_main", "配置初始化失败，5秒后重试...")
            goto EXCEPTION_PROC
        end

        -- 注册BLE事件回调
        exril_5101.on(ble_event_cb)
        log.info("ble_5101_main", "BLE事件回调已注册")

        -- 主模块初始化完成，通知其他模块
        sys.publish("BLE_5101_MAIN_READY")

        while true do
            msg = sys.waitMsg(TASK_NAME, "BLE_EVENT")
            log.info("ble_5101_main", "收到BLE事件:", msg[2], msg[3])

            -- 设备重启
            if msg[2] == "REBOOT_DETECTED" then
                log.info("ble_5101_main", "检测到设备重启，重新初始化...")
                goto EXCEPTION_PROC
            end

            -- 蓝牙连接成功
            if msg[2] == "CONNECTED" then
                log.info("ble_5101_main", "蓝牙连接成功")
                -- 通知FOTA模块连接成功
                if current_fota_handler and current_fota_handler.proc_connect then
                    current_fota_handler.proc_connect()
                end
            
            -- 蓝牙断开连接
            elseif msg[2] == "DISCONNECTED" then
                log.info("ble_5101_main", "蓝牙断开连接")
                -- 通知FOTA模块连接断开
                if current_fota_handler and current_fota_handler.proc_disconnect then
                    current_fota_handler.proc_disconnect()
                end
            
            -- 收到数据
            elseif msg[2] == "DATA_RECV" then
                local payload = msg[3]
                if payload and payload.data then
                    -- 处理接收到的数据
                    if current_fota_handler and current_fota_handler.proc then
                        current_fota_handler.proc(payload.data)
                    end
                end
            end
        end

        -- 出现异常
        ::EXCEPTION_PROC::
        
        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)

        -- 5秒后跳转到循环体开始位置，自动重新初始化
        log.info("ble_5101_main", "等待5秒后重新尝试...")
        sys.wait(5000)
    end
end

-- 启动主任务
sys.taskInitEx(ble_5101_main_task_func, TASK_NAME)