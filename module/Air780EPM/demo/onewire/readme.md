> 王棚嶙

# OneWire综合演示项目

## 功能模块介绍

本demo演示了完整的DS18B20温度传感器OneWire单总线协议实现。项目采用模块化架构，分别实现单传感器和多传感器应用场景。

1、main.lua：主程序入口 <br> 
2、onewire_single_app.lua：演示单传感器功能模块（GPIO2默认OneWire功能，硬件通道0模式，3秒间隔连续监测）<br> 
3、onewire_multi_app.lua：演示多传感器功能模块（引脚54/23切换，PWR_KEY按键控制，2秒间隔双路监测）<br> 

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

**分时复用测试逻辑**（按键切换设备）：
- **引脚54**：连接设备A（ROM ID: 28-9F-C4-93-00-00-00-14）
- **引脚23**：连接设备B（ROM ID: 28-59-F2-53-00-00-00-14）
- **PWR_KEY按键**：按一次切换一个设备，实现同一条总线的分时使用

**核心测试流程**：
1. 初始化当前引脚的OneWire总线
2. 发送SEARCH ROM命令扫描总线上的设备
3. 读取并验证设备的64位ROM ID（家族码+序列号+CRC）
4. 使用MATCH ROM(0x55)命令选择目标设备
5. 发送温度转换命令(0x44)并等待完成
6. 读取温度数据并进行CRC校验
7. 输出设备ROM ID、温度值、读取成功率



## 演示硬件环境
1、Air780EPM核心板一块

2、TYPE-C USB数据线一根

3、ds18b20传感器两个

4、Air780EPM核心板和数据线的硬件接线方式为

- Air780EPM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air780EPM核心板和ds18b20传感器接线方式

### 单传感器连接

|   Air780EPM核心板     |    DS18B20传感器    |
| --------------- | -------------------|
|    VDD_EXT         |         VCC        |
|    23/GPIO2     |         DQ         |
|    GND          |         GND        |

连接图：

![image](https://docs.openluat.com/air780epm/luatos/app/driver/onewire/image/ce9d3b2c9b3a36c22388d710913668a7.jpg)

### 多传感器连接


|   Air780EPM核心板     |    DS18B20传感器1    |
| --------------- | -------------------|
|    VDD_EXT         |         VCC        |
|    23/GPIO2     |         DQ         |
|    任意GND          |         GND        |

|   Air780EPM核心板     |    DS18B20传感器2    |
| --------------- | -------------------|
|    32/GPIO31         |         VCC        |
|    54/CAM_MCLK     |         DQ         |
|    任意GND          |         GND        |

连接图：

![image](https://docs.openluat.com/air780epm/luatos/app/driver/onewire/image/1957f5eb447654ec31894efb589e809b.jpg)

## 演示软件环境

1、Luatools下载调试工具： https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：
Air780EPM:https://docs.openluat.com/air780epm/luatos/firmware/version/

## 演示核心步骤
1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板或开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```lua
（1）单传感器演示
[2025-11-24 23:46:59.904][000000000.251] I/user.main onewire_demo 1.0.0
[2025-11-24 23:46:59.932][000000000.258] I/user.onewire_single_app 单传感器模块版本: 002.002.000
[2025-11-24 23:46:59.970][000000000.258] I/user.onewire_single_app 单传感器应用模块加载完成
[2025-11-24 23:47:00.002][000000000.259] I/user.onewire_single_app 启动单传感器应用
[2025-11-24 23:47:00.032][000000000.259] I/user.onewire_single_app 初始化OneWire总线...
[2025-11-24 23:47:00.064][000000000.259] I/user.onewire_single_app OneWire总线初始化完成，使用GPIO2默认引脚
[2025-11-24 23:47:00.096][000000000.259] I/user.onewire_single_app 检测DS18B20设备...
[2025-11-24 23:47:00.124][000000000.267] I/user.onewire_single_app 探测到DS18B20 2859F253000000 14
[2025-11-24 23:47:00.159][000000000.267] I/user.onewire_single_app 开始连续温度监测...
[2025-11-24 23:47:00.186][000000000.276] I/user.onewire_single_app 温度转换完成
[2025-11-24 23:47:00.216][000000000.289] I/user.onewire_single_app 温度读取成功: 85.00°C
[2025-11-24 23:47:00.246][000000000.290] W/user.onewire_single_app 温度偏高: 85.00°C
[2025-11-24 23:47:00.409][000000003.299] I/user.onewire_single_app 温度转换完成
[2025-11-24 23:47:00.436][000000003.312] I/user.onewire_single_app 温度读取成功: 28.25°C
[2025-11-24 23:47:00.465][000000003.313] I/user.onewire_single_app 温度正常: 28.25°C
[2025-11-24 23:47:03.404][000000006.322] I/user.onewire_single_app 温度转换完成
[2025-11-24 23:47:03.437][000000006.335] I/user.onewire_single_app 温度读取成功: 28.25°C
[2025-11-24 23:47:03.469][000000006.335] I/user.onewire_single_app 温度正常: 28.25°C

（2）双传感器演示
[2025-11-24 23:49:45.699][000000000.260] I/user.onewire_multi_app 双传感器应用模块加载完成（54和23切换）
[2025-11-24 23:49:45.732][000000000.261] I/user.onewire_multi_app 启动双传感器应用（引脚54和23）
[2025-11-24 23:49:45.761][000000000.261] I/user.onewire_multi_app 初始化硬件配置...
[2025-11-24 23:49:45.789][000000000.261] I/user.onewire_multi_app 硬件初始化完成
[2025-11-24 23:49:45.822][000000000.262] I/user.onewire_multi_app 初始引脚: 引脚54 (ONEWIRE功能)
[2025-11-24 23:49:45.859][000000000.262] I/user.onewire_multi_app 切换按键: PWR_KEY
[2025-11-24 23:49:45.898][000000000.262] I/user.onewire_multi_app 支持引脚: 54 和 23 循环切换
[2025-11-24 23:49:45.932][000000000.262] I/user.onewire_multi_app 电源控制: GPIO31/GPIO2 (已设置为高电平)
[2025-11-24 23:49:45.963][000000000.262] I/user.onewire_multi_app 电源控制: 开启
[2025-11-24 23:49:45.997][000000000.363] I/user.onewire_multi_app 初始化OneWire总线，通道: 0
[2025-11-24 23:49:46.026][000000000.374] I/user.onewire_multi_app OneWire总线初始化完成，通道: 0，引脚:54
[2025-11-24 23:49:46.059][000000000.573] I/user.onewire_multi_app 检测DS18B20设备，引脚: 54
[2025-11-24 23:49:46.089][000000000.575] I/user.onewire_multi_app 检测到DS18B20设备响应
[2025-11-24 23:49:46.117][000000000.575] I/user.onewire_multi_app 开始双传感器连续监测...
[2025-11-24 23:49:46.148][000000000.575] I/user.onewire_multi_app 按PWR_KEY按键可切换引脚(54和23)
[2025-11-24 23:49:46.181][000000000.575] I/user.onewire_multi_app 第1次读取，引脚:54
[2025-11-24 23:49:46.212][000000000.575] I/user.onewire_multi_app 开始读取DS18B20温度，引脚: 54
[2025-11-24 23:49:46.243][000000000.576] I/user.onewire_multi_app 读取设备ROM ID
[2025-11-24 23:49:46.272][000000000.583] I/user.onewire_multi_app ROM ID校验成功: 289FC493000000 14
[2025-11-24 23:49:46.297][000000000.583] I/user.onewire_multi_app 开始温度转换
[2025-11-24 23:49:46.325][000000000.590] I/user.onewire_multi_app 等待温度转换完成
[2025-11-24 23:49:46.401][000000001.341] I/user.onewire_multi_app 温度转换完成
[2025-11-24 23:49:46.433][000000001.342] I/user.onewire_multi_app 读取温度数据
[2025-11-24 23:49:46.466][000000001.354] I/user.onewire_multi_app CRC校验和温度计算
[2025-11-24 23:49:46.499][000000001.355] I/user.onewire_multi_app 温度读取成功: 27.44°C
[2025-11-24 23:49:46.530][000000001.355] I/user.onewire_multi_app 引脚54温度: 27.44°C 成功率: 100.0%
[2025-11-24 23:49:46.630][000000003.355] I/user.onewire_multi_app 第2次读取，引脚:54
[2025-11-24 23:49:46.665][000000003.356] I/user.onewire_multi_app 开始读取DS18B20温度，引脚: 54
[2025-11-24 23:49:46.698][000000003.356] I/user.onewire_multi_app 读取设备ROM ID
[2025-11-24 23:49:46.727][000000003.363] I/user.onewire_multi_app ROM ID校验成功: 289FC493000000 14
[2025-11-24 23:49:46.765][000000003.363] I/user.onewire_multi_app 开始温度转换
[2025-11-24 23:49:46.799][000000003.371] I/user.onewire_multi_app 等待温度转换完成
[2025-11-24 23:49:46.982][000000004.122] I/user.onewire_multi_app 温度转换完成
[2025-11-24 23:49:47.010][000000004.123] I/user.onewire_multi_app 读取温度数据
[2025-11-24 23:49:47.043][000000004.135] I/user.onewire_multi_app CRC校验和温度计算
[2025-11-24 23:49:47.077][000000004.136] I/user.onewire_multi_app 温度读取成功: 27.50°C
[2025-11-24 23:49:47.110][000000004.137] I/user.onewire_multi_app 引脚54温度: 27.50°C 成功率: 100.0%
[2025-11-24 23:49:48.999][000000006.137] I/user.onewire_multi_app 第3次读取，引脚:54
[2025-11-24 23:49:49.030][000000006.138] I/user.onewire_multi_app 开始读取DS18B20温度，引脚: 54
[2025-11-24 23:49:49.061][000000006.138] I/user.onewire_multi_app 读取设备ROM ID
[2025-11-24 23:49:49.094][000000006.145] I/user.onewire_multi_app ROM ID校验成功: 289FC493000000 14
[2025-11-24 23:49:49.124][000000006.145] I/user.onewire_multi_app 开始温度转换
[2025-11-24 23:49:49.154][000000006.153] I/user.onewire_multi_app 等待温度转换完成
[2025-11-24 23:49:49.778][000000006.904] I/user.onewire_multi_app 温度转换完成
[2025-11-24 23:49:49.806][000000006.905] I/user.onewire_multi_app 读取温度数据
[2025-11-24 23:49:49.836][000000006.917] I/user.onewire_multi_app CRC校验和温度计算
[2025-11-24 23:49:49.866][000000006.918] I/user.onewire_multi_app 温度读取成功: 27.50°C
[2025-11-24 23:49:49.907][000000006.919] I/user.onewire_multi_app 引脚54温度: 27.50°C 成功率: 100.0%

（3）双传感器按键切换演示
[2025-11-24 23:49:51.147][000000008.278] I/user.onewire_multi_app 切换按键被按下
[2025-11-24 23:49:51.783][000000008.919] I/user.onewire_multi_app 切换OneWire引脚...
[2025-11-24 23:49:51.821][000000008.939] I/user.onewire_multi_app 将PAD54配置为GPIO3 true
[2025-11-24 23:49:51.856][000000008.940] I/user.onewire_multi_app 将GPIO3设置为高电平输出 function: 0C7F4A10
[2025-11-24 23:49:51.897][000000008.940] I/user.onewire_multi_app 切换到引脚23
[2025-11-24 23:49:51.933][000000008.940] I/user.onewire_multi_app 当前使用引脚: 23
[2025-11-24 23:49:51.965][000000008.941] I/user.onewire_multi_app 将引脚23配置为ONEWIRE功能 true
[2025-11-24 23:49:51.994][000000008.961] I/user.onewire_multi_app 引脚切换完成，当前使用: 引脚23
[2025-11-24 23:49:52.324][000000009.461] I/user.onewire_multi_app 初始化OneWire总线，通道: 0
[2025-11-24 23:49:52.356][000000009.471] I/user.onewire_multi_app OneWire总线初始化完成，通道: 0，引脚:23
[2025-11-24 23:49:52.431][000000009.571] I/user.onewire_multi_app 第4次读取，引脚:23
[2025-11-24 23:49:52.474][000000009.571] I/user.onewire_multi_app 开始读取DS18B20温度，引脚: 23
[2025-11-24 23:49:52.519][000000009.572] I/user.onewire_multi_app 读取设备ROM ID
[2025-11-24 23:49:52.563][000000009.579] I/user.onewire_multi_app ROM ID校验成功: 2859F253000000 14
[2025-11-24 23:49:52.593][000000009.579] I/user.onewire_multi_app 开始温度转换
[2025-11-24 23:49:52.622][000000009.587] I/user.onewire_multi_app 等待温度转换完成
[2025-11-24 23:49:53.203][000000010.338] I/user.onewire_multi_app 温度转换完成
[2025-11-24 23:49:53.239][000000010.339] I/user.onewire_multi_app 读取温度数据
[2025-11-24 23:49:53.272][000000010.351] I/user.onewire_multi_app CRC校验和温度计算
[2025-11-24 23:49:53.302][000000010.352] I/user.onewire_multi_app 温度读取成功: 27.81°C
[2025-11-24 23:49:53.332][000000010.353] I/user.onewire_multi_app 引脚23温度: 27.81°C 成功率: 100.0%


```