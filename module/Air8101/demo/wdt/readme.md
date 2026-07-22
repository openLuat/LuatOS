# wdt_DEMO 项目说明

## 项目概述
本项目是基于 Air8101，演示了两种看门狗(WDT)功能的使用。

- 内部看门狗 - 使用芯片内置的硬件看门狗

- 外部看门狗 - 使用 Air153C 外置看门狗芯片

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

## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/multinetwork/4G/image/LzuBbS3NxoVu34x4dj7c3d04nDb.jpg)

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；

购买链接：[Air8101 核心板 WiFi 4G 以太网 蓝牙 720P显示屏 200万拍照](https://item.taobao.com/item.htm?id=931016598855&skuId=5816546236665&spm=a1z10.5-c-s.w4002-24045920841.10.40627052RK973c)

## 演示软件环境

在开始实践本示例之前，先筹备一下软件环境：

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V2018_Air8101_101.soc](https://docs.openluat.com/air8101/luatos/firmware/#v2018)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.luatos 需要的脚本和资源文件

- 脚本和资源文件[点击此处查看与下载](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/wdt)

- lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

4.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air8101 核心板中](https://docs.openluat.com/air8101/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到 Air8101核心板 中。

## 相关软件资料

wdt 核心库文档：https://docs.openluat.com/osapi/core/wdt/

air153C_wtd 扩展库文档：https://docs.openluat.com/osapi/ext/air153C_wtd/

## 演示核心步骤
1、搭建好硬件环境

2、加载演示脚本文件：

- 在main.lua中有选择的选择以下两个lua文件中的一个

  - require "internal_wdt"  -- 内部看门狗演示模块

  - require "air153c_wdt"    -- 外部看门狗演示模块

- 在internal_wdt.lua或者air153c_wdt.Lua 两个演示脚本中，通过修改 DEMO_MODE 变量选择演示模式

 - local DEMO_MODE = "normal"   -- 正常模式：持续喂狗

 - local DEMO_MODE = "fault"    -- 故障模式：模拟系统故障

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

8、外部看门狗演示（待补充）