## 演示模块概述

1、main.lua：主程序入口；

2、test_adc.lua：ADC测量功能模块；

## 演示功能概述

使用Air8000开发板测试ADC功能。

## 演示硬件环境

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、杜邦线若干

4、外部供电电源Air9000P

## 演示软件环境

1\.  [Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；；

2\. 内核固件文件（底层 core 固件文件）[LuatOS-SoC_V1004_Air1601.soc](https://gitee.com/openLuat/LuatOS/releases/tag/v1004.air1601.release)；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、如下是adc通道0设置ADC_RANGE_MIN量程外部供电1.2V，adc通道1设置ADC_RANGE_MAX量程外部供电1.2V，adc通道2设置ADC_RANGE_MAX量程外部供电3.3V，adc通道3设置ADC_RANGE_MIN量程外部供电3.3V的环境下测试的，代码运行结果如下：

这样设置量程和外部供电是为了更直观的观察两种量程下不同供电电压对精准度的影响，可以看到如下测量的数据是符合预期的

对于Air8000：ADC_RANGE_MIN对应量程为0-1.5V，ADC_RANGE_MAX对应量程为0-3.3V。

在外部供电1.2V的情况下，ADC_RANGE_MIN量程获取到的数据更精准；在外部供电3.3V的情况下，ADC_RANGE_MIN量程下会限制在1.5v左右，ADC_RANGE_MAX可以正常测量。

```
[2026-03-09 12:13:27.226][LTOS/N][000000018.087]:I/user.ADC1 处理值: 3198.62 mV (样本数:10)
[2026-03-09 12:13:27.228][LTOS/N][000000018.088]:I/user.ADC5 处理值: 3208.12 mV (样本数:10)
[2026-03-09 12:13:27.231][LTOS/N][000000018.089]:I/user.ADC2 处理值: 3196.12 mV (样本数:10)
[2026-03-09 12:13:27.233][LTOS/N][000000018.090]:I/user.ADC6 处理值: 3029.75 mV (样本数:10)


```
