---
module: lcd
summary: lcd图形处理库
version: 1.0
date: 2021.06.28
---

--------------------------------------------------
# lcd.init

```lua
lcd.init(tp, args)
```

lcd显示屏初始化

## 参数表

Name | Type | Description
-----|------|--------------
tp|`string`| lcd类型, 当前支持st7789/st7735/gc9a01/gc9106l/gc9306/ili9341/custom 
args|`table`| 附加参数,与具体设备有关 

## 返回值

> `int`: 正常初始化true,初始化失败返回false

## 调用示例

```lua
-- 初始化spi0的st7789 注意:lcd初始化之前需要先初始化spi
lcd.init("st7789",{port = 0,pin_cs = 20,pin_dc = 23, pin_pwr = 7,pin_rst = 22,direction = 0,w = 240,h = 320})
```


--------------------------------------------------
# lcd.close

```lua
lcd.close()
```

关闭显示屏

## 参数表

> 无参数

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- 关闭lcd
lcd.close()
```


--------------------------------------------------
# lcd.on

```lua
lcd.on()
```

开启lcd显示屏背光

## 参数表

> 无参数

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- 开启lcd显示屏背光
lcd.on()
```


--------------------------------------------------
# lcd.off

```lua
lcd.off()
```

关闭lcd显示屏背光

## 参数表

> 无参数

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- 关闭lcd显示屏背光
lcd.off()
```


--------------------------------------------------
# lcd.sleep

```lua
lcd.sleep()
```

lcd睡眠

## 参数表

> 无参数

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- lcd睡眠
lcd.sleep()
```


--------------------------------------------------
# lcd.wakeup

```lua
lcd.wakeup()
```

lcd唤醒

## 参数表

> 无参数

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- lcd唤醒
lcd.wakeup()
```


--------------------------------------------------
# lcd.setColor

```lua
lcd.setColor(back,fore)
```

lcd颜色设置

## 参数表

Name | Type | Description
-----|------|--------------
`back`|`int`| 背景色 
`fore`|`int`| 前景色 

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- lcd颜色设置
lcd.setColor(0xFFFF,0x0000)
```


--------------------------------------------------
# lcd.draw

```lua
lcd.draw(x1, y1, x2, y2,color)
```

lcd颜色填充

## 参数表

Name | Type | Description
-----|------|--------------
`x1`|`int`| 左上边缘的X位置. 
`y1`|`int`| 左上边缘的Y位置. 
`x2`|`int`| 右上边缘的X位置. 
`y2`|`int`| 右上边缘的Y位置. 
`color`|`int`| 绘画颜色 

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- lcd颜色填充
buff:writeInt32(0x001F)
lcd.draw(20,30,220,30,buff)
```


--------------------------------------------------
# lcd.clear

```lua
lcd.clear(color)
```

lcd清屏

## 参数表

Name | Type | Description
-----|------|--------------
`color`|`int`| 屏幕颜色 可选参数,默认背景色 

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- lcd清屏
lcd.clear()
```


--------------------------------------------------
# lcd.drawPoint

```lua
lcd.drawPoint(x0,y0,color)
```

画一个点.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 点的X位置. 
`y0`|`int`| 点的Y位置. 
`color`|`int`| 绘画颜色 可选参数,默认前景色 

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- 
lcd.drawPoint(20,30,0x001F)
```


--------------------------------------------------
# lcd.drawLine

```lua
lcd.drawLine(x0,y0,x1,y1,color)
```

在两点之间画一条线.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 第一个点的X位置. 
`y0`|`int`| 第一个点的Y位置. 
`x1`|`int`| 第二个点的X位置. 
`y1`|`int`| 第二个点的Y位置. 
`color`|`int`| 绘画颜色 可选参数,默认前景色 

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- 
lcd.drawLine(20,30,220,30,0x001F)
```


--------------------------------------------------
# lcd.drawRectangle

```lua
lcd.drawRectangle(x0,y0,x1,y1,color)
```

从x / y位置（左上边缘）开始绘制一个框

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 左上边缘的X位置. 
`y0`|`int`| 左上边缘的Y位置. 
`x1`|`int`| 右下边缘的X位置. 
`y1`|`int`| 右下边缘的Y位置. 
`color`|`int`| 绘画颜色 可选参数,默认前景色 

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- 
lcd.drawRectangle(20,40,220,80,0x001F)
```


--------------------------------------------------
# lcd.drawCircle

```lua
lcd.drawCircle(x0,y0,r,color)
```

从x / y位置（圆心）开始绘制一个圆

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 圆心的X位置. 
`y0`|`int`| 圆心的Y位置. 
 `r`     |`int`| 半径. 
`color`|`int`| 绘画颜色 可选参数,默认前景色 

## 返回值

> *`int`: 正常初始化true,初始化失败返回false*

## 调用示例

```lua
-- 
lcd.drawCircle(120,120,20,0x001F)
```

