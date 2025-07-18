
## 演示功能概述

本demo使用Air780EGH核心板，演示通过I2C协议接口来读取SHT20传感器数据，分别以硬件I2C和软件I2C的方式来做演示

## 演示硬件环境

1、Air780EHM核心板一块，TYPE-C USB数据线一根

2、SHT20模块一个，杜邦线若干

3、Air780EHM核心板和SHT20模块硬件连接

硬件I2C测试连线：

核心板                   SHT20模块
GND              <--->  GND
3.3V             <--->  3.3V
(PIN67)I2C1_SCL  <--->  SCL
(PIN66)I2C1_SDA  <--->  SDA

软件I2C测试连线：

核心板                   SHT20模块
GND              <--->  GND
3.3V             <--->  3.3V
(PIN97)GPIO16    <--->  SCL
(PIN100)GPIO17   <--->  SDA

4、Air780EGH核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EGH 最新版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，查看Luatools中打印的运行日志,具体详见相关文档 [Air780EGH I2C](https://docs.openluat.com/air780egh/luatos/app/driver/i2c/)

硬件I2C通信成功日志如下所示：

> I2C_MasterSetup 426:I2C1, Total 260 HCNT 113 LCNT 136  
> I/user.i2c   initial 1  
> I/user.SHT20 read tem data 70C8  4  
> I/user.SHT20 read hum data A73A  4  
> I/user.SHT20 temp,humi   30.56000    75.65000  

软件I2C通信成功日志如下所示：

> I/user.i2c    sw i2c initial    EI2C*: 0C7F7740
> I/user.SHT20 read tem data 70C8  4  
> I/user.SHT20 read hum data A73A  4  
> I/user.SHT20 temp,humi   30.56000    75.65000
