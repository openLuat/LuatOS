-- httpsrv 功能测试
-- PC模拟器: httpsrv 走宿主 socket 后端, 与浏览器同一套协议栈, 可以做真实 HTTP 往返
--           (回归 httpsrv 之前 PC 上只能"监听成功但收不到连接"的假成功)
-- 真机: 走 lwIP 后端, 绑定 socket.LWIP_ANY 全网卡
-- 注意: 各用例使用独立端口且自行 start/stop, 彼此无顺序依赖
local M = {}

local IS_PC = (rtos and rtos.bsp and rtos.bsp() == "PC")

-- 静态文件用例用它确认"文件确实被读出来并返回了"
local STATIC_MARKER = "HTTPSRV_STATIC_FILE_MARKER"

local last_req = {}

local function on_request(client, method, uri, headers, body)
    last_req.method = method
    last_req.uri = uri
    last_req.headers = headers
    last_req.body = body
    if uri == "/api/ok" then
        return 200, {["Content-Type"] = "application/json"}, '{"ok":true}'
    elseif uri == "/echo" then
        return 200, {["Content-Type"] = "text/plain"}, "echo:" .. tostring(body)
    end
    return 404, {}, "Not Found " .. uri
end

-- 找到可以用于 HTTP 往返的目标地址. 返回 nil 表示本平台当前无可用地址
local function resolve_target()
    if IS_PC then
        return "127.0.0.1", "PC 宿主 socket"
    end
    local ok, adapter = socket.adapter()
    if ok and adapter and adapter >= 1 and adapter <= 16 then
        local ip = socket.localIP(adapter)
        if ip and ip ~= "0.0.0.0" then
            return ip, "adapter " .. tostring(adapter)
        end
    end
    return nil, "no lwip netif"
end

-- 启动服务: PC 用默认 adapter(之前这条路径必然失败), 真机用 LWIP_ANY
local function start_server(port)
    if IS_PC then
        return httpsrv.start(port, on_request)
    end
    return httpsrv.start(port, on_request, socket.LWIP_ANY)
end

local function stop_server(port)
    if IS_PC then
        return httpsrv.stop(port, nil)
    end
    return httpsrv.stop(port, nil, socket.LWIP_ANY)
end

-- 等待 socket 到达指定状态
local function wait_state(netc, target, timeout_ms, desc)
    for _ = 1, timeout_ms / 100 do
        sys.wait(100)
        local st = socket.state(netc)
        if st == target then return true end
    end
    local st, str = socket.state(netc)
    error(string.format("%s: expected state %d, got %d(%s)", desc, target, st, tostring(str)))
end

-- 用 socket 发一次 HTTP 请求, 返回完整响应字符串
local function http_request(host, port, req, timeout_ms)
    local cli = socket.create()
    if not cli then return nil, "socket create failed" end
    socket.config(cli)
    if not socket.connect(cli, host, port) then
        socket.close(cli)
        return nil, "connect failed"
    end
    wait_state(cli, 5, 5000, "client online") -- NW_STATE_ONLINE = 5
    if not socket.tx(cli, req) then
        socket.close(cli)
        return nil, "tx failed"
    end
    local rx = zbuff.create(4096)
    for _ = 1, (timeout_ms or 5000) / 50 do
        sys.wait(50)
        local _, len = socket.rx(cli, rx)
        if len and len > 0 then break end
    end
    local resp = rx:used() > 0 and rx:toStr(0, rx:used()) or ""
    rx:del()
    socket.close(cli)
    return resp
end

local function start_roundtrip()
    local host, why = resolve_target()
    if not host then
        log.warn("test", "skip http roundtrip:", why)
        return nil
    end
    log.info("test", "roundtrip target", host, why)
    return host
end

-- 用例1: 端口被占时必须返回 false, 不能再出现"监听成功但没人能把包送进来"的假成功
function M.test_httpsrv_bind_conflict()
    log.info("test", "=== test_httpsrv_bind_conflict ===")
    local port = 18081
    if not IS_PC then
        log.warn("test", "skip: bind conflict check only covers PC host socket")
        return
    end

    -- 先用 socket 占住端口
    local hog = socket.create()
    assert(hog, "socket create failed")
    assert(socket.config(hog, port), "config listen port failed")
    assert(socket.listen(hog), "occupy port failed")
    log.info("test", "port", port, "occupied by socket.listen")

    -- httpsrv 再抢同一个端口必须失败
    local ok = httpsrv.start(port, on_request)
    log.info("test", "start on occupied port:", ok)
    assert(ok ~= true, "httpsrv.start on an occupied port must NOT report success")

    socket.close(hog)
    sys.wait(500)

    -- 端口释放后应能正常启动
    ok = httpsrv.start(port, on_request)
    log.info("test", "start after release:", ok)
    assert(ok == true, "httpsrv.start should succeed once the port is free")
    ok = httpsrv.stop(port, nil)
    assert(ok == true, "httpsrv.stop should return true")
    log.info("test", "=== test_httpsrv_bind_conflict PASSED ===")
end

-- 用例2: GET/POST 真实往返
function M.test_httpsrv_http_roundtrip()
    log.info("test", "=== test_httpsrv_http_roundtrip ===")
    local port = 18080
    local host = start_roundtrip()
    if not host then return end

    local ok = start_server(port)
    log.info("test", "start:", ok)
    assert(ok == true, "httpsrv.start should return true")

    -- GET
    local resp, err = http_request(host, port, "GET /api/ok HTTP/1.0\r\nHost: test\r\n\r\n")
    assert(resp, "GET failed: " .. tostring(err))
    log.info("test", "GET resp:", resp)
    assert(resp:find("200"), "expected 200 response, got: " .. resp)
    assert(resp:find('{"ok":true}'), "expected json body, got: " .. resp)
    assert(last_req.method == "GET", "expected method GET, got " .. tostring(last_req.method))
    assert(last_req.uri == "/api/ok", "expected uri /api/ok, got " .. tostring(last_req.uri))

    -- POST 带 body
    resp, err = http_request(host, port, "POST /echo HTTP/1.0\r\nHost: test\r\nContent-Length: 5\r\n\r\nhello")
    assert(resp, "POST failed: " .. tostring(err))
    log.info("test", "POST resp:", resp)
    assert(resp:find("200"), "expected 200 response, got: " .. resp)
    assert(resp:find("echo:hello"), "expected echoed body, got: " .. resp)
    assert(last_req.method == "POST", "expected method POST, got " .. tostring(last_req.method))
    assert(last_req.body == "hello", "expected body hello, got " .. tostring(last_req.body))

    -- 重复启动被拒绝
    ok = httpsrv.start(port, on_request, socket.LWIP_ANY)
    assert(not ok, "duplicate httpsrv.start on same port should fail")

    ok = stop_server(port)
    assert(ok == true, "httpsrv.stop should return true")
    ok = stop_server(port)
    assert(not ok, "second httpsrv.stop should fail")

    -- stop 返回后端口必须已经真正释放, 否则同端口立刻重启会 bind 失败
    ok = start_server(port)
    log.info("test", "restart on same port:", ok)
    assert(ok == true, "httpsrv.start must succeed immediately after stop on the same port")
    ok = stop_server(port)
    assert(ok == true, "httpsrv.stop should return true")

    log.info("test", "=== test_httpsrv_http_roundtrip PASSED ===")
end

-- 用例3: 静态文件
function M.test_httpsrv_static_file()
    log.info("test", "=== test_httpsrv_static_file ===")
    local port = 18082
    local host = start_roundtrip()
    if not host then return end

    local ok = start_server(port)
    assert(ok == true, "httpsrv.start should return true")

    -- 本文件自身就在 /luadb 下, 用它验证静态文件通道
    local resp, err = http_request(host, port, "GET /httpsrv_test.lua HTTP/1.0\r\nHost: test\r\n\r\n", 8000)
    assert(resp, "static request failed: " .. tostring(err))
    log.info("test", "static resp len:", #resp)
    assert(resp:find("200"), "expected 200 response, got: " .. resp:sub(1, 200))
    assert(resp:find(STATIC_MARKER, 1, true), "static file content not served, len=" .. #resp)

    ok = stop_server(port)
    assert(ok == true, "httpsrv.stop should return true")
    log.info("test", "=== test_httpsrv_static_file PASSED ===")
end

-- 用例4: 路径穿越必须被拦掉, 落到 Lua 回调而不是返回文件
function M.test_httpsrv_path_traversal()
    log.info("test", "=== test_httpsrv_path_traversal ===")
    local port = 18083
    local host = start_roundtrip()
    if not host then return end

    local ok = start_server(port)
    assert(ok == true, "httpsrv.start should return true")

    local resp, err = http_request(host, port, "GET /../luat_conf_bsp.h HTTP/1.0\r\nHost: test\r\n\r\n")
    assert(resp, "traversal request failed: " .. tostring(err))
    log.info("test", "traversal resp:", resp:sub(1, 120))
    -- 未命中静态文件 -> 走 Lua 回调 -> 404, 不应泄露文件内容
    assert(resp:find("404"), "path traversal should not serve a file, got: " .. resp:sub(1, 200))
    assert(not resp:find("LUAT_USE_LWIP", 1, true), "path traversal leaked file content")

    ok = stop_server(port)
    assert(ok == true, "httpsrv.stop should return true")
    log.info("test", "=== test_httpsrv_path_traversal PASSED ===")
end

-- 用例5: socket.LWIP_ANY 写法在 PC 上原样可用
-- Air8300/Air8301 factory 固件用的是 httpsrv.start(port, cb, socket.LWIP_ANY),
-- PC 上必须能原样跑通, 否则开发时得改代码才能验证
function M.test_httpsrv_lwip_any_bind()
    log.info("test", "=== test_httpsrv_lwip_any_bind ===")
    local port = 18084
    local host = start_roundtrip()
    if not host then return end

    local ok = httpsrv.start(port, on_request, socket.LWIP_ANY)
    log.info("test", "start with LWIP_ANY:", ok)
    assert(ok == true, "httpsrv.start with socket.LWIP_ANY should return true")

    local resp, err = http_request(host, port, "GET /api/ok HTTP/1.0\r\nHost: test\r\n\r\n")
    assert(resp, "LWIP_ANY roundtrip failed: " .. tostring(err))
    log.info("test", "resp:", resp:sub(1, 60))
    assert(resp:find("200"), "expected 200 response, got: " .. resp:sub(1, 120))
    assert(resp:find('{"ok":true}'), "expected json body, got: " .. resp:sub(1, 120))

    ok = httpsrv.stop(port, nil, socket.LWIP_ANY)
    assert(ok == true, "httpsrv.stop should return true")
    log.info("test", "=== test_httpsrv_lwip_any_bind PASSED ===")
end

return M
