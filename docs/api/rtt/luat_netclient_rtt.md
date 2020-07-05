---
title: luat_netclient_rtt
path: luat_netclient_rtt.c
---
--------------------------------------------------
# netclient_destory

```c
static rt_int32_t netclient_destory(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# socket_init

```c
static rt_int32_t socket_init(netclient_t *thiz, const char *hostname, int port)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*
**hostname**|`char*`| *无*
**port**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# socket_deinit

```c
static rt_int32_t socket_deinit(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# pipe_init

```c
static rt_int32_t pipe_init(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# pipe_deinit

```c
static rt_int32_t pipe_deinit(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# select_handle

```c
static void select_handle(netclient_t *thiz, char *sock_buff)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*
**sock_buff**|`char*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# netclient_thread_init

```c
static rt_int32_t netclient_thread_init(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# netclient_thread_entry

```c
static void netclient_thread_entry(void *param)
```


## 参数表

Name | Type | Description
-----|------|--------------
**param**|`void*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# EVENT

```c
static void EVENT(int netc_id, tpc_cb_t cb, int lua_ref, int tp, size_t len, void *buff)
```


## 参数表

Name | Type | Description
-----|------|--------------
**netc_id**|`int`| *无*
**cb**|`tpc_cb_t`| *无*
**lua_ref**|`int`| *无*
**tp**|`int`| *无*
**len**|`size_t`| *无*
**buff**|`void*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# netclient_destory

```c
static rt_int32_t netclient_destory(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# socket_init

```c
static rt_int32_t socket_init(netclient_t *thiz, const char *url, int port)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*
**url**|`char*`| *无*
**port**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# socket_deinit

```c
static rt_int32_t socket_deinit(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# pipe_init

```c
static rt_int32_t pipe_init(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# pipe_deinit

```c
static rt_int32_t pipe_deinit(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# netclient_thread_init

```c
static rt_int32_t netclient_thread_init(netclient_t *thiz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_int32_t`| *无*


--------------------------------------------------
# select_handle

```c
static void select_handle(netclient_t *thiz, char *sock_buff)
```


## 参数表

Name | Type | Description
-----|------|--------------
**thiz**|`netclient_t*`| *无*
**sock_buff**|`char*`| *无*

## 返回值

> *无返回值*


