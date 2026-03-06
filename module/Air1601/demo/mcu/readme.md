## 演示模块概述

1、main.lua：主程序入口；

2、mcu_test.lua：MCU功能测试模块；

## 演示功能概述

使用Air1601开发板测试MCU相关功能，包括：

- MCU死机时的处理模式设置
- 唯一ID获取与显示
- 系统tick计数功能测试
- 64位tick计数和差值计算
- 微秒、毫秒、秒级别的时间计数
- 16进制字符串转换输出

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

## **演示软件环境**

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/) ；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、通过luatools工具查看下面日志：

```lua
[2026-03-03 14:24:19.111][LTOS/N][000000000.016]:I/user.mcu ticks: 0
[2026-03-03 14:24:19.111][LTOS/N][000000000.016]:I/user.mcu 获取每秒的tick数量: 50
[2026-03-03 14:24:19.111][LTOS/N][000000000.016]:I/user.mcu tick64: 53FE180000000000 ticks per us: 100
[2026-03-03 14:24:19.111][LTOS/N][000000000.017]:D/heap skip ROM free 147001ba
[2026-03-03 14:24:19.111][LTOS/N][000000000.017]:D/heap skip ROM free 147007d9
[2026-03-03 14:24:19.111][LTOS/N][000000000.117]:I/user.mcu dtick64 result: false diff: -10039838
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu us: 0 117258
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu ms: 0 117
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu sec: 0 0
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu string 0x2009fffc
```
