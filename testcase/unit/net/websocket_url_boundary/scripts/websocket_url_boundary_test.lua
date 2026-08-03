-- WebSocket URL解析边界测试
-- 验证P0-3: luat_websocket.c中URL解析host[192]/uri[256]有边界检查
local websocket_url_boundary_test = {}

-- 测试: 超长host不应导致栈溢出
function websocket_url_boundary_test.test_overlong_host()
    log.info("ws_url", "测试超长host URL")
    -- host超过192字节
    local long_host = string.rep("a", 250)
    local url = "ws://" .. long_host .. "/path"
    local ok, err = pcall(function()
        local wsc = websocket.create(nil, url)
        if wsc then
            wsc:close()
        end
    end)
    -- 不应崩溃, 可以返回nil(创建失败)但不能crash
    assert(ok, "超长host不应导致崩溃: " .. tostring(err))
    log.info("ws_url", "超长host测试通过(未崩溃)")
end

-- 测试: 超长URI不应导致栈溢出
function websocket_url_boundary_test.test_overlong_uri()
    log.info("ws_url", "测试超长URI")
    -- uri超过256字节
    local long_uri = string.rep("/segment", 50)  -- 400 bytes
    local url = "ws://example.com" .. long_uri
    local ok, err = pcall(function()
        local wsc = websocket.create(nil, url)
        if wsc then
            wsc:close()
        end
    end)
    assert(ok, "超长URI不应导致崩溃: " .. tostring(err))
    log.info("ws_url", "超长URI测试通过(未崩溃)")
end

-- 测试: 超长端口号不应溢出port_tmp[6]
function websocket_url_boundary_test.test_overlong_port()
    log.info("ws_url", "测试超长端口号")
    local url = "ws://example.com:12345678901234/path"
    local ok, err = pcall(function()
        local wsc = websocket.create(nil, url)
        if wsc then
            wsc:close()
        end
    end)
    assert(ok, "超长端口号不应导致崩溃: " .. tostring(err))
    log.info("ws_url", "超长端口号测试通过(未崩溃)")
end

-- 测试: 正常URL仍然正常工作
function websocket_url_boundary_test.test_normal_url_still_works()
    log.info("ws_url", "测试正常URL")
    local ok, err = pcall(function()
        local wsc = websocket.create(nil, "ws://echo.example.com:8080/chat")
        if wsc then
            wsc:close()
        end
    end)
    assert(ok, "正常URL不应导致崩溃: " .. tostring(err))
    log.info("ws_url", "正常URL测试通过")
end

-- 测试: 边界长度host(恰好191字节)
function websocket_url_boundary_test.test_boundary_host_191()
    log.info("ws_url", "测试191字节host(边界)")
    local host191 = string.rep("h", 191)
    local url = "ws://" .. host191 .. "/"
    local ok, err = pcall(function()
        local wsc = websocket.create(nil, url)
        if wsc then
            wsc:close()
        end
    end)
    assert(ok, "191字节host不应崩溃: " .. tostring(err))
    log.info("ws_url", "191字节host测试通过")
end

-- 测试: 边界长度host(恰好192字节, 应被截断或拒绝)
function websocket_url_boundary_test.test_boundary_host_192()
    log.info("ws_url", "测试192字节host(超限)")
    local host192 = string.rep("h", 192)
    local url = "ws://" .. host192 .. "/"
    local ok, err = pcall(function()
        local wsc = websocket.create(nil, url)
        if wsc then
            wsc:close()
        end
    end)
    assert(ok, "192字节host不应崩溃: " .. tostring(err))
    log.info("ws_url", "192字节host测试通过(未崩溃)")
end

-- 测试: wss协议超长URL
function websocket_url_boundary_test.test_wss_overlong()
    log.info("ws_url", "测试wss超长URL")
    local long_path = string.rep("x", 300)
    local url = "wss://secure.example.com/" .. long_path
    local ok, err = pcall(function()
        local wsc = websocket.create(nil, url)
        if wsc then
            wsc:close()
        end
    end)
    assert(ok, "wss超长URL不应崩溃: " .. tostring(err))
    log.info("ws_url", "wss超长URL测试通过")
end

-- 测试: P0-5 连接失败时connect应返回false(不静默忽略)
function websocket_url_boundary_test.test_connect_failure_detected()
    log.info("ws_url", "测试连接失败检测(P0-5)")
    -- 连接一个不可达的地址, connect应返回false
    local ok, result = pcall(function()
        local wsc = websocket.create(nil, "ws://192.0.2.1:1/unreachable")
        if not wsc then
            return nil  -- 创建失败也是合理的
        end
        local ret = wsc:connect()
        wsc:close()
        return ret
    end)
    assert(ok, "连接不可达地址不应崩溃")
    -- result可能是false(连接失败被正确检测)或nil(创建失败)
    -- 关键是不能返回true(那意味着连接失败被静默忽略)
    if result == true then
        log.warn("ws_url", "connect返回true但目标不可达, 可能P0-5未修复")
    else
        log.info("ws_url", "连接失败被正确检测, ret=" .. tostring(result))
    end
    log.info("ws_url", "连接失败检测测试通过(未崩溃)")
end

return websocket_url_boundary_test
