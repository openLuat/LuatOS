## 功能模块介绍

### 自建服务器fota功能演示

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、update.lua：使用自建服务器进行远程升级功能模块，简单升级演示；

4、tcp_self_server文件夹：通过tcp服务器下发升级指令（指令格式使用json字符串，包含是否升级参数），控制设备启动customer_srv_fota功能模块，使用自建服务器进行升级；

5、customer_srv_fota.lua：自建服务器升级功能模块；


## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；



## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：socket client收到服务器下发的数据后，通过此消息发布出去，给其他应用模块处理；

2、"SEND_DATA_REQ"：其他应用模块发布此消息，通知socket client发送数据给服务器；



## 演示功能概述

1、combination文件夹下的demo会有三个演示场景，在main.lua中选择要使用的场景：

    (1) 使用自建服务器升级，演示最简单的升级逻辑。
    
    (2) 使用自建服务器升级，通过tcp下发升级指令控制设备升级，指令格式使用json字符串，包含版本、url、是否升级参数，演示如何通过服务器控制下发指令去升级。
    
    (3) 休眠状态下升级，此场景是针对psm状态下升级没完成就进入休眠导致升级失败的情况写的一个例子。

2、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_wifi：WIFI STA网卡

   (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级


## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

本demo默认联网方式用的是SPI_以太网接口，以太网功能开关设置说明

- `V_LAN` 电源开关：拨至 `ON`，为以太网 PHY 芯片供电。
- `U5`（SPI/ETH 通道拨码开关）：所有通道拨向左侧"ON"，打开以太网，以太网使用 `CS1 (GPIO14)` 作为片选。
- `S15`（WAKEUP/LAN_INT 中断开关）：
  - 单独使用以太网时：拨至 `ON`，连接 `WAKEUP` 信号到 `LAN_INT`，启用以太网中断功能。
  - 与触摸（TP）同时使用时：拨至 `OFF`，断开以太网中断，将 `WAKEUP` 信号留给 TP 使用。

![](https://docs.openluat.com/air1601/luatos/app/common/rtc/image/spi_lan.png)

使用其它网络接线方式请参考：[Air1601开发板使用说明](https://docs.openluat.com/air1601/product/shouce/#air1601_2)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、网线一根，网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

4、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## 演示软件环境

1、Luatools下载调试工具

2、固件版本：本demo开发测试时使用的固件为[LuatOS-SoC_V1016_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/p8000/netlab)；
详细使用说明参考：[合宙 TCP/UDP web 测试工具使用说明](https://docs.openluat.com/common/TCPUDP_Test/) 。

## 演示核心步骤

1、搭建好硬件环境

2、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/p8000/netlab)，点击 打开TCP 按钮，会创建一个TCP server，将server的地址和端口赋值给tcp_client_self_main.lua中的SERVER_ADDR和SERVER_PORT两个变量
详细使用说明参考：[合宙 TCP/UDP web 测试工具使用说明](https://docs.openluat.com/common/TCPUDP_Test/) 。
3、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的exnetif.set_priority_order函数里面的ssid和password，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的exnetif.set_priority_order函数里面的ssid和password，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

4、Luatools烧录内核固件和修改后的demo脚本代码

5、使用Luatools制作升级包，先把新旧版本分别生成量产文件，然后再制作升级包，工具上栏 luatOS->固件工具->差分包/整包升级包制作，将制作好的升级包配置到合宙iot服务器自己项目下，或上传到自建服务器上面；

6、烧录成功后，自动开机运行

7、[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/p8000/netlab)上创建的两个TCP server可以看到有设备连接上来，然后可以下发下面字符串触发升级：


``` lua

--自建服务器下发这个指令，下发之前需要在服务器上面配置好升级包，然后吧url给到字符串
--定义一个json格式如下，具体可以根据实际情况定义：
-- {"fota": "true","url": "http://airtest.openluat.com:2900/download/FOTA2_DEMO_1016.001.001_LuatOS-SoC_Air1601.bin"}

```

8、可以看到升级过程如下，不管是什么场景下升级，基本都是如下情况：

``` lua
--没有升级之前可以看到如下打印
I/user.fota 脚本版本号 001.999.000 core版本号 V1016

I/user.fota_task_func recv IP_READY
I/user.开始检查升级

luat_fota_write 717:common data done, now checking 0
luat_fota_write 757:common data md5 ok
luat_fota_write 768:only common data
luat_fota_finish 417:fota type 0 ok!, wait reboot

--升级之后可以看到如下打印
I/user.fota 脚本版本号 001.999.001 core版本号 V1016
```

