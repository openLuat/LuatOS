
## 演示功能概述

AirCAMERA_1020是合宙设计生产的一款DVP摄像头配件板；

本demo演示的核心功能为：

Air8101核心板+AirCAMERA_1020配件板，演示DVP摄像头100万像素拍照+http上传照片+电脑浏览器查看照片的功能；


## 演示硬件环境

1、Air8101核心板

2、AirCAMERA_1020配件板（带DVP摄像头）

3、母对母的杜邦线

4、Air8101核心板和AirCAMERA_1020配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）

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
|     不接     |           NC         |
|     不接     |          RST         |


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1003版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1003固件对比验证）

## 演示操作步骤

1、搭建好演示硬件环境

2、demo脚本代码wifi_app.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行

5、观察Luatools的运行日志，如果输出 http_upload_photo_task_func httpplus.request 200表示测试正常

6、电脑上浏览器打开https://www.air32.cn/upload/data/jpg/，打开对应的测试日期目录，点击具体的测试时间照片，可以查看摄像头拍照上传的照片
   

