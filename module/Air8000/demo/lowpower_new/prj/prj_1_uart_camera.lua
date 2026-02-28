--[[
@module  prj_1_uart_camera
@summary 低功耗模式（WORKMODE 1）下的uart camera应用项目主功能模块
@version 1.0
@date    2026.02.09
@author  马梦阳
@usage
本文件为低功耗模式（WORKMODE 1）下的uart camera应用项目主功能模块，核心业务逻辑为：
1、引用drv_lowpower驱动模块，用于配置最低功耗模式为低功耗模式（WORKMODE 1）；
2、引用app_lpuart驱动模块，用于初始化uart，以及接收拍照指令和将拍照数据通过uart发送出去；
3、引用app_camera驱动模块，用于初始化camera，以及控制camera拍照；


Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片，GPIO23作为WiFi芯片的使能引脚，
默认状态下，GPIO23为高电平输出，在低功耗模式下,WiFi芯片部分的功耗表现为42uA左右，PSM+模式下，WiFi芯片部分的功耗表现为16uA左右，客户应根据实际项目需求进行配置
在低功耗模式示例代码中，并未对GPIO23进行配置，默认WiFi芯片是开启状态，以此演示低功耗模式下的实际功耗表现

Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor，GPIO24作为GNSS备电电源开关和GSensor电源开关
默认状态下，GPIO24为高电平，在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为88uA左右，客户应根据实际需求进行配置
在低功耗模式示例代码中，并未对GPIO24进行配置，默认状态下为高电平，以此演示低功耗模式下的实际功耗表现


使用Air8000系列每个模组的整机开发板，不插sim卡，烧录运行此demo，在vbat供电3.8V状态下，进行拍照+通过uart将图像数据发送出去，测试功耗数据为3.9mA左右


本文件和其他功能模块的通信接口只有1个：
1、sys.publish("DRV_SET_LOWPOWER")：发布消息"DRV_SET_LOWPOWER"，通知drv_lowpower驱动模块配置最低功耗模式为低功耗模式
]]

require "drv_lowpower"
require "app_lpuart"
require "app_camera"


-- 硬件连接与操作说明：
-- 1、演示代码使用的是Air8000A整机开发板进行测试，需要搭配一个gc032a的摄像头和两个串口板；
-- 2、测试时，使用两根usb转ttl串口线连接电脑和开发板，第一根线和开发板的uart1 tx相连（电脑上的串口工具配置为9600波特率），第二根线和开发板的uart1 rx相连（电脑上的串口工具配置为115200波特率）；
-- 3、第一根线对应的电脑端串口工具下发A0001指令，就可以控制开发板拍照，拍照结束后，通过第二根线发给电脑端串口工具（每次接收到数据，可以单独保存为一个文件，修改文件名后缀为jpg，就能查看图片）


-- 设置SIM0进入飞行模式
-- 可以在此处配置，也可以在drv_lowpower.lua中设置（详情请查看drv_lowpower.lua中的代码注释说明）
mobile.flymode(0, true)


-- 发布消息“DRV_SET_LOWPOWER”，通知drv_lowpower驱动模块配置最低功耗模式为低功耗模式；
-- drv_lowpower驱动模块内部已有中断唤醒引脚和功能引脚的配置说明，根据实际项目需求打开或关闭对应配置代码即可；
-- 在执行完中断唤醒引脚和功能引脚的配置之后，调用pm.power(pm.WORK_MODE, 1)设置最低功耗模式为低功耗模式（WORKMODE 1）；‘
-- 设置完之后并不会里面进入休眠，而是等所有业务逻辑处理完毕之后，才会进入休眠；
sys.publish("DRV_SET_LOWPOWER")
