## 演示模块概述

1、main.lua：主程序入口；

2、fix_pulse_output.lua：高精度固定间隔脉冲输出功能模块；

3、var_pulse_output.lua：高精度可变间隔脉冲输出功能模块；

4、dht11_capture.lua：DHT11温湿度传感器数据读取功能模块；


## 演示功能概述

使用Air8000核心板测试ioqueue功能。

IO队列功能测试，包括：

   DHT11温湿度传感器数据读取

   高精度固定间隔脉冲输出
      输出脉冲信息：
      输出固定间隔对称方波
      - 低电平持续时间：20微秒（固定）
      - 高电平持续时间：20微秒（固定）
      - 脉冲周期：40微秒（完整周期）
      - 占空比50%
      - 脉冲数量：41个完整周期（通过循环40次生成）
      - 使用ioqueue.setdelay的连续模式，所有延时间隔自动保持20us


   高精度可变间隔脉冲输出
      输出脉冲信息：
      输出可变间隔非对称脉冲
      - 10次完整序列
      - 输出波形：低电平20us → 高电平30us → 低电平40us → 高电平50us→ 低电平60us → 高电平70us
      - 使用ioqueue.setdelay 单次模式，每个延时独立配置

## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/common/hwenv/image/Air8000_core_board1.jpg)

![](https://docs.openLuat.com/cdn/image/780epm_ioqueue2.PNG) 

1、Air8000核心板一块

2、TYPE-C USB数据线一根

- Air8000核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

3、DHT11温湿度传感器一个

接线说明：air8000的GPIO25引脚连接dht11的DATA引脚，VDD_EXT引脚连接dht11的VCC引脚，GND引脚连接dht11的GND引脚。

dht11传感器硬件连接如下：
<table>
<tr>
<td>DHT11<br/></td><td>Air8000<br/></td></tr>
<tr>
<td>VCC<br/></td><td>VDD_EXT<br/></td></tr>
<tr>
<td>DATA<br/></td><td>GPIO25<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
</table>

## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2016版本固件](https://docs.openluat.com/air8000/luatos/firmware/)

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、可以接逻辑分析仪看对应io的波形，下面具体分析下：

   1）固定间隔脉冲输出：

   ![](https://docs.openluat.com/osapi/core/image/ASpubdhLGoBFBJxMaMmcXPbOnPh.png)

   2）可变间隔脉冲输出：

   ![](https://docs.openluat.com/osapi/core/image/FvGjbOkJcozClex7xlzcEs9On6b.png)

   3）DHT11温湿度传感器数据读取：

   起始信号：

   ![](https://docs.openluat.com/osapi/core/image/WYT0b7wuLowfJzxxtEXco9l8nxF.png)

   dht11响应信号：

   ![](https://docs.openluat.com/osapi/core/image/ZxnLb73XNo8I3nxaAt4cq5p8nre.png)

   dht11数据信号及分析：

   ![](https://docs.openluat.com/osapi/core/image/BSNUb4lL5oM7tDxAEZHc9hLbnLe.png)

   结束信号：

   ![](https://docs.openluat.com/osapi/core/image/LDCfblEFdot9Ywx7AFoc9jkEnBb.png)


