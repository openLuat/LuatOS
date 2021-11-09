# Air105@LuatOS

## Air105是什么?

合宙Air105是一款QFN88 封装，10mm x 10mm 大小的MCU, 
不仅提供UART/GPIO/I2C/ADC/SPI等基础外设，更提供DAC/USB/DCMI/QSPI/LCDI/KCU等高级外设接口，
内置充电功能，自带5v转3.3V的LDO，4M字节Flash，640K字节RAM。

* UART*4, 其中U0是下载和日志口，其余3个供用户使用
* GPIO*54

## LuatOS为它提供哪些功能

* 基于Lua 5.3.x, 提供95%的原生库支持
* 适配LuaTask,提供极为友好的`sys.lua`
* 文件系统大小512kb,格式littlefs 2.1
* RAM 总大小640K
* Flash 总大小4M

LuatOS大QQ群: 1061642968

## 管脚映射表

请查阅硬件设计手册

开机时仅配置了`UART0_TX/RX`, 其他数字脚均为GPIO脚, 状态为输入高阻.

## 刷机工具

使用Luatools下载, 版本 2.1.37 以上, 越新越好

## 模块购买

手机访问: mall.m.openluat.com

