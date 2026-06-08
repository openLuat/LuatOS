##  演示功能概述：

本文件下共有4个示例demo和1个示例工程

1、modbus rtu：8000W双网口板子的2个485配置为 modbus RTU 主站和从站模式，进行与从站的寄存器读写操作

2、modbus tcp：8000W 双网口板子双网口分别设置静态 IP，工作在 Modbus TCP 一主站一从站模式，完成主站与从站之间的寄存器读写操作

3、netdrv：演示 netdrv核心库+dnsproxy扩展库+dhcpsrv扩展库 开启以太网或wifi单网卡,4G,wifi,以太网多网融合功能

4.network_routing: 演示三种网络路由模式

5.project：整合了 Socket 长连接、Modbus RTU/TCP 主从站、AirCloud 物联网数据上报、合宙 LBS 定位、网络看门狗等功能的一个项目示例
