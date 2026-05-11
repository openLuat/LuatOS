## 演示模块概述

1、main.lua：主程序入口；

2、tcp_slave_manage.lua：TCP 从站应用模块；

3、netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块；

4、param_field：TCP 主站应用模块（字段参数方式）；

5、raw_frame：TCP 主站应用模块（原始帧方式）；

## 演示功能概述

本功能模块演示的内容为：

1、将设备配置为 modbus TCP 1个主站 1个从站的模式

2、等待并且应答主站请求

注意事项：

1、该示例程序需要搭配 exmodbus 扩展库使用

2、在 main.lua 中 require "param_field" 模块，可以演示标准 modbus TCP 请求报文格式的使用方式

3、在 main.lua 中 require "raw_frame" 模块，可以演示非标准 modbus TCP 请求报文格式的使用方式

4、require "param_field" 和 require "raw_frame" 不要同时打开，否则功能会有冲突

特别说明：

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
    slave_id = 1,                         -- 从站地址
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
        0x01,       -- 单元标识符（从站地址）
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

1、EXB_8000W_CH390 开发板一块

2、TYPE-C USB数据线一根

3、网线两根（一根EXB_8000W_CH390 开发板网口1使用，一根EXB_8000W_CH390 开发板网口2使用）

![](https://docs.openluat.com/air8000/luatos/app/image/双网口modbus_tcp.jpg)

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 V2018 版本](https://docs.openluat.com/air8000/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2018-1 固件对比验证）

## 演示核心步骤

1、搭建硬件环境

- 将 TYPE-C USB 数据线一端接在 EXB_8000W_CH390 开发板上，另一端接在电脑上
- 将两根网线分别一端接在 EXB_8000W_CH390 开发板网口1和网口2上，另一端接在路由器/交换机上
- 参考图见 演示硬件环境

2、两个网口的网关和静态ip需要自己在"netdrv_eth_spi.lua"文件下根据实际设置

3、在“param_field”或”raw_frame“文件下create_config参数中修改实际使用的从站ip

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

若需要字段参数方式，打开 require "raw_frame" ，注释掉 require "param_field" 

若需要原始帧方式，打开 require "param_field" ，注释掉 require "raw_frame" 

5、烧录成功后，自动开机运行

6、此时需要等待客户端连接，连接成功后 Luatools 工具上的日志如下：

```
[2026-05-09 10:24:23.653][000000003.567] I/user.exmodbus TCP 从站已启动，监听端口: 6000
```

10、开启轮询后 Luatools 工具的日志如下：

打开 require "raw_frame" ，注释掉 require "param_field" 的运行日志

```
[2026-05-09 10:25:06.397][000000019.723] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-09 10:25:06.404][000000019.723] I/user.exmodbus_test 读取成功，返回数据:  123, 456
[2026-05-09 10:25:06.412][000000019.730] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-09 10:25:08.405][000000021.730] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-09 10:25:08.415][000000021.737] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-09 10:25:08.426][000000021.738] I/user.exmodbus_test 读取成功，返回数据:  123, 456
[2026-05-09 10:25:08.433][000000021.744] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-09 10:25:08.444][000000021.745] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-09 10:25:08.452][000000021.752] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-09 10:25:08.456][000000021.753] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
[2026-05-09 10:25:08.460][000000021.753] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  456
[2026-05-09 10:25:08.464][000000021.760] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1 的值
```

打开 require "param_field" ，注释掉 require "raw_frame" 的运行日志

```
[2026-05-09 10:25:54.196][000000009.608] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值
[2026-05-09 10:25:54.206][000000009.615] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-09 10:25:54.212][000000009.616] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  18
[2026-05-09 10:25:54.221][000000009.616] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  52
[2026-05-09 10:25:54.227][000000009.624] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1
[2026-05-09 10:25:56.183][000000011.625] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-09 10:25:56.189][000000011.631] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-09 10:25:56.194][000000011.632] I/user.exmodbus_test 读取成功，返回数据:  18, 52
[2026-05-09 10:25:56.201][000000011.638] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 18 ，寄存器 1 数值为 52
```

