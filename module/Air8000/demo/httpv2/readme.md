## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、http_app.lua：基于不同的应用场景，演示http核心库的使用方式；

4、httpplus_app.lua：基于不同的应用场景，演示httpplus扩展库的使用方式；



## 演示功能概述

1、http_app：使用http核心库，演示以下几种应用场景的使用方式

- 普通的http get请求功能演示；

- http get下载压缩数据的功能演示；

- http get下载数据保存到文件中的功能演示；

- http post提交表单数据功能演示；

- http post提交json数据功能演示；

- http post提交纯文本数据功能演示；

- http post提交xml数据功能演示；

- http post提交原始二进制数据功能演示；

- http post文件上传功能演示；

2、httpplus_app：使用httpplus扩展库，演示以下几种应用场景的使用方式

- 普通的http get请求功能演示；

- http get下载压缩数据的功能演示；

- http post提交表单数据功能演示；

- http post提交json数据功能演示；

- http post提交纯文本数据功能演示；

- http post提交xml数据功能演示；

- http post提交原始二进制数据功能演示；

- http post文件上传功能演示；

3、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_wifi：WIFI STA网卡

   (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级



## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根+网线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8000开发板和数据线的硬件接线方式为：

- Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接开发板的UART1_TX，绿线连接开发板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2011版本固件）](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，在日志中搜索success 200，每隔1分钟测试一轮，如果每轮出现22次success 200，如以下日志所示，就表示成功；详细日志所表示的含义，可以结合代码自行分析

``` lua
[2025-08-06 15:34:56.201][000000007.113] I/user.http_app_get1 success 200 {"Transfer-
[2025-08-06 15:34:56.354][000000007.271] I/user.httpplus_app_get1 success 200
[2025-08-06 15:34:56.622][000000007.537] I/user.httpplus_app_get2 success 200
[2025-08-06 15:34:57.896][000000008.796] I/user.httpplus_app_get_gzip success 200
[2025-08-06 15:34:58.287][000000009.070] I/user.http_app_get2 success 200 {"Vary":"Ac
[2025-08-06 15:34:58.369][000000009.112] I/user.httpplus_app_post_form success 200
[2025-08-06 15:34:58.592][000000009.248] I/user.http_app_get3 success 200 {"Connectio
[2025-08-06 15:34:58.765][000000009.412] I/user.httpplus_app_post_json success 200
[2025-08-06 15:34:59.043][000000009.951] I/user.http_app_get_gzip success 200 {"Conte
[2025-08-06 15:34:59.291][000000010.065] I/user.httpplus_app_post_text success 200
[2025-08-06 15:34:59.820][000000010.736] I/user.httpplus_app_post_xml success 200
[2025-08-06 15:34:59.903][000000010.744] I/user.http_app_get_file1 success 200 {"Tran
[2025-08-06 15:35:00.706][000000011.503] I/user.httpplus_app_post_binary success 200
[2025-08-06 15:35:01.008][000000011.862] I/user.http_app_get_file2 success 200 {"Vary
[2025-08-06 15:35:01.094][000000011.917] I/user.httpplus_app_post_file success 200
[2025-08-06 15:35:01.215][000000012.079] I/user.http_app_get_file3 success 200 {"Conn
[2025-08-06 15:35:01.356][000000012.270] I/user.http_app_post_form success 200 {"Conn
[2025-08-06 15:35:01.569][000000012.479] I/user.http_app_post_json success 200 {"Conn
[2025-08-06 15:35:01.769][000000012.681] I/user.http_app_post_text success 200 {"Conn
[2025-08-06 15:35:01.949][000000012.858] I/user.http_app_post_xml success 200 {"Conne
[2025-08-06 15:35:02.236][000000013.145] I/user.http_app_post_binary success 200 {"Da
[2025-08-06 15:35:02.437][000000013.348] I/user.post_multipart_form_data success 200 
```

