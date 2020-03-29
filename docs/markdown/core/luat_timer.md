# Luat定时器

## 基本信息

* 起草日期: 2019-11-25
* 设计人员: [wendal](https://github.com/wendal)

## 为什么需要定时器

1. 单次定时的需要, 例如10分钟后执行温度测量
2. 循环定时的需要, 每5分钟联网一次,发送心跳
3. `sys.wait`的需要, 通过定时器机制实现lua的延时执行

## 设计思路和边界

1. 基于rtos的timer API进行设计
2. 定时器超时后, 生产消息并发送到 `消息总线` , 由`rtos.receive`进行消费
3. 底层支持循环定时.

## C API(平台层)

### 数据结构

```c
#define LUAT_TIMER_MAXID ((size_t) 0xFFFF)
```

### 接口API

```c
uint32_t luat_timer_start(luat_timer_t* timer);
uint32_t luat_timer_stop(luat_timer_t* timer);
```

## Lua API

## 常量

备用

```lua
timer.HW -- "HW" 硬件定时器
timer.OS -- "OS" 软件定时器
```

### 启动定时器

```lua
-- timerout 超时时长, 数值, 1-0xFFFFFFFF, 单位毫秒, 大于0才有意义
-- repeat   额外重复次数, 数值, 1-0xFFFFFFFF, 单位毫秒,默认0
local t = timer.start(timeout, _repeat, function() end)
if not t then
    -- 启动成功
else
    -- 启动失败, 可能id已满或timeout值错误
end
```

### 关闭定时器(含删除)

```lua
-- timer_id 时钟id, 数值, 0-0xFF, 取决于LUAT_TIMER_MAXID
timer.stop(t)
-- 只要传入数值型的id, timer_stop总会成功
```

## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)
* [消息总线](/markdown/core/msgbus)
