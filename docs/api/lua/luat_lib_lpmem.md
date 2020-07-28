---
module: lpmem
summary: 操作低功耗不掉电内存块
version: V0002
date: 2020.07.10
---

--------------------------------------------------
# lpmem.read

```lua
lpmem.read(offset, size)
```

读取内存块

## 参数表

Name | Type | Description
-----|------|--------------
`offset`|`int`| 内存偏移量
`size`|`int`| 读取大小,单位字节

## 返回值

> `string`: 读取成功返回字符串,否则返回nil

## 调用示例

```lua
-- 读取1kb的内存
local data = lpmem.read(0, 1024)
```


--------------------------------------------------
# lpmem.write

```lua
lpmem.write(offset, str)
```

写入内存块

## 参数表

Name | Type | Description
-----|------|--------------
`offset`|`int`| 内存偏移量
`str`|`string`| 待写入的数据

## 返回值

> `boolean`: 成功返回true,否则返回false

## 调用示例

```lua
-- 往偏移量为512字节的位置, 写入数据
lpmem.write(512, data)
```


--------------------------------------------------
# lpmem.size

```lua
lpmem.size()
```

获取内存块的总大小

## 参数表

> 无参数

## 返回值

> `int`: 内存块的大小

## 调用示例

```lua
-- 
lpmem.size()
```


