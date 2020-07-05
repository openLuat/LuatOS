---
title: luat_lib_socket
path: luat_lib_socket.c
module: socket
summary: socket操作库
version: 1.0
date: 2020.03.30
---
--------------------------------------------------
# socket_ntp_sync

```c
static int socket_ntp_sync(lua_State *L)
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
# sal_tls_test

```c
static int sal_tls_test(lua_State *L)
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
# l_socket_is_ready

```c
static int l_socket_is_ready(lua_State *L)
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
# l_socket_selfip

```c
static int l_socket_selfip(lua_State *L)
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
# luat_lib_netc_msg_handler

```c
static int luat_lib_netc_msg_handler(lua_State *L, void *ptr)
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
# luat_lib_socket_new

```c
static int luat_lib_socket_new(lua_State *L, int netc_type)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*
**netc_type**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# luat_lib_socket_ent_handler

```c
static int luat_lib_socket_ent_handler(netc_ent_t *ent)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ent**|`netc_ent_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# socket.tcp

```lua
socket.tcp()
```

新建一个tcp socket

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`object`| socket对象,如果创建失败会返回nil

## 调用示例

```lua
-- 如果读取失败,会返回nil
local so = socket.tcp()
if so then
    so:host("www.baidu.com")
    so:port(80)
    so:on("connect", function(id, re)
        if re == 1 then
            so:send("GET / HTTP/1.0\r\n\r\n")
        end
    end)
    so:on("recv", function(id, data)
        log.info("netc", id, data)
    end)
    if so:start() == 1 then
        sys.waitUntil("NETC_END_" .. so:id())
    end
    so:close()
    so:clean()
end
```
## C API

```c
static int luat_lib_socket_tcp(lua_State *L)
```


--------------------------------------------------
# socket.udp

```lua
socket.udp()
```

新建一个udp socket

## 参数表

> 无参数

## 返回值

> *无返回值*
## C API

```c
static int luat_lib_socket_udp(lua_State *L)
```


--------------------------------------------------
# luat_lib_socket_new

```c
static int luat_lib_socket_new(lua_State *L, int netc_type)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*
**netc_type**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# netc_connect

```c
static int netc_connect(lua_State *L)
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
# netc_close

```c
static int netc_close(lua_State *L)
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
# netc_send

```c
static int netc_send(lua_State *L)
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
# netc_gc

```c
static int netc_gc(lua_State *L)
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
# netc_tostring

```c
static int netc_tostring(lua_State *L)
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
# netc_id

```c
static int netc_id(lua_State *L)
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
# netc_host

```c
static int netc_host(lua_State *L)
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
# netc_port

```c
static int netc_port(lua_State *L)
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
# netc_clean

```c
static int netc_clean(lua_State *L)
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
# netc_on

```c
static int netc_on(lua_State *L)
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
# netc_closed

```c
static int netc_closed(lua_State *L)
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


