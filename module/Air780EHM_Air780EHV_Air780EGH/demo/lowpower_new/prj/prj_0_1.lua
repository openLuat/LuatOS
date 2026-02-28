--[[
@module  prj_0_1
@summary 常规模式（WORKMODE 0）和低功耗模式（WORKMODE 1）切换，应用项目主调度功能模块
@version 1.0
@date    2026.02.12
@author  马梦阳
@usage
本文件为常规模式（WORKMODE 0）和低功耗模式（WORKMODE 1）切换，应用项目主调度功能模块，核心业务逻辑为：
1、自动的在常规模式（WORKMODE 0）和低功耗模式（WORKMODE 1）之间切换，演示GPIO以及AGPIO输出电平的特性
2、显式的在常规模式（WORKMODE 0）和低功耗模式（WORKMODE 1）之间切换，演示GPIO以及AGPIO输出电平的特性


Air780EGP/EGG模组内部包含有GNSS和Gsensor，Air780EGH模组内部只包含有GNSS，不包含Gsensor；
GPIO23作为GNSS备电电源开关和Gsensor电源开关，默认状态下为高电平；
在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为200uA左右，客户应根据实际需求进行配置；
在常规模式和低功耗模式示例代码中，并未对GPIO23进行额外配置，默认状态下为高电平，以此演示常规模式和低功耗模式下的实际功耗表现；


使用Air780EXX系列每个模组的核心板，烧录运行此demo，在vbat供电3.8v状态下，分为以下两种独立的场景来介绍一下功耗情况：

1、插sim卡，上电开机之后，大约21秒后（包含20秒延时），成功进入低功耗状态；
   初始化阶段（常规模式，持续20秒），平均电流51mA；（此数据仅供参考，测试网络环境不同，持续时长以及平均电流都会不同，但是差异应该不是特别大才对）
   低功耗阶段（因为有网络寻呼，所以是低功耗模式+常规模式自动切换，持续40秒），平均电流2.6mA左右（1.7mA到2.7mA左右都属于正常值，和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准，但是差异应该不是特别大才对）
   第二次常规模式（持续20秒），平均电流31mA；（此数据仅供参考，测试网络环境不同，持续时长以及平均电流都会不同，但是差异应该不是特别大才对）
   第二次低功耗阶段（因为有网络寻呼，所以是低功耗模式+常规模式自动切换），平均电流2.2mA左右（1.7mA到2.3mA左右都属于正常值，和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准，但是差异应该不是特别大才对）

2、不插sim卡，上电开机之后，大约21秒后（包含20秒延时），成功进入低功耗状态；
   初始化阶段（常规模式，持续20秒），平均电流28mA；（此数据仅供参考，测试网络环境不同，持续时长以及平均电流都会不同，但是差异应该不是特别大才对）
   低功耗阶段（因为有网络寻呼，所以是低功耗模式+常规模式自动切换，持续40秒），平均电流133uA左右（110uA到150uA左右都属于正常值）
   第二次常规模式（持续20秒），平均电流29mA；（此数据仅供参考，测试网络环境不同，持续时长以及平均电流都会不同，但是差异应该不是特别大才对）
   第二次低功耗阶段（因为有网络寻呼，所以是低功耗模式+常规模式自动切换），平均电流35uA左右（30uA到60uA左右都属于正常值）


本文件和其他功能模块的通信接口有以下2个：
1、sys.publish("DRV_SET_LOWPOWER")：发布消息"DRV_SET_LOWPOWER"，通知drv_lowpower驱动模块配置最低功耗模式为低功耗模式
2、sys.publish("DRV_SET_NORMAL")：发布消息"DRV_SET_NORMAL"，通知drv_normal驱动模块配置最低功耗模式为常规模式
]]


require "drv_lowpower"
require "drv_normal"


-- GPIO1为普通GPIO；
-- 在常规模式下，可以正常工作
-- 在低功耗模式下掉电，无法正常工作
-- 此引脚对应Air780EXX系列每个模组的核心板上的丝印为22/GPIO1
local GPIO_ID = 1

-- GPIO24为AGPIO；
-- 在常规模式下可以做为输出，输入或者终端，正常使用
-- 在低功耗模式下仅可以保持电平输出
-- 此引脚对应Air780EXX系列每个模组的核心板上的丝印为20/GPIO24
local AGPIO_ID = 24

-- 常规模式（WORKMODE 0）和低功耗模式（WORKMODE 1）切换任务
-- 通过演示一个普通GPIO和一个AGPIO的输出电平状态
-- 来简单理解常规模式（WORKMODE 0）和低功耗模式（WORKMODE 1）的两种功耗模式特性以及自动切换和显式切换的区别
local function normal_lowpower_switch_task()
    log.info("normal_lowpower_switch_task enter")

    local i
    -- 此处循环20秒，每1秒翻转1次GPIO_ID和AGPIO_ID的输出电平
    -- 因为没有主动设置过功耗模式，所以这20秒内一定是工作在常规模式，GPIO和AGPIO可以正常输出高低电平
    for i=1,20 do
        gpio.setup(GPIO_ID, i%2)
        gpio.setup(AGPIO_ID, i%2)
        sys.wait(1000)
    end

    -- 显式配置最低功耗模式为低功耗模式
    -- 执行此行代码后，会通过异步消息"DRV_SET_LOWPOWER"通知drv_lowpower功能模块配置低功耗模式
    -- 所以执行此行代码后，并不会马上进入低功耗模式
    -- 而是等待sys.run()在分发处理到"DRV_SET_LOWPOWER"消息时，drv_lowpower功能模块才去配置低功耗模式
    -- 即使运行到了drv_lowpower功能模块，也不一定马上进入低功耗模式，只有配置过低功耗模式，并且当前内核固件和脚本没有task处于运行状态，才能进入真正进入低功耗
    sys.publish("DRV_SET_LOWPOWER")
    -- 执行此代码时，处于常规模式
    log.info("normal_lowpower_switch_task after publish DRV_SET_LOWPOWER")





    -- 执行此代码时，处于常规模式
    log.info("normal_lowpower_switch_task auto switch during gpio business")

    -- 此处循环20秒，每1秒翻转1次GPIO_ID输出电平
    -- 第一次循环：
    --    执行gpio.setup(GPIO_ID, i%2)时，因为此task处于运行状态，所以系统仍然处于常规模式，所以这个时刻可以正常输出高电平
    --    但是在执行sys.wait(1000)时，此task会处于阻塞状态，此时如果不考虑系统中其他运行的任务影响，系统就会立即自动进入到低功耗模式
    --    虽然刚才设置了GPIO_ID输出高电平，但是此时处于低功耗模式下，此GPIO_ID掉电，所以输出的高电平立刻消失
    --    如果使用示波器来抓波形的话，会看到一个时间非常短的高脉冲（可能是微秒级、毫秒级的时长），并不会像代码设计的一样持续1秒钟
    -- 第二次循环：
    --    执行gpio.setup(GPIO_ID, i%2)时，因为此任务切换为运行状态，所以低功耗模式自动切换为常规模式，所以这个时刻可以正常输出低电平
    --    但是在执行sys.wait(1000)时，此task会处于阻塞状态，此时如果不考虑系统中其他运行的任务影响，系统就会立即自动进入到低功耗模式
    --    虽然刚才设置了GPIO_ID输出低电平，但是此时处于低功耗模式下，此GPIO_ID掉电，所以仍然是低电平，因为本来就是输出低电平，所以看不出来异常
    -- 接下来的循环过程、功耗模式的自动切换逻辑、电平逻辑和第一次循环以及第二次循环的过程完全一致，系统不断的在低功耗模式和常规模式自动切换，呈现出一个低功耗模式持续时间长、常规模式持续时间短的特点
    for i=1,20 do
        gpio.setup(GPIO_ID, i%2)
        sys.wait(1000)
    end





    -- 执行此代码时，处于常规模式（因为此task处于运行状态，会将系统自动切换为常规模式）
    log.info("normal_lowpower_switch_task auto switch during agpio business")

    -- 此处循环20秒，每1秒翻转1次AGPIO_ID输出电平
    -- 和普通的GPIO相比，AGPIO的特点是，在低功耗模式下供电正常，可以保持电平输出
    -- 虽然此处循环20次，系统也会在常规模式和低功耗模式之间自动切换，但是无论哪一种模式，此AGPIO_ID都能正常工作
    -- 所以在此处，AGPIO_ID输出电平的逻辑和持续时长完全正确，1秒输出高电平，1秒输出低电平
    for i=1,20 do
        gpio.setup(AGPIO_ID, i%2)
        sys.wait(1000)
    end




    -- 显式配置最低功耗模式为常规模式
    -- 执行此代码时，处于常规模式（因为此task处于运行状态，会将系统自动切换为常规模式）
    -- 执行此行代码后，会通过异步消息"DRV_SET_NORMAL"通知drv_normal功能模块配置常规模式
    -- 等待sys.run()在分发处理到"DRV_SET_NORMAL"消息时，drv_normal功能模块才去配置常规模式
    sys.publish("DRV_SET_NORMAL")

     -- 执行此代码时，处于常规模式（因为此task处于运行状态，会将系统自动切换为常规模式）
     log.info("normal_lowpower_switch_task auto switch during gpio business")

    -- 此处循环20秒，每1秒翻转1次GPIO_ID输出电平
    -- 第一次循环：
    --    执行gpio.setup(GPIO_ID, i%2)时，因为此task处于运行状态，所以系统仍然处于常规模式，所以这个时刻可以正常输出高电平
    --    在执行sys.wait(1000)时，此task会处于阻塞状态，但是此时系统并不会自动进入低功耗模式，因为刚才的"DRV_SET_NORMAL"消息还在sys.run()中等待处理
    --    所以说，虽然此时，本task处于阻塞状态，但是sys.run()中还在运行处理其他消息，具体到本demo，就是在drv_normal中处理"DRV_SET_NORMAL"消息，显式的配置最低功耗模式为常规模式
    --    经过显式配置之后，系统就会一直处于常规模式；所以此处的sys.wait(1000)期间，就会进入到显式常规模式中，就可以一直持续1秒钟输出高电平
    -- 第二次循环：
    --    此时已经显式的处于常规模式，所以工作完全正常
    -- 接下来的循环过程中都处于显式的常规模式中，所以工作完全正常
    for i=1,20 do
        gpio.setup(GPIO_ID, i%2)
        sys.wait(1000)
    end





    -- 显式配置最低功耗模式为低功耗模式
    -- 执行此行代码后，会通过异步消息"DRV_SET_LOWPOWER"通知drv_lowpower功能模块配置低功耗模式
    -- 所以执行此行代码后，并不会马上进入低功耗模式
    -- 而是等待sys.run()在分发处理到"DRV_SET_LOWPOWER"消息时，drv_lowpower功能模块才去配置低功耗模式
    -- 即使运行到了drv_lowpower功能模块，也不一定马上进入低功耗模式，只有配置过低功耗模式，并且当前内核固件和脚本没有task处于运行状态，才能进入真正进入低功耗
    sys.publish("DRV_SET_LOWPOWER")
    -- 执行此代码时，处于常规模式
    log.info("normal_lowpower_switch_task exit after publish DRV_SET_LOWPOWER")
end

sys.taskInit(normal_lowpower_switch_task)