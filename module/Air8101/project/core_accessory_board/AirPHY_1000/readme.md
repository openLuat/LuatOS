
## 演示功能概述

AirPHY_1000是合宙设计生产的一款搭载LAN8720Ai芯片的以太网配件板；

本demo演示的核心功能为：

Air8101核心板+AirPHY_1000配件板，使用配件板上的以太网口通过网线连接路由器，演示以太网数传功能；


## 核心板+配件板资料

[Air8101核心板+配件板相关资料](https://docs.openluat.com/air8101/product/shouce/#air8101_1)


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirPHY_1000/hw_connection.jpg)

![](https://docs.openluat.com/air8101/product/file/AirPHY_1000/hw_connection1.jpg)

1、Air8101核心板

2、AirPHY_1000配件板

3、公对母的杜邦线11根（连接核心板和配件板）

4、网线1根（一端接配件板，一端接路由器）

5、Air8101核心板和AirPHY_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

| Air8101核心板 | AirPHY_1000配件板  |
| ------------ | ------------------ |
|    59/3V3    |         3.3v       |
|     gnd      |         gnd        |
|     5/D2     |         RX1        |
|    72/D1     |         RX0        |
|    71/D3     |         CRS        |
|     4/D0     |         MDIO       |
|     6/D4     |         TX0        |
|    74/PCK    |         MDC        |
|    70/D5     |         TX1        |
|     7/D6     |         TXEN       |
|     不接     |          NC        |
|    69/D7     |         CLK        |


## 演示软件环境

1、Luatools下载调试工具

2、[最新版本的内核固件](https://docs.openluat.com/air8101/luatos/firmware/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) 配件板上网口水晶头位置处的橙色灯常亮，表示配件板和路由器的连接正常；

   (2) 配件板上网口水晶头位置处的绿色灯常亮或者闪烁，表示配件板和核心板的供电连接正常；

   (3) 观察Luatools的运行日志，如果出现类似于下面的日志，表示软件功能正常：

```lua
user.http	200	table: 608FD678	{
   "args": {}, 
   "headers": {
      "Accept-Encoding": "gzip", 
      "Host": "httpbin.air32.cn:80", 
      "X-Forwarded-Host": "httpbin.air32.cn:80", 
      "X-Forwarded-Server": "c4a1487bcf14"
   }, 
   "origin": "10.0.0.24", 
   "url": "http://httpbin.air32.cn:80/get"
}
```

