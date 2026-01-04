## 演示模块概述

1、main.lua：主程序入口；

2、rtu_slave_manage.lua：RTU 从站应用模块；

## 演示功能概述

本 demo 演示的核心功能为：

1、将设备配置为 modbus RTU 从站模式

2、等待并且应答主站请求



注意事项：

1、该示例程序需要搭配 exmodbus 扩展库使用

2、设备作为 modbus RTU 从站模式时，仅支持接收 modbus RTU 标准格式的请求报文

3、进行回应时也需要符合 modbus RTU 标准格式

## 演示硬件环境

1、Air8000 开发板一块

2、TYPE-C USB数据线一根

3、USB-RS485 串口板

> 此处购买链接仅为推荐，如有问题请直接联系店家

- 购买链接：[4路RS-485，TYPEC接口 不含USB线](https://item.taobao.com/item.htm?app=chrome&bxsign=scdJP32y4DuiSo5k5D89Yse5PsbQ6EIYXNIPNkzmMi6zdQszLdrZrUy6-Nw96m51cCA5oz67QzXT9StIYyW8C2WWDa9P6CTUC4Imox3bONGK_FgAw8bQ8lYY0rnL7cRpNsG&cpp=1&id=608773837508&price=2.5&shareUniqueId=34323628624&share_crt_v=1&shareurl=true&short_name=h.7YHZDX57ex5G68h&skuId=5692060399621&sourceType=item&sp_tk=QXZFNGZzdXJGeTg%3D&spm=a2159r.13376460.0.0&suid=97525605-306d-4a26-8181-c6a5e5ac1449&tbSocialPopKey=shareItem&tk=AvE4fsurFy8&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1765329298678.Copy.1&wxsign=tbwqCWYZys39IqYxa6fkQJ4fSCqNnxJegN9tEYlbjtUm1rAZyDddEbbohCLQnFZUojPMaKxNICvdbp1uAgV6d03jf7_X0hLeyUaHbuddZUTcL_y45R5fClnUqq9IfXXAxNG)

![](https://docs.openluat.com/cdn/image/Air8000_rs485.png)

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 V2018 版本](https://docs.openluat.com/air8000/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2018-1 固件对比验证）

3、[摩尔信使(MThings)官网](https://www.gulink.cn/)（用于模拟 modbus 主站设备）

## 演示核心步骤

1、搭建硬件环境

- 将 USB-RS485 串口板与 Air8000 开发板进行连接
- 将 USB-RS485 串口板 与 Air8000 开发板的 USB 端同时接在电脑上
- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 RTU 主站设备环境

- 点击左上角的 “通道管理”按钮，在 “通道管理” 窗口选择对应的串口（USB-RS485 串口板与 Air8000 开发板进行 485 通信时的端口），点击对应串口后面的 “配置” 按钮，在 “串口参数配置” 窗口配置串口参数（要求与代码中调用 exmodbus.create 接口时填入的配置参数一致），操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/1.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/20.png)

- 点击左侧的第一个主站（我这里显示为 “COM36-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增线圈 0-2，操作流程图如下，此时按照刚才操作，依次分别创建离散输入 0-2、保持寄存器 0-2、输入寄存器 0-2

  ![](https://docs.openluat.com/cdn/image/MThings/21.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/22.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下，此时便开始等待主站发送请求

```
[2025-12-08 17:23:19.802][000000000.678] I/user.main RTU_SLAVE 001.000.000
[2025-12-08 17:23:19.806][000000000.711] Uart_ChangeBR 1338:uart1, 115200 115203 26000000 3611
[2025-12-08 17:23:19.809][000000000.711] I/user.exmodbus 串口 1 初始化成功，波特率 115200
[2025-12-08 17:23:19.811][000000000.712] I/user.exmodbus_test rtu_slave 创建成功, 从站 ID 为 1
[2025-12-08 17:23:19.813][000000000.712] I/user.exmodbus 已注册从站请求处理回调函数
[2025-12-08 17:23:19.816][000000000.712] I/user.从站回调函数已注册，开始监听主站请求...
```

7、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “启动轮询”，此时上位机便会模拟主站设备开始执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/23.png)

8、如下图所示，如果需要修改轮询的间隔时间或者其他参数，先将滑动条滑到右边，然后鼠标左键双击对应参数即可修改

![](https://docs.openluat.com/cdn/image/MThings/24.png)

9、开启轮询后 Luatools 工具与摩尔信使上的日志如下：

```
[2025-12-08 17:32:09.235][000000023.394] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:32:09.239][000000023.394] I/user.exmodbus_test 读取成功，返回数据:  0, 0
[2025-12-08 17:32:12.251][000000026.402] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:32:12.255][000000026.402] I/user.exmodbus_test 读取成功，返回数据:  1, 1
[2025-12-08 17:32:15.266][000000029.417] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:32:15.269][000000029.418] I/user.exmodbus_test 读取成功，返回数据:  201, 202
[2025-12-08 17:32:18.270][000000032.420] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:32:18.273][000000032.420] I/user.exmodbus_test 读取成功，返回数据:  101, 102
[2025-12-08 17:32:21.294][000000035.443] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:32:21.296][000000035.444] I/user.exmodbus_test 读取成功，返回数据:  0, 0
[2025-12-08 17:32:24.288][000000038.446] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:32:24.290][000000038.447] I/user.exmodbus_test 读取成功，返回数据:  1, 1
[2025-12-08 17:32:27.326][000000041.476] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:32:27.329][000000041.477] I/user.exmodbus_test 读取成功，返回数据:  201, 202
```

![](https://docs.openluat.com/cdn/image/MThings/25.png)

10、如下图所示，如果需要执行写入请求，需要先在执行可写操作的对应区块行的指令处鼠标左键双击填入要写入的数值，然后在鼠标右键双击该数值，最后点击下发写指令

![](https://docs.openluat.com/cdn/image/MThings/26.png)

11、执行写入请求后 Luatools 工具与摩尔信使上的日志如下：

```
[2025-12-08 17:42:53.696][000000667.848] I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-08 17:42:53.704][000000667.848] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
```

![](https://docs.openluat.com/cdn/image/MThings/27.png)

12、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “停止轮询”，此时上位机便不会再执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/28.png)
