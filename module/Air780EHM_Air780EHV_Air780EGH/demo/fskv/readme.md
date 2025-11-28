## 功能模块介绍：

1. main.lua：主程序入口

2. fskv_test.lua：演示fskv核心库API的用法，详细逻辑请看fskv_test.lua 文件

## 演示功能概述：

### fskv_test.lua：

1.初始化fskv

2.获取 kv 数据库状态

3.设置不同类型的kv数据

4.设置 table 内的键值对数据

5.根据 key 获取对应的数据

6.使用kv迭代器遍历kv数据

7.删除kv数据，清空KV数据

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EHV.jpg)



1. 合宙 Air780EHM/EHV/EGH 核心板一块

2. TYPE-C USB 数据线一根 ，Air780EHM/EHV/EGH 核心板和数据线的硬件接线方式为：
- Air780EHM/EHV/EGH核心板通过 TYPE-C USB 口供电；（USB的拨码开关off/on,拨到on）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境：

1. Luatools 下载调试工具

2. Air780EHM固件版本：LuatOS-SoC_V2016_Air780EHM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780ehm/luatos/firmware/](https://docs.openluat.com/air780ehm/luatos/firmware/version/)
   
   Air780EHV固件版本：LuatOS-SoC_V2016_Air780EHV_1，固件地址，如有最新固件请用最新
   
    [https://docs.openluat.com/air780ehv/luatos/firmware/](https://docs.openluat.com/air780ehv/luatos/firmware/version/)
   
   Air780EGH固件版本：LuatOS-SoC_V2016_Air780EGH_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780egh/luatos/firmware/](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. Luatools 烧录内核固件和 脚本文件

3. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，设置kv数据、设置 table 内的键值对数据，用kv迭代器遍历kv数据，删除kv数据等。

4. 如下 log 显示：

```bash
[2025-11-21 17:18:37.104][000000000.372] I/user.main fskv_demo 001.000.000
[2025-11-21 17:18:37.111][000000000.379] I/lfs sfd_lfs mount ret -84, exec auto-format
[2025-11-21 17:18:37.120][000000000.551] D/lfs init ok
[2025-11-21 17:18:37.135][000000000.552] I/user.fskv init complete true
[2025-11-21 17:18:37.149][000000000.552] I/user.获取kv数据库状态 fskv kv 8192 65536 0
[2025-11-21 17:18:37.156][000000000.553] I/user.fskv设置用户数据是字符串 true
[2025-11-21 17:18:37.167][000000000.554] I/user.fskv设置用户数据是布尔值 true
[2025-11-21 17:18:37.177][000000000.555] I/user.fskv设置用户数据是数值 true
[2025-11-21 17:18:37.187][000000000.557] I/user.fskv设置用户数据是整数 true
[2025-11-21 17:18:37.196][000000000.558] I/user.fskv用户数据是table类型 true
[2025-11-21 17:18:37.210][000000000.560] I/user.mytable设置用户数据是字符串 true
[2025-11-21 17:18:37.218][000000000.563] I/user.mytable设置用户数据是布尔值 true
[2025-11-21 17:18:37.225][000000000.566] I/user.mytable设置用户数据是数值 true
[2025-11-21 17:18:37.234][000000000.569] I/user.mytable设置用户数据是table true
[2025-11-21 17:18:37.247][000000000.571] I/user.获取my_str的类型和值 string goodgoodstudy
[2025-11-21 17:18:37.263][000000000.573] I/user.获取upgrade的类型和值 boolean true
[2025-11-21 17:18:37.273][000000000.574] I/user.获取my_number的类型和值 number 1.230000
[2025-11-21 17:18:37.283][000000000.576] I/user.获取my_int的类型和值 number 5
[2025-11-21 17:18:37.290][000000000.578] I/user.获取my_table的类型和值 table: 0C7F59D0 {"name":"wendal","age":18}
[2025-11-21 17:18:37.303][000000000.580] I/user.获取mytable的类型和值 table: 0C7F5858 {"bigd":{"name":"wendal","age":123},"wendal":"goodgoodstudy","timer":1,"upgrade":true}
[2025-11-21 17:18:37.309][000000000.580] I/user.kv数据库迭代器 userdata: 0C7F5670
[2025-11-21 17:18:37.317][000000000.583] I/user.kv迭代器获取下一个key my_bool
[2025-11-21 17:18:37.322][000000000.585] I/user.fskv my_bool value true
[2025-11-21 17:18:37.333][000000000.587] I/user.kv迭代器获取下一个key my_int
[2025-11-21 17:18:37.352][000000000.588] I/user.fskv my_int value 5
[2025-11-21 17:18:37.366][000000000.591] I/user.kv迭代器获取下一个key my_number
[2025-11-21 17:18:37.375][000000000.593] I/user.fskv my_number value 1.230000
[2025-11-21 17:18:37.387][000000000.595] I/user.kv迭代器获取下一个key my_str
[2025-11-21 17:18:37.399][000000000.597] I/user.fskv my_str value goodgoodstudy
[2025-11-21 17:18:37.407][000000000.599] I/user.kv迭代器获取下一个key my_table
[2025-11-21 17:18:37.418][000000000.601] I/user.fskv my_table value table: 0C7F5538
[2025-11-21 17:18:37.437][000000000.603] I/user.kv迭代器获取下一个key mytable
[2025-11-21 17:18:37.460][000000000.606] I/user.fskv mytable value table: 0C7F5420
[2025-11-21 17:18:37.473][000000000.608] I/user.kv迭代器获取下一个key nil
[2025-11-21 17:18:37.484][000000000.608] I/user.kv数据库遍历完成
[2025-11-21 17:18:37.501][000000000.653] I/user.fskv my_bool删除结果 true
[2025-11-21 17:18:37.515][000000000.654] I/user.fskv 删除后查询my_bool nil nil
[2025-11-21 17:18:37.528][000000000.655] I/user.设置新的table，key是mytable2 true
[2025-11-21 17:18:37.539][000000000.659] I/user.mytable2的值 table: 0C7F51E0 {"age":18,"name":"wendal"}
[2025-11-21 17:18:37.558][000000000.662] I/user.mytable2删除name测试 true
[2025-11-21 17:18:37.567][000000000.664] I/user.mytable2删除结果 table: 0C7F4FF8 {"age":18}
[2025-11-21 17:18:37.580][000000000.738] I/user.清空整个kv数据库 true
[2025-11-21 17:18:37.592][000000000.739] I/user.获取kv数据库状态 fskv kv 8192 65536 0

```
