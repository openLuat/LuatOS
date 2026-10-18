-- httpsrv 修复回归测试
--
-- 背景: 2026-10 审查修复 httpsrv 五项问题, 本用例做回归:
--   #3 stop 后 ctx 过早释放/端口无法重绑 -> test_stop_start_rebind
--   #4 静态文件带 query 404               -> test_static_with_query / test_query_passthrough
--   #5 svg MIME 错误                      -> test_svg_mime
--   #1 请求体跨分段只留最后一段            -> test_post_large_body
--      (lwIP 跨 pbuf 路径已在 Air1601 真机验证, 这里覆盖公共 http.c 解析)
--   #2 响应派发与连接关闭竞争(UAF 隐患)    -> test_rst_storm / test_concurrent
--   附带: Content-Length 的 %zu 输出       -> test_static_with_query 的 content-length 断言
--
-- 注意: testsuite 用 pairs() 遍历, 执行顺序无序, 各用例必须相互独立;
-- 服务器当前回调的 marker 记录在 M.marker 中, 任何时刻只有一个活跃服务器。
--
-- 不依赖 httpplus(PC luadb 未打包该库): 内置最小 HTTP/1.1 客户端(raw socket)。
local M = {}
local TAG = "httpsrv_basic"
local PORT = 8321
local HOST = "127.0.0.1"

local STATIC_HTML = "<!DOCTYPE html><html><body>httpsrv-static-ok</body></html>\n"
local STATIC_SVG  = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"></svg>\n"

-- 当前活跃服务器回调的 marker (setup/rebind 时更新, 用例从这里取)
M.marker = "from_A"

local function make_cb(marker)
    return function(client, method, uri, headers, body)
        return 200, {}, marker .. ":" .. method .. ":" .. uri .. "#" .. tostring(body and #body or -1)
    end
end

-- 解析 HTTP 响应, 返回 code, headers(table), body
local function parse_response(resp)
    local h_end = resp:find("\r\n\r\n", 1, true)
    assert(h_end, "响应缺少头结束符: " .. resp:sub(1, 64))
    local head = resp:sub(1, h_end - 1)
    local body = resp:sub(h_end + 4)
    local code = tonumber(head:match("^HTTP/%d%.%d (%d%d%d)"))
    assert(code, "无法解析状态行: " .. head:match("^[^\r\n]*"))
    local headers = {}
    for line in head:gmatch("[^\r\n]+") do
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k then
            headers[k] = v
        end
    end
    return code, headers, body
end

-- 最小 HTTP/1.1 客户端(短连接), 返回 code, headers, body
local function req(method, path, req_body, req_headers)
    local chunks = {}
    local total = 0
    local online = false
    local netc
    -- connect 偶发 WSAEADDRINUSE(前序连接 TIME_WAIT 与本端口号冲突), 重试几次
    for attempt = 1, 5 do
        netc = socket.create(nil, function(sc, event)
            if event == socket.ON_LINE then
                online = true
            elseif event == socket.EVENT then
                local buff = zbuff.create(8192)
                while true do
                    buff:seek(0)
                    local succ, data_len = socket.rx(sc, buff)
                    if succ and data_len and data_len > 0 then
                        chunks[#chunks + 1] = buff:query(0, data_len)
                        total = total + data_len
                    else
                        break
                    end
                end
            end
        end)
        assert(netc, "socket.create 失败")
        socket.config(netc, nil, false)   -- 必须显式指定 TCP, 默认是 UDP
        if socket.connect(netc, HOST, PORT) then
            break
        end
        socket.close(netc)
        socket.release(netc)
        netc = nil
        sys.wait(500)
    end
    assert(netc, "socket.connect 重试 5 次仍失败 " .. method .. " " .. path)
    -- 必须等 ON_LINE 再发送, 否则非阻塞 connect 未完成时 tx 会丢
    local conn_deadline = mcu.ticks() + 10000
    while not online and mcu.ticks() < conn_deadline do
        sys.wait(10)
    end
    assert(online, "连接超时 " .. method .. " " .. path)

    local lines = {
        string.format("%s %s HTTP/1.1\r\n", method, path),
        string.format("Host: %s:%d\r\n", HOST, PORT),
        "Connection: close\r\n",
    }
    if req_headers then
        for k, v in pairs(req_headers) do
            lines[#lines + 1] = string.format("%s: %s\r\n", k, v)
        end
    end
    if req_body then
        lines[#lines + 1] = string.format("Content-Length: %d\r\n", #req_body)
    end
    lines[#lines + 1] = "\r\n"
    -- 头与 body 必须合并成一次 socket.tx: 连续两次 tx 时前一次可能还在
    -- 发送队列里, Lua 字符串被 GC 后适配层会拿到失效指针, 请求即截断
    local payload = table.concat(lines)
    if req_body then
        payload = payload .. req_body
    end
    socket.tx(netc, payload)

    -- 等齐 Content-Length 指定的字节 (httpsrv 的静态与 Lua 响应都带该头)
    local deadline = mcu.ticks() + 15000
    while mcu.ticks() < deadline do
        local resp = table.concat(chunks)
        local h_end = resp:find("\r\n\r\n", 1, true)
        if h_end then
            local cl = resp:sub(1, h_end):match("[Cc]ontent%-[Ll]ength:%s*(%d+)")
            if cl and total - (h_end + 3) >= tonumber(cl) then
                break
            end
        end
        sys.wait(20)
    end
    socket.close(netc)
    socket.release(netc)
    assert(total > 0, "无响应数据 " .. method .. " " .. path)
    return parse_response(table.concat(chunks))
end

-- 大小写不敏感的 header 查找
local function hdr(headers, name)
    local lname = name:lower()
    for k, v in pairs(headers) do
        if type(k) == "string" and k:lower() == lname then
            return v
        end
    end
    return nil
end

function M.setup()
    io.writeFile("/httpsrv_t.html", STATIC_HTML)
    io.writeFile("/httpsrv_t.svg", STATIC_SVG)
    M.marker = "from_A"
    local ok = httpsrv.start(PORT, make_cb(M.marker))
    assert(ok, "httpsrv.start 失败 port=" .. PORT)
    log.info(TAG, "httpsrv listen on", PORT)
end

function M.teardown()
    pcall(httpsrv.stop, PORT)
end

-- query string 必须原样传给 Lua 回调 (#4 的另一半)
function M.test_query_passthrough()
    local code, _, body = req("GET", "/echo?x=1&y=2")
    assert(code == 200, "code=" .. tostring(code))
    assert(body:find(M.marker .. ":GET:", 1, true) == 1, "body=" .. body)
    assert(body:find("/echo?x=1&y=2#", 1, true) ~= nil, "query 未原样透传, body=" .. body)
    log.info(TAG, "query 透传 ok", body)
    return true
end

-- 静态文件 + query 必须命中文件而不是 404 (#4)
-- content-length 校验同时覆盖 %zu 修复: 修复前该头输出字面 "zu", tonumber 失败
function M.test_static_with_query()
    local code, headers, body = req("GET", "/httpsrv_t.html?from=qq&v=1")
    assert(code == 200, "静态+query 应 200, 实际 " .. tostring(code))
    assert(body == STATIC_HTML, "静态内容不匹配 len=" .. tostring(#body))
    local cl = tonumber(hdr(headers, "content-length"))
    assert(cl == #STATIC_HTML, "Content-Length 错: " .. tostring(hdr(headers, "content-length")))
    return true
end

-- svg 扩展名必须返回 image/svg+xml (#5)
function M.test_svg_mime()
    local code, headers, body = req("GET", "/httpsrv_t.svg")
    assert(code == 200, "code=" .. tostring(code))
    assert(body == STATIC_SVG, "svg 内容不匹配")
    local ct = hdr(headers, "content-type") or ""
    assert(ct:find("image/svg+xml", 1, true) ~= nil, "svg MIME 错: " .. ct)
    log.info(TAG, "svg mime ok", ct)
    return true
end

-- 5KB POST 连续三次, 内容必须完整 (http.c 累积解析; lwIP 跨 pbuf 同路径真机已验)
function M.test_post_large_body()
    local big = string.rep("Ab", 2500)   -- 5000 字节
    for i = 1, 3 do
        local code, _, body = req("POST", "/post", big, { ["Content-Type"] = "text/plain" })
        assert(code == 200, "第 " .. i .. " 次 code=" .. tostring(code))
        assert(body:find(M.marker .. ":POST:/post#", 1, true) == 1, "body=" .. body)
        assert(body:match("#5000$") ~= nil, "body 长度错(应为 #5000), body 尾部=" .. body:sub(-16))
    end
    log.info(TAG, "POST 5KB x3 ok")
    return true
end

-- stop 后同端口立即重绑且新回调生效 (#3)
function M.test_stop_start_rebind()
    local new_marker = "rebound_" .. tostring(mcu.ticks() % 100000)
    assert(httpsrv.stop(PORT), "httpsrv.stop 失败")
    local ok = httpsrv.start(PORT, make_cb(new_marker))
    assert(ok, "同端口重启失败")
    M.marker = new_marker
    local code, _, body = req("GET", "/echo?after=restart")
    assert(code == 200, "code=" .. tostring(code))
    assert(body:find(new_marker .. ":GET:", 1, true) == 1,
        "重启后仍是旧回调或未生效, body=" .. body)
    assert(body:find("/echo?after=restart#", 1, true) ~= nil, "body=" .. body)
    log.info(TAG, "stop/start 重绑 ok", body)
    return true
end

-- 8 路并发连接全部成功
function M.test_concurrent()
    local total, failed = 0, nil
    for i = 1, 8 do
        sys.taskInit(function()
            local ok, err = pcall(function()
                local code, _, body = req("GET", "/echo?c=" .. i)
                assert(code == 200, "c" .. i .. " code=" .. tostring(code))
                assert(body:find("/echo?c=" .. i .. "#", 1, true) ~= nil, "c" .. i .. " body=" .. body)
            end)
            if not ok then
                failed = tostring(err)
            end
            total = total + 1
        end)
    end
    local deadline = mcu.ticks() + 30000
    while total < 8 and mcu.ticks() < deadline do
        sys.wait(50)
    end
    assert(total == 8, "并发请求未完成: " .. total .. "/8")
    assert(failed == nil, failed)
    log.info(TAG, "8 路并发 ok")
    return true
end

-- 连接中途断开(半个请求就 close) x10 之后, 服务必须照常 (#2)
function M.test_rst_storm()
    for i = 1, 10 do
        local netc = socket.create(nil, function() end)
        assert(netc, "socket.create 失败")
        socket.config(netc, nil, false)   -- TCP
        assert(socket.connect(netc, HOST, PORT), "socket.connect 失败")
        sys.wait(100)   -- 等连接建立
        socket.tx(netc, "GET /echo?rst=" .. i .. " HTTP/1.1\r\nHost: x\r\n")
        socket.close(netc)    -- 请求不完整就断开
        socket.release(netc)
        sys.wait(30)
    end
    sys.wait(500)   -- 让服务端收尾
    local code, _, body = req("GET", "/echo?final=ok")
    assert(code == 200, "风暴后服务不可用, code=" .. tostring(code))
    assert(body:find("/echo?final=ok#", 1, true) ~= nil, "body=" .. body)
    log.info(TAG, "RST 风暴后服务正常")
    return true
end

return M
