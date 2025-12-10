## 演示模块概述

1、main.lua：主程序入口；

2、pwm_app.lua：PWM 输出功能模块；



注意事项：

1、本 demo 演示所使用的是 Air8101 模组的 PWM2 通道（GPIO24，PIN33）；

2、PWM 功能需要使用 V2xxx 版本固件，固件下载链接：https://docs.openluat.com/air8101/luatos/firmware/；

## 演示功能概述

使用 Air8101 核心板搭配 PWM 库演示 PWM 输出功能；

PWM 库目前有两套 API 风格：

1、旧风格 PWM 演示：

- 使用 pwm.open() 函数一次性完成 PWM 通道的配置与启动
- 使用 pwm.close() 函数关闭 PWM 通道
- 旧风格 PWM 接口不支持动态调整参数

2、新风格 PWM 演示：

- 使用 pwm.setup() 函数进行 PWM 参数配置
- 使用 pwm.start() 函数开启 PWM 通道进行 PWM 输出
- 使用 pwm.setDuty() 函数动态调整占空比，支持在开启 PWM 通道后调用
- 使用 pwm.setFreq() 函数动态调整信号频率，支持在开启 PWM 通道后调用
- 新风格 PWM 接口支持实时动态调整占空比和信号频率

## 演示硬件环境

1、Air8101 核心板一块

2、TYPE-C USB数据线一根

3、杜邦线若干

4、逻辑分析仪或者示波器，用于观察 PWM 输出的波形

5、代码中选用的 PWM 通道是 Air8101 模组的 PWM2 通道（GPIO24，PIN33）

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8101 V2xxx 版本](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

1、搭建好硬件环境

2、Luatools 工具烧录内核固件和 demo 脚本代码

3、烧录成功后，自动开机运行

4、正常运行情况时的日志如下：

```
[2025-12-10 09:38:25.280] luat:U(2057):I/user.main PWM 001.000.000
[2025-12-10 09:38:25.287] luat:U(2082):I/user.PWM PWM2 通道配置成功（GPIO24，PIN33）
[2025-12-10 09:38:25.287] luat:U(2083):I/user.PWM PWM 综合演示任务开始
[2025-12-10 09:38:25.287] luat:U(2083):I/user.PWM 旧风格 PWM 示例开始
[2025-12-10 09:38:25.287] luat:D(2084):pwm:pwm(2) gpio init : pwm_pin 24
[2025-12-10 09:38:25.287] luat:U(2085):I/user.PWM PWM2 通道开启成功: 信号频率 1000 Hz, 分频精度 100, 占空比 45%
[2025-12-10 09:38:26.288] luat:U(3088):I/user.PWM PWM2 通道已关闭
[2025-12-10 09:38:27.314] luat:D(4089):pwm:pwm(2) gpio init : pwm_pin 24
[2025-12-10 09:38:27.314] luat:U(4089):I/user.PWM PWM2 通道开启成功: 信号频率 500 Hz, 分频精度 100, 占空比 60%
[2025-12-10 09:38:29.321] luat:U(6091):I/user.PWM PWM2 通道已关闭
[2025-12-10 09:38:30.321] luat:D(7093):pwm:pwm(2) gpio init : pwm_pin 24
[2025-12-10 09:38:30.321] luat:U(7094):I/user.PWM PWM2 通道开启成功: 信号频率 300 Hz, 分频精度 100, 占空比 80%
[2025-12-10 09:38:33.323] luat:U(10095):I/user.PWM PWM2 通道已关闭
[2025-12-10 09:38:33.323] luat:U(10096):I/user.PWM 旧风格 PWM 示例结束
[2025-12-10 09:38:36.320] luat:U(13096):I/user.PWM 新风格 PWM 示例开始
[2025-12-10 09:38:36.320] luat:U(13097):I/user.PWM PWM2 配置成功: 信号频率 1000 Hz, 分频精度 100, 占空比 50%
[2025-12-10 09:38:36.320] luat:D(13098):pwm:pwm(2) gpio init : pwm_pin 24
[2025-12-10 09:38:36.320] luat:U(13098):I/user.PWM PWM2 启动成功
[2025-12-10 09:38:38.302] luat:U(15099):I/user.PWM PWM2 占空比更新为 25%
[2025-12-10 09:38:40.328] luat:U(17100):I/user.PWM PWM2 频率更新为 2000 Hz
[2025-12-10 09:38:42.326] luat:U(19102):I/user.PWM PWM2 停止成功
[2025-12-10 09:38:42.326] luat:U(19103):I/user.PWM 新风格 PWM 示例结束
[2025-12-10 09:38:42.326] luat:U(19103):I/user.PWM PWM 综合演示任务结束
```

5、使用逻辑分析仪或者示波器观察 PWM 输出波形是否与配置的参数一致