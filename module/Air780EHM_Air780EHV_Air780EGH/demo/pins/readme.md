## 功能模块介绍：

1、main.lua：主程序入口。

2、my.json:   自定义管脚配置示例文件，用于演示 pins.loadjson(path)接口加载自定义管脚配置文件的功能，该文件手动编写容易出错，建议使用合宙LuatIO可视化工具 [LuatIO初始化配置工具 ](https://docs.openluat.com/air780epm/common/luatio/)自动生成。

3、pins_Air780EHM.json: Air780EHM核心板管脚配置示例文件，底层自动加载该文件完成管脚配置，使用合宙LuatIO可视化工具自动生成。

4、pins_Air780EHV.json: Air780EHV核心板管脚配置示例文件，底层自动加载该文件完成管脚配置，使用合宙LuatIO可视化工具自动生成。

5、pins_Air780EGH.json: Air780EGH核心板管脚配置示例文件，底层自动加载该文件完成管脚配置，使用合宙LuatIO可视化工具自动生成。

6、pins_default.lua：功能演示模块，在main.lua中加载运行。

7、pins_dynamic.lua：功能演示模块，在main.lua中加载运行。

## 演示功能概述：

**pins_default.lua:**

1.烧录管脚配置文件pins_Air780EHM.json配置管脚功能



2.烧录pins_Air780EHM.json前，

pin28默认功能是UART2_RXD

pin29默认功能是UART2_TXD

pin55默认功能是CAM_RX0

pin56默认功能是CAM_RX1



烧录了pins_Air780EHM.json后，在内核固件运行时，已经自动加载pins_Air780EHM.json，并且按照pins_Air780EHM.json的配置初始化所有io引脚功能，

文件中把pin28由原UART2_RXD功能配置为GPIO12，

pin29由原UART2_TXD功能配置为GPIO13，

pin55由原CAM_RX0功能配置为UART2_RXD，

pin56由原CAM_RX1功能配置为UART2_TXD，



3.演示重新配置的串口管脚的功能，通过串口工具收发数据。



**pins_dynamic.lua:**

1.加载自定义的管脚配置文件my.json配置管脚功能

文件中配置

pin28功能是UART2_RXD



pin29功能是UART2_TXD



pin55功能是CAM_RX0



pin56功能是CAM_RX1



2.通过pins.setup接口动态修改管脚复用功能，



这里演示把pin28由原UART2_RXD功能配置为GPIO12，



pin29由原UART2_TXD功能配置为GPIO13，



pin55由原CAM_RX0功能配置为UART2_RXD，



pin56由原CAM_RX1功能配置为UART2_TXD，



3.演示重新配置的串口管脚的功能，通过串口工具收发数据。



## 演示硬件环境

![netdrv_multi](https://docs.openluat.com/air780epm/image/780EHM.png)



1、Air780EHM/EHV/EGH核心板一块

2、TYPE-C USB数据线一根 ，Air780EHM/EHV/EGH核心板和数据线的硬件接线方式为：

* Air780EHM/EHV/EGH核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口。 

3、USB转TTL串口线一根，串口线usb口连接电脑USB口，Air780EHM/EHV/EGH核心板和串口线，按以下方式接线：

| Air780EHM/EHV/EGH核心板 | 串口线     |
| -------------------- | ------- |
| pin55/CAM_RX0        | uart_tx |
| pin56/CAM_RX1        | uart_rx |
| GND                  | GND     |



## 演示软件环境

1、 Luatools下载调试工具

2、 固件版本：LuatOS-SoC_V2016_Air780EHM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/Air780EHM/luatos/firmware/](https://docs.openluat.com/Air780EHM/luatos/firmware/)

LuatOS-SoC_V2016_Air780EHV_1，固件地址，如有最新固件请用最新 [[https://docs.openluat.com/air780ehv/luatos/firmware/version/](https://docs.openluat.com/air780ehv/luatos/firmware/version/)]

LuatOS-SoC_V2016_Air780EGH_1，固件地址，如有最新固件请用最新 [[https://docs.openluat.com/air780egh/luatos/firmware/version/](https://docs.openluat.com/air780egh/luatos/firmware/version/)]

3、 脚本文件：
    main.lua



   pins_default.lua

   pins_dynamic.lua



   my.json



   pins_Air780EHM.json（Air780EHM使用）

   pins_Air780EHV.json（Air780EHV使用）

   pins_Air780EGH.json（Air780EGH使用）

4、 pc 系统 win11（win10 及以上）

5、sscom串口工具



## 演示核心步骤

1、搭建好硬件环境

2、main.lua中，加载pins_default.lua或者pins_dynamic.lua

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印加载配置文件，配置管脚，以及配置完成后向串口发消息，通过SSCOM串口工具查看串口收到的消息，SSCOM也可以向模组发送消息进行交互。

如下log显示使用pins_dynamic功能模块：其中 I/user.uart receive日志是串口工具向模组发数据，模组收到数据触发打印，

图片中蓝框是SSCOM串口工具收到模组发来的消息，红框是模组收到SSCOM串口工具发来的消息。

```
[2025-11-10 10:47:00.089][000000000.233] D/pins /luadb/pins_Air780EHM.json 加载和配置完成
[2025-11-10 10:47:00.100][000000000.237] D/main loadlibs luavm 4194296 16096 16096
[2025-11-10 10:47:00.105][000000000.237] D/main loadlibs sys   3211688 104004 113640
[2025-11-10 10:47:00.110][000000000.237] D/main loadlibs psram 3211688 104112 113640
[2025-11-10 10:47:00.117][000000000.256] I/user.main Air780EHM/EHV/EGH_pins 001.000.000
[2025-11-10 10:47:00.124][000000000.269] I/user.加载自定义的配置文件 true 0
[2025-11-10 10:47:00.130][000000000.269] I/user.uart 重新配置uart2到新管脚
[2025-11-10 10:47:00.135][000000000.269] Uart_TxStop 1180:uart2,br 0
[2025-11-10 10:47:00.142][000000000.269] I/user.配置pin28脚即UART2_RXD为GPIO12 true
[2025-11-10 10:47:00.149][000000000.270] I/user.配置pin29脚即UART2_TXD为GPIO13 true
[2025-11-10 10:47:00.157][000000000.270] I/user.配置pin55脚即CAM_RX0为UART2_RXD true
[2025-11-10 10:47:00.162][000000000.270] I/user.配置pin56脚即CAM_RX1为UART2_TXD true
[2025-11-10 10:47:00.166][000000000.270] Uart_ChangeBR 1338:uart2, 115200 115203 26000000 3611
[2025-11-10 10:47:00.172][000000000.271] I/user.uart uart2重新配置完成
[2025-11-10 10:47:01.559][000000002.272] I/user.这是第0次向串口发数据
[2025-11-10 10:47:05.565][000000006.272] I/user.这是第1次向串口发数据
[2025-11-10 10:47:09.558][000000010.272] I/user.这是第2次向串口发数据
[2025-11-10 10:47:13.556][000000014.272] I/user.这是第3次向串口发数据
[2025-11-10 10:47:15.206][000000015.917] I/user.uart receive 2 11 123456789

[2025-11-10 10:47:15.214][000000015.918] I/user.uart receive(hex) 2 11 3132333435363738390D0A 22
[2025-11-10 10:47:16.336][000000017.042] I/user.uart receive 2 11 123456789

[2025-11-10 10:47:16.348][000000017.043] I/user.uart receive(hex) 2 11 3132333435363738390D0A 22
[2025-11-10 10:47:17.561][000000018.272] I/user.这是第4次向串口发数据
[2025-11-10 10:47:21.565][000000022.272] I/user.这是第5次向串口发数据
[2025-11-10 10:47:25.561][000000026.272] I/user.这是第6次向串口发数据
[2025-11-10 10:47:29.564][000000030.272] I/user.这是第7次向串口发数据
[2025-11-10 10:47:33.559][000000034.272] I/user.这是第8次向串口发数据
[2025-11-10 10:47:37.565][000000038.272] I/user.这是第9次向串口发数据



```

![](https://docs.openluat.com/air780epm/image/sscom.jpg)

如下log显示使用pins_default功能模块：其中 I/user.uart receive日志是串口工具向模组发数据，模组收到数据触发打印，

图片中蓝框是SSCOM串口工具收到模组发来的消息，红框是模组收到SSCOM串口工具发来的消息。

```
[2025-11-10 10:56:02.315][000000000.233] D/pins /luadb/pins_Air780EHM.json 加载和配置完成
[2025-11-10 10:56:02.321][000000000.236] D/main loadlibs luavm 4194296 16096 16096
[2025-11-10 10:56:02.328][000000000.236] D/main loadlibs sys   3211688 104004 113640
[2025-11-10 10:56:02.332][000000000.236] D/main loadlibs psram 3211688 104112 113640
[2025-11-10 10:56:02.339][000000000.256] I/user.main Air780EHM/EHV/EGH_pins 001.000.000
[2025-11-10 10:56:02.344][000000000.262] Uart_ChangeBR 1338:uart2, 115200 115203 26000000 3611
[2025-11-10 10:56:02.347][000000000.262] I/user.uart uart2配置完成
[2025-11-10 10:56:03.889][000000002.262] I/user.这是第0次向串口发数据
[2025-11-10 10:56:07.880][000000006.263] I/user.这是第1次向串口发数据
[2025-11-10 10:56:11.881][000000010.263] I/user.这是第2次向串口发数据
[2025-11-10 10:56:15.893][000000014.263] I/user.这是第3次向串口发数据
[2025-11-10 10:56:19.881][000000018.263] I/user.这是第4次向串口发数据
[2025-11-10 10:56:23.880][000000022.263] I/user.这是第5次向串口发数据
[2025-11-10 10:56:27.881][000000026.263] I/user.这是第6次向串口发数据
[2025-11-10 10:56:31.882][000000030.263] I/user.这是第7次向串口发数据
[2025-11-10 10:56:35.879][000000034.263] I/user.这是第8次向串口发数据
[2025-11-10 10:56:39.882][000000038.263] I/user.这是第9次向串口发数据
[2025-11-10 10:57:17.518][000000075.902] I/user.uart receive 2 11 123456789

[2025-11-10 10:57:17.528][000000075.902] I/user.uart receive(hex) 2 11 3132333435363738390D0A 22
[2025-11-10 10:57:18.404][000000076.781] I/user.uart receive 2 11 123456789

[2025-11-10 10:57:18.413][000000076.782] I/user.uart receive(hex) 2 11 3132333435363738390D0A 22

```

![](https://docs.openluat.com/air780epm/image/sscom1.jpg)
