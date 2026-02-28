--[[
@module  prj_3_tcp_short
@summary PSM+模式下的tcp client短连接应用项目主功能模块
@version 1.0
@date    2026.02.09
@author  马梦阳
@usage
本文件为psm+模式下的tcp短连接应用项目主功能模块，核心业务逻辑为：
1、初始化时配置最低功耗模式为psm+模式
2、启动一个tcp client短连接，连接tcp server；连接断开后，不会自动重连
3、tcp client发送一次数据到tcp server，无论成功还是失败，一段时间后主动断开连接，然后进入PSM+模式
4、tcp client接收到tcp server下发的数据后，在日志中打印出来
5、进入PSM+模式休眠一个小时唤醒后，重新执行前面的操作


Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片，GPIO23作为WiFi芯片的使能引脚，
默认状态下，GPIO23为高电平输出，在低功耗模式下，WiFi芯片部分的功耗表现为42uA左右，PSM+模式下，WiFi芯片部分的功耗表现为16uA左右，客户应根据实际项目需求进行配置
在PSM+模式示例代码中，默认关闭了WiFi芯片，以此演示PSM+模式下的实际功耗表现

Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor，GPIO24作为GNSS备电电源开关和GSensor电源开关
默认状态下，GPIO24为高电平，在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为88uA左右，客户应根据实际需求进行配置
在PSM+模式示例代码中，默认配置GPIO24为输入下拉的方式来演示PSM+模式的功耗表现


2026.01.30：目前实测WiFi芯片在PSM+模式下功耗表现为42uA左右，通过在底层关闭airlink之后可以达到理论功耗数值，暂时还在解决中...


使用Air8000系列每个模组的核心板，烧录运行此demo，在vbat供电3.8v状态下，在以下测试场景来介绍一下功耗情况：

1、插sim卡，上电开机之后，大约2.4秒后，成功进入PSM+状态；
   初始化阶段（常规模式），平均电流62.36mA；（此数据仅供参考，测试网络环境不同，持续时长以及平均电流都会不同，但是差异应该不是特别大才对）
   PSM+阶段（PSM+模式，关闭WiFi芯片，配置GPIO24为输入下拉），平均电流8.2uA左右（3.6uA到11.8uA都属于正常值）


本文件和其他功能模块的通信接口只有1个：
1、sys.publish("DRV_SET_PSM")：发布消息"DRV_SET_PSM"，通知drv_psm驱动模块配置最低功耗模式为PSM+模式
]]


require "drv_psm"
require "app_tcp_main"


-- 数据发送结果回调函数；
local function send_data_cbfunc(result)
    sys.publish("SEND_DATA_RSP", result)
end


-- tcp client短连接任务函数；
local function tcp_short_task()
    -- 发布消息“TCP_CLIENT_RUN_REQ”，通知tcp client socket主功能应用模块（例如app_tcp_main.lua）；
    -- 第二个参数用于设置连接的类型，“true”表示长连接，连接断开后会自动重连，“false”表示短连接，连接断开后不会自动重连；
    -- tcp client主功能应用模块接收到“TCP_CLIENT_RUN_REQ”消息后，根据第二个参数判断开始运行tcp client长链接任务还是短连接任务；
    sys.publish("TCP_CLIENT_RUN_REQ", false)

    -- 发布消息“SEND_DATA_REQ”，通知tcp client socket数据发送应用功能模块（例如app_tcp_sender.lua）将数据发到服务器；
    -- 发送的数据内容大致为”send from tcp_short_task: wakeup report“等；
    -- 数据发送结果会通过回调函数send_data_cbfunc返回；
    sys.publish("SEND_DATA_REQ", "tcp_short_task", "wakeup report", {func = send_data_cbfunc})

    -- 等待数据发送结果，最长等待10秒钟；
    local no_timeout, result = sys.waitUntil("SEND_DATA_RSP", 10000)
    log.info("tcp_long_task", "send data rsp", no_timeout, result)

    -- 无论发送成功还是失败，主动断开tcp client短连接；
    sys.publish("TCP_CLIENT_CLOSE_REQ")
    -- 等待断开结果，最长等待3秒钟；
    -- 为了更省电，此处也可以不等待结果，可以更快的进入PSM+模式；
    -- 代价就是server端无法及时检测到客户端已经断开，要等server端超时之后，才会清空当前客户端在server上的资源；
    no_timeout, result = sys.waitUntil("TCP_CLIENT_CLOSE_RSP", 3000)
    log.info("tcp_long_task", "tcp close rsp", no_timeout, result)


    -- 配置深度休眠定时器1小时后唤醒（定时器时长有讲究，此处的时长不要小于80秒，而且为了省电，至少要几十分钟才可能有意义）
    -- 可以在此处配置，也可以在drv_psm.lua中设置（详情请查看drv_psm.lua中的代码注释说明）
    pm.dtimerStart(0, 60*60*1000)

    -- 发布消息“DRV_SET_PSM”，通知drv_psm驱动模块配置最低功耗模式为PSM+模式；
    -- drv_psm驱动模块内部已有中断唤醒引脚和功能引脚的配置说明，根据实际项目需求打开或关闭对应配置代码即可；
    -- 在执行完中断唤醒引脚和功能引脚的配置之后，调用pm.power(pm.WORK_MODE, 3)设置最低功耗模式为PSM+模式；
    -- 设置完之后并不会里面进入休眠，而是等所有业务逻辑处理完毕之后，才会进入休眠；
    sys.publish("DRV_SET_PSM")
end

-- 启动tcp client短连接任务；
sys.taskInit(tcp_short_task)
