-- httpplus 功能回归用例，覆盖长 header、大 body、multipart 和 bodyfile 等能力
local httpplus = require("httpplus")

local httpplus_test = {}

-- 共用的回环地址
local urlbase = "http://httpbin.air32.cn"
-- 上传和 bodyfile 复用的固定文件路径
local upload_fixture_path = "/luadb/httpplus_upload.txt"

-- 读取固定文件，确保上传和回显可校验
local function read_fixture(path)
    local data = io.readFile(path)
    assert(data, "fixture missing: " .. path)
    return data
end

-- 将响应体转成 Lua table，便于校验
local function decode_body(resp)
    assert(resp and resp.body, "响应体缺失")
    local raw = resp.body:query()
    assert(raw and #raw > 0, "body为空")
    local data = json.decode(raw)
    assert(data, "响应体不是有效JSON")
    return data, raw
end

-- GET：基础请求，确认默认超时时间和 zbuff 响应无误
function httpplus_test.test_httpplus_get_basic()
    log.info("httpplus_test", "GET 基础请求")
    local code, resp = httpplus.request({ url = urlbase .. "/get", timeout = 10 })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local _, raw = decode_body(resp)
    assert(raw and #raw > 0, "GET body 为空")
end

-- GET：长 header 回显，验证 httpplus 对大 header 的支持
function httpplus_test.test_httpplus_get_long_header()
    local long_value = string.rep("A", 1500)
    local code, resp = httpplus.request({
        url = urlbase .. "/headers",
        headers = { ["X-Long-Header"] = long_value },
        timeout = 10
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.headers and data.headers["X-Long-Header"] == long_value, "长 header 回显不一致")
end

-- POST：body 为 table，自动 JSON 编码
function httpplus_test.test_httpplus_post_json_table()
    local payload = { device = "LuatOS", feature = "httpplus" }
    local code, resp = httpplus.request({
        url = urlbase .. "/post",
        body = payload,
        timeout = 10
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.json and data.json.device == "LuatOS", "JSON 回显不一致")
end

-- POST：urlencoded 表单提交
function httpplus_test.test_httpplus_post_form_urlencoded()
    local form = { foo = "bar", answer = "42" }
    local code, resp = httpplus.request({
        url = urlbase .. "/post",
        forms = form,
        timeout = 10
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.form and data.form.foo == "bar", "表单回显缺失")
    assert(data.form and data.form.answer == "42", "表单值错误")
end

-- POST：multipart 同时携带文件和表单
function httpplus_test.test_httpplus_post_multipart_file()
    local expected = read_fixture(upload_fixture_path)
    local code, resp = httpplus.request({
        url = urlbase .. "/post",
        files = { uploadFile = upload_fixture_path },
        forms = { note = "multipart+file" },
        timeout = 15
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.files and data.files.uploadFile == expected, "文件回显不一致")
    assert(data.form and data.form.note == "multipart+file", "表单回显不一致")
end

-- POST：大 body 使用 zbuff 上传，验证长度不受限制
function httpplus_test.test_httpplus_post_zbuff_large_body()
    local size = 40 * 1024
    local payload = zbuff.create(size)
    payload:write(string.rep("Z", size))
    local code, resp = httpplus.request({
        url = urlbase .. "/post",
        headers = { ["Content-Type"] = "application/octet-stream" },
        body = payload,
        timeout = 20
    })
    -- log.info("httpplus_test", "POST 大 body 响应码", code, resp and resp.body and resp.body:len() or 0)
    -- log.info("httpplus_test", "POST 大 body 响应体预览", resp and resp.body and resp.body:query() or "")
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.data and #data.data == size, string.format("预期长度 %d, 实际 %s", size, data.data and #data.data or 0))
end

-- POST：bodyfile 直接上传文件内容
function httpplus_test.test_httpplus_post_bodyfile()
    local expected = read_fixture(upload_fixture_path)
    local code, resp = httpplus.request({
        url = urlbase .. "/post",
        headers = { ["Content-Type"] = "text/plain" },
        bodyfile = upload_fixture_path,
        timeout = 15
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.data == expected, "bodyfile 上传内容不一致")
end

-- GET：URL 携带鉴权信息，验证自动 Authorization 头
function httpplus_test.test_httpplus_get_basic_auth()
    log.info("httpplus_test", "GET 带鉴权")
    local code, resp = httpplus.request({
        url = "http://user:passwd@httpbin.air32.cn/basic-auth/user/passwd",
        timeout = 10
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.authenticated == true, "鉴权失败")
end

-- POST：无效 URL，预期返回本地错误码
function httpplus_test.test_httpplus_invalid_url()
    local code = httpplus.request({ url = "abc" })
    assert(code < 0, "预期失败, 实际 " .. tostring(code))
end

-- POST：bodyfile 文件不存在，预期失败
function httpplus_test.test_httpplus_missing_bodyfile()
    local code = httpplus.request({
        url = urlbase .. "/post",
        bodyfile = "/luadb/not_exists.bin",
        timeout = 5
    })
    assert(code < 0, "预期失败, 实际 " .. tostring(code))
end

-- GET：超时场景，快速返回错误码
function httpplus_test.test_httpplus_timeout()
    local code = httpplus.request({
        url = urlbase .. "/delay/5",
        timeout = 1
    })
    assert(code < 0, "预期超时失败, 实际 " .. tostring(code))
end

-- HTTPS：基础 GET，验证 TLS 通路
function httpplus_test.test_httpplus_https_get_basic()
    log.info("httpplus_test", "HTTPS 基础请求")
    local code, resp = httpplus.request({ url = "https://httpbin.air32.cn/get", timeout = 10 })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local _, raw = decode_body(resp)
    assert(raw and #raw > 0, "HTTPS GET body 为空")
end

-- HTTPS：POST JSON，确认加密链路下的 body 与回显
function httpplus_test.test_httpplus_https_post_json()
    local payload = { secure = true, feature = "httpplus" }
    local code, resp = httpplus.request({
        url = "https://httpbin.air32.cn/post",
        body = payload,
        timeout = 15
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.json and data.json.secure == true, "HTTPS JSON 回显不一致")
end

-- HTTPS：multipart 文件 + 表单
function httpplus_test.test_httpplus_https_post_multipart_file()
    local expected = read_fixture(upload_fixture_path)
    local code, resp = httpplus.request({
        url = "https://httpbin.air32.cn/post",
        files = { uploadFile = upload_fixture_path },
        forms = { note = "https-multipart" },
        timeout = 20
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.files and data.files.uploadFile == expected, "HTTPS 文件回显不一致")
    assert(data.form and data.form.note == "https-multipart", "HTTPS 表单回显不一致")
end

-- 多种 Method 覆盖：GET/POST/PUT/DELETE/PATCH，分别校验 http/https 状态码
function httpplus_test.test_httpplus_methods_status_codes()
    local status_codes = {200, 201, 204}
    local methods = {"GET", "POST", "PUT", "DELETE", "PATCH"}

    for _, code in ipairs(status_codes) do
        for _, m in ipairs(methods) do
            local url_http = string.format("http://httpbin.air32.cn/status/%d", code)
            local resp_code = httpplus.request({ method = m, url = url_http, timeout = 10 })
            assert(resp_code == code, string.format("HTTP %s 预期 %d, 实际 %s", m, code, tostring(resp_code)))
            sys.wait(10)
            collectgarbage("collect")
            collectgarbage("collect")
            local url_https = string.format("https://httpbin.air32.cn/status/%d", code)
            resp_code = httpplus.request({ method = m, url = url_https, timeout = 10 })
            assert(resp_code == code, string.format("HTTPS %s 预期 %d, 实际 %s", m, code, tostring(resp_code)))
            sys.wait(10)
        end
    end
end

-- HTTPS：chunked 流式输出，验证分块解码能力
function httpplus_test.test_httpplus_https_chunked_stream()
    log.info("httpplus_test", "HTTPS chunked stream")
    local code, resp = httpplus.request({ url = "https://httpbin.air32.cn/stream/100", timeout = 20 })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    assert(resp and resp.body, "响应体缺失")
    local raw = resp.body:query()
    assert(raw and #raw > 0, "chunked body 为空")
    local lines = {}
    for line in raw:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
    end
    assert(#lines == 100, string.format("预期 100 行, 实际 %d", #lines))
    local first = json.decode(lines[1])
    assert(first and first.url, "首行 JSON 解析失败")
end

-- 文件表单上传,支持参数值是数字类型
function httpplus_test.test_httpplus_post_multipart_file_with_number_form()
    local expected = read_fixture(upload_fixture_path)
    local code, resp = httpplus.request({
        url = urlbase .. "/post",
        files = { uploadFile = upload_fixture_path },
        forms = { note = "multipart+file", count = 12345 },
        timeout = 15
    })
    assert(code == 200, "预期 200, 实际 " .. tostring(code))
    local data = decode_body(resp)
    assert(data.files and data.files.uploadFile == expected, "文件回显不一致")
    assert(data.form and data.form.note == "multipart+file", "表单回显不一致")
    assert(tonumber(data.form.count) == 12345, "数字类型表单值回显不一致")
end

return httpplus_test
