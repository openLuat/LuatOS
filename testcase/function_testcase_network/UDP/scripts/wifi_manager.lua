-- -- [file name]: wifi_manager.lua
-- -- WiFi连接管理器，确保WiFi只连接一次
-- local wifi_manager = {}

-- local device_name = rtos.bsp()
-- local wifi_connected = false
-- local wifi_connecting = false

-- -- WiFi配置
-- local WIFI_CONFIG = {
--     ssid = "观看15秒广告解锁WiFi",
--     password = "qwertYUIOP"  -- 如果不需要密码就留空
-- }

-- -- 等待WiFi连接成功
-- local function wait_wifi_ready(timeout)
--     timeout = timeout or 30000
--     local steps = timeout / 100
--     for i = 1, steps do
--         if wlan and wlan.ready and wlan.ready() then
--             return true
--         end
--         -- 检查是否获取到IP
--         local ip = wlan and wlan.getIP and wlan.getIP()
--         if ip and ip ~= "0.0.0.0" then
--             return true
--         end
--         sys.wait(100)
--     end
--     return false
-- end

-- -- 连接WiFi（只执行一次）
-- function wifi_manager.connect()
--     if not wlan or not wlan.connect then
--         return false
--     end
    
--     if wifi_connected then
--         log.info("wifi_manager", "WiFi已连接，复用现有连接")
--         return true
--     end
    
--     if wifi_connecting then
--         log.info("wifi_manager", "WiFi正在连接中，等待...")
--         local timeout = 30000
--         local steps = timeout / 100
--         for i = 1, steps do
--             sys.wait(100)
--             if wifi_connected then
--                 return true
--             end
--         end
--         return wifi_connected
--     end
    
--     wifi_connecting = true
--     log.info("wifi_manager", string.format("开始连接WiFi: %s", WIFI_CONFIG.ssid))
    
--     -- 如果密码为空字符串，则使用nil
--     local password = WIFI_CONFIG.password
--     if password == "" then
--         password = nil
--     end
    
--     wlan.connect(WIFI_CONFIG.ssid, password, 1)
    
--     -- 等待IP就绪
--     local result = wait_wifi_ready(30000)
    
--     if result then
--         wifi_connected = true
--         local ip = wlan.getIP and wlan.getIP() or "未知"
--         log.info("wifi_manager", "✓ WiFi连接成功", ip)
--     else
--         wifi_connected = false
--         log.error("wifi_manager", "✗ WiFi连接失败")
--     end
    
--     wifi_connecting = false
--     return wifi_connected
-- end

-- -- 获取WiFi连接状态
-- function wifi_manager.is_connected()
--     if not wlan then
--         return false
--     end
--     local ready = wlan.ready and wlan.ready() or false
--     local ip = wlan.getIP and wlan.getIP() or "0.0.0.0"
--     return ready and ip ~= "0.0.0.0"
-- end

-- return wifi_manager


-- [file name]: wifi_manager.lua
-- WiFi连接管理器，确保WiFi只连接一次
local wifi_manager = {}

local device_name = rtos.bsp()
local wifi_connected = false
local wifi_connecting = false

-- WiFi配置 - 使用正确的WiFi信息
local WIFI_CONFIG = {
    ssid = "观看15秒广告解锁WiFi",
    password = "qwertYUIOP"  -- 如果是开放网络就留空，如果需要密码就填写
}

-- 等待WiFi连接成功
local function wait_wifi_ready(timeout)
    timeout = timeout or 30000
    local steps = timeout / 100
    for i = 1, steps do
        -- 检查wlan是否就绪
        if wlan and wlan.ready and wlan.ready() then
            local ip = wlan.getIP and wlan.getIP() or ""
            log.info("wifi_manager", string.format("WiFi已就绪, IP: %s", ip))
            return true
        end
        
        -- 检查是否获取到IP
        if wlan and wlan.getIP then
            local ip = wlan.getIP()
            if ip and ip ~= "0.0.0.0" and ip ~= "" then
                log.info("wifi_manager", string.format("已获取IP: %s", ip))
                return true
            end
        end
        
        -- 检查连接状态
        if wlan and wlan.getStatus then
            local status = wlan.getStatus()
            if status == "COMPLETED" or status == "CONNECTED" then
                log.info("wifi_manager", string.format("WiFi状态: %s", status))
                return true
            end
        end
        
        sys.wait(100)
    end
    return false
end

-- 连接WiFi（只执行一次）
function wifi_manager.connect()
    if not wlan or not wlan.connect then
        log.error("wifi_manager", "当前设备不支持WiFi功能")
        return false
    end
    
    if wifi_connected then
        log.info("wifi_manager", "WiFi已连接，复用现有连接")
        -- 获取当前IP
        local ip = wlan.getIP and wlan.getIP() or "未知"
        log.info("wifi_manager", string.format("当前IP: %s", ip))
        return true
    end
    
    if wifi_connecting then
        log.info("wifi_manager", "WiFi正在连接中，等待...")
        local timeout = 30000
        local steps = timeout / 100
        for i = 1, steps do
            sys.wait(100)
            if wifi_connected then
                return true
            end
            -- 检查是否意外连接成功
            if wlan.ready and wlan.ready() then
                wifi_connected = true
                wifi_connecting = false
                local ip = wlan.getIP and wlan.getIP() or "未知"
                log.info("wifi_manager", string.format("WiFi连接成功, IP: %s", ip))
                return true
            end
        end
        wifi_connecting = false
        log.error("wifi_manager", "WiFi连接超时")
        return false
    end
    
    wifi_connecting = true
    log.info("wifi_manager", string.format("开始连接WiFi: %s", WIFI_CONFIG.ssid))
    
    -- 处理密码
    local password = WIFI_CONFIG.password
    if password == "" then
        password = nil
    end
    
    -- 先断开已有连接
    pcall(function()
        if wlan.disconnect then
            wlan.disconnect()
            log.info("wifi_manager", "已断开现有WiFi连接")
        end
    end)
    sys.wait(1000)
    
    -- 连接WiFi
    log.info("wifi_manager", "正在发起WiFi连接...")
    local result = wlan.connect(WIFI_CONFIG.ssid, password, 1)
    log.info("wifi_manager", string.format("wlan.connect返回: %s", tostring(result)))
    
    -- 等待连接成功
    local connected = wait_wifi_ready(45000)  -- 增加超时时间到45秒
    
    if connected then
        wifi_connected = true
        local ip = wlan.getIP and wlan.getIP() or "未知"
        log.info("wifi_manager", string.format("✓ WiFi连接成功, IP: %s", ip))
        
        -- 额外等待一下，确保网络完全就绪
        sys.wait(1000)
    else
        wifi_connected = false
        -- 获取失败原因
        local reason = "未知"
        if wlan.getStatus then
            reason = wlan.getStatus() or "未知"
        end
        log.error("wifi_manager", string.format("✗ WiFi连接失败, 状态: %s", reason))
        
        -- 尝试获取更多信息
        if wlan.getLastError then
            local err = wlan.getLastError()
            log.error("wifi_manager", string.format("错误码: %s", tostring(err)))
        end
    end
    
    wifi_connecting = false
    return wifi_connected
end

-- 获取WiFi连接状态
function wifi_manager.is_connected()
    if not wlan then
        return false
    end
    
    -- 多种方式检查连接状态
    local ready = wlan.ready and wlan.ready() or false
    local ip = wlan.getIP and wlan.getIP() or "0.0.0.0"
    local status = wlan.getStatus and wlan.getStatus() or ""
    
    local connected = ready and ip ~= "0.0.0.0" and ip ~= ""
    if status == "COMPLETED" or status == "CONNECTED" then
        connected = true
    end
    
    return connected
end

-- 重新连接WiFi
function wifi_manager.reconnect()
    log.info("wifi_manager", "尝试重新连接WiFi...")
    wifi_connected = false
    wifi_connecting = false
    return wifi_manager.connect()
end

-- 获取WiFi信号强度
function wifi_manager.get_rssi()
    if wlan and wlan.getRSSI then
        return wlan.getRSSI()
    end
    return nil
end

return wifi_manager