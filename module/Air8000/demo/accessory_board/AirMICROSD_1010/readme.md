## **功能模块介绍**

本demo演示了在嵌入式环境中对TF卡（SD卡）的完整操作流程，覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为两个核心模块：

1、main.lua：主程序入口 <br> 
2、tfcard_app.lua：TF卡基础应用模块，实现文件系统管理、文件操作和目录管理功能<br> 
3、http_download_file.lua：HTTP下载模块，实现网络检测与文件下载到TF卡的功能<br>
4、http_upload_file.lua：HTTP下载模块，实现网络检测与tf卡内大文件上传服务器的功能

**注意事项：**使用大牌卡，杜邦线或者飞线测试时速率不能超过10M，自己画板走线速率实测可以到24M

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
[2026-05-15 10:27:36.908][000000000.558] I/user.main tfcard 001.999.000
[2026-05-15 10:27:36.913][000000000.565] SPI_HWInit 445:APB MP 102400000
[2026-05-15 10:27:36.918][000000000.565] SPI_HWInit 556:spi1 speed 2000000,1994805,154
[2026-05-15 10:27:36.925][000000000.565] D/fatfs init sdcard at spi=1 cs=12
[2026-05-15 10:27:36.929][000000000.716] D/SPI_TF 卡容量 3932160KB
[2026-05-15 10:27:36.935][000000000.716] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 10:27:36.940][000000000.720] I/fatfs mount success at fat32
[2026-05-15 10:27:36.944][000000000.720] I/user.fatfs.mount 挂载成功 0
[2026-05-15 10:27:36.947][000000000.721] I/user.fatfs getfree {"free_sectors":7841920,"total_kb":3931584,"free_kb":3920960,"total_sectors":7863168}
[2026-05-15 10:27:36.951][000000000.722] I/user.fs lsmount [{"fs":"ec7xx","path":""},{"fs":"inline","path":"/lua/"},{"fs":"ram","path":"/ram/"},{"fs":"luadb","path":"/luadb/"},{"fs":"fatfs","path":"/sd"}]



（2）文件操作演示
[2026-05-15 10:27:36.954][000000000.722] I/user.文件操作 ===== 开始文件操作 =====
[2026-05-15 10:27:37.065][000000001.057] I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2026-05-15 10:27:37.148][000000001.086] I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2026-05-15 10:27:37.287][000000001.089] I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2026-05-15 10:27:37.297][000000001.093] I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2026-05-15 10:27:37.302][000000001.098] I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2026-05-15 10:27:37.310][000000001.104] I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2026-05-15 10:27:37.316][000000001.104] I/user.启动计数 当前值: 0
[2026-05-15 10:27:37.522][000000001.105] I/user.启动计数 更新值: 1
[2026-05-15 10:27:37.767][000000001.223] I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2026-05-15 10:27:37.771][000000001.255] I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2026-05-15 10:27:37.777][000000001.269] I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2026-05-15 10:27:37.781][000000001.274] I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2026-05-15 10:27:37.788][000000001.305] I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2026-05-15 10:27:37.795][000000001.310] I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2026-05-15 10:27:37.803][000000001.311] I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2026-05-15 10:27:37.811][000000001.311] I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2026-05-15 10:27:37.822][000000001.323] I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2026-05-15 10:27:37.829][000000001.330] D/fatfs f_open /io_test/test_a 4
[2026-05-15 10:27:37.836][000000001.330] D/vfs fopen /sd/io_test/test_a r not found
[2026-05-15 10:27:37.846][000000001.330] I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2026-05-15 10:27:37.853][000000001.331] I/user.目录操作 ===== 开始目录列举 =====
[2026-05-15 10:27:37.861][000000001.342] I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"testline","size":15,"type":0},{"name":"renamed_file.txt","size":6,"type":0}]
[2026-05-15 10:27:37.870][000000001.359] I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2026-05-15 10:27:37.876][000000001.363] D/fatfs f_open /io_test/renamed_file.txt 4
[2026-05-15 10:27:37.882][000000001.363] D/vfs fopen /sd/io_test/renamed_file.txt r not found
[2026-05-15 10:27:37.888][000000001.364] I/user.验证结果 renamed_file.txt文件删除验证成功
[2026-05-15 10:27:37.895][000000001.382] I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2026-05-15 10:27:37.903][000000001.385] D/fatfs f_open /io_test/testline 4
[2026-05-15 10:27:37.921][000000001.386] D/vfs fopen /sd/io_test/testline r not found
[2026-05-15 10:27:37.930][000000001.386] I/user.验证结果 testline文件删除验证成功
[2026-05-15 10:27:38.051][000000001.403] I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2026-05-15 10:27:38.062][000000001.407] D/fatfs f_open /io_test/boottime 4
[2026-05-15 10:27:38.067][000000001.407] D/vfs fopen /sd/io_test/boottime r not found
[2026-05-15 10:27:38.088][000000001.408] I/user.验证结果 boottime文件删除验证成功
[2026-05-15 10:27:38.093][000000001.428] I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2026-05-15 10:27:38.103][000000001.430] D/fatfs f_open /io_test 4
[2026-05-15 10:27:38.108][000000001.430] D/vfs fopen /sd/io_test r not found
[2026-05-15 10:27:38.112][000000001.430] I/user.验证结果 目录删除验证成功
[2026-05-15 10:27:38.160][000000001.431] I/user.文件操作 ===== 文件操作完成 =====
[2026-05-15 10:27:38.230][000000001.431] I/user.结束 开始执行关闭操作...
[2026-05-15 10:27:38.340][000000001.431] I/user.文件系统 卸载成功
[2026-05-15 10:27:38.353][000000001.432] I/user.SPI接口 已关闭



（3）网络连接与HTTP下载
[2026-05-15 10:28:46.782][000000000.468] I/user.main tfcard 001.999.000
[2026-05-15 10:28:46.785][000000000.475] W/user.HTTP下载 等待网络连接 1 3
[2026-05-15 10:28:47.719][000000001.475] W/user.HTTP下载 等待网络连接 1 3
[2026-05-15 10:28:48.371][000000002.476] W/user.HTTP下载 等待网络连接 1 3
[2026-05-15 10:28:49.273][000000003.477] W/user.HTTP下载 等待网络连接 1 3
[2026-05-15 10:28:50.294][000000004.478] W/user.HTTP下载 等待网络连接 1 3
[2026-05-15 10:28:51.404][000000005.484] I/user.HTTP下载 网络已就绪 1 3
[2026-05-15 10:28:51.412][000000005.484] SPI_HWInit 445:APB MP 102400000
[2026-05-15 10:28:51.421][000000005.484] SPI_HWInit 556:spi1 speed 2000000,1994805,154
[2026-05-15 10:28:51.436][000000005.485] D/fatfs init sdcard at spi=1 cs=12
[2026-05-15 10:28:51.561][000000005.756] D/SPI_TF 卡容量 3932160KB
[2026-05-15 10:28:51.575][000000005.757] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 10:28:51.585][000000005.761] I/fatfs mount success at fat32
[2026-05-15 10:28:51.592][000000005.762] I/user.HTTP下载 开始下载任务
[2026-05-15 10:28:51.597][000000005.766] dns_run 676:cdn.openluat-erp.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-05-15 10:28:51.602][000000005.768] D/mobile cid1, state0
[2026-05-15 10:28:51.608][000000005.768] D/mobile bearer act 0, result 0
[2026-05-15 10:28:51.615][000000005.768] D/mobile NETIF_LINK_ON -> IP_READY
[2026-05-15 10:28:51.620][000000005.769] D/mobile TIME_SYNC 0 tm 1778812131
[2026-05-15 10:28:51.753][000000005.950] dns_run 693:dns all done ,now stop
[2026-05-15 10:29:53.518][000000067.712] I/http http close c1217a8
[2026-05-15 10:29:53.520][000000067.714] I/user.HTTP下载 下载完成 success 200 
[2026-05-15 10:29:53.527][000000067.715] {"x-oss-hash-crc64ecma":"7570337686322137116","x-oss-server-time":"96","x-oss-object-type":"Normal","Content-Length":"3389723","Via":"cache45.l2cn8003[252,252,200-0,M], cache46.l2cn8003[253,0], kunlun8.cn9405[0,6,200-0,H], kunlun9.cn9405[32,0]","x-oss-cdn-auth":"success","Date":"Fri, 15 May 2026 01:41:54 GMT","ETag":"\"029F3DE3E030DFAC693878E381F5B40B\"","x-oss-request-id":"6A0679E28A3C5F3032719295","Content-MD5":"Ap894+Aw36xpOHjjgfW0Cw==","Last-Modified":"Wed, 03 Sep 2025 07:26:20 GMT","Connection":"close","Server":"Tengine","Timing-Allow-Origin":"*","X-Swift-CacheTime":"3600","X-Swift-SaveTime":"Fri, 15 May 2026 01:41:54 GMT","Accept-Ranges":"bytes","x-oss-storage-class":"Standard","Content-Type":"application/octet-stream","X-Cache":"HIT TCP_MEM_HIT dirn:10:259240384","Ali-Swift-Global-Savetime":"1778809314","Age":"2818","EagleId":"6ae3669d17788121327865722e"}
[2026-05-15 10:29:53.534][000000067.715]  3389723
[2026-05-15 10:29:53.538][000000067.718] I/user.HTTP下载 文件大小验证 预期: 3389723 实际: 3389723
[2026-05-15 10:29:53.540][000000067.718] I/user.HTTP下载 资源清理完成


（4）网络连接与HTTP上传
[2026-05-15 10:34:51.278][000000000.543] I/user.main tfcard 001.999.000
[2026-05-15 10:34:51.283][000000000.588] W/user.HTTP上传 等待网络连接 1 3
[2026-05-15 10:34:51.904][000000001.589] W/user.HTTP上传 等待网络连接 1 3
[2026-05-15 10:34:52.896][000000002.590] W/user.HTTP上传 等待网络连接 1 3
[2026-05-15 10:34:53.905][000000003.591] W/user.HTTP上传 等待网络连接 1 3
[2026-05-15 10:34:54.904][000000004.592] W/user.HTTP上传 等待网络连接 1 3
[2026-05-15 10:34:55.974][000000005.597] I/user.HTTP上传 网络已就绪 1 3
[2026-05-15 10:34:55.978][000000005.598] SPI_HWInit 445:APB MP 102400000
[2026-05-15 10:34:55.982][000000005.598] SPI_HWInit 556:spi1 speed 2000000,1994805,154
[2026-05-15 10:34:55.987][000000005.598] D/fatfs init sdcard at spi=1 cs=12
[2026-05-15 10:34:56.058][000000005.753] D/SPI_TF 卡容量 3932160KB
[2026-05-15 10:34:56.062][000000005.753] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 10:34:56.074][000000005.757] I/fatfs mount success at fat32
[2026-05-15 10:34:56.077][000000005.760] I/user.HTTP上传 准备上传文件 /sd/3_23MB.bin 大小: 3389723 字节
[2026-05-15 10:34:56.082][000000005.760] I/user.HTTP上传 开始上传任务
[2026-05-15 10:34:56.086][000000005.766] D/socket connect to airtest.luatos.com,443
[2026-05-15 10:34:56.089][000000005.766] dns_run 676:airtest.luatos.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-05-15 10:34:56.092][000000005.768] D/mobile cid1, state0
[2026-05-15 10:34:56.095][000000005.768] D/mobile bearer act 0, result 0
[2026-05-15 10:34:56.098][000000005.769] D/mobile NETIF_LINK_ON -> IP_READY
[2026-05-15 10:34:56.100][000000005.769] D/mobile TIME_SYNC 0 tm 1778812495
[2026-05-15 10:34:56.184][000000005.868] dns_run 693:dns all done ,now stop
[2026-05-15 10:34:56.993][000000006.663] I/zbuff create large size: 128 kbyte, trigger force GC
[2026-05-15 10:35:41.048][000000050.717] I/user.httpplus 服务器已完成响应
[2026-05-15 10:35:41.054][000000050.720] I/user.HTTP上传 上传完成 success 200
[2026-05-15 10:35:41.060][000000050.721] I/user.HTTP上传 服务器响应头 {"Content-Length":"257","Date":"Fri, 15 May 2026 02:35:40 GMT","Connection":"close","Server":"nginx/1.28.2","Vary":"Access-Control-Request-Headers","Content-Type":"application/x-www-form-urlencoded;charset=UTF-8"}
[2026-05-15 10:35:41.071][000000050.721] I/user.HTTP上传 服务器响应体长度 257
[2026-05-15 10:35:41.089][000000050.722] I/user.HTTP上传 服务器响应内容 {"info":"iot->iam-server./iam/tenant/getbyoid/6268048492107342913./iot/luat_test_file/add","code":0,"trace":"iot->iam-server./iam/tenant/getbyoid/6268048492107342913./iot/luat_test_file/add trcace:clear 1 temp suc infos.","log":"^^^","value":"上传成功"}
[2026-05-15 10:35:41.097][000000050.722] I/user.HTTP上传 资源清理完成

```