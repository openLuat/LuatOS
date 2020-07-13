---
module: pm
summary: 电源管理
version: 1.0
date: 2020.07.02
---

--------------------------------------------------
# pm.request

```lua
pm.request(mode)
```

*
请求进入指定的休眠模式

## 参数表

Name | Type | Description
-----|------|--------------
`mode`|`int`| 休眠模式,例如pm.IDLE/LIGHT/DEEP/HIB

## 返回值

No. | Type | Description
----|------|--------------
1 |`boolean`| 处理结果,即使返回成功,也不一定会进入, 也不会马上进入

## 调用示例

```lua
-- 请求进入休眠模式
pm.request(pm.HIB)
```

## C API

```c
static int l_pm_request(lua_State *L)
```


--------------------------------------------------
# pm.force

```lua
pm.force(mode)
```

*
强制进入指定的休眠模式

## 参数表

Name | Type | Description
-----|------|--------------
`mode`|`int`| 休眠模式,仅pm.DEEP/HIB

## 返回值

No. | Type | Description
----|------|--------------
1 |`boolean`| 处理结果,若返回成功,大概率会马上进入该休眠模式

## 调用示例

```lua
-- 请求进入休眠模式
pm.force(pm.HIB)
```

## C API

```c
static int l_pm_force(lua_State *L)
```


--------------------------------------------------
# pm.check

```lua
pm.check()
```

*
检查休眠状态

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`boolean`| 处理结果,如果能顺利进入休眠,返回true,否则返回false

## 调用示例

```lua
-- 请求进入休眠模式,然后检查是否能真的休眠
pm.request(pm.HIB)
if pm.check() then
    log.info("pm", "it is ok to hib")
else
    pm.force(pm.HIB) -- 强制休眠
end
```

## C API

```c
static int l_pm_check(lua_State *L)
```


