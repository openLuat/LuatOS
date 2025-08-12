--[[
@module  http_test
@summary http_test 网络测试http模块 
@version 1.0
@date    2025.07.14
@author  wjq
@usage
本文件为网络管理模块，核心业务逻辑为：
1、循环进行http请求，测试不同网络切换时能否正常使用网络
本文件没有对外接口，直接在main.lua中require "http_test"就可以加载运行；
]]
-- 如果打算 MQTT+HTTP 同时测试，建议注释掉下段代码，否则会重复打印（MQTT 中也会打印）。
exnetif.notify_status(function(net_type, adapter)
    log.info("可以使用优先级更高的网络:", net_type, adapter)
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(6000)
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil,{ timeout = 3000}).wait()
        if body then
            log.info("http", "状态码: ", code, "body长度: ", #body)
        else
            log.info("http", "状态码: ", code)
        end
    end
end)


