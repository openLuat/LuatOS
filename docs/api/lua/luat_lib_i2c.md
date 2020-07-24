---
module: i2c
summary: I2C操作
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# i2c.exist

```lua
i2c.exist(id)
```

i2c编号是否存在

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 设备id, 例如i2c1的id为1, i2c2的id为2

## 返回值

> `int`: 存在就返回1,否则返回0

## 调用示例

```lua
-- 检查i2c1是否存在
if i2c.exist(1) then
    log.info("存在 i2c1")
end
```


--------------------------------------------------
# i2c.setup

```lua
i2c.setup(id)
```

i2c初始化

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 设备id, 例如i2c1的id为1, i2c2的id为2

## 返回值

> `int`: 成功就返回1,否则返回0

## 调用示例

```lua
-- 初始化i2c1
if i2c.setup(1) then
    log.info("存在 i2c1")
else
    i2c.close(1) -- 关掉
end
```


--------------------------------------------------
# i2c.send

```lua
i2c.send(id, addr, data)
```

i2c发送数据

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 设备id, 例如i2c1的id为1, i2c2的id为2
`addr`|`int`| I2C子设备的地址, 7位地址
`data`|`string`| 待发送的数据

## 返回值

> *无返回值*

## 调用示例

```lua
-- 往i2c1发送2个字节的数据
i2c.send(1, 0x5C, string.char(0x0F, 0x2F))
```


--------------------------------------------------
# i2c.recv

```lua
i2c.recv(id, addr, len)
```

i2c接收数据

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 设备id, 例如i2c1的id为1, i2c2的id为2
`addr`|`int`| I2C子设备的地址, 7位地址
`len`|`int`| 手机数据的长度

## 返回值

> `string`: 收到的数据

## 调用示例

```lua
-- 从i2c1读取2个字节的数据
local data = i2c.recv(1, 0x5C, 2)
```


--------------------------------------------------
# i2c.writeReg

```lua
i2c.writeReg(id, addr, reg, data)
```

i2c接收数据

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 设备id, 例如i2c1的id为1, i2c2的id为2
`addr`|`int`| I2C子设备的地址, 7位地址
`reg`|`int`| 寄存器地址
`data`|`string`| 待发送的数据

## 返回值

> `string`: 收到的数据

## 调用示例

```lua
-- 从i2c1的地址为0x5C的设备的寄存器0x01写入2个字节的数据
i2c.writeReg(1, 0x5C, 0x01, string.char(0x00, 0xF2))
```


--------------------------------------------------
# i2c.close

```lua
i2c.close(id)
```

关闭i2c设备

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 设备id, 例如i2c1的id为1, i2c2的id为2

## 返回值

> *无返回值*

## 调用示例

```lua
-- 关闭i2c1
i2c.close(1)
```


