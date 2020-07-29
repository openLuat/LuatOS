---
module: disp
summary: 显示屏控制
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# disp.init

```lua
disp.init(conf)
```

显示屏初始化

## 参数表

Name | Type | Description
-----|------|--------------
`conf`|`table`| 配置信息

## 返回值

> `int`: 正常初始化1,已经初始化过2,内存不够3,初始化失败返回4

## 调用示例

```lua
-- 初始化i2c1的ssd1306
if disp.init({mode="i2c_sw", pin0=17, pin1=18}) == 1 then
    log.info("disp", "disp init complete")
end
```


--------------------------------------------------
# disp.close

```lua
disp.close()
```

关闭显示屏

## 参数表

> 无参数

## 返回值

> *无返回值*

## 调用示例

```lua
-- 关闭disp,再次使用disp相关API的话,需要重新初始化
disp.close()
```


--------------------------------------------------
# disp.update

```lua
disp.update()
```

把显示数据更新到屏幕

## 参数表

> 无参数

## 返回值

> *无返回值*

## 调用示例

```lua
-- 把显示数据更新到屏幕
disp.update()
```


--------------------------------------------------
# disp.drawStr

```lua
disp.drawStr(content, x, y)
```

在显示屏上画一段文字,要调用disp.update才会更新到屏幕

## 参数表

Name | Type | Description
-----|------|--------------
`content`|`string`| 文件内容
`x`|`int`| 横坐标
`y`|`int`| 竖坐标

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
disp.drawStr("wifi is ready", 10, 20)
```


--------------------------------------------------
# disp.setFont

```lua
disp.setFont(fontId)
```

设置字体

## 参数表

Name | Type | Description
-----|------|--------------
`fontId`|`int`| 字体id, 默认0,纯英文8x8字节. 如果支持中文支持, 那么1代表12x12的中文字体.

## 返回值

> *无返回值*

## 调用示例

```lua
-- 设置为中文字体,对之后的drawStr有效
disp.setFont(1)
```


