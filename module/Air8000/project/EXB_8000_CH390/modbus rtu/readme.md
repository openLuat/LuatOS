## 演示模块概述

1、main.lua：主程序入口；

2、param_field.lua：RTU 主站应用模块（字段参数方式）；

3、rtu_slave_manage.lua：RTU 从站应用模块（字段参数方式）；

## 演示功能概述

本 demo 演示的核心功能为：

1、将设备的两个485工业接口配置为 modbus RTU 主站和从站模式

2、与从站 1  进行通信

- 对从站 1 进行 2 秒一次的读取保持寄存器 0-1 操作
- 对从站 2 进行 4 秒一次的写入保持寄存器 0-1 操作

注意事项：

1、该示例程序需要搭配 exmodbus 扩展库使用

2、在 main.lua 中 require "param_field" 模块，可以演示标准 modbus RTU 请求报文格式的使用方式

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
        0x01,       -- 从站地址
        0x10,       -- 功能码：写入保持寄存器
        0x00, 0x00, -- 寄存器起始地址
        0x00, 0x02, -- 寄存器数量
        0x04,       -- 字节数量
        0x00, 0x12, -- 寄存器 0 的值
        0x00, 0x34, -- 寄存器 1 的值
        0x52, 0x7D  -- CRC16校验码
    )
    timeout = 1000  -- 超时时间
}
```

如果你需要发送的请求报文是符合 modbus RTU 标准格式，可以使用 字段参数 或者 原始帧 方式

如果你需要发送的请求报文是非标准格式，必须使用 原始帧 方式，使用 字段参数 方式会导致解析的数据不正确

## 演示硬件环境

1、Air8000 开发板一块

2、TYPE-C USB数据线一根

3、三根母对母杜邦线

| 隔离485 | 非隔离485 |
| ------- | --------- |
| A       | A         |
| B       | B         |
| GND     | GND       |

![](https://docs.openluat.com/air8000/luatos/app/image/双网口modbus__rtu.jpg)



## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 V2018 版本](https://docs.openluat.com/air8000/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2018-1 固件对比验证）

## 演示核心步骤

1、搭建硬件环境

- 参考图见 演示硬件环境

3、调整软件代码

- 若需要字段参数方式，打开 require "param_field" ，注释掉 require "raw_frame" 
- 若需要原始帧方式，打开 require "raw_frame" ，注释掉 require "param_field" 

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、开机运行后 Luatools 工具上记录的日志如下：

运行"param_field"文件

```
[2026-05-09 12:35:34.806][000000013.530] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-09 12:35:34.813][000000013.530] I/user.exmodbus_test 读取成功，返回数据:  123, 456
[2026-05-09 12:35:34.816][000000013.534] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-09 12:35:34.821][000000013.534] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-09 12:35:34.823][000000013.538] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-09 12:35:34.824][000000013.539] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
[2026-05-09 12:35:34.827][000000013.539] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  456
[2026-05-09 12:35:34.828][000000013.543] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1 的值
[2026-05-09 12:35:36.823][000000015.543] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
```

运行"raw_frame"文件

```
[2026-05-09 12:37:28.681][000000033.643] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-09 12:37:28.688][000000033.644] I/user.exmodbus_test 读取成功，返回数据:  18, 52
[2026-05-09 12:37:28.694][000000033.647] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 18 ，寄存器 1 数值为 52
[2026-05-09 12:37:28.700][000000033.648] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值
[2026-05-09 12:37:28.707][000000033.652] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-09 12:37:28.713][000000033.652] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  18
[2026-05-09 12:37:28.720][000000033.653] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  52
[2026-05-09 12:37:28.726][000000033.656] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1
[2026-05-09 12:37:30.694][000000035.656] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
```









