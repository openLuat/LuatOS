# wdt_DEMO 项目说明

## 项目概述
本项目是基于 Air780EPM开发板，演示了两种看门狗(WDT)功能的使用。

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
1、Air780EPM开发板
 
![alt text]( https://docs.openLuat.com/cdn/image/Air780EPM开发板.jpg)

2、Air153C配件版（待补充图片和接线图）

3、TYPE-C USB数据线一根
- Air780EPM开发板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；


## 演示软件环境
1、Luatools下载调试工具 [https://docs.openluat.com/air780epm/common/Luatools/]

2、固件版本LuatOS-SoC_V2016_Air780EPM 版本固件。不同版本区别请见 https://docs.openluat.com/air780epm/luatos/firmware/version/

3、lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

4、准备好软件环境之后，接下来查看[如何烧录项目文件到 Air780EPM开发板中](https://docs.openluat.com/air780epm/luatos/common/download/)将本篇文章中演示使用的项目文件烧录到相应的核心板中。

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
   [2025-11-04 15:31:38.907][000000000.263] I/user.main wdt_DEMO 001.000.000
   [2025-11-04 15:31:38.913][000000000.271] I/user.wdt 硬件看门狗已由底层固件启用
   [2025-11-04 15:31:41.459][000000003.272] I/user.wdt 喂狗完成
   [2025-11-04 15:31:43.457][000000005.271] I/user.wdt 故障前最后一次喂狗，成功 = true
   [2025-11-04 15:31:43.464][000000005.272] I/user.fault_task 进入死循环模拟故障
   [2025-11-04 15:31:43.472][000000005.272] I/user.fault_task 看门狗喂狗任务被阻塞，系统将在约20秒后重启
   [2025-11-04 15:32:08.710] 工具提示: 模组已经死机，请不要关闭程序，正在接收必要的信息用于分析
   [2025-11-04 15:32:32.943] 工具提示: diag com USB 断开连接 COM4 CommError,[WinError 22] 设备不识别此命令。
   [2025-11-04 15:32:32.985] 工具提示: 死机信息接收成功，如有需要请将死机信息文件交给FAE分析，文件保存在log\ramdump\2025-11-04_153209_LuatOS-SoC_V2016_Air780EGH_867920073503634_COM4_ramdump.bin
   [2025-11-04 15:32:33.006] 工具提示: 同时把使用的soc固件包或者编译生成的.elf文件交给FAE
   [2025-11-04 15:32:33.022] 工具提示: print com USB 断开连接 COM3 CommError,[WinError 22] 设备不识别此命令。
   [2025-11-04 15:32:33.664] 工具提示: soc log port COM3打开成功
   [2025-11-04 15:32:33.738] 工具提示: ap log port COM4打开成功
   [2025-11-04 15:32:33.751] 工具提示: 用户虚拟串口 COM5
   [2025-11-04 15:32:34.049][000000000.272] I/user.wdt 硬件看门狗已由底层固件启用
   [2025-11-04 15:32:34.054][000000000.272] I/user.reset_reason 重启原因1: 0 原因2: 0 原因3: 8
  ``` 
 6、关于重启时间的说明：

   实际重启时间不是精确的20秒，主要原因包括：

   硬件处理时间：从看门狗超时到实际硬件复位需要一定的处理时间

   系统状态保存：在复位前系统需要保存必要的状态信息和日志便于分析


 7、关于重启原因值的验证：

   根据[pm.lastReson()函数的返回值说明](https://docs.openluat.com/osapi/core/pm/#45-pmlastreson)确认重启的原因3: 8 是内部看门狗触发的重启。

8、外部看门狗演示（待补充）