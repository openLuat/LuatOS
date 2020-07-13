---
module: libgnss
summary: NMEA数据处理
version: 1.0
date: 2020.07.03
---

--------------------------------------------------
# libgnss.parse

```lua
libgnss.parse(str)
```

*
处理nmea数据

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| nmea数据

## 返回值

> *无返回值*

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", json.encode(libgnss.getRmc()))
```

## C API

```c
static int l_libgnss_parse(lua_State *L)
```


