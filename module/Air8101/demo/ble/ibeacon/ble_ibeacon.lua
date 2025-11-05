--[[
@module  ble_ibeacon
@summary Air8101演示ibeacon功能模块
@version 1.0
@date    2025.10.21
@author  wangshihao
@usage
本文件为Air8101核心板演示ibeacon功能的代码示例，核心业务逻辑为：
1. 初始化蓝牙底层框架
2. 创建BLE对象实例
3. 配置ibeacon广播数据包
    - 包含厂商特定数据格式,ibeacon类型标识符
    - 设置UUID、Major、Minor等关键参数
4. 启动BLE广播功能
]]

-- 广播本地名称
local device_name = "LuatOS"
-- 广播状态
local adv_state = false

-- 配置ibeacon广播数据包
local ibeacon_data = string.char(0x4C, 0x00, -- Manufacturer ID（2字节, 小端序）
                            0x02, 0x15, -- ibeacon数据类型（2字节, 小端序）
                            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, -- UUID（16字节, 大端序）
                            0x00, 0x01, -- Major（2字节, 小端序）
                            0x00, 0x02, -- Minor（2字节, 小端序）
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
            ble_device = nil
        end

        -- 5秒后跳转到循环体开始位置，重新广播
        sys.wait(5000)
    end
end

sys.taskInit(ble_ibeacon_task_func)