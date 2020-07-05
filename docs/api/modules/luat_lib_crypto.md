---
title: luat_lib_crypto
path: luat_lib_crypto.c
module: crypto
summary: 加解密和hash函数
version: 1.0
date: 2020.07.03
---
--------------------------------------------------
# fixhex

```c
static void fixhex(const char *source, char *dst, size_t len)
```


## 参数表

Name | Type | Description
-----|------|--------------
**source**|`char*`| *无*
**dst**|`char*`| *无*
**len**|`size_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# l_crypto_md5

```c
static int l_crypto_md5(lua_State *L)
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
# l_crypto_hmac_md5

```c
static int l_crypto_hmac_md5(lua_State *L)
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
# l_crypto_sha1

```c
static int l_crypto_sha1(lua_State *L)
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
# l_crypto_hmac_sha1

```c
static int l_crypto_hmac_sha1(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


