# wdt_DEMO 项目说明

## 项目概述
本项目是基于 Air8101，演示了三种看门狗(WDT)功能的使用。

> 使用 AirLink 方式看门狗时，演示代码中设计的喂狗空闲电平为 低电平，喂狗电平为 高电平。
>
> 需要在 Air8101 与 从机 之间通过 三极管 方式设计双向互看门狗电路。
>
> 双向互看门狗电路由于 Air8101 开发板设计文件中没有提供，可以参考 Air1601 开发板设计文件：[Air1601 规格书/原理图PCB封装/参考设计/开发板/核心板/引擎主机](https://docs.openluat.com/air1601/product/shouce/)。
>
> 在选择控制管脚时，需要注意不要选择默认电平为高电平的管脚，会导致误复位从机。
>
> 后续会在 DOCS 文档中展示 Air8101 默认电平表格，**链接待补充**。

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

- 引脚控制：通过GPIO引脚6控制对端复位
- 定期喂狗：每150秒执行一次喂狗操作
- 故障模拟：当停止喂狗超过240秒后，对端会将本端进行复位
- 硬件复位：对端控制本端的RESET管脚实现硬件复位

AirLink SPI 方式看门狗演示

- 引脚控制：通过GPIO引脚6控制对端复位
- 定期喂狗：每150秒执行一次喂狗操作
- 故障模拟：当停止喂狗超过240秒后，对端会将本端进行复位
- 硬件复位：对端控制本端的RESET管脚实现硬件复位

## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/multinetwork/4G/image/LzuBbS3NxoVu34x4dj7c3d04nDb.jpg)

1、Air8101核心板一块

2、Air780ER2、Air780ER3 核心板各一块（板子图片待补充）

- Air780ER2/ER3 模组专门用于为主控提供 4G 上网能力；
- 该模组不需要用户进行二次开发，收到后其模组内部已经烧录好底层固件和脚本，上手即用；
- 模组详细资料请参考：[Air780ER2/ER3 简介](https://docs.openluat.com/air780er2/product/)

3、TYPE-C USB数据线一根

4、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；

5、Air8101 核心板与 Air780ER2 核心板硬件接线方式如下，用于演示 AirLink UART 看门狗

| 说明               | Air8101 核心板（排针丝印） | Air780ER2 核心板（排针丝印） |
| ------------------ | -------------------------- | ---------------------------- |
| 主机接收，从机发送 | 11/U1RX                    | 18/U1_TXD                    |
| 主机发送，从机接收 | 12/U1TX                    | 17/U1_RXD                    |
| 共地               | GND                        | GND                          |
| 主机控制复位从机   | 9/GPIO6                    | 15/RESET_N                   |
| 从机控制复位主机   | 23/CEN                     | 16/GPIO27                    |

6、Air1601 开发板与 Air780ER3 核心板硬件接线方式如下，用于演示 AirLink SPI 看门狗

| 说明             | Air8101 核心板（排针丝印） | Air780ER3 核心板（排针丝印） |
| ---------------- | -------------------------- | ---------------------------- |
| SPI_CS           | 54/DISP                    | 30/SPI0_CS                   |
| SPI_CLK          | 28/DCLK                    | 33/SPI0_CLK                  |
| SPI_MOSI         | 57/DE                      | 32/SPI0_MOSI                 |
| SPI_MISO         | 55/HSYN                    | 31/SPI0_MISO                 |
| RDY              | 43/R2                      | 26/GPIO25                    |
| GND              | GND                        | GND                          |
| 主机控制复位从机 | 9/GPIO6                    | 15/RESET_N                   |
| 从机控制复位主机 | 23/CEN                     | 16/GPIO27                    |

Air8101 购买链接：[Air8101 核心板 WiFi 4G 以太网 蓝牙 720P显示屏 200万拍照](https://item.taobao.com/item.htm?id=931016598855&skuId=5816546236665&spm=a1z10.5-c-s.w4002-24045920841.10.40627052RK973c)

Air780ER2 购买链接：[Air780ER2 USB/RNDIS通用协议 合宙AirLink协议搭配Air1601/8101](https://item.taobao.com/item.htm?id=1058735769426&spm=a1z10.3-c-s.w4002-24045920836.9.82516ee5SFBB4k)

Air780ER3 购买链接：[Air780ER3 USB/RNDIS通用协议 合宙AirLink协议搭配Air1601/8101](https://item.taobao.com/item.htm?id=1068550237908&spm=a1z10.3-c-s.w4002-24045920836.9.6e206ee5o1MxoN)

## 演示软件环境

在开始实践本示例之前，先筹备一下软件环境：

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.Air8101 内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V2018_Air8101_101.soc](https://docs.openluat.com/air8101/luatos/firmware/#v2018)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.Air780ER2/ER3 量产固件文件：

Air780ER2/ER3 不需要用户再进行二次开发，在收到模组后其模组内部已经烧录好内核固件和脚本。

如果需要查看固件更新说明请参考：[Air780ER2/ER3 固件版本索引](https://docs.openluat.com/air780er2/product/firmware/)

4.luatos 需要的脚本和资源文件

- Air8101 脚本和资源文件[点击此处查看与下载](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/wdt)

- lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

5.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air8101 核心板中](https://docs.openluat.com/air8101/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到 Air8101核心板 中。

## 相关软件资料

wdt 核心库文档：https://docs.openluat.com/osapi/core/wdt/

air153C_wtd 扩展库文档：https://docs.openluat.com/osapi/ext/air153C_wtd/

## 演示核心步骤
1、搭建好硬件环境

2、加载演示脚本文件：

- 在main.lua中有选择的选择以下两个lua文件中的一个

  - require "internal_wdt"  -- 内部看门狗演示模块

  - require "air153c_wdt"    -- 外部看门狗演示模块

  - require "airlink_uart_wdt" -- AirLink UART模式看门狗演示模块

  - require "airlink_spi_wdt" -- AirLink SPI模式看门狗演示模块

- 在internal_wdt.lua或者air153c_wdt.Lua 两个演示脚本中，通过修改 DEMO_MODE 变量选择演示模式

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
  [2026-07-22 17:09:39.054][CPU1][LTOS/N][000000015.805]:I/user.main wdt_DEMO 001.999.000
  [2026-07-22 17:09:39.055][CPU2][LTOS/N][000000015.811]:I/user.wdt 硬件看门狗已由底层固件启用
  [2026-07-22 17:09:39.059][CPU2][LTOS/N][000000015.811]:reset reason: WDT
  [2026-07-22 17:09:39.061][CPU2][LTOS/N][000000015.812]:I/user.reset_reason 重启原因1: 0 原因2: 0 原因3: 8
  [2026-07-22 17:09:42.038][CPU1][LTOS/N][000000018.812]:I/user.wdt 喂狗完成
  [2026-07-22 17:09:44.049][CPU1][LTOS/N][000000020.810]:I/user.wdt 故障前最后一次喂狗，成功 = true
  [2026-07-22 17:09:44.055][CPU1][LTOS/N][000000020.810]:I/user.fault_task 进入死循环模拟故障
  [2026-07-22 17:09:44.058][CPU1][LTOS/N][000000020.810]:I/user.fault_task 看门狗喂狗任务被阻塞，系统将在约20秒后重启
  [2026-07-22 17:09:53.503][CPU1][CAPP/N][000000030.277]:task wdt timeout!!!
  [2026-07-22 17:09:53.550][CPU0][CAPP/N][000000030.323]:ENV start address is 0x007FA000, size is 8192 bytes.
  [2026-07-22 17:09:53.552][CPU0][CAPP/N][000000030.326]:EasyFlash V4.1.0 is initialize success.
  [2026-07-22 17:09:53.554][CPU0][CAPP/N][000000030.328]:driver_init: psram init ok
  [2026-07-22 17:09:53.557][CPU0][CAPP/N][000000030.329]:uncali sdmadc value:[0 0]
  [2026-07-22 17:09:53.559][CPU0][LTOS/N][000000030.330]:rwnx_cal_set_rfconfig(0x102) phy on; rf off
  [2026-07-22 17:09:53.561][CPU0][CAPP/N][000000030.336]:temp in otp is:582
  [2026-07-22 17:09:53.659][CPU0][CAPP/N][000000030.431]:load polar tab magic code error 0xffffffff
  [2026-07-22 17:09:53.663][CPU0][LTOS/N][000000030.431]:xtal_cali:76
  [2026-07-22 17:09:53.665][CPU0][CAPP/N][000000030.432]:idx:40=40+(0),r:54,xtal:76,pwr_gain:a8ab7128
  [2026-07-22 17:09:53.667][CPU0][CAPP/N][000000030.433]:wifi inited(1) ret(0)
  [2026-07-22 17:09:53.669][CPU0][CAPP/N][000000030.434]:sync_base_mac_record, saved records is more than 1, free index(3).
  [2026-07-22 17:09:54.034][CPU2][CAPP/N][000000030.795]:ENV start address is 0x007FC000, size is 8192 bytes.
  [2026-07-22 17:09:54.126][CPU1][CAPP/N][000000030.888]:EasyFlash V4.1.0 is initialize success.
  [2026-07-22 17:09:54.129][CPU1][CAPP/N][000000030.892]:wdrv_tx_cmd_buffer_init, addr[0]=0x28012e14, pattern_addr=0x28012e10
  [2026-07-22 17:09:54.131][CPU1][CAPP/N][000000030.892]:wdrv_tx_cmd_buffer_init, addr[1]=0x28013134, pattern_addr=0x28013130
  [2026-07-22 17:09:54.133][CPU1][CAPP/N][000000030.892]:wdrv_tx_cmd_buffer_init, addr[2]=0x28013454, pattern_addr=0x28013450
  [2026-07-22 17:09:54.136][CPU0][CAPP/N][000000030.894]:cif_handle_bk_cmd_lwipmem_addr_req,665,addr:0x2806c400
  [2026-07-22 17:09:54.157][CPU1][LTOS/N][000000030.923]:reset native reason: 2
  [2026-07-22 17:09:54.160][CPU1][LTOS/N][000000030.923]:boot up by watchdog reset
  [2026-07-22 17:09:54.162][CPU1][LTOS/N][000000030.923]:reset reason: WDT
  [2026-07-22 17:09:54.164][CPU1][LTOS/N][000000030.923]:poweron reason 8
  [2026-07-22 17:09:54.167][CPU1][LTOS/N][000000030.924]:reset reason: WDT
  [2026-07-22 17:09:54.218][CPU1][LTOS/N][000000030.924]:STA MAC: C8C2C68CD586
  [2026-07-22 17:09:54.223][CPU1][LTOS/N][000000030.925]:AP  MAC: C8C2C68CD587
  [2026-07-22 17:09:54.226][CPU1][CAPP/N][000000030.926]:sync_base_mac_record, saved records is more than 1, free index(3).
  [2026-07-22 17:09:54.230][CPU1][LTOS/N][000000030.926]:BLE MAC: C8C2C68CD588
  [2026-07-22 17:09:54.238][CPU1][LTOS/N][000000030.926]:UID: 54540D2043
  [2026-07-22 17:09:54.243][CPU1][LTOS/N][000000030.928]:LuatOS@Air8101 base 26.04 bsp V2018 64bit
  [2026-07-22 17:09:54.245][CPU1][LTOS/N][000000030.928]:ROM Build: Jul  7 2026 14:14:30
  [2026-07-22 17:09:54.247][CPU1][LTOS/N][000000030.954]:/luadb/pins_air8101.json not exist!!
  [2026-07-22 17:09:54.249][CPU1][LTOS/N][000000030.956]:loadlibs luavm 2097144 19136 19216
  [2026-07-22 17:09:54.251][CPU1][LTOS/N][000000030.956]:loadlibs sys   224464 29736 29736
  [2026-07-22 17:09:54.253][CPU1][LTOS/N][000000030.956]:loadlibs psram 6291456 34832 52960
  [2026-07-22 17:09:54.255][CPU1][LTOS/N][000000030.973]:I/user.main wdt_DEMO 001.999.000
  [2026-07-22 17:09:54.257][CPU1][LTOS/N][000000030.979]:I/user.wdt 硬件看门狗已由底层固件启用
  [2026-07-22 17:09:54.260][CPU1][LTOS/N][000000030.980]:reset reason: WDT
  [2026-07-22 17:09:54.262][CPU1][LTOS/N][000000030.980]:I/user.reset_reason 重启原因1: 0 原因2: 0 原因3: 8
  ```

 6、关于重启时间的说明：

   实际重启时间不是精确的20秒，主要原因包括：

   硬件处理时间：从看门狗超时到实际硬件复位需要一定的处理时间

   系统状态保存：在复位前系统需要保存必要的状态信息和日志便于分析


 7、关于重启原因值的验证：

   根据[pm.lastReson()函数的返回值说明](https://docs.openluat.com/osapi/core/pm/#45-pmlastreson)确认重启的原因3: 8 是内部看门狗触发的重启。

8、AirLink UART/SPI 模式看门狗演示模块

- 开启喂狗，并进行第一次喂狗操作（默认每 150 秒喂狗一次）

  ```
  [2026-07-23 01:25:51.970][CPU1][LTOS/N][000000005.864]:I/user.exairlinkwdt 命令发送成功: WDT:OPEN
  [2026-07-23 01:25:51.975][CPU1][LTOS/N][000000005.865]:I/user.exairlinkwdt 命令发送成功: WDT:FEED
  [2026-07-23 01:25:52.001][CPU1][LTOS/N][000000005.866]:I/user.exairlinkwdt 喂狗定时器启动，周期: 150000 ms
  [2026-07-23 01:25:52.005][CPU1][LTOS/N][000000005.866]:I/user.exairlinkwdt 看门狗初始化成功，管脚: 6 常态电平: 0
  [2026-07-23 01:25:52.008][CPU1][LTOS/N][000000005.866]:I/user.main 看门狗启动成功
  ```

- 从机收到开启命令后开启/重置等待喂狗超时定时器

  ```
  [2026-07-23 01:25:51.986][000000008.197] I/user.exairlinkwdt TO_RESET 管脚配置成功，管脚: 27 常态电平: 0
  [2026-07-23 01:25:51.988][000000008.198] I/user.exairlinkwdt 等待喂狗超时定时器启动，超时时长: 240000 ms
  [2026-07-23 01:25:51.993][000000008.199] I/user.收到AIRLINK_SDATA!! WDT:OPEN
  [2026-07-23 01:25:51.995][000000008.200] I/user.exairlinkwdt 收到喂狗命令，重置等待喂狗超时定时器
  [2026-07-23 01:25:52.000][000000008.200] I/user.exairlinkwdt 等待喂狗超时定时器已停止
  [2026-07-23 01:25:52.011][000000008.201] I/user.exairlinkwdt 等待喂狗超时定时器启动，超时时长: 240000 ms
  [2026-07-23 01:25:52.024][000000008.201] I/user.收到AIRLINK_SDATA!! WDT:FEED
  [2026-07-23 01:25:52.028][000000008.205] I/user.收到AIRLINK_SDATA!! Air8101 Thu Jan  1 08:00:05 1970
  ```

- 从机的等待喂狗超时定时器超时时间达到后，会复位 8101

  ```
  [2026-07-23 01:29:51.978][000000248.196] W/user.exairlinkwdt 等待喂狗超时，触发硬件复位
  [2026-07-23 01:29:51.985][000000248.197] W/user.exairlinkwdt TO_RESET 管脚输出复位电平: 1
  [2026-07-23 01:29:52.087][000000248.297] I/user.exairlinkwdt TO_RESET 管脚恢复常态电平: 0
  ```

- 8101 被从机硬件复位

  ```
  [2026-07-23 01:29:51.421][CPU1][LTOS/N][000000245.312]:I/user.ticks 245196 BK7258 Air8101 A10
  [2026-07-23 01:29:51.424][CPU1][LTOS/N][000000245.312]:统计信息 收发总包 278 278 0 0
  [2026-07-23 01:29:51.428][CPU1][LTOS/N][000000245.312]:统计信息 发送IP包 104 104 0 0
  [2026-07-23 01:29:51.431][CPU1][LTOS/N][000000245.312]:统计信息 发送IP字节 7262 7262 0 0
  [2026-07-23 01:29:51.434][CPU1][LTOS/N][000000245.312]:统计信息 接收IP包 31 31 0 0
  [2026-07-23 01:29:51.438][CPU1][LTOS/N][000000245.312]:统计信息 接收IP字节 16350 16350 0 0
  [2026-07-23 01:29:51.443][CPU1][LTOS/N][000000245.312]:统计信息 等待从机 0
  [2026-07-23 01:29:51.447][CPU1][LTOS/N][000000245.312]:统计信息 Task超时事件 0
  [2026-07-23 01:29:51.451][CPU1][LTOS/N][000000245.312]:统计信息 Task新数据事件 352
  [2026-07-23 01:29:51.454][CPU1][LTOS/N][000000245.313]:I/user.发送数据给对端设备 Air8101 Thu Jan  1 08:04:05 1970 当前airlink状态 true
  [2026-07-23 01:29:51.963][CPU2][LTOS/N][000000245.855]:dns all done ,now stop
  [2026-07-23 01:29:51.967][CPU2][LTOS/N][000000245.855]:adatper 15 dns server 0.0.0.0
  [2026-07-23 01:29:52.134][CPU0][CAPP/N][000000000.000]:ENV start address is 0x007FA000, size is 8192 bytes.
  [2026-07-23 01:29:52.138][CPU0][CAPP/N][000000000.000]:EasyFlash V4.1.0 is initialize success.
  [2026-07-23 01:29:52.141][CPU0][CAPP/N][000000000.002]:driver_init: psram init ok
  [2026-07-23 01:29:52.144][CPU0][CAPP/N][000000000.002]:uncali sdmadc value:[0 0]
  [2026-07-23 01:29:52.147][CPU0][LTOS/N][000000000.004]:rwnx_cal_set_rfconfig(0x102) phy on; rf off
  [2026-07-23 01:29:52.152][CPU0][CAPP/N][000000000.010]:temp in otp is:582
  [2026-07-23 01:29:52.243][CPU0][CAPP/N][000000000.108]:load polar tab magic code error 0xffffffff
  [2026-07-23 01:29:52.247][CPU0][LTOS/N][000000000.108]:xtal_cali:76
  [2026-07-23 01:29:52.251][CPU0][CAPP/N][000000000.108]:idx:40=40+(0),r:54,xtal:76,pwr_gain:a8ab7128
  [2026-07-23 01:29:52.253][CPU0][CAPP/N][000000000.110]:wifi inited(1) ret(0)
  [2026-07-23 01:29:52.257][CPU0][CAPP/N][000000000.111]:sync_base_mac_record, saved records is more than 1, free index(3).
  [2026-07-23 01:29:52.604][CPU2][CAPP/N][000000000.472]:ENV start address is 0x007FC000, size is 8192 bytes.
  [2026-07-23 01:29:52.696][CPU1][CAPP/N][000000000.564]:EasyFlash V4.1.0 is initialize success.
  [2026-07-23 01:29:52.701][CPU2][CAPP/N][000000000.567]:wdrv_tx_cmd_buffer_init, addr[0]=0x28012e14, pattern_addr=0x28012e10
  [2026-07-23 01:29:52.704][CPU2][CAPP/N][000000000.567]:wdrv_tx_cmd_buffer_init, addr[1]=0x28013134, pattern_addr=0x28013130
  [2026-07-23 01:29:52.707][CPU2][CAPP/N][000000000.568]:wdrv_tx_cmd_buffer_init, addr[2]=0x28013454, pattern_addr=0x28013450
  [2026-07-23 01:29:52.710][CPU0][CAPP/N][000000000.569]:cif_handle_bk_cmd_lwipmem_addr_req,665,addr:0x2806c400
  [2026-07-23 01:29:52.728][CPU1][LTOS/N][000000000.595]:reset native reason: 0
  [2026-07-23 01:29:52.731][CPU1][LTOS/N][000000000.596]:boot up by power on
  [2026-07-23 01:29:52.734][CPU1][LTOS/N][000000000.596]:poweron reason 0
  [2026-07-23 01:29:52.763][CPU2][LTOS/N][000000000.597]:STA MAC: C8C2C68CD586
  [2026-07-23 01:29:52.766][CPU2][LTOS/N][000000000.598]:AP  MAC: C8C2C68CD587
  [2026-07-23 01:29:52.770][CPU1][CAPP/N][000000000.598]:sync_base_mac_record, saved records is more than 1, free index(3).
  [2026-07-23 01:29:52.773][CPU1][LTOS/N][000000000.599]:BLE MAC: C8C2C68CD588
  [2026-07-23 01:29:52.778][CPU1][LTOS/N][000000000.599]:UID: 54540D2043
  [2026-07-23 01:29:52.783][CPU2][LTOS/N][000000000.601]:LuatOS@Air8101 base 26.04 bsp V2018 64bit
  [2026-07-23 01:29:52.786][CPU2][LTOS/N][000000000.601]:ROM Build: Jul  7 2026 14:14:30
  [2026-07-23 01:29:52.900][CPU1][LTOS/N][000000000.759]:/luadb/pins_air8101.json not exist!!
  [2026-07-23 01:29:52.907][CPU1][LTOS/N][000000000.762]:loadlibs luavm 2097144 19136 19216
  [2026-07-23 01:29:52.911][CPU1][LTOS/N][000000000.762]:loadlibs sys   224464 29736 29736
  [2026-07-23 01:29:52.916][CPU1][LTOS/N][000000000.762]:loadlibs psram 6291456 133904 151792
  [2026-07-23 01:29:52.919][CPU1][LTOS/N][000000000.778]:I/user.main wdt_DEMO 001.999.000
  [2026-07-23 01:29:52.946][CPU1][LTOS/N][000000000.805]:D/user.dnsproxy version -> 202607100900
  [2026-07-23 01:29:52.950][CPU1][LTOS/N][000000000.823]:D/user.udpsrv version -> 202607021200
  [2026-07-23 01:29:52.953][CPU1][LTOS/N][000000000.826]:D/user.dhcpsrv version -> 202607021200
  [2026-07-23 01:29:52.978][CPU1][LTOS/N][000000000.836]:D/user.httpdns version -> 202607021200
  [2026-07-23 01:29:52.981][CPU1][LTOS/N][000000000.840]:D/user.exnetif version -> 202607161200
  [2026-07-23 01:29:52.984][CPU1][LTOS/N][000000000.852]:D/user.exairlinkwdt version -> 202607190000
  ```

9、外部看门狗演示（待补充）