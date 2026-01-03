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



特别说明：

演示代码使用 Air8101 核心板进行演示

由于 Air8101 核心板不带 485 接口，所以在演示时需要外接 485 转串口模块

演示时使用的 485 转串口模块，模块硬件自动切换方向，不需要软件 io 控制

如果外接的 485 转串口模块的方向引脚连接到了 Air8101 核心板的 GPIO 引脚

则需要在 "param_field" 等其他模块代码中配置 rs485_dir_gpio 为对应的 GPIO 引脚号

同时也需要配置 rs485_dir_rx_level 为 0 或 1，默认为 0

## 演示硬件环境

1、Air8101 核心板一块

2、TYPE-C USB数据线一根

3、UART-RS485 串口板

> 此处购买链接仅为推荐，如有问题请直接联系店家

- 购买链接：[裸板3.3-5V供电TTL电平兼容3.3-5V M2铜柱固定](https://item.taobao.com/item.htm?app=chrome&bxsign=scdXlhF10ejv6GI1K5bBXly15Q2huOVUk-H8hGnJMbwSuFKLuiLfWBBCKV_W0XKWwpzVniqvSivBSvcCEu4RZdrZIjE2F8UdRi5IFekvB7zM-0fJXYrHjTB7ccHXHAhG3KV&cpp=1&id=803532080330&price=18&shareUniqueId=34590410848&share_crt_v=1&shareurl=true&short_name=h.7T9Saa9u4QXerkU&skuId=5471217113027&sourceType=item&sp_tk=WkNDZVVhZE1lUEo%3D&spm=a2159r.13376460.0.0&suid=b9adc616-d579-4b37-9a09-0c35a35d9179&tbSocialPopKey=shareItem&tk=ZCCeUadMePJ&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1767146559998.Copy.1&wxsign=tbwhYFjAC-a3R2BDAoFO2r6gHQDtBjNmFT2zOjw54KFizTEcOpblmA7KI6WfBoKdA3R5iIA241AAi5wWpQrUjQ6g9_keE1IsPkHXSpAvPZIXvbrfuAnNCf0GiI0ieRM9Jda)

4、USB-RS485 串口板

> 此处购买链接仅为推荐，如有问题请直接联系店家

- 购买链接：[4路RS-485，TYPEC接口 不含USB线](https://item.taobao.com/item.htm?app=chrome&bxsign=scdJP32y4DuiSo5k5D89Yse5PsbQ6EIYXNIPNkzmMi6zdQszLdrZrUy6-Nw96m51cCA5oz67QzXT9StIYyW8C2WWDa9P6CTUC4Imox3bONGK_FgAw8bQ8lYY0rnL7cRpNsG&cpp=1&id=608773837508&price=2.5&shareUniqueId=34323628624&share_crt_v=1&shareurl=true&short_name=h.7YHZDX57ex5G68h&skuId=5692060399621&sourceType=item&sp_tk=QXZFNGZzdXJGeTg%3D&spm=a2159r.13376460.0.0&suid=97525605-306d-4a26-8181-c6a5e5ac1449&tbSocialPopKey=shareItem&tk=AvE4fsurFy8&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1765329298678.Copy.1&wxsign=tbwqCWYZys39IqYxa6fkQJ4fSCqNnxJegN9tEYlbjtUm1rAZyDddEbbohCLQnFZUojPMaKxNICvdbp1uAgV6d03jf7_X0hLeyUaHbuddZUTcL_y45R5fClnUqq9IfXXAxNG)

Air8101 与 UART-RS485 串口板接线图如下：

![](https://docs.openluat.com/cdn/image/Air8101_uart-485.png)

UART-RS485 串口板与 USB-RS485 串口板接线图如下：

![](https://docs.openluat.com/cdn/image/uart-485-USB.png)

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/)

2、[Air8101 V2001 版本](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2001 固件对比验证）

> 目前 V2001 正式固件还未发布，可以先用 https://www.air32.cn/air8101v2/LuatOS-SoC_V2001_Air8101_20251230_234242.soc 这个测试固件进行测试

3、[摩尔信使(MThings)官网](https://www.gulink.cn/)（用于模拟 modbus 主站设备）

## 演示核心步骤

1、搭建硬件环境

- 将 UART-RS485 串口板的 UART 端与 Air8101 核心板进行连接
- 将 UART-RS485 串口板的 RS485 端与 USB-RS485 的 RS485 端进行连接
- 将 USB-RS485 串口板与 Air8101 核心板的 USB 端同时接在电脑上
- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 RTU 主站设备环境

- 点击左上角的 “通道管理”按钮，在 “通道管理” 窗口选择对应的串口（UART-RS485 串口板与 Air8101 核心板进行 485 通信时的端口），点击对应串口后面的 “配置” 按钮，在 “串口参数配置” 窗口配置串口参数（要求与代码中调用 exmodbus.create 接口时填入的配置参数一致），操作流程图如下：

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
[2025-12-31 16:03:50.355] luat:U(1187):I/user.main RTU_SLAVE 001.000.000
[2025-12-31 16:03:50.413] luat:D(1243):uart:uart(1) tx pin: 0, rx pin: 1
[2025-12-31 16:03:50.413] luat:U(1244):I/user.exmodbus 串口 1 初始化成功，波特率 115200
[2025-12-31 16:03:50.413] luat:U(1244):I/user.exmodbus_test rtu_slave 创建成功, 从站 ID 为 1
[2025-12-31 16:03:50.413] luat:U(1244):I/user.exmodbus 已注册从站请求处理回调函数
[2025-12-31 16:03:50.413] luat:U(1245):I/user.从站回调函数已注册，开始监听主站请求...
```

7、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “启动轮询”，此时上位机便会模拟主站设备开始执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/23.png)

8、如下图所示，如果需要修改轮询的间隔时间或者其他参数，先将滑动条滑到右边，然后鼠标左键双击对应参数即可修改

![](https://docs.openluat.com/cdn/image/MThings/24.png)

9、开启轮询后 Luatools 工具与摩尔信使上的日志如下：

```
[2025-12-31 16:04:06.725] luat:U(17553):I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-31 16:04:06.725] luat:U(17554):I/user.exmodbus_test 读取成功，返回数据:  0, 0
[2025-12-31 16:04:09.734] luat:U(20563):I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-31 16:04:09.734] luat:U(20564):I/user.exmodbus_test 读取成功，返回数据:  1, 1
[2025-12-31 16:04:12.739] luat:U(23569):I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-31 16:04:12.739] luat:U(23570):I/user.exmodbus_test 读取成功，返回数据:  201, 202
[2025-12-31 16:04:15.740] luat:U(26570):I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-31 16:04:15.740] luat:U(26571):I/user.exmodbus_test 读取成功，返回数据:  101, 102
[2025-12-31 16:04:18.762] luat:U(29590):I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-31 16:04:18.762] luat:U(29591):I/user.exmodbus_test 读取成功，返回数据:  0, 0
```

![](https://docs.openluat.com/cdn/image/MThings/Air8101_25.png)

10、如下图所示，如果需要执行写入请求，需要先在执行可写操作的对应区块行的指令处鼠标左键双击填入要写入的数值，然后在鼠标右键双击该数值，最后点击下发写指令

![](https://docs.openluat.com/cdn/image/MThings/Air8101_26.png)

11、执行写入请求后 Luatools 工具与摩尔信使上的日志如下：

```
[2025-12-31 16:08:57.335] luat:U(308176):I/user.exmodbus_test rtu_slave 收到主站请求
[2025-12-31 16:08:57.335] luat:U(308177):I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
```

![](https://docs.openluat.com/cdn/image/MThings/Air8101_27.png)

12、如下图所示，在摩尔信使上鼠标右击第一个主站，然后点击 “停止轮询”，此时上位机便不会再执行轮询请求操作

![](https://docs.openluat.com/cdn/image/MThings/Air8101_28.png)
