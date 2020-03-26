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

```c
#define Luat_GPIO_LOW                 0x00
#define Luat_GPIO_HIGH                0x01

#define Luat_GPIO_OUTPUT         0x00
#define Luat_GPIO_INPUT          0x01
#define Luat_GPIO_INPUT_PULLUP   0x02
#define Luat_GPIO_INPUT_PULLDOWN 0x03
#define Luat_GPIO_OUTPUT_OD      0x04

#define Luat_GPIO_RISING             0x00
#define Luat_GPIO_FALLING            0x01
#define Luat_GPIO_RISING_FALLING     0x02

int luat_gpio_setup(luat_gpio_t* gpio);
int luat_gpio_set(int pin, int level);
int luat_gpio_get(int pin);
int luat_gpio_close(int pin);
```

## Lua API

## 常量

```lua
gpio.OUTPUT          -- 输出模式,推挽
gpio.OUTPUT_OD       -- 输出模式,开漏
gpio.INPUT_PULLUP    -- 输入模式,上拉
gpio.INPUT_PULLDOWN  -- 输入模式,下拉
gpio.INPUT           -- 输入模式,缺省
gpio.LOW             -- 低电平
gpio.HIGH            -- 高电平
```

### 进入指定的功耗级别

```lua
-- 简单输入
gpio.setup(PIN, gpio.INPUT)
-- 简单输出
gpio.setup(PIN, gpio.OUTPUT, 0)
-- 中断,回调函数的t的值为 GPIO_RISING 或 GPIO_FALLING
-- 最后一个参数为中断模式, GPIO_RISING_FALLING就是默认值, 双边触发
gpio.setup(PIN, gpio.INPUT, function(t) end, gpio.GPIO_RISING_FALLING)
-- 设置输出为高电平
gpio.set(PIN, gpio.HIGH)
-- 获取输入电平或当前的输出电平
gpio.get(PIN)
-- 关闭引脚, 事实上是输入高阻态
gpio.close(PIN)
```
## 相关知识点

* [Luat核心机制](/markdown/device/luat_core)

