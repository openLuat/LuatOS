-- TCP Server 监听功能测试
-- 仅PC模拟器运行, 通过状态轮询验证
local M = {}

-- 辅助: 等待socket到达指定状态
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

-- Test 1: 验证 listen 能正常启动并到达 LISTEN 状态
function M.test_tcp_server_listen()
    log.info("test", "=== test_tcp_server_listen ===")
    local netc = socket.create(socket.ETH0)
    assert(netc, "socket create failed")
    socket.config(netc, 18765)

    local succ, result = socket.listen(netc)
    log.info("test", "listen:", succ, result)
    assert(succ, "socket.listen failed")

    -- NW_STATE_LISTEN = 6
    wait_state(netc, 6, 5000, "listen")
    log.info("test", "state:", socket.state(netc))

    socket.close(netc)
    sys.wait(1000)
    log.info("test", "listen test PASSED")
end

-- Test 2: 自连接测试 - server 和 client 在同一进程内通信
-- 使用 socket.state 轮询代替回调, 避免回调链的异步问题
function M.test_tcp_server_self_connect()
    log.info("test", "=== test_tcp_server_self_connect ===")
    local TEST_PORT = 18766

    -- 创建 server socket (不使用回调)
    local srv = socket.create(socket.ETH0)
    assert(srv, "server create failed")
    socket.config(srv, TEST_PORT)
    socket.debug(srv, true)

    -- 启动监听
    local succ, result = socket.listen(srv)
    log.info("test", "listen:", succ, result)
    assert(succ, "listen failed")

    -- 等待 LISTEN 状态 (6)
    wait_state(srv, 6, 5000, "server listen")
    log.info("test", "server listening on port", TEST_PORT)

    -- 预接受 (一对一模式)
    socket.accept(srv, nil)

    -- 创建 client socket
    local cli = socket.create(socket.ETH0)
    assert(cli, "client create failed")
    socket.config(cli)
    socket.debug(cli, true)

    -- 客户端连接到服务端
    succ, result = socket.connect(cli, "127.0.0.1", TEST_PORT)
    log.info("test", "connect:", succ, result)
    assert(succ, "connect failed")

    -- 等待 client 到 ONLINE (5)
    wait_state(cli, 5, 5000, "client online")
    log.info("test", "client connected")

    -- 等待 server 到 ONLINE (5) (收到客户端连接)
    wait_state(srv, 5, 5000, "server online")
    log.info("test", "server saw client connection")

    -- 客户端发送 PING
    succ = socket.tx(cli, "PING")
    log.info("test", "client tx PING:", succ)
    assert(succ, "tx PING failed")

    -- 等待服务端收到数据 (轮询 socket.rx 返回的长度)
    local rx_buff = zbuff.create(1024)
    for i = 1, 50 do
        sys.wait(100)
        local ok, len = socket.rx(srv)
        if ok and len and len > 0 then break end
    end

    -- 服务端读取数据
    local ok, len = socket.rx(srv, rx_buff)
    log.info("test", "server rx:", ok, len, "used:", rx_buff:used())
    assert(ok, "server rx failed")
    assert(rx_buff:used() > 0, "server rx buffer empty")
    local srv_data = rx_buff:toStr(0, rx_buff:used())
    log.info("test", "server received:", srv_data)
    assert(srv_data == "PING", "expected PING, got: " .. tostring(srv_data))
    rx_buff:del()

    -- 服务端发送 PONG
    succ = socket.tx(srv, "PONG")
    log.info("test", "server tx PONG:", succ)
    assert(succ, "tx PONG failed")

    -- 等待客户端收到数据
    for i = 1, 50 do
        sys.wait(100)
        local ok, len = socket.rx(cli)
        if ok and len and len > 0 then break end
    end

    -- 客户端读取数据
    ok, len = socket.rx(cli, rx_buff)
    log.info("test", "client rx:", ok, len, "used:", rx_buff:used())
    assert(ok, "client rx failed")
    assert(rx_buff:used() > 0, "client rx buffer empty")
    local cli_data = rx_buff:toStr(0, rx_buff:used())
    log.info("test", "client received:", cli_data)
    assert(cli_data == "PONG", "expected PONG, got: " .. tostring(cli_data))

    -- 清理
    socket.close(cli)
    socket.close(srv)
    sys.wait(1000)

    log.info("test", "self-connect test PASSED")
end

return M
