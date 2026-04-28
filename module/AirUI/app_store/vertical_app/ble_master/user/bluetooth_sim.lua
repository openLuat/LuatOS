--[[
@module  bluetooth_sim
@summary 蓝牙BLE模拟器（PC环境）
@version 1.0.0
@date    2026.04.10
@author  王世豪
@usage
PC模拟器环境下的蓝牙BLE模拟实现
--]]

-- ==================== 模拟蓝牙模块 ====================
if not bluetooth then
    bluetooth = {}
    
    local mock_bluetooth_device = {
        ble_callbacks = {}
    }
    
    -- 模拟蓝牙初始化
    function bluetooth.init()
        log.info("BLUETOOTH_SIM", "模拟蓝牙初始化")
        return mock_bluetooth_device
    end
    
    -- 模拟BLE功能
    function mock_bluetooth_device:ble(callback)
        log.info("BLUETOOTH_SIM", "模拟BLE初始化")
        
        local mock_ble_device = {
            callbacks = {},
            scan_state = false,
            conn_state = false,
            scan_timer = nil,
            mock_devices = {
                {name = "BLE设备-A1", mac = "AABBCCDDEE01", rssi = -65},
                {name = "传感器节点", mac = "AABBCCDDEE02", rssi = -78},
                {name = "智能手环", mac = "AABBCCDDEE03", rssi = -52},
                {name = "蓝牙音箱", mac = "AABBCCDDEE04", rssi = -70},
                {name = "温度传感器", mac = "AABBCCDDEE05", rssi = -85}
            }
        }
        
        -- 保存回调
        if callback then
            table.insert(mock_ble_device.callbacks, callback)
        end
        
        -- 模拟扫描创建
        function mock_ble_device:scan_create(addr_mode, scan_interval, scan_window, scan_mode)
            log.info("BLUETOOTH_SIM", "模拟扫描创建")
            return true
        end
        
        -- 模拟扫描开始
        function mock_ble_device:scan_start()
            log.info("BLUETOOTH_SIM", "模拟扫描开始")
            mock_ble_device.scan_state = true
            
            -- 触发扫描初始化事件
            for _, cb in ipairs(mock_ble_device.callbacks) do
                cb(mock_ble_device, ble.EVENT_SCAN_INIT, {})
            end
            
            -- 模拟扫描报告
            local device_index = 1
            local function scan_report_timer()
                if not mock_ble_device.scan_state then return end
                
                if device_index <= #mock_ble_device.mock_devices then
                    local device = mock_ble_device.mock_devices[device_index]
                    local param = {
                        adv_addr = string.fromHex(device.mac),
                        rssi = device.rssi,
                        addr_type = 0,
                        data = string.fromHex("020106")  -- 模拟广播数据
                    }
                    
                    for _, cb in ipairs(mock_ble_device.callbacks) do
                        cb(mock_ble_device, ble.EVENT_SCAN_REPORT, param)
                    end
                    
                    device_index = device_index + 1
                end
            end
            mock_ble_device.scan_timer = sys.timerLoopStart(scan_report_timer, 1500)
            
            return true
        end
        
        -- 模拟扫描停止
        function mock_ble_device:scan_stop()
            log.info("BLUETOOTH_SIM", "模拟扫描停止")
            mock_ble_device.scan_state = false
            
            if mock_ble_device.scan_timer then
                sys.timerStop(mock_ble_device.scan_timer)
                mock_ble_device.scan_timer = nil
            end
            
            for _, cb in ipairs(mock_ble_device.callbacks) do
                cb(mock_ble_device, ble.EVENT_SCAN_STOP, {})
            end
            
            return true
        end
        
        -- 模拟连接
        function mock_ble_device:connect(addr_type, mac)
            log.info("BLUETOOTH_SIM", "模拟连接:", mac:toHex())
            
            local function on_connect_timeout()
                mock_ble_device.conn_state = true
                for _, cb in ipairs(mock_ble_device.callbacks) do
                    cb(mock_ble_device, ble.EVENT_CONN, {})
                end
            end
            sys.timerStart(on_connect_timeout, 1000)
            
            return true
        end
        
        -- 模拟断开连接
        function mock_ble_device:disconnect()
            log.info("BLUETOOTH_SIM", "模拟断开连接")
            
            mock_ble_device.conn_state = false
            for _, cb in ipairs(mock_ble_device.callbacks) do
                cb(mock_ble_device, ble.EVENT_DISCONN, {})
            end
            
            return true
        end
        
        -- 模拟广播数据解码
        function mock_ble_device:adv_decode(data)
            -- 简单模拟解码
            return {}
        end
        
        return mock_ble_device
    end
end

-- ==================== 模拟BLE常量 ====================
if not ble then
    ble = {}
    
    -- 事件类型
    ble.EVENT_SCAN_INIT = 1
    ble.EVENT_SCAN_REPORT = 2
    ble.EVENT_SCAN_STOP = 3
    ble.EVENT_CONN = 4
    ble.EVENT_DISCONN = 5
    ble.EVENT_WRITE = 6
    ble.EVENT_READ = 7
    ble.EVENT_ADV_START = 8
    ble.EVENT_ADV_STOP = 9
    
    -- 扫描模式
    ble.SCAN_ACTIVE = 0
    ble.SCAN_PASSIVE = 1
    
    -- 地址模式
    ble.PUBLIC = 0
    ble.RANDOM = 1
    
    -- 特征值属性
    ble.READ = 0x02
    ble.WRITE = 0x08
    ble.NOTIFY = 0x10
    ble.WRITE_CMD = 0x04
    
    -- 广播标志
    ble.FLAGS = 0x01
    ble.COMPLETE_LOCAL_NAME = 0x09
    ble.CHNLS_ALL = 0x07
end

log.info("BLUETOOTH_SIM", "蓝牙模拟模块已加载")
