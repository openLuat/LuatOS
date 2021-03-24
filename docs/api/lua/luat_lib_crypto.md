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
# crypto.sha256

```lua
crypto.sha256(str)
```

计算sha256值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串

## 返回值

> `string`: 计算得出的sha256值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的sha256
log.info("sha256", crypto.sha256("abc"))
```


--------------------------------------------------
# crypto.hmac_sha256

```lua
crypto.hmac_sha256(str, key)
```

计算hmac_sha256值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串
`key`|`string`| 密钥

## 返回值

> `string`: 计算得出的hmac_sha1值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的hmac_sha256
log.info("hmac_sha256", crypto.hmac_sha256("abc", "1234567890"))
```


--------------------------------------------------
# crypto.sha512

```lua
crypto.sha512(str)
```

计算sha512值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串

## 返回值

> `string`: 计算得出的sha512值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的sha512
log.info("sha512", crypto.sha512("abc"))
```


--------------------------------------------------
# crypto.hmac_sha512

```lua
crypto.hmac_sha512(str, key)
```

计算hmac_sha512值

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 需要计算的字符串
`key`|`string`| 密钥

## 返回值

> `string`: 计算得出的hmac_sha1值的hex字符串

## 调用示例

```lua
-- 计算字符串"abc"的hmac_sha512
log.info("hmac_sha512", crypto.hmac_sha512("abc", "1234567890"))
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


--------------------------------------------------
# crypto.cipher

```lua
crypto.cipher(type, padding, str, key, iv)
```

对称解密

## 参数表

Name | Type | Description
-----|------|--------------
`type`|`string`| 算法名称, 例如 AES-128-ECB/AES-128-CBC, 可查阅mbedtls的cipher_wrap.c
`padding`|`string`| 对齐方式, 当前仅支持PKCS7
`str`|`string`| 需要解密的数据
`key`|`string`| 密钥,需要对应算法的密钥长度
`iv`|`string`| IV值, 非ECB算法需要

## 返回值

> `string`: 解密后的字符串

## 调用示例

```lua
-- 用AES加密,然后用AES解密
-- data的hex为 757CCD0CDC5C90EADBEEECF638DD0000
-- data2的值为 1234567890123456
local data = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
local data2 = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", data, "1234567890123456")
-------------------------
-- 用AES加密,然后用AES解密
-- data的hex为 757CCD0CDC5C90EADBEEECF638DD0000
-- data2的值为 1234567890123456
local data = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
local data2 = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", data, "1234567890123456")
-------------------------
-- 用AES加密,然后用AES解密
-- data的hex为 757CCD0CDC5C90EADBEEECF638DD0000
-- data2的值为 1234567890123456
local data = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
local data2 = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", data, "1234567890123456")
```


--------------------------------------------------
# crypto.crc16

```lua
crypto.crc16(method, data, poly, initial, finally, inReversem outReverse, ?)
```

计算CRC16

## 参数表

Name | Type | Description
-----|------|--------------
`method`|`string`| 输入模式
`data`|`string`| 字符串
`poly`|`int`| poly值
`initial`|`int`| initial值
`finally`|`int`| finally值
`inReversem outReverse`|`int`| 输入反转,1反转,默认0不反转
`?`|`int`| 输入反转,1反转,默认0不反转

## 返回值

> `int`: 对应的CRC16值

## 调用示例

```lua
-- 计算CRC16
local crc = crypto.crc16("")
```


--------------------------------------------------
# crypto.crc16_modbus

```lua
crypto.crc16_modbus(data)
```

直接计算modbus的crc16值

## 参数表

Name | Type | Description
-----|------|--------------
`data`|`string`| 数据

## 返回值

> `int`: 对应的CRC16值

## 调用示例

```lua
-- 计算CRC16 modbus
local crc = crypto.crc16_modbus(data)
```


--------------------------------------------------
# crypto.crc32

```lua
crypto.crc32(data)
```

计算crc32值

## 参数表

Name | Type | Description
-----|------|--------------
`data`|`string`| 数据

## 返回值

> `int`: 对应的CRC32值

## 调用示例

```lua
-- 计算CRC32
local crc = crypto.crc32(data)
```


--------------------------------------------------
# crypto.crc8

```lua
crypto.crc8(data)
```

计算crc8值

## 参数表

Name | Type | Description
-----|------|--------------
`data`|`string`| 数据

## 返回值

> `int`: 对应的CRC8值

## 调用示例

```lua
-- 计算CRC8
local crc = crypto.crc8(data)
```


