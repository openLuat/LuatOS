
## 演示功能概述

AirCAMERA_1030是合宙设计生产的一款USB摄像头配件板；

AirUSBHUB_1000是合宙直接使用的第三方一拖四的USB HUB（例如绿联的USB HUB产品）

本demo演示的核心功能为：

Air8101核心板+AirUSBHUB_1000+HUB上外挂四个AirCAMERA_1030配件板；

依次演示四个AirCAMERA_1030的USB摄像头100万像素拍照+http上传照片+电脑浏览器查看照片的功能；


## 核心板+配件板资料

[Air8101核心板+配件板相关资料](https://docs.openluat.com/air8101/product/shouce/#air8101_1)


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirUSBHUB_1000/hw_connection.jpg)

1、Air8101核心板

2、AirUSBHUB_1000配件板

3、四个AirCAMERA_1030配件板（带USB摄像头+数据连接线）

4、Air8101核心板+AirUSBHUB_1000配件板+AirCAMERA_1030配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，可能是供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

- Air8101核心板上的3.3V和5V拨动开关，拨到5V的一端；

- Air8101核心板的USB-A母座和AirUSBHUB_1000配件板的USB-A公座相连；

- AirUSBHUB_1000配件板上有四个USB端口，每个端口接一个AirCAMERA_1030配件板


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1003版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1003固件对比验证）

## 演示操作步骤

1、搭建好演示硬件环境

2、demo脚本代码wifi_app.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行

5、观察Luatools的运行日志，如果输出 http_upload_photo_task_func httpplus.request 200 x，表示USB HUB上的第x个摄像头测试正常

6、电脑上浏览器打开[https://www.air32.cn/upload/data/jpg/](https://www.air32.cn/upload/data/jpg/)，打开对应的测试日期目录，点击具体的测试时间照片，可以查看摄像头拍照上传的照片
   

