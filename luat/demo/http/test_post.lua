
function demo_http_post_json()
    -- POST request 演示
    local req_headers = {}
    req_headers["Content-Type"] = "application/json"
    local body = json.encode({name="LuatOS"})
    local code, headers, body = http.request("POST","http://site0.cn/api/httptest/simple/date", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
    ).wait()
    log.info("http.post", code, headers, body)
end

function demo_http_post_form()
    -- POST request 演示
    local req_headers = {}
    req_headers["Content-Type"] = "application/x-www-form-urlencoded"
    local params = {
        ABC = "123",
        DEF = 345
    }
    local body = ""
    for k, v in pairs(params) do
        body = body .. tostring(k) .. "=" .. tostring(v):urlEncode() .. "&"
    end
    local code, headers, body = http.request("POST","http://echohttp.wendal.cn/post", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
    ).wait()
    log.info("http.post.form", code, headers, body)
end
