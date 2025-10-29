
function demo_http_download()

    -- POST and download, task内的同步操作
    local opts = {}                 -- 额外的配置项
    opts["dst"] = "/data.bin"       -- 下载路径,可选
    opts["timeout"] = 30000         -- 超时时长,单位ms,可选
    -- opts["adapter"] = socket.ETH0  -- 使用哪个网卡,可选
    -- opts["callback"] = http_download_callback
    -- opts["userdata"] = http_userdata

    for k, v in pairs(opts) do
        print("opts",k,v)
    end
    
    local code, headers, body = http.request("POST","http://site0.cn/api/httptest/simple/date",
            {}, -- 请求所添加的 headers, 可以是nil
            "", 
            opts
    ).wait()
    log.info("http.post", code, headers, body) -- 只返回code和headers

    -- local f = io.open("/data.bin", "rb")
    -- if f then
    --     local data = f:read("*a")
    --     log.info("fs", "data", data, data:toHex())
    -- end
    
    -- GET request, 开个task让它自行执行去吧, 不管执行结果了
    sys.taskInit(http.request("GET","http://site0.cn/api/httptest/simple/time").wait)
end
