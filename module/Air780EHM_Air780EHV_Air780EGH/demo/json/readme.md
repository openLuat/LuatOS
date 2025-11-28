## 演示模块概述

1、main.lua：主程序入口；

2、json_app.lua：json 序列化与反序列化功能模块；

## 演示功能概述

使用 Air780EHM/EHV/EGH 核心板搭配 json 库演示 json 序列化与反序列化功能；

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

1、Air780EHM/EHV/EGH 核心板一块

2、TYPE-C USB数据线一根

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air780EHM V2016 版本](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2016-1 固件对比验证）

3、[Air780EHV V2016 版本](https://docs.openluat.com/air780ehv/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2016-1 固件对比验证）

4、[Air780EGH V2016 版本](https://docs.openluat.com/air780egh/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2016-1 固件对比验证）

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

