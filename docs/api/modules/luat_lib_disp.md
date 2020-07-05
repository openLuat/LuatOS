---
title: luat_lib_disp
path: luat_lib_disp.c
module: disp
summary: 显示屏控制
version: 1.0
date: 2020.03.30
---
--------------------------------------------------
# disp.init

```lua
disp.init(id, type, port)
```

显示屏初始化

## 参数表

Name | Type | Description
-----|------|--------------
**id**|`int`| 显示器id, 默认值0, 当前只支持0,单个显示屏
**type**|`string`| 显示屏类型,当前仅支持ssd1306,默认值也是ssd1306
**port**|`string`| 接口类型,当前仅支持i2c1,默认值也是i2c1

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 正常初始化1,已经初始化过2,内存不够3

## 调用示例

```lua
-- 初始化i2c1的ssd1306
-- disp.init(0, "ssd1306", "i2c1")
if disp.init() == 1 then
    log.info("显示屏初始化成功")
end
-- 初始化i2c1的ssd1306
-- disp.init(0, "ssd1306", "i2c1")
if disp.init() == 1 then
    log.info("显示屏初始化成功")
end
```
## C API

```c
static int l_disp_init(lua_State *L)
```


--------------------------------------------------
# disp.close

```lua
disp.close(id)
```

关闭显示屏

## 参数表

Name | Type | Description
-----|------|--------------
**id**|`int`| 显示器id, 默认值0, 当前只支持0,单个显示屏

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
disp.close()
```
## C API

```c
static int l_disp_close(lua_State *L)
```


--------------------------------------------------
# disp.clear

```lua
disp.clear(id)
```


## 参数表

Name | Type | Description
-----|------|--------------
**id**|`int`| 显示器id, 默认值0, 当前只支持0,单个显示屏

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
disp.clear(0)
```
## C API

```c
static int l_disp_clear(lua_State *L)
```


--------------------------------------------------
# disp.update

```lua
disp.update(id)
```

把显示数据更新到屏幕

## 参数表

Name | Type | Description
-----|------|--------------
**id**|`int`| 显示器id, 默认值0, 当前只支持0,单个显示屏

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
disp.update(0)
```
## C API

```c
static int l_disp_update(lua_State *L)
```


--------------------------------------------------
# l_disp_draw_text

```c
static int l_disp_draw_text(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


