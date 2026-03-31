

sys.taskInit(function()
    log.info("wlan_test", "开始 wlan 模块测试")
    wlan.init()
    sys.wait(1000)  -- 等待模块初始化完成
    
    wlan.scan()
    sys.waitUntil("WLAN_SCAN_DONE", 10000)
    -- 检查搜索结构
    local results = wlan.scanResult()
    assert(type(results) == "table", "scanResult 应返回 table")
    assert(#results >= 1, "scan 应返回至少 1 个 AP")
    log.info("wlan_test", "扫描到 AP 数量:", #results)
    -- 验证 luatos1234 在结果中
    local found = false
    for _, ap in ipairs(results) do
        log.info("wlan_test", "AP:", ap.ssid, "rssi:", ap.rssi, "ch:", ap.ch)
        if ap.ssid == "luatos1234" then
            found = true
        end
    end
    assert(found, "scan 结果中应包含 luatos1234")

    -- 测试 ready 状态 (未连接时)
    wlan.disconnect()
    sys.wait(500)
    local r = wlan.ready()
    log.info("wlan_test", "ready:", r)
    -- 测试 connect 和 IP_READY 事件
    wlan.connect("luatos1234", "12341234")
    local result = sys.waitUntil("IP_READY", 10000)
    assert(result, "connect 后未收到 IP_READY")
    log.info("wlan_test", "connect 成功, ready:", wlan.ready())
    -- 测试 disconnect 和 reconnect
    wlan.disconnect()
    sys.wait(500)
    log.info("wlan_test", "disconnect 后 ready:", wlan.ready())
    wlan.connect("luatos1234", "12341234")
    result = sys.waitUntil("IP_READY", 10000)
    assert(result, "reconnect 后未收到 IP_READY")
    log.info("wlan_test", "reconnect 成功, ready:", wlan.ready())
end)

sys.run()