http_response = {}

local urlbase = "http://httpbin.air32.cn"

-- 读取证书和私钥的函数
local function read_file(file_path)
    local file, err = io.open(file_path, "r")
    if not file then
        error("Failed to open file: " .. err)
    end
    local data = file:read("*a")
    file:close()
    return data
end

-- 读取证书和私钥
local ca_server = read_file("/luadb/http_ca.crt") -- 服务器 CA 证书数据
local ca_client = read_file("/luadb/http_client.crt") -- 客户端 CA 证书数据
local client_private_key_encrypts_data = read_file("/luadb/http_client.key") -- 客户端私钥
local client_private_key_password = "123456789" -- 客户端私钥口令

local http_debug = false

-- GET：无请求头、无body、无附加数据
function http_response.test_http_get_basic()
    log.info("http_response", "开始【GET方法,无请求头、body以及额外的附加数据】测试")
    local code = http.request("GET", urlbase .. "/get", nil, nil, {}).wait()
    assert(code == 200, "GET方法,无请求头、body以及额外的附加数据测试失败: 预期 200, 实际 " ..
        tostring(code))
    log.info("http_response", "GET方法,无请求头、body以及额外的附加数据 测试通过 ")
end

-- GET：有请求头、无body、无附加数据
function http_response.test_http_get_with_headers()
    log.info("http_response", "开始【GET方法,有请求头,无body和额外的附加数据】测试")
    local code = http.request("GET", urlbase .. "/get", {
        ["Content-Type"] = "application/json"
    }, nil, {}).wait()
    assert(code == 200,
        "GET方法,有请求头,无body和额外的附加数据测试失败: 预期 200, 实际 " .. tostring(code))
    log.info("http_response", "GET方法,有请求头,无body和额外的附加数据 测试通过 ")
end

-- GET：无请求头、无body、超时5S、debug打开
function http_response.test_http_get_timeout_debug()
    log.info("http_response", "开始【GET方法,无请求头,无body,超时时间5S,debug日志打开】测试")
    local code = http.request("GET", urlbase .. "/get", nil, nil, {
        timeout = 5000,
        debug = http_debug
    }).wait()
    assert(code == 200,
        "GET方法,无请求头,无body,超时时间5S,debug日志打开测试失败: 预期 200, 实际 " ..
            tostring(code))
    log.info("http_response", "GET方法,无请求头,无body,超时时间5S,debug日志打开 测试通过 ")
end

-- GET：下载2K小文件
function http_response.test_http_get_download_2k()
    -- 实际文件大小 1675 字节
    log.info("http_response", "开始【GET 2K小文件下载】测试")
    local expected_content_start = [[我现在有一个用lua写的 http接口，接口描述如下

http客户端
@api http.request(method,url,headers,body,opts,ca_file,client_ca, client_key, client_password)
@string 请求方法, 支持 GET/POST 等合法的HTTP方法
@string url地址, 支持 http和https, 支持域名, 支持自定义端口
@tabal  请求头 可选 例如 {["Content-Type"] = "application/x-www-form-urlencoded"}
@string/zbuff body 可选
@table  额外配置 可选 包含 timeout:超时时间单位ms 可选,默认10分钟,写0即永久等待 dst:下载路径,可选 adapter:选择使用网卡,可选 debug:是否打开debug信息,可选,ipv6:是否为ipv6 默认不是,可选 callback:下载回调函数,参数 content_len:总长度 body_len:以下载长度 userdata 用户传参,可选 userdata:回调自定义传参  
@string 服务器ca证书数据, 可选, 一般不需要
@string 客户端ca证书数据, 可选, 一般不需要, 双向https认证才需要
@string 客户端私钥加密数据, 可选, 一般不需要, 双向https认证才需要
@string 客户端私钥口令数据, 可选, 一般不需要, 双向https认证才需要
@return int code , 服务器反馈的值>=100, 最常见的是200.如果是底层错误,例如连接失败, 返回值小于0
@return tabal headers 当code>100时, 代表服务器返回的头部数据 
@return string/int body 服务器响应的内容字符串,如果是下载模式, 则返回文件大小


我需要用lua写一份完整的测试用例，包含了所有可能，如get方法有请求头，没有请求头，有额外配置项无额外配置项，有证书无证书，请帮用lua我写一份完善的测试用例]]
    local code, _, body = http.request("GET", "http://airtest.openluat.com:2900/download/2K", nil, nil, {}).wait()
    log.info("2K文件下载内容长度:", body)
    assert(code == 200, "GET 2K小文件下载测试失败: 预期 200, 实际 " .. tostring(code))
    -- 可选: 校验长度为2048字节（2K）
    if body then
        assert(#body == 1675, "GET 2K小文件下载测试失败: 预期长度 1675, 实际长度 " .. tostring(#body))
    end

    local function normalize_string(str)
        -- 移除尾部空格
        str = str:gsub("%s+$", "")
        -- 将多个连续空格替换为单个空格
        str = str:gsub("%s+", " ")
        -- 标准化换行符（如果需要）
        str = str:gsub("\r\n", "\n")
        return str
    end

    local expected_normalized = normalize_string(expected_content_start)
    local actual_normalized = normalize_string(body)

    if body and #body > 0 then
        assert(expected_normalized == actual_normalized, string.format(
            "文件起始内容不匹配!\n预期: '%s'\n实际: '%s'", expected_normalized, actual_normalized))
    end

    log.info("http_response", "GET 2K小文件下载 测试通过 ")
end

-- GET：无效域名
function http_response.test_http_get_invalid_url_domain()
    log.info("http_response", "开始【GET方法,无效的url,域名】测试")
    local code = http.request("GET", "http://invalid-url", nil, nil, {}).wait()
    assert(code == -4, "GET方法,无效的url,域名测试失败: 预期 -4, 实际 " .. tostring(code))
    log.info("http_response", "GET方法,无效的url,域名 测试通过 ")
end

-- GET：无效IP
function http_response.test_http_get_invalid_ip()
    log.info("http_response", "开始【GET方法,无效的url,IP地址】测试")
    local code = http.request("GET", "192.168.1", nil, nil, {}).wait()
    assert(code == -4, "GET方法,无效的url,IP地址测试失败: 预期 -4, 实际 " .. tostring(code))
    log.info("http_response", "GET方法,无效的url,IP地址 测试通过 ")
end

-- POST：有请求头、JSON body
function http_response.test_http_post_json()
    log.info("http_response", "开始【POST方法,有请求头,body为json】测试")
    local code = http.request("POST", urlbase .. "/post", {
        ["Content-Type"] = "application/json"
    }, '{"key": "value"}', {}).wait()
    assert(code == 200, "POST方法,有请求头,body为json测试失败: 预期 200, 实际 " .. tostring(code))
    log.info("http_response", "POST方法,有请求头,body为json 测试通过 ")
end

-- POST：无请求头、无body、无额外数据
function http_response.test_http_post_no_headers_no_body()
    log.info("http_response", "开始【POST方法,无请求头,无body,无额外的数据】测试")
    local code = http.request("POST", urlbase .. "/post", nil, nil, {}).wait()
    assert(code == 200,
        "POST方法,无请求头,无body,无额外的数据测试失败: 预期 200, 实际 " .. tostring(code))
    log.info("http_response", "POST方法,无请求头,无body,无额外的数据 测试通过 ")
end

-- POST：无效域名
function http_response.test_http_post_invalid_url_domain()
    log.info("http_response", "开始【POST方法,无效的url,域名】测试")
    local code = http.request("POST", "clahflkjfpsjvlsvnlohvioehoi", nil, nil, {}).wait()
    assert(code == -4, "POST方法,无效的url,域名测试失败: 预期 -4, 实际 " .. tostring(code))
    log.info("http_response", "POST方法,无效的url,域名 测试通过 ")
end

-- POST：无效IP
function http_response.test_http_post_invalid_ip()
    log.info("http_response", "开始【POST方法,无效的url,IP地址】测试")
    local code = http.request("POST", "192.168.1", nil, nil, {}).wait()
    assert(code == -4, "POST方法,无效的url,IP地址测试失败: 预期 -4, 实际 " .. tostring(code))
    log.info("http_response", "POST方法,无效的url,IP地址 测试通过 ")
end

-- POST：上传30K大数据
function http_response.test_http_post_large_30k_octet_stream()
    log.info("http_response", "开始【POST 30K大数据上传】测试")
    local payload = string.rep("A", 30 * 1024)
    local code = http.request("POST", urlbase .. "/post", {
        ["Content-Type"] = "application/octet-stream"
    }, payload, {}).wait()
    assert(code == 200, "POST 30K大数据上传测试失败: 预期 200, 实际 " .. tostring(code))
    log.info("http_response", "POST 30K大数据上传 测试通过 ")
end

-- POST：x-www-form-urlencoded，超时5S
function http_response.test_http_post_form_urlencoded_timeout()
    log.info("http_response", "开始【POST方法,有请求头,body为json,超时时间5S】测试")
    local code = http.request("POST", urlbase .. "/post", {
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }, "key=value", {
        timeout = 5000
    }).wait()
    assert(code == 200,
        "POST方法,有请求头,body为json,超时时间5S测试失败: 预期 200, 实际 " .. tostring(code))
    log.info("http_response", "POST方法,有请求头,body为json,超时时间5S 测试通过 ")
end

-- HTTPS GET：双向认证
function http_response.test_https_get_mutual_auth()
    log.info("http_response", "开始【HTTPS GET方法,双向认证】测试")
    local code = http.request("GET", urlbase .. "/get", nil, nil, {
        ca = ca_server,
        client_cert = ca_client,
        client_key = client_private_key_encrypts_data,
        client_key_password = client_private_key_password
    }).wait()
    assert(code == 200, "HTTPS GET方法,双向认证测试失败: 预期 200, 实际 " .. tostring(code))
    log.info("http_response", "HTTPS GET方法,双向认证 测试通过 ")
end

-- HTTPS POST：双向认证
function http_response.test_https_post_mutual_auth()
    log.info("http_response", "开始【HTTPS POST方法,双向认证】测试")
    local code = http.request("POST", urlbase .. "/post", {
        ["Content-Type"] = "application/json"
    }, '{"key": "value"}', {
        ca = ca_server,
        client_cert = ca_client,
        client_key = client_private_key_encrypts_data,
        client_key_password = client_private_key_password
    }).wait()
    assert(code == 200, "HTTPS POST方法,双向认证测试失败: 预期 200, 实际 " .. tostring(code))
    log.info("http_response", "HTTPS POST方法,双向认证 测试通过 ")
end

-- 测试延时, 包括http和https
function http_response.test_delay()
    local code = http.request("GET", "http://httpbin.air32.cn/delay/3", nil, nil, {
        timeout = 5000
    }).wait()
    assert(code == 200, "延时3秒测试失败: 预期 200, 实际 " .. tostring(code))
    local code = http.request("GET", "https://httpbin.air32.cn/delay/3", nil, nil, {
        timeout = 10000
    }).wait()
    assert(code == 200, "延时3秒测试失败: 预期 200, 实际 " .. tostring(code))
end

-- 读取指定字节数测试
function http_response.test_bytes()
    local code, headers, body = http.request("GET", "http://httpbin.air32.cn/bytes/1024", nil, nil, {
        timeout = 5000
    }).wait()
    assert(code == 200, "预期status 200, 实际 " .. tostring(code))
    assert(body and #body == 1024, "预期长度 1024, 实际长度" .. tostring(body and #body == 1024 or 0))

    local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/1024", nil, nil, {
        timeout = 5000
    }).wait()
    assert(code == 200, "预期status 200, 实际 " .. tostring(code))
    assert(body and #body == 1024, "预期长度 1024, 实际长度" .. tostring(body and #body == 1024 or 0))
end

-- 各种指定返回码的测试
-- 这里隐含一个对Content-Length的测试, 因为httpbin会返回一个带Content-Length: 0的响应
function http_response.test_status_codes()
    local status_codes = {200, 201, 202, 203, 301, 302, 400, 401, 403, 404, 500, 502, 503}
    local method = {"GET", "POST", "PUT", "DELETE", "PATCH"}
    for _, code in ipairs(status_codes) do
        for _, m in ipairs(method) do
            -- 测试http的情况
            local url = string.format("http://httpbin.air32.cn/status/%d", code)
            local resp_code, headers, body = http.request(m, url, nil, nil, {
                timeout = 5000,
                debug = http_debug
            }).wait()
            assert(resp_code == code, string.format("预期 status %d, 实际 %d", code, resp_code))
            -- 测试https的情况
            local url = string.format("https://httpbin.air32.cn/status/%d", code)
            local resp_code, headers, body = http.request(m, url, nil, nil, {
                timeout = 5000,
                debug = http_debug
            }).wait()
            assert(resp_code == code, string.format("预期 status %d, 实际 %d", code, resp_code))
            sys.wait(10) -- 测试间隔
        end
    end
end

-- 延迟输出测试, 包括http和https, httpbin的/drip接口用于测试延迟输出
function http_response.test_drip()
    local code, headers, body = http.request("GET", "http://httpbin.air32.cn/drip", nil, nil, {
        timeout = 15000
    }).wait()
    assert(code == 200, "drip测试失败: 预期 200, 实际 " .. tostring(code))
    assert(body and #body == 10, "drip测试失败: 预期长度 10, 实际长度 " .. tostring(body and #body or 0))

    local code, headers, body = http.request("GET", "https://httpbin.air32.cn/drip", nil, nil, {
        timeout = 15000
    }).wait()
    assert(code == 200, "drip测试失败: 预期 200, 实际 " .. tostring(code))
    assert(body and #body == 10, "drip测试失败: 预期长度 10, 实际长度 " .. tostring(body and #body or 0))
end

-- 多个请求同时进行
function http_response.test_concurrent_requests()
    log.info("http_response", "开始【多个请求同时进行】测试")
    local tasks = {}
    local count = 3
    -- 先测试http
    log.info("http_response", "开始【多个HTTP请求同时进行】测试")
    for i = 1, count do
        sys.taskInit(function()
            local code = http.request("GET", "http://httpbin.air32.cn/delay/1", nil, nil, {
                timeout = 3000
            }).wait()
            tasks[i] = code
            sys.publish("task_done")
        end)
    end
    -- 等待所有任务完成
    log.info("http_response", "等待所有HTTP请求完成")
    for i = 1, count do
        sys.waitUntil("task_done", 5000)
    end
    for i = 1, count do
        local code = tasks[i]
        assert(code == 200, string.format("并发请求 %d 失败: 预期 200, 实际 %d", i, code))
    end
    log.info("http_response", "多个HTTP请求同时进行 测试通过 ")

    collectgarbage("collect")
    collectgarbage("collect")
    sys.wait(10)

    log.info("http_response", "开始【多个HTTPS请求同时进行】测试")
    tasks = {}
    -- 再测试https
    for i = 1, count do
        sys.taskInit(function()
            local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/10240", nil, nil, {
                timeout = 10000,
                debug = true
            }).wait()
            log.info("http_response", "并发请求 ", i, code, " 返回 body 长度: ", body and #body or 0)
            tasks[i] = {code, headers, body}
            sys.publish("task_done")
        end)
    end
    -- 等待所有任务完成
    for i = 1, count do
        sys.waitUntil("task_done", 5000)
    end
    for i = 1, count do
        local code = tasks[i][1]
        local body = tasks[i][3]
        assert(body and #body == 10240,
            string.format("并发请求 %d 失败: 预期长度 10240, 实际长度 %d", i, body and #body or 0))
        assert(code == 200, string.format("并发请求 %d 失败: 预期 200, 实际 %d", i, code))
    end

    log.info("http_response", "多个请求同时进行 测试通过 ")
end

-- 测试cheunked编码响应body完整性
function http_response.test_chunked()
    log.info("http_response", "开始【chunked编码响应body完整性】测试")
    local count = 30
    local PostBody = {
        deviceAccess = "8",
        deviceUser = "admin",
        devicePsd = "Air123456"
    }
    local header = {
        ["Accept-Encoding"] = "identity",
        ["Host"] = "video.luatos.com:10030",
        ["Content-Type"] = "application/json"
    }
    for i = 1, count do
        local code, headers, body = http.request("POST",
                                        "http://video.luatos.com:10030/api-system/deviceVideo/get/C8C2C68C5D7A", header,
                                        json.encode(PostBody), {
                timeout = 5000
            }).wait()
        assert(code == 200, string.format("chunked测试body完整性请求 %d 失败: 预期 200, 实际 %d", i, code))
        assert(body and #body == 204, string.format(
            "chunked测试body完整性请求 %d 失败: 预期长度 204, 实际长度 %d", i, body and #body or 0))
    end
end

-- 测试请求chunked编码流式JSON文件并测试完整性
function http_response.test_chunked_stream_json()
    log.info("http_response", "开始【chunked编码流式JSON完整性】测试")
    local count = 10
    for i = 1, count do
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/stream/1", nil, nil, {
            timeout = 5000,
            debug = http_debug
        }).wait()
        assert(code == 200, string.format("chunked流式JSON测试 %d 失败: status 预期 200, 实际 %d", i, code))
        assert(body and #body > 0, string.format("chunked流式JSON测试 %d 失败: 预期长度 >0, 实际长度 %d",
            i, body and #body or 0))
        local success, result = pcall(json.decode, body)
        assert(success and result, string.format("chunked流式JSON测试 %d 失败: JSON解析失败", i))
    end

    for i = 1, count do
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/stream/100", nil, nil, {
            timeout = 5000,
            debug = http_debug
        }).wait()
        assert(code == 200, string.format("chunked流式JSON测试 %d 失败: 预期 200, 实际 %d", i, code))
        assert(body and #body > 0, string.format("chunked流式JSON测试 %d 失败: 预期长度 >0, 实际长度 %d",
            i, body and #body or 0))
        local jsons = {}
        for json_str in body:gmatch("{.-}\r?\n?") do
            local ok, obj = pcall(json.decode, json_str)
            if ok and obj then
                table.insert(jsons, obj)
            end
        end
        assert(#jsons == 100, string.format("chunked流式JSON测试 %d 失败: JSON解析失败", i))
    end
end

-- 测试下载mp3文件数据完整性以及文件是否正常存在
function http_response.test_download_mp3()
    local url = "http://airtest.openluat.com:2900/download/1.mp3"
    local save_path = "/ram/1.mp3"
    log.info("http_response", "开始【下载mp3文件数据完整性】测试")
    local code, headers, body = http.request("GET", url, nil, nil, {
        dst = save_path,
        timeout = 10000
    }).wait()
    local body_len = type(body) == "string" and #body or (type(body) == "number" and body or 0)
    log.info("http_response", "下载mp3文件结果", code, body_len)
    assert(code == 200, "下载mp3文件测试失败: 预期 200, 实际 " .. tostring(code))
    assert(body_len == 411922, "下载mp3文件测试失败: 预期长度 411922, 实际长度 " .. tostring(body_len))
    assert(io.exists and io.exists(save_path), "下载mp3文件测试失败: 文件不存在")
    -- 删除文件
    os.remove(save_path)
    log.info("http_response", "下载mp3文件数据完整性 测试通过")
end

-- 测试下载星历文件是否正常
function http_response.test_download_agps()
    local url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat"
    local save_path = "/ram/HXXT_GPS_BDS_AGNSS_DATA.dat"
    os.remove(save_path)
    log.info("http_response", "开始【下载星历文件数据完整性】测试")
    local code, headers, body = http.request("GET", url, nil, nil, {
        dst = save_path,
        timeout = 5000,
        debug = http_debug
    }).wait()
    local body_len = type(body) == "string" and #body or (type(body) == "number" and body or 0)
    log.info("http_response", "下载星历文件结果", code, body_len)
    assert(code == 200, "下载星历文件测试失败: 预期 200, 实际 " .. tostring(code))
    assert(io.exists and io.exists(save_path), "下载星历文件测试失败: 文件不存在")
    assert(io.fileSize(save_path) > 4096, "下载星历文件测试失败: 文件大小异常")

    -- 检查headers
    local header_content_length = tonumber(headers["Content-Length"] or headers["content-length"] or "0")
    local file_size = io.fileSize(save_path)
    assert(header_content_length == file_size,
        string.format("下载星历文件测试失败: Content-Length 与实际文件大小不符, Content-Length=%d, 文件大小=%d",
            header_content_length, file_size))

    -- 删除文件
    os.remove(save_path)
    log.info("http_response", "下载星历文件数据完整性 测试通过")
end

-- 测试访问天地图，验证会忽略Connection: close请求头的服务器，是否会一直等到超时
function http_response.test_test()
    local req_headers = {
        ["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
        ["Connection"] = "keep-alive"
    }
    local code
    local headers
    local body
    -- 获取请求之前的时间戳
    local start_time = os.time()
    code, headers, body = http.request("GET","http://api.tianditu.gov.cn/geocoder?postStr={'lon':117.1155846,'lat':36.6828714,'ver':1}}&tk=004150d6645036a89ef32cfc2df46985", req_headers, nil, {
            timeout = 5000,
            debug = http_debug
        }).wait()
    -- 获取请求之后的时间戳
    local end_time = os.time()
    local elapsed_time = end_time - start_time
    log.info("http_response", "test_test", code, headers, body, "耗时", elapsed_time, "秒")
    assert(code == 200, "test_test测试失败: 预期 200, 实际 " .. tostring(code))
    assert(body and body:find("山东省济南市历下区"), "test_test测试失败: 预期响应包含 '山东省济南市历下区', 实际响应 " .. tostring(body))
    assert(elapsed_time < 5, "test_test测试失败: 预期耗时 < 5秒, 实际耗时 " .. tostring(elapsed_time) .. "秒")
end

return http_response
