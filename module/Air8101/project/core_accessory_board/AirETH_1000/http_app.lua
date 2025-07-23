
--这个task的核心业务逻辑是：每隔一段时间发送一次http get请求，测试http数传是否正常
local function http_get_task_func()
    --检查当前使用的网卡(本demo使用的是以太网卡socket.LWIP_USER1)的连接状态
    log.info("http_get_task_func", "socket.adapter(socket.dft())", socket.adapter(socket.dft()))
    --如果当前使用的网卡(本demo使用的是以太网卡socket.LWIP_USER1)还没有连接成功
    if not socket.adapter(socket.dft()) then
        --net_app.lua中的以太网配置和启动结束后，一旦以太网卡准备就绪，就会产生一个"IP_READY"消息
        --在此处阻塞等待以太网连接成功的消息"IP_READY"
        --或者等待30秒超时退出阻塞等待状态
        --如果没有等到"IP_READY"消息，直接退出这个函数
        if not sys.waitUntil("IP_READY", 30000) then
            log.error("http_get_task_func error", "ip network timeout")
            return
        end
    end


    --每6秒执行一次循环
    while true do
        --发送http get请求服务器，等待服务器的http应答，此处会阻塞当前task，等待整个过程成功结束或者出现错误异常结束
        --此处使用了http.request().wait()的形式
        --http.request()的详细说明参考API文档
        --wait()表示在此处阻塞等待整个过程的结束

        --具体到此处的代码，对部分参数以及返回值做如下解释
        --timeout=3000表示超时时间为3秒，如果3秒内没有成功结束或者异常结束整个过程，则会超时结束；
        --整个过程结束后，http.request().wait()有三个返回值code，headers，body
        --code表示结果，number类型，详细说明参考API手册，一般来说：
        --             200表示成功
        --             小于0的值表示出错，例如-8表示超时错误
        --             其余结果值参考API手册
        --headers表示服务器返回的应答头，table类型
        --body表示服务器返回的应答题，具体到这里的代码使用方式，为string类型
        log.info("http", http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {timeout=3000}).wait())

        --打印使用的内存信息，方便分析内存使用情况
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))

        --打印当前使用的网卡(本demo使用的是以太网卡socket.LWIP_USER1)下的本地IP，网关，子网掩码，网关IP信息
        log.info("ip", socket.dft(), socket.localIP(socket.dft()))

        --等待6秒钟
        sys.wait(6000)
    end

end


--创建并且启动一个task
--task的主函数为http_get_task_func
sys.taskInit(http_get_task_func)
