## Air8201 airtalk demo 说明

> 本目录为 **Air8201**（兼容 Air8201G/Air8201H）的 airtalk demo。

## 功能模块介绍

1、main.lua：程序入口，初始化 AirTalk 对讲系统

2、talk.lua：airtalk 对讲业务核心模块

3、audio_drv：音频设备初始化与控制

## 常量的介绍

1. extalk.START            -- 通话开始

2. extalk.STOP             -- 通话结束

3. extalk.UNRESPONSIVE     -- 对端未响应

4. extalk.ONE_ON_ONE       -- 一对一来电

5. extalk.BROADCAST        -- 广播

## 演示功能概述

1、talk.lua 实现AirTalk对讲核心业务。

- 包括群组内联系人列表信息显示、对讲状态监控、音频设备控制等功能，实时显示对讲状态和设备信息。

- 按键处理：

 （1）主动发起对讲：按一次Boot/Wakeup键选择指定设备，开始1对1对讲，再按一次Boot/Wakeup键或powerkey键结束对讲；按一次powerkey键开始一对多广播，再按一次Boot/Wakeup键或powerkey键结束广播。

 （2）被动接听对讲：当其他设备呼叫本机时，自动接听对讲；按任意键（Boot/Wakeup或Power键）即可结束当前对讲。

 注意按键引脚因硬件版本不同：
 - Air8201G：BTB扩展板使用 WAKEUP0 + PWRKEY
 - Air8201H：板载使用 BOOT(GPIO0) + PWRKEY
 - 请在 talk.lua 中修改 HW 变量（"G" 或 "H"）选择对应硬件版本

3、audio_drv：定义所有硬件引脚常量，使用exaudio扩展库初始化音频设备。pa_ctrl 引脚：Air8201G 使用 25，Air8201H 使用 23。

2、main.lua 启动AirTalk对讲服务。

## 演示硬件环境

Air8201 整机板 + 喇叭

- 具备volte功能的电话卡插入开发板的sim卡槽

- TYPE-C USB数据线一根

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/) 

2、[Air8201G固件(基于Air780EGH)](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3、[Air8201H固件(基于Air780EHM)](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)

4、lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

1、搭建好硬件环境

2、创建群组：详情请见：[Airtalk](https://docs.openluat.com/value/airtalk/)  第 5.2 章节--创建群组

3、main.lua 中，修改 PRODUCT_KEY 。
``` lua
--到 iot.openluat.com 创建项目，获取正确的项目key
PRODUCT_KEY =  "123"
```

4、talk.lua 中，修改目标设备终端ID。
``` lua
-- 目标设备终端ID，修改为你想要对讲的终端ID
TARGET_DEVICE_ID = "78122397"  -- 请替换为实际的目标设备终端ID
```

5、audio_drv.lua 中，根据硬件版本修改 pa_ctrl 引脚（Air8201G=25，Air8201H=23）。

6、talk.lua 中，根据硬件版本修改 HW 变量（"G" 或 "H"），以匹配正确的按键引脚。

7、Luatools烧录内核固件和修改后的demo脚本代码

8、烧录成功后，自动开机运行，在 luatools 查看日志。
