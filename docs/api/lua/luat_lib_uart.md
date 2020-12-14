---
module: uart
summary: 串口操作库
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# uart.setup

```lua
uart.setup(id, baud_rate, data_bits, stop_bits, partiy, bit_order, buff_size)
```

配置串口参数

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 串口id, uart0写0, uart1写1
`baud_rate`|`int`| 波特率 9600~115200
`data_bits`|`int`| 数据位 7或8, 一般是8
`stop_bits`|`int`| 停止位 1或0, 一般是1
`partiy`|`int`| 校验位, 可选 uart.None/uart.Even/uart.Odd
`bit_order`|`int`| 大小端, 默认小端 uart.LSB, 可选 uart.MSB
`buff_size`|`int`| 缓冲区大小, 默认值1024

## 返回值

> `int`: 成功返回0,失败返回其他值

## 调用示例

```lua
-- 最常用115200 8N1
-- 可以简写为 uart.setup(1)
uart.setup(1, 115200, 8, 1, uart.NONE)
-------------------------
-- 最常用115200 8N1
-- 可以简写为 uart.setup(1)
uart.setup(1, 115200, 8, 1, uart.NONE)
```


--------------------------------------------------
# uart.write

```lua
uart.write(id, data)
```

写串口

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 串口id, uart0写0, uart1写1
`data`|`string`| 待写入的数据

## 返回值

> `int`: 成功的数据长度

## 调用示例

```lua
-- 
uart.write(1, "rdy\r\n")
```


--------------------------------------------------
# uart.read

```lua
uart.read(id, len, ?)
```

读串口

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 串口id, uart0写0, uart1写1
`len`|`int`| 读取长度
`?`|`int`| 文件句柄(可选)

## 返回值

> `string`: 读取到的数据

## 调用示例

```lua
-- 
uart.read(1, 16)
```


--------------------------------------------------
# uart.close

```lua
uart.close(id)
```

关闭串口

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 串口id, uart0写0, uart1写1

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
uart.close(1)
```


--------------------------------------------------
# uart.on

```lua
uart.on(id, event, func)
```

注册串口事件回调

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 串口id, uart0写0, uart1写1
`event`|`string`| 事件名称
`func`|`function`| 回调方法

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
uart.on("receive", function(id, len)
    local data = uart.read(id, len)
    log.info("uart", id, len, data)
end)
```


