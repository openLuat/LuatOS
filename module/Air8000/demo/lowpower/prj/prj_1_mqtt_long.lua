--[[
@module  prj_1_mqtt_long
@summary 低功耗模式（WORKMODE 1）下的mqtt client长连接应用项目主功能模块
@version 1.0
@date    2026.02.09
@author  马梦阳
@usage
本文件为低功耗模式（WORKMODE 1）下的mqtt client长连接应用项目主功能模块，核心业务逻辑为：
1、初始化时配置最低功耗模式为低功耗模式（WORKMODE 1）
2、启动一个mqtt client长连接，连接mqtt broker；连接断开后，自动重连
3、mqtt client每隔一段时间发送数据到mqtt broker
4、mqtt client接收到mqtt broker下发的数据后，在日志中打印出来


Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片，GPIO23作为WiFi芯片的使能引脚，
默认状态下，GPIO23为高电平输出，在低功耗模式下,WiFi芯片部分的功耗表现为42uA左右，PSM+模式下，WiFi芯片部分的功耗表现为16uA左右，客户应根据实际项目需求进行配置
在低功耗模式示例代码中，并未对GPIO23进行配置，默认WiFi芯片是开启状态，以此演示低功耗模式下的实际功耗表现

Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor，GPIO24作为GNSS备电电源开关和GSensor电源开关
默认状态下，GPIO24为高电平，在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为88uA左右，客户应根据实际需求进行配置
在低功耗模式示例代码中，并未对GPIO24进行配置，默认状态下为高电平，以此演示低功耗模式下的实际功耗表现


2026.01.22：目前在低功耗模式时，4G内核固件存在缺陷，在低功耗模式下，会有一个1秒1次的电流波动，最终导致实际功耗较高，属于已知问题，正在解决中...


特别说明：
1、V2024 及之前的固件版本，4G芯片进入低功耗模式1后，WiFi芯片功耗表现较高，需要使用V2024以后的固件版本才能使得WiFi芯片达到42uA左右的功耗表现


使用Air8000系列每个模组的核心板，烧录运行此demo，在vbat供电3.8v状态下，在以下测试场景来介绍一下功耗情况：

1、插sim卡，上电开机之后，大约7秒后，成功进入低功耗状态；
   初始化阶段（常规模式），平均电流18mA；（此数据仅供参考，测试网络环境不同，持续时长以及平均电流都会不同，但是差异应该不是特别大才对）
   低功耗阶段（因为有网络寻呼和mqtt交互，所以是低功耗模式+常规模式自动切换），平均电流1.8mA左右（1.0mA到2.0mA左右都属于正常值，和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准，但是差异应该不是特别大才对）

   2026.02.10：目前实际测试，在低功耗阶段，电流数据在1.8mA左右，待目前已知问题解决后，再进行一次测试


本文件和其他功能模块的通信接口只有1个：
1、sys.publish("DRV_SET_LOWPOWER")：发布消息"DRV_SET_LOWPOWER"，通知drv_lowpower驱动模块配置最低功耗模式为低功耗模式
]]


require "drv_lowpower"
require "app_mqtt_main"


-- 数据发送结果回调函数；
local function send_data_cbfunc(result)
    sys.publish("SEND_DATA_RSP", result)
end


-- mqtt client长连接任务函数；
local function mqtt_long_task()
    -- 发布消息“MQTT_CLIENT_RUN_REQ”，通知mqtt client主功能应用模块（例如app_mqtt_main.lua）；
    -- 第二个参数用于设置连接的类型，“true”表示长连接，连接断开后会自动重连，“false”表示短连接，连接断开后不会自动重连；
    -- mqtt client主功能应用模块接收到“MQTT_CLIENT_RUN_REQ”消息后，根据第二个参数判断开始运行mqtt client长链接任务还是短连接任务；
    sys.publish("MQTT_CLIENT_RUN_REQ", true)


    local count = 0 -- 发送数据的次数
    local _, result -- 用于接收数据发送结果


    -- 发布消息“SEND_DATA_REQ”，通知mqtt client数据发送应用功能模块（例如app_mqtt_sender.lua）将数据发到服务器；
    while true do
        -- 用于在发送的数据内容中体现发送的次数
        count = count + 1

        -- 发布消息“SEND_DATA_REQ”，通知mqtt client数据发送应用功能模块（例如app_mqtt_sender.lua）将数据发到服务器；
        -- 发送的数据内容大致为”send from mqtt_long_task: heart_1“、”send from mqtt_long_task: heart_2“等；
        -- 数据发送结果会通过回调函数send_data_cbfunc返回；
        sys.publish("SEND_DATA_REQ", "mqtt_long_task", mobile.imei().."/up", "heart_"..count, 0, {func = send_data_cbfunc})

        -- 等待数据发送结果
        _, result = sys.waitUntil("SEND_DATA_RSP")
        log.info("mqtt_long_task", "send data rsp", result)

        -- 延时5分钟之后，再次循环
        sys.wait(5*60*1000)
    end
end


-- 发布消息“DRV_SET_LOWPOWER”，通知drv_lowpower驱动模块配置最低功耗模式为低功耗模式；
-- drv_lowpower驱动模块内部已有中断唤醒引脚和功能引脚的配置说明，根据实际项目需求打开或关闭对应配置代码即可；
-- 在执行完中断唤醒引脚和功能引脚的配置之后，调用pm.power(pm.WORK_MODE, 1)设置最低功耗模式为低功耗模式（WORKMODE 1）；
-- 设置完之后并不会里面进入休眠，而是等所有业务逻辑处理完毕之后，才会进入休眠；
sys.publish("DRV_SET_LOWPOWER")


-- 启动mqtt client长连接任务；
sys.taskInit(mqtt_long_task)
