---
module: sensor
summary: 传感器操作库
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# sensor.ds18b20

```lua
sensor.ds18b20(pin)
```

获取DS18B20的温度数据

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| gpio端口号

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


