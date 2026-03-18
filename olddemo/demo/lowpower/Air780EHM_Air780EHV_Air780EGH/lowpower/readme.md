## 演示功能概述

本DEMO演示的核心功能为：

Air780EPM/EHM/EHV/EGH 核心板在常规模式、低功耗模式、PSM+模式的功耗表现；

1、normal_power常规模式：normal_power.lua中就是常规模式的代码案例,5分钟一次向平台发送心跳数据。平均功耗：6mA，无业务待机功耗平均：5mA

2、low_power低功耗模式：low_power.lua中就是低功耗模式的代码案例，进入低功耗模式后5分钟一次向平台发送心跳包。low_power低功耗模式平均功耗：1.5mA，无业务待机功耗：300uA

3、psm+_power低功耗模式：psm+_power.lua中就是PSM+模式的代码案例，5分钟一次唤醒向平台发送心跳包。PSM+极低功耗模式平均功耗：3uA，无业务待机功耗：3uA

## 核心板资料

[Air780EPM/EHM核心板](https://docs.openluat.com/air780epm/product/shouce/)

[Air780EHV核心板](https://docs.openluat.com/air780ehv/product/shouce/)

[Air780EGH核心板](https://docs.openluat.com/air780egh/product/shouce/)

## 演示硬件环境

1、Air780EPM/EHM/EHV/EGH 核心板

2、Air9000P功耗分析仪

3、接线方式

 - Air9000P连接核心板的VBAT和GND接口，低功耗模式需要使用外部供电才能测试；

 - 将USB旁边的拨码开关拨到OFF，断开USB供电；

 - 电脑打开 “ 功耗分析仪 ” 软件，连接Air9000P；

## 演示软件环境

1、Luatools下载调试工具；

2、
[Air780EPM/EHM核心板](https://docs.openluat.com/air780epm/luatos/firmware/version/)

[Air780EHV核心板](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

[Air780EGH核心板](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示操作步骤

1、搭建好演示硬件环境

2、demo脚本代码：

 - tcp_client_main.lua中的上方，修改好 “ SERVER_ADDR ”  “ SERVER_PORT ” 参数，修改为自己测试的TCP服务器IP地址和端口号；

 - low_power.lua \ normal.lua 中的上方，可根据业务需求可以通过参数设置是否开启4G功能、连接TCP服务器功能、心跳数据包，演示对应需求的功耗情况；

 - psm+_power.lua 中调用的是 tcp_short.lua 短连接TCP客户端功能模块，在每次发送信息结束后释放TCP客户端，避免造成TCP客户端资源占用情况，修改好“ SERVER_ADDR ”  “ SERVER_PORT ” 参数  “tcp_rec” 参数 ，即可正常测试。

3、Luatools烧录内核固件和修改后的demo脚本代码；

4、烧录成功后，自动开机运行；

5、USB会漏电，所以烧录成功后先观察Luatools的打印，如果输出 “ D/pm workmode X （ X 是代码中pm.power(pm.WORK_MODE, X)所填的数值 ）” 表示已经进入对应的功耗模式，即可拔掉USB，重启核心板，通过观察功耗分析仪的平均功耗值观察是否进入低功耗模式。

## 文档网址

Air780EHM:https://docs.openluat.com/air780epm/luatos/app/lowpower/sleep/

Air780EHV:https://docs.openluat.com/air780ehv/luatos/app/lowpower/sleep/

Air780EGH:https://docs.openluat.com/air780egh/luatos/app/lowpower/sleep/