---
title: luat_i2c_rtt
path: luat_i2c_rtt.c
---
--------------------------------------------------
# luat_i2c_rtt_init

```c
static int luat_i2c_rtt_init()
```


## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# write_reg

```c
static rt_err_t write_reg(struct rt_i2c_bus_device *bus, rt_uint16_t addr, rt_uint8_t reg, rt_uint8_t *data, rt_uint8_t len)
```


## 参数表

Name | Type | Description
-----|------|--------------
**bus**|`rt_i2c_bus_device*`| *无*
**addr**|`rt_uint16_t`| *无*
**reg**|`rt_uint8_t`| *无*
**data**|`rt_uint8_t*`| *无*
**len**|`rt_uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_err_t`| *无*


--------------------------------------------------
# read_regs

```c
static rt_err_t read_regs(struct rt_i2c_bus_device *bus, rt_uint16_t addr, rt_uint8_t *buf, rt_uint8_t len)
```


## 参数表

Name | Type | Description
-----|------|--------------
**bus**|`rt_i2c_bus_device*`| *无*
**addr**|`rt_uint16_t`| *无*
**buf**|`rt_uint8_t*`| *无*
**len**|`rt_uint8_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_err_t`| *无*


