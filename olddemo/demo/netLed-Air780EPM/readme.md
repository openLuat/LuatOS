## 功能模块介绍：

1、main.lua：主程序入口；

2、Lte_test.lua：功能演示核心脚本，lte 指示灯的亮灭演示,在main.lua中加载运行。

3、Led_test.lua：功能演示核心脚本，led 网络灯的亮灭演示,在main.lua中加载运行。

## 演示功能概述：

#### Lte_test.lua：

核心逻辑：

1.初始化LTE,打开LTE指示灯功能；

2.LTE灯状态模拟，通过sys.publish("LTE_LED_UPDATE", 状态)：手动模拟状态触发，控制 LTE 灯的亮灭状态

3.关闭常规LTE灯功能（避免冲突）,演示呼吸灯效果

#### Led_test.lua：

核心逻辑:

1.自定义LED灯不同状态的闪烁时间

2.初始化LED,打开LED网络灯功能；

3.LED灯状态模拟，通过sys.publish("工作状态", 状态)：手动模拟状态触发，控制 LED灯的亮灭状态

4.关闭常规LED灯功能（避免冲突）,演示呼吸灯效果





工作状态说明，优先级顺序(1-5表示从高到低），高优先级状态会直接覆盖低优先级状态

1. "FLYMODE"     飞行模式

2. "SIMERR"      未检测到SIM卡或者SIM卡锁pin码等SIM卡异常

3. "SCK"         socket已连接上后台

4. "GPRS"        已附着GPRS数据网络

5. "IDLE"        未注册GPRS网络
   "NULL":功能关闭状态
   
   

各种工作状态下配置的点亮、熄灭时长(单位毫秒)，默认值:

NULL = { 0, 0xFFFF }, --常灭

FLYMODE = { 0, 0xFFFF }, --常灭

SIMERR = { 300, 5700 }, --亮300毫秒,灭5700毫秒

IDLE = { 300, 3700 }, --亮300毫秒,灭3700毫秒

GPRS = { 300, 700 },  --亮300毫秒,灭700毫秒

SCK = { 100, 100 },   --亮100毫秒,灭100毫秒



## 演示硬件环境



![](https://docs.openluat.com/air780epm/luatos/app/socket/ftp/image/Df0ZbzlUHonW3IxFO9dcCjcFnLy.jpeg)

1、Air780EPM 1.3 版本开发板一块 + 可上网的 sim 卡一张 +4g 天线一根 + 网线一根：

* sim 卡插入开发板的 sim 卡槽

* 天线装到开发板上

* 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根，Air780EPM 开发板和数据线的硬件接线方式为：

* Air780EPM 开发板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

* TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

3、Air780EPM 开发板购买链接：https://item.taobao.com/item.htm?id=871567339387&scene=taobao_shop&skuId=5914252858584&spm=a1z10.1-c-s.w4024-24640132990.1.614a1170fDHCdo

### 

## 演示软件环境

1、 Luatools下载调试工具

2、 固件版本：LuatOS-SoC_V2016_Air780EPM_1.soc，固件地址，如有最新固件请用最新 [固件版本 - luatos@air780epm - 合宙模组资料中心](https://docs.openluat.com/air780epm/luatos/firmware/version/)](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、 脚本文件：
   main.lua   

   Lte_test.lua

   Led_test.lua

4、 pc 系统 win11（win10 及以上）



## 演示核心步骤

1、搭建好硬件环境

2、Lte_test.lua和Led_test.lua文件中修改自己用到的网络灯的GPIO编号，脚本中使用GPIO 27,是Air780EPM ,1.3版本开发板的NET灯控制脚,其他管脚按自己的硬件设计修改。

3、main.lua中加载Lte_test.lua和Led_test.lua文件之一。

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，相关灯会按设定的时长亮灭显示，打印如下log：

Lte_test.lua

```
[2025-10-22 14:44:57.803][000000000.216] I/user.main netLed_demo 001.000.000
[2025-10-22 14:44:57.809][000000000.233] I/user.LTE灯状态 常灭
[2025-10-22 14:44:58.021][000000000.713] I/user.netLed.setState true NULL nil false nil nil
[2025-10-22 14:44:58.040][000000000.714] I/user.sim status RDY
[2025-10-22 14:44:58.053][000000000.895] I/user.sim status GET_NUMBER
[2025-10-22 14:44:59.291][000000002.198] D/mobile cid1, state0
[2025-10-22 14:44:59.293][000000002.199] D/mobile bearer act 0, result 0
[2025-10-22 14:44:59.297][000000002.200] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-22 14:44:59.299][000000002.200] I/user.netLed.setState true IDLE nil false 1 nil
[2025-10-22 14:44:59.302][000000002.201] I/user.mobile IP_READY 10.215.50.235 true
[2025-10-22 14:44:59.306][000000002.230] D/mobile TIME_SYNC 0
[2025-10-22 14:45:00.287][000000003.233] I/user.LTE灯状态 常亮
[2025-10-22 14:45:03.280][000000006.233] I/user.LTE灯状态 慢速闪烁（500ms亮/500ms灭）
[2025-10-22 14:45:08.279][000000011.234] I/user.LTE灯状态 快速闪烁（100ms亮/100ms灭）
[2025-10-22 14:45:10.286][000000013.234] I/user.LTE灯状态 呼吸灯效果

```

Led_test.lua

```
[2025-10-22 17:06:32.664][000000000.217] I/user.main netLed_demo 001.000.000
[2025-10-22 17:06:32.670][000000000.234] I/user.LED状态 未注册网络(IDLE):500ms亮/2500ms灭
[2025-10-22 17:06:32.686][000000000.239] I/user.netLed.setState true NULL false nil nil nil
[2025-10-22 17:06:32.703][000000000.239] I/user.netLed.setState true IDLE false false nil nil
[2025-10-22 17:06:32.716][000000000.240] I/user.sim status RDY
[2025-10-22 17:06:32.726][000000000.240] I/user.mobile IP_LOSE false
[2025-10-22 17:06:32.741][000000000.240] I/user.netLed.setState true IDLE false false nil false
[2025-10-22 17:06:33.038][000000000.715] I/user.sim status RDY
[2025-10-22 17:06:33.047][000000000.850] I/user.sim status GET_NUMBER
[2025-10-22 17:06:33.651][000000001.739] D/mobile cid1, state0
[2025-10-22 17:06:33.658][000000001.740] D/mobile bearer act 0, result 0
[2025-10-22 17:06:33.676][000000001.741] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-22 17:06:33.685][000000001.742] I/user.netLed.setState true IDLE false false 1 false
[2025-10-22 17:06:33.698][000000001.742] I/user.mobile IP_READY 10.83.147.139 true
[2025-10-22 17:06:33.707][000000001.798] D/mobile TIME_SYNC 0
[2025-10-22 17:06:44.011][000000012.235] I/user.LED状态 SIM卡错误(SIMERR):300ms亮/1700ms灭
[2025-10-22 17:06:44.014][000000012.236] I/user.netLed.setState true GPRS false true 1 false
[2025-10-22 17:06:44.017][000000012.236] I/user.sim status ERROR
[2025-10-22 17:06:52.013][000000020.235] I/user.LED状态 已附着GPRS:200ms亮/200ms灭(中速闪）
[2025-10-22 17:06:52.018][000000020.236] I/user.netLed.setState true SIMERR false false 1 false
[2025-10-22 17:06:52.022][000000020.236] I/user.sim status RDY
[2025-10-22 17:06:52.030][000000020.236] I/user.netLed.setState true GPRS false false true false
[2025-10-22 17:06:52.033][000000020.237] I/user.mobile IP_READY 192.168.1.1 false
[2025-10-22 17:07:00.017][000000028.234] I/user.LED状态 Socket连接(SCK):100ms亮/50ms灭(快速闪）
[2025-10-22 17:07:00.027][000000028.235] I/user.netLed.setState true GPRS false false true true
[2025-10-22 17:07:06.006][000000034.234] I/user.LED状态 飞行模式(FLYMODE):常灭
[2025-10-22 17:07:06.011][000000034.235] I/user.netLed.setState true SCK true false true true
[2025-10-22 17:07:11.006][000000039.234] I/user.LED状态 呼吸灯模式:平滑渐变亮灭


```
