## 演示模块概述

1、main.lua：主程序入口；

2、param_field.lua：RTU 主站应用模块（字段参数方式）；

3、raw_frame.lua：RTU 主站应用模块（原始帧方式）；

4、temp_hum_sensor.lua：485温湿度传感器读取模块；

## 演示功能概述

本 demo 演示的核心功能为：

1、将设备配置为 modbus RTU 主站模式

2、与从站 1 和 从站 2 进行通信

- 对从站 1 进行 2 秒一次的读取保持寄存器 0-1 操作
- 对从站 2 进行 4 秒一次的写入保持寄存器 0-1 操作

3、读取温湿度传感器数据

- 配置 modbus RTU 主站，读取温湿度传感器数据
- 每 2 秒读取一次传感器数据并解析温度和湿度值



注意事项：

1、该示例程序需要搭配 exmodbus 扩展库使用

2、在 main.lua 中 require "param_field" 模块，可以演示标准 modbus RTU 请求报文格式的使用方式

3、在 main.lua 中 require "raw_frame" 模块，可以演示非标准 modbus RTU 请求报文格式的使用方式

4、在 main.lua 中 require "temp_hum_sensor" 模块，可以演示读取485温湿度传感器数值的使用方式

5、require "param_field"、require "raw_frame" 和 require "temp_hum_sensor"，不要同时打开，否则功能会有冲突



特别说明：

关于 RTU 报文，exmodbus 扩展库支持通过 字段参数 或 原始帧 两种方式进行配置

这两种配置方式本质都由用户将其放入 table 中在调用接口时传入，区别如下：

1、字段参数方式

这种方式需要用户将请求报文进行解析后，将其放入 table 中，例如：

```lua
-- 读取请求：
local config = {
    slave_id = 1,                         -- 从站地址
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x0000,                  -- 寄存器起始地址
    reg_count = 0x0002,                   -- 寄存器数量
    timeout = 1000                        -- 超时时间
}

-- 写入请求：
local config = {
    slave_id = 2,                         -- 从站地址
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x0000,                  -- 寄存器起始地址
    reg_count = 0x0002,                   -- 寄存器数量
    data = {
        [start_addr] = 0x0012,            -- 寄存器 0 的值
        [start_addr + 1] = 0x0034,        -- 寄存器 1 的值
    }
    force_multiple = true, -- 是否强制使用多个寄存器写入操作（写多个线圈功能码：0x0F；写多个寄存器功能码：0x10）
    timeout = 1000                        -- 超时时间
}
```

2、原始帧方式

这种方式只需要用户将原始请求报文放入 table 中，例如：

```Lua
-- 读取请求：
local config = {
    raw_request = string.char(
        0x01,       -- 从站地址
        0x03,       -- 功能码：读取保持寄存器
        0x00, 0x00, -- 寄存器起始地址
        0x00, 0x02, -- 寄存器数量
        0xC4, 0x0B  -- CRC16校验码
    )
    timeout = 1000  -- 超时时间
}

-- 写入请求：
local config = {
    raw_request = string.char(
        0x02,       -- 从站地址
        0x10,       -- 功能码：写入保持寄存器
        0x00, 0x00, -- 寄存器起始地址
        0x00, 0x02, -- 寄存器数量
        0x04,       -- 字节数量
        0x00, 0x12, -- 寄存器 0 的值
        0x00, 0x34, -- 寄存器 1 的值
        0x5D, 0x39  -- CRC16校验码
    )
    timeout = 1000  -- 超时时间
}
```

如果你需要发送的请求报文是符合 modbus RTU 标准格式，可以使用 字段参数 或者 原始帧 方式

如果你需要发送的请求报文是非标准格式，必须使用 原始帧 方式，使用 字段参数 方式会导致解析的数据不正确

## 演示硬件环境

1、Air780EPM 开发板一块

2、TYPE-C USB数据线一根

3、USB-RS485 串口板

> 此处购买链接仅为推荐，如有问题请直接联系店家

- 购买链接：[4路RS-485，TYPEC接口 不含USB线](https://item.taobao.com/item.htm?app=chrome&bxsign=scdJP32y4DuiSo5k5D89Yse5PsbQ6EIYXNIPNkzmMi6zdQszLdrZrUy6-Nw96m51cCA5oz67QzXT9StIYyW8C2WWDa9P6CTUC4Imox3bONGK_FgAw8bQ8lYY0rnL7cRpNsG&cpp=1&id=608773837508&price=2.5&shareUniqueId=34323628624&share_crt_v=1&shareurl=true&short_name=h.7YHZDX57ex5G68h&skuId=5692060399621&sourceType=item&sp_tk=QXZFNGZzdXJGeTg%3D&spm=a2159r.13376460.0.0&suid=97525605-306d-4a26-8181-c6a5e5ac1449&tbSocialPopKey=shareItem&tk=AvE4fsurFy8&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1765329298678.Copy.1&wxsign=tbwqCWYZys39IqYxa6fkQJ4fSCqNnxJegN9tEYlbjtUm1rAZyDddEbbohCLQnFZUojPMaKxNICvdbp1uAgV6d03jf7_X0hLeyUaHbuddZUTcL_y45R5fClnUqq9IfXXAxNG)

4、气体浓度变送器（RS485 版）

> 如果你是小白，建议直接购买同款变送器，由于不同型号的温湿度模块默认的参数也会有所区别

- 购买链接：[空气质量+温湿度+RS485](https://item.taobao.com/item.htm?app=chrome&bxsign=scdFu-qKg8ZXJ1xjQqlalAwji8TFl1rnWrARQlKI_RJiN6UHRZGAJbKyD-u91Id7rHVdhRGgc1Qz_dP3NaVPGvuOvxnqRK8Ue2_4iWjUqc88zgv0p4m-UtvX8C8Oo6ie3zT&cpp=1&id=845163274010&price=40&shareUniqueId=34323863342&share_crt_v=1&shareurl=true&short_name=h.71oGcXUfrc46J83&skuId=5623949684515&sourceType=item&sp_tk=UkoxV2ZzdUJmdVk%3D&spm=a2159r.13376460.0.0&suid=5bc5312a-35fd-42d4-8a70-01d4f0634912&tbSocialPopKey=shareItem&tk=RJ1WfsuBfuY&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1765329298678.Copy.1&wxsign=tbwCFryRbuO3rOk8mETON_dt0pgE9dS7hbxK6Bcm0UJlzwzAbizoHUbY78zKnYm0DkkItxxjmYLA-BAD5i3Efxa1_QbpFAksRNHi4GETTmGVBH4KDIUrzeLBSbPiLKvpHsq)

Air780EPM 与 USB-RS485 串口板接线图如下：

![](https://docs.openluat.com/cdn/image/Air780EPM_rs485.png)

Air780EPM 与气体浓度变送器（RS-485 版）接线图如下：

![](https://docs.openluat.com/cdn/image/Air780EPM_RS485.jpg)

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/)

2、[Air780EPM V2018 版本](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2018-1 固件对比验证）

3、[摩尔信使(MThings)官网](https://www.gulink.cn/)（用于模拟 modbus 从站设备）

## 演示核心步骤

### RTU 主站应用模块（字段参数方式，对应 param_field.lua）

1、搭建硬件环境

- 将 USB-RS485 串口板与 Air780EPM 开发板进行连接
- 将 USB-RS485 串口板 与 Air780EPM 开发板的 USB 端同时接在电脑上
- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 RTU 从站设备环境

- 点击左上角的 “通道管理”按钮，在 “通道管理” 窗口选择对应的串口（USB-RS485 串口板与 Air780EPM 开发板进行 485 通信时的端口），点击对应串口后面的 “配置” 按钮，在 “串口参数配置” 窗口配置串口参数（要求与代码中调用 exmodbus.create 接口时填入的配置参数一致），操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_1.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_2.png)

- 点击左侧的第一个从站（我这里显示为 “COM36-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_3.png)

- 点击左侧的第二个从站（我这里显示为 “COM36-002”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_4.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_5.png)

3、调整软件代码

- 打开 require "param_field" ，注释掉 require "raw_frame" 和 require "temp_hum_sensor"，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/modbus/Air780EPM_1.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2025-12-29 10:08:32.083][000000000.320] I/user.main RTU_MASTER 001.000.000
[2025-12-29 10:08:32.089][000000000.347] Uart_ChangeBR 1338:uart1, 115200 115203 26000000 3611
[2025-12-29 10:08:32.111][000000000.348] I/user.exmodbus 串口 1 初始化成功，波特率 115200
[2025-12-29 10:08:32.120][000000000.348] I/user.exmodbus_test rtu_master 创建成功
[2025-12-29 10:08:32.129][000000000.349] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:32.367][000000001.353] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:08:32.532][000000001.354] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-29 10:08:33.206][000000002.358] I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2025-12-29 10:08:35.210][000000004.359] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:36.199][000000005.362] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:08:38.199][000000007.363] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:39.212][000000008.366] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:08:39.216][000000008.367] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-29 10:08:40.210][000000009.370] I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2025-12-29 10:08:42.206][000000011.371] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:43.211][000000012.374] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:08:45.212][000000014.375] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:45.228][000000014.390] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:08:45.231][000000014.390] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-29 10:08:45.260][000000014.403] I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:08:47.251][000000016.403] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:47.264][000000016.422] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:08:49.270][000000018.423] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:49.276][000000018.436] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:08:49.281][000000018.437] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-29 10:08:49.293][000000018.452] I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
```

7、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air780EPM 之间的串口通道关闭后，此时 Air780EPM 在发送请求时便会收不到响应，Luatools 工具上显示的日志如下：

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_6.png)

```
[2025-12-29 10:08:32.129][000000000.349] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:32.367][000000001.353] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:08:32.532][000000001.354] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-29 10:08:33.206][000000002.358] I/user.exmodbus_test 未收到从站 2 的响应（超时）
```

8、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air780EPM 之间的串口通道打开后，此时 Air780EPM 在发送请求时便会接收到响应，Luatools 工具与摩尔信使上显示的日志如下：

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_7.png)

```
[2025-12-29 10:08:45.212][000000014.375] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:08:45.228][000000014.390] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:08:45.231][000000014.390] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-29 10:08:45.260][000000014.403] I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
```

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_8.png)

9、关于 Air780EPM 执行读取和写入请求后，摩尔信使上位机的数值变化如下图所示：

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_9.png)

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_10.png)

### RTU 主站应用模块（原始帧方式，对应 raw_frame.lua）

1、搭建硬件环境

- 将 USB-RS485 串口板与 Air780EPM 开发板进行连接
- 将 USB-RS485 串口板 与 Air780EPM 开发板的 USB 端同时接在电脑上
- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 RTU 从站设备环境

- 点击左上角的 “通道管理”按钮，在 “通道管理” 窗口选择对应的串口（USB-RS485 串口板与 Air780EPM 开发板进行 485 通信时的端口），点击对应串口后面的 “配置” 按钮，在 “串口参数配置” 窗口配置串口参数（要求与代码中调用 exmodbus.create 接口时填入的配置参数一致），操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_1.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_2.png)

- 点击左侧的第一个从站（我这里显示为 “COM36-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_3.png)

- 点击左侧的第二个从站（我这里显示为 “COM36-002”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_4.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_5.png)

3、调整软件代码

- 打开 require "raw_frame" ，注释掉 require "param_field" 和 require "temp_hum_sensor"，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/modbus/Air780EPM_2.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2025-12-29 10:23:51.883][000000000.320] I/user.main RTU_MASTER 001.000.000
[2025-12-29 10:23:51.884][000000000.349] Uart_ChangeBR 1338:uart1, 115200 115203 26000000 3611
[2025-12-29 10:23:51.885][000000000.350] I/user.exmodbus 串口 1 初始化成功，波特率 115200
[2025-12-29 10:23:51.886][000000000.350] I/user.exmodbus_test rtu_master 创建成功
[2025-12-29 10:23:51.887][000000000.351] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:23:52.540][000000001.354] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:23:52.554][000000001.355] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:23:53.532][000000002.359] I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2025-12-29 10:23:55.541][000000004.360] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:23:56.542][000000005.362] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:23:58.546][000000007.363] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:23:59.539][000000008.366] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:23:59.540][000000008.367] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:24:00.553][000000009.370] I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2025-12-29 10:24:02.556][000000011.371] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:03.547][000000012.374] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:24:05.557][000000014.375] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:05.561][000000014.388] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:24:05.565][000000014.389] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:24:05.588][000000014.404] I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2025-12-29 10:24:07.576][000000016.405] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:07.609][000000016.422] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:24:09.607][000000018.422] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:09.611][000000018.436] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:24:09.614][000000018.437] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:24:09.639][000000018.452] I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2025-12-29 10:24:11.634][000000020.453] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:11.649][000000020.468] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:24:13.653][000000022.468] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:13.656][000000022.485] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:24:13.659][000000022.485] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:24:13.684][000000022.500] I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
```

7、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air780EPM 之间的串口通道关闭后，此时 Air780EPM 在发送请求时便会收不到响应，Luatools 工具上显示的日志如下：

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_6.png)

```
[2025-12-29 10:23:51.887][000000000.351] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:23:52.540][000000001.354] I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-29 10:23:52.554][000000001.355] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:23:53.532][000000002.359] I/user.exmodbus_test 未收到从站 2 的响应（超时）
```

8、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air780EPM 之间的串口通道打开后，此时 Air780EPM 在发送请求时便会接收到响应，Luatools 工具与摩尔信使上显示的日志如下：

> 程序设计为每隔 2 秒执行一次读取，每隔 4 秒执行一次写入，在日志上呈现出现就是先执行两次读取再执行一次写入

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_7.png)

```
[2025-12-29 10:24:11.634][000000020.453] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:11.649][000000020.468] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:24:13.653][000000022.468] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-29 10:24:13.656][000000022.485] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-29 10:24:13.659][000000022.485] I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-29 10:24:13.684][000000022.500] I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
```

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_11.png)

9、关于 Air780EPM 执行读取和写入请求后，摩尔信使上位机的数值变化如下图所示：

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_9.png)

![](https://docs.openluat.com/cdn/image/MThings/Air780EPM_10.png)

### 485 温湿度传感器读取模块（对应 temp_hum_sensor.lua）

1、搭建硬件环境

- 将气体浓度变送器（RS-485 版）的 '+' 和 '-' 与供电设备（稳压电源等）进行连接，供电范围 8V ~ 36V DC

- 将气体浓度变送器（RS-485 版）与 Air780EPM 开发板进行连接
- 将 Air780EPM 开发板的 USB 端接在电脑上
- 参考图见 演示硬件环境

2、了解气体浓度变送器（RS-485 版）

- 该变送器模块上电后默认输出数据，从站地址默认为 1，波特率默认为 9600
- 温度传感器数值通过保持寄存器地址 0x001E 输出，输出数据为 16 位有符号整数（-0x7FFF ~ +0x7FFF），
  - 数据范围为 -40℃ ~ +85℃，分辨率为 0.1℃
  - 注：寄存器值为 235，实际温度值为 235 * 0.1 = 23.5
- 湿度传感器对应保持寄存器地址 0x001F 输出，输出数据为 16 位无符号整数（0 ~ 0xFFFF）
  - 数据范围为 0%RH ~ 85%RH，分辨率为 0.1%RH
  - 注：寄存器值为 653，实际湿度值为 653 * 0.1 = 65.3

3、调整软件代码

- 打开 require "temp_hum_sensor" ，注释掉 require "raw_frame" 和 require "param_field" ，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/modbus/Air780EPM_3.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码，为气体浓度变送器（RS-485 版）进行供电（提前通电也可以）

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2025-12-29 10:32:29.548][000000000.201] I/user.main RTU_MASTER 001.000.000
[2025-12-29 10:32:29.550][000000000.230] Uart_ChangeBR 1338:uart1, 9600 9600 26000000 43333
[2025-12-29 10:32:29.552][000000000.231] I/user.exmodbus 串口 1 初始化成功，波特率 9600
[2025-12-29 10:32:29.554][000000000.231] I/user.temp_hum_sensor RTU 主站创建成功
[2025-12-29 10:32:29.555][000000000.231] I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-29 10:32:29.563][000000000.260] I/user.temp_hum_sensor 读取成功，温度为 15.80000 ℃，湿度为 48.90000 %RH
[2025-12-29 10:32:31.011][000000002.260] I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-29 10:32:31.042][000000002.289] I/user.temp_hum_sensor 读取成功，温度为 15.70000 ℃，湿度为 48.90000 %RH
[2025-12-29 10:32:33.049][000000004.289] I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-29 10:32:33.080][000000004.317] I/user.temp_hum_sensor 读取成功，温度为 15.60000 ℃，湿度为 49.10000 %RH
[2025-12-29 10:32:35.077][000000006.318] I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-29 10:32:35.093][000000006.346] I/user.temp_hum_sensor 读取成功，温度为 15.40000 ℃，湿度为 49.30000 %RH
[2025-12-29 10:32:37.104][000000008.347] I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-29 10:32:37.134][000000008.376] I/user.temp_hum_sensor 读取成功，温度为 15.40000 ℃，湿度为 49.30000 %RH
[2025-12-29 10:32:39.121][000000010.376] I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-29 10:32:39.151][000000010.405] I/user.temp_hum_sensor 读取成功，温度为 15.50000 ℃，湿度为 49.40000 %RH
[2025-12-29 10:32:41.163][000000012.405] I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-29 10:32:41.195][000000012.433] I/user.temp_hum_sensor 读取成功，温度为 15.50000 ℃，湿度为 49.40000 %RH
```
