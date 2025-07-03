
## 演示功能概述

使用Air780EHM核心板通过SFUD库实现对SPI Flash的高效操作，并可以挂载sfud lfs文件系统，通过文件系统相关接口去操作sfud lfs文件系统中的文件，并演示文件的读写、删除、追加等操作。

## 演示硬件环境

1、Air780EHM核心板一块

2、TYPE-C USB数据线一根

3、spi flash模块一个

4、Air780EHM核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air780EHM核心板和spi flash模块接线方式

|   Air780EHM     |       SPI_FLASH       |
| --------------- | --------------------- |
|  GND(任意)      |          GND          |
|  VDD_EXT        |          VCC          |
|  GPIO8/SPI0_CS  |        CS,片选        |
|  SPI0_SLK       |        CLK,时钟       |
|  SPI0_MOSI      |  DI,主机输出,从机输入  |
|  SPI0_MISO      |  DO,主机输入,从机输出  |



## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2008版本固件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM/core)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2008固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

(1) 直接操作sfud接口去读写Flash,结果如下：

```lua
[2025-07-03 19:00:18.305][000000001.391] I/user.sfud	spi_flash	SPI*: 0C7F6E58
[2025-07-03 19:00:18.325][000000001.392] I/sfud Found a Winbond flash chip. Size is 4194304 bytes.
[2025-07-03 19:00:18.351][000000001.411] I/sfud LuatOS-sfud flash device initialized successfully.
[2025-07-03 19:00:18.421][000000001.412] I/user.sfud.init ok
[2025-07-03 19:00:18.480][000000001.412] I/user.sfud.getDeviceNum	1
[2025-07-03 19:00:18.536][000000001.412] I/user.sfud.getInfo	4194304	4096
[2025-07-03 19:00:18.590][000000001.443] I/user.sfud.eraseWrite	0
[2025-07-03 19:00:18.637][000000001.444] I/user.sfud 写入与读取数据成功

```

(2) 将Flash设备成功挂载为sfud lfs文件系统后，通过标准化文件管理接口对文件系统进行了全流程验证，结果如下：

```lua
[2025-07-01 21:03:53.218][000000001.280] I/user.sfud.init ok
[2025-07-01 21:03:53.239][000000001.281] I/user.sfud.getDeviceNum	1
[2025-07-01 21:03:53.262][000000001.281] I/user.sfud.getInfo	4194304	4096
[2025-07-01 21:03:53.280][000000001.289] D/sfud lfs_mount 0
[2025-07-01 21:03:53.302][000000001.289] D/sfud vfs mount /sfud ret 0
[2025-07-01 21:03:53.317][000000001.290] I/user.sfud.mount	true
[2025-07-01 21:03:53.331][000000001.290] I/user.sfud	挂载成功
[2025-07-01 21:03:53.340][000000001.298] I/user.fsstat	true	1024	2	4096	lfs
[2025-07-01 21:03:53.352][000000001.303] I/user./sfud/test文件写入数据	Sun   0 08:00:01
[2025-07-01 21:03:53.365][000000001.313] I/user.sfud_lfs read	Sun   0 08:00:01
[2025-07-01 21:03:53.374][000000001.314] I/user.写入测试成功，写入字符串与读出字符串一样
[2025-07-01 21:03:53.383][000000001.347] I/user./sfud/test2	LuatOS-Sun   0 08:00:01
[2025-07-01 21:03:53.395][000000001.361] I/user.sfud read	LuatOS-Sun   0 08:00:01
[2025-07-01 21:03:53.416][000000001.362] I/user.追加测试成功，写入字符串与读出字符串一样

```