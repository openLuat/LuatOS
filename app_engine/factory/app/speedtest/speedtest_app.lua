-- Naming convention: local fns ≤5 chars, local vars ≤4 chars
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

local BU = "http://speed.cloudflare.com"
local it = false
local nc = false
local TF = 1

local bsp = rtos.bsp()
if string.find(bsp, "Air1601") or string.find(bsp, "Air1602") then
    TF = 20
end

--[[
@function measure_latency_and_jitter
@summary 测量网络延迟与抖动
@return number 最小延迟（ms），失败返回 nil
@return number 抖动值（ms），失败返回 nil
]]
local function mlj()
    local rt = {}
    local sc = 5
    for i = 1, sc do
        local st = mcu.ticks()
        local rs = http.request("GET", BU .. "/__down?bytes=0&nocache=" .. tostring(mcu.ticks()), nil, nil, {timeout=5000})
        if rs and rs.wait then
            local cd, hd, bd = rs.wait()
            local et = mcu.ticks()
            if cd == 200 then
                local rtt = (et - st) * TF
                table.insert(rt, rtt)
                log.info("spdt", "RTT sample " .. i .. ": " .. rtt .. " ms")
            else
                log.warn("spdt", "Latency request failed, code: " .. tostring(cd))
            end
        else
            log.warn("spdt", "Latency request failed, no result object")
        end
        if i < sc then
            sys.wait(150)
        end
    end
    if #rt == 0 then return nil, nil end
    table.sort(rt)
    local ml = rt[1]
    local jt = 0
    if #rt >= 2 then
        local df = {}
        for i = 1, #rt - 1 do
            table.insert(df, math.abs(rt[i + 1] - rt[i]))
        end
        local sm = 0
        for _, v in ipairs(df) do sm = sm + v end
        jt = sm / #df
    end
    return ml, jt
end

--[[
@function measure_download
@summary 测量下载速度
@return number 下载速度（Mbps），失败返回 nil
]]
local function mdl()
    local tb = 32 * 1024
    local url = BU .. "/__down?bytes=" .. tostring(tb) .. "&t=" .. tostring(mcu.ticks())
    log.info("spdt", "Starting download test, size: 32KB")
    local st = mcu.ticks()
    local rs = http.request("GET", url, nil, nil, {timeout=15000})
    if not rs or not rs.wait then
        log.error("spdt", "Download request failed, no result object")
        return nil
    end
    local cd, hd, bd = rs.wait()
    local et = mcu.ticks()
    if cd ~= 200 or not bd then
        log.error("spdt", "Download test failed, code: " .. tostring(cd))
        return nil
    end
    local dm = (et - st) * TF
    if dm < 10 then dm = 10 end
    local ds = dm / 1000
    local bt = #bd * 8
    local sm = (bt / ds) / 1000000
    log.info("spdt", "Download: " .. string.format("%.2f", sm) .. " Mbps, time: " .. dm .. "ms")
    return sm
end

--[[
@function measure_upload
@summary 测量上传速度
@return number 上传速度（Mbps），失败返回 nil
]]
local function mul()
    local tb = 16 * 1024
    local url = BU .. "/__up"
    local td = string.char(0xAA):rep(tb)
    log.info("spdt", "Starting upload test, size: 16KB")
    local st = mcu.ticks()
    local rs = http.request("POST", url, {["Content-Type"] = "application/octet-stream"}, td, {timeout=15000})
    if not rs or not rs.wait then
        log.error("spdt", "Upload request failed, no result object")
        return nil
    end
    local cd, hd, bd = rs.wait()
    local et = mcu.ticks()
    if cd ~= 200 then
        log.error("spdt", "Upload test failed, code: " .. tostring(cd))
        return nil
    end
    local dm = (et - st) * TF
    if dm < 10 then dm = 10 end
    local ds = dm / 1000
    local bt = tb * 8
    local sm = (bt / ds) / 1000000
    log.info("spdt", "Upload: " .. string.format("%.2f", sm) .. " Mbps, time: " .. dm .. "ms")
    return sm
end

--[[
@function run_speed_test_task
@summary 运行完整的网络测速流程（延迟->下载->上传）
]]
local function rstt()
    if it then return end
    if not nc then
        sys.publish("SPDTEST_STATUS", "当前未连接网络")
        return
    end
    it = true
    sys.publish("SPDTEST_STARTED")
    sys.publish("SPDTEST_STATUS", "测延迟 & 抖动...")
    sys.wait(100)
    local pg, jt = mlj()
    if not nc then
        it = false
        return
    end
    sys.publish("SPDTEST_STATUS", "测试下载速度...")
    sys.wait(100)
    local dl = mdl()
    if not nc then
        it = false
        return
    end
    sys.publish("SPDTEST_STATUS", "测试上传速度...")
    sys.wait(100)
    local ul = mul()
    if not nc then
        it = false
        return
    end
    local rs = {
        download = dl,
        upload = ul,
        ping = pg,
        jitter = jt
    }
    sys.publish("SPDTEST_RESULT", rs)
    if dl or ul then
        sys.publish("SPDTEST_STATUS", "测速完成")
    else
        sys.publish("SPDTEST_STATUS", "部分失败，请重试")
    end
    it = false
    sys.publish("SPDTEST_FINISHED")
    log.info("spdt", "Speed test completed")
end

sys.subscribe("SPEEDTEST_START", function()
    sys.taskInit(rstt)
end)

sys.subscribe("IP_READY", function()
    nc = true
    log.info("spdt", "网络已连接")
end)

sys.subscribe("IP_LOSE", function()
    nc = false
    if it then
        it = false
        sys.publish("SPDTEST_STATUS", "网络已断开")
        sys.publish("SPDTEST_FINISHED")
    end
    log.info("spdt", "网络已断开")
end)
