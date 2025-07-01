
## 演示功能概述
本demo演示的核心功能为：
使用Air780EHM核心板通过UART1连接PC端的串口调试仿真工具SecureCRT，通过Ymodem协议接收文件。

## 演示硬件环境

1、Air780EHM核心板一块

2、TYPE-C USB数据线一根

3、USB转串口线数据线一根

4、Air780EHM核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的12/U1TX，绿线连接核心板的11/U1RX，黑线连接核心板的gnd，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM最新版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、PC端的串口仿真工具SecureCRT：[下载链接](https://www.vandyke.com/download/index.html)


## 演示核心步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、打开SecureCRT，连接上Air780EHM UATR1端口，等待窗口接收到Air780EHM发送的字符"C" 表示准备接收数据，选择.bin文件发送，等待传输完成，传输完成后，Luatools的运行日志输出：
``` lua
[2025-06-25 11:28:30.664][000000185.351] I/main.lua:41	1029
[2025-06-25 11:28:30.665][000000185.353] D/ymodem save.bin,1024,1
[2025-06-25 11:28:30.667][000000185.353] I/main.lua:44	true	6	67	false	false
[2025-06-25 11:28:30.668][000000185.354] I/main.lua:66	uart	sent	1
[2025-06-25 11:28:30.755][000000185.456] I/main.lua:41	1029
[2025-06-25 11:28:30.769][000000185.465] I/main.lua:44	true	6	nil	true	false
[2025-06-25 11:28:30.771][000000185.466] I/main.lua:66	uart	sent	1
[2025-06-25 11:28:30.800][000000185.491] I/main.lua:41	1
[2025-06-25 11:28:30.802][000000185.492] I/main.lua:44	true	21	nil	false	false
[2025-06-25 11:28:30.803][000000185.492] I/main.lua:66	uart	sent	1
[2025-06-25 11:28:30.832][000000185.522] I/main.lua:41	1
[2025-06-25 11:28:30.835][000000185.522] I/main.lua:44	true	6	67	false	false
[2025-06-25 11:28:30.836][000000185.523] I/main.lua:66	uart	sent	1
[2025-06-25 11:28:30.861][000000185.563] I/main.lua:41	133
[2025-06-25 11:28:30.866][000000185.563] I/main.lua:44	true	6	nil	false	true
[2025-06-25 11:28:30.867][000000185.566] I/main.lua:53	io	save.bin file exists:	true
[2025-06-25 11:28:30.868][000000185.568] I/main.lua:54	io	save.bin file size:	1024
```