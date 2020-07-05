---
title: luat_lib_sensor
path: luat_lib_sensor.c
module: sensor
summary: 传感器操作库
version: 1.0
date: 2020.03.30
---
--------------------------------------------------
# w1_reset

```c
static void w1_reset(int pin)
```


## 参数表

Name | Type | Description
-----|------|--------------
**pin**|`int`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# w1_connect

```c
static uint8_t w1_connect(int pin)
```


## 参数表

Name | Type | Description
-----|------|--------------
**pin**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint8_t`| *无*


--------------------------------------------------
# w1_read_bit

```c
static uint8_t w1_read_bit(int pin)
```


## 参数表

Name | Type | Description
-----|------|--------------
**pin**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint8_t`| *无*


--------------------------------------------------
# w1_read_byte

```c
static uint8_t w1_read_byte(int pin)
```


## 参数表

Name | Type | Description
-----|------|--------------
**pin**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint8_t`| *无*


--------------------------------------------------
# w1_write_byte

```c
static void w1_write_byte(int pin, uint8_t dat)
```


## 参数表

Name | Type | Description
-----|------|--------------
**pin**|`int`| *无*
**dat**|`uint8_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# ds18b20_get_temperature

```c
static int32_t ds18b20_get_temperature(int pin, int32_t *val)
```


## 参数表

Name | Type | Description
-----|------|--------------
**pin**|`int`| *无*
**val**|`int32_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int32_t`| *无*


--------------------------------------------------
# sensor.ds18b20

```lua
sensor.ds18b20(pin)
```

获取DS18B20的温度数据

## 参数表

Name | Type | Description
-----|------|--------------
**pin**|`int`| gpio端口号

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 温度数据

## 调用示例

```lua
-- 如果读取失败,会返回nil
while 1 do sys.wait(5000) log.info("ds18b20", sensor.ds18b20(14)) end
```
## C API

```c
static int l_sensor_ds18b20(lua_State *L)
```


