# string_DEMO 项目说明

## 项目概述

本项目演示了LuatOS的string核心库的使用，string核心库提供了丰富的字符串处理功能，包括编码转换、字符串分割、格式处理等。
## 功能说明

本demo通过多个示例演示string核心库的主要功能：

    十六进制编码/解码：演示字符串与十六进制格式的互相转换
    
    字符串分割处理：演示使用不同分隔符进行字符串分割
    
    数值转换操作：演示字符串到二进制数据的转换
    
    Base64编码解码：演示Base64编码和解码功能
    
    Base32编码解码：演示Base32编码和解码功能
    
    字符串前后缀判断：演示字符串前缀和后缀判断功能
    
    字符串裁剪处理：演示去除字符串前后空白字符的功能

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

本demo开发测试时使用的固件为[LuatOS-SoC_V1012_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板中。

## 相关软件资料
string 核心库文档：https://docs.openluat.com/osapi/core/string/

## 演示核心步骤
1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、在日志中查看演示结果

``` lua
 I/user.string_demo 字符串操作演示模块初始化
 I/user.string_demo 开始执行所有字符串操作演示
```

本demo包含6个主要功能，运行后会在日志中输出每一步的结果：

- 十六进制转换示例

  演示字符串与十六进制格式的互相转换

  ``` lua
  I/user.=== 十六进制转换示例 ===
  I/user.toHex 原始字符串: 123abc HEX结果: 313233616263 长度: 12
  I/user.toHex 带空格分隔: 31 32 33 61 62 63 
  I/user.fromHex HEX字符串解码: 123abc
  I/user.toHex 二进制数据转HEX: 0102030405
  ```

- 字符串分割示例

  演示使用不同分隔符进行字符串分割

  ``` lua
  I/user.=== 字符串分割示例 ===
  I/user.split CSV分割结果: 3 ["123","456","789"]
  I/user.split IP地址分割: 1 ["192.168.1.1"]
  I/user.split 多字符分隔符: 4 ["a","b","c","d"]
  I/user.split 路径分割: 4 ["usr","local","bin","lua"]
  ```


- 实数值转换示例

  演示字符串到二进制数据的转换
  
  ``` lua
  I/user.=== 数值转换示例 ===
  I/user.toValue 原始字符串: 123456 转换字符数: 6
  I/user.toValue 二进制结果HEX: 010203040506 12
  I/user.toValue 混合字符串转换: 123abc 字符数: 6
  I/user.toValue 混合结果HEX: 0102030A0B0C 12
  ```

- Base64编码示例

  演示Base64编码和解码功能    
  ``` lua
  I/user.=== Base64编码示例 ===
  I/user.toBase64 原文: Hello LuaOS! 编码后: SGVsbG8gTHVhT1Mh
  I/user.fromBase64 解码结果: Hello LuaOS!
  I/user.toBase64 中文原文: 你好世界 编码后: 5L2g5aW95LiW55WM
  I/user.fromBase64 中文解码: 你好世界
  ```

- Base32编码示例
  演示Base32编码和解码功能
  ``` lua
  I/user.=== Base32编码解码示例 ===
  I/user.toBase32 原文: Hello World 编码后: JBSWY3DPEBLW64TMMQ======
  I/user.fromBase32 解码结果: Hello World
  I/user.toBase32 短字符串编码: test => ORSXG5A=
  I/user.fromBase32 短字符串解码: test
  I/user.toBase32 中文原文: 你好世界 编码后: 4S62BZNFXUYQKIIUHU4Q====
  I/user.fromBase32 中文解码: 你好世界
  I/user.toBase32 二进制数据HEX: 0102030405 Base32: AEBAGBAFAYDQ====
  I/user.toBase32 空字符串编码:'' => 
  I/user.fromBase32 空字符串解码: ''
  ```

- 字符串判断示例

  演示字符串前缀和后缀判断功能

  ``` lua
  I/user.=== 字符串判断示例 ===
  I/user.startsWith 字符串: hello world
  I/user.startsWith 以'hello'开头: true
  I/user.startsWith 以'world'开头: false
  I/user.endsWith 以'world'结尾: true
  I/user.endsWith 以'hello'结尾: false
  ```

- 字符串裁剪示例

  演示去除字符串前后空白字符的功能

  ``` lua
  I/user.=== 字符串裁剪示例 ===
  I/user.trim 原始字符串长度: 23
  I/user.trim 裁剪后字符串: 'hello world' 长度: 11
  I/user.trim 用户输入清理: '   admin   ' => 'admin'
  ```



## 注意事项

本demo仅用于演示string核心库的基本用法，更多高级用法请参考[string核心库](https://docs.openluat.com/osapi/core/string/)文档。

在实际使用中，请根据具体需求选择合适的字符串处理函数，注意不同函数对输入数据的要求和边界情况处理。

