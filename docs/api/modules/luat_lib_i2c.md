---
title: luat_lib_i2c
path: luat_lib_i2c.c
module: i2c
summary: I2C操作
version: 1.0
date: 2020.03.30
---
--------------------------------------------------
# l_i2c_exist

```c
static int l_i2c_exist(lua_State *L)
```

i2c编号是否存在
@api i2c.exist(id)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@return int 存在就返回1,否则返回0
@usage
-- 检查i2c1是否存在
if i2c.exist(1) then
    log.info("存在 i2c1")
end

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_i2c_setup

```c
static int l_i2c_setup(lua_State *L)
```

i2c初始化
@api i2c.setup(id)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@return int 成功就返回1,否则返回0
@usage
-- 初始化i2c1
if i2c.setup(1) then
    log.info("存在 i2c1")
else
    i2c.close(1) -- 关掉
end

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_i2c_send

```c
static int l_i2c_send(lua_State *L)
```

i2c发送数据
@api i2c.send(id, addr, data)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C子设备的地址, 7位地址
@string 待发送的数据
@return nil 无返回值
@usage
-- 往i2c1发送2个字节的数据
i2c.send(1, 0x5C, string.char(0x0F, 0x2F))

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_i2c_recv

```c
static int l_i2c_recv(lua_State *L)
```

i2c接收数据
@api i2c.recv(id, addr, len)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C子设备的地址, 7位地址
@int 手机数据的长度
@return string 收到的数据
@usage
-- 从i2c1读取2个字节的数据
local data = i2c.recv(1, 0x5C, 2)

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_i2c_write_reg

```c
static int l_i2c_write_reg(lua_State *L)
```

i2c接收数据
@api i2c.writeReg(id, addr, reg, data)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C子设备的地址, 7位地址
@int 寄存器地址
@string 待发送的数据
@return string 收到的数据
@usage
-- 从i2c1的地址为0x5C的设备的寄存器0x01写入2个字节的数据
i2c.writeReg(1, 0x5C, 0x01, string.char(0x00, 0xF2))

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_i2c_read_reg

```c
static int l_i2c_read_reg(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_i2c_close

```c
static int l_i2c_close(lua_State *L)
```

关闭i2c设备
@api i2c.close(id)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@return nil 无返回值
@usage
-- 关闭i2c1
i2c.close(1)

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


