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

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/8101.jpg)



1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

* Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

* 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V1006_Air8101_1.soc，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. Luatools 烧录内核固件和 脚本文件

3. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，设置kv数据、设置 table 内的键值对数据，用kv迭代器遍历kv数据，删除kv数据等。

4. 如下 log 显示：

```bash
[2025-11-21 17:01:23.675] luat:U(247):I/user.main Air8101_fskv 001.000.000
[2025-11-21 17:01:23.691] luat:I(251):lfs:sfd_lfs mount ret -84, exec auto-format
[2025-11-21 17:01:23.753] luat:D(320):lfs:init ok
[2025-11-21 17:01:23.759] luat:U(320):I/user.fskv init complete true
[2025-11-21 17:01:23.759] luat:U(321):I/user.获取kv数据库状态 fskv kv 8192 65536 0
[2025-11-21 17:01:23.759] luat:U(325):I/user.fskv设置用户数据是字符串 true
[2025-11-21 17:01:23.759] luat:U(330):I/user.fskv设置用户数据是布尔值 true
[2025-11-21 17:01:23.759] luat:U(334):I/user.fskv设置用户数据是数值 true
[2025-11-21 17:01:23.759] luat:U(338):I/user.fskv设置用户数据是整数 true
[2025-11-21 17:01:23.772] luat:U(343):I/user.fskv用户数据是table类型 true
[2025-11-21 17:01:23.772] luat:U(349):I/user.mytable设置用户数据是字符串 true
[2025-11-21 17:01:23.777] luat:U(353):I/user.mytable设置用户数据是布尔值 true
[2025-11-21 17:01:23.780] luat:U(357):I/user.mytable设置用户数据是数值 true
[2025-11-21 17:01:23.800] luat:U(362):I/user.mytable设置用户数据是table true
[2025-11-21 17:01:23.800] luat:U(364):I/user.获取my_str的类型和值 string goodgoodstudy
[2025-11-21 17:01:23.800] luat:U(366):I/user.获取upgrade的类型和值 boolean true
[2025-11-21 17:01:23.800] luat:U(368):I/user.获取my_number的类型和值 number   1.23000
[2025-11-21 17:01:23.800] luat:U(370):I/user.获取my_int的类型和值 number 5
[2025-11-21 17:01:23.800] luat:U(372):I/user.获取my_table的类型和值 table: 60C7E3D0 {"name":"wendal","age":18}
[2025-11-21 17:01:23.800] luat:U(373):I/user.获取mytable的类型和值 table: 60C7E258 {"bigd":{"name":"wendal","age":123},"wendal":"goodgoodstudy","timer":1,"upgrade":true}
[2025-11-21 17:01:23.800] luat:U(374):I/user.kv数据库迭代器 userdata: 60C7E070
[2025-11-21 17:01:23.820] luat:U(377):I/user.kv迭代器获取下一个key my_bool
[2025-11-21 17:01:23.820] luat:U(379):I/user.fskv my_bool value true
[2025-11-21 17:01:23.820] luat:U(382):I/user.kv迭代器获取下一个key my_int
[2025-11-21 17:01:23.820] luat:U(383):I/user.fskv my_int value 5
[2025-11-21 17:01:23.820] luat:U(386):I/user.kv迭代器获取下一个key my_number
[2025-11-21 17:01:23.820] luat:U(388):I/user.fskv my_number value   1.23000
[2025-11-21 17:01:23.820] luat:U(390):I/user.kv迭代器获取下一个key my_str
[2025-11-21 17:01:23.820] luat:U(393):I/user.fskv my_str value goodgoodstudy
[2025-11-21 17:01:23.851] luat:U(395):I/user.kv迭代器获取下一个key my_table
[2025-11-21 17:01:23.851] luat:U(397):I/user.fskv my_table value table: 60C7DF38
[2025-11-21 17:01:23.851] luat:U(399):I/user.kv迭代器获取下一个key mytable
[2025-11-21 17:01:23.851] luat:U(400):I/user.fskv mytable value table: 60C7DE20
[2025-11-21 17:01:23.851] luat:U(402):I/user.kv迭代器获取下一个key nil
[2025-11-21 17:01:23.851] luat:U(402):I/user.kv数据库遍历完成
[2025-11-21 17:01:23.907] luat:U(450):I/user.fskv my_bool删除结果 true
[2025-11-21 17:01:23.907] luat:U(450):I/user.fskv 删除后查询my_bool nil nil
[2025-11-21 17:01:23.907] luat:U(455):I/user.设置新的table，key是mytable2 true
[2025-11-21 17:01:23.907] luat:U(456):I/user.mytable2的值 table: 60C7DBE0 {"age":18,"name":"wendal"}
[2025-11-21 17:01:23.931] luat:U(460):I/user.mytable2删除name测试 true
[2025-11-21 17:01:23.931] luat:U(461):I/user.mytable2删除结果 table: 60C7D9F8 {"age":18}
[2025-11-21 17:01:23.984] luat:U(526):I/user.清空整个kv数据库 true
[2025-11-21 17:01:23.984] luat:U(527):I/user.获取kv数据库状态 fskv kv 8192 65536 0

```
