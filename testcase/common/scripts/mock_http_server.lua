-- 简易 HTTP mock server，用于 CI 中替代外部网络依赖
-- 在 PC 模拟器上通过 socket 监听 localhost 端口提供固定响应
local mock = {}

local PORT = 18080
local server_socket = nil
local running = false

-- 预设路由表: path -> {status, body, content_type}
local routes = {
    ["/"] = { status = 200, body = "OK", content_type = "text/plain" },
    ["/get"] = { status = 200, body = '{"method":"GET","ok":true}', content_type = "application/json" },
    ["/post"] = { status = 200, body = '{"method":"POST","ok":true}', content_type = "application/json" },
    ["/status/404"] = { status = 404, body = "Not Found", content_type = "text/plain" },
    ["/status/500"] = { status = 500, body = "Internal Server Error", content_type = "text/plain" },
    ["/delay/100"] = { status = 200, body = "delayed", content_type = "text/plain" },
    ["/bytes/64"] = { status = 200, body = string.rep("A", 64), content_type = "application/octet-stream" },
}

local STATUS_TEXT = {
    [200] = "OK",
    [404] = "Not Found",
    [500] = "Internal Server Error",
}

local function build_response(route)
    local status = route.status or 200
    local status_text = STATUS_TEXT[status] or "OK"
    local body = route.body or ""
    local ct = route.content_type or "text/plain"
    return string.format(
        "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
        status, status_text, ct, #body, body
    )
end

local function parse_request(data)
    -- 解析第一行: METHOD PATH HTTP/x.x
    local method, path = data:match("^(%u+)%s+(%S+)%s+HTTP")
    return method, path
end

local function handle_client(client)
    local data = client:recv(4096)
    if data and #data > 0 then
        local method, path = parse_request(data)
        if path then
            -- 去掉 query string
            path = path:match("^([^?]+)") or path
            local route = routes[path]
            if route then
                client:send(build_response(route))
            else
                client:send(build_response({ status = 404, body = "Not Found: " .. path }))
            end
        end
    end
    client:close()
end

--- 启动 mock server (非阻塞，在协程中运行)
function mock.start(port)
    PORT = port or PORT
    local socket = require("socket")

    sys.taskInit(function()
        server_socket = socket.create("0.0.0.0", PORT, {
            is_udp = false,
        })
        if not server_socket then
            log.error("mock_http", "failed to create server socket on port " .. PORT)
            return
        end
        running = true
        log.info("mock_http", "listening on 127.0.0.1:" .. PORT)

        while running do
            local client = server_socket:accept()
            if client then
                -- 每个连接在独立协程处理
                sys.taskInit(function()
                    pcall(handle_client, client)
                end)
            else
                sys.wait(10)
            end
        end
    end)

    -- 等待 server 就绪
    sys.wait(100)
    return true
end

--- 停止 mock server
function mock.stop()
    running = false
    if server_socket then
        server_socket:close()
        server_socket = nil
    end
end

--- 获取 base URL
function mock.base_url()
    return "http://127.0.0.1:" .. PORT
end

--- 添加自定义路由
function mock.add_route(path, status, body, content_type)
    routes[path] = {
        status = status or 200,
        body = body or "",
        content_type = content_type or "text/plain",
    }
end

return mock
