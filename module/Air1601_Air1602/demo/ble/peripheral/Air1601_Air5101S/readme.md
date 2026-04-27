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

1、Air1601开发板已板载Air5101S蓝牙模块，可直接使用Air1601开发板演示 exril_5101 功能；

2、演示功能包括：

    - 配置ble外围设备（Air5101S）；

    - 中心设备可以向ble外围设备写入数据；

    - ble外围设备可以接收中心设备写入的数据；

    - ble外围设备可以定时发送notify数据给中心设备；

    - 演示Air5101S的看门狗功能，当看门狗喂狗超时，会重启Air1601；
    
    - 演示低功耗控制功能，切换ble外围设备的低功耗模式；

## 演示硬件环境

1、Air1601开发板一个；

2、TYPE-C USB数据线一根，Air1601开发板和数据线的硬件接线方式为：

- Air1601开发板通过USB口供电；

- TYPE-C USB数据线直接插到开发板的USB1口(串口下载)座子，另外一端连接电脑USB口；

拨码开关位置请参考如下文档串口烧录章节[1601开发板使用说明](https://docs.openluat.com/air1601/product/file/Air1601%E5%BC%80%E5%8F%91%E6%9D%BF%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.pdf)

## 演示软件环境

1、Luatools下载调试工具

2、[Air1601 V1010版本固件）](https://docs.openluat.com/air1601/luatos/firmware/)

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行，通过luatools日志可以观察到以下信息：

```lua
[2026-04-16 18:55:30.476][LTOS/N][000000000.015]:I/user.main project name is  exril_5101_demo version is  001.999.000
[2026-04-16 18:55:30.479][CAPP/N][000000000.044]:Uart_ChangeBR 347:uart1 波特率 目标 9600 实际 9600
[2026-04-16 18:55:30.482][LTOS/N][000000000.048]:I/user.exril_5101_wdt 初等待主模块初始化完成...
[2026-04-16 18:55:30.486][CAPP/N][000000000.056]:Uart_ChangeBR 347:uart3 波特率 目标 9600 实际 9600
[2026-04-16 18:55:30.489][LTOS/N][000000000.057]:I/user.exril_5101.config_uart 已更新主控串口ID: 3
[2026-04-16 18:55:30.492][LTOS/N][000000000.071]:I/user.exril_5101_main ========== 配置初始化 ==========
[2026-04-16 18:55:30.494][LTOS/N][000000000.082]:I/user.exril_5101_main 当前工作模式: exril_5101.MODE_UA
[2026-04-16 18:55:30.496][LTOS/N][000000000.082]:I/user.exril_5101_main 切换到AT指令模式...
[2026-04-16 18:55:30.499][CAPP/N][000000000.092]:_uart_tx_next 114:uart3, tx one block done 7
[2026-04-16 18:55:30.502][CAPP/N][000000000.092]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.504][CAPP/N][000000000.099]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.507][LTOS/N][000000000.114]:I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +UA
[2026-04-16 18:55:30.510][LTOS/N][000000000.123]:I/user.exril_5101_main 已切换到: exril_5101.MODE_AT
[2026-04-16 18:55:30.513][LTOS/N][000000000.124]:I/user.exril_5101_main 配置设备参数...
[2026-04-16 18:55:30.515][LTOS/N][000000000.125]:I/user.exril_5101.set 设备名称: Air5101_Test
[2026-04-16 18:55:30.518][LTOS/N][000000000.125]:I/user.exril_5101.set 添加配置项到序列: name 命令: AT+SN=Air5101_Test
[2026-04-16 18:55:30.521][LTOS/N][000000000.126]:W/user.exril_5101.set mtu_len需要在蓝牙连接后才能设置，跳过
[2026-04-16 18:55:30.524][CAPP/N][000000000.132]:_uart_tx_next 114:uart3, tx one block done 20
[2026-04-16 18:55:30.527][CAPP/N][000000000.132]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.529][CAPP/N][000000000.147]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.531][LTOS/N][000000000.162]:I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +SN
[2026-04-16 18:55:30.534][CAPP/N][000000000.163]:_uart_tx_next 114:uart3, tx one block done 9
[2026-04-16 18:55:30.537][CAPP/N][000000000.163]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.540][CAPP/N][000000000.172]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.542][LTOS/N][000000000.184]:I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +SAVE
[2026-04-16 18:55:30.545][LTOS/N][000000000.184]:I/user.exril_5101.set 配置保存到Flash成功
[2026-04-16 18:55:30.547][LTOS/N][000000000.185]:I/user.exril_5101_main 参数配置成功
[2026-04-16 18:55:30.550][LTOS/N][000000000.185]:I/user.exril_5101_main 查询设备信息...
[2026-04-16 18:55:30.552][LTOS/N][000000000.195]:I/user.exril_5101.get 批量获取参数: name,mac,ver
[2026-04-16 18:55:30.554][CAPP/N][000000000.195]:_uart_tx_next 114:uart3, tx one block done 7
[2026-04-16 18:55:30.557][CAPP/N][000000000.196]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.559][CAPP/N][000000000.203]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.562][LTOS/N][000000000.228]:I/user.ril.proatc AT:Air5101_Test cmdtype: 11 cmdhead: +GN
[2026-04-16 18:55:30.566][LTOS/N][000000000.229]:I/user.exril_5101.get name 获取成功: Air5101_Test
[2026-04-16 18:55:30.570][CAPP/N][000000000.229]:_uart_tx_next 114:uart3, tx one block done 7
[2026-04-16 18:55:30.573][CAPP/N][000000000.230]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.576][CAPP/N][000000000.237]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.611][LTOS/N][000000000.264]:I/user.ril.proatc AT:0xA4A493C6C2C8 cmdtype: 11 cmdhead: +GM
[2026-04-16 18:55:30.616][LTOS/N][000000000.265]:I/user.exril_5101.get mac 获取成功: C8C2C693A4A4
[2026-04-16 18:55:30.619][CAPP/N][000000000.265]:_uart_tx_next 114:uart3, tx one block done 8
[2026-04-16 18:55:30.622][CAPP/N][000000000.265]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.627][CAPP/N][000000000.274]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.631][LTOS/N][000000000.301]:I/user.ril.proatc AT:1.5.2-2601211840 cmdtype: 11 cmdhead: +VER
[2026-04-16 18:55:30.634][LTOS/N][000000000.302]:I/user.exril_5101.get ver 获取成功: 1.5.2-2601211840
[2026-04-16 18:55:30.637][LTOS/N][000000000.308]:I/user.exril_5101_main 设备名称: Air5101_Test
[2026-04-16 18:55:30.640][LTOS/N][000000000.309]:I/user.exril_5101_main MAC地址: C8C2C693A4A4
[2026-04-16 18:55:30.645][LTOS/N][000000000.309]:I/user.exril_5101_main 固件版本: 1.5.2-2601211840
[2026-04-16 18:55:30.648][LTOS/N][000000000.309]:I/user.exril_5101_main BLE事件回调已注册
[2026-04-16 18:55:30.651][LTOS/N][000000000.309]:I/user.exril_5101_wdt 收到主模块初始化完成信号，开始初始化看门狗...
[2026-04-16 18:55:30.654][LTOS/N][000000000.320]:I/user.exril_5101_wdt 当前工作模式: exril_5101.MODE_AT
[2026-04-16 18:55:30.657][LTOS/N][000000000.323]:D/user.exril_5101.wdcfg 设置命令: AT+WDCFG=1,60,0,100
[2026-04-16 18:55:30.664][CAPP/N][000000000.330]:_uart_tx_next 114:uart3, tx one block done 21
[2026-04-16 18:55:30.667][CAPP/N][000000000.330]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.670][CAPP/N][000000000.345]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.704][LTOS/N][000000000.360]:I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +WDCFG
[2026-04-16 18:55:30.709][CAPP/N][000000000.361]:_uart_tx_next 114:uart3, tx one block done 9
[2026-04-16 18:55:30.712][CAPP/N][000000000.361]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:30.716][CAPP/N][000000000.371]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:30.719][LTOS/N][000000000.382]:I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +SAVE
[2026-04-16 18:55:30.724][LTOS/N][000000000.383]:I/user.exril_5101.wdt.init 看门狗初始化成功，超时: 60 秒
[2026-04-16 18:55:30.728][LTOS/N][000000000.383]:I/user.exril_5101_wdt 看门狗初始化成功
[2026-04-16 18:55:30.730][LTOS/N][000000000.383]:I/user.exril_5101_wdt 喂狗任务启动，间隔: 20.000000000000 秒
[2026-04-16 18:55:50.705][CAPP/N][000000020.393]:_uart_tx_next 114:uart3, tx one block done 10
[2026-04-16 18:55:50.713][CAPP/N][000000020.393]:_uart_tx_next 150:uart3, tx wait done
[2026-04-16 18:55:50.717][CAPP/N][000000020.403]:_uart_tx_next 142:uart3, tx done
[2026-04-16 18:55:50.722][LTOS/N][000000020.418]:I/user.ril.proatc AT:OK cmdtype: 11 cmdhead: +WDFED
[2026-04-16 18:55:50.726][LTOS/N][000000020.419]:D/user.exril_5101.wdt.feed 喂狗成功
[2026-04-16 18:55:50.729][LTOS/N][000000020.425]:D/user.exril_5101_wdt 喂狗成功


```