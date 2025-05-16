function demo_http_get()
    -- 最普通的Http GET请求
    local code, headers, body = http.request("GET", "https://www.air32.cn/").wait()
    log.info("http.get", code, headers, body)
    local code, headers, body = http.request("GET", "https://mirrors6.tuna.tsinghua.edu.cn/", nil, nil, {ipv6=true}).wait()
    log.info("http.get", code, headers, body)
    sys.wait(100)
    local code, headers, body = http.request("GET", "https://www.luatos.com/").wait()
    log.info("http.get", code, headers, body)

    -- 按需打印
    -- code 响应值, 若大于等于 100 为服务器响应, 小于的均为错误代码
    -- headers是个table, 一般作为调试数据存在
    -- body是字符串. 注意lua的字符串是带长度的byte[]/char*, 是可以包含不可见字符的
    -- log.info("http", code, json.encode(headers or {}), #body > 512 and #body or body)
end
