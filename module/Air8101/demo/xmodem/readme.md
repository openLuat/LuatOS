
## 演示功能概述
本demo演示的核心功能为：
使用Air8101核心板的UART1连接PC端的串口工具，通过xmodem协议接收文件。

## 演示硬件环境

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、USB转串口线数据线一根

4、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的12/U1TX，绿线连接核心板的11/U1RX，黑线连接核心板的gnd，另外一端连接电脑USB口；

| Air8101核心板 | USB转串口数据线 |
| -------------- | -------------- |
| U1TX           | UART_RX        |
| U1RX           | UART_TX        |
| GND            | GND            |

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101最新版本固件](https://docs.openluat.com/air8101/luatos/firmware/)

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；


## 演示核心步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、打开串口工具，连接上Air8101 UATR1端口，Air8101等待接收到工具发送过来的字符'C'，然后8101开始发送数据，工具端接收到数据返回0x06，0x06为xmodem协议的ack值表示正确接收，然后模块返回0x04,0x04为xmodem协议的​EOT​值，表示传输结束，然后对端发送0x06表示确认结束，Luatools的运行日志输出：

发送脚本区的文件，日志内容如下：
``` lua
[2025-10-27 16:06:33.386] luat:U(11530):I/user.xmodem uart读取到数据: 43 2
[2025-10-27 16:06:33.386] luat:U(11531):I/user.xmodem 发送第 1 包
[2025-10-27 16:06:38.133] luat:U(16281):I/user.xmodem uart读取到数据: 06 2
[2025-10-27 16:06:38.149] luat:U(16282):I/user.xmodem 文件到头了
[2025-10-27 16:06:38.149] luat:U(16282):I/user.Xmodem start
[2025-10-27 16:06:38.149] luat:U(16282):I/user.Xmodem send result true
[2025-10-27 16:06:38.149] luat:U(16283):I/user.Xmodem send success


```

HTTP下载到文件系统区的，再通过xmodem协议发送日志如下：
``` lua
[2025-10-27 15:57:19.006] luat:U(6415):I/user.netdrv_wifi.ip_ready_func IP_READY {"gw":"192.168.2.1","rssi":-23,"bssid":"34CA81D40F19"}
[2025-10-27 15:57:19.006] luat:D(6417):DNS:airtest.openluat.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-10-27 15:57:19.006] luat:D(6417):net:adatper 2 dns server 192.168.2.1
[2025-10-27 15:57:19.006] luat:D(6417):net:dns udp sendto 192.168.2.1:53 from 192.168.2.20
[2025-10-27 15:57:19.006] luat:D(6419):wlan:event_module 2 event_id 0
[2025-10-27 15:57:19.006] luat:I(6429):DNS:dns all done ,now stop
[2025-10-27 15:57:19.006] luat:D(6429):net:connect 47.96.229.157:2900 TCP
[2025-10-27 15:57:19.087] luat:U(6530):I/user.http success 200
[2025-10-27 15:57:19.087] luat:U(6531):I/user.HTTP receive ok 29
[2025-10-27 15:57:19.087] luat:U(6532):I/user.文件读取 路径:/send.bin 内容:AA BB CC DD 01 02 03 04 05 06
[2025-10-27 15:57:23.387] luat:U(10839):I/user.xmodem uart读取到数据: 430D0A 6
[2025-10-27 15:57:23.387] luat:U(10840):I/user.xmodem 发送第 1 包
[2025-10-27 15:57:27.857] luat:U(15292):I/user.xmodem uart读取到数据: 06 2
[2025-10-27 15:57:27.857] luat:U(15293):I/user.xmodem 文件到头了
[2025-10-27 15:57:27.857] luat:U(15294):I/user.Xmodem start
[2025-10-27 15:57:27.857] luat:U(15294):I/user.Xmodem send result true
[2025-10-27 15:57:27.857] luat:U(15294):I/user.Xmodem send success



```