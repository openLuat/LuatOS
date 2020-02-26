# LuatOS

[![license](https://img.shields.io/github/license/openLuat/LuatOS)](/LICENSE)
[![rtt-w60x ci](https://github.com/openLuat/LuatOS/workflows/rtt-w60x/badge.svg)](https://github.com/openLuat/LuatOS/actions?query=workflow%3Artt-w60x)
[![qemu ci](https://github.com/openLuat/LuatOS/workflows/qemu-vexpress-a9/badge.svg)](https://github.com/openLuat/LuatOS/actions?query=workflow%3Aqemu-vexpress-a9)
[![issue](https://img.shields.io/github/issues/openLuat/LuatOS)](https://github.com/openLuat/LuatOS/issues)

LuatOS是运行在嵌入式硬件的实时操作系统,只需要少量内存的flash空间就能运行,用户编写lua代码就可完成各种功能

Lua base RTOS, build for many embedded systems

1. 基于Lua 5.3.5
2. 低内存需求, 最低32kb, 96kb flash空间
3. 硬件抽象层兼容M3/arm/risc-v等
4. 可测试,可模拟(qemu)
5. 在线升级
6. 可裁剪,可扩展

QQ群: 1061642968

----------------------------------------------------------------------------------
## 总体架构

![总体架构](system.jpg)

----------------------------------------------------------------------------------
## 资源

* 参阅 [Luat 平台层](markdown/core/luat_platform.md)
* [文档索引](docs.md)
* [搭建开发环境](markdown/proj/workspace.md)
* [如何开发](markdown/proj/how_to_dev.md)
* [预编译固件](https://github.com/openLuat/LuatOS/releases)

----------------------------------------------------------------------------------
## 配套

TODO: 构建工具链,IDE,刷机工具,等等

## 使用到的开源项目

* [rt-thread](https://github.com/RT-Thread/rt-thread) 国产rtos
* [rtt-ds18b20](https://github.com/willianchanlovegithub/ds18b20) 在RT-Thread环境下读取ds18b20
* [LuaTask](https://github.com/openLuat/Luat_2G_RDA_8955) 合宙LuaTask
* [iRTU](https://github.com/hotdll/iRTU) 基于Luat的DTU
* [airkissOpen](https://github.com/heyuanjie87/airkissOpen)

## 授权协议

[MIT License](LICENSE)
