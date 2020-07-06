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
# crypto.md5

```lua
crypto.md5(str)
```

*
计算md5值

## 参数表

Name | Type | Description
-----|------|--------------
**str**|`string`| 需要计算的字符串

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 计算得出的md5值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的md5
log.info("md5", crypto.md5("abc"))
```
## C API

```c
static int l_crypto_md5(lua_State *L)
```


--------------------------------------------------
# crypto.hmac_md5

```lua
crypto.hmac_md5(str, key)
```

*
计算hmac_md5值

## 参数表

Name | Type | Description
-----|------|--------------
**str**|`string`| 需要计算的字符串
**key**|`string`| 密钥

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 计算得出的hmac_md5值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的hmac_md5
log.info("hmac_md5", crypto.hmac_md5("abc", "1234567890"))
```
## C API

```c
static int l_crypto_hmac_md5(lua_State *L)
```


--------------------------------------------------
# crypto.sha1

```lua
crypto.sha1(str)
```

*
计算sha1值

## 参数表

Name | Type | Description
-----|------|--------------
**str**|`string`| 需要计算的字符串

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 计算得出的sha1值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的sha1
log.info("sha1", crypto.sha1("abc"))
```
## C API

```c
static int l_crypto_sha1(lua_State *L)
```


--------------------------------------------------
# crypto.hmac_sha1

```lua
crypto.hmac_sha1(str, key)
```

*
计算hmac_sha1值

## 参数表

Name | Type | Description
-----|------|--------------
**str**|`string`| 需要计算的字符串
**key**|`string`| 密钥

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 计算得出的hmac_sha1值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的hmac_sha1
log.info("hmac_sha1", crypto.hmac_sha1("abc", "1234567890"))
```
## C API

```c
static int l_crypto_hmac_sha1(lua_State *L)
```


