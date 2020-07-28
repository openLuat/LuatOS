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
2 |`boolean`| 成功返回true,否则返回false

## 调用示例

```lua
-- 如果读取失败,会返回nil
while 1 do 
    sys.wait(5000) 
    local val,result = sensor.ds18b20(17)
    -- val 301 == 30.1摄氏度
    -- result true 读取成功
    log.info("ds18b20", val, result)
end
```


