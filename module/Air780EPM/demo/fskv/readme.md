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

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EPM.jpg)



1. 合宙 Air780EPM 核心板一块

2. TYPE-C USB 数据线一根 ，Air780EPM 核心板和数据线的硬件接线方式为：
- Air780EPM 核心板通过 TYPE-C USB 口供电；（USB的拨码开关off/on,拨到on）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V2018_Air780EPM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/Air780EPM/luatos/firmware/](https://docs.openluat.com/air780epm/luatos/firmware/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. Luatools 烧录内核固件和 脚本文件

3. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，设置kv数据、设置 table 内的键值对数据，用kv迭代器遍历kv数据，删除kv数据等。

4. 如下 log 显示：

```bash
[2025-11-21 17:37:24.554][000000000.319] I/user.main Air780EPM_fskv 001.000.000
[2025-11-21 17:37:24.581][000000000.327] I/lfs sfd_lfs mount ret -84, exec auto-format
[2025-11-21 17:37:24.607][000000000.482] D/lfs init ok
[2025-11-21 17:37:24.649][000000000.482] I/user.fskv init complete true
[2025-11-21 17:37:24.681][000000000.483] I/user.获取kv数据库状态 fskv kv 8192 65536 0
[2025-11-21 17:37:24.733][000000000.484] I/user.fskv设置用户数据是字符串 true
[2025-11-21 17:37:24.773][000000000.485] I/user.fskv设置用户数据是布尔值 true
[2025-11-21 17:37:24.822][000000000.487] I/user.fskv设置用户数据是数值 true
[2025-11-21 17:37:24.854][000000000.488] I/user.fskv设置用户数据是整数 true
[2025-11-21 17:37:24.884][000000000.489] I/user.fskv用户数据是table类型 true
[2025-11-21 17:37:24.922][000000000.492] I/user.mytable设置用户数据是字符串 true
[2025-11-21 17:37:24.957][000000000.494] I/user.mytable设置用户数据是布尔值 true
[2025-11-21 17:37:24.996][000000000.497] I/user.mytable设置用户数据是数值 true
[2025-11-21 17:37:25.034][000000000.500] I/user.mytable设置用户数据是table true
[2025-11-21 17:37:25.068][000000000.502] I/user.获取my_str的类型和值 string goodgoodstudy
[2025-11-21 17:37:25.097][000000000.503] I/user.获取upgrade的类型和值 boolean true
[2025-11-21 17:37:25.128][000000000.505] I/user.获取my_number的类型和值 number 1.230000
[2025-11-21 17:37:25.160][000000000.507] I/user.获取my_int的类型和值 number 5
[2025-11-21 17:37:25.192][000000000.508] I/user.获取my_table的类型和值 table: 0C1A7D70 {"name":"wendal","age":18}
[2025-11-21 17:37:25.218][000000000.510] I/user.获取mytable的类型和值 table: 0C1A7BF8 {"bigd":{"name":"wendal","age":123},"wendal":"goodgoodstudy","timer":1,"upgrade":true}
[2025-11-21 17:37:25.245][000000000.510] I/user.kv数据库迭代器 userdata: 0C1A7A10
[2025-11-21 17:37:25.266][000000000.513] I/user.kv迭代器获取下一个key my_bool
[2025-11-21 17:37:25.287][000000000.515] I/user.fskv my_bool value true
[2025-11-21 17:37:25.312][000000000.517] I/user.kv迭代器获取下一个key my_int
[2025-11-21 17:37:25.342][000000000.519] I/user.fskv my_int value 5
[2025-11-21 17:37:25.363][000000000.521] I/user.kv迭代器获取下一个key my_number
[2025-11-21 17:37:25.380][000000000.523] I/user.fskv my_number value 1.230000
[2025-11-21 17:37:25.396][000000000.525] I/user.kv迭代器获取下一个key my_str
[2025-11-21 17:37:25.417][000000000.527] I/user.fskv my_str value goodgoodstudy
[2025-11-21 17:37:25.438][000000000.529] I/user.kv迭代器获取下一个key my_table
[2025-11-21 17:37:25.463][000000000.531] I/user.fskv my_table value table: 0C1A78D8
[2025-11-21 17:37:25.485][000000000.533] I/user.kv迭代器获取下一个key mytable
[2025-11-21 17:37:25.504][000000000.535] I/user.fskv mytable value table: 0C1A77C0
[2025-11-21 17:37:25.530][000000000.536] I/user.kv迭代器获取下一个key nil
[2025-11-21 17:37:25.553][000000000.537] I/user.kv数据库遍历完成
[2025-11-21 17:37:25.565][000000000.573] I/user.fskv my_bool删除结果 true
[2025-11-21 17:37:25.578][000000000.574] I/user.fskv 删除后查询my_bool nil nil
[2025-11-21 17:37:25.591][000000000.575] I/user.设置新的table，key是mytable2 true
[2025-11-21 17:37:25.607][000000000.578] I/user.mytable2的值 table: 0C1A7580 {"age":18,"name":"wendal"}
[2025-11-21 17:37:25.630][000000000.580] I/user.mytable2删除name测试 true
[2025-11-21 17:37:25.651][000000000.583] I/user.mytable2删除结果 table: 0C1A7398 {"age":18}
[2025-11-21 17:37:25.670][000000000.643] I/user.清空整个kv数据库 true
[2025-11-21 17:37:25.694][000000000.643] I/user.获取kv数据库状态 fskv kv 8192 65536 0
[2025-11-21 17:37:28.866][000000005.695] D/mobile cid1, state0
[2025-11-21 17:37:28.888][000000005.696] D/mobile bearer act 0, result 0
[2025-11-21 17:37:28.896][000000005.696] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-21 17:37:28.906][000000005.738] D/mobile TIME_SYNC 0

```
