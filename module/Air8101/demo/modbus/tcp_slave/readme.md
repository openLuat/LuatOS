## 演示模块概述

1、main.lua：主程序入口；

2、tcp_slave_manage.lua：TCP 从站应用模块；

3、netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块；

4、netdrv_eth_rmii.lua：“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”驱动模块

## 演示功能概述

本功能模块演示的内容为：

1、将设备配置为 modbus TCP 从站模式

2、等待并且应答主站请求



注意事项：

1、该示例程序需要搭配 exmodbus 扩展库使用

2、设备作为 modbus TCP 从站模式时，仅支持接收 modbus TCP 标准格式的请求报文

3、进行回应时也需要符合 modbus TCP 标准格式



特别说明：

1、示例代码中配置了两种以太网卡

2、在 main.lua 中 require "netdrv_eth_rmii" 模块，使用的是“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”

3、在 main.lua 中 require "netdrv_eth_spi" 模块，使用的是“通过SPI外挂CH390H芯片的以太网卡”

4、require "netdrv_eth_rmii" 和 require "netdrv_eth_spi" 不要同时打开，否则会导致功能冲突

## 演示硬件环境

1、Air8101 核心板一块

2、AirPHY_1000 和 AirETH_1000 配件板任意一块

3、TYPE-C USB数据线一根

4、网线两根（一根开发板使用，一根电脑使用）



Air8101 核心板和 AirPHY_1000 配件板的硬件接线方式为:

| Air8101核心板 | AirPHY_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 5/D2          | RX1               |
| 72/D1         | RX0               |
| 71/D3         | CRS               |
| 4/D0          | MDIO              |
| 6/D4          | TX0               |
| 74/PCK        | MDC               |
| 70/D5         | TX1               |
| 7/D6          | TXEN              |
| 不接          | NC                |
| 69/D7         | CLK               |

Air8101 核心板和 AirETH_1000 配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 28/DCLK       | SCK               |
| 54/DISP       | CSS               |
| 55/HSYN       | SDO               |
| 57/DE         | SDI               |
| 14/GPIO8      | INT               |

Air8101 核心板与 AirPHY_1000、AirETH_1000 配件板接线图为：

![img](https://docs.openluat.com/cdn/image/Air8101_rmii_spi.png)

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/)

2、[Air8101 V2001 版本](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2001 固件对比验证）

> 目前 V2001 正式固件还未发布，可以先用上级目录中临时固件文件夹下的 LuatOS-SoC_V2001_Air8101_20251230_234242.soc 固件进行测试

3、[摩尔信使(MThings)官网](https://www.gulink.cn/)（用于模拟 modbus 主站设备）

## 演示核心步骤

1、搭建硬件环境

- 将 TYPE-C USB 数据线一端接在 Air8101 核心板上，另一端接在电脑上
- 将 AirPHY_1000 或 AirETH_1000 配件板与 Air8101 核心板相连接，网线接在配件板网口上，另一端接在路由器/交换机上

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

3、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

4、烧录成功后，自动开机运行

5、此时需要等待客户端连接，连接成功后 Luatools 工具上的日志如下：

```
[2026-01-04 17:27:14.729] luat:U(21062):I/user.exmodbus TCP 从站已启动，监听端口: 6000
```

6、如果摩尔信使一直没有连接成功，则需要对网络通道进行重启，鼠标右击左上角 “通道” 下方的按钮，点击 “配置参数” 后会弹出 “网络参数配置” 窗口，此时直接点击确定，通道便已经重启，操作流程如下：

![](https://docs.openluat.com/cdn/image/MThings/33.png)

7、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “启动轮询”，此时上位机便会模拟主站设备开始执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/34.png)

8、如下图所示，如果需要修改轮询的间隔时间或者其他参数，先将滑动条滑到右边，然后鼠标左键双击对应参数即可修改

![](https://docs.openluat.com/cdn/image/MThings/35.png)

9、开启轮询后 Luatools 工具与摩尔信使上的日志如下：

```
[2026-01-04 17:28:27.416] luat:U(93750):I/user.exmodbus_test 读取成功，返回数据:  0, 0
[2026-01-04 17:28:30.443] luat:U(96769):I/user.exmodbus_test tcp_slave 收到主站请求
[2026-01-04 17:28:30.443] luat:U(96769):I/user.exmodbus_test 读取成功，返回数据:  1, 1
[2026-01-04 17:28:33.465] luat:U(99792):I/user.exmodbus_test tcp_slave 收到主站请求
[2026-01-04 17:28:33.465] luat:U(99792):I/user.exmodbus_test 读取成功，返回数据:  201, 202
[2026-01-04 17:28:36.482] luat:U(102811):I/user.exmodbus_test tcp_slave 收到主站请求
[2026-01-04 17:28:36.482] luat:U(102812):I/user.exmodbus_test 读取成功，返回数据:  101, 102
```

![](https://docs.openluat.com/cdn/image/MThings/Air8101_36.png)

10、如下图所示，如果需要执行写入请求，需要先在执行可写操作的对应区块行的指令处鼠标左键双击填入要写入的数值，然后在鼠标右键双击该数值，最后点击下发写指令

![](https://docs.openluat.com/cdn/image/MThings/Air8101_37.png)

11、执行写入请求后 Luatools 工具与摩尔信使上的日志如下：

```
[2026-01-04 17:32:11.049] luat:U(317384):I/user.exmodbus_test tcp_slave 收到主站请求
[2026-01-04 17:32:11.049] luat:U(317385):I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
```

![](https://docs.openluat.com/cdn/image/MThings/Air8101_38.png)

12、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “停止轮询”，此时上位机便不会再执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/Air8101_39.png)