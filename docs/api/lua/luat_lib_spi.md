---
module: spi
summary: spi操作库
version: 1.0
date: 2020.04.23
---

--------------------------------------------------
# spi.setup

```lua
spi.setup(id, cs, CPHA, CPOL, dataw, bandrate, bitdict, ms, mode)
```

设置并启用SPI

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| SPI号,例如0
`cs`|`int`| CS 片选脚,暂不可用,请填nil
`CPHA`|`int`| CPHA 默认0,可选0/1
`CPOL`|`int`| CPOL 默认0,可选0/1
`dataw`|`int`| 数据宽度,默认8bit
`bandrate`|`int`| 波特率,默认2M=2000000
`bitdict`|`int`| 大小端, 默认spi.MSB, 可选spi.LSB
`ms`|`int`| 主从设置, 默认主1, 可选从机0. 通常只支持主机模式
`mode`|`int`| 工作模式, 全双工1, 半双工0, 默认全双工

## 返回值

> `int`: 成功返回0,否则返回其他值


--------------------------------------------------
# spi.close

```lua
spi.close(id)
```

关闭指定的SPI

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| SPI号,例如0

## 返回值

> `int`: 成功返回0,否则返回其他值


--------------------------------------------------
# spi.transfer

```lua
spi.transfer(id, send_data)
```

传输SPI数据

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| SPI号,例如0
`send_data`|`string`| 待发送的数据

## 返回值

> `string`: 读取成功返回字符串,否则返回nil


--------------------------------------------------
# spi.recv

```lua
spi.recv(id, size)
```

接收指定长度的SPI数据

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| SPI号,例如0
`size`|`int`| 数据长度

## 返回值

> `string`: 读取成功返回字符串,否则返回nil


--------------------------------------------------
# spi.send

```lua
spi.send(id, data)
```

发送SPI数据

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| SPI号,例如0
`data`|`string`| 待发送的数据

## 返回值

> `int`: 发送结果


