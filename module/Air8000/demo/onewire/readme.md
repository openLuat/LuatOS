> 王棚嶙

# OneWire综合演示项目

## 功能模块介绍

本demo演示了完整的DS18B20温度传感器OneWire单总线协议实现。项目采用模块化架构，分别实现单传感器和多传感器应用场景。

1、main.lua：主程序入口 <br> 
2、onewire_single_app.lua：演示单传感器功能模块（GPIO2默认OneWire功能，硬件通道0模式，3秒间隔连续监测）<br> 
3、onewire_multi_app.lua：演示多传感器功能模块（引脚98/30切换，PWR_KEY按键控制，2秒间隔双路监测）<br> 

## 演示功能概述

###  主程序入口模块 (main.lua)

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载onewire_single_app模块（通过require "onewire_single_app"）
- 加载onewire_multi_app模块（通过require "onewire_multi_app"）

### 单传感器模式 (onewire_single_app.lua)
- 使用GPIO2默认OneWire功能，硬件通道0模式，无需引脚复用
- 完整的CRC8数据校验机制，确保数据可靠性
- 设备自动识别和ROM验证，支持设备类型检测
- 3秒间隔连续温度监测，实时温度报警功能
- zbuff缓冲区优化，提高数据传输效率


### 多传感器模式 (onewire_multi_app.lua - 单总线多设备演示)


**单总线多设备挂载原理**：
1. **物理连接**：所有DS18B20的VDD、GND、DQ引脚分别并联到同一组单总线
2. **设备识别**：每个DS18B20出厂时烧录了全球唯一的64位ROM ID
3. **总线扫描**：主机发送SEARCH ROM(0xF0)命令发现总线上的所有设备
4. **设备选择**：通过MATCH ROM(0x55)命令+目标设备ROM ID选择特定设备通信
5. **分时操作**：每次只与一个设备通信，避免总线冲突

**分时复用测试逻辑**（2秒切换一次）：
- **前2秒**：使用总线端A设备（引脚98，ROM ID: 28-9F-C4-93-00-00-00-14）
- **按PWR_KEY后2秒**：切换使用总线端B设备（引脚30，ROM ID: 28-59-F2-53-00-00-00-14）
- **循环切换**：按键一次切换一个设备，实现同一条总线的分时使用

**核心测试流程**：
1. 初始化当前引脚的OneWire总线
2. 发送SEARCH ROM命令扫描总线上的设备
3. 读取并验证设备的64位ROM ID（家族码+序列号+CRC）
4. 使用MATCH ROM(0x55)命令选择目标设备
5. 发送温度转换命令(0x44)并等待完成
6. 读取温度数据并进行CRC校验
7. 输出设备ROM ID、温度值、读取成功率



## 演示硬件环境
1、Air8000A核心板一块

2、TYPE-C USB数据线一根

3、ds18b20传感器两个

4、Air8000A核心板和数据线的硬件接线方式为

- Air8000A核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air8000A核心板和ds18b20传感器接线方式

### 单传感器连接

|   Air8000A核心板     |    DS18B20传感器    |
| --------------- | -------------------|
|    VDD_EXT         |         VCC        |
|    GPIO2     |         DQ         |
|    GND          |         GND        |

连接图：

![image](https://docs.openluat.com/air8000/luatos/app/driver/onewire/image/b1e471848d3181dcd822dc93c62d660d.jpg)



### 多传感器连接


|   Air8000A核心板     |    DS18B20传感器1    |
| --------------- | -------------------|
|    VDD_EXT         |         VCC        |
|    GPIO2     |         DQ         |
|    任意GND          |         GND        |

|   Air8000A核心板     |    DS18B20传感器2    |
| --------------- | -------------------|
|    GPIO20         |         VCC        |
|    GPIO3     |         DQ         |
|    任意GND          |         GND        |

连接图:

![image](https://docs.openluat.com/air8000/luatos/app/driver/onewire/image/8a1b2ebfc3749f8d5e84e40a78a31aa4.jpg)

## 演示软件环境

1、Luatools下载调试工具：https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：https://docs.openluat.com/air8000/luatos/firmware/

## 演示核心步骤
1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板或开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```lua
（1）单传感器演示
[2025-11-25 15:14:59.660][000000000.387] I/user.onewire_single_app 单传感器模块版本:1.0.0
[2025-11-25 15:14:59.683][000000000.387] I/user.onewire_single_app 单传感器应用模块加载完成
[2025-11-25 15:14:59.705][000000000.387] I/user.onewire_single_app 启动单传感器应用
[2025-11-25 15:14:59.721][000000000.388] I/user.onewire_single_app 初始化OneWire总线...
[2025-11-25 15:14:59.737][000000000.388] I/user.onewire_single_app OneWire总线初始化完成，使用GPIO2默认引脚
[2025-11-25 15:14:59.755][000000000.388] I/user.onewire_single_app 检测DS18B20设备...
[2025-11-25 15:14:59.769][000000000.395] I/user.onewire_single_app 探测到DS18B20 2859F253000000 14
[2025-11-25 15:14:59.793][000000000.396] I/user.onewire_single_app 开始连续温度监测...
[2025-11-25 15:14:59.817][000000000.405] I/user.onewire_single_app 温度转换完成
[2025-11-25 15:14:59.842][000000000.418] I/user.onewire_single_app 温度读取成功: 26.12°C
[2025-11-25 15:14:59.858][000000000.419] I/user.onewire_single_app 温度正常: 26.12°C
[2025-11-25 15:15:00.727][000000003.428] I/user.onewire_single_app 温度转换完成
[2025-11-25 15:15:00.751][000000003.441] I/user.onewire_single_app 温度读取成功: 26.12°C
[2025-11-25 15:15:00.766][000000003.442] I/user.onewire_single_app 温度正常: 26.12°C
[2025-11-25 15:15:03.755][000000006.451] I/user.onewire_single_app 温度转换完成
[2025-11-25 15:15:03.771][000000006.464] I/user.onewire_single_app 温度读取成功: 26.12°C
[2025-11-25 15:15:03.788][000000006.465] I/user.onewire_single_app 温度正常: 26.12°C
[2025-11-25 15:15:06.775][000000009.474] I/user.onewire_single_app 温度转换完成
[2025-11-25 15:15:06.794][000000009.487] I/user.onewire_single_app 温度读取成功: 26.12°C
[2025-11-25 15:15:06.817][000000009.488] I/user.onewire_single_app 温度正常: 26.12°C
[2025-11-25 15:15:09.800][000000012.497] I/user.onewire_single_app 温度转换完成
[2025-11-25 15:15:09.812][000000012.510] I/user.onewire_single_app 温度读取成功: 26.12°C
[2025-11-25 15:15:09.832][000000012.511] I/user.onewire_single_app 温度正常: 26.12°C
[2025-11-25 15:15:12.830][000000015.520] I/user.onewire_single_app 温度转换完成
[2025-11-25 15:15:12.842][000000015.533] I/user.onewire_single_app 温度读取成功: 26.12°C
[2025-11-25 15:15:12.856][000000015.534] I/user.onewire_single_app 温度正常: 26.12°C

（2）单总线分时复用演示
[2025-11-25 15:10:27.765][000000000.393] I/user.onewire_multi_app 多传感器模块版本: 1.0.0
[2025-11-25 15:10:27.826][000000000.394] I/user.onewire_multi_app 双传感器应用模块加载完成（30和98切换）
[2025-11-25 15:10:27.910][000000000.394] I/user.onewire_multi_app 启动双传感器应用（引脚30和98）
[2025-11-25 15:10:27.968][000000000.394] I/user.onewire_multi_app 初始化硬件配置...
[2025-11-25 15:10:28.023][000000000.395] I/user.onewire_multi_app 硬件初始化完成
[2025-11-25 15:10:28.067][000000000.395] I/user.onewire_multi_app 初始引脚: 引脚98 (ONEWIRE功能)
[2025-11-25 15:10:28.115][000000000.396] I/user.onewire_multi_app 切换按键: PWR_KEY
[2025-11-25 15:10:28.174][000000000.396] I/user.onewire_multi_app 支持引脚: 98 和 30 循环切换
[2025-11-25 15:10:28.235][000000000.396] I/user.onewire_multi_app 电源控制: GPIO31/GPIO2 (已设置为高电平)
[2025-11-25 15:10:28.284][000000000.396] I/user.onewire_multi_app 电源控制: 开启
[2025-11-25 15:10:28.312][000000000.497] I/user.onewire_multi_app 初始化OneWire总线，通道: 0
[2025-11-25 15:10:28.350][000000000.508] I/user.onewire_multi_app OneWire总线初始化完成，通道: 0，引脚:98
[2025-11-25 15:10:28.468][000000000.709] I/user.onewire_multi_app 检测DS18B20设备，引脚: 98
[2025-11-25 15:10:28.502][000000000.710] I/user.onewire_multi_app 检测到DS18B20设备响应
[2025-11-25 15:10:28.531][000000000.710] I/user.onewire_multi_app 开始双传感器连续监测...
[2025-11-25 15:10:28.561][000000000.710] I/user.onewire_multi_app 按PWR_KEY按键可切换引脚(30和98)
[2025-11-25 15:10:28.592][000000000.711] I/user.onewire_multi_app 第1次读取，引脚:98
[2025-11-25 15:10:28.625][000000000.711] I/user.onewire_multi_app 开始读取DS18B20温度，引脚: 98
[2025-11-25 15:10:28.653][000000000.711] I/user.onewire_multi_app 读取设备ROM ID
[2025-11-25 15:10:28.685][000000000.718] I/user.onewire_multi_app ROM ID校验成功: 289FC493000000 14
[2025-11-25 15:10:28.719][000000000.719] I/user.onewire_multi_app 开始温度转换
[2025-11-25 15:10:28.747][000000000.726] I/user.onewire_multi_app 等待温度转换完成
[2025-11-25 15:10:28.777][000000001.478] I/user.onewire_multi_app 温度转换完成
[2025-11-25 15:10:28.800][000000001.478] I/user.onewire_multi_app 读取温度数据
[2025-11-25 15:10:28.828][000000001.491] I/user.onewire_multi_app CRC校验和温度计算
[2025-11-25 15:10:28.860][000000001.492] I/user.onewire_multi_app 温度读取成功: 25.75°C
[2025-11-25 15:10:28.890][000000001.492] I/user.onewire_multi_app 引脚98温度: 25.75°C 成功率: 100.0%
[2025-11-25 15:10:29.029][000000003.493] I/user.onewire_multi_app 第2次读取，引脚:98
[2025-11-25 15:10:29.063][000000003.493] I/user.onewire_multi_app 开始读取DS18B20温度，引脚: 98
[2025-11-25 15:10:29.094][000000003.493] I/user.onewire_multi_app 读取设备ROM ID
[2025-11-25 15:10:29.124][000000003.500] I/user.onewire_multi_app ROM ID校验成功: 289FC493000000 14
[2025-11-25 15:10:29.158][000000003.501] I/user.onewire_multi_app 开始温度转换
[2025-11-25 15:10:29.192][000000003.508] I/user.onewire_multi_app 等待温度转换完成
[2025-11-25 15:10:29.220][000000004.260] I/user.onewire_multi_app 温度转换完成
[2025-11-25 15:10:29.251][000000004.260] I/user.onewire_multi_app 读取温度数据
[2025-11-25 15:10:29.281][000000004.273] I/user.onewire_multi_app CRC校验和温度计算
[2025-11-25 15:10:29.308][000000004.274] I/user.onewire_multi_app 温度读取成功: 25.81°C
[2025-11-25 15:10:29.342][000000004.274] I/user.onewire_multi_app 引脚98温度: 25.81°C 成功率: 100.0%


（3）单总线分时复用按键切换演示
[2025-11-25 15:10:34.504][000000010.718] I/user.onewire_multi_app 切换按键被按下
[2025-11-25 15:10:35.624][000000011.838] I/user.onewire_multi_app 切换OneWire引脚...
[2025-11-25 15:10:35.647][000000011.859] I/user.onewire_multi_app 将PIN984配置为GPIO3 true
[2025-11-25 15:10:35.677][000000011.859] I/user.onewire_multi_app 将GPIO3设置为高电平输出 function: 0C7F4648
[2025-11-25 15:10:35.698][000000011.859] I/user.onewire_multi_app 切换到引脚30
[2025-11-25 15:10:35.721][000000011.860] I/user.onewire_multi_app 当前使用引脚: 30
[2025-11-25 15:10:35.745][000000011.860] I/user.onewire_multi_app 将引脚30配置为ONEWIRE功能 true
[2025-11-25 15:10:35.769][000000011.880] I/user.onewire_multi_app 引脚切换完成，当前使用: 引脚30
[2025-11-25 15:10:36.167][000000012.380] I/user.onewire_multi_app 初始化OneWire总线，通道: 0
[2025-11-25 15:10:36.189][000000012.391] I/user.onewire_multi_app OneWire总线初始化完成，通道: 0，引脚:30
[2025-11-25 15:10:36.275][000000012.490] I/user.onewire_multi_app 第5次读取，引脚:30
[2025-11-25 15:10:36.296][000000012.491] I/user.onewire_multi_app 开始读取DS18B20温度，引脚: 30
[2025-11-25 15:10:36.315][000000012.491] I/user.onewire_multi_app 读取设备ROM ID
[2025-11-25 15:10:36.335][000000012.498] I/user.onewire_multi_app ROM ID校验成功: 2859F253000000 14
[2025-11-25 15:10:36.361][000000012.499] I/user.onewire_multi_app 开始温度转换
[2025-11-25 15:10:36.390][000000012.506] I/user.onewire_multi_app 等待温度转换完成
[2025-11-25 15:10:37.038][000000013.258] I/user.onewire_multi_app 温度转换完成
[2025-11-25 15:10:37.063][000000013.258] I/user.onewire_multi_app 读取温度数据
[2025-11-25 15:10:37.084][000000013.271] I/user.onewire_multi_app CRC校验和温度计算
[2025-11-25 15:10:37.107][000000013.272] I/user.onewire_multi_app 温度读取成功: 26.00°C
[2025-11-25 15:10:37.130][000000013.272] I/user.onewire_multi_app 引脚30温度: 26.00°C 成功率: 100.0%



```