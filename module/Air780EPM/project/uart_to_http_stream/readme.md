## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单spi以太网卡，多网卡，PC模拟网卡)中的任何一种网卡；

3、uart_app.lua：UART串口通信模块，负责与PC端串口交互获取文件数据；

4、http_upload_stream.lua：HTTP流式上传模块，使用httpplus扩展库的fill_data_func功能，将UART接收的数据流式上传到服务器；



## 演示功能概述

1、uart_app：通过UART1串口与PC端通信，支持以下两种请求

- 请求文件大小：模组发送"getSize\r\n"，PC端返回文件大小（数字字符串）
- 请求文件数据：模组发送"getData,{index}\r\n"，PC端返回从index位置开始的文件数据（二进制）

2、http_upload_stream：使用httpplus扩展库的fill_data_func流式上传功能

- 向uart_app请求文件大小（GET_FILE_SIZE_REQ/RESP消息对）
- 向uart_app分片请求文件数据（GET_FILE_DATA_REQ/RESP消息对）
- 通过fill_data_func将数据流式上传到https://airtest.luatos.com/iot/luat_test_file/add
- http测试服务器要求文件name使用"f"，文本name使用"params"；
- 如果使用的是你自己的服务器，根据实际情况修改服务器地址、端口、文件name、文本name等参数

3、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (3) netdrv_multiple：支持以上两种网卡，可以配置两种网卡的优先级

   (4) netdrv_pc：PC模拟网卡（用于开发调试）



## 模块间消息交互

```
  uart_app                              http_upload_stream
     |                                        |
     |<--------- GET_FILE_SIZE_REQ ----------|  (请求文件大小)
     |---------- GET_FILE_SIZE_RESP -------->|  (返回文件大小)
     |                                        |
     |<--------- GET_FILE_DATA_REQ(index) ---|  (请求第index片数据，由fill_data_func触发)
     |---------- GET_FILE_DATA_RESP -------->|  (返回zbuff或者string数据)
```



## 演示硬件环境

1、Air780EPM开发板一块+可上网的sim卡一张+4g天线一根：

- sim卡插入开发板的sim卡槽
- 天线装到开发板上

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air780EPM开发板和数据线的硬件接线方式为：

- Air780EPM开发板通过TYPE-C USB口供电
- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口
- USB转串口数据线：白线连接开发板的UART1_TX，绿线连接开发板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口



## 演示软件环境

1、Luatools下载调试工具

2、PC端串口工具（如SSCOM、XCOM等），用于模拟文件数据源

3、[Air780EPM最新版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉
- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉
- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉
- 如果在PC上调试，打开require "netdrv_pc"，其余注释掉

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行

5、PC端串口工具配置：波特率115200，数据位8，停止位1，无校验

6、PC端串口工具按照以下协议应答模组的请求：

- 收到getSize\r\n时，返回文件总字节数（纯数字字符串），例如163840
- 收到getData,{index}\r\n时，返回从index位置开始的文件二进制数据，每个数据包大小，由项目运行过程中的可用内存来定，本demo在uart_app.lua中单包处理的大小为16384字节，如果最后一包长度不足16384字节，返回最后一包实际长度的数据即可
- 例如：getData,1\r\n，表示返回开头位置开始的16384长度字节数据；getData,116385\r\n，表示返回第116385字节开始的16384长度字节数据；

7、上传成功后，在浏览器中打开https://iot.luatos.com/#/p8000/netlab_file_server，即可查看上传的文件
