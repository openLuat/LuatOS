
## 演示功能概述
1、设置网络优先级功能，根据优先级自动切换可用网络

2、验证网络是否正常切换，http功能是否可用

3、设置多网融合模式，例如以太网作为数据出口给WIFI设备上网

## 演示硬件环境

1、Air8000开发板
2、网线1根（一端接开发板软件rj45接口，一端接路由器）
![](https://docs.openluat.com/air8000/luatos/app/multinetwork/multinetwork2/image/OBqobf8qXoeHnwxi7K6ckkDRnlb.png)

## 演示软件环境

1、Luatools下载调试工具

2、烧录demo代码 [烧录教程](https://docs.openluat.com/air8000/luatos/common/download/)

## 演示核心步骤

1、搭建好硬件环境

2、成功连接wifi，http请求功能正常

3、测试网络切换功能:
- 插入网线
- 关闭wifi
- 打开wifi并拔掉网线
- 网络可以正常切换，http请求均正常

4、测试多网融合功能时，连接好网线，其他设备连接模块的wifi热点。测试网络是否正常