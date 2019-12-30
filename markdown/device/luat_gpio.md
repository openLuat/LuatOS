# GPIO

## 基本信息

* 起草日期: 2019-12-18
* 设计人员: [wendal](https://github.com/wendal)

## 为什么需要GPIO

* 读取外部输入的电平信号
* 输出指定电平

## 设计思路和边界

* 管理并抽象GPIO的C API, 提供一套Lua API供用户代码调用

## C API(平台层)

```C
int luat_gpio_setup(luat_gpio_t* gpio);
int luat_gpio_set(int pin, int level);
int luat_gpio_get(int pin);
```

## Lua API

## 常量

```lua
gpio.INPUT  -- 输入模式
gpio.OUTPUT -- 输出模式
gpio.PULLDOWN -- 下拉
gpio.PULLUP -- 上拉
gpio.HIGH
gpio.LOW
```

### 进入指定的功耗级别

```lua
gpio.setup(PIN, gpio.gpio.INPUT, function(t) end, gpio.PULLUP)
gpio.set(PIN, gpio.HIGH)
gpio.get(PIN)
```
## 相关知识点

* [Luat核心机制](luat_core.md)

