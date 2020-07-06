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
# libcoap.new

```lua
libcoap.new(code, uri, headers, payload)
```

*
创建一个coap数据包

## 参数表

Name | Type | Description
-----|------|--------------
**code**|`int`| coap的code, 例如libcoap.GET/libcoap.POST/libcoap.PUT/libcoap.DELETE
**uri**|`string`| 目标URI,必须填写, 不需要加上/开头
**headers**|`table`| 请求头,类似于http的headers,可选
**payload**|`string`| 请求体,类似于http的body,可选

## 返回值

No. | Type | Description
----|------|--------------
1 |`userdata`| coap数据包

## 调用示例

```lua
-- 创建一个请求服务器time的数据包
local coapdata = libcoap.new(libcoap.GET, "time")
local data = coapdata:rawdata()
```
## C API

```c
static int l_libcoap_new(lua_State *L)
```


--------------------------------------------------
# libcoap.parse

```lua
libcoap.parse(str)
```

*
解析coap数据包

## 参数表

Name | Type | Description
-----|------|--------------
**str**|`string`| coap数据包

## 返回值

No. | Type | Description
----|------|--------------
1 |`userdata`| coap数据包,如果解析失败会返回nil

## 调用示例

```lua
-- 解析服务器传入的数据包
local coapdata = libcoap.parse(indata)
log.info("coapdata", coapdata:hcode(), coapdata:data())
```
## C API

```c
static int l_libcoap_parse(lua_State *L)
```


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


