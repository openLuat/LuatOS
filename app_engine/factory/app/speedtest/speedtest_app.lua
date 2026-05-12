--[[
@module  speedtest_app
@summary 网络测速业务逻辑层
@version 1.0
@date    2026.04.28
@author  江访
@usage
本模块基于 Cloudflare speedtest API 实现网络测速功能：
1. 延迟与抖动测试（5次采样取最小值）
2. 下载速度测试（32KB 文件）
3. 上传速度测试（16KB 数据）
测速结果通过 SPDTEST_RESULT 事件发布。
]]

local BASE_URL = "http://speed.cloudflare.com"
local is_testing = false
local network_connected = false
local cancel_requested = false
local TIME_FACTOR_MS = 1

local bsp = rtos.bsp()
if string.find(bsp, "Air1601") or string.find(bsp, "Air1602") then
    TIME_FACTOR_MS = 20
end

--[[
@function measure_latency_and_jitter
@summary 测量网络延迟与抖动
@return number 最小延迟（ms），失败返回 nil
@return number 抖动值（ms），失败返回 nil
]]
local function measure_latency_jitter()
    local rtt_samples = {}
    local sample_count = 5
    for i = 1, sample_count do
        local start_ticks = mcu.ticks()
        local response = http.request("GET", BASE_URL .. "/__down?bytes=0&nocache=" .. tostring(mcu.ticks()), nil, nil, {timeout=5000})
        if response and response.wait then
            local code, headers, body = response.wait()
            local end_ticks = mcu.ticks()
            if code == 200 then
                local rtt = (end_ticks - start_ticks) * TIME_FACTOR_MS
                table.insert(rtt_samples, rtt)
                log.info("speedtest", "RTT sample " .. i .. ": " .. rtt .. " ms")
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
    if #rtt_samples == 0 then return nil, nil end
    table.sort(rtt_samples)
    local min_latency = rtt_samples[1]
    local jitter = 0
    if #rtt_samples >= 2 then
        local diffs = {}
        for i = 1, #rtt_samples - 1 do
            table.insert(diffs, math.abs(rtt_samples[i + 1] - rtt_samples[i]))
        end
        local diff_total = 0
        for _, v in ipairs(diffs) do diff_total = diff_total + v end
        jitter = diff_total / #diffs
    end
    return min_latency, jitter
end

--[[
@function measure_download
@summary 测量下载速度
@return number 下载速度（Mbps），失败返回 nil
]]
local function measure_download()
    local total_bytes = 32 * 1024
    local url = BASE_URL .. "/__down?bytes=" .. tostring(total_bytes) .. "&t=" .. tostring(mcu.ticks())
    log.info("speedtest", "Starting download test, size: 32KB")
    local start_ticks = mcu.ticks()
    local response = http.request("GET", url, nil, nil, {timeout=15000})
    if not response or not response.wait then
        log.error("speedtest", "Download request failed, no result object")
        return nil
    end
    local code, headers, body = response.wait()
    local end_ticks = mcu.ticks()
    if code ~= 200 or not body then
        log.error("speedtest", "Download test failed, code: " .. tostring(code))
        return nil
    end
    local duration_ms = (end_ticks - start_ticks) * TIME_FACTOR_MS
    if duration_ms < 10 then duration_ms = 10 end
    local duration_sec = duration_ms / 1000
    local total_bits = #body * 8
    local speed_mbps = (total_bits / duration_sec) / 1000000
    log.info("speedtest", "Download: " .. string.format("%.2f", speed_mbps) .. " Mbps, time: " .. duration_ms .. "ms")
    return speed_mbps
end

--[[
@function measure_upload
@summary 测量上传速度
@return number 上传速度（Mbps），失败返回 nil
]]
local function measure_upload()
    local total_bytes = 16 * 1024
    local url = BASE_URL .. "/__up"
    local test_data = string.char(0xAA):rep(total_bytes)
    log.info("speedtest", "Starting upload test, size: 16KB")
    local start_ticks = mcu.ticks()
    local response = http.request("POST", url, {["Content-Type"] = "application/octet-stream"}, test_data, {timeout=15000})
    if not response or not response.wait then
        log.error("speedtest", "Upload request failed, no result object")
        return nil
    end
    local code, headers, body = response.wait()
    local end_ticks = mcu.ticks()
    if code ~= 200 then
        log.error("speedtest", "Upload test failed, code: " .. tostring(code))
        return nil
    end
    local duration_ms = (end_ticks - start_ticks) * TIME_FACTOR_MS
    if duration_ms < 10 then duration_ms = 10 end
    local duration_sec = duration_ms / 1000
    local total_bits = total_bytes * 8
    local speed_mbps = (total_bits / duration_sec) / 1000000
    log.info("speedtest", "Upload: " .. string.format("%.2f", speed_mbps) .. " Mbps, time: " .. duration_ms .. "ms")
    return speed_mbps
end

--[[
@function run_speed_test_task
@summary 运行完整的网络测速流程（延迟->下载->上传）
]]
local function run_speedtest()
    if is_testing then return end
    if not network_connected then
        sys.publish("SPDTEST_STATUS", "当前未连接网络")
        return
    end
    cancel_requested = false
    is_testing = true
    sys.publish("SPDTEST_STARTED")
    sys.publish("SPDTEST_STATUS", "测延迟 & 抖动...")
    sys.wait(100)
    if cancel_requested then
        cancel_requested = false
        sys.publish("SPDTEST_STATUS", "测速已取消")
        sys.publish("SPDTEST_FINISHED")
        is_testing = false
        return
    end
    local ping_ms, jitter = measure_latency_jitter()
    if not network_connected then
        is_testing = false
        return
    end
    sys.publish("SPDTEST_STATUS", "测试下载速度...")
    sys.wait(100)
    if cancel_requested then
        cancel_requested = false
        sys.publish("SPDTEST_STATUS", "测速已取消")
        sys.publish("SPDTEST_FINISHED")
        is_testing = false
        return
    end
    local download_speed = measure_download()
    if not network_connected then
        is_testing = false
        return
    end
    sys.publish("SPDTEST_STATUS", "测试上传速度...")
    sys.wait(100)
    if cancel_requested then
        cancel_requested = false
        sys.publish("SPDTEST_STATUS", "测速已取消")
        sys.publish("SPDTEST_FINISHED")
        is_testing = false
        return
    end
    local upload_speed = measure_upload()
    if not network_connected then
        is_testing = false
        return
    end
    local test_result = {
        download = download_speed,
        upload = upload_speed,
        ping = ping_ms,
        jitter = jitter
    }
    sys.publish("SPDTEST_RESULT", test_result)
    if download_speed or upload_speed then
        sys.publish("SPDTEST_STATUS", "测速完成")
    else
        sys.publish("SPDTEST_STATUS", "部分失败，请重试")
    end
    is_testing = false
    sys.publish("SPDTEST_FINISHED")
    log.info("speedtest", "Speed test completed")
end

sys.subscribe("SPEEDTEST_START", function()
    sys.taskInit(run_speedtest)
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

sys.subscribe("SPEEDTEST_CANCEL", function()
    cancel_requested = true
    is_testing = false
end)
