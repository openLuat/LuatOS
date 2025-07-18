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
sys.taskInit(function()
    while 1 do
        sys.wait(6000)
        log.info("http",
            http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil).wait())
    end
end)

