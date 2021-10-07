# IR

## 基本信息

* 起草日期: 2021-10-07
* 设计人员: [chenxuuu](https://github.com/chenxuuu)

## 用途

* 实现常用的红外遥控协议

## 设计思路和边界

* 使用芯片自带的pwm，输出38k/36kHz频率
* 或是直接使用外部pwm源，只用gpio控制通断
* 需要支持us级精度延时
* 至少实现NEC、RC5、sony协议，其他协议待定
* 接收解析功能待定，先能发再说

## C API(平台层)

直接使用gpio与pwm的接口

## Lua API

### 常量

目前无

### 用例

```lua
ir.sendNEC(
    0x12,--cmd
    0x34,--data
    10,--重复次数
)
```
