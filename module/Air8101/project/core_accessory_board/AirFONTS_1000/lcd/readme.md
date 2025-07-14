
## 演示功能概述

AirFONTS_1000是合宙设计生产的一款矢量字体的配件板；

支持GBK中文和ASCII码字符集

支持16到192号的黑体字体

16号到31号，支持4bit灰度显示

32号到64号，支持2bit灰度显示

65号到192号，不支持灰度显示

本demo演示的核心功能为：

Air8101核心板+AirFONTS_1000配件板+AirLCD_1020配件板，演示多种字号和灰度的显示效果；


## 核心板+配件板资料

[Air8101核心板+配件板相关资料](https://docs.openluat.com/air8101/product/shouce/#air8101_1)


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirFONTS_1000/hw_connection.jpg)

1、Air8101核心板

2、AirFONTS_1000配件板+6根5cm长的母对母的杜邦线（一定要使用配套的杜邦线，如果杜邦线太长，SPI数据传输不稳定，可能会出现显示花屏的问题）

3、AirLCD_1020配件板+40pin双头线

4、Air8101核心板和AirFONTS_1000配件板、AirLCD_1020配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

- 为了演示方便，所以Air8101核心板上电后直接通过vbat引脚给AirFONTS_1000配件板提供了3.3V的供电；

- 客户在设计实际项目时，一般来说，需要通过一个GPIO来控制LDO给FONTS芯片供电，这样可以灵活地控制供电，可以使项目的整体功耗降到最低；

- Air8101核心板 和 AirFONTS_1000配件板之间一定要使用配套的5cm长的杜邦线相连，杜邦线太长的话，会出现spi通信不稳定的现象；


| Air8101核心板 | AirFONTS_1000配件板|
| ------------ | ------------------ |
|     vbat     |         3.3V       |
|     gnd      |         GND        |
|   67/GPIO4   |         MOSI       |
|   8/GPIO5    |         MISO       |
|   66/GPIO3   |          CS        |
|   65/GPIO2   |         CLK        |


- 为了演示方便，所以Air8101核心板上电后直接通过vbat引脚给AirLCD_1020配件板提供了3.3V的供电；

- 客户在设计实际项目时，一般来说，需要通过一个GPIO来控制LDO给LCD和TP供电，这样可以灵活地控制供电，可以使项目的整体功耗降到最低；

- 核心板和配件板之间配备了双排40PIN的双头线，可以参考下表很方便地连接双方各自的40个管脚，插入或者拔出双头线时，要慢慢的操作，防止将排针折弯；

| Air8101核心板 | AirLCD_1020配件板 |
| ------------ | ------------------ |
|     gnd      |         GND        |
|     vbat     |         VCC        |
|    42/R0     |        RGB_R0      |
|    40/R1     |        RGB_R1      |
|    43/R2     |        RGB_R2      |
|    39/R3     |        RGB_R3      |
|    44/R4     |        RGB_R4      |
|    38/R5     |        RGB_R5      |
|    45/R6     |        RGB_R6      |
|    37/R7     |        RGB_R7      |
|    46/G0     |        RGB_G0      |
|    36/G1     |        RGB_G1      |
|    47/G2     |        RGB_G2      |
|    35/G3     |        RGB_G3      |
|    48/G4     |        RGB_G4      |
|    34/G5     |        RGB_G5      |
|    49/G6     |        RGB_G6      |
|    33/G7     |        RGB_G7      |
|    50/B0     |        RGB_B0      |
|    32/B1     |        RGB_B1      |
|    51/B2     |        RGB_B2      |
|    31/B3     |        RGB_B3      |
|    52/B4     |        RGB_B4      |
|    30/B5     |        RGB_B5      |
|    53/B6     |        RGB_B6      |
|    29/B7     |        RGB_B7      |
|   28/DCLK    |       RGB_DCLK     |
|   54/DISP    |       RGB_DISP     |
|   55/HSYN    |       RGB_HSYNC    |
|   56/VSYN    |       RGB_VSYNC    |
|    57/DE     |        RGB_DE      |
|   14/GPIO8   |        LCD_BL      |
|   13/GPIO9   |        LCD_RST     |
|    8/GPIO5   |        LCD_SDI     |
|    9/GPIO6   |        LCD_SCL     |
|  68/GPIO12   |        LCD_CS      |
|  75/GPIO28   |        TP_RST      |
|   10/GPIO7   |        TP_INT      |
|   12/U1TX    |        TP_SCL      |
|   11/U1RX    |        TP_SDA      |


## 演示软件环境

1、Luatools下载调试工具

2、[目前还没有正式固件，只有临时内测固件，联系合宙销售同事获取](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) ；
   

