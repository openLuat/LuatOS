## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的三种网卡(单4g网卡，单spi以太网卡，多网卡)中的任何一种网卡；

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

3、netdrv_device：配置连接外网使用的网卡，目前支持以下三种选择（三选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (3) netdrv_multiple：支持以上两种网卡，可以配置两种网卡的优先级



## 演示硬件环境

![](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV.png)

1、Air780EXX核心板一块

2、TYPE-C USB数据线一根

3、USB转串口数据线一根

4、Air780EXX核心板和数据线的硬件接线方式为

- Air780EXX核心板通过TYPE-C USB口供电；

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者5V管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的18/U1TXD，绿线连接核心板的17/U1RXD，黑线连接核心板的gnd，另外一端连接电脑USB口；

5、可选AirETH_1000配件板一块，Air780EXX核心板和AirETH_1000配件板的硬件接线方式为:

| Air780EXX核心板 | AirETH_1000配件板 |
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| gnd             | gnd               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 107/GPIO21      | INT               |


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2012版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)、[Air780EHV V2012版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)、[Air780EGH V2012版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)（理论上，2025年7月26日之后发布的固件都可以）



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉
- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉
- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉

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

