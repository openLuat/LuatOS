## 演示功能概述

本demo演示的核心功能为：

Air8000系列模组在常规模式、低功耗模式1、PSM+模式3下的功耗表现，通过下列九个项目示例代码进行介绍：

1、prj_0_tcp_long：常规模式下的tcp长连接项目（每5分钟发送一次数据到tcp server）

2、prj_3：PSM+模式3简单项目

3、prj_1：低功耗模式1简单项目

4、prj_0_1：常规模式0和低功耗模式1切换项目

5、prj_1_tcp_long：低功耗模式下的tcp长连接项目（每5分钟发送一次数据到tcp server）

6、prj_3_tcp_short：PSM+模式下的tcp短连接项目（每次开机，发送一次数据到tcp server，无论成功还是失败，然后进入PSM+模式，1小时后唤醒）

7、prj_1_mqtt_long：低功耗模式下的mqtt长连接项目（每5分钟发送一次数据到mqtt server）

8、prj_3_mqtt_short：PSM+模式下的mqtt短连接项目（每次开机，读取一次温湿度数据，然后发送到mqtt server，无论成功还是失败，然后进入PSM+模式，1小时后唤醒）

9、prj_1_uart_camera：低功耗模式+飞行模式下的上位机通过串口控制拍照以及照片回传项目（uart1 9600波特率接收上位机拍照指令，拍照后，通过115200波特率将照片回传给上位机）



简单说明：

1、Air8000系列模组目前包括Air8000A、Air8000AB、Air8000N、Air8000U、Air8000W、Air8000D、Air8000DB、Air8000T；

2、Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片，GPIO23作为WiFi芯片的使能引脚，默认状态下，GPIO23为高电平输出，在低功耗模式1下，WiFi芯片部分的功耗表现为42uA左右，PSM+模式3下，WiFi芯片部分的功耗表现为16uA左右；

在低功耗模式1示例代码中，并未对GPIO23进行配置，默认WiFi芯片是开启状态，以此演示低功耗模式1下的实际功耗表现；

在PSM+模式3示例代码中，默认关闭了WiFi芯片，以此演示PSM+模式3下的实际功耗表现；

3、Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor，GPIO24作为GNSS备电电源开关和GSensor电源开关，默认状态下，GPIO24为高电平，在低功耗模式1和PSM+模式3下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为783uA左右；

在低功耗模式1示例代码中，并未对GPIO24进行配置，默认状态下为高电平，以此演示低功耗模式1下的实际功耗表现；

在PSM+模式3示例代码中，默认配置GPIO24为输入下拉的方式来演示PSM+模式3的功耗表现；



目前存在的缺陷说明：

2026.01.22：目前在低功耗模式1时，4G内核固件存在缺陷，会有一个1秒1次的电流波动，最终导致实际功耗较高，属于已知问题，正在解决中...

2026.01.30：目前实测WiFi芯片在PSM+模式3下功耗表现为42uA左右，通过在底层关闭airlink之后可以达到理论功耗数值，暂时还在解决中...

## 模组及核心板/开发板资料

[Air8000系列模组及核心板/开发板资料](https://docs.openluat.com/air8000/product/shouce/)

## 演示硬件环境

1、Air8000系列核心板（可通过[上海合宙LuatOS官方企业店](https://luat.taobao.com/)采购）

2、Air8000系列开发板（可通过[上海合宙LuatOS官方企业店](https://luat.taobao.com/)采购，用于prj_1_uart_camera项目演示）

3、AirSHT30_1000温湿度传感器配件板（可通过[上海合宙LuatOS官方企业店](https://luat.taobao.com/)采购，用于prj_3_mqtt_short项目演示）

4、AirCAMERA _1040摄像头模组（可通过[上海合宙LuatOS官方企业店](https://luat.taobao.com/)采购，用于prj_1_uart_camera项目演示）

5、支持两个UART端口及以上的串口板

6、物联网卡（需要自行联系卡商）

7、Air9000P合宙功耗分析仪（可通过[上海合宙LuatOS官方企业店](https://luat.taobao.com/)采购，用于外部供电）



Air9000P与Air8000系列核心板接线说明：

- 将Air9000P的‘+’、‘-’极分别连接到核心板的VBAT、GND排针上，在测试低功耗模式1、PSM+模式3时需要使用外部供电才行；
- 将核心板USB旁边的拨码开关拨到OFF，断开USB供电；
- 电脑打开“功耗分析仪”软件（使用说明请看[Air9000P使用说明](https://hezhouyibiao.com/)），连接Air9000P；



Air9000P与Air8000系列开发板接线说明：

- 将Air9000P的‘+’、‘-’极分别连接到开发板的4V、GND排针上，在测试低功耗模式1、PSM+模式3时需要使用外部供电才行；
- 将开发板USB旁边的拨码开关拨到“外部供电”，断开USB供电；
- 电脑打开“功耗分析仪”软件（使用说明请看[Air9000P使用说明](https://hezhouyibiao.com/)），连接Air9000P；



AirSHT30_1000与Air8000系列核心板接线说明：

| Air8000系列核心板 | AirSHT30_1000温湿度传感器配件板 |
| ----------------- | ------------------------------- |
| VDD_EXT           | 3.3V                            |
| GND               | GND                             |
| I2C1_SDA          | SDA                             |
| I2C1_SCL          | SCL                             |



两个UART端口及以上的串口板与Air8000系列开发板接线说明：

1、使用两根usb转ttl串口线连接电脑和开发板，第一根线和开发板的uart1 tx相连（电脑上的串口工具配置为9600波特率），第二根线和开发板的uart1 rx相连（电脑上的串口工具配置为115200波特率）；

2、第一根线对应的电脑端串口工具下发A0001指令，就可以控制开发板拍照，拍照结束后，通过第二根线发给电脑端串口工具（每次接收到数据，可以单独保存为一个文件，修改文件名后缀为jpg，就能查看图片）

## 演示软件环境

1、烧录工具：LuaTools下载调试工具（可鼠标右键点击[此处](https://docs.openluat.com/air780epm/common/Luatools/)并左键打开此链接进行下载）；

2、内核固件：[Air8000系列最新版本内核固件](https://docs.openluat.com/air8000/luatos/firmware/)；

3、脚本文件：先占个位置，后续加上

4、lib脚本文件：使用Luatools烧录时，勾选 添加默认lib 选项，使用默认lib脚本文件

准备好软件环境之后，接下来根据[Air8000系列核心板使用手册](https://docs.openluat.com/air8000/product/file/Air8000%E7%B3%BB%E5%88%97%E6%A8%A1%E7%BB%84%E6%A0%B8%E5%BF%83%E6%9D%BF%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8EV2.2.pdf)和[Air8000系列开发板使用手册](https://docs.openluat.com/air8000/product/file/Air8000_V2.0%E5%BC%80%E5%8F%91%E6%9D%BF%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E_V1.0.3.pdf)中的烧录说明，将本篇文章中演示使用的项目文件烧录到Air8000系列核心板/开发板中。

## 演示操作步骤

1、搭建好演示硬件环境；

- prj_3、prj_1、prj_0_1、prj_0_tcp_long、prj_1_tcp_long、prj_3_tcp_short、prj_1_mqtt_long这七个功能演示只需要使用Air8000系列核心板+物联网卡+Air9000P合宙功耗分析仪即可；
- prj_3_mqtt_short这一个功能演示时还需要在前面的基础上连接AirSHT30_1000温湿度传感器配件板；
- prj_1_uart_camera这一个功能演示时核心板无法演示，需要使用Air8000系列开发板，开发板上还需要接AirCAMERA _1040摄像头模组和两个UART端口及以上的串口板才行；
- 在进行搭建硬件环境时请参考前面的“演示硬件环境”；

2、在 main.lua 代码文件中根据需要演示的项目功能，打开对应的代码；

- prj_3、prj_1、prj_0_1这三个功能演示时只需要打开对应的代码即可；
- prj_0_tcp_long、prj_1_tcp_long、prj_3_tcp_short这两个功能演示时需要在app_tcp_main.lua代码文件中填写需要连接的TCP服务器地址和端口号；
- prj_1_mqtt_long、prj_3_mqtt_short这三个功能演示时需要在app_mqtt_main.lua代码文件中填写需要连接的MQTT服务器地址和端口号，并且prj_3_mqtt_short功能演示时需要连接AirSHT30_1000温湿度传感器配件板，接线说明见前面的“演示硬件环境”章节；
- prj_1_uart_camera这一个功能演示时需要使用开发板，开发板上需要接AirCAMERA _1040摄像头模组和两个UART端口及以上的串口板，接线说明见前面的“演示硬件环境”章节；

3、使用LuaTools工具烧录内核固件和修改后的demo脚本代码；

4、烧录成功后，自动开机运行，并使用Air9000P合宙功耗分析仪观察功耗表现；

- prj_3、prj_1、prj_0_1、prj_0_tcp_long、prj_1_tcp_long、prj_3_tcp_short、prj_1_mqtt_long、prj_3_mqtt_short这八个功能演示时是全自动运行的，用户无法进行额外操作（除非是需要修改功能配置项），只需观察功耗表现即可；
- prj_1_uart_camera这一个功能演示还需要通过PC端串口工具与模组进行串口通信，详细说明见前面的“演示硬件环境”章节；
