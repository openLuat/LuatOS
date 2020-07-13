---
module: log
summary: 日志库
version: 1.0
date: 2020.03.30
---

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
`val`|`any`| ...         需打印的参数
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

## C API

```c
static int l_log_debug(lua_State *L)
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
`val`|`any`| ...         需打印的参数
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

## C API

```c
static int l_log_info(lua_State *L)
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
`val`|`any`| ...         需打印的参数
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

## C API

```c
static int l_log_warn(lua_State *L)
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
`val`|`any`| ...         需打印的参数
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

## C API

```c
static int l_log_error(lua_State *L)
```


