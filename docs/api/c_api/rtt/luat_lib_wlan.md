---
module: wlan
summary: wifi操作库
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# wlan_cb

```c
static void wlan_cb(int event, struct rt_wlan_buff *buff, void *parameter)
```

注册回调

## 参数表

Name | Type | Description
-----|------|--------------
`event`|`int`| *无*
`buff`|`rt_wlan_buff*`| *无*
`parameter`|`void*`| *无*

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
`L`|`lua_State*`| *无*
`ptr`|`void*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


