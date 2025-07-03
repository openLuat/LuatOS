
## 演示功能概述

使用Air780EHM核心板通过fatfs库实现对SPI SD的高效操作，并可以挂载fatfs文件系统，通过文件系统相关接口去操作fatfs文件系统中的文件，并演示文件的读写、删除、追加以及HTTP服务器下载到SD卡等操作。

## 演示硬件环境

1、Air780EHM核心板一块

2、TYPE-C USB数据线一根

3、spi SD卡模块一个和SD卡一张

4、Air780EHM核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air780EHM核心板和spi SD卡模块接线方式

|   Air780EHM     |       SPI_SD卡模块    |
| --------------- | --------------------- |
|  GND(任意)      |          GND          |
|  VDD_EXT        |          VCC          |
|  GPIO8/SPI0_CS  |        CS,片选        |
|  SPI0_SLK       |        CLK,时钟       |
|  SPI0_MOSI      |  MOSI,主机输出,从机输入|
|  SPI0_MISO      |  MISO,主机输入,从机输出|



## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2008版本固件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM/core)

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

(1) 用SD卡接口fatfs挂载SD卡成文件系统，然后用文件系统接口操作：

```lua
[2025-07-03 12:58:38.413][000000001.547] D/SPI_TF 卡容量 62367744KB
[2025-07-03 12:58:38.414][000000001.547] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2025-07-03 12:58:38.515][000000001.654] I/user.fatfs	getfree	{"free_sectors":124665856,"total_kb":62334976,"free_kb":62332928,"total_sectors":124669952}
[2025-07-03 12:58:38.517][000000001.657] I/user.fs	data	6	36	2
[2025-07-03 12:58:38.519][000000001.657] I/user.fs	boot count	6
[2025-07-03 12:58:38.524][000000001.665] I/user.fs	write c to file	7	7
[2025-07-03 12:58:38.548][000000001.680] I/user.fsstat	true	128	4	4096	lfs
[2025-07-03 12:58:38.550][000000001.680] I/user.fsstat	true	124669952	4096	512	fatfs
[2025-07-03 12:58:38.609][000000001.757] I/user.data	ABCdef	true
[2025-07-03 12:58:38.700][000000001.826] D/mobile cid1, state0
[2025-07-03 12:58:38.702][000000001.827] D/mobile bearer act 0, result 0
[2025-07-03 12:58:38.703][000000001.827] D/mobile NETIF_LINK_ON -> IP_READY
[2025-07-03 12:58:38.733][000000001.872] I/user.sdio	line1	abc
[2025-07-03 12:58:38.734][000000001.873] I/user.sdio	line2	123
[2025-07-03 12:58:38.736][000000001.873] I/user.sdio	line3	wendal

```

(2) 使用HTTP去下载文件到SD卡，然后读取下文件的大小：

```lua
[2025-07-03 12:58:38.738][000000001.874] dns_run 674:airtest.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-07-03 12:58:38.764][000000001.907] D/mobile TIME_SYNC 0
[2025-07-03 12:58:38.794][000000001.917] dns_run 691:dns all done ,now stop
[2025-07-03 12:58:44.719][000000007.856] I/user.下载完成	200	table: 0C7F62D8	411922
[2025-07-03 12:58:44.728][000000007.859] I/user.io.fileSize	411922
```