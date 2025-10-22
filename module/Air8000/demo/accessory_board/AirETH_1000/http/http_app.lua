--[[
@module  http_app
@summary http应用功能模块
@version 1.0
@date    2025.09.17
@author  王城钧
@usage
本文件为http应用功能模块，核心业务逻辑为：基于不同的应用场景，演示http核心库的使用方式；
本文件没有对外接口，直接在main.lua中require "http_app"就可以加载运行；
]]




-- 普通的http get请求功能演示
-- 请求的body数据保存到内存变量中，在内存够用的情况下，最大支持32KB的数据存储到内存中
-- timeout可以设置超时时间
-- callback可以设置回调函数，可用于实时检测body数据的下载进度
local function http_app_get()
    -- https get请求https://www.air32.cn/网页内容
    -- 如果请求成功，请求的数据保存到body中
    local code, headers, body = http.request("GET", "https://www.air32.cn/").wait()
    log.info("http_app_get1",
        code == 200 and "success" or "error",
        code,
        json.encode(headers or {}),
        body and (body:len() > 512 and body:len() or body) or "nil")

    -- https get请求https://www.luatos.com/网页内容，超时时间为10秒
    -- 请求超时时间为10秒，用户自己写代码时，不要照抄10秒，根据自己业务逻辑的需要设置合适的超时时间
    -- 回调函数为http_cbfunc，回调函数使用的第三个回调参数为"http_app_get2"
    -- 如果请求成功，请求的数据保存到body中
    code, headers, body = http.request("GET", "https://www.luatos.com/", nil, nil,
        { timeout = 10000, userdata = "http_app_get2", callback = http_cbfunc }).wait()
    log.info("http_app_get2",
        code == 200 and "success" or "error",
        code,
        json.encode(headers or {}),
        body and (body:len() > 512 and body:len() or body) or "nil")

    -- http get请求http://httpbin.air32.cn/get网页内容，超时时间为3秒
    -- 请求超时时间为3秒，用户自己写代码时，不要照抄3秒，根据自己业务逻辑的需要设置合适的超时时间
    -- 回调函数为http_cbfunc，回调函数使用的第三个回调参数为"http_app_get3"
    -- 如果请求成功，请求的数据保存到body中
    code, headers, body = http.request("GET", "http://httpbin.air32.cn/get", nil, nil,
        { timeout = 3000, userdata = "http_app_get3", callback = http_cbfunc }).wait()
    log.info("http_app_get3",
        code == 200 and "success" or "error",
        code,
        json.encode(headers or {}),
        body and (body:len() > 512 and body:len() or body) or "nil")
end

-- http app task 的任务处理函数
local function http_app_task_func()
    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("http_app_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("http_app_task_func", "recv IP_READY", socket.dft())

        -- 普通的http get请求功能演示
        http_app_get()

        -- 50秒之后，循环测试
        sys.wait(50000)
    end
end

--创建并且启动一个task
--运行这个task的处理函数http_app_task_func
sys.taskInit(http_app_task_func)
