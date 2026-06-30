## 演示模块概述

1、main.lua：主程序入口；

2、can_normal：CAN总线正常工作模式使用示例；

3、can_self_test：CAN总线自测模式使用示例；

4、can_sleep：CAN总线休眠模式使用示例；

## 演示功能概述

使用Air780EPM开发板测试can相关功能。

## 演示硬件环境

![](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、Air780EPM V1.3版本开发板一块：

2、TYPE-C USB数据线一根 + UUSB_CAN调试工具，Air780EPM V1.3版本开发板和数据线的硬件接线方式为：

- Air780EPM V1.3版本开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB_CAN调试工具；
[购买链接](https://item.taobao.com/item.htm?ali_refid=a3_420434_1006%3A1330120002%3AH%3A9SFQIGQ4mY23bDITa5hTWDVt9Q0NFo%2BR%3Af5b96aea99b81f4ec91d26df711cca50&ali_trackid=282_f5b96aea99b81f4ec91d26df711cca50&id=812265392082&mi_id=0000vjVYSYIby0jbxBAjaGtBcBvrJQC3ZiM5PLnmCR72-A4&mm_sceneid=1_0_1265540007_0&priceTId=213e087917624285597364626e0f67&spm=a21n57.1.hoverItem.7&utparam=%7B%22aplus_abtest%22%3A%2287f8626860a1f088a37e15c1554afbf4%22%7D&xxc=ad_ztc&skuId=5507953049692)

3、接线说明:

| Air780EPM开发板    | USB_CAN调试工具 |
| ----------------- | -------------   |
| H                 | H               |
| L                 | L               |
| GND               | GND             |

![](https://docs.openluat.com/air780epm/luatos/app/driver/can/image/VGHJbqeJVobFHYxx11Dcy2a8ngf.png)

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM V2016版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上，最新发布的固件都可以）

3、PC端的USB_CAN调试工具上位机软件；ZCANPRO和UCANFDtoCANFDNETTool
![](https://docs.openluat.com/air780epm/luatos/app/driver/can/image/usb-can-1.png)
![](https://docs.openluat.com/air780epm/luatos/app/driver/can/image/usb-can-2.png)
![](https://docs.openluat.com/air780epm/luatos/app/driver/can/image/usb-can-3.png)

## 演示核心步骤

1、搭建好硬件环境

2、main.lua 中加载需要用的功能模块，三个功能模块同时只能选择一个使用，其他的注释。

3、Luatools 烧录内核固件和修改后的 demo 脚本代码

4、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印can初始化和can收发数据等相关信息。

5、can_normal：
![](https://docs.openluat.com/air780epm/luatos/app/driver/can/image/780EPM-can1.png)

6、can_self_test：
![](https://docs.openluat.com/air780epm/luatos/app/driver/can/image/780EPM-can2.png)

7、can_sleep：
![](https://docs.openluat.com/air780epm/luatos/app/driver/can/image/780EPM-can3.png)
