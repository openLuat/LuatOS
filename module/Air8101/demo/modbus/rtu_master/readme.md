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



特别说明一：

演示代码使用 Air8101 核心板进行演示

由于 Air8101 核心板不带 485 接口，所以在演示时需要外接 485 转串口模块

演示时使用的 485 转串口模块，模块硬件自动切换方向，不需要软件 io 控制

如果外接的 485 转串口模块的方向引脚连接到了 Air8101 核心板的 GPIO 引脚

则需要在 "param_field" 等其他模块代码中配置 rs485_dir_gpio 为对应的 GPIO 引脚号

同时也需要配置 rs485_dir_rx_level 为 0 或 1，默认为 0



特别说明二：

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

1、Air8101 核心板一块

2、TYPE-C USB数据线一根

3、UART-RS485 串口板

> 此处购买链接仅为推荐，如有问题请直接联系店家

- 购买链接：[裸板3.3-5V供电TTL电平兼容3.3-5V M2铜柱固定](https://item.taobao.com/item.htm?app=chrome&bxsign=scdXlhF10ejv6GI1K5bBXly15Q2huOVUk-H8hGnJMbwSuFKLuiLfWBBCKV_W0XKWwpzVniqvSivBSvcCEu4RZdrZIjE2F8UdRi5IFekvB7zM-0fJXYrHjTB7ccHXHAhG3KV&cpp=1&id=803532080330&price=18&shareUniqueId=34590410848&share_crt_v=1&shareurl=true&short_name=h.7T9Saa9u4QXerkU&skuId=5471217113027&sourceType=item&sp_tk=WkNDZVVhZE1lUEo%3D&spm=a2159r.13376460.0.0&suid=b9adc616-d579-4b37-9a09-0c35a35d9179&tbSocialPopKey=shareItem&tk=ZCCeUadMePJ&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1767146559998.Copy.1&wxsign=tbwhYFjAC-a3R2BDAoFO2r6gHQDtBjNmFT2zOjw54KFizTEcOpblmA7KI6WfBoKdA3R5iIA241AAi5wWpQrUjQ6g9_keE1IsPkHXSpAvPZIXvbrfuAnNCf0GiI0ieRM9Jda)

4、USB-RS485 串口板

> 此处购买链接仅为推荐，如有问题请直接联系店家

- 购买链接：[4路RS-485，TYPEC接口 不含USB线](https://item.taobao.com/item.htm?app=chrome&bxsign=scdJP32y4DuiSo5k5D89Yse5PsbQ6EIYXNIPNkzmMi6zdQszLdrZrUy6-Nw96m51cCA5oz67QzXT9StIYyW8C2WWDa9P6CTUC4Imox3bONGK_FgAw8bQ8lYY0rnL7cRpNsG&cpp=1&id=608773837508&price=2.5&shareUniqueId=34323628624&share_crt_v=1&shareurl=true&short_name=h.7YHZDX57ex5G68h&skuId=5692060399621&sourceType=item&sp_tk=QXZFNGZzdXJGeTg%3D&spm=a2159r.13376460.0.0&suid=97525605-306d-4a26-8181-c6a5e5ac1449&tbSocialPopKey=shareItem&tk=AvE4fsurFy8&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1765329298678.Copy.1&wxsign=tbwqCWYZys39IqYxa6fkQJ4fSCqNnxJegN9tEYlbjtUm1rAZyDddEbbohCLQnFZUojPMaKxNICvdbp1uAgV6d03jf7_X0hLeyUaHbuddZUTcL_y45R5fClnUqq9IfXXAxNG)

5、气体浓度变送器（RS485 版）

> 如果你是小白，建议直接购买同款变送器，由于不同型号的温湿度模块默认的参数也会有所区别

- 购买链接：[空气质量+温湿度+RS485](https://item.taobao.com/item.htm?app=chrome&bxsign=scdFu-qKg8ZXJ1xjQqlalAwji8TFl1rnWrARQlKI_RJiN6UHRZGAJbKyD-u91Id7rHVdhRGgc1Qz_dP3NaVPGvuOvxnqRK8Ue2_4iWjUqc88zgv0p4m-UtvX8C8Oo6ie3zT&cpp=1&id=845163274010&price=40&shareUniqueId=34323863342&share_crt_v=1&shareurl=true&short_name=h.71oGcXUfrc46J83&skuId=5623949684515&sourceType=item&sp_tk=UkoxV2ZzdUJmdVk%3D&spm=a2159r.13376460.0.0&suid=5bc5312a-35fd-42d4-8a70-01d4f0634912&tbSocialPopKey=shareItem&tk=RJ1WfsuBfuY&un=7a6477372f5d73d28011994573a7abfb&un_site=0&ut_sk=1.ZjZmtV%2FpLDkDACz9psyM0ajN_21646297_1765329298678.Copy.1&wxsign=tbwCFryRbuO3rOk8mETON_dt0pgE9dS7hbxK6Bcm0UJlzwzAbizoHUbY78zKnYm0DkkItxxjmYLA-BAD5i3Efxa1_QbpFAksRNHi4GETTmGVBH4KDIUrzeLBSbPiLKvpHsq)

Air8101 与 UART-RS485 串口板接线图如下：

![](https://docs.openluat.com/cdn/image/Air8101_uart-485.png)

UART-RS485 串口板与 USB-RS485 串口板接线图如下：

![](https://docs.openluat.com/cdn/image/uart-485-USB.png)

Air8101 与气体浓度变送器（RS-485 版）接线图如下：

![](https://docs.openluat.com/cdn/image/Air8101_485_1.png)

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/)

2、[Air8101 V2001 版本](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2001 固件对比验证）

> 目前 V2001 正式固件还未发布，可以先用上级目录中临时固件文件夹下的 LuatOS-SoC_V2001_Air8101_20251230_234242.soc 固件进行测试

3、[摩尔信使(MThings)官网](https://www.gulink.cn/)（用于模拟 modbus 从站设备）

## 演示核心步骤

### RTU 主站应用模块（字段参数方式，对应 param_field.lua）

1、搭建硬件环境

- 将 UART-RS485 串口板的 UART 端与 Air8101 核心板进行连接
- 将 UART-RS485 串口板的 RS485 端与 USB-RS485 的 RS485 端进行连接
- 将 USB-RS485 串口板与 Air8101 核心板的 USB 端同时接在电脑上
- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 RTU 从站设备环境

- 点击左上角的 “通道管理”按钮，在 “通道管理” 窗口选择对应的串口（UART-RS485 串口板与 Air8101 核心板进行 485 通信时的端口），点击对应串口后面的 “配置” 按钮，在 “串口参数配置” 窗口配置串口参数（要求与代码中调用 exmodbus.create 接口时填入的配置参数一致），操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/1.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/2.png)

- 点击左侧的第一个从站（我这里显示为 “COM36-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/3.png)

- 点击左侧的第二个从站（我这里显示为 “COM36-002”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/4.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/5.png)

3、调整软件代码

- 打开 require "param_field" ，注释掉 require "raw_frame" 和 require "temp_hum_sensor"，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/modbus/Air8101_1.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2025-12-31 14:39:17.737] luat:U(1416):I/user.main RTU_MASTER 001.000.000
[2025-12-31 14:39:17.783] luat:D(1477):uart:uart(1) tx pin: 0, rx pin: 1
[2025-12-31 14:39:17.785] luat:U(1478):I/user.exmodbus 串口 1 初始化成功，波特率 115200
[2025-12-31 14:39:17.785] luat:U(1478):I/user.exmodbus_test rtu_master 创建成功
[2025-12-31 14:39:17.785] luat:U(1478):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:18.779] luat:U(2483):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-31 14:39:18.779] luat:U(2484):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-31 14:39:19.779] luat:U(3488):I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2025-12-31 14:39:21.798] luat:U(5489):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:22.806] luat:U(6491):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-31 14:39:24.807] luat:U(8492):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:24.855] luat:U(8544):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 14:39:24.855] luat:U(8545):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-31 14:39:24.860] luat:U(8560):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
[2025-12-31 14:39:26.874] luat:U(10560):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:26.882] luat:U(10577):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 14:39:28.889] luat:U(12578):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:28.893] luat:U(12591):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 14:39:28.893] luat:U(12591):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-31 14:39:28.920] luat:U(12608):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
[2025-12-31 14:39:30.917] luat:U(14608):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:30.919] luat:U(14623):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 14:39:32.940] luat:U(16623):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:32.944] luat:U(16640):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 14:39:32.944] luat:U(16640):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-31 14:39:32.948] luat:U(16655):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
```

7、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的串口通道关闭后，此时 Air8101 在发送请求时便会收不到响应，Luatools 工具上显示的日志如下：

![](https://docs.openluat.com/cdn/image/MThings/Air8101_6.png)

```
[2025-12-31 14:39:17.785] luat:U(1478):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:18.779] luat:U(2483):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-31 14:39:18.779] luat:U(2484):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-31 14:39:19.779] luat:U(3488):I/user.exmodbus_test 未收到从站 2 的响应（超时）
```

8、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的串口通道打开后，此时 Air8101 在发送请求时便会接收到响应，Luatools 工具与摩尔信使上显示的日志如下：

![](https://docs.openluat.com/cdn/image/MThings/Air8101_7.png)

```
[2025-12-31 14:39:24.807] luat:U(8492):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 14:39:24.855] luat:U(8544):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 14:39:24.855] luat:U(8545):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2025-12-31 14:39:24.860] luat:U(8560):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
```

![](https://docs.openluat.com/cdn/image/MThings/Air8101_8.png)

9、关于 Air8101 执行读取和写入请求后，摩尔信使上位机的数值变化如下图所示：

![](https://docs.openluat.com/cdn/image/MThings/Air8101_9.png)

![](https://docs.openluat.com/cdn/image/MThings/Air8101_10.png)

### RTU 主站应用模块（原始帧方式，对应 raw_frame.lua）

1、搭建硬件环境

- 将 UART-RS485 串口板的 UART 端与 Air8101 核心板进行连接
- 将 UART-RS485 串口板的 RS485 端与 USB-RS485 的 RS485 端进行连接
- 将 USB-RS485 串口板与 Air8101 核心板的 USB 端同时接在电脑上
- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 RTU 从站设备环境

- 点击左上角的 “通道管理”按钮，在 “通道管理” 窗口选择对应的串口（UART-RS485 串口板与 Air8101 开发板进行 485 通信时的端口），点击对应串口后面的 “配置” 按钮，在 “串口参数配置” 窗口配置串口参数（要求与代码中调用 exmodbus.create 接口时填入的配置参数一致），操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/1.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/2.png)

- 点击左侧的第一个从站（我这里显示为 “COM36-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/3.png)

- 点击左侧的第二个从站（我这里显示为 “COM36-002”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/4.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/MThings/5.png)

3、调整软件代码

- 打开 require "raw_frame" ，注释掉 require "param_field" 和 require "temp_hum_sensor"，操作流程图如下：

  ![](https://docs.openluat.com/cdn/image/modbus/Air8101_2.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2025-12-31 15:00:17.964] luat:U(1418):I/user.main RTU_MASTER 001.000.000
[2025-12-31 15:00:18.026] luat:D(1478):uart:uart(1) tx pin: 0, rx pin: 1
[2025-12-31 15:00:18.026] luat:U(1479):I/user.exmodbus 串口 1 初始化成功，波特率 115200
[2025-12-31 15:00:18.026] luat:U(1479):I/user.exmodbus_test rtu_master 创建成功
[2025-12-31 15:00:18.026] luat:U(1479):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:19.021] luat:U(2484):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-31 15:00:19.021] luat:U(2484):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-31 15:00:20.016] luat:U(3487):I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2025-12-31 15:00:22.036] luat:U(5488):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:23.044] luat:U(6490):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-31 15:00:25.036] luat:U(8491):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:25.044] luat:U(8510):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 15:00:25.044] luat:U(8510):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-31 15:00:25.053] luat:U(8525):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2025-12-31 15:00:27.077] luat:U(10525):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:27.080] luat:U(10541):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 15:00:29.093] luat:U(12541):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:29.096] luat:U(12559):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 15:00:29.096] luat:U(12559):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-31 15:00:29.101] luat:U(12573):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2025-12-31 15:00:31.113] luat:U(14573):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:31.118] luat:U(14589):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 15:00:33.136] luat:U(16589):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:33.140] luat:U(16606):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 15:00:33.140] luat:U(16606):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-31 15:00:33.146] luat:U(16622):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2025-12-31 15:00:35.168] luat:U(18622):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:35.173] luat:U(18640):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
```

7、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的串口通道关闭后，此时 Air8101 在发送请求时便会收不到响应，Luatools 工具上显示的日志如下：

![](https://docs.openluat.com/cdn/image/MThings/Air8101_6.png)

```
[2025-12-31 15:00:18.026] luat:U(1479):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:19.021] luat:U(2484):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2025-12-31 15:00:19.021] luat:U(2484):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-31 15:00:20.016] luat:U(3487):I/user.exmodbus_test 未收到从站 2 的响应（超时）
```

8、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的串口通道打开后，此时 Air8101 在发送请求时便会接收到响应，Luatools 工具与摩尔信使上显示的日志如下：

> 程序设计为每隔 2 秒执行一次读取，每隔 4 秒执行一次写入，在日志上呈现出现就是先执行两次读取再执行一次写入

![](https://docs.openluat.com/cdn/image/MThings/Air8101_7.png)

```
[2025-12-31 15:00:27.077] luat:U(10525):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:27.080] luat:U(10541):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 15:00:29.093] luat:U(12541):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2025-12-31 15:00:29.096] luat:U(12559):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2025-12-31 15:00:29.096] luat:U(12559):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2025-12-31 15:00:29.101] luat:U(12573):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
```

![](https://docs.openluat.com/cdn/image/MThings/Air8101_11.png)

9、关于 Air8101 执行读取和写入请求后，摩尔信使上位机的数值变化如下图所示：

![](https://docs.openluat.com/cdn/image/MThings/Air8101_9.png)

![](https://docs.openluat.com/cdn/image/MThings/Air8101_10.png)

### 485 温湿度传感器读取模块（对应 temp_hum_sensor.lua）

1、搭建硬件环境

- 将气体浓度变送器（RS-485 版）的 '+' 和 '-' 与供电设备（稳压电源等）进行连接，供电范围 8V ~ 36V DC

- 将气体浓度变送器（RS-485 版）与 UART-RS485 串口板的 RS485 端进行连接
- 将 UART-RS485 串口板的 UART 端与 Air8101 核心板进行连接
- 将 Air8101 核心板的 USB 端接在电脑上
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

  ![](https://docs.openluat.com/cdn/image/modbus/Air8101_3.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码，为气体浓度变送器（RS-485 版）进行供电（提前通电也可以）

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2025-12-31 15:11:12.347] luat:U(1269):I/user.main RTU_MASTER 001.000.000
[2025-12-31 15:11:12.394] luat:D(1326):uart:uart(1) tx pin: 0, rx pin: 1
[2025-12-31 15:11:12.394] luat:U(1327):I/user.exmodbus 串口 1 初始化成功，波特率 9600
[2025-12-31 15:11:12.394] luat:U(1327):I/user.temp_hum_sensor RTU 主站创建成功
[2025-12-31 15:11:12.394] luat:U(1327):I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-31 15:11:12.410] luat:U(1357):I/user.temp_hum_sensor 读取成功，温度为 22.200000000000 ℃，湿度为 35.700000000000 %RH
[2025-12-31 15:11:14.432] luat:U(3358):I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-31 15:11:14.462] luat:U(3388):I/user.temp_hum_sensor 读取成功，温度为 22.200000000000 ℃，湿度为 35.800000000000 %RH
[2025-12-31 15:11:16.464] luat:U(5389):I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-31 15:11:16.495] luat:U(5419):I/user.temp_hum_sensor 读取成功，温度为 22.100000000000 ℃，湿度为 35.900000000000 %RH
[2025-12-31 15:11:18.498] luat:U(7420):I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-31 15:11:18.500] luat:U(7449):I/user.temp_hum_sensor 读取成功，温度为 22.000000000000 ℃，湿度为 36.000000000000 %RH
[2025-12-31 15:11:20.521] luat:U(9450):I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-31 15:11:20.552] luat:U(9479):I/user.temp_hum_sensor 读取成功，温度为 21.800000000000 ℃，湿度为 36.300000000000 %RH
[2025-12-31 15:11:22.552] luat:U(11480):I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-31 15:11:22.583] luat:U(11509):I/user.temp_hum_sensor 读取成功，温度为 21.700000000000 ℃，湿度为 36.400000000000 %RH
[2025-12-31 15:11:24.587] luat:U(13510):I/user.temp_hum_sensor 开始读取温湿度传感器数据
[2025-12-31 15:11:24.590] luat:U(13539):I/user.temp_hum_sensor 读取成功，温度为 21.600000000000 ℃，湿度为 36.500000000000 %RH
```
