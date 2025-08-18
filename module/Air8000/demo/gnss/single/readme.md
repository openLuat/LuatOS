
## 演示功能概述

使用Air8000整机开发板，本示例主要是展示exgnss库的三种应用模式，

exgnss.DEFAULT模式

exgnss.TIMERORSUC模式

exgnss.TIMER模式

主要操作为：

打开三种应用模式

等待40秒关闭操作TIMER模式

然后查询三种应用模式是否处于激活模式

等待10秒关闭全部应用模式，再次查询三种模式是否处于激活模式

然后获取最后一次的定位经纬度数据打印

定位成功之后使用exgnss库获取gnss的rmc数据

## 演示硬件环境

1、Air8000整机开发板一块

2、TYPE-C USB数据线一根

3、gnss天线一根

4、Air8000整机开发板和数据线的硬件接线方式为

- Air8000整机开发板通过TYPE-C USB口供电；（整机开发板的拨钮开关拨到USB供电）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2010版本固件](https://docs.openluat.com/air8000/luatos/firmware/)

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

(1) 开启GNSS应用：

```lua
[2025-08-13 17:30:59.548][000000000.449] I/user.全卫星开启
[2025-08-13 17:30:59.587][000000000.449] I/user.debug开启
[2025-08-13 17:30:59.633][000000000.449] D/gnss Debug ON
[2025-08-13 17:30:59.697][000000000.449] I/user.agps开启
[2025-08-13 17:30:59.779][000000000.450] W/user.gnss_agps wait IP_READY
[2025-08-13 17:30:59.810][000000000.451] I/user.exgnss._open
[2025-08-13 17:30:59.834][000000000.452] I/user.exgnss.open 1 modeDefault nil function: 0C7F7A20
[2025-08-13 17:30:59.873][000000000.453] I/user.exgnss.open 2 modeTimerorsuc 60 function: 0C7FAFF0
[2025-08-13 17:30:59.918][000000000.456] I/user.exgnss state OPEN

```

(2) GNSS定位成功：

```lua
[2025-08-13 17:31:05.314][000000008.890] I/gnss Fixed 344786478 1141919416
[2025-08-13 17:31:05.331][000000008.892] I/user.exgnss state FIXED
[2025-08-13 17:31:05.348][000000008.894] I/user.nmea rmc0 {"variation":0,"lat":3447.86475,"min":31,"valid":true,"day":13,"lng":11419.19336,"speed":0.01300,"year":2025,"month":8,"sec":4,"hour":9,"course":340.04800}
[2025-08-13 17:31:05.361][000000008.894] I/user.exgnss.statInd@1 true 3 modeTimer 60 52 nil function: 0C7FB4B8
[2025-08-13 17:31:05.369][000000008.895] I/user.exgnss.statInd@2 true 1 modeDefault nil nil nil function: 0C7F7A20
[2025-08-13 17:31:05.387][000000008.896] I/user.exgnss.statInd@3 true 2 modeTimerorsuc 60 52 nil function: 0C7FAFF0
[2025-08-13 17:31:05.401][000000008.896] I/user.exgnss.statInd@4 true 3 libagps 20 17 nil nil
[2025-08-13 17:31:06.311][000000009.895] I/user.exgnss.timerFnc@1 3 modeTimer 60 52 nil
[2025-08-13 17:31:06.324][000000009.896] I/user.exgnss.timerFnc@2 1 modeDefault nil nil 1
[2025-08-13 17:31:06.329][000000009.896] I/user.TAGmode2_cb+++++++++ modeDefault
[2025-08-13 17:31:06.335][000000009.897] I/user.nmea rmc {"variation":0,"lat":34.7977448,"min":31,"valid":true,"day":13,"lng":114.3199005,"speed":0.0130000,"year":2025,"month":8,"sec":4,"hour":9,"course":340.0480042}
[2025-08-13 17:31:06.337][000000009.898] I/user.exgnss.timerFnc@3 2 modeTimerorsuc 60 52 1
[2025-08-13 17:31:06.340][000000009.898] I/user.TAGmode3_cb+++++++++ modeTimerorsuc
[2025-08-13 17:31:06.342][000000009.899] I/user.nmea rmc {"variation":0,"lat":34.7977448,"min":31,"valid":true,"day":13,"lng":114.3199005,"speed":0.0130000,"year":2025,"month":8,"sec":4,"hour":9,"course":340.0480042}
[2025-08-13 17:31:06.344][000000009.900] I/user.exgnss.close 2 modeTimerorsuc 60 function: 0C7FAFF0
[2025-08-13 17:31:06.349][000000009.900] I/user.exgnss.timerFnc@4 3 libagps 20 17 nil

```
3、到时间关闭所有应用：
```lua
[2025-08-13 17:31:46.861][000000050.455] I/user.exgnss.close 3 modeTimer 60 function: 0C7FB4B8
[2025-08-13 17:31:46.876][000000050.455] I/user.TAGmode2_cb+++++++++ modeDefault
[2025-08-13 17:31:46.892][000000050.456] I/user.nmea rmc {"variation":0,"lat":34.7977867,"min":31,"valid":true,"day":13,"lng":114.3198853,"speed":0,"year":2025,"month":8,"sec":46,"hour":9,"course":0}
[2025-08-13 17:31:46.911][000000050.456] I/user.exgnss.close 1 modeDefault nil function: 0C7F7A20
[2025-08-13 17:31:46.936][000000050.463] I/user.exgnss._close
[2025-08-13 17:31:46.950][000000050.464] I/user.exgnss.close 2 modeTimerorsuc 60 function: 0C7FAFF0
[2025-08-13 17:31:46.965][000000050.465] I/user.exgnss.close 3 libagps 20 nil
[2025-08-13 17:31:46.982][000000050.465] I/user.gnss应用状态1
[2025-08-13 17:31:46.997][000000050.465] I/user.gnss应用状态2
[2025-08-13 17:31:47.013][000000050.466] I/user.gnss应用状态3
[2025-08-13 17:31:47.027][000000050.469] I/user.lastloc 3447.8671900000 11419.193360000
[2025-08-13 17:31:47.042][000000050.470] I/user.exgnss state CLOSE
```