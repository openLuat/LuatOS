---
module: libcoap
summary: coap数据处理
version: 1.0
date: 2020.06.30
---

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
`code`|`int`| coap的code, 例如libcoap.GET/libcoap.POST/libcoap.PUT/libcoap.DELETE
`uri`|`string`| 目标URI,必须填写, 不需要加上/开头
`headers`|`table`| 请求头,类似于http的headers,可选
`payload`|`string`| 请求体,类似于http的body,可选

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
`str`|`string`| coap数据包

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


