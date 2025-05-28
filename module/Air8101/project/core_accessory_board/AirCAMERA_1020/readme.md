
## 演示功能概述

AirCAMERA_1020是合宙设计生产的一款DVP摄像头配件板；

本demo演示的核心功能为：

Air8101核心板+AirCAMERA_1020配件板，演示DVP摄像头100万像素拍照+http上传照片+电脑浏览器查看照片的功能；


## 核心板+配件板资料

[Air8101核心板+配件板相关资料](https://docs.openluat.com/air8101/product/shouce/#air8101_1)


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirCAMERA_1020/hw_connection.jpg)

![](https://docs.openluat.com/air8101/product/file/AirCAMERA_1020/hw_connection1.jpg)

1、Air8101核心板

2、AirCAMERA_1020配件板（带DVP摄像头，1.8V的开关拨到ON，1.2V和1.5V的开关拨到OFF）

3、Air8101核心板和AirCAMERA_1020配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端），此种供电方式下，vbat引脚为3.3V，可以直接给AirCAMERA_1020配件板供电；

- 为了演示方便，所以Air8101核心板上电后直接通过vbat引脚给AirCAMERA_1020配件板提供了3.3V的供电；

- 客户在设计实际项目时，一般来说，需要通过一个GPIO来控制LDO给摄像头供电，这样可以灵活地控制摄像头的供电，可以使项目的整体功耗降到最低；

- AirCAMERA_1020配件板设计为了排母的形式，可以参考下表直接插到Air8101核心板的排针上

| Air8101核心板 | AirCAMERA_1020配件板 |
| ------------ | -------------------- |
|     vbat     |          VDD         |
|     gnd      |          GND         |
|   11/U1RX    |          SDA         |
|   12/U1TX    |          SCL         |
|   73/VSY     |          VSY         |
|    3/HSY     |          HSY         |
|    69/D7     |           D7         |
|    2/MCLK    |         MCLK         |
|     7/D6     |           D6         |
|     70/D5    |           D5         |
|    74/PCK    |         PCLK         |
|     6/D4     |           D4         |
|     4/D0     |           D0         |
|    71/D3     |           D3         |
|    72/D1     |           D1         |
|     5/D2     |           D2         |


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1003版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1003固件对比验证）


## 演示操作步骤

1、搭建好演示硬件环境

2、demo脚本代码wifi_app.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行

5、观察Luatools的运行日志，如果输出 http_upload_photo_task_func httpplus.request 200表示测试正常

6、电脑上浏览器打开[https://www.air32.cn/upload/data/jpg/](https://www.air32.cn/upload/data/jpg/)，打开对应的测试日期目录，点击具体的测试时间照片，可以查看摄像头拍照上传的照片
   

