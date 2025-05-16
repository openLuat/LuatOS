-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

sys.taskInit(function()
    sys.wait(3000)
    local result = spi.setup(0, -- 串口id
    nil, 0, -- CPHA
    0, -- CPOL
    8, -- 数据宽度
    25600000 -- ,--频率
    -- spi.MSB,--高低位顺序    可选，默认高位在前
    -- spi.master,--主模式     可选，默认主
    -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open", result)
    if result ~= 0 then -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        return
    end

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spiid = 0,
        cs = 8
    })
    netdrv.dhcp(socket.LWIP_ETH, true)
    -- sys.wait(3000)
    while 1 do
        local ipv4ip, aaa, bbb = netdrv.ipv4(socket.LWIP_ETH, "", "", "")
        log.info("ipv4地址,掩码,网关为", ipv4ip, aaa, bbb)
        local netdrv_start = netdrv.ready(socket.LWIP_ETH)
        if netdrv_start and ipv4ip and ipv4ip ~= "0.0.0.0" then
            log.info("条件都满足")
            sys.publish("CH390_IP_READY")
            return
        end
        sys.wait(1000)
    end

end)

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
local ca_server = read_file("/luadb/ca.crt") -- 服务器 CA 证书数据
local ca_client = read_file("/luadb/client.crt") -- 客户端 CA 证书数据
local client_private_key_encrypts_data = read_file("/luadb/client.key") -- 客户端私钥
local client_private_key_password = "123456789" -- 客户端私钥口令

-- 测试用例函数
local function run_tests()
    log.info("启动HTTP多项测试")
    local tests = { -- GET 方法测试
    {
        method = "GET",
        url = url .. "/get",
        headers = nil,
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH

        },
        expected_code = 200,
        description = "GET方法,无请求头、body以及额外的附加数据"
    }, {
        method = "GET",
        url = url .. "/get",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH

        },
        expected_code = 200,
        description = "GET方法,有请求头,无body和额外的附加数据"
    }, {
        method = "GET",
        url = url .. "/get",
        headers = nil,
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH,
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
        opts = {
            adapter = socket.LWIP_ETH,
        },
        expected_code = 200,
        description = "GET 2K小文件下载"
    }, {
        method = "GET",
        url = "http://invalid-url",
        headers = nil,
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH,
        },
        expected_code = -4,
        description = "GET方法,无效的url,域名"
    }, {
        method = "GET",
        -- url = "http://invalid-url",
        url = "192.168.1",
        headers = nil,
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH,
        },
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
        opts = {
            adapter = socket.LWIP_ETH,
        },
        expected_code = 200,
        description = "POST方法,有请求头,body为json"
    }, {
        method = "POST",
        url = url .. "/post",
        headers = nil,
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH,
        },
        expected_code = 200,
        description = "POST方法,无请求头,无body,无额外的数据"
    }, {
        method = "POST",
        url = "clahflkjfpsjvlsvnlohvioehoi",
        headers = nil,
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH,
        },
        expected_code = -4,
        description = "POST方法,无效的url,域名"
    }, {
        method = "POST",
        -- url = "http://invalid-url",
        url = "192.168.1",
        headers = nil,
        body = nil,
        opts = {
            adapter = socket.LWIP_ETH,
        },
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
        opts = {
            adapter = socket.LWIP_ETH,
        },
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
            adapter = socket.LWIP_ETH,
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
            adapter = socket.LWIP_ETH,
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
            adapter = socket.LWIP_ETH,
            ca = ca_server,
            client_cert = ca_client,
            client_key = client_private_key_encrypts_data,
            client_key_password = client_private_key_password
        },
        expected_code = 200,
        description = "HTTPS POST方法,有请求头,body为json,带双向认证的服务器证书、客户端证书、客户端key,客户端password"
    }}

    for i, test in ipairs(tests) do
        log.info("HTTP第" .. i .. "次测试")
        -- sys.wait(5000)
        local code, headers, body = http.request(test.method, test.url, test.headers, test.body, test.opts).wait()

        -- 调试输出
        print(string.format("Test %d: %s", i, test.description))
        print("Returned values: code =", code, ", headers =", headers, ", body =", body)

        -- 验证返回值
        if code == test.expected_code then
            log.info("本次测试的是", test.description, "code 符合预期结果 code = ", code)
        else
            log.info("本次测试的是", test.description, "预期结果为", test.expected_code,
                "code 不符合预期结果 code =", code)

        end
    end
end

-- 运行测试用例
sys.taskInit(function()

    sys.waitUntil("CH390_IP_READY")
    log.info("CH390 联网成功，开始测试")
    socket.dft(socket.LWIP_ETH)
    -- 如果自带的DNS不好用，可以用下面的公用DNS,但是一定是要在CH390联网成功后使用
    -- socket.setDNS(socket.LWIP_ETH,1,"223.5.5.5")	
    -- socket.setDNS(nil,1,"114.114.114.114")
    run_tests()

end)
