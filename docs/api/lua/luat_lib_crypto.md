---
module: crypto
summary: 加解密和hash函数
version: 1.0
date: 2020.07.03
---

--------------------------------------------------
# crypto.md5

```lua
crypto.md5(str)
```

计算md5值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串

## 返回值

> `string`: 计算得出的md5值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的md5
log.info("md5", crypto.md5("abc"))
```


--------------------------------------------------
# crypto.hmac_md5

```lua
crypto.hmac_md5(str, key)
```

计算hmac_md5值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串
`key`|`string`| 密钥

## 返回值

> `string`: 计算得出的hmac_md5值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的hmac_md5
log.info("hmac_md5", crypto.hmac_md5("abc", "1234567890"))
```


--------------------------------------------------
# crypto.sha1

```lua
crypto.sha1(str)
```

计算sha1值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串

## 返回值

> `string`: 计算得出的sha1值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的sha1
log.info("sha1", crypto.sha1("abc"))
```


--------------------------------------------------
# crypto.hmac_sha1

```lua
crypto.hmac_sha1(str, key)
```

计算hmac_sha1值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串
`key`|`string`| 密钥

## 返回值

> `string`: 计算得出的hmac_sha1值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的hmac_sha1
log.info("hmac_sha1", crypto.hmac_sha1("abc", "1234567890"))
```


--------------------------------------------------
# crypto.cipher

```lua
crypto.cipher(type, padding, str, key, iv)
```

对称加密

## 参数表

Name | Type | Description
-----|------|--------------
`type`|`string`| 算法名称, 例如 AES-128-ECB/AES-128-CBC, 可查阅mbedtls的cipher_wrap.c
`padding`|`string`| 对齐方式, 当前仅支持PKCS7
`str`|`string`| 需要加密的数据
`key`|`string`| 密钥,需要对应算法的密钥长度
`iv`|`string`| IV值, 非ECB算法需要

## 返回值

> `string`: 加密后的字符串

## 调用示例

```lua
-- 计算AES
local data = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
local data2 = crypto.cipher_encrypt("AES-128-CBC", "PKCS7", "1234567890123456", "1234567890123456", "1234567890666666")
```


