---
title: luat_lib_gpio
path: luat_lib_gpio.c
module: gpio
summary: GPIO操作
version: 1.0
date: 2020.03.30
---
--------------------------------------------------
# l_gpio_set

```c
static int l_gpio_set(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_gpio_get

```c
static int l_gpio_get(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_gpio_close

```c
static int l_gpio_close(lua_State *L)
```


## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_gpio_setup

```c
static int l_gpio_setup(lua_State *L)
```

设置管脚功能
@funtion gpio.setup(pin, mode, pull)
@int pin 针脚编号,必须是数值
@any mode 输入输出模式. 数字0/1代表输出模式,nil代表输入模式,function代表中断模式
@int pull 上拉下列模式, 可以是gpio.PULLUP 或 gpio.PULLDOWN, 需要根据实际硬件选用
@int irq 中断触发模式, 上升沿gpio.RISING, 下降沿gpio.FALLING, 上升和下降都要gpio.BOTH.默认是RISING
@return any 输出模式返回设置电平的闭包, 输入模式和中断模式返回获取电平的闭包
@usage 
-- 设置gpio17为输入
gpio.setup(17, nil) 
@usage 
-- 设置gpio17为输出
gpio.setup(17, 0) 
@usage 
-- 设置gpio27为中断
gpio.setup(27, function(val) print("IRQ_27") end, gpio.RISING)

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_gpio_set

```c
static int l_gpio_set(lua_State *L)
```

设置管脚电平
@api gpio.set(pin, value)
@int pin 针脚编号,必须是数值
@int value 电平, 可以是 高电平gpio.HIGH, 低电平gpio.LOW, 或者直接写数值1或0
@return nil
@usage
-- 设置gpio17为低电平
gpio.set(17, 0) 

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_gpio_get

```c
static int l_gpio_get(lua_State *L)
```

获取管脚电平
@api gpio.get(pin)
@int pin 针脚编号,必须是数值
@return value 电平, 高电平gpio.HIGH, 低电平gpio.LOW, 对应数值1和0
@usage 
-- 获取gpio17的当前电平
gpio.get(17) 

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_gpio_close

```c
static int l_gpio_close(lua_State *L)
```

关闭管脚功能(高阻输入态),关掉中断
@api gpio.close(pin)
@int pin 针脚编号,必须是数值
@return nil 无返回值,总是执行成功
@usage
-- 关闭gpio17
gpio.close(17)

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


