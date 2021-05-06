# 屏幕显示接口

## 基本信息

* 起草日期: 2021-05-26
* 设计人员: [chenxuuu](https://github.com/chenxuuu)

## 有什么用途

提供统一的API对屏幕进行初始化、唤醒、刷新、休眠操作

* 利用zbuff作为缓存
* 只提供屏幕操作功能，屏幕数据处理交给zbuff处理

## 设计思路和边界

## Lua API

使用示例

```lua
-- 创建FrameBuffer的zbuff对象，初始化白色
local buff = zbuff.create({200,200,16},0xffff)

--新建一个屏幕对象，xy偏移默认0
local screen = scr.create("st7735",spi或者i2c编号,rstPin,csPin,x_offset,y_offset)
screen:wake()--唤醒屏幕
--screen:sleep()--休眠屏幕
screen:show(buff)--显示buff内容

buff:pixel(0,3,0)-- 设置具体像素值
buff:drawLine(1, 2, 1, 20, 0) -- 画线操作
buff:drawRect(20, 40, 40, 40, 0) -- 画矩形

screen:show(buff)--显示buff内容
```

## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)
