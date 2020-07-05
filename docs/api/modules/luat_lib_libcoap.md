---
title: luat_lib_libcoap
path: luat_lib_libcoap.c
module: libcoap
summary: coap数据处理
version: 1.0
date: 2020.06.30
---
--------------------------------------------------
# addopt

```c
static void addopt(luat_lib_libcoap_t *_coap, uint8_t opt_type, const char *value, size_t len)
```


## 参数表

Name | Type | Description
-----|------|--------------
**_coap**|`luat_lib_libcoap_t*`| *无*
**opt_type**|`uint8_t`| *无*
**value**|`char*`| *无*
**len**|`size_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# l_libcoap_new

```c
static int l_libcoap_new(lua_State *L)
```

libcoap.new(libcoap.GET, "time", {}, nil)

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_libcoap_parse

```c
static int l_libcoap_parse(lua_State *L)
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
# libcoap_msgid

```c
static int libcoap_msgid(lua_State *L)
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
# libcoap_token

```c
static int libcoap_token(lua_State *L)
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
# libcoap_rawdata

```c
static int libcoap_rawdata(lua_State *L)
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
# libcoap_code

```c
static int libcoap_code(lua_State *L)
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
# libcoap_httpcode

```c
static int libcoap_httpcode(lua_State *L)
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
# libcoap_type

```c
static int libcoap_type(lua_State *L)
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
# libcoap_data

```c
static int libcoap_data(lua_State *L)
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
# createmeta

```c
static void createmeta(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

> *无返回值*


