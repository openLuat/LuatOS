---
title: luat_lib_libgnss
path: luat_lib_libgnss.c
module: libgnss
summary: NMEA数据处理
version: 1.0
date: 2020.07.03
---
--------------------------------------------------
# parse_nmea

```c
static int parse_nmea(const char *line)
```


## 参数表

Name | Type | Description
-----|------|--------------
**line**|`char*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# libgnss.parse

```lua
libgnss.parse(str)
```

*
处理nmea数据

## 参数表

Name | Type | Description
-----|------|--------------
**str**|`string`| nmea数据

## 返回值

> *无返回值*

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", json.encode(libgnss.getRmc()))
```
## C API

```c
static int l_libgnss_parse(lua_State *L)
```


--------------------------------------------------
# l_libgnss_is_fix

```c
static int l_libgnss_is_fix(lua_State *L)
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
# l_libgnss_get_int_location

```c
static int l_libgnss_get_int_location(lua_State *L)
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
# l_libgnss_get_rmc

```c
static int l_libgnss_get_rmc(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


