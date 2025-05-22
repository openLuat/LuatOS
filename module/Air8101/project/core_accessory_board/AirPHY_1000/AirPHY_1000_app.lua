-- 本demo演示的硬件环境为：
-- 使用Air8101核心板+AirPHY_1000配件板，配件板上的以太网口通过网线连接路由器；
-- AirPHY_1000是合宙设计生产的一款搭载LAN8720Ai芯片的以太网配件板，可以搭配Air8101使用；

-- 本demo演示的业务逻辑为：
-- 以太网环境准备好之后，Air8101做为以太网客户端会被分配IP地址；
-- 然后Air8101启动一个http get请求，等待http get应答或者3秒超时没有收到应答退出等待；
-- 每隔6秒循环执行一次上卖弄描述的http get请求动作；




--本demo中，Air8101核心板和AirPHY_1000配件板的接线方式如下
--Air8101核心板             AirPHY_1000配件板
--     59/3V3-----------------3.3v
--     gnd-----------------gnd
--     69/D7-----------------CLK
--     7/D6-----------------K4
--     70/D5-----------------K5
--     74/PCK-----------------K6
--     6/D4-----------------K7
--     4/D0-----------------K8
--     71/D3-----------------G
--     72/D1-----------------G
--     5/D2-----------------G




--这个task的核心业务逻辑是：每隔一段时间发送一次http get请求，测试http数传是否正常
local function http_get_task_func()
    log.info("http_get_task_func enter")

    --等待以太网卡准备就绪
    --ethernet_setup_task_func中的以太网配置和启动结束后，一旦以太网卡准备就绪，就会产生一个"IP_READY"消息
    --所以此处阻塞等待这个消息即可
    --注意：阻塞等待的动作一定要在以太网配置和启动动作之前，否则有可能先产生"IP_READY"消息，后阻塞等待这个消息，就会错过这个消息，而一直死等
    sys.waitUntil("IP_READY")

    
    --每6秒执行一次循环
    while true do
        sys.wait(6000)

        --发送http get请求服务器，等待服务器的http应答，此处会阻塞当前task，等待整个过程成功结束或者出现错误异常结束
        --此处使用了http.request().wait()的形式
        --http.request()的详细说明参考API文档
        --wait()表示在此处阻塞等待整个过程的结束

        --具体到此处的代码，对部分参数以及返回值做如下解释
        --adapter=socket.LWIP_ETH表示使用的是以太网卡
        --timeout=3000表示超时时间为3秒，如果3秒内没有成功结束或者异常结束整个过程，则会超时结束；
        --整个过程结束后，http.request().wait()有三个返回值code，headers，body
        --code表示结果，number类型，详细说明参考API手册，一般来说：
        --             200表示成功
        --             小于0的值表示出错，例如-8表示超时错误
        --             其余结果值参考API手册
        --headers表示服务器返回的应答头，table类型
        --body表示服务器返回的应答题，具体到这里的代码使用方式，为string类型
        log.info("http", http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {adapter=socket.LWIP_ETH,timeout=3000}).wait())

        --打印使用的内存信息，方便分析内存使用情况
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))

        --打印以太网卡下的本地IP，网关，子网掩码，网关IP信息
        log.info("ip", socket.localIP(socket.LWIP_ETH))
    end

end


--这个task的核心业务逻辑是：配置并且启动以太网卡
local function ethernet_setup_task_func()
    log.info("ethernet_setup_task_func enter")

    --本demo测试使用的是核心板的VDD 3V3引脚对AirPHY_1000配件板进行供电
    --VDD 3V3引脚是Air8101内部的LDO输出引脚，最大输出电流300mA
    --GPIO13在Air8101内部使能控制这个LDO的输出
    --所以在此处GPIO13输出高电平打开这个LDO
    gpio.setup(13, 1, gpio.PULLUP) 

    --初始化以太网卡
    netdrv.setup(socket.LWIP_ETH)
    --开启动态主机配置协议
    netdrv.dhcp(socket.LWIP_ETH, true)
end


--创建并且启动一个task
--这个task的核心业务逻辑是：每隔一段时间发送一次http get请求，测试http数传是否正常
sys.taskInit(http_get_task_func)

--创建并且启动一个task
--这个task的核心业务逻辑是：配置并且启动以太网卡
sys.taskInit(ethernet_setup_task_func)


