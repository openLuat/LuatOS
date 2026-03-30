## 功能模块介绍

1、main.lua：主程序入口；

2、lora2_main.lua：lora主应用功能模块；

3、lora2_sender.lua：lora数据发送应用功能模块；

4、lora2_receiver.lua：lora数据接收应用功能模块；

5、uart_app.lua：UART应用功能模块；


## 演示功能概述

使用Air780EPM核心板+lora模块测试lora的数据发送和接收功能。

需要两套Air780EPM核心板+lora模块，才能进行有效的通信测试。

## 演示硬件环境

1、Air780EPM 核心板两块 + 同型号lora模块两块（芯片选择llcc68/sx1268）；

![image](https://docs.openluat.com/air780epm/luatos/app/driver/lora/image/255MN.png)

演示使用的 LoRa 模块是 <font color="orange">南京二五五物联科技</font> 的 <font color="orange">255MN-L03</font> 模块，是一款基于射频芯片LLCC68设计的无线收发模组。该模组具有+22dBm的可调输出功率，最低4.2mA的接收电流，传输距离远，可靠性高，功耗低。模块提供了SPI通用接口，采用半双工通信方式。

二五五物联官网：[https://255mesh.com/](https://255mesh.com/)

资料下载：[255MN-L03 模块资料](https://255mesh.com/chanpinzhongxin/255MNmozuxilie/119.html)

淘宝购买链接：[https://item.taobao.com/item.htm?abbucket=9&id=905046008431&mi_id=0000sz-y6pYMNtwApPC3D3afiJFxiZmXkCwCdhnQSR3qV8w&ns=1&priceTId=213e09fa17659699305601049e125b&skuId=5765457041940&spm=a21n57.1.hoverItem.2&utparam=%7B%22aplus_abtest%22%3A%22536abb31a9b47a2a9d837ffff3617cf5%22%7D&xxc=taobaoSearch](https://item.taobao.com/item.htm?abbucket=9&id=905046008431&mi_id=0000sz-y6pYMNtwApPC3D3afiJFxiZmXkCwCdhnQSR3qV8w&ns=1&priceTId=213e09fa17659699305601049e125b&skuId=5765457041940&spm=a21n57.1.hoverItem.2&utparam=%7B%22aplus_abtest%22%3A%22536abb31a9b47a2a9d837ffff3617cf5%22%7D&xxc=taobaoSearch)


2、TYPE-C USB数据线一根，Air780EPM核心板和数据线的硬件接线方式为：

- Air780EPM核心板通过TYPE-C USB口供电，核心板正面的 ON/OFF 拨动开关 拨到ON一端；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的UART1_TX，绿线连接核心板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口；

3、Air780EPM 核心板通过SPI接口与lora模块连接并进行通信，具体接线如下：

![image](https://docs.openluat.com/air780epm/luatos/app/driver/lora/image/179c82696fa29c9ac6095fa75b7cd3f1.jpg)

| Air780EPM核心板  |  lora模块          |
| --------------- | ----------------- |
| 3V3             | VCC               |
| GND             | GND               |
| 86/SPI0CLK      | SCK               |
| 85/SPI0MOSI     | MOSI              |
| 84/SPI0MISO     | MISO              |
| 83/SPI0CS       | CSS               |
| 22/GPIO1        | RST               |
| 97/GPIO16       | BUSY              |
| 100/GPIO17       | DIO1              |

硬件连接注意事项：

1. 电源要求：
   - 不同lora模块的供电电压范围可能存在差异，请根据具体模块规格确定合适的电源电压

2. 控制信号连接：
   - RST引脚：连接至核心板的GPIO1，用于lora模块复位控制
  
   - BUSY引脚：连接至核心板的GPIO16，用于lora模块忙状态指示
  
   - DIO1引脚：连接至核心板的GPIO17，用于lora模块中断信号接收
  

3. 连接确认：
   - 上述GPIO引脚分配已在测试中验证可用
  
   - 如有变更需求，需同步修改软件配置中的引脚定义

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM 固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

5、如下是Air780EPM核心板搭配lora模块发送和接收数据的演示结果：（Air780EPM核心板+lora模块，下面统称为lora设备）

（1）上电后，lora设备A和B会进入lora接收状态，等待接收数据; 若接收超时，会继续等待接收, 所以在没有数据传输时，luatools会一直打印接收超时信息。

```lua
I/user.lora2_main 接收超时
```

（2）设备A发送数据，设备B接收数据：
  
   - 发送端通过UART1发送字符串"Hello, I am LoRa device A!"

   - 接收端通过UART1成功接收到数据"Hello, I am LoRa device A!"
  
（2）设备B发送数据，设备A接收数据：
  
   - 发送端通过UART1发送字符串"Hello, I am LoRa device B!"

   - 接收端通过UART1成功接收到数据"Hello, I am LoRa device B!"

![image](https://docs.openLuat.com/cdn/image/lora_uart_test.png)

```
