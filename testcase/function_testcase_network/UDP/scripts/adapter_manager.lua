local adapter_manager = {}
local device_name = rtos.bsp()
local wifi_manager = require("wifi_manager")

local cached_adapters = nil
local wifi_prepared = false
local wifi_connection_attempted = false

-- 获取设备支持的适配器列表
function adapter_manager.get_supported_adapters()
    if cached_adapters then
        return cached_adapters
    end
    
    local adapters = {}
    
    -- 所有设备都支持默认适配器
    table.insert(adapters, {
        name = "默认",
        adapter = nil,
        type = "default",
        need_wifi = false
    })
    
    -- Air8000: 支持4G和WiFi
    if device_name == "Air8000" then
        table.insert(adapters, {
            name = "LWIP_GP",
            adapter = socket.LWIP_GP,
            type = "4g",
            need_wifi = false
        })
        table.insert(adapters, {
            name = "LWIP_STA",
            adapter = socket.LWIP_STA,
            type = "wifi",
            need_wifi = true
        })
    -- Air780系列: 只支持4G
    elseif device_name == "Air780EPM" or device_name == "Air780EHM" or device_name == "Air780E" then
        table.insert(adapters, {
            name = "LWIP_GP",
            adapter = socket.LWIP_GP,
            type = "4g",
            need_wifi = false
        })
    -- Air8101: 支持WiFi
    elseif device_name == "Air8101" then
        table.insert(adapters, {
            name = "LWIP_STA",
            adapter = socket.LWIP_STA,
            type = "wifi",
            need_wifi = true
        })
    end
    
    cached_adapters = adapters
    return adapters
end

-- 预连接WiFi（只执行一次）
function adapter_manager.prepare_wifi_once()
    if wifi_connection_attempted then
        return wifi_prepared
    end
    
    wifi_connection_attempted = true
    
    local adapters = adapter_manager.get_supported_adapters()
    local has_wifi = false
    
    for _, adapter_info in ipairs(adapters) do
        if adapter_info.type == "wifi" then
            has_wifi = true
            break
        end
    end
    
    if has_wifi then
        log.info("adapter_manager", "检测到WiFi适配器，开始预连接...")
        wifi_prepared = wifi_manager.connect()
        if wifi_prepared then
            log.info("adapter_manager", "✓ WiFi预连接成功")
        else
            log.warn("adapter_manager", "✗ WiFi预连接失败，将跳过WiFi测试项")
        end
    else
        wifi_prepared = false
        log.info("adapter_manager", "当前设备不支持WiFi，跳过WiFi预连接")
    end
    
    return wifi_prepared
end

-- 获取所有可测试的适配器
function adapter_manager.get_testable_adapters()
    local adapters = adapter_manager.get_supported_adapters()
    local testable = {}
    
    for _, adapter_info in ipairs(adapters) do
        -- WiFi适配器需要检查是否已连接
        if adapter_info.type == "wifi" then
            if wifi_prepared and wifi_manager.is_connected() then
                table.insert(testable, adapter_info)
            else
                log.info("adapter_manager", string.format("适配器 [%s] WiFi未连接，已跳过", adapter_info.name))
            end
        else
            -- 非WiFi适配器直接加入
            table.insert(testable, adapter_info)
        end
    end
    
    return testable
end

return adapter_manager