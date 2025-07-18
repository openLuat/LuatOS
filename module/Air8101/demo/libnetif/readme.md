
## 演示功能概述
1、设置网络优先级功能，根据优先级自动切换可用网络

2、验证网络是否正常切换，http功能是否可用

3、设置多网融合模式，例如以太网作为数据出口给WIFI设备上网

## 演示硬件环境

> Air8101支持一路MAC接口，两路SPI接口，均支持外挂以太网模块。

### MAC接口接线方式

![](https://docs.openluat.com/air8101/product/file/AirPHY_1000/hw_connection.jpg)

![](https://docs.openluat.com/air8101/product/file/AirPHY_1000/hw_connection1.jpg)

1、Air8101核心板

2、AirPHY_1000配件板

3、公对母的杜邦线11根（连接核心板和配件板）

4、网线1根（一端接配件板，一端接路由器）

5、Air8101核心板和AirPHY_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

| Air8101核心板 | AirPHY_1000配件板  |
| ------------ | ------------------ |
|    59/3V3    |         3.3v       |
|     gnd      |         gnd        |
|     5/D2     |         RX1        |
|    72/D1     |         RX0        |
|    71/D3     |         CRS        |
|     4/D0     |         MDIO       |
|     6/D4     |         TX0        |
|    74/PCK    |         MDC        |
|    70/D5     |         TX1        |
|     7/D6     |         TXEN       |
|     不接     |          NC        |
|    69/D7     |         CLK        |

### SPI接口接线方式

![](https://docs.openluat.com/air8101/product/file/AirETH_1000/hw_connection.jpg)

![](https://docs.openluat.com/air8101/product/file/AirETH_1000/hw_connection1.jpg)

1、Air8101核心板

2、AirETH_1000配件板

3、母对母的杜邦线7根（连接核心板和配件板）

4、网线1根（一端接配件板，一端接路由器）

5、Air8101核心板和AirETH_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

| Air8101核心板 | AirETH_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 28/DCLK       | SCK               |
| 54/DISP       | CSS               |
| 55/HSYN       | SDO               |
| 57/DE         | SDI               |
| 14/GPIO8      | INT               |

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1005版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1005固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、成功连接wifi，http请求功能正常

3、测试网络切换功能:

- 插入网线
- 关闭wifi
- 打开wifi并拔掉网线
- 网络可以正常切换，http请求均正常

4、测试多网融合功能时，连接好网线，其他设备连接模块的wifi热点。测试网络是否正常