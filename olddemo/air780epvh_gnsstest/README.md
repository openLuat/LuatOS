# Air780EPVH定位数据测试程序

## 使用条件

硬件条件: Air780EVPH

## 固件要求

2024.6.1之后的编译的Air780EP或者Air780EPV固件

## 提醒, 本demo需要很多流量

若持续开启, 日流量需要**100M**以上, 务必留意!!

本demo完全没有优化流量, 会上报**全部**GNSS数据, 以便分析!!!

## demo说明

1. 开启 testGnss 是定位功能演示, 含开启GNSS功能, 获取GNSS数据, 注入辅助定位信息(AGPS)
2. 开启 testMqtt 是上报定位信息到MQTT服务器, 对应的演示网页是 https://iot.openluat.com/iot/device-gnss
3. 开启 testGpio 是演示GPIO功能, 定位成功后切换GPIO输出
4. 开启 testTcp 是演示上传数据到TCP服务器, 对应的网页是 https://gps.nutz.cn 微信小程序 iRTU寻物