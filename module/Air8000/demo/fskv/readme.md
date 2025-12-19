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

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/80001.jpg)

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/80002.jpg)

1. 合宙 Air8000 核心板一块

2. TYPE-C USB 数据线一根 ，Air8000 核心板和数据线的硬件接线方式为：
- Air8000 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V2018_Air8000_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8000/luatos/firmware/](https://docs.openluat.com/air8000/luatos/firmware/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. Luatools 烧录内核固件和 脚本文件

3. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，设置kv数据、设置 table 内的键值对数据，用kv迭代器遍历kv数据，删除kv数据等。

4. 如下 log 显示：

```bash
[2025-11-14 16:37:13.043][000000000.379] I/user.main Air8000_fskv 001.000.000
[2025-11-14 16:37:13.058][000000000.396] D/lfs init ok
[2025-11-14 16:37:13.069][000000000.396] I/user.fskv init complete true
[2025-11-14 16:37:13.083][000000000.397] I/user.获取kv数据库状态 fskv kv 8192 65536 0
[2025-11-14 16:37:13.097][000000000.431] I/user.fskv设置用户数据是字符串 true
[2025-11-14 16:37:13.108][000000000.432] I/user.fskv设置用户数据是布尔值 true
[2025-11-14 16:37:13.119][000000000.434] I/user.fskv设置用户数据是数值 true
[2025-11-14 16:37:13.141][000000000.435] I/user.fskv设置用户数据是整数 true
[2025-11-14 16:37:13.158][000000000.437] I/user.fskv用户数据是table类型 true
[2025-11-14 16:37:13.182][000000000.440] I/user.mytable设置用户数据是字符串 true
[2025-11-14 16:37:13.238][000000000.443] I/user.mytable设置用户数据是布尔值 true
[2025-11-14 16:37:13.258][000000000.446] I/user.mytable设置用户数据是数值 true
[2025-11-14 16:37:13.283][000000000.450] I/user.mytable设置用户数据是table true
[2025-11-14 16:37:13.306][000000000.452] I/user.获取my_str的类型和值 string goodgoodstudy
[2025-11-14 16:37:13.324][000000000.454] I/user.获取upgrade的类型和值 boolean true
[2025-11-14 16:37:13.342][000000000.456] I/user.获取my_number的类型和值 number 1.230000
[2025-11-14 16:37:13.361][000000000.458] I/user.获取my_int的类型和值 number 5
[2025-11-14 16:37:13.382][000000000.460] I/user.获取my_table的类型和值 table: 0C7F5460 {"name":"wendal","age":18}
[2025-11-14 16:37:13.406][000000000.462] I/user.获取mytable的类型和值 table: 0C7F52E8 {"bigd":{"name":"wendal","age":123},"wendal":"goodgoodstudy","timer":1,"upgrade":true}
[2025-11-14 16:37:13.426][000000000.462] I/user.kv数据库迭代器 userdata: 0C7F5100
[2025-11-14 16:37:13.448][000000000.466] I/user.kv迭代器获取下一个key my_bool
[2025-11-14 16:37:13.468][000000000.468] I/user.fskv my_bool value true
[2025-11-14 16:37:13.489][000000000.474] I/user.kv迭代器获取下一个key my_int
[2025-11-14 16:37:13.506][000000000.476] I/user.fskv my_int value 5
[2025-11-14 16:37:13.523][000000000.479] I/user.kv迭代器获取下一个key my_number
[2025-11-14 16:37:13.540][000000000.481] I/user.fskv my_number value 1.230000
[2025-11-14 16:37:13.560][000000000.484] I/user.kv迭代器获取下一个key my_str
[2025-11-14 16:37:13.578][000000000.486] I/user.fskv my_str value goodgoodstudy
[2025-11-14 16:37:13.604][000000000.488] I/user.kv迭代器获取下一个key my_table
[2025-11-14 16:37:13.622][000000000.491] I/user.fskv my_table value table: 0C7F4FC8
[2025-11-14 16:37:13.637][000000000.493] I/user.kv迭代器获取下一个key mytable
[2025-11-14 16:37:13.655][000000000.494] I/user.fskv mytable value table: 0C7F4EB0
[2025-11-14 16:37:13.669][000000000.497] I/user.kv迭代器获取下一个key nil
[2025-11-14 16:37:13.681][000000000.497] I/user.kv数据库遍历完成
[2025-11-14 16:37:13.691][000000000.539] I/user.fskv my_bool删除结果 true
[2025-11-14 16:37:13.706][000000000.540] I/user.fskv 删除后查询my_bool nil nil
[2025-11-14 16:37:13.721][000000000.551] I/user.设置新的table，key是mytable2 true
[2025-11-14 16:37:13.740][000000000.553] I/user.mytable2的值 table: 0C7F4C70 {"age":18,"name":"wendal"}
[2025-11-14 16:37:13.766][000000000.555] I/user.mytable2删除name测试 true
[2025-11-14 16:37:13.781][000000000.558] I/user.mytable2删除结果 table: 0C7F4A88 {"age":18}
[2025-11-14 16:37:13.798][000000000.632] I/user.清空整个kv数据库 true
[2025-11-14 16:37:13.814][000000000.633] I/user.获取kv数据库状态 fskv kv 8192 65536 0
[2025-11-14 16:37:14.123][000000002.324] D/mobile cid1, state0
[2025-11-14 16:37:14.140][000000002.325] D/mobile bearer act 0, result 0
[2025-11-14 16:37:14.160][000000002.326] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-14 16:37:14.173][000000002.342] D/mobile TIME_SYNC 0



```
