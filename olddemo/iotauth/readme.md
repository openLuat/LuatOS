## 演示模块概述

1、main.lua：主程序入口；

2、iotauth_app.lua：物联网平台 MQTT 三元组参数生成功能模块；

## 演示功能概述

使用目前主流模组（例如 Air780EPM、Air8000、Air8101）对应的开发板搭配 iotauth 库演示各主流物联网平台 MQTT 三元组参数生成功能；

1、为 阿里云 生成 MQTT 三元组参数；

2、为 中移OneNet 生成 MQTT 三元组参数；

3、为 华为云IoTDA 生成 MQTT 三元组参数；

4、为 腾讯云 生成 MQTT 三元组参数；

5、为 涂鸦云 生成 MQTT 三元组参数；

6、为 百度云 生成 MQTT 三元组参数；



注意事项如下：

1、iotauth 库及该示例代码仅供参考，目前已不再提供维护和技术支持服务

2、该示例代码存放于：https://gitee.com/openLuat/LuatOS/tree/master/olddemo/iotauth

3、在烧录底层固件时需要选择支持 64 位的固件版本

- Air7xxx、Air8000 系列模组选择版本号为 101-199 的固件
- Air8101 系列模组选择版本号为 V2xxx 的固件（目前 V2xxx 版本固件还没有第一版）

## 演示硬件环境

1、目前主流模组（例如 Air780EPM、Air8000、Air8101）对应开发板

2、TYPE-C USB数据线一根

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air7xx 系列模组 V2016 版本](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2016-103 固件对比验证）

3、[Air8000 系列模组 V2016 版本](https://docs.openluat.com/air8000/luatos/common/download/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2016-101 固件对比验证）

4、[Air8101 模组 V2xxx 版本](https://docs.openluat.com/air8101/luatos/firmware/)（V1xxx 版本不支持 64 位运算，需要等 V2xxx 版本发布）

## 演示核心步骤

1、搭建好硬件环境

2、Luatools 工具烧录内核固件和 demo 脚本代码

3、烧录成功后，自动开机运行

4、正常运行情况时的日志如下：

```
[000000000.750] I/user.main iotauth 001.000.000
[000000000.760] I/user.aliyun a1B2c3D4e5F.sensor_001|securemode=2,signmethod=hmacsha256,timestamp=324721152001213| sensor_001&a1B2c3D4e5F 26DC1595358D45D373FBE40B54540C0D8763DABDE7F1CBB263FF4067A93F7150
[000000000.761] I/user.onenet test Ck2AF9QD2K version=2048-10-31&res=products%2FCk2AF9QD2K%2Fdevices%2Ftest&et=32472115200&method=sha256&sign=7TMn%2FaAfeybZBTPstT%2FxSQUqHokNOVbJ3JpLJR8fz7g%3D
[000000000.762] I/user.iotda 6203cc94c7fb24029b110408_88888888_0_0_2999010100 6203cc94c7fb24029b110408_88888888 5888ea6f4631ce76d621f452e8823507c36dd68a61f6e08518c8935e280c3c72
[000000000.785] I/user.qcloud LD8S5J1L07test LD8S5J1L07test;12010126;qkvrc;32472115200 7f9b0fcd6eb78676f38272f7025948d8564ace5339a5b5c0e00d6339bba30c99;hmacsha256
[000000000.786] I/user.tuya tuyalink_6c95875d0f5ba69607nzfl 6c95875d0f5ba69607nzfl|signMethod=hmacSha256,timestamp=7258089600,secureMode=1,accessType=1 d4e2d498e4195db3ed213b33d662e3b7bf434dc3d5a1f2e63b602ac9248ba72c
[000000000.787] I/user.baidu abcd123 thingidp@abcd123|mydevice|32472115200|SHA256 0e2e78921783530a6402f64b4265abbaa4fefb5f5da10af556d0c5b676c52836
```

