## **功能模块介绍**

本demo演示了在嵌入式环境中对TF卡（SD卡）的完整操作流程，覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为两个核心模块：

1、main.lua：主程序入口 <br> 
2、tfcard_app.lua：TF卡基础应用模块，实现文件系统管理、文件操作和目录管理功能<br> 
3、http_download_file.lua：HTTP下载模块，实现网络检测与文件下载到TF卡的功能<br>
4、http_upload_file.lua：HTTP下载模块，实现网络检测与tf卡内大文件上传服务器的功能

## **演示功能概述**

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载tfcard_app模块（通过require "tfcard_app"）
- 加载http_download_file模块（通过require "http_download_file"）
- 加载http_upload_file模块（通过require "http_upload_file"）

### 2、TF卡基础应用模块（tfcard_app.lua）

#### 文件系统管理

- SPI初始化与挂载：
  - 配置SPI接口参数（频率400kHz）
  - 挂载FAT32文件系统到`/sd`路径
  - 自动格式化检测与处理
- 空间信息获取：
  - 实时查询TF卡可用空间
  - 输出详细存储信息（总空间/剩余空间）

#### 文件操作

- 创建目录：io.mkdir("/sd/io_test")
- 创建/写入文件： io.open("/sd/io_test/boottime", "wb")
- 检查文件存在： io.exists(file_path)
- 获取文件大小：io.fileSize(file_path)
- 读取文件内容: io.open(file_path, "rb"):read("*a")
- 启动计数文件： 记录设备启动次数
- 文件追加： io.open(append_file, "a+")
- 按行读取： file:read("*l")
- 文件关闭： file:close()
- 文件重命名： os.rename(old_path, new_path)
- 列举目录： io.lsdir(dir_path)
- 删除文件： os.remove(file_path)
- 删除目录： io.rmdir(dir_path)

### 3、TF卡核心演示模块（tfcard_app.lua）

#### 文件系统管理

- SPI初始化与挂载：
  - 配置SPI接口参数（频率400kHz）
  - 挂载FAT32文件系统到`/sd`路径
  - 自动格式化检测与处理
- 空间信息获取：
  - 实时查询TF卡可用空间
  - 输出详细存储信息（总空间/剩余空间）
#### 文件操作
- 创建目录：io.mkdir("/sd/io_test")
- 创建/写入文件： io.open("/sd/io_test/boottime", "wb")
- 检查文件存在： io.exists(file_path)
- 获取文件大小：io.fileSize(file_path)
- 读取文件内容: io.open(file_path, "rb"):read("*a")
- 启动计数文件： 记录设备启动次数
- 文件追加： io.open(append_file, "a+")
- 按行读取： file:read("*l")
- 文件关闭： file:close()
- 文件重命名： os.rename(old_path, new_path)
- 列举目录： io.lsdir(dir_path)
- 删除文件： os.remove(file_path)
- 删除目录： io.rmdir(dir_path)

#### 结果处理

- 资源清理（卸载/SPI关闭）

### 4、HTTP下载功能 (http_download_file.lua)

#### 文件系统管理

- SPI初始化与挂载

#### 网络就绪检测

- 1秒循环等待IP就绪
- 网络故障处理机制

#### 安全下载

- HTTP下载

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 资源清理（卸载/spi关闭）

### 5、HTTP上传功能 (http_download_file.lua)

#### 加载扩展库

- require("httpplus")

#### 网络就绪检测

- 1秒循环等待IP就绪

#### 文件系统管理

- SPI初始化与挂载

- 确认文件存在


#### 安全上传

- HTTP上传

#### 结果处理

- 解析服务器响应
- 资源清理（卸载/spi关闭）

## **演示硬件环境**

1、Air8000核心板一块(Air8000系列模块的核心板接线方式相同，这里以Air8000为例)

2、TYPE-C USB数据线一根

3、AirMICROSD_1010模块一个和SD卡一张

4、Air8000系列核心板和数据线的硬件接线方式为

- Air8000核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到供电一端）

- Air8000核心板背面的拨码开关拨到USB ON

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air8000核心板和AirMICROSD_1010模块接线方式

|   Air8000核心板    |    AirMICROSD_1010    |
| --------------- | --------------------- |
|  GND(任意)      |          GND          |
|  VDD_EXT        |          3V3         |
|  GPIO12/SPI1_CS  |        spi_cs         |
|  SPI1_SLK       |        spi_clk,时钟       |
|  SPI1_MOSI      |  spi_mosi,主机输出,从机输入|
|  SPI1_MISO      |  spi_miso,主机输入,从机输出|

## **演示软件环境**

1、Luatools下载调试工具：https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：https://docs.openluat.com/air8000/luatos/firmware/

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印

```lua
（1）TF卡初始化与挂载
[2025-11-14 11:49:12.769][000000000.278] SPI_HWInit 552:spi1 speed 2000000,1994805,154
[2025-11-14 11:49:12.788][000000000.279] D/fatfs init sdcard at spi=1 cs=12
[2025-11-14 11:49:12.811][000000000.407] D/SPI_TF 卡容量 125173760KB
[2025-11-14 11:49:12.822][000000000.408] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2025-11-14 11:49:12.835][000000000.412] I/user.fatfs.mount 挂载成功 0
[2025-11-14 11:49:12.844][000000000.665] I/user.fatfs getfree {"free_sectors":250335488,"total_kb":125168512,"free_kb":125167744,"total_sectors":250337024}
[2025-11-14 11:49:12.873][000000000.666] I/user.fs lsmount [{"fs":"ec7xx","path":""},{"fs":"inline","path":"\/lua\/"},{"fs":"ram","path":"\/ram\/"},{"fs":"luadb","path":"\/luadb\/"},{"fs":"fatfs","path":"\/sd"}]



（2）文件操作演示
[2025-11-14 11:49:12.880][000000000.666] I/user.文件操作 ===== 开始文件操作 =====
[2025-11-14 11:49:13.111][000000001.254] I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2025-11-14 11:49:13.116][000000001.267] I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2025-11-14 11:49:13.123][000000001.270] I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2025-11-14 11:49:13.127][000000001.273] I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2025-11-14 11:49:13.131][000000001.276] I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2025-11-14 11:49:13.148][000000001.280] I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2025-11-14 11:49:13.157][000000001.280] I/user.启动计数 当前值: 0
[2025-11-14 11:49:13.165][000000001.281] I/user.启动计数 更新值: 1
[2025-11-14 11:49:13.178][000000001.292] I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2025-11-14 11:49:13.188][000000001.308] I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2025-11-14 11:49:13.194][000000001.314] I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2025-11-14 11:49:13.203][000000001.318] I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2025-11-14 11:49:13.208][000000001.334] I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2025-11-14 11:49:13.215][000000001.338] I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2025-11-14 11:49:13.219][000000001.338] I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2025-11-14 11:49:13.223][000000001.339] I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2025-11-14 11:49:13.232][000000001.344] I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2025-11-14 11:49:13.236][000000001.348] D/fatfs f_open /io_test/test_a 4
[2025-11-14 11:49:13.242][000000001.349] D/vfs fopen /sd/io_test/test_a r not found
[2025-11-14 11:49:13.247][000000001.349] I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2025-11-14 11:49:13.252][000000001.349] I/user.目录操作 ===== 开始目录列举 =====
[2025-11-14 11:49:13.259][000000001.357] I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"testline","size":15,"type":0},{"name":"renamed_file.txt","size":6,"type":0}]
[2025-11-14 11:49:13.264][000000001.364] I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2025-11-14 11:49:13.276][000000001.366] D/fatfs f_open /io_test/renamed_file.txt 4
[2025-11-14 11:49:13.281][000000001.366] D/vfs fopen /sd/io_test/renamed_file.txt r not found
[2025-11-14 11:49:13.287][000000001.367] I/user.验证结果 renamed_file.txt文件删除验证成功
[2025-11-14 11:49:13.293][000000001.373] I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2025-11-14 11:49:13.297][000000001.375] D/fatfs f_open /io_test/testline 4
[2025-11-14 11:49:13.305][000000001.376] D/vfs fopen /sd/io_test/testline r not found
[2025-11-14 11:49:13.310][000000001.376] I/user.验证结果 testline文件删除验证成功
[2025-11-14 11:49:13.315][000000001.383] I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2025-11-14 11:49:13.323][000000001.385] D/fatfs f_open /io_test/boottime 4
[2025-11-14 11:49:13.328][000000001.386] D/vfs fopen /sd/io_test/boottime r not found
[2025-11-14 11:49:13.332][000000001.386] I/user.验证结果 boottime文件删除验证成功
[2025-11-14 11:49:13.339][000000001.393] I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2025-11-14 11:49:13.343][000000001.395] D/fatfs f_open /io_test 4
[2025-11-14 11:49:13.348][000000001.395] D/vfs fopen /sd/io_test r not found
[2025-11-14 11:49:13.352][000000001.395] I/user.验证结果 目录删除验证成功
[2025-11-14 11:49:13.359][000000001.395] I/user.文件操作 ===== 文件操作完成 =====
[2025-11-14 11:49:13.369][000000001.396] I/user.结束 开始执行关闭操作...
[2025-11-14 11:49:13.373][000000001.396] I/user.文件系统 卸载成功
[2025-11-14 11:49:13.379][000000001.396] I/user.SPI接口 已关闭



（3）网络连接与HTTP下载
[2025-11-14 11:52:24.522][000000002.310] I/user.HTTP下载 开始下载任务
[2025-11-14 11:52:24.539][000000002.314] dns_run 676:cdn.openluat-erp.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-11-14 11:52:24.550][000000002.316] D/mobile TIME_SYNC 0
[2025-11-14 11:52:24.567][000000002.390] dns_run 693:dns all done ,now stop
[2025-11-14 11:53:02.635][000000040.462] I/user.HTTP下载 下载完成 success 200 
[2025-11-14 11:53:02.650][000000040.462] {"x-oss-hash-crc64ecma":"7570337686322137116","x-oss-server-time":"104","x-oss-object-type":"Normal","Content-Length":"3389723","Via":"cache19.l2cn3022[331,331,200-0,M], cache35.l2cn3022[333,0], kunlun19.cn5230[416,415,200-0,M], kunlun19.cn5230[421,0]","x-oss-cdn-auth":"success","Date":"Fri, 14 Nov 2025 03:52:24 GMT","x-oss-request-id":"6916A7782B654B37362C05B4","Content-MD5":"Ap894+Aw36xpOHjjgfW0Cw==","Last-Modified":"Wed, 03 Sep 2025 07:26:20 GMT","Connection":"keep-alive","Server":"Tengine","ETag":"\"029F3DE3E030DFAC693878E381F5B40B\"","Timing-Allow-Origin":"*","X-Swift-CacheTime":"3600","Accept-Ranges":"bytes","x-oss-storage-class":"Standard","Content-Type":"application\/octet-stream","X-Swift-SaveTime":"Fri, 14 Nov 2025 03:52:24 GMT","X-Cache":"MISS TCP_MISS dirn:-2:-2","Ali-Swift-Global-Savetime":"1763092344","EagleId":"6f30473017630923443325751e"}
[2025-11-14 11:53:02.667][000000040.462]  3389723
[2025-11-14 11:53:02.679][000000040.464] I/user.HTTP下载 文件大小验证 预期: 3389723 实际: 3389723
[2025-11-14 11:53:02.693][000000040.465] I/user.HTTP下载 资源清理完成


（4）网络连接与HTTP上传
[2025-11-14 12:10:07.428][000000000.266] I/user.main tfcard 001.000.000
[2025-11-14 12:10:07.433][000000000.288] W/user.HTTP上传 等待网络连接 1 1
[2025-11-14 12:10:07.732][000000001.289] W/user.HTTP上传 等待网络连接 1 1
[2025-11-14 12:10:08.580][000000002.059] D/mobile cid1, state0
[2025-11-14 12:10:08.586][000000002.059] D/mobile bearer act 0, result 0
[2025-11-14 12:10:08.597][000000002.060] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-14 12:10:08.606][000000002.061] I/user.HTTP上传 网络已就绪 1 1
[2025-11-14 12:10:08.611][000000002.062] SPI_HWInit 552:spi1 speed 2000000,1994805,154
[2025-11-14 12:10:08.615][000000002.062] D/fatfs init sdcard at spi=1 cs=12
[2025-11-14 12:10:08.666][000000002.224] D/SPI_TF 卡容量 125173760KB
[2025-11-14 12:10:08.671][000000002.224] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2025-11-14 12:10:08.676][000000002.230] I/user.HTTP上传 准备上传文件 /sd/3_23MB.bin 大小: 3389723 字节
[2025-11-14 12:10:08.687][000000002.230] I/user.HTTP上传 开始上传任务
[2025-11-14 12:10:08.691][000000002.234] D/socket connect to airtest.openluat.com,2900
[2025-11-14 12:10:08.699][000000002.235] dns_run 676:airtest.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-11-14 12:10:08.704][000000002.237] D/mobile TIME_SYNC 0
[2025-11-14 12:10:08.736][000000002.291] dns_run 693:dns all done ,now stop
[2025-11-14 12:10:19.571][000000013.118] I/user.httpplus 等待服务器完成响应
[2025-11-14 12:10:19.974][000000013.519] I/user.httpplus 等待服务器完成响应
[2025-11-14 12:10:19.980][000000013.529] I/user.httpplus 服务器已完成响应,开始解析响应
[2025-11-14 12:10:20.005][000000013.555] I/user.HTTP上传 上传完成 success 200
[2025-11-14 12:10:20.010][000000013.555] I/user.HTTP上传 服务器响应头 {"Content-Type":"text\/plain;charset=UTF-8","Connection":"close","Content-Length":"20","Vary":"Access-Control-Request-Headers","Date":"Fri, 14 Nov 2025 04"}
[2025-11-14 12:10:20.017][000000013.556] I/user.HTTP上传 服务器响应体长度 20
[2025-11-14 12:10:20.026][000000013.557] I/user.HTTP上传 服务器响应内容 uploadFileToStaticOK
[2025-11-14 12:10:20.031][000000013.557] I/user.HTTP上传 资源清理完成
```