--[[
@module  exril_5101_main
@summary exril_5101 主应用功能模块
@version 1.1
@date    2026.03.02
@author  王世豪
@usage
本文件为exril_5101 主应用功能模块，核心业务逻辑为：
1. 初始化BLE功能
2. 配置设备参数（设备名称、广播参数等）
3. 注册并处理BLE事件（连接、断开连接、数据接收等）
4. 调用 receiver 处理接收到的数据
5. 通知 sender 连接状态变化

依赖模块：
    - exril_5101_receiver: 用于处理接收到的BLE数据
    - exril_5101_sender: 用于发送BLE数据
]]

local exril_5101 = require("exril_5101")
local exril_5101_receiver = require("exril_5101_receiver")
local exril_5101_sender = require("exril_5101_sender")

-- 主任务名
local TASK_NAME = exril_5101_sender.TASK_NAME_PREFIX.."main"

-- 默认配置参数
local default_config = {
    -- 设备名称（不超过20字符）
    device_name = "Air5101_Test",
    -- -- 广播类型（可连接）
    -- adv_type = exril_5101.ADV_C,
    -- -- 广播间隔（毫秒）
    -- adv_interval = 30,
    -- -- 广播数据
    -- adv_data = "02010603031218",
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
        log.warn("exril_5101_main", "收到错误码:", payload.error_type, payload.error_code)
        -- 不处理错误码，只打印日志
    
    -- 系统事件（如设备重启）
    elseif event == "system" then
        if payload.type == "mac" then
            -- 设备重启后重新初始化
            log.info("exril_5101_main", "设备重启，开始重新初始化...")
            -- 发送消息给主任务，触发重新初始化
            sys.sendMsg(TASK_NAME, "BLE_EVENT", "REBOOT_DETECTED")
        end
    end
end

-- 初始化配置
local function init_config()
    log.info("exril_5101_main", "========== 配置初始化 ==========")
    
    -- 1. 获取当前工作模式
    local success, mode = exril_5101.mode()
    if success then
        log.info("exril_5101_main", "当前工作模式:", mode)
    else
        log.error("exril_5101_main", "获取模式失败:", mode)
        return false
    end
    
    -- 2. 切换到AT模式（确保可以配置参数）
    log.info("exril_5101_main", "切换到AT指令模式...")
    success, mode = exril_5101.mode(exril_5101.MODE_AT)
    if not success then
        log.error("exril_5101_main", "切换AT模式失败:", mode)
        return false
    end
    log.info("exril_5101_main", "已切换到:", mode)
    
    -- 3. 配置设备参数
    log.info("exril_5101_main", "配置设备参数...")
    local config_result, err = exril_5101.set({
        name = default_config.device_name,
        adv_type = default_config.adv_type,
        adv_data = default_config.adv_data,
        adv_interval = default_config.adv_interval,
        mtu_len = 247,
    })
    
    if config_result then
        log.info("exril_5101_main", "参数配置成功")
    else
        log.error("exril_5101_main", "参数配置失败:", err)
    end
    
    -- 4. 查询设备信息
    log.info("exril_5101_main", "查询设备信息...")
    local info, err = exril_5101.get({"name", "mac", "ver"})
    if info then
        log.info("exril_5101_main", "设备名称:", info.name or "未知")
        log.info("exril_5101_main", "MAC地址:", info.mac or "未知")
        log.info("exril_5101_main", "固件版本:", info.ver or "未知")
    else
        log.error("exril_5101_main", "查询失败:", err)
    end
    
    return true
end

-- 主任务处理函数
local function exril_5101_main_task_func()
    local msg

    while true do
        -- 初始化配置
        local result = init_config()
        if not result then
            log.error("exril_5101_main", "配置初始化失败，5秒后重试...")
            goto EXCEPTION_PROC
        end

        -- 注册BLE事件回调
        exril_5101.on(ble_event_cb)
        log.info("exril_5101_main", "BLE事件回调已注册")

        -- 主模块初始化完成，通知其他模块
        sys.publish("EXRIL_5101_MAIN_READY")

        while true do
            msg = sys.waitMsg(TASK_NAME, "BLE_EVENT")
            log.info("exril_5101_main", "收到BLE事件:", msg[2], msg[3])

            -- 设备重启
            if msg[2] == "REBOOT_DETECTED" then
                log.info("exril_5101_main", "检测到设备重启，重新初始化...")
                goto EXCEPTION_PROC
            end

            -- 蓝牙连接成功
            if msg[2] == "CONNECTED" then
                log.info("exril_5101_main", "蓝牙连接成功")
                -- 通知 sender 连接成功
                sys.sendMsg(exril_5101_sender.TASK_NAME, "BLE_EVENT", "CONNECTED", true)
            
            -- 蓝牙断开连接
            elseif msg[2] == "DISCONNECTED" then
                log.info("exril_5101_main", "蓝牙断开连接")
                -- 通知 sender 连接断开
                sys.sendMsg(exril_5101_sender.TASK_NAME, "BLE_EVENT", "DISCONNECTED")
            
            -- 收到数据
            elseif msg[2] == "DATA_RECV" then
                local payload = msg[3]
                if payload and payload.data then
                    -- 调用 receiver 处理接收到的数据
                    exril_5101_receiver.proc(payload.mode, payload.data)
                end
            end
        end

        -- 出现异常
        ::EXCEPTION_PROC::
        
        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)

        -- 5秒后跳转到循环体开始位置，自动重新初始化
        log.info("exril_5101_main", "等待5秒后重新尝试...")
        sys.wait(5000)
    end
end

-- 启动主任务
sys.taskInitEx(exril_5101_main_task_func, TASK_NAME)
