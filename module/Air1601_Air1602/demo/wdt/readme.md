# wdt_DEMO 项目说明

## 项目概述
本项目是基于 Air1601开发板，演示了三种看门狗(WDT)功能的使用。

> 使用 AirLink 方式看门狗时，演示代码中设计的喂狗空闲电平为 低电平，喂狗电平为 高电平。
>
> 需要在 Air1601 与 从机 之间通过 三极管 方式设计双向互看门狗电路。
>
> 双向互看门狗电路可以参考 Air1601 开发板设计文件：[Air1601 规格书/原理图PCB封装/参考设计/开发板/核心板/引擎主机](https://docs.openluat.com/air1601/product/shouce/)。
>
> 在选择控制管脚时，需要注意不要选择默认电平为高电平的管脚，会导致误复位从机。
>
> 后续会在 DOCS 文档中展示 Air1601 默认电平表格，**链接待补充**。

- 内部看门狗 - 使用芯片内置的硬件看门狗

- 外部看门狗 - 使用 Air153C 外置看门狗芯片

- AirLink 方式看门狗（需要主/从机均支持 AirLink 库才能实现）
  - 主控与被控通过 UART 方式实现 AirLink 通信，通过 AirLink 通信实现主控与被控双向互看门狗操作；
  - 主控与被控通过 SPI 方式实现 AirLink 通信，通过 AirLink 通信实现主控与被控双向互看门狗操作；


## 功能说明

内部看门狗演示

 - 自动启用：硬件看门狗由底层固件自动启用，超时时间20秒

 - 定期喂狗：每3秒执行一次喂狗操作，确保系统正常运行

 - 故障模拟：可模拟系统死锁导致无法喂狗的场景

 - 自动恢复：看门狗超时后自动重启系统

外部看门狗演示 (Air153C)

 - 引脚控制：通过GPIO引脚24控制外部看门狗芯片

 - 定期喂狗：每10秒执行一次喂狗操作

 - 故障模拟：可模拟程序异常停止喂狗的场景

 - 硬件复位：外部看门狗超时后通过硬件复位系统

AirLink UART 方式看门狗演示

- 引脚控制：通过GPIO引脚14控制对端复位
- 定期喂狗：每150秒执行一次喂狗操作
- 故障模拟：当停止喂狗超过240秒后，对端会将本端进行复位
- 硬件复位：对端控制本端的RESET管脚实现硬件复位

AirLink SPI 方式看门狗演示

- 引脚控制：通过GPIO引脚14控制对端复位
- 定期喂狗：每150秒执行一次喂狗操作
- 故障模拟：当停止喂狗超过240秒后，对端会将本端进行复位
- 硬件复位：对端控制本端的RESET管脚实现硬件复位

## 演示硬件环境

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、Air780ER2、Air780ER3 核心板各一块（板子图片待补充）

- Air780ER2/ER3 模组专门用于为主控提供 4G 上网能力；
- 该模组不需要用户进行二次开发，收到后其模组内部已经烧录好底层固件和脚本，上手即用；
- 模组详细资料请参考：[Air780ER2/ER3 简介](https://docs.openluat.com/air780er2/product/)

2、TYPE-C USB数据线两根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

4、Air1601 开发板与 Air780ER2 核心板硬件接线方式如下，用于演示 AirLink UART 看门狗

| 说明               | Air1601 开发板（排针丝印） | Air780ER2 核心板（排针丝印） |
| ------------------ | -------------------------- | ---------------------------- |
| 主机接收，从机发送 | RX3                        | 18/U1_TXD                    |
| 主机发送，从机接收 | TX3                        | 17/U1_RXD                    |
| 共地               | GND                        | GND                          |
| 主机控制复位从机   | CS1                        | 15/RESET_N                   |
| 从机控制复位主机   | RESET                      | 16/GPIO27                    |

5、Air1601 开发板与 Air780ER3 核心板硬件接线方式如下，用于演示 AirLink SPI 看门狗

| 说明             | Air1601 开发板 | Air780ER3 核心板 |
| ---------------- | -------------- | ---------------- |
| SPI_CS           | CS0            | 30/SPI0_CS       |
| SPI_CLK          | CLK1           | 33/SPI0_CLK      |
| SPI_MOSI         | MOSI1          | 32/SPI0_MOSI     |
| SPI_MISO         | MISO1          | 31/SPI0_MISO     |
| RDY              | GPIO12         | 26/GPIO25        |
| GND              | GND            | GND              |
| 主机控制复位从机 | CS1            | 15/RESET_N       |
| 从机控制复位主机 | RESET          | 16/GPIO27        |

Air1601 购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

Air780ER2 购买链接：[Air780ER2 USB/RNDIS通用协议 合宙AirLink协议搭配Air1601/8101](https://item.taobao.com/item.htm?id=1058735769426&spm=a1z10.3-c-s.w4002-24045920836.9.82516ee5SFBB4k)

Air780ER3 购买链接：[Air780ER3 USB/RNDIS通用协议 合宙AirLink协议搭配Air1601/8101](https://item.taobao.com/item.htm?id=1068550237908&spm=a1z10.3-c-s.w4002-24045920836.9.6e206ee5o1MxoN)

## 演示软件环境

在开始实践本示例之前，先筹备一下软件环境：

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.Air1601 内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1012_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.Air780ER2/ER3 量产固件文件：

Air780ER2/ER3 不需要用户再进行二次开发，在收到模组后其模组内部已经烧录好内核固件和脚本。

如果需要查看固件更新说明请参考：[Air780ER2/ER3 固件版本索引](https://docs.openluat.com/air780er2/product/firmware/)

3.luatos 需要的脚本和资源文件

- Air1601 脚本和资源文件[点击此处查看与下载](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/wdt)

- lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

4.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板 中。

## 相关软件资料

wdt 核心库文档：https://docs.openluat.com/osapi/core/wdt/

air153C_wtd 扩展库文档：https://docs.openluat.com/osapi/ext/air153C_wtd/

## 演示核心步骤
1、搭建好硬件环境

2、加载演示脚本文件：

- 在main.lua中自由选择以下四个lua文件中的一个

  - require "internal_wdt"  -- 内部看门狗演示模块

  - require "air153c_wdt"    -- 外部看门狗演示模块

  - require "airlink_uart_wdt" -- AirLink UART模式看门狗演示模块

  - require "airlink_spi_wdt" -- AirLink SPI模式看门狗演示模块

- 在 internal_wdt.lua 或者 air153c_wdt.Lua 两个演示脚本中，通过修改 DEMO_MODE 变量选择演示模式

 - local DEMO_MODE = "normal"   -- 正常模式：持续喂狗

 - local DEMO_MODE = "fault"    -- 故障模式：模拟系统故障

 - airlink_uart_wdt.lua 与 airlink_spi_wdt 两个演示脚本不需要用户进行任何修改，只需按照文档说明进行硬件接线即可

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行

5、内部看门狗演示

- 正常模式演示

  设置 DEMO_MODE = "normal"

  烧录并运行脚本

  程序运行后会显示以下典型日志：
  ```lua
  I/user.wdt 硬件看门狗已由底层固件启用
  I/user.wdt 喂狗完成
  I/user.wdt 喂狗完成
  ```

- 故障模式演示

  设置 DEMO_MODE = "fault"

  烧录并运行脚本

  程序运行后会显示以下典型日志：
  ```lua
  [2026-04-22 11:19:16.939][LTOS/N][000000000.014]:I/user.main wdt_DEMO 001.999.000
  [2026-04-22 11:19:16.942][LTOS/N][000000000.016]:I/user.wdt 硬件看门狗已由底层固件启用
  [2026-04-22 11:19:16.945][CAPP/N][000000000.016]:luat_pm_last_state 66:not support yet
  [2026-04-22 11:19:16.949][LTOS/N][000000000.016]:I/user.reset_reason 重启原因1: 0 原因2: 0 原因3: 0
  [2026-04-22 11:19:19.837][LTOS/N][000000003.016]:I/user.wdt 喂狗完成
  [2026-04-22 11:19:21.784][LTOS/N][000000005.016]:I/user.wdt 故障前最后一次喂狗，成功 = true
  [2026-04-22 11:19:21.795][LTOS/N][000000005.016]:I/user.fault_task 进入死循环模拟故障
  [2026-04-22 11:19:21.806][LTOS/N][000000005.016]:I/user.fault_task 看门狗喂狗任务被阻塞，系统将在约20秒后重启
  [2026-04-22 11:19:47.832][CAPP/N][000000031.061]:wdt timeout
  [2026-04-22 11:19:47.842][CAPP/N][000000031.061]:看门狗超时
  [2026-04-22 11:19:47.852][CAPP/N][000000031.061]:pc 1401ad08
  [2026-04-22 11:19:47.859][CAPP/N][000000031.061]:lr 1400e547
  [2026-04-22 11:19:47.866][CAPP/N][000000031.061]:等待下一次wdt超时后重启
  [2026-04-22 11:19:47.872][!!BS/N][000000031.061]:2
  [2026-04-22 11:19:47.877] 工具提示: SOC已经死机
  [2026-04-22 11:19:47.886] 工具提示: 正在捕获死机信息！！！
  [2026-04-22 11:19:47.889][CAPP/N][000000031.089]:soc_cmd_input 1179:ram1 20000000 57544
  [2026-04-22 11:19:47.892][CAPP/N][000000031.089]:soc_cmd_input 1180:ram2 1c000000 3803528
  [2026-04-22 11:19:47.895] 工具提示: 接收20000000.bin,共57544byte,大约需要0秒
  [2026-04-22 11:19:48.249] 工具提示: 接收20000000.bin完成, 共57544byte
  [2026-04-22 11:19:48.252] 工具提示: 接收1c000000.bin,共3803528byte,大约需要12秒
  [2026-04-22 11:20:14.772] 工具提示: 接收1c000000.bin完成, 共3803528byte
  [2026-04-22 11:20:14.781] 工具提示: 接收完成100%，存放路径D:\LuaTools\log\ramdump\2026-04-22_111947___COM28，请将该文件夹交给FAE分析
  [2026-04-22 11:20:40.995] 工具提示: trace lost 48 -> 1
  [2026-04-22 11:20:41.017][CAPP/N][000000000.000]:Uart_ChangeBR 347:uart4 波特率 目标 6000000 实际 6000000
  [2026-04-22 11:20:41.029][CAPP/N][000000000.001]:__start 47:bootloader start! build in Apr 20 2026,18:12:29
  [2026-04-22 11:20:41.039][CAPP/N][000000000.001]:ffffffff,1
  [2026-04-22 11:20:41.048][FOTA/N][000000000.001]:bl_fota_check 101:no ota info
  [2026-04-22 11:20:41.054][CAPP/N][000000000.001]:__start 58:no fota
  [2026-04-22 11:20:41.060][CAPP/N][000000000.001]:__start 73:ap in flash
  [2026-04-22 11:20:41.066][CAPP/N][000000000.001]:__start 82:jump to 0x1400033d in 769267!
  [2026-04-22 11:20:41.073] 工具提示: trace lost 8 -> 1
  [2026-04-22 11:20:41.078][CAPP/N][000000000.000]:Uart_ChangeBR 347:uart4 波特率 目标 6000000 实际 6000000
  [2026-04-22 11:20:41.082][CAPP/N][000000000.000]:soc_heap_print_init_info 59:heap0 start 0x1c020988 total 1048576
  [2026-04-22 11:20:41.086][CAPP/N][000000000.000]:soc_heap_print_init_info 59:heap1 start 0x1c120988 total 524288
  [2026-04-22 11:20:41.089][CAPP/N][000000000.000]:soc_heap_print_init_info 59:heap2 start 0x1c3b0988 total 12908152
  [2026-04-22 11:20:41.092][CAPP/N][000000000.000]:soc_create_event_task 174:task am_timer have 128 isr_event, total 192 static event
  [2026-04-22 11:20:41.096][CAPP/N][000000000.000]:am_service_init 743:TRIM时钟 400000000
  [2026-04-22 11:20:41.099][CAPP/N][000000000.000]:am_service_init 744:内核时钟 480000000
  [2026-04-22 11:20:41.104][CAPP/N][000000000.000]:am_service_init 745:系统时钟 240000000
  [2026-04-22 11:20:41.107][CAPP/N][000000000.000]:am_service_init 746:IPS时钟 120000000
  [2026-04-22 11:20:41.110][CAPP/N][000000000.000]:am_service_init 747:AHB3时钟 240000000
  [2026-04-22 11:20:41.114][CAPP/N][000000000.000]:am_service_init 749:复位原因 8
  [2026-04-22 11:20:41.118][CAPP/N][000000000.000]:am_service_init 750:Air1601_A11
  [2026-04-22 11:20:41.121][CAPP/N][000000000.000]:soc_create_event_task 174:task am_service have 64 isr_event, total 128 static event
  [2026-04-22 11:20:41.124][CAPP/N][000000000.000]:soc_create_event_task 174:task am_work have 16 isr_event, total 80 static event
  [2026-04-22 11:20:41.129][CAPP/N][000000000.001]:soc_create_event_task 174:task luat_ctrl_usb have 64 isr_event, total 128 static event
  [2026-04-22 11:20:41.131][CAPP/N][000000000.001]:soc_create_event_task 174:task luat_app_usb have 64 isr_event, total 128 static event
  [2026-04-22 11:20:41.135][CAPP/N][000000000.001]:soc_create_event_task 174:task luatos have 128 isr_event, total 192 static event
  [2026-04-22 11:20:41.138][CAPP/N][000000000.001]:soc_create_event_task 174:task lwip have 64 isr_event, total 128 static event
  [2026-04-22 11:20:41.141][CAPP/N][000000000.001]:soc_create_event_task 174:task luat_camera have 16 isr_event, total 80 static event
  [2026-04-22 11:20:41.144][CAPP/N][000000000.001]:__start 84:app start! build in Apr 20 2026,18:11:44
  [2026-04-22 11:20:41.153][LTOS/N][000000000.002]:I/main LuatOS@Air1601 base 26.04 bsp V1012 64bit
  [2026-04-22 11:20:41.158][LTOS/N][000000000.002]:I/main ROM Build: Apr 20 2026 18:11:53
  [2026-04-22 11:20:41.160][LTOS/N][000000000.005]:W/pins /luadb/pins_air1601.json not exist!!
  [2026-04-22 11:20:41.165][LTOS/N][000000000.008]:D/main loadlibs luavm 2097144 34176 34208
  [2026-04-22 11:20:41.168][MEMP/N][000000000.008]:pool 0, 1048576,111920,111920
  [2026-04-22 11:20:41.171][MEMP/N][000000000.008]:pool 1, 524288,0,0
  [2026-04-22 11:20:41.174][MEMP/N][000000000.008]:pool 2, 12908152,224,268
  [2026-04-22 11:20:41.177][LTOS/N][000000000.008]:D/main loadlibs sys   14481016 112144 112188
  [2026-04-22 11:20:41.182][LTOS/N][000000000.014]:I/user.main wdt_DEMO 001.999.000
  [2026-04-22 11:20:41.185][LTOS/N][000000000.016]:I/user.wdt 硬件看门狗已由底层固件启用
  [2026-04-22 11:20:41.188][CAPP/N][000000000.016]:luat_pm_last_state 66:not support yet
  [2026-04-22 11:20:41.191][LTOS/N][000000000.016]:I/user.reset_reason 重启原因1: 0 原因2: 0 原因3: 8
  ```

6、AirLink SPI 模式看门狗演示模块

7、关于重启时间的说明：

   实际重启时间不是精确的20秒，主要原因包括：

   硬件处理时间：从看门狗超时到实际硬件复位需要一定的处理时间

   系统状态保存：在复位前系统需要保存必要的状态信息和日志便于分析

8、关于重启原因值的验证：

   根据[pm.lastReson()函数的返回值说明](https://docs.openluat.com/osapi/core/pm/#45-pmlastreson)确认重启的原因3: 8 是内部看门狗触发的重启。

9、AirLink UART/SPI 模式看门狗演示模块

- 开启喂狗，并进行第一次喂狗操作（默认每 150 秒喂狗一次）

  ```
  [2026-07-22 23:58:07.021][LTOS/N][000000005.081]:I/user.exairlinkwdt 命令发送成功: WDT:OPEN
  [2026-07-22 23:58:07.024][LTOS/N][000000005.081]:I/airlink sdata via RPC notify len=8
  [2026-07-22 23:58:07.027][LTOS/N][000000005.082]:I/user.exairlinkwdt 命令发送成功: WDT:FEED
  [2026-07-22 23:58:07.030][LTOS/N][000000005.082]:I/user.exairlinkwdt 喂狗定时器启动，周期: 150000 ms
  [2026-07-22 23:58:07.048][LTOS/N][000000005.082]:I/user.exairlinkwdt 看门狗初始化成功，管脚: 14 常态电平: 0
  [2026-07-22 23:58:07.052][LTOS/N][000000005.082]:I/user.main 看门狗启动成功
  ```

- 从机收到开启命令后开启/重置等待喂狗超时定时器

  ```
  [2026-07-22 23:58:07.002][000000006.924] I/user.exairlinkwdt TO_RESET 管脚配置成功，管脚: 27 常态电平: 0
  [2026-07-22 23:58:07.007][000000006.925] I/user.exairlinkwdt 等待喂狗超时定时器启动，超时时长: 240000 ms
  [2026-07-22 23:58:07.014][000000006.925] I/user.收到AIRLINK_SDATA!! WDT:OPEN
  [2026-07-22 23:58:07.017][000000006.927] I/user.exairlinkwdt 收到喂狗命令，重置等待喂狗超时定时器
  [2026-07-22 23:58:07.029][000000006.927] I/user.exairlinkwdt 等待喂狗超时定时器已停止
  [2026-07-22 23:58:07.043][000000006.928] I/user.exairlinkwdt 等待喂狗超时定时器启动，超时时长: 240000 ms
  [2026-07-22 23:58:07.055][000000006.928] I/user.收到AIRLINK_SDATA!! WDT:FEED
  [2026-07-22 23:58:07.060][000000006.929] I/user.收到AIRLINK_SDATA!! Air1602 Wed Jan  1 08:00:00 2020
  ```

- 从机的等待喂狗超时定时器超时时间达到后，会复位 1601

  ```
  [2026-07-23 00:02:07.000][000000246.923] W/user.exairlinkwdt 等待喂狗超时，触发硬件复位
  [2026-07-23 00:02:07.011][000000246.924] W/user.exairlinkwdt TO_RESET 管脚输出复位电平: 1
  [2026-07-23 00:02:07.110][000000247.024] I/user.exairlinkwdt TO_RESET 管脚恢复常态电平: 0
  ```

- 1601 被从机硬件复位

  ```
  [2026-07-23 00:02:06.386][LTOS/N][000000244.432]:D/airlink 统计信息 接收IP字节 11830 11830 0 0
  [2026-07-23 00:02:06.390][LTOS/N][000000244.432]:D/airlink 统计信息 等待从机 0
  [2026-07-23 00:02:06.394][LTOS/N][000000244.432]:D/airlink 统计信息 Task超时事件 0
  [2026-07-23 00:02:06.398][LTOS/N][000000244.432]:D/airlink 统计信息 Task新数据事件 401
  [2026-07-23 00:02:06.401][LTOS/N][000000244.433]:I/user.发送数据给对端设备 Air1602 Wed Jan  1 08:00:00 2020 当前airlink状态 true
  [2026-07-23 00:02:06.405][LTOS/N][000000244.433]:I/airlink sdata via RPC notify len=32
  [2026-07-23 00:02:06.521][LTOS/N][000000244.588]:D/net adatper 15 dns server 0.0.0.0
  [2026-07-23 00:02:06.846][LTOS/N][000000244.914]:I/user.收到AIRLINK_SDATA!! Air780ER2 Thu Jul 23 00:02:07 2026
  [2026-07-23 00:02:07.283] 工具提示: trace lost 3473 -> 1
  [2026-07-23 00:02:07.289][CAPP/N][000000000.000]:Uart_ChangeBR 397:uart4 波特率 目标 6000000 实际 6000000
  [2026-07-23 00:02:07.294][CAPP/N][000000000.001]:__start 48:bootloader start! build in Jul  6 2026,19:51:00
  [2026-07-23 00:02:07.298][CAPP/N][000000000.001]:__start 49:TRIM时钟 400000000
  [2026-07-23 00:02:07.302][CAPP/N][000000000.001]:__start 50:内核时钟 480000000
  [2026-07-23 00:02:07.306][CAPP/N][000000000.001]:__start 51:系统时钟 240000000
  [2026-07-23 00:02:07.310][CAPP/N][000000000.001]:__start 52:IPS时钟 120000000
  [2026-07-23 00:02:07.318][CAPP/N][000000000.001]:__start 53:AHB3时钟 240000000
  [2026-07-23 00:02:07.322][CAPP/N][000000000.001]:__start 54:reset reg 8 vref f
  [2026-07-23 00:02:07.326][CAPP/N][000000000.001]:ffffffff,1
  [2026-07-23 00:02:07.331][FOTA/N][000000000.001]:bl_fota_check 101:no ota info
  [2026-07-23 00:02:07.336][CAPP/N][000000000.002]:__start 64:no fota
  [2026-07-23 00:02:07.339][CAPP/N][000000000.002]:__start 79:ap in flash
  [2026-07-23 00:02:07.343][CAPP/N][000000000.002]:__start 88:jump to 0x1400033d in 1086886!
  [2026-07-23 00:02:07.350] 工具提示: trace lost 14 -> 1
  [2026-07-23 00:02:07.352][CAPP/N][000000000.000]:Uart_ChangeBR 397:uart4 波特率 目标 6000000 实际 6000000
  [2026-07-23 00:02:07.356][CAPP/N][000000000.000]:soc_heap_print_init_info 60:heap0 start 0x1c05a5d8 total 1048576
  [2026-07-23 00:02:07.360][CAPP/N][000000000.000]:soc_heap_print_init_info 60:heap1 start 0x1c15a5d8 total 524288
  [2026-07-23 00:02:07.364][CAPP/N][000000000.000]:soc_heap_print_init_info 60:heap2 start 0x1c7d25d8 total 25352744
  [2026-07-23 00:02:07.369][CAPP/N][000000000.000]:soc_create_event_task 188:task am_timer have 96 isr_event, total 192 static event
  [2026-07-23 00:02:07.373][CAPP/N][000000000.000]:am_service_init 753:TRIM时钟 400000000
  [2026-07-23 00:02:07.381][CAPP/N][000000000.000]:am_service_init 754:内核时钟 480000000
  [2026-07-23 00:02:07.385][CAPP/N][000000000.000]:am_service_init 755:系统时钟 240000000
  [2026-07-23 00:02:07.389][CAPP/N][000000000.000]:am_service_init 756:IPS时钟 120000000
  [2026-07-23 00:02:07.394][CAPP/N][000000000.000]:am_service_init 757:AHB3时钟 240000000
  [2026-07-23 00:02:07.398][CAPP/N][000000000.000]:am_service_init 759:复位原因 0
  [2026-07-23 00:02:07.401][CAPP/N][000000000.000]:am_service_init 760:Air1602_A10
  [2026-07-23 00:02:07.405][CAPP/N][000000000.001]:soc_create_event_task 188:task am_service have 64 isr_event, total 128 static event
  [2026-07-23 00:02:07.413][CAPP/N][000000000.001]:soc_create_event_task 188:task am_work have 16 isr_event, total 80 static event
  [2026-07-23 00:02:07.417][CAPP/N][000000000.001]:soc_create_event_task 188:task luat_ctrl_usb have 64 isr_event, total 128 static event
  [2026-07-23 00:02:07.421][CAPP/N][000000000.001]:soc_create_event_task 188:task luat_app_usb have 64 isr_event, total 128 static event
  [2026-07-23 00:02:07.425][CAPP/N][000000000.002]:soc_create_event_task 188:task luatos have 128 isr_event, total 256 static event
  [2026-07-23 00:02:07.429][CAPP/N][000000000.002]:soc_create_event_task 188:task lwip have 64 isr_event, total 128 static event
  [2026-07-23 00:02:07.432][CAPP/N][000000000.002]:soc_create_event_task 188:task luat_audio have 64 isr_event, total 128 static event
  [2026-07-23 00:02:07.436][CAPP/N][000000000.003]:soc_create_event_task 188:task luat_tts have 0 isr_event, total 64 static event
  [2026-07-23 00:02:07.441][CAPP/N][000000000.003]:soc_create_event_task 188:task luat_camera have 16 isr_event, total 80 static event
  [2026-07-23 00:02:07.445][CAPP/N][000000000.003]:__start 84:app start! build in Jul  6 2026,19:51:03
  [2026-07-23 00:02:07.454][LTOS/N][000000000.004]:I/main LuatOS@Air1602 base 26.04 bsp V1024 64bit
  [2026-07-23 00:02:07.459][LTOS/N][000000000.004]:I/main ROM Build: Jul  6 2026 19:51:24
  [2026-07-23 00:02:07.463][LTOS/N][000000000.007]:W/pins /luadb/pins_air1602.json not exist!!
  [2026-07-23 00:02:07.466][LTOS/N][000000000.010]:D/main loadlibs luavm 2097144 41512 41512
  [2026-07-23 00:02:07.472][LTOS/N][000000000.011]:D/main loadlibs sys   26925608 221792 221836
  [2026-07-23 00:02:07.476][LTOS/N][000000000.017]:I/user.main wdt_DEMO 001.999.000
  [2026-07-23 00:02:07.480][LTOS/N][000000000.038]:D/user.dnsproxy version -> 202607100900
  [2026-07-23 00:02:07.484][LTOS/N][000000000.049]:D/user.udpsrv version -> 202607021200
  [2026-07-23 00:02:07.489][LTOS/N][000000000.052]:D/user.dhcpsrv version -> 202607021200
  [2026-07-23 00:02:07.492][LTOS/N][000000000.057]:D/user.httpdns version -> 202607021200
  [2026-07-23 00:02:07.496][LTOS/N][000000000.059]:D/user.exnetif version -> 202607161200
  [2026-07-23 00:02:07.501][LTOS/N][000000000.068]:D/user.exairlinkwdt version -> 202607190000
  ```

10、外部看门狗演示（待补充）