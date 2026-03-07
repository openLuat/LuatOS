test_wlan = {}

gpio.setup(20, 1) -- 打开lan供电

local url = "http://httpbin.air32.cn"

-- 测试用例函数
function test_wlan.test_wan()
    log.info("启动HTTP测试")
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
    }}
    -- 调试输出
    local code = http.request("GET", "https://www.air32.cn/").wait()

    -- 验证返回值
    if code == tests.expected_code then
        log.info("本次测试的是", tests.description, "code 符合预期结果 code = ", code)
    else
        log.info("本次测试的是", tests.description, "预期结果为", tests.expected_code,
            "code 不符合预期结果 code =", code)
    end
end

return test_wlan
