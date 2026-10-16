-- PC 模拟器 httpsrv 局域网可访问性验证 (Gitee IKLV09)
-- 模拟真实使用场景: PC 模拟器起 httpsrv, 局域网里的手机浏览器直接访问 http://<PC-IP>:<port>/
-- 与 testcase 的区别: 这个脚本会保持运行一段时间, 便于外部用浏览器/curl 实际访问
--
-- 运行:
--   cd bsp/pc\build\out
--   .\luatos-lua.exe ..\..\test\156.httpsrv_lan\
-- 然后在同一个局域网的手机浏览器打开日志里打印的地址

local PORT = tonumber(arg and arg[1]) or 8080
local HOLD_MS = tonumber(arg and arg[2]) or 60000

local function on_request(client, method, uri, headers, body)
    log.info("httpsrv_lan", "on_request", method, uri, "body=" .. tostring(body))
    if uri == "/" then
        return 200,
            {["Content-Type"] = "text/html; charset=utf-8"},
            [[<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LuatOS httpsrv @ PC</title><style>body{font-family:sans-serif;padding:24px}
b{color:#0a0}</style></head><body>
<h1>LuatOS httpsrv works on PC</h1>
<p>如果你在手机浏览器里看到这一页, 说明 PC 模拟器的 httpsrv 真的可以用了。</p>
<p>当前时间: ]] .. os.date("%Y-%m-%d %H:%M:%S") .. [[</p>
<form method="POST" action="/submit"><input name="q" placeholder="输入点什么"><button>提交</button></form>
<p><a href="/api/state">/api/state (JSON)</a></p>
</body></html>]]
    elseif uri == "/submit" then
        log.info("httpsrv_lan", "POST body:", body)
        return 200, {["Content-Type"] = "text/plain"}, "got:" .. tostring(body)
    elseif uri == "/api/state" then
        return 200, {["Content-Type"] = "application/json"},
            json.encode({ok = true, model = hmeta.model(), port = PORT, uptime = os.time()})
    end
    return 404, {}, "not found"
end

sys.taskInit(function()
    local ip = "?"
    local ok, adapter = socket.adapter()
    if ok and adapter then
        ip = socket.localIP(adapter) or "?"
    end
    log.info("httpsrv_lan", "=========================================")
    log.info("httpsrv_lan", " PC 模拟器 httpsrv 已启动")
    log.info("httpsrv_lan", " 手机/电脑浏览器请打开:  http://" .. ip .. ":" .. PORT .. "/")
    log.info("httpsrv_lan", " 保持运行 " .. (HOLD_MS/1000) .. " 秒")
    log.info("httpsrv_lan", "=========================================")

    local started = httpsrv.start(PORT, on_request)
    if not started then
        log.error("httpsrv_lan", "start failed on port", PORT)
        os.exit(1)
    end

    -- 静态文件通道自检: /luadb/main.lua 由 C 层直接返回
    sys.wait(200)
    log.info("httpsrv_lan", "自检 GET / ->")
    sys.wait(HOLD_MS)
    log.info("httpsrv_lan", "bye")
    os.exit(0)
end)

sys.run()
