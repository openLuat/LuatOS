## 演示模块概述

1、main.lua：主程序入口；

2、tcp_slave_manage.lua：TCP 从站应用模块；

3、netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块；

## 演示功能概述

本功能模块演示的内容为：

1、将设备配置为 modbus TCP 从站模式

2、等待并且应答主站请求



注意事项：

1、该示例程序需要搭配 exmodbus 扩展库使用

2、设备作为 modbus TCP 从站模式时，仅支持接收 modbus TCP 标准格式的请求报文

3、进行回应时也需要符合 modbus TCP 标准格式

## 演示硬件环境

1、Air780EPM V1.3 开发板一块

2、TYPE-C USB数据线一根

3、网线两根（一根开发板使用，一根电脑使用）

![](https://docs.openluat.com/cdn/image/Air780EPM_tcp1.png)

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/)

2、[Air780EPM V2018 版本](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2018-1 固件对比验证）

3、[摩尔信使(MThings)官网](https://www.gulink.cn/)（用于模拟 modbus 主站设备）

## 演示核心步骤

1、搭建硬件环境

- 将 TYPE-C USB 数据线一端接在 Air780EPM 开发板上，另一端接在电脑上
- 将网线一端接在 Air780EPM 开发板网口上，另一端接在路由器/交换机上

- 将另一根网线一端接在电脑网口上，另一端接在同一个路由器/交换机上

- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 TCP 主站设备环境

- 点击左上角的 “通道管理” 按钮，在 “通道管理” 窗口点击 “网络通道” 按钮，点击 NET000 通道后面的 “配置” 按钮，在 “网络参数配置” 窗口配置网络参数，操作流程如下：

  ![](https://docs.openluat.com/cdn/image/MThings/40.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/30.png)

- 点击左侧的第一个主站（我这里显示为 “NET000-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增线圈 0-2，操作流程图如下，此时按照刚才操作，依次分别创建离散输入 0-2、保持寄存器 0-2、输入寄存器 0-2

  ![](https://docs.openluat.com/cdn/image/MThings/31.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/32.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、此时需要等待客户端连接，连接成功后 Luatools 工具上的日志如下：

```
[2025-12-30 14:35:47.143][000000007.794] I/user.exmodbus TCP 从站已启动，监听端口: 6000
```

7、如果摩尔信使一直没有连接成功，则需要对网络通道进行重启，鼠标右击左上角 “通道” 下方的按钮，点击 “配置参数” 后会弹出 “网络参数配置” 窗口，此时直接点击确定，通道便已经重启，操作流程如下：

![](https://docs.openluat.com/cdn/image/MThings/33.png)

8、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “启动轮询”，此时上位机便会模拟主站设备开始执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/34.png)

9、如下图所示，如果需要修改轮询的间隔时间或者其他参数，先将滑动条滑到右边，然后鼠标左键双击对应参数即可修改

![](https://docs.openluat.com/cdn/image/MThings/35.png)

10、开启轮询后 Luatools 工具与摩尔信使上的日志如下：

```
[2025-12-30 14:36:23.190][000000043.854] I/user.exmodbus_test tcp_slave 收到主站请求
[2025-12-30 14:36:23.197][000000043.854] I/user.exmodbus_test 读取成功，返回数据:  0, 0
[2025-12-30 14:36:26.211][000000046.865] I/user.exmodbus_test tcp_slave 收到主站请求
[2025-12-30 14:36:26.218][000000046.866] I/user.exmodbus_test 读取成功，返回数据:  1, 1
[2025-12-30 14:36:29.226][000000049.882] I/user.exmodbus_test tcp_slave 收到主站请求
[2025-12-30 14:36:29.236][000000049.882] I/user.exmodbus_test 读取成功，返回数据:  201, 202
[2025-12-30 14:36:32.241][000000052.897] I/user.exmodbus_test tcp_slave 收到主站请求
[2025-12-30 14:36:32.246][000000052.898] I/user.exmodbus_test 读取成功，返回数据:  101, 102
[2025-12-30 14:36:35.265][000000055.919] I/user.exmodbus_test tcp_slave 收到主站请求
[2025-12-30 14:36:35.271][000000055.919] I/user.exmodbus_test 读取成功，返回数据:  0, 0
```

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_36.png)

11、如下图所示，如果需要执行写入请求，需要先在执行可写操作的对应区块行的指令处鼠标左键双击填入要写入的数值，然后在鼠标右键双击该数值，最后点击下发写指令

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_37.png)

12、执行写入请求后 Luatools 工具与摩尔信使上的日志如下：

```
[2025-12-30 14:42:32.629][000000413.285] I/user.exmodbus_test tcp_slave 收到主站请求
[2025-12-30 14:42:32.637][000000413.285] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
```

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_38.png)

13、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “停止轮询”，此时上位机便不会再执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_39.png)