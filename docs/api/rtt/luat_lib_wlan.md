---
title: luat_lib_wlan
path: luat_lib_wlan.c
module: wlan
summary: wifi操作库
version: 1.0
date: 2020.03.30
---
--------------------------------------------------
# l_wlan_get_mode

```c
static int l_wlan_get_mode(lua_State *L)
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
# l_wlan_set_mode

```c
static int l_wlan_set_mode(lua_State *L)
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
# _wlan_connect

```c
static void _wlan_connect(void *params)
```


## 参数表

Name | Type | Description
-----|------|--------------
**params**|`void*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# wlan.connect

```lua
wlan.connect(ssid, password)
```

连接wifi

## 参数表

Name | Type | Description
-----|------|--------------
**ssid**|`string`| ssid  wifi的SSID
**password**|`string`| password wifi的密码,可选

## 返回值

No. | Type | Description
----|------|--------------
1 |`re`| 如果正常启动联网线程,无返回值,否则返回出错信息. 成功启动联网线程不等于联网成功!!

## 调用示例

```lua
-- 连接到uiot,密码1234567890
wlan.connect("uiot", "1234567890")
```
## C API

```c
static int l_wlan_connect(lua_State *L)
```


--------------------------------------------------
# wlan.disconnect

```lua
wlan.disconnect()
```

断开wifi

## 参数表

> 无参数

## 返回值

> *无返回值*

## 调用示例

```lua
-- 断开wifi连接
wlan.disconnect()
```
## C API

```c
static int l_wlan_disconnect(lua_State *L)
```


--------------------------------------------------
# wlan.connected

```lua
wlan.connected()
```

是否已经连上wifi网络

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`re`| 已连接返回1,未连接返回0

## 调用示例

```lua
-- 连上wifi网络,只代表密码正确, 不一定拿到了ip
wlan.connected()
```
## C API

```c
static int l_wlan_connected(lua_State *L)
```


--------------------------------------------------
# wlan.autoreconnect

```lua
wlan.autoreconnect(enable)
```

设置或查询wifi station是否自动连接

## 参数表

Name | Type | Description
-----|------|--------------
**enable**|`int`| 传入1启用自动连接(自动重连wifi), 传入0关闭. 不传这个参数就是查询

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 已启用自动连接(自动重连wifi)返回1, 否则返回0

## 调用示例

```lua
-- 查询自动连接的设置
-- 设置自动连接
wlan.autoreconnect()
wlan.autoreconnect(1)
-- 查询自动连接的设置
-- 设置自动连接
wlan.autoreconnect()
wlan.autoreconnect(1)
```
## C API

```c
static int l_wlan_autoreconnect(lua_State *L)
```


--------------------------------------------------
# wlan.scan

```lua
wlan.scan()
```

开始扫网,通常配合wlan.scanResult使用

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`boolean`| 启动结果,一般为true

## 调用示例

```lua
-- 扫描并查询结果
wlan.scan()
sys.waitUntil("WLAN_SCAN_DONE", 30000)
local re = wlan.scanResult()
for i in ipairs(re) do
    log.info("wlan", "info", re[i].ssid, re[i].rssi)
end
```
## C API

```c
static int l_wlan_scan(lua_State *L)
```


--------------------------------------------------
# l_wlan_scan_get_result

```c
static int l_wlan_scan_get_result(lua_State *L)
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
# wlan.get_mac

```lua
wlan.get_mac(?)
```

获取mac地址

## 参数表

Name | Type | Description
-----|------|--------------
**?**|`usage`| wlan.get_mac()

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 长度为12的HEX字符串
## C API

```c
static int l_wlan_get_mac(lua_State *L)
```


--------------------------------------------------
# wlan.get_mac_raw

```lua
wlan.get_mac_raw(?)
```

获取mac地址,raw格式

## 参数表

Name | Type | Description
-----|------|--------------
**?**|`usage`| wlan.get_mac_raw()

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 6字节的mac地址串
## C API

```c
static int l_wlan_get_mac_raw(lua_State *L)
```


--------------------------------------------------
# wlan.ready

```lua
wlan.ready(?)
```

wifi是否已经获取ip

## 参数表

Name | Type | Description
-----|------|--------------
**?**|`usage`| wlan.ready()

## 返回值

No. | Type | Description
----|------|--------------
1 |`re`| 已经有ip返回true,否则返回false
## C API

```c
static int l_wlan_ready(lua_State *L)
```


--------------------------------------------------
# l_wlan_handler

```c
static int l_wlan_handler(lua_State *L, void *ptr)
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
# wlan_cb

```c
static void wlan_cb(int event, struct rt_wlan_buff *buff, void *parameter)
```

注册回调

## 参数表

Name | Type | Description
-----|------|--------------
**event**|`int`| *无*
**buff**|`rt_wlan_buff*`| *无*
**parameter**|`void*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# reg_wlan_callbacks

```c
static void reg_wlan_callbacks(void)
```


## 参数表

Name | Type | Description
-----|------|--------------
**null**|`void`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# luat_PW_msghandler

```c
static int luat_PW_msghandler(lua_State *L, void *ptr)
```

----------------------------
-----------------------------

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
# _PW_callback

```c
static void _PW_callback(int state, unsigned char *_ssid, unsigned char *_passwd)
```


## 参数表

Name | Type | Description
-----|------|--------------
**state**|`int`| *无*
**_ssid**|`char*`| *无*
**_passwd**|`char*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# l_wlan_oneshot_start

```c
static int l_wlan_oneshot_start(lua_State *L)
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
# l_wlan_oneshot_stop

```c
static int l_wlan_oneshot_stop(lua_State *L)
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
# l_wlan_oneshot_state

```c
static int l_wlan_oneshot_state(lua_State *L)
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
# l_wlan_join_info

```c
static int l_wlan_join_info(lua_State *L)
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
# wlan.rssi

```lua
wlan.rssi(?)
```

获取wifi信号强度值rssi

## 参数表

Name | Type | Description
-----|------|--------------
**?**|`usage`| wlan.rssi()

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 如果是station模式,返回正的rssi值,否则返回负值
## C API

```c
static int l_wlan_rssi(lua_State *L)
```


--------------------------------------------------
# wlan.airkiss_start

```lua
wlan.airkiss_start(?)
```

启动airkiss配网线程

## 参数表

Name | Type | Description
-----|------|--------------
**?**|`usage`| wlan.airkiss_start()

## 返回值

No. | Type | Description
----|------|--------------
1 |`re`| 启动成功返回1,否则返回0
## C API

```c
static int l_wlan_airkiss_start(lua_State *L)
```


