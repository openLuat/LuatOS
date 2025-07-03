## 演示功能概述

本DEMO演示的核心功能为：

Air8101核心板在常规模式、低功耗模式、PSM+模式的功耗表现；

1、normal常规模式：normal.lua中就是常规模式的代码案例,持续向平台发送心跳数据。平均功耗：8.17mA

2、low_power低功耗模式：low_powerr.lua中就是低功耗模式的代码案例，进入低功耗模式后向平台发送心跳包。平均功耗：218uA

3、psm+低功耗模式：psm+_power.lua中就是PSM+模式的代码案例，定时唤醒向平台发送心跳包。平均功耗：11uA

## 核心板资料

[Air8101核心板](https://docs.openluat.com/air8101/product/shouce/#air8101_1)

## 演示硬件环境

1、Air8101核心板

2、Air9000P功耗分析仪

3、接线方式

 - Air9000P连接核心板的VBAT和GND接口，低功耗模式需要使用外部供电才能测试；

 - 电脑连接USB，将背面 “ 功耗测试开关 ” 拨到ON，断开USB供电，仅保留数据传输功能用于烧录固件；

 - 电脑打开 “ 功耗分析仪 ” 软件，连接Air9000P；

## 演示软件环境

1、Luatools下载调试工具；

2、[Air8101 最新版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（请更新官网最新固件，低于V1005版本的固件不支持调整DTIM参数）

## 演示操作步骤

1、搭建好演示硬件环境

2、demo脚本代码：

 - wifi_app.lua中的上方，修改好 “ ssid ” 和 “ password ” 参数，修改为自己测试时WIFI热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

 - tcp_client_main.lua中的上方，修改好 “ SERVER_ADDR ”  “ SERVER_PORT ” 参数，修改为自己测试的TCP服务器IP地址和端口号；

 - psm+_power.lua \ low_power.lua \ normal.lua 中的上方，可根据业务需求可以通过参数设置是否开启WIFI功能、DTIM参数、心跳数据包，演示对应需求的功耗情况；

3、Luatools烧录内核固件和修改后的demo脚本代码；

4、烧录成功后，自动开机运行；

5、USB会漏电，所以烧录成功后先观察Luatools的打印，如果输出 “ D/pm workmode X （ X 是代码中pm.power(pm.WORK_MODE, X)所填的数值 ）” 表示已经进入对应的功耗模式，即可拔掉USB，重启核心板，通过观察功耗分析仪的平均功耗值观察是否进入低功耗模式。