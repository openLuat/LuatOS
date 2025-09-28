
## 功能模块介绍

1、main.lua：主程序入口；

2、talk.lua：airtalk 运行主程序

## 常量的介绍

1. extalk.START = 1     -- 通话开始
2. extalk.STOP = 2      -- 通话结束
3. extalk.UNRESPONSIVE = 3  -- 对端未响应
4. extalk.ONE_ON_ONE = 5  -- 一对一来电
5. extalk.BROADCAST = 6 -- 广播


## 演示功能概述

1.    按一次boot，选择群组内第一个联系人，开始1对1对讲，再按一次boot，结束对讲
2.    按一次powerkey，开始1对多广播，再按一次powerkey或者boot，结束对讲

## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块

2、喇叭一个

2、插入喇叭到开发板中


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2014版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）


## 演示核心步骤

1、搭建好硬件环境

2、创建群组：详情请见：https://docs.openluat.com/value/airtalk/

3、选择本demo 的全部文件(可不包含readme)

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，自动开机运行，如果出现以下日志

``` lua
I/user. 联系人列表更新
```

6、 点击BOOT 按键，会选择联系人列表第一个人，进行一对一对讲，当对面收到对讲，将亮起灯

7、 点击POWERKEY按键，会进行广播，所有群组内的人，都会收到对讲消息，并亮起灯


