_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000)
    log.info("http_timeout", "start", "5s timeout test")
    local code, headers, body = http.request("GET", "http://httpbin.air32.cn/delay/10", {timeout=5000}).wait()
    log.info("http_timeout", code, body)
end)

sys.run()
