# LuatOS

LuatOS是运行在嵌入式硬件的实时操作系统,只需要少量内存的flash空间就能运行,用户编写lua代码就可完成各种功能

Lua base RTOS, build for many embedded systems

1. 基于Lua 5.3.5
2. 低内存需求, 最低32kb, 96kb flash空间
3. 硬件抽象层兼容arm/risc-v等
4. 可测试,可模拟(qemu)
5. 在线升级
6. 可裁剪,可扩展


----------------------------------------------------------------------------------
## 总体架构

![总体架构](system.jpg)

----------------------------------------------------------------------------------
## 资源

* 参阅 [Luat 平台层](markdown/core/luat_platform.md) 
* [文档索引](docs.md)
* [如何开发](markdown/proj/how_to_dev.md)
* [预编译固件](https://github.com/openLuat/LuatOS/releases)

----------------------------------------------------------------------------------
## 配套

TODO: 构建工具链,IDE,刷机工具,等等


## 授权协议

[MIT License](LICENSE)
