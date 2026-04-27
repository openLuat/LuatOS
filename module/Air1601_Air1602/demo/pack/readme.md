# pack_DEMO 项目说明

## 项目概述
本项目演示了LuatOS的pack核心库的使用，pack核心库提供了二进制数据的打包和解包功能，支持多种数据格式和字节序。

## 功能说明

本demo通过7个实验演示pack核心库的主要功能：

    大小端编码演示：使用'<'和'>'格式符进行小端和大端编码
    
    多种数据类型打包：打包short、int、float等多种数据类型
    
    字符串格式演示：'a'格式（带长度前缀）和'z'格式（以null结尾）的字符串打包和解包
    
    An格式演示：An格式（如A2、A5）的打包行为，即打包前n个字符串参数
    
    指定位置解包：从指定位置开始解包数据
    
    复杂数据组合：打包和解包复杂的数据结构，包括整数、字符串和短整数
    
    边界情况测试：空数据打包和解包，以及数值边界测试

## 演示硬件环境

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## 演示软件环境

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.luatos 需要的脚本和资源文件

- 脚本和资源文件[点击此处查看与下载](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/pack)

- lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

4.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板 中。

## 相关软件资料

pack 核心库文档：https://docs.openluat.com/osapi/core/pack/

## 演示核心步骤
1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、在日志中查看演示结果

本demo包含7个实验，运行后会在日志中输出每一步的结果：

- 实验1：大小端编码

  演示如何使用'<'和'>'格式符进行小端和大端编码

        ``` lua
        I/user.小端编码: DDCCBBAA 8
        I/user.大端编码: AABBCCDD 8
        I/user.解包验证 - 小端: 0xAABBCCDD
        I/user.解包验证 - 大端: 0xAABBCCDD
         ```

- 实验2：多种数据类型打包

  演示如何同时打包short、int、float等多种数据类型

        ``` lua
        I/user.混合数据打包: 7B0055F80600C3F54840 20
        I/user.解包混合数据: 123 456789 3.140000
         ```


- 实验3：字符串格式演示

  演示'a'格式（带长度前缀）和'z'格式（以null结尾）的字符串打包和解包

        ``` lua
         I/user.'a'格式字符串: 060000004C7561744F53 20
         I/user.'a'格式解包: LuatOS
         I/user.'z'格式字符串: 4C7561744F5300 14
         I/user.'z'格式解包: LuatOS
         ```
  
- 实验4：An格式演示

  演示An格式（如A2、A5）的打包行为，即打包前n个字符串参数

        ``` lua
        I/user.'A'格式打包: 68657A686F75 12
        I/user.'A'格式结果: hezhou
        I/user.'A5'格式打包: 68657A686F754C7561744F532121 28
        I/user.'A5'格式结果: hezhouLuatOS!!
         ```

- 实验5：指定位置解包

  演示如何从指定位置开始解包数据

        ``` lua
         I/user.多数据打包: 6400C80000002C01 16
         I/user.分步解包结果: 100 200 300
         ```

- 实验6：复杂数据组合

  演示如何打包和解包复杂的数据结构，包括整数、字符串和短整数

        ``` lua
         I/user.复杂数据打包: 12340000000454657374FFCE 24
         I/user.复杂数据解包: 0x1234 Test -50
         ```

 - 实验7：边界情况

    演示空数据打包和解包，以及数值边界测试

        ``` lua
         I/user.空格式打包:  0
         I/user.空格式解包位置: 1
         I/user.短整型边界 - 最大值: FF7F 4
         I/user.短整型边界 - 最小值: 0080 4
         I/user.边界值验证: 32767 -32768
         ```

## 注意事项

本demo仅用于演示pack核心库的基本用法，更多高级用法请参考[pack 核心板文档](https://docs.openluat.com/osapi/core/pack/)。

在实际使用中，请根据具体需求选择合适的数据类型和字节序。

