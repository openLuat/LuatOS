# wdt_DEMO 项目说明

## 项目概述
本项目是基于 Air1601开发板，演示了两种看门狗(WDT)功能的使用。

- 内部看门狗 - 使用芯片内置的硬件看门狗

- 外部看门狗 - 使用 Air153C 外置看门狗芯片

## 功能说明

内部看门狗演示

 - 自动启用：硬件看门狗由底层固件自动启用，超时时间20秒

 - 定期喂狗：每3秒执行一次喂狗操作，确保系统正常运行

 - 故障模拟：可模拟系统死锁导致无法喂狗的场景

 - 自动恢复：看门狗超时后自动重启系统

外部看门狗演示 (Air153C)

 - 引脚控制：通过GPIO引脚28控制外部看门狗芯片

 - 定期喂狗：每10秒执行一次喂狗操作

 - 故障模拟：可模拟程序异常停止喂狗的场景

 - 硬件复位：外部看门狗超时后通过硬件复位系统

## 演示硬件环境

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## 演示软件环境

在开始实践本示例之前，先筹备一下软件环境：

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1012_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.luatos 需要的脚本和资源文件

- 脚本和资源文件[点击此处查看与下载](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/wdt)

- lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

4.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板 中。

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
   6、关于重启时间的说明：
  
   实际重启时间不是精确的20秒，主要原因包括：
  
   硬件处理时间：从看门狗超时到实际硬件复位需要一定的处理时间
  
   系统状态保存：在复位前系统需要保存必要的状态信息和日志便于分析


 7、关于重启原因值的验证：

   根据[pm.lastReson()函数的返回值说明](https://docs.openluat.com/osapi/core/pm/#45-pmlastreson)确认重启的原因3: 8 是内部看门狗触发的重启。

8、外部看门狗演示（待补充）