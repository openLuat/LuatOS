---
module: adc
summary: 数模转换
version: 1.0
date: 2020.07.03
---

--------------------------------------------------
# adc.open

```lua
adc.open(id)
```

打开adc通道

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 通道id,与具体设备有关,通常从0开始

## 返回值

> `boolean`: 打开结果

## 调用示例

```lua
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.read(2))
end
adc.close(2)
```


--------------------------------------------------
# adc.read

```lua
adc.read(id)
```

读取adc通道

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 通道id,与具体设备有关,通常从0开始

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 原始值
2 |`int`| 计算后的值

## 调用示例

```lua
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.read(2))
end
adc.close(2)
```


--------------------------------------------------
# adc.close

```lua
adc.close(id)
```

关闭adc通道

## 参数表

Name | Type | Description
-----|------|--------------
`id`|`int`| 通道id,与具体设备有关,通常从0开始

## 返回值

> *无返回值*

## 调用示例

```lua
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.read(2))
end
adc.close(2)
```


