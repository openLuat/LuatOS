---
title: luat_lib_rtos
path: luat_lib_rtos.c
module: rtos
summary: RTOS底层操作库
version: 1.0
date: 2020.03.30
---
--------------------------------------------------
# rtos.receive

```lua
rtos.receive(timeout)
```

接受并处理底层消息队列.

## 参数表

Name | Type | Description
-----|------|--------------
**timeout**|`int`| 超时时长,通常是-1,永久等待

## 返回值

No. | Type | Description
----|------|--------------
1 |`msgid`| 如果是定时器消息,会返回定时器消息id及附加信息, 其他消息由底层决定,不向lua层进行任何保证.

## 调用示例

```lua
-- 本方法通过sys.run()调用, 普通用户不要使用
rtos.receive(-1)
```
## C API

```c
static int l_rtos_receive(lua_State *L)
```


--------------------------------------------------
# l_timer_handler

```c
static int l_timer_handler(lua_State *L, void *ptr)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*
**ptr**|`void*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# rtos.timer_start

```lua
rtos.timer_start(id, timeout, _repeat)
```

启动一个定时器

## 参数表

Name | Type | Description
-----|------|--------------
**id**|`int`| 定时器id
**timeout**|`int`| 超时时长,单位毫秒
**_repeat**|`int`| 重复次数,默认是0

## 返回值

No. | Type | Description
----|------|--------------
1 |`id`| 如果是定时器消息,会返回定时器消息id及附加信息, 其他消息由底层决定,不向lua层进行任何保证.

## 调用示例

```lua
-- 用户代码请使用 sys.timerStart
-- 启动一个3秒的循环定时器
rtos.timer_start(10000, 3000, -1)
```
## C API

```c
static int l_rtos_timer_start(lua_State *L)
```


--------------------------------------------------
# rtos.timer_stop

```lua
rtos.timer_stop(id)
```

关闭并释放一个定时器

## 参数表

Name | Type | Description
-----|------|--------------
**id**|`int`| 定时器id

## 返回值

> *无返回值*

## 调用示例

```lua
-- 用户代码请使用sys.timerStop
rtos.timer_stop(100000)
```
## C API

```c
static int l_rtos_timer_stop(lua_State *L)
```


--------------------------------------------------
# rtos.reboot

```lua
rtos.reboot()
```

设备重启

## 参数表

> 无参数

## 返回值

> *无返回值*

## 调用示例

```lua
-- 立即重启设备
rtos.reboot()
```
## C API

```c
static int l_rtos_reboot(lua_State *L)
```


--------------------------------------------------
# l_rtos_build_date

```c
static int l_rtos_build_date(lua_State *L)
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
# rtos.bsp

```lua
rtos.bsp()
```

获取硬件bsp型号

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 硬件bsp型号

## 调用示例

```lua
-- 获取编译日期
local bsp = rtos.bsp()
```
## C API

```c
static int l_rtos_bsp(lua_State *L)
```


--------------------------------------------------
# rtos.version

```lua
rtos.version()
```

 获取固件版本号

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 固件版本号,例如"1.0.2"

## 调用示例

```lua
-- 读取版本号
local luatos_version = rtos.version()
```
## C API

```c
static int l_rtos_version(lua_State *L)
```


--------------------------------------------------
# rtos.standy

```lua
rtos.standy(timeout)
```

进入待机模式(部分设备可用,例如w60x)

## 参数表

Name | Type | Description
-----|------|--------------
**timeout**|`int`| 休眠时长,单位毫秒

## 返回值

> *无返回值*

## 调用示例

```lua
-- 读取版本号
local luatos_version = rtos.version()
```
## C API

```c
static int l_rtos_standy(lua_State *L)
```


--------------------------------------------------
# l_rtos_meminfo

```c
static int l_rtos_meminfo(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


