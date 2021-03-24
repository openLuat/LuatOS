---
module: eink
summary: 墨水屏操作库
version: 1.0
date: 2020.11.14
---

--------------------------------------------------
# eink.setup

```lua
eink.setup(full, spiid)
```

初始化eink

## 参数表

Name | Type | Description
-----|------|--------------
`full`|`int`| 全屏刷新1,局部刷新0,默认是全屏刷新
`spiid`|`int`| 所在的spi,默认是0

## 返回值

> `boolean`: 成功返回true,否则返回false


--------------------------------------------------
# eink.clear

```lua
eink.clear()
```

清除绘图缓冲区

## 参数表

> 无参数

## 返回值

> *无返回值*


--------------------------------------------------
# eink.setWin

```lua
eink.setWin(width, height, rotate)
```

设置窗口

## 参数表

Name | Type | Description
-----|------|--------------
`width`|`int`| width  宽度
`height`|`int`| height 高度
`rotate`|`int`| rotate 显示方向,0/1/2/3, 相当于旋转0度/90度/180度/270度

## 返回值

> *无返回值*


--------------------------------------------------
# eink.getWin

```lua
eink.getWin()
```

获取窗口信息

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| width  宽
2 |`int`| height 高
3 |`int`| rotate 旋转方向


--------------------------------------------------
# eink.print

```lua
eink.print(x, y, str, colored, font)
```

绘制字符串(仅ASCII)

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| x坐标
`y`|`int`| y坐标
`str`|`string`| 字符串
`colored`|`int`| 默认是0
`font`|`font`| 字体大小,默认12

## 返回值

> *无返回值*


--------------------------------------------------
# eink.printcn

```lua
eink.printcn(x, y, str, colored, font)
```

绘制字符串,支持中文

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| x坐标
`y`|`int`| y坐标
`str`|`string`| 字符串
`colored`|`int`| 默认是0
`font`|`font`| 字体大小,默认12

## 返回值

> *无返回值*


--------------------------------------------------
# eink.show

```lua
eink.show(x, y)
```

将缓冲区图像输出到屏幕

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| x 输出的x坐标,默认0
`y`|`int`| y 输出的y坐标,默认0

## 返回值

> *无返回值*


--------------------------------------------------
# eink.line

```lua
eink.line(x, y, x2, y2, colored)
```

缓冲区绘制线

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 起点x坐标
`y`|`int`| 起点y坐标
`x2`|`int`| 终点x坐标
`y2`|`int`| 终点y坐标
`colored`|`null`| *无*

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
eink.line(0, 0, 10, 20, 0)
```


--------------------------------------------------
# eink.rect

```lua
eink.rect(x, y, x2, y2, colored, fill)
```

缓冲区绘制矩形

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 左上顶点x坐标
`y`|`int`| 左上顶点y坐标
`x2`|`int`| 右下顶点x坐标
`y2`|`int`| 右下顶点y坐标
`colored`|`int`| 默认是0
`fill`|`int`| 是否填充,默认是0,不填充

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
eink.rect(0, 0, 10, 20)
eink.rect(0, 0, 10, 20, 1) -- Filled
```


--------------------------------------------------
# eink.circle

```lua
eink.circle(x, y, radius, colored, fill)
```

缓冲区绘制圆形

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| 圆心x坐标
`y`|`int`| 圆心y坐标
`radius`|`int`| 半径
`colored`|`int`| 默认是0
`fill`|`int`| 是否填充,默认是0,不填充

## 返回值

> *无返回值*

## 调用示例

```lua
-- 
eink.circle(0, 0, 10)
eink.circle(0, 0, 10, 1, 1) -- Filled
```


--------------------------------------------------
# eink.qrcode

```lua
eink.qrcode(x, y, str, version)
```

缓冲区绘制QRCode

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| x坐标
`y`|`int`| y坐标
`str`|`string`| 二维码的内容
`version`|`int`| 二维码版本号

## 返回值

> *无返回值*


--------------------------------------------------
# eink.bat

```lua
eink.bat(x, y, bat)
```

缓冲区绘制电池

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| x坐标
`y`|`int`| y坐标
`bat`|`int`| 电池电压,单位毫伏

## 返回值

> *无返回值*


--------------------------------------------------
# eink.weather_icon

```lua
eink.weather_icon(x, y, code)
```

缓冲区绘制天气图标

## 参数表

Name | Type | Description
-----|------|--------------
`x`|`int`| x坐标
`y`|`int`| y坐标
`code`|`int`| 天气代号

## 返回值

> *无返回值*


--------------------------------------------------
# eink.model

```lua
eink.model(m)
```

设置墨水屏驱动型号

## 参数表

Name | Type | Description
-----|------|--------------
`m`|`int`| 型号名称, 例如 eink.model(eink.MODEL_1in54_V2)

## 返回值

> *无返回值*


