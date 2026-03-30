## 功能模块介绍

1、main.lua：主程序入口；

2、lora2_main.lua：lora主应用功能模块；

3、lora2_sender.lua：lora数据发送应用功能模块；

4、lora2_receiver.lua：lora数据接收应用功能模块；

5、uart_app.lua：UART应用功能模块；


## 演示功能概述

使用Air8000核心板+lora模块测试lora的数据发送和接收功能。

需要两套Air8000核心板+lora模块，才能进行有效的通信测试。

## 演示硬件环境

1、Air8000 核心板两块 + 同型号lora模块两块（芯片选择llcc68/sx1268）；

本演示中，使用的lora模块为Ai-Thinker的Ra-01SC模块，该模块基于llcc68芯片。

![image](https://docs.openLuat.com/cdn/image/Ai-Thinker_lora模块.png)

[淘宝购买链接 点击此处](https://detail.tmall.com/item.htm?ali_refid=a3_430673_1006%3A1310580056%3AN%3AbqpGoPHh6maprV%2FiOvfLQlttIGZ5%2F0H4%3A8ac800110c31e390e3a00be4332367ec&ali_trackid=1_8ac800110c31e390e3a00be4332367ec&id=642897064381&mi_id=00007gKI69Jf4rfCAQlHSi0FwOhhsjkApkWKIk0aR6x63s4&mm_sceneid=1_0_1079550197_0&priceTId=2147872c17636209574944284e0e8c&skuId=4696650265078&spm=a21n57.sem.item.2&utparam=%7B%22aplus_abtest%22%3A%2204f30be1eb4a5e73cebb07691a717fb3%22%7D&xxc=ad_ztc)


2、TYPE-C USB数据线一根，Air8000核心板和数据线的硬件接线方式为

- Air8000核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；

- 核心板正面的 供电/充电 拨动开关 拨到供电一端；

- 核心板背面的 USB ON/USB OFF 拨动开关 拨到USB ON一端；

- USB转串口数据线，一般来说，白线连接核心板的UART1_TX，绿线连接核心板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口；

3、Air8000 核心板通过SPI接口与lora模块连接并进行通信，具体接线如下：

![image](https://docs.openLuat.com/cdn/image/Air8000_lora2.jpg)

| Air8000核心板  |  lora模块          |
| --------------- | ----------------- |
| VDD_EXT         | VCC               |
| GND             | GND               |
| SPI1_CLK        | SCK               |
| SPI1_CS         | CSS               |
| SPI1_MISO       | MISO              |
| SPI1_MOSI       | MOSI              |
| GPIO1           | RST               |
| GPIO16          | BUSY              |
| GPIO17          | DIO1              |

硬件连接注意事项：

1. 电源要求：
   - 不同lora模块的供电电压范围可能存在差异，请根据具体模块规格确定合适的电源电压

2. 控制信号连接：
   - RST引脚：连接至Air8000的GPIO1，用于lora模块复位控制
  
   - BUSY引脚：连接至Air8000的GPIO16，用于lora模块忙状态指示
  
   - DIO1引脚：连接至Air8000的GPIO17，用于lora模块中断信号接收
  

3. 连接确认：
   - 上述GPIO引脚分配已在测试中验证可用
  
   - 如有变更需求，需同步修改软件配置中的引脚定义

## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2018版本固件](https://docs.openluat.com/air8000/luatos/firmware/)

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

5、如下是Air8000核心板搭配lora模块发送和接收数据的演示结果：（Air8000核心板+lora模块，下面统称为lora设备）

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
