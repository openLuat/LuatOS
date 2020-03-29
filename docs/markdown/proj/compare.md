# 主要竞品分析

|名称|硬件|lua版本|底层rtos|
|----|----|------|--------|
|NodeMCU|ESP32|5.1|自研|
|Lua-RTOS-ESP32|ESP32|5.3|freertos|
|eLua|多款|5.1|自研|
|Luat|air202/air720|5.1|厂商rtos|
|MicroPython|多款|py语言|自研|

## NodeMCU

官网: https://nodemcu.readthedocs.io/

```
NodeMCU is an open source Lua based firmware for the ESP8266 WiFi SOC from Espressif and uses an on-module flash-based SPIFFS file system.
```

专为esp8266/esp32设计,移植性不佳,但知名度非常高.

## eLua

官网: http://www.eluaproject.net/

```
eLua stands for Embedded Lua and the project aims to offer the full implementation of the Lua Programming Language to the embedded world, extending it with specific features for efficient and portable software embedded development.
```

luat最初也是从eLua开始开发,但eLua本身的开发已经半停滞,背后没有商业公司在维护.

## Lua-RTOS-ESP32

官网: https://github.com/whitecatboard/Lua-RTOS-ESP32

```
Lua RTOS is a real-time operating system designed to run on embedded systems, with minimal requirements of FLASH and RAM memory.
```

从eLua发展而来,底层改成freertos, lua版本也更新到5.3,支持众多外设, 由商业公司维护开发活跃.

## MicroPython

官网: https://micropython.org/

```
MicroPython is a lean and efficient implementation of the Python 3 programming language that includes a small subset of the Python standard library and is optimised to run on microcontrollers and in constrained environments.
```

https://micropython.nxez.com/2019/01/15/rtt-micropython-vs-official-native-micropython.html

基于python的竞品中,`MicroPython`是最有实力的了, 移植到各种平台的实现也非常多.

## Luat

官网: http://www.openluat.com

从eLua发展而来,为Air202深度定制,最近又移植到Air720系列,沿用了eLua的底层Lua API风格,发展出LuaTask和iRTU等上层建筑.

曾经存在的win32虚拟环境, 也证明当年跨平台的一些尝试. 现在有qemu加持, 移植思路就不一样了.

## 意见

市面上的竞品, 要么专门为esp系列设计/要么lua版本低/要么没有商业公司支撑.

从API完成度说, `Lua-RTOS-ESP32`是非常不错的产品,但其源码组织方式,在源码中大量使用`#ifdef`区分不同的场景,使得其可移植性大打折扣.

`eLua`和`nodeMCU`均基于`Lua 5.1.x`,其代码具有参考价值.

`MicroPython`是需要重视的对手.
