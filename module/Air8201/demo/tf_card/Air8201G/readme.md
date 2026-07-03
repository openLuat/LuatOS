## Air8201G tf_card demo 说明

> 本目录为 **Air8201G**（基于 Air780EGH 模组）的 tf_card demo。**Air8201G 的 BTB 扩展板已板载 TF 卡槽**，可直接插入 TF 卡（SD 卡）进行测试，无需额外配件。

## 功能模块介绍

本 demo 演示了在嵌入式环境中对 TF 卡（SD 卡）的完整操作流程，覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为四个核心模块：

1、main.lua：主程序入口；

2、tfcard_app.lua：TF 卡基础应用模块，实现文件系统管理、文件操作和目录管理功能；

3、http_download_file.lua：HTTP 下载模块，实现网络检测与文件下载到 TF 卡的功能；

4、http_upload_file.lua：HTTP 上传模块，实现网络检测与 TF 卡内大文件上传服务器的功能。

## 演示功能概述

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号；
- 初始化看门狗，并定时喂狗；
- 启动一个循环定时器，每隔 3 秒钟打印一次总内存、实时的已使用内存、历史最高的已使用内存情况，方便分析内存使用是否有异常；
- 加载 tfcard_app 模块、http_download_file 模块、http_upload_file 模块；
- 最后运行 sys.run()。

### 2、TF 卡核心演示模块（tfcard_app.lua）

#### 文件系统管理

- SPI 初始化与挂载：
  - 配置 SPI 接口参数（频率 400kHz）；
  - 挂载 FAT32 文件系统到 `/sd` 路径；
  - 自动格式化检测与处理。
- 空间信息获取：
  - 实时查询 TF 卡可用空间；
  - 输出详细存储信息（总空间/剩余空间）。

#### 文件操作

- 创建目录、创建/写入文件、检查文件存在、获取文件大小、读取文件内容；
- 启动计数文件：记录设备启动次数；
- 文件追加、按行读取、文件关闭、文件重命名；
- 列举目录、删除文件、删除目录。

#### 结果处理

- 资源清理（卸载/SPI 关闭）。

### 3、HTTP 下载功能 (http_download_file.lua)

- SPI 初始化与挂载；
- 1 秒循环等待 IP 就绪，网络故障处理机制；
- HTTP 下载，下载状态码解析，自动文件大小验证；
- 资源清理（卸载/spi 关闭）。

### 4、HTTP 上传功能 (http_upload_file.lua)

- 加载扩展库 require("httpplus")；
- 1 秒循环等待 IP 就绪；
- SPI 初始化与挂载，确认文件存在；
- HTTP 上传，下载状态码解析，自动文件大小验证；
- 资源清理（卸载/spi 关闭）。

## 演示硬件环境

1、Air8201G 整机板一块（BTB 扩展板已板载 TF 卡槽）；

2、TYPE-C USB 数据线一根；

3、TF 卡（SD 卡）一张；

4、Air8201G BTB 扩展板和数据线的硬件接线方式：

- Air8201G BTB 扩展板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到 BTB 扩展板的 TYPE-C USB 座子，另外一端连接电脑 USB 口。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201G固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

1、将 TF 卡插入 Air8201G BTB 扩展板的 TF 卡槽；

2、搭建好硬件环境；

3、通过 Luatools 将 demo 与固件烧录到 Air8201G 整机板中；

4、烧录好后，板子开机将会在 Luatools 上看到 TF 卡初始化与挂载、文件操作、HTTP 下载/上传等日志打印。

## 异常处理

1、使用合宙开发板时，如出现 TF 卡初始化失败的情况，请使用 exmux 扩展库的 setup 函数初始化外设分组开关状态，使用 open 函数打开外设分组，并跳转至 exmux 扩展库介绍文档中了解 I2C/SPI 总线上拉问题；https://docs.openluat.com/osapi/ext/exmux/

2、使用自己制作的板子时，如出现 TF 卡初始化失败的情况，请根据各型号文档中"硬件设计资料"的 I2C 和 SPI 板块"常见的坑"栏目中的经验，检查板子上的 I2C/SPI 总线是否正常上拉；也可使用 exmux 库来管理 i2c 和 spi 总线的上拉状态，详情请参考 exmux 扩展库介绍文档。
