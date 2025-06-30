local air_http = {}
local test_type = "http_test"
local url = "http://httpbin.air32.cn"

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

-- 测试用例函数
function air_http.run_tests()
    -- sys.waitUntil("net_ready")
    local tests = { -- GET 方法测试
    {
        method = "GET",
        url = url .. "/get",
        headers = nil,
        body = nil,
        opts = {},
        expected_code = 200,
        description = "GET方法,无请求头、body以及额外的附加数据"
    }, {
        method = "GET",
        url = url .. "/get",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = nil,
        opts = {},
        expected_code = 200,
        description = "GET方法,有请求头,无body和额外的附加数据"
    }, {
        method = "GET",
        url = url .. "/get",
        headers = nil,
        body = nil,
        opts = {
            timeout = 5000,
            debug = true
        },
        expected_code = 200,
        description = "GET方法,无请求头,无body,超时时间5S,debug日志打开"
    }, -- GET 方法测试（下载 2K 小文件）
    {
        method = "GET",
        url = "http://airtest.openluat.com:2900/download/2K", -- 返回 2K 字节的文件
        headers = nil,
        body = nil,
        opts = {},
        expected_code = 200,
        description = "GET方法 2K小文件下载"
    }, {
        method = "GET",
        url = "http://invalid-url",
        headers = nil,
        body = nil,
        opts = {},
        expected_code = -4,
        description = "GET方法,无效的url,域名"
    }, {
        method = "GET",
        -- url = "http://invalid-url",
        url = "192.168.1",
        headers = nil,
        body = nil,
        opts = {},
        expected_code = -4,
        description = "GET方法,无效的url,IP地址"
    }, -- POST 方法测试
    {
        method = "POST",
        url = url .. "/post",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = '{"key": "value"}',
        opts = {},
        expected_code = 200,
        description = "POST方法,有请求头,body为json"
    }, {
        method = "POST",
        url = url .. "/post",
        headers = nil,
        body = nil,
        opts = {},
        expected_code = 200,
        description = "POST方法,无请求头,无body,无额外的数据"
    }, {
        method = "POST",
        url = "clahflkjfpsjvlsvnlohvioehoi",
        headers = nil,
        body = nil,
        opts = {},
        expected_code = -4,
        description = "POST方法,无效的url,域名"
    }, {
        method = "POST",
        -- url = "http://invalid-url",
        url = "192.168.1",
        headers = nil,
        body = nil,
        opts = {},
        expected_code = -4,
        description = "POST方法,无效的url,IP地址"
    }, -- POST 方法测试（上传 30K 大文件）
    {
        method = "POST",
        url = url .. "/post",
        headers = {
            ["Content-Type"] = "application/octet-stream"
        },
        body = string.rep("A", 30 * 1024), -- 生成 30K 的数据
        opts = {},
        expected_code = 200,
        description = "POST 30K大数据上传"
    }, {
        method = "POST",
        url = url .. "/post",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        },
        body = "key=value",
        opts = {
            timeout = 5000
        },
        expected_code = 200,
        description = "POST方法,有请求头,body为json,超时时间5S"
    }, -- HTTPS GET 方法测试（双向认证）
    {
        method = "GET",
        url = url .. "/get",
        headers = nil,
        body = nil,
        opts = {
            ca = ca_server,
            client_cert = ca_client,
            client_key = client_private_key_encrypts_data,
            client_key_password = client_private_key_password
        },
        expected_code = 200,
        description = "HTTPS GET方法,无请求头,无body,带双向认证的服务器证书、客户端证书、客户端key,客户端password"
    }, -- HTTPS POST 方法测试（双向认证）
    {
        method = "POST",
        url = url .. "/post",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = '{"key": "value"}',
        opts = {
            ca = ca_server,
            client_cert = ca_client,
            client_key = client_private_key_encrypts_data,
            client_key_password = client_private_key_password
        },
        expected_code = 200,
        description = "HTTPS POST方法,有请求头,body为json,带双向认证的服务器证书、客户端证书、客户端key,客户端password"
    }}
    local tests_len = #tests
    local len = 0
    local pass = true
    local failing_item = nil
    local test_mode
    for i, test in ipairs(tests) do
        len = len + 1
        lcd.clear()
        local code, headers, body = http.request(test.method, test.url, test.headers, test.body, test.opts).wait()

        -- 调试输出
        print(string.format("Test %d: %s", i, test.description))
        print("Returned values: code =", code, ", headers =", headers, ", body =", body)

        -- 验证返回值
        if code == test.expected_code then
            log.info("本次测试的是", test.description, "code 符合预期结果 code = ", code)
            -- lcd.drawStr(50,50,"testrady")
            lcd.drawStr(10, 200,
                string.format("本次测试的是%s,code符合预期结果code=%d", test.description, code))
        else
            log.info("本次测试的是", test.description, "预期结果为", test.expected_code,
                "code 不符合预期结果 code =", code)
            lcd.drawStr(50, 50,
                string.format("本次测试的是%s,code不符合预期结果code=%d", test.description, code))
            pass = false
            failing_item = test.description
            -- break
        end
        sys.wait(5000)

        --http所有测试项目完成
        if len == tests_len then
            lcd.clear()
            log.info("测试结束")
            lcd.drawStr(50, 50, "测试结束")
            if pass then
                test_mode  = "测试所有项目通过"
                log.info(test_mode)
                lcd.drawStr(70, 40, test_mode)
            else
                test_mode = "测试有项目未通过"
                log.info("测试有项目未通过")
                lcd.drawStr(70, 60, "测试有项目未通过")
                lcd.drawStr(100, 80, "失败的项目是:" .. failing_item)
            end

            local data = {
                type = test_type,
                test_mode = test_mode,
                test_end = pass or failing_item,
                fail_res = pass or "code不符合预期结果code=" .. code,
                imei = mobile.imei()
            }
            local data = json.encode(data)
            sys.publish("OTHER_FILE_SENDMSG",data)
            -- sys.wait(5000)
            break
        end

    end
end

return air_http
