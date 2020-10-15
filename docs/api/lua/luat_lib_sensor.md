---
module: sensor
summary: 传感器操作库
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# sensor.ds18b20

```lua
sensor.ds18b20(pin, ?)
```

获取DS18B20的温度数据

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| gpio端口号
`?`|`boolean`| 是否校验crc值,默认为true. 不校验crc值能提高读取成功的概率,但可能会读取到错误的值

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 温度数据,单位0.1摄氏度
2 |`boolean`| 成功返回true,否则返回false

## 调用示例

```lua
-- 如果读取失败,会返回nil
while 1 do 
    sys.wait(5000) 
    local val,result = sensor.ds18b20(17, true) -- GPIO17且校验CRC值
    -- val 301 == 30.1摄氏度
    -- result true 读取成功
    log.info("ds18b20", val, result)
end
```


--------------------------------------------------
# sensor.w1_reset

```lua
sensor.w1_reset(pin)
```

单总线协议,复位设备

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| gpio端口号

## 返回值

> *无返回值*


--------------------------------------------------
# sensor.w1_reset

```lua
sensor.w1_reset(pin)
```

单总线协议,连接设备

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| gpio端口号

## 返回值

> `boolean`: 成功返回true,失败返回false


--------------------------------------------------
# sensor.w1_write

```lua
sensor.w1_write(pin, data1, data2)
```

单总线协议,往总线写入数据

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| gpio端口号
`data1`|`int`| 第一个数据
`data2`|`int`| 第二个数据, 可以写N个数据

## 返回值

> *无返回值*


--------------------------------------------------
# sensor.w1_read

```lua
sensor.w1_read(pin, len)
```

单总线协议,从总线读取数据

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| gpio端口号
`len`|`int`| 读取的长度

## 返回值

> `int`: 按读取的长度返回N个整数


