--[[
@module  tcp_ssl_ca_main
@summary tcp_ssl_ca client socket主应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为tcp_ssl_ca client socket主应用功能模块，核心业务逻辑为：
1、创建一个tcp_ssl_ca client socket，连接server；
2、处理连接异常，出现异常后执行重连动作；
3、调用tcp_ssl_ca_receiver和tcp_ssl_ca_sender中的外部接口，进行数据收发处理；

本文件没有对外接口，直接在main.lua中require "tcp_ssl_ca_main"就可以加载运行；
]]

local libnet = require "libnet"

-- 加载sntp时间同步应用功能模块（ca证书校验的ssl socket需要时间同步功能）
require "sntp_app"

-- 加载tcp_ssl_ca client socket数据接收功能模块
local tcp_ssl_ca_receiver = require "tcp_ssl_ca_receiver"
-- 加载tcp_ssl_ca client socket数据发送功能模块
local tcp_ssl_ca_sender = require "tcp_ssl_ca_sender"

-- https://www.baidu.com网站服务器，地址为"www.baidu.com"，端口为443
local SERVER_ADDR = "www.baidu.com"
local SERVER_PORT = 443

-- tcp_ssl_ca_main的任务名
local TASK_NAME = tcp_ssl_ca_sender.TASK_NAME


-- 处理未识别的消息
local function tcp_ssl_ca_main_cbfunc(msg)
	log.info("tcp_ssl_ca_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end

-- tcp_ssl_ca client socket的任务处理函数
local function tcp_ssl_ca_main_task_func() 

    local socket_client
    local result, para1, para2

    -- 用来验证server证书是否合法的ca证书文件为baidu_parent_ca.crt
    -- 此ca证书的有效期截止到2028年11月21日
    -- 将这个ca证书文件的内容读取出来，赋值给server_ca_cert
    -- 注意：此处的ca证书文件仅用来验证baidu网站的server证书
    -- baidu网站的server证书有效期截止到2026年8月10日
    -- 在有效期之前，baidu会更换server证书，如果server证书更换后，此处验证使用的baidu_parent_ca.crt也可能需要更换
    -- 使用电脑上的网页浏览器访问https://www.baidu.com，可以实时看到baidu的server证书以及baidu_parent_ca.crt
    -- 如果你使用的是自己的server，要替换为自己server证书对应的ca证书文件
    local server_ca_cert = io.readFile("/luadb/baidu_parent_ca.crt")

    while true do
        -- 如果当前时间点设置的网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("tcp_ssl_ca_main_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用libnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改当前使用的网卡
            -- 当libnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("tcp_ssl_ca_main_task_func", "recv IP_READY", socket.dft())

        -- 创建socket client对象
        socket_client = socket.create(nil, TASK_NAME)
        -- 如果创建socket client对象失败
        if not socket_client then
            log.error("tcp_ssl_ca_main_task_func", "socket.create error")
            goto EXCEPTION_PROC
        end

        -- 配置socket client对象为tcp_ssl_ca client
        -- client仅单向校验server的证书，server不校验client的证书和密钥文件
        -- 如果做证书校验，需要特别注意以下几点：
        -- 1、证书校验前，设备端必须同步为正确的时间，因为校验过程中会检查ca证书以及server证书中的有效期是否合法；本demo中的sntp_app.lua会同步时间；
        -- 2、任何证书都有有效期，无论是ca证书还是server证书，必须在有效期截止之前，及时更换证书，延长有效期，否则证书校验会失败；
        -- 3、如果要更换ca证书，需要在设备端远程升级，必须保证ca证书失效之前升级成功，否则校验失败，就无法连接server；
        -- 综上所述，证书校验虽然安全，可以验证身份，但是后续维护成本比较高；除非有需要，否则可以不配置证书校验功能；
        -- 另外，如果使用https://netlab.luatos.com/创建的TCP SSL Server，使用的server证书有可能过了有效期；
        -- 如果过了有效期，使用本文件无法连接成功tcp ssl ca server，遇到这种问题，可以在main.lua中打开socket.sslLog(3)，观察Luatools的日志，如果出现类似于下面的日志
        -- expires on        : 2020-12-27 15:46:55
        -- 表示证书有效期截止到2020-12-27 15:46:55，明显就是证书已经过了有效期
        -- 遇到这种情况，可以反馈给合宙的技术人员；或者不再使用netlab server测试，使用你自己的tcp ssl server来测试，只要保证你的server证书合法就行；
        result = socket.config(socket_client, nil, nil, true, nil, nil, nil, server_ca_cert)
        -- 如果配置失败
        if not result then
            log.error("tcp_ssl_ca_main_task_func", "socket.config error")
            goto EXCEPTION_PROC
        end

        -- 连接server
        result = libnet.connect(TASK_NAME, 15000, socket_client, SERVER_ADDR, SERVER_PORT)
        -- 如果连接server失败
        if not result then
            log.error("tcp_ssl_ca_main_task_func", "libnet.connect error")
            goto EXCEPTION_PROC
        end

        log.info("tcp_ssl_ca_main_task_func", "libnet.connect success")

        -- 数据收发以及网络连接异常事件总处理逻辑
        while true do
            -- 数据接收处理（接收处理必须写在libnet.wait之前，因为老版本的内核固件要求必须这样，新版本的内核固件没这个要求，为了不出问题，写在libnet.wait之前就行了）
            -- 如果处理失败，则退出循环
            if not tcp_ssl_ca_receiver.proc(socket_client) then
                log.error("tcp_ssl_ca_main_task_func", "tcp_ssl_ca_receiver.proc error")
                break
            end

            -- 数据发送处理
            -- 如果处理失败，则退出循环
            if not tcp_ssl_ca_sender.proc(TASK_NAME, socket_client) then
                log.error("tcp_ssl_ca_main_task_func", "tcp_ssl_ca_sender.proc error")
                break
            end

            -- 阻塞等待socket.EVENT事件或者15秒钟超时
            -- 以下三种业务逻辑会发布事件：
            -- 1、socket client和server之间的连接出现异常（例如server主动断开，网络环境出现异常等），此时在内核固件中会发布事件socket.EVENT
            -- 2、socket client接收到server发送过来的数据，此时在内核固件中会发布事件socket.EVENT
            -- 3、socket client需要发送数据到server, 在tcp_ssl_ca_sender.lua中会发布事件socket.EVENT
			result, para1, para2 = libnet.wait(TASK_NAME, 15000, socket_client)
            log.info("tcp_ssl_ca_main_task_func", "libnet.wait", result, para1, para2)
			
			-- 如果连接异常，则退出循环
			if not result then
				log.warn("tcp_ssl_ca_main_task_func", "connection exception")
				break
            end
        end


        -- 出现异常    
        ::EXCEPTION_PROC::

        -- 数据发送应用模块对来不及发送的数据做清空和通知失败处理
        tcp_ssl_ca_sender.exception_proc()

        -- 如果存在socket client对象
        if socket_client then
            -- 关闭socket client连接
            libnet.close(TASK_NAME, 5000, socket_client)

            -- 释放socket client对象
            socket.release(socket_client)
            socket_client = nil
        end
        
        -- 5秒后跳转到循环体开始位置，自动发起重连
        sys.wait(5000)
    end
end

--创建并且启动一个task
--运行这个task的主函数tcp_ssl_ca_main_task_func
sysplus.taskInitEx(tcp_ssl_ca_main_task_func, TASK_NAME, tcp_ssl_ca_main_cbfunc)

