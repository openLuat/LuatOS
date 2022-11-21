local libnet = require "libnet"


-- local function downloadFile(code, headers, body)
--     log.info("http2.get", code, json.encode(headers), body)
--     local r = io.writeFile("/data.txt", body)
--     if r then
--         log.info("文件写入成功")
--         sys.publish("WRITE_FILE_SUCCESS")
--     else
--         log.info("文件写入失败")
--     end
-- end

-- Download File task
sys.taskInit(function ()
    sys.wait(5000)  
    log.info("------下载文件------")
    local path = "/data.txt"
    -- GET请求,但下载到文件
    http2.request(
        "GET",
        "http://cdn.openluat-luatcommunity.openluat.com/attachment/20220825134126812_text.txt").cb
        (
            function (code, headers, body)
                log.info("http2.get", code, json.encode(headers), body)
                local r = io.writeFile("/data.txt", body)
                if r then
                    log.info("文件写入成功")
                    sys.publish("WRITE_FILE_SUCCESS")
                else
                    log.info("文件写入失败")
                end
            end
        )

    sys.waitUntil("WRITE_FILE_SUCCESS")
    local data = io.readFile(path)
    if data then
        log.info("fs", "data", data, data:toHex())
    else
        log.info("打开文件失败")
    end

    -- POST and download, task内的同步操作
    -- local opts = {}                 -- 额外的配置项
    -- opts["dst"] = "/data.bin"       -- 下载路径,可选
    -- opts["adapter"] = ""  -- 使用哪个网卡,可选
    -- local req_headers = {}
    -- req_headers["Content-Type"] = "application/json"
    -- local code, headers, body = http2.request("POST","http://site0.cn/api/httptest/simple/date", 
    --         json.encode(req_headers), -- 请求所添加的 headers, 可以是nil
    --         "",
    --         opts
    -- ).wait()
    -- log.info("http2.post", code, headers, body) -- 只返回code和headers
end)

-- [[
sys.taskInit(
    function()
        sys.wait(3000)
        
        log.info("mem.lua", rtos.meminfo())
        log.info("mem.sys", rtos.meminfo("sys"))

        -- GET请求
        log.info("------GET请求------")
        local code, headers, body = http2.request("GET","https://www.baidu.com/").wait()
        log.info("http.get", code, json.encode(headers), body)
        sys.wait(2000)

        -- POST请求后以回调函数方式处理的例子。
        log.info("------POST请求------")
        local req_headers = {}
        req_headers["Content-Type"] = "application/json"
        local body = json.encode({name="LuatOS"})
        http2.request("POST","http://site0.cn/api/httptest/simple/date", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
        ).cb(function(code, headers, body)
            log.info("http.post", code, json.encode(headers), body)
        end)

    end
)
-- ]]


-- sys.taskInit(
--     function()
--         sys.wait(3000)
        
--         -- while 1 do
--             log.info("mem.lua", rtos.meminfo())
--             log.info("mem.sys", rtos.meminfo("sys"))
--             local code, headers, body = http2.request("GET","https://www.baidu.com/").wait()
--             log.info("http2.get", code, json.encode(headers), body)

--             -- -- local code, headers, body = http2.request("GET","http://site0.cn/api/httptest/simple/time").wait()
--             -- -- log.info("http2.get", code, json.encode(headers), body)
--             -- sys.wait(2000)

--             -- -- POST request
--             -- local req_headers = {}
--             -- req_headers["Content-Type"] = "application/json"
--             -- local body = json.encode({name="LuatOS"})
--             -- local code, headers, body = http2.request("POST","http://site0.cn/api/httptest/simple/date", 
--             --         req_headers,
--             --         body -- POST请求所需要的body, string, zbuff, file均可
--             -- ).cb(function (code, headers, body)
--             --     log.info("http2.post", code, headers, body)
--             -- end)
--             -- log.info("http2.post1", code, headers, body)
--         -- end
--     end
-- )

