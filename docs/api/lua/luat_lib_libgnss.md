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

处理nmea数据

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 原始nmea数据

## 返回值

> *无返回值*

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", json.encode(libgnss.getRmc()))
```


--------------------------------------------------
# libgnss.isFix

```lua
libgnss.isFix()
```

当前是否已经定位成功

## 参数表

> 无参数

## 返回值

> `boolean`: 定位成功与否

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "isFix", libgnss.isFix())
```


--------------------------------------------------
# libgnss.getIntLocation

```lua
libgnss.getIntLocation()
```

获取位置信息

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| lat数据, 格式为 ddmmmmmmm
2 |`int`| lng数据, 格式为 ddmmmmmmm
3 |`int`| speed数据

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "loc", libgnss.getIntLocation())
```


--------------------------------------------------
# libgnss.getRmc

```lua
libgnss.getRmc()
```

获取原始RMC位置信息

## 参数表

> 无参数

## 返回值

> `table`: 原始rmc数据

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "rmc", json.encode(libgnss.getRmc()))
```


--------------------------------------------------
# libgnss.getGsv

```lua
libgnss.getGsv()
```

获取原始GSV信息

## 参数表

> 无参数

## 返回值

> `table`: 原始GSV数据

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "gsv", json.encode(libgnss.getGsv()))
```


--------------------------------------------------
# libgnss.getGsa

```lua
libgnss.getGsa()
```

获取原始GSA信息

## 参数表

> 无参数

## 返回值

> `table`: 原始GSA数据

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "gsa", json.encode(libgnss.getGsa()))
```


--------------------------------------------------
# libgnss.getVtg

```lua
libgnss.getVtg()
```

获取原始VTA位置信息

## 参数表

> 无参数

## 返回值

> `table`: 原始VTA数据

## 调用示例

```lua
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "vtg", json.encode(libgnss.getVtg()))
```


