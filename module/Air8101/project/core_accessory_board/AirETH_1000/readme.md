
## 演示功能概述

AirETH_1000是合宙设计生产的一款搭载CH390H芯片的以太网配件板；

本demo演示的核心功能为：

Air8101核心板+AirETH_1000配件板，使用配件板上的以太网口通过网线连接路由器，演示以太网数传功能；


## 核心板+配件板资料

[Air8101核心板+配件板相关资料](https://docs.openluat.com/air8101/product/shouce/#air8101_1)


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirETH_1000/hw_connection.jpg)

![](https://docs.openluat.com/air8101/product/file/AirETH_1000/hw_connection1.jpg)

1、Air8101核心板

2、AirETH_1000配件板

3、母对母的杜邦线7根（连接核心板和配件板）

4、网线1根（一端接配件板，一端接路由器）

5、Air8101核心板和AirETH_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

| Air8101核心板   | AirETH_1000配件板 |
| ------------ | ------------------ |
| 59/3V3          | 3.3v              |
| gnd             | gnd               |
| 28/DCLK | SCK               |
| 54/DISP | CSS               |
| 55/HSYN | SDO               |
| 57/DE | SDI               |
| 14/GPIO8        | INT               |


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

