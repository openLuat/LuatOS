## **功能模块介绍：**

本demo进行了一个完整的 zbuff 二进制数据处理库 的演示，示了在嵌入式环境中高效处理二进制数据的全流程。项目分为三个核心模块，覆盖了从基础到高级的二进制数据处理场景：

1、main.lua:主程序入口

2、zbuff_core.lua：为zbuff的基础操作模块，包含zbuff最常用的创建，读写高效查询等基础功能。

3、zbuff_advanced.lua：为zbuff高级操作模块，包含zbuff较为复杂的结构化打包，类型化操作等数据处理功能。

4、zbuff_memory.lua：为内存管理模块，核心业务逻辑为内存管理操作。

## 演示功能概述

### 1、核心功能模块 (zbuff_core.lua)

#### 缓冲区管理:

（1）创建固定大小(1024字节)的缓冲区 zbuff.create

（2）索引直接访问(如 buff[0] = 0xAE)

#### 基础IO操作:

（1）写入字符串和数值数据(write("123"))

（2）指针控制(seek()定位操作)

（3）数据读取(read(3))

#### 元信息查询

（1）获取缓冲区总长度(len())

（2）查询已使用空间(used())

#### 高效数据查询

（1）query()接口快速提取数据

（2）自动格式转换(大端序处理)

### 2、高级功能模块 (zbuff_advanced.lua)

#### 结构化数据处理

（1）数据打包(pack(">IIHA", ...))：支持大端序/多种数据类型

（2）数据解包(unpack(">IIHA10"))：自动解析复合数据结构

#### 类型化操作

（1）精确类型读写：writeI8()/readU32()等

#### 浮点处理

（1）单精度浮点写入(writeF32(1.2))

（2）浮点数据读取(readF32())

### 3、内存管理模块 (zbuff_memory.lua)

#### 动态内存管理

（1）缓冲区动态扩容resize(2048)

#### 块操作

（1）内存块设置(set(10,0xaa,5))类似 memset

（2）数据删除(del(2,3))及前移

#### 数据工具

（1）内存比较(isEqual())

（2）Base64编码转换(toBase64())

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

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

2.内核固件文件（底层 core 固件文件）：[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/) ；

本demo开发测试时使用的固件为[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板中。

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与内核固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```Lua
（1）开始打印项目信息正式开始展示。
[2025-08-11 16:38:35.922][000000000.369] I/user.main 项目启动 zbuff 003.000.000
[2025-08-11 16:38:35.932][000000000.379] I/user.zbuff_core 启动核心功能演示
[2025-08-11 16:38:35.938][000000000.380] I/user.zbuff_core 缓冲区创建 长度: 1024


（2）进行BUFF创建,初始化以及索引,读写,清除等基础功能演示操作
[2025-08-11 16:38:35.950][000000000.380] I/user.zbuff_core === 缓冲区创建与初始化演示 ===
[2025-08-11 16:38:35.955][000000000.380] I/user.zbuff_core 索引访问示例 buff[0] = 174

[2025-08-11 16:38:35.965][000000000.381] I/user.zbuff_core === 基础IO操作演示 ===
[2025-08-11 16:38:35.971][000000000.381] I/user.zbuff_core 写入字符串 123
[2025-08-11 16:38:35.979][000000000.381] I/user.zbuff_core 写入数值 0x12, 0x13, 0x13, 0x33
[2025-08-11 16:38:35.985][000000000.381] I/user.zbuff_core 指针当前位置 向后移动5字节 当前位置: 12
[2025-08-11 16:38:35.991][000000000.382] I/user.zbuff_core 指针移动 重置到开头
[2025-08-11 16:38:36.000][000000000.382] I/user.zbuff_core 读取数据 长度3: 123

[2025-08-11 16:38:36.005][000000000.382] I/user.zbuff_core === 缓冲区清除操作 ===
[2025-08-11 16:38:36.013][000000000.382] I/user.zbuff_core 清除操作 全部清零
[2025-08-11 16:38:36.019][000000000.382] I/user.zbuff_core 清除操作 填充0xA5

[2025-08-11 16:38:36.027][000000000.383] I/user.zbuff_core === 元信息查询 ===
[2025-08-11 16:38:36.033][000000000.383] I/user.zbuff_core 元信息 总长度: 1024
[2025-08-11 16:38:36.043][000000000.383] I/user.zbuff_core 元信息 已使用: 3

[2025-08-11 16:38:36.048][000000000.383] I/user.zbuff_core === 高效数据查询 ===
[2025-08-11 16:38:36.056][000000000.384] I/user.zbuff_core query查询 全部数据: 123456789ABC 12
[2025-08-11 16:38:36.060][000000000.384] I/user.zbuff_core query查询 大端序格式: 305419896
[2025-08-11 16:38:36.067][000000000.384] I/user.zbuff_core 核心功能演示完成


（3）进行高级功能演示，包括数据打包与解包、类型化读写、浮点操作演示等。
[2025-08-11 16:38:36.072][000000000.398] I/user.zbuff_advanced 启动高级功能演示

[2025-08-11 16:38:36.078][000000000.398] I/user.zbuff_advanced === 数据打包与解包演示 ===
[2025-08-11 16:38:36.088][000000000.399] I/user.zbuff_advanced 数据打包 格式: >IIHA 值: 0x1234, 0x4567, 0x12, 'abcdefg'
[2025-08-11 16:38:36.092][000000000.399] I/user.zbuff_advanced 打包后数据 0000123400004567001261626364656667 34
[2025-08-11 16:38:36.101][000000000.400] I/user.zbuff_advanced 数据解包 数量: 20 值: 4660 17767 18 abcdefg
[2025-08-11 16:38:36.105][000000000.401] I/user.zbuff_advanced 解包输出内容 cnt: 20 a(32位): 0x1234 b(32位): 0x4567 c(16位): 0x12 s(字符串): abcdefg

[2025-08-11 16:38:36.109][000000000.401] I/user.zbuff_advanced === 类型化读写演示 ===
[2025-08-11 16:38:36.119][000000000.401] I/user.zbuff_advanced 类型化写入 I8: 10
[2025-08-11 16:38:36.126][000000000.402] I/user.zbuff_advanced 类型化写入 U32: 1024
[2025-08-11 16:38:36.135][000000000.402] I/user.zbuff_advanced 类型化读取 I8: 10
[2025-08-11 16:38:36.140][000000000.402] I/user.zbuff_advanced 类型化读取 U32: 1024

[2025-08-11 16:38:36.151][000000000.402] I/user.zbuff_advanced === 浮点数操作演示 ===
[2025-08-11 16:38:36.156][000000000.403] I/user.zbuff_advanced 浮点数操作 写入F32: 1.200000
[2025-08-11 16:38:36.165][000000000.403] I/user.zbuff_advanced 浮点数操作 读取F32: 1.200000
[2025-08-11 16:38:36.171][000000000.403] I/user.zbuff_advanced 高级功能演示完成


（4）内存管理演示:内存块设置(set(10,0xaa,5)),数据删除(del(2,3))及前移,内存比较,Base64编码转换等
[2025-08-11 16:38:36.182][000000000.415] I/user.zbuff_memory 启动内存管理功能演示
[2025-08-11 16:38:36.188][000000000.416] I/user.zbuff_memory 大小调整 原始大小: 1024 新大小: 2048
[2025-08-11 16:38:36.198][000000000.417] I/user.zbuff_memory 内存设置 位置10-14设置为0xaa
[2025-08-11 16:38:36.204][000000000.417] I/user.zbuff_memory 验证结果 位置10: 170 应为0xaa
[2025-08-11 16:38:36.215][000000000.417] I/user.zbuff_memory 删除前数据 
[2025-08-11 16:38:36.222][000000000.418] ABCDEFGH
[2025-08-11 16:38:36.233][000000000.418] I/user.zbuff_memory 删除操作 删除位置2-4 结果: 
[2025-08-11 16:38:36.244][000000000.418] ABFGH
[2025-08-11 16:38:36.251][000000000.418] I/user.zbuff_memory 内存比较 结果: false 差异位置: 0
[2025-08-11 16:38:36.258][000000000.419] I/user.zbuff_memory Base64编码 长度: 8 结果: QUJGR0g=
[2025-08-11 16:38:36.264][000000000.419] I/user.zbuff_memory 内存管理功能演示完成
```

