
## 演示功能概述


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirCAMERA_1030/hw_connection.jpg)

1、Air8101核心板

2、AirCAMERA_1030配件板（带USB摄像头+数据连接线）

3、Air8101核心板和AirCAMERA_1030配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，可能是供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

- Air8101核心板上的3.3V和5V拨动开关，拨到5V的一端；为了演示方便，所以Air8101核心板的上电后直接给AirCAMERA_1030配件板提供了供电；

- 客户在设计实际项目时，一般来说，需要通过一个GPIO来控制LDO给摄像头供电，这样可以灵活地控制摄像头的供电，可以使项目的整体功耗降到最低；

- Air8101核心板的USB-A母座和AirCAMERA_1030配件板的USB-A公座相连；


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1004版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1004固件对比验证）


## 演示操作步骤

1、搭建好演示硬件环境

2、demo脚本代码wifi_app.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行

5、......
   

