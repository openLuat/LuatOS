# 电源及低功耗管理

## 基本信息

* 起草日期: 2019-11-28
* 设计人员: [wendal](https://github.com/wendal)

## 为什么需要电源及低功耗管理

* mcu通常提供多个低功耗级别,部分级别可以继续运行lua, 部分只能跑C

## 设计思路和边界

* 管理并抽象电源的C API, 提供一套Lua API供用户代码调用
* 用户可申请直接进入指定的低功耗级别

## C API(平台层)

```c
uint32_t luat_pm_mode(uint8_t mode);
```

## Lua API

## 常量

```lua
pm.IDLE   -- 空闲模式,功耗高
pm.SLEEP1 -- 休眠模式1, 主内存不掉电,低功耗内存(lpmem)掉电
pm.SLEEP2 -- 休眠模式2, 主内存掉电,低功耗内存(lpmem)不掉电
pm.HIB    -- 停止模式, 仅timer或gpio可以唤醒
```

### 进入指定的功耗级别

```lua
pm.mode(mode)
```
## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)

