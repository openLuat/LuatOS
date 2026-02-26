--[[
@module  prj_1_tcp_long
@summary 低功耗模式（WORKMODE 1）下的tcp client长连接应用项目主功能模块 
@version 1.0
@date    2026.02.12
@author  马梦阳
@usage
本文件为低功耗模式（WORKMODE 1）下的tcp长连接应用项目主功能模块，核心业务逻辑为：
1、初始化时配置最低功耗模式为低功耗模式（WORKMODE 1）
2、启动一个tcp client长连接，连接tcp server；连接断开后，自动重连
3、tcp client每隔一段时间发送数据到tcp server
4、tcp client接收到tcp server下发的数据后，在日志中打印出来


Air780EGP/EGG模组内部包含有GNSS和Gsensor，Air780EGH模组内部只包含有GNSS，不包含Gsensor；
GPIO23作为GNSS备电电源开关和Gsensor电源开关，默认状态下为高电平；
在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为200uA左右，客户应根据实际需求进行配置；
在低功耗模式示例代码中，并未对GPIO23进行配置，默认状态下为高电平，以此演示低功耗模式下的实际功耗表现；


使用Air780EXX系列每个模组的核心板，烧录运行此demo，在vbat供电3.8v状态下，在以下测试场景来介绍一下功耗情况：


1、插sim卡，上电开机之后，大约9秒后，成功进入低功耗状态；
   初始化阶段（常规模式），平均电流33mA；（此数据仅供参考，测试网络环境不同，持续时长以及平均电流都会不同，但是差异应该不是特别大才对）
   低功耗阶段（因为有网络寻呼和tcp交互，所以是低功耗模式+常规模式自动切换），平均电流2.3mA左右（2.1mA到2.7mA左右都属于正常值，和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准，但是差异应该不是特别大才对）


本文件和其他功能模块的通信接口只有1个：
1、sys.publish("DRV_SET_LOWPOWER")：发布消息"DRV_SET_LOWPOWER"，通知drv_lowpower驱动模块配置最低功耗模式为低功耗模式
]]


require "drv_lowpower"
require "app_tcp_main"


-- 数据发送结果回调函数；
local function send_data_cbfunc(result)
    sys.publish("SEND_DATA_RSP", result)
end


-- tcp client长连接任务函数；
local function tcp_long_task()
    -- 发布消息“TCP_CLIENT_RUN_REQ”，通知tcp client socket主功能应用模块（例如app_tcp_main.lua）；
    -- 第二个参数用于设置连接的类型，“true”表示长连接，连接断开后会自动重连，“false”表示短连接，连接断开后不会自动重连；
    -- tcp client主功能应用模块接收到“TCP_CLIENT_RUN_REQ”消息后，根据第二个参数判断开始运行tcp client长链接任务还是短连接任务；
    sys.publish("TCP_CLIENT_RUN_REQ", true)


    local count = 0 -- 发送数据的次数
    local _, result -- 用于接收数据发送结果


    -- 发布消息“SEND_DATA_REQ”，通知tcp client socket数据发送应用功能模块（例如app_tcp_sender.lua）将数据发到服务器；
    while true do
        -- 用于在发送的数据内容中体现发送的次数
        count = count + 1

        -- 发布消息“SEND_DATA_REQ”，通知tcp client socket数据发送应用功能模块（例如app_tcp_sender.lua）将数据发到服务器；
        -- 发送的数据内容大致为”send from tcp_long_task: heart_1“、”send from tcp_long_task: heart_2“等；
        -- 数据发送结果会通过回调函数send_data_cbfunc返回；
        sys.publish("SEND_DATA_REQ", "tcp_long_task", "heart_"..count, {func = send_data_cbfunc})

        -- 等待数据发送结果
        _, result = sys.waitUntil("SEND_DATA_RSP")
        log.info("tcp_long_task", "send data rsp", result)

        -- 延时5分钟之后，再次循环
        sys.wait(5*60*1000)
    end
end


-- 发布消息“DRV_SET_LOWPOWER”，通知drv_lowpower驱动模块配置最低功耗模式为低功耗模式；
-- drv_lowpower驱动模块内部已有中断唤醒引脚和功能引脚的配置说明，根据实际项目需求打开或关闭对应配置代码即可；
-- 在执行完中断唤醒引脚和功能引脚的配置之后，调用pm.power(pm.WORK_MODE, 1)设置最低功耗模式为低功耗模式（WORKMODE 1）；
-- 设置完之后并不会里面进入休眠，而是等所有业务逻辑处理完毕之后，才会进入休眠；
sys.publish("DRV_SET_LOWPOWER")


-- 启动tcp client长连接任务；
sys.taskInit(tcp_long_task)
