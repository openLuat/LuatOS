--[[
本demo演示的核心功能为：
1、创建四路socket连接，详情如下
- 创建一个tcp client，连接tcp server；
- 创建一个udp client，连接udp server；
- 创建一个tcp ssl client，连接tcp ssl server，不做证书校验；
- 创建一个tcp ssl client，连接tcp ssl server，client仅单向校验server的证书，server不校验client的证书和密钥文件；
2、每一路socket连接出现异常后，自动重连；
3、每一路socket连接，client按照以下几种逻辑发送数据给server
- 串口应用功能模块uart_app.lua，通过uart1接收到串口数据，将串口数据增加send from uart: 前缀后发送给server；
- 定时器应用功能模块timer_app.lua，定时产生数据，将数据增加send from timer：前缀后发送给server；
4、每一路socket连接，client收到server数据后，将数据增加recv from tcp/udp/tcp ssl/tcp ssl ca（四选一）server: 前缀后，通过uart1发送出去；
5、每一路socket连接，启动一个网络业务逻辑看门狗task，用来监控socket工作状态，如果连续长时间工作不正常，重启整个软件系统（后续补充）；

更多说明参考本目录下的readme.md文件
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "SOCKET_LONG_CONNECTION"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    --配置喂狗超时时间为9秒钟
    wdt.init(9000)
    --启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 加载WIFI网络连接管理应用功能模块
require "wifi_app"

-- 加载串口应用功能模块
require "uart_app"
-- 加载定时器应用功能模块
require "timer_app"
-- 加载测试应用功能模块(只有调试某些接口时才需要)
-- require "test_app"

-- 加载tcp client socket主应用功能模块
require "tcp_client_main"

-- 加载udp client socket主应用功能模块
require "udp_client_main"

-- 打开内核固件中ssl的调试日志（需要分析问题时再打开）
-- socket.sslLog(3)
-- 加载tcp ssl client socket主应用功能模块
require "tcp_ssl_main"

-- 加载sntp时间同步应用功能模块（ca证书校验的ssl socket需要时间同步功能）
require "sntp_app"
-- 加载tcp ssl ca client socket主应用功能模块
require "tcp_ssl_ca_main"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
