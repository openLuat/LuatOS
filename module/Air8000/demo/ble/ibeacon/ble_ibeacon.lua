--[[
@module  ble_ibeacon
@summary Air8000演示ibeacon功能模块
@version 1.0
@date    2025.11.18
@author  wangshihao
@usage
本文件为Air8000核心板演示ibeacon功能的代码示例，核心业务逻辑为：
1. 初始化蓝牙底层框架
2. 创建BLE对象实例
3. 配置ibeacon广播数据包
    - 包含厂商特定数据格式,ibeacon类型标识符
    - 设置UUID、Major、Minor等关键参数
4. 启动BLE广播功能
]]

-- 广播状态
local adv_state = false
-- WiFi和蓝牙状态 (1=开启, 0=关闭)
local wifi_state = 1

local function wifi_state_change(state)
    wifi_state = state
    log.info("ble_ibeacon", "收到WiFi状态变化:", state)
    
    -- 如果是关闭状态，将广播状态设置为false，并释放已创建的BLE资源
    if state == 0 and adv_state then
        adv_state = false
        -- 释放已创建的BLE资源
        ble_device = nil
        bluetooth_device = nil
        adv_create = nil
    else
        -- WiFi状态打开时发布消息
        sys.publish("WIFI_STATE_OPEN")
    end
end

-- 订阅WiFi和蓝牙状态变化消息
sys.subscribe("WIFI_STATE_CHANGED", wifi_state_change)

local function wifi_state_change(state)
    wifi_state = state
    log.info("ble_ibeacon", "收到WiFi状态变化:", state)
    
    if state == 0 then
        -- 如果是关闭状态，将广播状态设置为false，并释放已创建的BLE资源
        if adv_state then
            adv_state = false
            -- 释放已创建的BLE资源
            ble_device = nil
            bluetooth_device = nil
            adv_create = nil
        end
    else
        -- WiFi状态打开时发布消息
        sys.publish("WIFI_ACTIVATED", state)
    end
end

-- 订阅WiFi和蓝牙状态变化消息
sys.subscribe("WIFI_STATE_CHANGED", wifi_state_change)

-- 配置ibeacon广播数据包
local ibeacon_data = string.char(0x4C, 0x00, -- Manufacturer ID（2字节）
                            0x02, -- ibeacon数据类型（1字节）
                            0x15, -- ibeacon数据长度（1字节）
                            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, -- UUID（16字节）
                            0x00, 0x01, -- Major（2字节）
                            0x00, 0x02, -- Minor（2字节）
                            0xC0) -- Signal Power（1字节）

-- 事件回调函数
function ble_callback(ble_device, ble_event)
    if ble_event == ble.EVENT_ADV_START then
        log.info("iBeacon", "广播已成功启动")
        adv_state = true
    elseif ble_event == ble.EVENT_ADV_STOP then
        log.info("iBeacon", "广播已停止，等待重新启动")
        adv_state = false
    end
end

function ble_ibeacon_task_func()
    while true do
        -- 检查WiFi状态
        if wifi_state == 0 then
            log.info("ble_ibeacon", "WiFi关闭，等待WiFi开启...")
            sys.waitUntil("WIFI_STATE_OPEN")
            goto CONTINUE_LOOP
        end

        -- 初始化蓝牙核心
        bluetooth_device = bluetooth_device or bluetooth.init()
        if not bluetooth_device then
            log.error("BLE", "蓝牙初始化失败")
            goto EXCEPTION_PROC
        end

        -- 初始化BLE功能
        ble_device = ble_device or bluetooth_device:ble(ble_callback)
        if not ble_device then
            log.error("BLE", "当前固件不支持完整的BLE")
            goto EXCEPTION_PROC
        end

        -- 设置广播内容
        -- 由于没有 "COMPLETE_LOCAL_NAME" ,故仅安卓可用
        adv_create = adv_create or ble_device:adv_create({
            addr_mode = ble.PUBLIC, -- 广播地址模式, 仅支持: ble.PUBLIC
            channel_map = ble.CHNLS_ALL, -- 广播的通道, 可选值: ble.CHNL_37, ble.CHNL_38, ble.CHNL_39, ble.CHNLS_ALL
            intv_min = 120, -- 广播间隔最小值, 单位为0.625ms, 最小值为20, 最大值为10240
            intv_max = 120, -- 广播间隔最大值, 单位为0.625ms, 最小值为20, 最大值为10240
            adv_data = { -- 支持表格形式, 也支持字符串形式(255字节以内)
                {ble.FLAGS, string.char(0x06)}, -- 广播标志位
                {ble.MANUFACTURER_SPECIFIC_DATA, ibeacon_data}, -- 厂商特定数据, 包含ibeacon数据
            }
        })

        if not adv_create then
            log.error("BLE", "BLE创建广播失败")
            goto EXCEPTION_PROC
        end

        log.info("开始广播")
        if not ble_device:adv_start() then
            log.error("BLE", "BLE广播启动失败")
            goto EXCEPTION_PROC
        end

        adv_state = true

        -- 等待直到广播停止
        while adv_state do
            sys.wait(1000)
        end
        ::EXCEPTION_PROC::

        log.info("iBeacon", "检测到广播停止，准备重新初始化")
        -- 停止广播
        if ble_device then
            ble_device:adv_stop()
        end

        ::CONTINUE_LOOP::
        -- 5秒后跳转到循环体开始位置，重新广播
        log.info("ble_ibeacon", "等待5秒后重新广播")
        sys.wait(5000)
    end
end

sys.taskInit(ble_ibeacon_task_func)