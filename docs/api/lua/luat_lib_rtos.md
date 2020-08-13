---
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
`timeout`|`int`| 超时时长,通常是-1,永久等待

## 返回值

> `msgid`: 如果是定时器消息,会返回定时器消息id及附加信息, 其他消息由底层决定,不向lua层进行任何保证.

## 调用示例

```lua
-- 本方法通过sys.run()调用, 普通用户不要使用
rtos.receive(-1)
```


--------------------------------------------------
# rtos.timer_start

```lua
rtos.timer_start(id, timeout, _repeat)
```

启动一个定时器

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 定时器id
`timeout`|`int`| 超时时长,单位毫秒
`_repeat`|`int`| 重复次数,默认是0

## 返回值

> `id`: 如果是定时器消息,会返回定时器消息id及附加信息, 其他消息由底层决定,不向lua层进行任何保证.

## 调用示例

```lua
-- 用户代码请使用 sys.timerStart
-- 启动一个3秒的循环定时器
rtos.timer_start(10000, 3000, -1)
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
`id`|`int`| 定时器id

## 返回值

> *无返回值*

## 调用示例

```lua
-- 用户代码请使用sys.timerStop
rtos.timer_stop(100000)
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


--------------------------------------------------
# rtos.buildDate

```lua
rtos.buildDate()
```

获取固件编译日期

## 参数表

> 无参数

## 返回值

> `string`: 固件编译日期

## 调用示例

```lua
-- 获取编译日期
local d = rtos.buildDate()
```


--------------------------------------------------
# rtos.bsp

```lua
rtos.bsp()
```

获取硬件bsp型号

## 参数表

> 无参数

## 返回值

> `string`: 硬件bsp型号

## 调用示例

```lua
-- 获取编译日期
local bsp = rtos.bsp()
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

> `string`: 固件版本号,例如"1.0.2"

## 调用示例

```lua
-- 读取版本号
local luatos_version = rtos.version()
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
`timeout`|`int`| 休眠时长,单位毫秒

## 返回值

> *无返回值*

## 调用示例

```lua
-- 读取版本号
local luatos_version = rtos.version()
```


--------------------------------------------------
# rtos.meminfo

```lua
rtos.meminfo(type)
```

获取内存信息

## 参数表

Name | Type | Description
-----|------|--------------
`type`|`type`| "sys"系统内存, "lua"虚拟机内存, 默认为lua虚拟机内存

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 总内存大小,单位字节
2 |`int`| 当前使用的内存大小,单位字节
3 |`int`| 最大使用的内存大小,单位字节

## 调用示例

```lua
-- 打印内存占用
log.info("mem.lua", rtos.meminfo())
log.info("mem.sys", rtos.meminfo("sys"))
```


--------------------------------------------------
# rtos.firmware

```lua
rtos.firmware()
```

返回底层描述信息,格式为 LuatOS_$VERSION_$BSP,可用于OTA升级判断底层信息

## 参数表

> 无参数

## 返回值

> `string`: 底层描述信息

## 调用示例

```lua
-- 打印底层描述信息
log.info("firmware", rtos.firmware())
```


