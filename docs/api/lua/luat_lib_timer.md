---
module: timer
summary: 操作底层定时器
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# timer.mdelay

```lua
timer.mdelay(timeout)
```

硬阻塞指定时长,期间没有任何luat代码会执行,包括底层消息处理机制

## 参数表

Name | Type | Description
-----|------|--------------
`timeout`|`int`| 阻塞时长

## 返回值

> *无返回值*

## 调用示例

```lua
-- 本方法通常不会使用,除非你很清楚会发生什么
timer.mdelay(10)
```


