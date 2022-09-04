
--[[
这个demo未完成, 暂不可用
TODO http2库完成后删除这段注释
]]
local function testTask()

    -- GET request, task内的同步操作
    local code, headers, body = http2.request("GET","http://site0.cn/api/httptest/simple/time").wait()
    log.info("http2.get", code, headers, body)

    -- POST request
    local req_headers = {}
    req_headers["Content-Type"] = "application/json"
    local body = json.encode({name="LuatOS"})
    local code, headers, body = http2.request("POST","http://site0.cn/api/httptest/simple/date", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
    ).wait()
    log.info("http2.post", code, headers, body)

    -- POST and download, task内的同步操作
    local opts = {}           -- 额外的配置项
    opts["dst"] = "/data.bin" -- 下载路径,可选
    opts["timeout"] = 30      -- 超时时长,单位秒,可选
    opts["adapter"] = 0       -- 使用哪个网卡,可选
    local code, headers, body = http2.request("POST","http://site0.cn/api/httptest/simple/date", 
            {}, -- 请求所添加的 headers, 可以是nil
            "", 
            opts
    ).wait()
    log.info("http2.get", code, headers, body) -- 只返回code和headers

    -- GET request, 开个task让它自行执行去吧, 不管执行结果了
    sys.taskInit(http2.request("GET","http://site0.cn/api/httptest/simple/time").wait)
end

function httpDemo()
	sys.taskInit(testTask)
end
