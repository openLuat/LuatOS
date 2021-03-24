---
module: u8g2
summary: u8g2图形处理库
version: 1.0
date: 2021.01.25
---

--------------------------------------------------
# u8g2.begin

```lua
u8g2.begin("ssd1306")
```

u8g2显示屏初始化

## 参数表

Name | Type | Description
-----|------|--------------
`"ssd1306"`|`string`| 配置信息

## 返回值

> `int`: 正常初始化1,已经初始化过2,内存不够3,初始化失败返回4

## 调用示例

```lua
-- 初始化i2c1的ssd1306
u8g2.begin("ssd1306")
```


--------------------------------------------------
# u8g2.close

```lua
u8g2.close()
```

关闭显示屏

## 参数表

> 无参数

## 返回值

> *无返回值*

## 调用示例

```lua
-- 关闭disp,再次使用disp相关API的话,需要重新初始化
u8g2.close()
```


--------------------------------------------------
# u8g2.ClearBuffer

```lua
u8g2.ClearBuffer()
```

清屏，清除内存帧缓冲区中的所有像素

## 参数表

> 无参数

## 返回值

> *无返回值*

## 调用示例

```lua
-- 清屏
u8g2.ClearBuffer()
```


--------------------------------------------------
# u8g2.SendBuffer

```lua
u8g2.SendBuffer()
```

将数据更新到屏幕，将存储器帧缓冲区的内容发送到显示器

## 参数表

> 无参数

## 返回值

> *无返回值*

## 调用示例

```lua
-- 把显示数据更新到屏幕
u8g2.SendBuffer()
```


--------------------------------------------------
# u8g2.DrawUTF8

```lua
u8g2.DrawUTF8(str, x, y)
```

在显示屏上画一段文字，在显示屏上画一段文字,要调用u8g2.SendBuffer()才会更新到屏幕

## 参数表

Name | Type | Description
-----|------|--------------
`str`|`string`| 文件内容
`x`|`int`| 横坐标
`y`|`int`| 竖坐标

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawUTF8("wifi is ready", 10, 20)
```


--------------------------------------------------
# u8g2.SetFontMode

```lua
u8g2.SetFontMode(mode)
```

设置字体模式

## 参数表

Name | Type | Description
-----|------|--------------
`mode`|`int`| mode字体模式，启用（1）或禁用（0）透明模式

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.SetFontMode(1)
```


--------------------------------------------------
# u8g2.SetFont

```lua
u8g2.SetFont(font)
```

设置字体

## 参数表

Name | Type | Description
-----|------|--------------
`font`|`string`| font, "u8g2_font_ncenB08_tr"为纯英文8x8字节,"u8g2_font_wqy12_t_gb2312"为12x12全中文,"u8g2_font_unifont_t_symbols"为符号.

## 返回值

> *无返回值*

## 调用示例

```lua
-- 设置为中文字体,对之后的drawStr有效,使用中文字体需在luat_base.h开启#define USE_U8G2_WQY12_T_GB2312
u8g2.setFont("u8g2_font_wqy12_t_gb2312")
```


--------------------------------------------------
# u8g2.GetDisplayHeight

```lua
u8g2.GetDisplayHeight()
```

获取显示屏高度

## 参数表

> 无参数

## 返回值

> `int`: 显示屏高度

## 调用示例

```lua
-- 
u8g2.GetDisplayHeight()
```


--------------------------------------------------
# u8g2.GetDisplayWidth

```lua
u8g2.GetDisplayWidth()
```

获取显示屏宽度

## 参数表

> 无参数

## 返回值

> `int`: 显示屏宽度

## 调用示例

```lua
-- 
u8g2.GetDisplayWidth()
```


--------------------------------------------------
# u8g2.DrawLine

```lua
u8g2.DrawLine(x0, y0, x1, y1)
```

在两点之间画一条线.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 第一个点的X位置.
`y0`|`int`| 第一个点的Y位置.
`x1`|`int`| 第二个点的X位置.
`y1`|`int`| 第二个点的Y位置.

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawLine(20, 5, 5, 32)
```


--------------------------------------------------
# u8g2.DrawCircle

```lua
u8g2.DrawCircle(x0, y0, rad, opt)
```

在x,y位置画一个半径为rad的空心圆.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 圆心位置
`y0`|`int`| 圆心位置
`rad`|`int`| 圆半径.
`opt`|`int`| 选择圆的部分或全部.

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawCircle(60,30,8,15)
```


--------------------------------------------------
# u8g2.DrawDisc

```lua
u8g2.DrawDisc(x0, y0, rad, opt)
```

在x,y位置画一个半径为rad的实心圆.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 圆心位置
`y0`|`int`| 圆心位置
`rad`|`int`| 圆半径.
`opt`|`int`| 选择圆的部分或全部.

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawDisc(60,30,8,15)
```


--------------------------------------------------
# u8g2.DrawEllipse

```lua
u8g2.DrawEllipse(x0, y0, rx, ry, opt)
```

在x,y位置画一个半径为rad的空心椭圆.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 圆心位置
`y0`|`int`| 圆心位置
`rx`|`int`| 椭圆大小
`ry`|`int`| 椭圆大小
`opt`|`int`| 选择圆的部分或全部.

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawEllipse(60,30,8,15)
```


--------------------------------------------------
# u8g2.DrawFilledEllipse

```lua
u8g2.DrawFilledEllipse(x0, y0, rx, ry, opt)
```

在x,y位置画一个半径为rad的实心椭圆.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 圆心位置
`y0`|`int`| 圆心位置
`rx`|`int`| 椭圆大小
`ry`|`int`| 椭圆大小
`opt`|`int`| 选择圆的部分或全部.

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawFilledEllipse(60,30,8,15)
```


--------------------------------------------------
# u8g2.DrawBox

```lua
u8g2.DrawBox(x, y, w, h)
```

从x / y位置（左上边缘）开始绘制一个框（填充的框）.

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 左上边缘的X位置
`y`|`int`| 左上边缘的Y位置
`w`|`int`| 盒子的宽度
`h`|`int`| 盒子的高度

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawBox(3,7,25,15)
```


--------------------------------------------------
# u8g2.DrawFrame

```lua
u8g2.DrawFrame(x, y, w, h)
```

从x / y位置（左上边缘）开始绘制一个框（空框）.

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 左上边缘的X位置
`y`|`int`| 左上边缘的Y位置
`w`|`int`| 盒子的宽度
`h`|`int`| 盒子的高度

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawFrame(3,7,25,15)
```


--------------------------------------------------
# u8g2.DrawRBox

```lua
u8g2.DrawRBox(x, y, w, h, r)
```

绘制一个从x / y位置（左上边缘）开始具有圆形边缘的填充框/框架.

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 左上边缘的X位置
`y`|`int`| 左上边缘的Y位置
`w`|`int`| 盒子的宽度
`h`|`int`| 盒子的高度
`r`|`int`| 四个边缘的半径

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawRBox(3,7,25,15)
```


--------------------------------------------------
# u8g2.DrawRFrame

```lua
u8g2.DrawRFrame(x, y, w, h, r)
```

绘制一个从x / y位置（左上边缘）开始具有圆形边缘的空框/框架.

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 左上边缘的X位置
`y`|`int`| 左上边缘的Y位置
`w`|`int`| 盒子的宽度
`h`|`int`| 盒子的高度
`r`|`int`| 四个边缘的半径

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawRFrame(3,7,25,15)
```


--------------------------------------------------
# u8g2.DrawGlyph

```lua
u8g2.DrawGlyph(x, y, encoding)
```

绘制一个图形字符。字符放置在指定的像素位置x和y.

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 字符在显示屏上的位置
`y`|`int`| 字符在显示屏上的位置
`encoding`|`int`| 字符的Unicode值

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.SetFont(u8g2_font_unifont_t_symbols)
u8g2.DrawGlyph(5, 20, 0x2603)	-- dec 9731/hex 2603 Snowman
```


--------------------------------------------------
# u8g2.DrawTriangle

```lua
u8g2.DrawTriangle(x0, y0, x1, y1, x2, y2)
```

绘制一个三角形（实心多边形）.

## 参数表

Name | Type | Description
-----|------|--------------
`x0`|`int`| 点0X位置
`y0`|`int`| 点0Y位置
`x1`|`int`| 点1X位置
`y1`|`int`| 点1Y位置
`x2`|`int`| 点2X位置
`y2`|`int`| 点2Y位置

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.DrawTriangle(20,5, 27,50, 5,32)
```


--------------------------------------------------
# u8g2.SetBitmapMode

```lua
u8g2.SetBitmapMode(mode)
```

定义位图函数是否将写入背景色

## 参数表

Name | Type | Description
-----|------|--------------
`mode`|`int`| mode字体模式，启用（1）或禁用（0）透明模式

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
u8g2.SetBitmapMode(1)
```


