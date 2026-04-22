## 演示模块概述

1、main.lua：主程序入口；

2、json_app.lua：json 序列化与反序列化功能模块；

## 演示功能概述

使用 Air8000 核心板搭配 json 库演示 json 序列化与反序列化功能；

演示分为两部分：

1、将 Lua 对象 转为 JSON 字符串：

- 示例一：Lua string 转为 JSON string；

- 示例二：Lua number 转为 JSON string；

- 示例三：Lua boolean 转为 JSON string；

- 示例四：Lua table 转为 JSON string；

- 示例五：Lua nil 转为 JSON string；

- 序列化失败示例和指定浮点数示例；

2、将 JSON 字符串 转为 Lua 对象：

- 示例一：JSON string 转为 Lua string；
- 示例二：JSON number 转为 Lua number；
- 示例三：JSON boolean 转为 Lua boolean；
- 示例四：JSON table 转为 Lua table；
- 示例五：JSON nil 转为 Lua nil；
- 反序列化失败示例；
- 空表（empty table）转换为 JSON 时的说明；
- 字符串中包含控制字符（如 \r\n）的 JSON 序列化与反序列化说明；
- json.null 的语义与比较行为说明：

## 演示硬件环境

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## **演示软件环境**

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

## 演示核心步骤

1、搭建好硬件环境

2、Luatools 工具烧录内核固件和 demo 脚本代码

3、烧录成功后，自动开机运行

4、正常运行情况时的日志如下：

```
[00000001.009] I/user.string_string_test1 序列化成功： "test"
[00000001.009] I/user.number_string_test1 序列化成功： 123456789
[00000001.010] I/user.boolean_string_test1 序列化成功： true
[00000001.010] I/user.table_string_test1 序列化成功： {"abc":123,"ttt":true,"def":"123"}
[00000001.010] I/user.nil_string_test1 序列化成功：
[00000001.011] I/user.table_string_test2 序列化失败： Cannot serialise function: type not supported
[00000001.011] I/user.table_string_test3 序列化成功： {"abc":1234.568}
[00000001.011] I/user.string_string_test1 反序列化成功： test
[00000001.011] I/user.string_number_test1 反序列化成功： 123456789
[00000001.011] I/user.string_boolean_test1 反序列化成功： true
[00000001.011] I/user.string_table_test1.2 反序列化成功： table: 01FE5010
[00000001.011] I/user.string_table_test1.2 反序列化成功： 1234545
[00000001.011] I/user.string_table_test2 反序列化失败： Expected value but found T_OBJ_END at character 8
[00000001.012] I/user.table_string_test3 序列化成功： {"abc":{}}
[00000001.012] I/user.json 序列化成功： {"str":"ABC\r\nDEF\r\n"}
[00000001.012] I/user.json 反序列化成功： ABC
DEF
 true
[00000001.012] I/user.json.null {"name":null}
[00000001.012] I/user.json.null true
[00000001.012] I/user.json.null false
```

