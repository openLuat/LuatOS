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

1、Air780EHM核心板
 
![alt text]( https://docs.openLuat.com/cdn/image/Air780EHM核心板.jpg)


Air780EHV核心板
 
![alt text]( https://docs.openLuat.com/cdn/image/Air780EHV核心板.jpg)

Air780EGH核心板
 
![alt text]( https://docs.openLuat.com/cdn/image/Air780EGH核心板.jpg)

2、TYPE-C USB数据线一根
- Air780EHM/Air780EHV/Air780EGH核心板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；


## 演示软件环境
1、Luatools下载调试工具 [https://docs.openluat.com/air780epm/common/Luatools/]

2、固件版本：
- LuatOS-SoC_V2016_Air780EHM 版本固件。不同版本区别请见 https://docs.openluat.com/air780epm/luatos/firmware/version/

- LuatOS-SoC_V2016_Air780EHV 版本固件。不同版本区别请见 https://docs.openluat.com/air780ehv/luatos/firmware/version/

- LuatOS-SoC_V2016_Air780EGH 版本固件。不同版本区别请见 https://docs.openluat.com/air780egh/luatos/firmware/version/

3、lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

4、准备好软件环境之后，接下来查看

- [如何烧录项目文件到 Air780EHV核心板中](https://docs.openluat.com/air780ehv/luatos/common/download/)  

- [如何烧录项目文件到 Air780EGH核心板中](https://docs.openluat.com/air780egh/luatos/common/download/)  
将本篇文章中演示使用的项目文件烧录到相应的核心板中。

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
  
