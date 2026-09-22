-- httpsrv 全网卡绑定(socket.LWIP_ANY)功能测试
-- PC模拟器: 验证 start/冲突拒绝/stop; PC 上 lwip 无就绪网卡, HTTP 回环降级跳过
-- 真机: 额外验证 HTTP 回环(STA/AP 双网卡场景)
-- 注意: 用例内部步骤有顺序依赖(start->dup->roundtrip->stop), 集中在单个test_函数内保证执行顺序
local M = {}

local TEST_PORT = 18080

local function on_request(client, method, uri, headers, body)
    log.info("httpsrv_test", "on_request", method, uri)
    return 200, {}, "hello httpsrv"
end

-- 等待socket到达指定状态
local function wait_state(netc, target, timeout_ms, desc)
    local deadline = timeout_ms / 100
    for i = 1, deadline do
        sys.wait(100)
        local st = socket.state(netc)
        if st == target then return true end
    end
    local st, str = socket.state(netc)
    error(string.format("%s: expected state %d, got %d(%s)", desc, target, st, tostring(str)))
end

function M.test_httpsrv_any_bind()
    log.info("test", "=== test_httpsrv_any_bind ===")

    -- 步骤1: 绑定全部网卡启动
    local ok = httpsrv.start(TEST_PORT, on_request, socket.LWIP_ANY)
    log.info("test", "start with LWIP_ANY:", ok)
    assert(ok == true, "httpsrv.start with socket.LWIP_ANY should return true")

    -- 步骤2: 同端口重复启动被拒绝
    ok = httpsrv.start(TEST_PORT, on_request, socket.LWIP_ANY)
    log.info("test", "dup start:", ok)
    assert(not ok, "duplicate httpsrv.start on same port should fail")

    -- 步骤3: ANY与具体网卡同端口冲突被拒绝
    -- PC上具体网卡未就绪会提前返回失败, 两种路径结果一致(不成功)
    ok = httpsrv.start(TEST_PORT, on_request, socket.LWIP_STA)
    log.info("test", "conflict start:", ok)
    assert(not ok, "start with specific adapter on ANY-bound port should fail")

    -- 步骤4: HTTP 回环, 仅当就绪网卡是LWIP协议栈(1~16)时才可能成功
    -- PC上就绪的是ETH0(=17, posix协议栈), 与lwip内的httpsrv是两套协议栈, 互通不了, 跳过
    local isReady, adapter = socket.adapter()
    if isReady and adapter and adapter >= 1 and adapter <= 16 then
        local ip = socket.localIP(adapter)
        log.info("test", "roundtrip via ip", ip, "adapter", adapter)
        if ip and ip ~= "0.0.0.0" then
            local cli = socket.create(adapter)
            assert(cli, "socket create failed")
            socket.config(cli)
            local succ = socket.connect(cli, ip, TEST_PORT)
            assert(succ, "connect to httpsrv failed")
            wait_state(cli, 5, 5000, "client online") -- NW_STATE_ONLINE = 5
            succ = socket.tx(cli, "GET / HTTP/1.0\r\nHost: test\r\n\r\n")
            assert(succ, "tx http request failed")
            local rx_buff = zbuff.create(1024)
            for i = 1, 50 do
                sys.wait(100)
                local _, len = socket.rx(cli, rx_buff)
                if len and len > 0 then break end
            end
            local resp = rx_buff:used() > 0 and rx_buff:toStr(0, rx_buff:used()) or ""
            rx_buff:del()
            socket.close(cli)
            log.info("test", "http resp:", resp)
            assert(resp:find("200"), "expected 200 response, got: " .. resp)
            assert(resp:find("hello httpsrv"), "expected body, got: " .. resp)
        end
    else
        log.warn("test", "no IP READY lwip netif, skip http roundtrip")
    end

    -- 步骤5: 停止服务
    ok = httpsrv.stop(TEST_PORT, nil, socket.LWIP_ANY)
    log.info("test", "stop:", ok)
    assert(ok == true, "httpsrv.stop should return true")

    -- 步骤6: 重复停止被拒绝
    ok = httpsrv.stop(TEST_PORT, nil, socket.LWIP_ANY)
    log.info("test", "dup stop:", ok)
    assert(not ok, "second httpsrv.stop should fail")

    sys.wait(500)
    log.info("test", "=== test_httpsrv_any_bind PASSED ===")
end

return M
