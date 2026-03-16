## 功能模块介绍

1、main.lua 入口文件，加载各功能模块

2、exril_5101_main.lua 主控模块，初始化BLE、配置服务、处理事件

3、exril_5101_receiver.lua 数据接收模块，处理接收到的BLE数据

4、exril_5101_sender.lua 数据发送模块，管理发送队列和BLE数据发送

5、exril_5101_timer.lua 定时发送数据模块，演示定时发送功能

6、exril_5101_wdt.lua 看门狗模块，初始化和喂狗

7、exril_5101_lowpower.lua 低功耗控制模块，定期切换低功耗模式

## 模块架构

```
main.lua (入口文件)
    ├── exril_5101_main.lua (主控模块)
    │   ├── exril_5101_receiver.lua (数据接收)
    │   └── exril_5101_sender.lua (数据发送)
    ├── exril_5101_timer.lua (定时发送数据)
    ├── exril_5101_wdt.lua (看门狗)
    └── exril_5101_lowpower.lua (低功耗控制)
```

## 用户消息介绍

1. `SEND_DATA_REQ`：请求发送BLE数据，由 exril_5101_timer 发布，exril_5101_sender 订阅处理，然后将数据发送给中心设备

2. `RECV_BLE_DATA`：接收到BLE数据，由 exril_5101_main 发布，exril_5101_receiver 订阅处理

3. `BLE_CONNECT_STATUS`：BLE连接状态变化，由 exril_5101_sender 发布，exril_5101_timer 订阅处理

4. `POWER_STATE_CHANGED`：电源状态变化，由 exril_5101_lowpower 发布

## 演示功能概述

1、使用Air780EPM核心板搭配Air5101S开发板演示 exril_5101 功能；

2、演示功能包括：

    - 配置ble外围设备（Air5101S）；

    - 中心设备可以向ble外围设备写入数据；

    - ble外围设备可以接收中心设备写入的数据；

    - ble外围设备可以定时发送notify数据给中心设备；

    - 演示Air5101S的看门狗功能，当看门狗喂狗超时，会重启Air780EPM；
    
    - 演示低功耗控制功能，切换ble外围设备的低功耗模式；

## 演示硬件环境

1、Air780EPM核心板一个；

2、Air5101S开发板一个；

3、串口连接线，用于连接Air780EPM和Air5101

4、TYPE-C USB数据线一根，Air780EPM 核心板和数据线的硬件接线方式为：

- Air780EPM核心板通过TYPE-C USB口供电，核心板正面的 ON/OFF 拨动开关 拨到ON一端；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM 固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

Air780EPM 与 Air5101S 开发板接线:

| Air780EPM 引脚 | Air5101S 开发板引脚 | 
| :-----------  | :---------------  |
| 3.3V          | VBAT              |
| GND           | GND               | 
| RX            | TX                | 
| TX            | RX                | 

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行，通过luatools日志可以观察到以下信息：

```lua
[2026-03-03 14:02:43.562][000000000.299] I/user.exril_5101_wdt 初等待主模块初始化完成...
[2026-03-03 14:02:43.565][000000000.337] I/user.exril_5101_main ========== 配置初始化 ==========
[2026-03-03 14:02:43.565][000000000.338] I/user.exril_5101_main 当前工作模式: exril_5101.MODE_UA
[2026-03-03 14:02:43.566][000000000.338] I/user.exril_5101_main 切换到AT指令模式...
[2026-03-03 14:02:43.569][000000000.359] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +UA
[2026-03-03 14:02:43.569][000000000.360] I/user.exril_5101_main 已切换到: exril_5101.MODE_AT
[2026-03-03 14:02:43.576][000000000.361] I/user.exril_5101_main 配置设备参数...
[2026-03-03 14:02:43.579][000000000.361] I/user.exril_5101.set 处理配置项: name 值: Air5101_Test
[2026-03-03 14:02:43.581][000000000.361] I/user.exril_5101.set 设备名称: Air5101_Test
[2026-03-03 14:02:43.582][000000000.361] I/user.exril_5101.set 添加配置项到序列: name 命令: AT+SN=Air5101_Test
[2026-03-03 14:02:43.584][000000000.362] I/user.exril_5101.set 处理配置项: mtu_len 值: 247
[2026-03-03 14:02:43.586][000000000.362] W/user.exril_5101.set mtu_len需要在蓝牙连接后才能设置，跳过
[2026-03-03 14:02:43.588][000000000.363] I/user.exril_5101.set.sync 执行命令: name 命令: AT+SN=Air5101_Test
[2026-03-03 14:02:43.589][000000000.397] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +SN
[2026-03-03 14:02:43.591][000000000.398] I/user.exril_5101.set.sync 执行结果: name 成功: true 响应: AT:OK
[2026-03-03 14:02:43.592][000000000.418] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +SAVE
[2026-03-03 14:02:43.596][000000000.419] I/user.exril_5101.set 配置保存到Flash成功
[2026-03-03 14:02:43.599][000000000.419] I/user.exril_5101_main 参数配置成功
[2026-03-03 14:02:43.600][000000000.419] I/user.exril_5101_main 查询设备信息...
[2026-03-03 14:02:43.602][000000000.419] I/user.exril_5101.get 批量获取参数: name,mac,ver
[2026-03-03 14:02:43.603][000000000.450] I/user.ril.proatc AT:Air5101_Test cmdtype: 11 cmdhead: +GN
[2026-03-03 14:02:43.605][000000000.452] I/user.exril_5101.get name 获取成功: Air5101_Test
[2026-03-03 14:02:43.607][000000000.485] I/user.ril.proatc AT:0x443322116AED cmdtype: 11 cmdhead: +GM
[2026-03-03 14:02:43.608][000000000.487] I/user.exril_5101.get mac 获取成功: ED6A11223344
[2026-03-03 14:02:43.612][000000000.520] I/user.ril.proatc AT:1.5.2-2601211840 cmdtype: 11 cmdhead: +VER
[2026-03-03 14:02:43.614][000000000.521] I/user.exril_5101.get ver 获取成功: 1.5.2-2601211840
[2026-03-03 14:02:43.615][000000000.522] I/user.exril_5101_main 设备名称: Air5101_Test
[2026-03-03 14:02:43.616][000000000.522] I/user.exril_5101_main MAC地址: ED6A11223344
[2026-03-03 14:02:43.618][000000000.522] I/user.exril_5101_main 固件版本: 1.5.2-2601211840
[2026-03-03 14:02:43.619][000000000.522] I/user.exril_5101_main BLE事件回调已注册
[2026-03-03 14:02:43.621][000000000.523] I/user.exril_5101_wdt 收到主模块初始化完成信号，开始初始化看门狗...
[2026-03-03 14:02:43.622][000000000.523] I/user.exril_5101_wdt 当前工作模式: exril_5101.MODE_AT
[2026-03-03 14:02:43.624][000000000.524] D/user.exril_5101.wdcfg 设置命令: AT+WDCFG=1,60,0,100
[2026-03-03 14:02:43.629][000000000.559] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +WDCFG
[2026-03-03 14:02:43.630][000000000.578] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +SAVE
[2026-03-03 14:02:43.632][000000000.579] I/user.exril_5101.wdt.init 看门狗初始化成功，超时: 60 秒
[2026-03-03 14:02:43.633][000000000.579] I/user.exril_5101_wdt 看门狗初始化成功
[2026-03-03 14:02:43.635][000000000.580] I/user.exril_5101_wdt 喂狗任务启动，间隔: 30.00000 秒
[2026-03-03 14:02:58.275][000000015.395] I/user.ril.proatc AT:DISCONNECT cmdtype: nil cmdhead: nil
[2026-03-03 14:02:58.283][000000015.397] I/user.exril_5101_main 收到BLE事件: DISCONNECTED table: 0C7E36D0
[2026-03-03 14:02:58.287][000000015.397] I/user.exril_5101_main 蓝牙断开连接
[2026-03-03 14:02:58.289][000000015.398] I/user.exril_5101_timer 已停止notify发送定时器
[2026-03-03 14:02:58.819][000000015.937] I/user.ril.proatc AT:CONNECTED cmdtype: nil cmdhead: nil
[2026-03-03 14:02:58.824][000000015.938] I/user.exril_5101_main 收到BLE事件: CONNECTED table: 0C7E3010
[2026-03-03 14:02:58.825][000000015.939] I/user.exril_5101_main 蓝牙连接成功
[2026-03-03 14:02:58.829][000000015.940] I/user.exril_5101_timer 已启动notify发送定时器, 间隔: 5000 ms
[2026-03-03 14:03:03.859][000000020.977] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +BS
[2026-03-03 14:03:08.823][000000025.941] I/user.exril_5101_timer 发送结果: true 参数: notify Notify 1 08:00:20
[2026-03-03 14:03:08.859][000000025.978] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +BS
[2026-03-03 14:03:12.448][000000029.565] I/user.ril.proatc AT:DISCONNECT cmdtype: nil cmdhead: nil
[2026-03-03 14:03:12.450][000000029.566] I/user.exril_5101_main 收到BLE事件: DISCONNECTED table: 0C7E1AC0
[2026-03-03 14:03:12.451][000000029.567] I/user.exril_5101_main 蓝牙断开连接
[2026-03-03 14:03:12.454][000000029.568] I/user.exril_5101_timer 已停止notify发送定时器
[2026-03-03 14:03:13.485][000000030.603] I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +WDFED
[2026-03-03 14:03:13.487][000000030.604] D/user.exril_5101.wdt.feed 喂狗成功
[2026-03-03 14:03:13.488][000000030.605] D/user.exril_5101_wdt 喂狗成功

```