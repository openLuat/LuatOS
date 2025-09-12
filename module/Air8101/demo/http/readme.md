## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的五种网卡(单wifi网卡，单rmii以太网卡，单spi以太网卡，单4g网卡，多网卡)中的任何一种网卡；

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

3、netdrv_device：配置连接外网使用的网卡，目前支持以下五种选择（五选一）

   (1) netdrv_4g：通过SPI外挂4G模组的4G网卡

   (2) netdrv_wifi：WIFI STA网卡

   (3) netdrv_eth_rmii：通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡

   (4) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (5) netdrv_multiple：支持以上(2)、(3)、(4)三种网卡，可以配置三种网卡的优先级



## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/image/netdrv_multi.jpg)

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、USB转串口数据线一根

4、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的12/U1TX，绿线连接核心板的11/U1RX，黑线连接核心板的gnd，另外一端连接电脑USB口；

5、可选AirPHY_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

| Air8101核心板 | AirPHY_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 5/D2          | RX1               |
| 72/D1         | RX0               |
| 71/D3         | CRS               |
| 4/D0          | MDIO              |
| 6/D4          | TX0               |
| 74/PCK        | MDC               |
| 70/D5         | TX1               |
| 7/D6          | TXEN              |
| 不接          | NC                |
| 69/D7         | CLK               |

6、可选AirETH_1000配件板一块，Air8101核心板和AirETH_1000配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 28/DCLK       | SCK               |
| 54/DISP       | CSS               |
| 55/HSYN       | SDO               |
| 57/DE         | SDI               |
| 14/GPIO8      | INT               |

7、可选Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板或者开发板一块，Air8101核心板和Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板或者开发板的硬件接线方式为:

| Air8101核心板 | Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板 |
| ------------- | --------------------------------------------- |
| gnd           | GND                                           |
| 54/DISP       | 83/SPI0CS                                     |
| 55/HSYN       | 84/SPI0MISO                                   |
| 57/DE         | 85/SPI0MOSI                                   |
| 28/DCLK       | 86/SPI0CLK                                    |
| 43/R2         | 19/GPIO22                                     |
| 75/GPIO28     | 22/GPIO1                                      |


| Air8101核心板 | Air780EHM/Air780EHV/Air780EGH/Air780EPM开发板 |
| ------------- | --------------------------------------------- |
| gnd           | GND                                           |
| 54/DISP       | SPI_CS                                        |
| 55/HSYN       | SPI_MISO                                      |
| 57/DE         | SPI_MOSI                                      |
| 28/DCLK       | SPI_CLK                                       |
| 43/R2         | GPIO22                                        |
| 75/GPIO28     | GPIO1                                         |




## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1005版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要RMII以太网卡，打开require "netdrv_eth_rmii"，其余注释掉

- 如果需要SPI以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

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

