--[[
@module  wifi_app
@summary WiFi业务层模块，扫描和结果缓存
@version 2.0
@date    2026.08.04
@author  江访
@usage
本模块没有对外接口，require 即加载运行：
1、订阅 WIFI_SCAN_REQ 执行扫描
2、扫描完成后发布 WIFI_SCAN_RESULT(results)
]]

-- 缓存最近一次扫描结果
local last_scan_results = {}
local scan_busy = false

--[[
WiFi 扫描协程：发起扫描并等待结果，然后发布 WIFI_SCAN_RESULT(results)
含 sys.waitUntil，故需放协程执行。

@local
@function wifi_scan_task
]]
local function wifi_scan_task()
    wlan.scan()
    sys.waitUntil("WLAN_SCAN_DONE", 20000)
    local results = wlan.scanResult()
    if results and type(results) == "table" then
        last_scan_results = results
        log.info("wifi_app", "scan done, results:", #results)
    else
        last_scan_results = {}
        log.warn("wifi_app", "scan done, no results")
    end
    scan_busy = false
    sys.publish("WIFI_SCAN_RESULT", last_scan_results)
end

--[[
执行WiFi扫描：防止并发扫描（scan_busy 互斥），启动扫描协程

@local
@function do_scan
]]
local function do_scan()
    if scan_busy then
        log.warn("wifi_app", "scan busy")
        return
    end
    scan_busy = true
    sys.taskInit(wifi_scan_task)
end

-- WIFI_SCAN_REQ 订阅
local function on_scan_req()
    do_scan()
end

sys.subscribe("WIFI_SCAN_REQ", on_scan_req)

log.info("wifi_app", "init done")
