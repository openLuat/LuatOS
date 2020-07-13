---
module: socket
summary: socket操作库
version: 1.0
date: 2020.03.30
---

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


