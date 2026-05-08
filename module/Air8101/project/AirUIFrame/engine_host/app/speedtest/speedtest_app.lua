--[[
@module  speedtest_app
@summary 网络测速业务逻辑层
@version 1.0.0
@date    2026.04.28
]]

local BASE_URL = "http://speed.cloudflare.com"
local is_testing = false
local network_connected = false
local TICK_MS_FACTOR = 1
do
    local bsp = rtos.bsp()
    if string.find(bsp, "Air1601") or string.find(bsp, "Air1602") then
        TICK_MS_FACTOR = 20
    end
end

local function measure_latency_and_jitter()
    local rtts = {}
    local sample_count = 5
    for i = 1, sample_count do
        local start_time = mcu.ticks()
        local result = http.request("GET", BASE_URL .. "/__down?bytes=0&nocache=" .. tostring(mcu.ticks()), nil, nil, {timeout=5000})
        if result and result.wait then
            local code, headers, body = result.wait()
            local end_time = mcu.ticks()
            if code == 200 then
                local rtt = (end_time - start_time) * TICK_MS_FACTOR
                table.insert(rtts, rtt)
                log.info("speedtest", "RTT sample " .. i .. ": " .. string.format("%.0f", rtt) .. " ms")
            else
                log.warn("speedtest", "Latency request failed, code: " .. tostring(code))
            end
        else
            log.warn("speedtest", "Latency request failed, no result object")
        end
        if i < sample_count then
            sys.wait(150)
        end
    end
    if #rtts == 0 then return nil, nil end
    table.sort(rtts)
    local min_latency = rtts[1]
    local jitter = 0
    if #rtts >= 2 then
        local diffs = {}
        for i = 1, #rtts - 1 do
            table.insert(diffs, math.abs(rtts[i + 1] - rtts[i]))
        end
        local sum = 0
        for _, v in ipairs(diffs) do sum = sum + v end
        jitter = sum / #diffs
    end
    return min_latency, jitter
end

local function measure_download()
    local test_bytes = 32 * 1024
    local url = BASE_URL .. "/__down?bytes=" .. tostring(test_bytes) .. "&t=" .. tostring(mcu.ticks())
    log.info("speedtest", "Starting download test, size: 32KB")
    local start_time = mcu.ticks()
    local result = http.request("GET", url, nil, nil, {timeout=15000})
    if not result or not result.wait then
        log.error("speedtest", "Download request failed, no result object")
        return nil
    end
    local code, headers, body = result.wait()
    local end_time = mcu.ticks()
    if code ~= 200 or not body then
        log.error("speedtest", "Download test failed, code: " .. tostring(code))
        return nil
    end
    local duration_ms = (end_time - start_time) * TICK_MS_FACTOR
    if duration_ms < 10 then duration_ms = 10 end
    local duration_sec = duration_ms / 1000
    local bits = #body * 8
    local speed_mbps = (bits / duration_sec) / 1000000
    log.info("speedtest", "Download: " .. string.format("%.2f", speed_mbps) .. " Mbps, time: " .. duration_ms .. "ms")
    return speed_mbps
end

local function measure_upload()
    local test_bytes = 16 * 1024
    local url = BASE_URL .. "/__up"
    local test_data = string.char(0xAA):rep(test_bytes)

    log.info("speedtest", "Starting upload test, size: 16KB")
    local start_time = mcu.ticks()
    local result = http.request("POST", url, {["Content-Type"] = "application/octet-stream"}, test_data, {timeout=15000})
    if not result or not result.wait then
        log.error("speedtest", "Upload request failed, no result object")
        return nil
    end
    local code, headers, body = result.wait()
    local end_time = mcu.ticks()
    if code ~= 200 then
        log.error("speedtest", "Upload test failed, code: " .. tostring(code))
        return nil
    end
    local duration_ms = (end_time - start_time) * TICK_MS_FACTOR
    if duration_ms < 10 then duration_ms = 10 end
    local duration_sec = duration_ms / 1000
    local bits = test_bytes * 8
    local speed_mbps = (bits / duration_sec) / 1000000
    log.info("speedtest", "Upload: " .. string.format("%.2f", speed_mbps) .. " Mbps, time: " .. duration_ms .. "ms")
    return speed_mbps
end

local function run_speed_test_task()
    if is_testing then return end

    if not network_connected then
        sys.publish("SPDTEST_STATUS", "当前未连接网络")
        return
    end

    is_testing = true
    sys.publish("SPDTEST_STARTED")

    sys.publish("SPDTEST_STATUS", "测延迟 & 抖动...")
    sys.wait(100)
    local ping, jitter = measure_latency_and_jitter()
    if not network_connected then
        is_testing = false
        return
    end

    sys.publish("SPDTEST_STATUS", "测试下载速度...")
    sys.wait(100)
    local download = measure_download()
    if not network_connected then
        is_testing = false
        return
    end

    sys.publish("SPDTEST_STATUS", "测试上传速度...")
    sys.wait(100)
    local upload = measure_upload()
    if not network_connected then
        is_testing = false
        return
    end

    local results = {
        download = download,
        upload = upload,
        ping = ping,
        jitter = jitter
    }
    sys.publish("SPDTEST_RESULT", results)

    if download or upload then
        sys.publish("SPDTEST_STATUS", "测速完成")
    else
        sys.publish("SPDTEST_STATUS", "部分失败，请重试")
    end

    is_testing = false
    sys.publish("SPDTEST_FINISHED")
    log.info("speedtest", "Speed test completed")
end

sys.subscribe("SPEEDTEST_START", function()
    sys.taskInit(run_speed_test_task)
end)

sys.subscribe("IP_READY", function()
    network_connected = true
    log.info("speedtest", "网络已连接")
end)

sys.subscribe("IP_LOSE", function()
    network_connected = false
    if is_testing then
        is_testing = false
        sys.publish("SPDTEST_STATUS", "网络已断开")
        sys.publish("SPDTEST_FINISHED")
    end
    log.info("speedtest", "网络已断开")
end)

log.info("speedtest_app", "模块加载完成")
