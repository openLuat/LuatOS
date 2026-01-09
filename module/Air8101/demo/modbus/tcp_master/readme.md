## 演示模块概述

1、main.lua：主程序入口；

2、param_field.lua：TCP 主站应用模块（字段参数方式）；

3、raw_frame.lua：TCP 主站应用模块（原始帧方式）；

4、netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块；

5、netdrv_eth_rmii.lua：“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”驱动模块

## 演示功能概述

本 demo 演示的核心功能为：

1、将设备配置为 modbus TCP 主站模式

2、与从站 1 和 从站 2 进行通信

- 对从站 1 进行 2 秒一次的读取保持寄存器 0-1 操作
- 对从站 2 进行 4 秒一次的写入保持寄存器 0-1 操作



注意事项：

1、该示例程序需要搭配 exmodbus 扩展库使用

2、在 main.lua 中 require "param_field" 模块，可以演示标准 modbus TCP 请求报文格式的使用方式

3、在 main.lua 中 require "raw_frame" 模块，可以演示非标准 modbus TCP 请求报文格式的使用方式

4、require "param_field" 和 require "raw_frame" 不要同时打开，否则功能会有冲突



特别说明一：

1、示例代码中配置了两种以太网卡

2、在 main.lua 中 require "netdrv_eth_rmii" 模块，使用的是“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”

3、在 main.lua 中 require "netdrv_eth_spi" 模块，使用的是“通过SPI外挂CH390H芯片的以太网卡”

4、require "netdrv_eth_rmii" 和 require "netdrv_eth_spi" 不要同时打开，否则会导致功能冲突



特别说明二：

关于 TCP 报文，exmodbus 扩展库支持通过 字段参数 或 原始帧 两种方式进行配置

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

```lua
-- 读取请求：
local config = {
    raw_request = string.char(
        0x00, 0x01, -- 事务标识符
        0x00, 0x00, -- 协议标识符
        0x00, 0x06, -- 长度
        0x01,       -- 单元标识符（从站地址）
        0x03,       -- 功能码：读取保持寄存器
        0x00, 0x00, -- 寄存器起始地址
        0x00, 0x02  -- 寄存器数量
    ),
    timeout = 1000  -- 超时时间 1000 ms
}

-- 写入请求：
local config = {
    raw_request = string.char(
        0x00, 0x02, -- 事务标识符
        0x00, 0x00, -- 协议标识符
        0x00, 0x0B, -- 长度
        0x02,       -- 单元标识符（从站地址）
        0x10,       -- 功能码：写入保持寄存器
        0x00, 0x00, -- 寄存器起始地址
        0x00, 0x02, -- 寄存器数量
        0x04,       -- 字节数量
        0x00, 0x12, -- 寄存器 0 的值
        0x00, 0x34  -- 寄存器 1 的值
    ),
    timeout = 1000  -- 超时时间 1000 ms
}
```

如果你需要发送的请求报文是符合 modbus TCP 标准格式，可以使用 字段参数 或者 原始帧 方式

如果你需要发送的请求报文是非标准格式，必须使用 原始帧 方式，使用 字段参数 方式会导致解析的数据不正确

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

3、[摩尔信使(MThings)官网](https://www.gulink.cn/)（用于模拟 modbus 从站设备）

## 演示核心步骤

### TCP 主站应用模块（字段参数方式，对应 param_field.lua）

1、搭建硬件环境

- 将 TYPE-C USB 数据线一端接在 Air8101 核心板上，另一端接在电脑上
- 将 AirPHY_1000 或 AirETH_1000 配件板与 Air8101 核心板相连接，网线接在配件板网口上，另一端接在路由器/交换机上

- 将另一根网线一端接在电脑网口上，另一端接在同一个路由器/交换机上

- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 TCP 从站设备环境

- 点击左上角的 “通道管理” 按钮，在 “通道管理” 窗口点击 “网络通道” 按钮，点击 NET000 通道后面的 “配置” 按钮，在 “网络参数配置” 窗口配置网络参数，操作流程如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/41.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/42.png)

- 点击左侧的第一个从站（我这里显示为 “NET000-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/43.png)

- 点击左侧的第二个从站（我这里显示为 “NET000-002”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/44.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/45.png)

3、调整软件代码

- 打开 require "param_field" ，注释掉 require "raw_frame" ，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/modbus/Air8101_4.png)
  
- 在 ”param_field.lua“ 文件中修改对应的 IP 地址和端口号（与上位机保持一致）

  ![img](https://docs.openluat.com/cdn/image/modbus/Air8101_6.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2026-01-04 16:41:21.280] luat:U(18777):I/user.exmodbus 连接服务器成功
[2026-01-04 16:41:22.294] luat:U(19784):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:22.294] luat:U(19791):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:24.284] luat:U(21792):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:24.284] luat:U(21799):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:24.296] luat:U(21800):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:24.296] luat:U(21807):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
[2026-01-04 16:41:26.306] luat:U(23807):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:26.306] luat:U(23816):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:28.329] luat:U(25817):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:28.329] luat:U(25823):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:28.329] luat:U(25824):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:28.329] luat:U(25830):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
[2026-01-04 16:41:28.812] luat:U(26307):I/user.exmodbus 连接断开
[2026-01-04 16:41:30.333] luat:U(27830):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:30.333] luat:U(27831):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:30.333] luat:U(27832):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 16:41:32.334] luat:U(29832):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:32.334] luat:U(29833):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:32.334] luat:U(29834):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 16:41:32.334] luat:U(29834):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:32.334] luat:U(29835):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:32.334] luat:U(29836):I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2026-01-04 16:41:33.820] luat:D(31310):socket:connect to 192.168.1.100,6000
[2026-01-04 16:41:33.820] luat:D(31311):net:adapter 4 connect 192.168.1.100:6000 TCP
[2026-01-04 16:41:34.349] luat:U(31836):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:34.349] luat:U(31837):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:34.349] luat:U(31838):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 16:41:36.349] luat:U(33838):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:36.349] luat:U(33839):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:36.349] luat:U(33840):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 16:41:36.349] luat:U(33840):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:36.349] luat:U(33841):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:36.349] luat:U(33842):I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2026-01-04 16:41:38.018] luat:U(35512):I/user.exmodbus 连接服务器成功
[2026-01-04 16:41:38.345] luat:U(35842):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:38.352] luat:U(35849):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:40.349] luat:U(37850):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:40.352] luat:U(37858):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:40.352] luat:U(37859):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:40.352] luat:U(37864):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
[2026-01-04 16:41:42.362] luat:U(39865):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:42.371] luat:U(39874):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:44.389] luat:U(41875):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:44.389] luat:U(41882):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:44.389] luat:U(41883):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:44.389] luat:U(41890):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
[2026-01-04 16:41:46.382] luat:U(43890):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:46.382] luat:U(43897):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
```

7、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的网络通道关闭后，此时 Air8101 在发送请求时便会收不到响应，Luatools 工具上显示的日志如下：

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_46.png)

```
[2026-01-04 16:41:28.812] luat:U(26307):I/user.exmodbus 连接断开
[2026-01-04 16:41:30.333] luat:U(27830):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:30.333] luat:U(27831):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:30.333] luat:U(27832):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 16:41:32.334] luat:U(29832):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:32.334] luat:U(29833):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:32.334] luat:U(29834):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 16:41:32.334] luat:U(29834):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:32.334] luat:U(29835):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 16:41:32.334] luat:U(29836):I/user.exmodbus_test 未收到从站 2 的响应（超时）
```

8、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的网络通道打开后，此时 Air8101 在发送请求时便会接收到响应，Luatools 工具与摩尔信使上显示的日志如下：

> 程序设计为每隔 2 秒执行一次读取，每隔 4 秒执行一次写入

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_47.png)

```
[2026-01-04 16:41:38.018] luat:U(35512):I/user.exmodbus 连接服务器成功
[2026-01-04 16:41:38.345] luat:U(35842):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:38.352] luat:U(35849):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:40.349] luat:U(37850):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 16:41:40.352] luat:U(37858):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 16:41:40.352] luat:U(37859):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-01-04 16:41:40.352] luat:U(37864):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1 的值
```

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_48.png)

9、关于 Air8101 执行读取和写入请求后，摩尔信使上位机的数值变化如下图所示：

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_49.png)

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_50.png)

### TCP 主站应用模块（原始帧方式，对应 raw_frame.lua）

1、搭建硬件环境

- 将 TYPE-C USB 数据线一端接在 Air8101 核心板上，另一端接在电脑上
- 将 AirPHY_1000 或 AirETH_1000 配件板与 Air8101 核心板相连接，网线接在配件板网口上，另一端接在路由器/交换机上

- 将另一根网线一端接在电脑网口上，另一端接在同一个路由器/交换机上

- 参考图见 演示硬件环境

2、在摩尔信使上配置模拟 TCP 从站设备环境

- 点击左上角的 “通道管理” 按钮，在 “通道管理” 窗口点击 “网络通道” 按钮，点击 NET000 通道后面的 “配置” 按钮，在 “网络参数配置” 窗口配置网络参数，操作流程如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/41.png)

- 点击左上角的 “添加设备”按钮，在 “添加设备” 窗口对通信设备参数进行配置，配置好后点击 “添加” 按钮，左侧栏即为添加后的效果，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/42.png)

- 点击左侧的第一个从站（我这里显示为 “NET000-001”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/43.png)

- 点击左侧的第二个从站（我这里显示为 “NET000-002”），点击中上部分的 “新增数据” 按钮，在 “新增数据配置” 窗口将 “数据条数” 、“区块” 、“起始数据地址” 按照下图中所示进行配置，最后点击 “确定” 按钮，此时便成功新增保持寄存器 0 和 保持寄存器 1，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/44.png)

- 此时在摩尔信使上的配置操作已经完成，如果需要在摩尔信使上查看报文，那么操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/MThings/45.png)

3、调整软件代码

- 打开 require "raw_frame" ，注释掉 require "param_field" ，操作流程图如下：

  ![img](https://docs.openluat.com/cdn/image/modbus/Air8101_5.png)
  
- 在 ”raw_frame.lua“ 文件中修改对应的 IP 地址和端口号（与上位机保持一致）

  ![img](https://docs.openluat.com/cdn/image/modbus/Air8101_7.png)

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

```
[2026-01-04 17:11:37.408] luat:U(12264):I/user.exmodbus 连接服务器成功
[2026-01-04 17:11:39.095] luat:U(13942):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:39.095] luat:U(13949):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:39.095] luat:U(13950):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:39.109] luat:U(13957):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2026-01-04 17:11:41.104] luat:U(15957):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:41.107] luat:U(15962):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:43.122] luat:U(17963):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:43.122] luat:U(17972):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:43.122] luat:U(17972):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:43.147] luat:U(17978):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2026-01-04 17:11:45.124] luat:U(19978):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:45.127] luat:U(19983):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:45.992] luat:U(20839):I/user.exmodbus 连接断开
[2026-01-04 17:11:47.134] luat:U(21984):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:47.134] luat:U(21985):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:47.134] luat:U(21985):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 17:11:47.134] luat:U(21985):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:47.156] luat:U(21986):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:47.156] luat:U(21987):I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2026-01-04 17:11:49.131] luat:U(23987):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:49.131] luat:U(23987):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:49.131] luat:U(23988):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 17:11:50.999] luat:D(25842):socket:connect to 192.168.1.100,6000
[2026-01-04 17:11:50.999] luat:D(25843):net:adapter 4 connect 192.168.1.100:6000 TCP
[2026-01-04 17:11:51.126] luat:U(25988):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:51.126] luat:U(25989):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:51.126] luat:U(25989):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 17:11:51.126] luat:U(25990):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:51.126] luat:U(25990):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:51.126] luat:U(25991):I/user.exmodbus_test 未收到从站 2 的响应（超时）
[2026-01-04 17:11:53.150] luat:U(27991):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:53.150] luat:U(27992):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:53.150] luat:U(27992):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 17:11:53.792] luat:U(28645):I/user.exmodbus 连接服务器成功
[2026-01-04 17:11:55.147] luat:U(29992):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:55.147] luat:U(29999):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:55.147] luat:U(29999):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:55.169] luat:U(30009):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2026-01-04 17:11:57.167] luat:U(32009):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:57.167] luat:U(32016):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:59.176] luat:U(34017):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:59.176] luat:U(34023):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:59.176] luat:U(34023):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:59.176] luat:U(34029):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
[2026-01-04 17:12:01.167] luat:U(36029):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:12:01.167] luat:U(36035):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
```

7、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的网络通道关闭后，此时 Air8101 在发送请求时便会收不到响应，Luatools 工具上显示的日志如下：

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_46.png)

```
[2026-01-04 17:11:45.992] luat:U(20839):I/user.exmodbus 连接断开
[2026-01-04 17:11:47.134] luat:U(21984):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:47.134] luat:U(21985):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:47.134] luat:U(21985):I/user.exmodbus_test 未收到从站 1 的响应（超时）
[2026-01-04 17:11:47.134] luat:U(21985):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:47.156] luat:U(21986):E/user.exmodbus TCP 连接未建立或已断开，无法发送请求
[2026-01-04 17:11:47.156] luat:U(21987):I/user.exmodbus_test 未收到从站 2 的响应（超时）
```

8、如下图所示，鼠标右键点击 “通道” 下方的按钮，当我们把摩尔信使上由上位机与 Air8101 之间的网络通道打开后，此时 Air8101 在发送请求时便会接收到响应，Luatools 工具与摩尔信使上显示的日志如下：

> 程序设计为每隔 2 秒执行一次读取，每隔 4 秒执行一次写入

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_47.png)

```
[2026-01-04 17:11:53.792] luat:U(28645):I/user.exmodbus 连接服务器成功
[2026-01-04 17:11:55.147] luat:U(29992):I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-01-04 17:11:55.147] luat:U(29999):I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 0 ，寄存器 1 数值为 0
[2026-01-04 17:11:55.147] luat:U(29999):I/user.exmodbus_test 开始写入从站 2 保持寄存器 0-1 的值
[2026-01-04 17:11:55.169] luat:U(30009):I/user.exmodbus_test 成功写入从站 2 保持寄存器 0-1
```

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_48.png)

9、关于 Air8101 执行读取和写入请求后，摩尔信使上位机的数值变化如下图所示：

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_49.png)

![img](https://docs.openluat.com/cdn/image/MThings/Air8101_50.png)