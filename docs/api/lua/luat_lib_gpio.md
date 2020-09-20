---
module: gpio
summary: GPIO操作
version: 1.0
date: 2020.03.30
---

--------------------------------------------------
# gpio.setup

```lua
gpio.setup(pin, mode, pull, ?)
```

设置管脚功能

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| pin 针脚编号,必须是数值
`mode`|`any`| mode 输入输出模式. 数字0/1代表输出模式,nil代表输入模式,function代表中断模式
`pull`|`int`| pull 上拉下列模式, 可以是gpio.PULLUP 或 gpio.PULLDOWN, 需要根据实际硬件选用
`?`|`int`| irq 中断触发模式, 上升沿gpio.RISING, 下降沿gpio.FALLING, 上升和下降都要gpio.BOTH.默认是RISING

## 返回值

> `any`: 输出模式返回设置电平的闭包, 输入模式和中断模式返回获取电平的闭包

## 调用示例

```lua
-- 设置gpio17为输入
gpio.setup(17, nil) 
-------------------------
-- 设置gpio17为输出
gpio.setup(17, 0) 
-------------------------
-- 设置gpio27为中断
gpio.setup(27, function(val) print("IRQ_27") end, gpio.RISING)
```


--------------------------------------------------
# gpio.set

```lua
gpio.set(pin, value)
```

设置管脚电平

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| pin 针脚编号,必须是数值
`value`|`int`| value 电平, 可以是 高电平gpio.HIGH, 低电平gpio.LOW, 或者直接写数值1或0

## 返回值

> *无返回值*

## 调用示例

```lua
-- 设置gpio17为低电平
gpio.set(17, 0) 
```


--------------------------------------------------
# gpio.get

```lua
gpio.get(pin)
```

获取管脚电平

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| pin 针脚编号,必须是数值

## 返回值

> `value`: 电平, 高电平gpio.HIGH, 低电平gpio.LOW, 对应数值1和0

## 调用示例

```lua
-- 获取gpio17的当前电平
gpio.get(17) 
```


--------------------------------------------------
# gpio.close

```lua
gpio.close(pin)
```

关闭管脚功能(高阻输入态),关掉中断

## 参数表

Name | Type | Description
-----|------|--------------
`pin`|`int`| pin 针脚编号,必须是数值

## 返回值

> *无返回值*

## 调用示例

```lua
-- 关闭gpio17
gpio.close(17)
```


--------------------------------------------------
# gpio.setDefaultPull

```lua
gpio.setDefaultPull(val)
```

设置GPIO脚的默认上拉/下拉设置, 默认是平台自定义(一般为开漏).

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`int`| val 0平台自定义,1上拉, 2下拉

## 返回值

> `boolean`: 传值正确返回true,否则返回false

## 调用示例

```lua
-- 设置gpio.setup的pull默认值为上拉
gpio.setDefaultPull(1)
```


