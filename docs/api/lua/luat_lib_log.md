---
module: log
summary: 日志库
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# log.setLevel

```lua
log.setLevel(level)
```

设置日志级别

## 参数表

Name | Type | Description
-----|------|--------------
`level`|`string`| level 日志级别,可用字符串或数值, 字符串为(SILENT,DEBUG,INFO,WARN,ERROR,FATAL), 数值为(0,1,2,3,4,5)

## 返回值

> *无返回值*

## 调用示例

```lua
-- 设置日志级别为INFO
log.setLevel("INFO")
```


--------------------------------------------------
# log.getLevel

```lua
log.getLevel()
```

获取日志级别

## 参数表

> 无参数

## 返回值

> `int`: 日志级别对应0,1,2,3,4,5

## 调用示例

```lua
-- 得到日志级别
log.getLevel()
```


--------------------------------------------------
# log.debug

```lua
log.debug(tag, val, val2, val3, ...)
```

输出日志,级别debug

## 参数表

Name | Type | Description
-----|------|--------------
`tag`|`string`| tag         日志标识,必须是字符串
`val`|`...`| 需打印的参数
`val2`|`null`| *无*
`val3`|`null`| *无*
`...`|`null`| *无*

## 返回值

> *无返回值*

## 调用示例

```lua
-- 日志输出 D/onenet connect ok
log.debug("onenet", "connect ok")
```


--------------------------------------------------
# log.info

```lua
log.info(tag, val, val2, val3, ...)
```

输出日志,级别info

## 参数表

Name | Type | Description
-----|------|--------------
`tag`|`string`| tag         日志标识,必须是字符串
`val`|`...`| 需打印的参数
`val2`|`null`| *无*
`val3`|`null`| *无*
`...`|`null`| *无*

## 返回值

> *无返回值*

## 调用示例

```lua
-- 日志输出 I/onenet connect ok
log.info("onenet", "connect ok")
```


--------------------------------------------------
# log.warn

```lua
log.warn(tag, val, val2, val3, ...)
```

输出日志,级别warn

## 参数表

Name | Type | Description
-----|------|--------------
`tag`|`string`| tag         日志标识,必须是字符串
`val`|`...`| 需打印的参数
`val2`|`null`| *无*
`val3`|`null`| *无*
`...`|`null`| *无*

## 返回值

> *无返回值*

## 调用示例

```lua
-- 日志输出 W/onenet connect ok
log.warn("onenet", "connect ok")
```


--------------------------------------------------
# log.error

```lua
log.error(tag, val, val2, val3, ...)
```

输出日志,级别error

## 参数表

Name | Type | Description
-----|------|--------------
`tag`|`string`| tag         日志标识,必须是字符串
`val`|`...`| 需打印的参数
`val2`|`null`| *无*
`val3`|`null`| *无*
`...`|`null`| *无*

## 返回值

> *无返回值*

## 调用示例

```lua
-- 日志输出 E/onenet connect ok
log.error("onenet", "connect ok")
```


