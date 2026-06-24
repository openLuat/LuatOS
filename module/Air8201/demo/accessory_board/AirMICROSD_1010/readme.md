## **功能模块介绍**

本demo演示了在嵌入式环境中对TF卡（SD卡）的完整操作流程，覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为两个核心模块：

1、main.lua：主程序入口 <br> 
2、tfcard_app.lua：TF卡基础应用模块，实现文件系统管理、文件操作和目录管理功能<br> 
3、http_download_file.lua：HTTP下载模块，实现网络检测与文件下载到TF卡的功能<br> 
4、http_upload_file.lua：HTTP上传模块，实现网络检测与文件上传到服务器的功能<br> 

**注意事项：**使用大牌卡，杜邦线或者飞线测试时速率不能超过10M，自己画板走线速率实测可以到24M

## **演示功能概述**

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载tfcard_app模块（通过require "tfcard_app"）
- 加载http_download_file模块（通过require "http_download_file"）
- 加载http_upload_file模块（通过require "http_upload_file"）
- 最后运行sys.run()。



### 2、TF卡核心演示模块（tfcard_app.lua）

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

### 3、HTTP下载功能 (http_download_file.lua)

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


### 4、HTTP上传功能 (http_upload_file.lua)

#### 文件系统管理

- SPI初始化与挂载

#### 网络就绪检测

- 1秒循环等待IP就绪
- 网络故障处理机制

#### 安全上传

- HTTP上传

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 资源清理（卸载/spi关闭）


## 演示硬件环境

### Air780EHM核心板演示环境

1、Air780EHM核心板一块(Air780EHM/780EGH/780EHV三种模块的核心板接线方式相同，这里以Air780EHM为例)

2、TYPE-C USB数据线一根

3、AirMICROSD_1010模块一个和SD卡一张

4、SIM卡一张

5、Air780EHM/780EGH/780EHV核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

6、Air780EHM核心板和AirMICROSD_1010模块接线方式

|   Air780EHM     |    AirMICROSD_1010    |
| --------------- | --------------------- |
|  GND(任意)      |          GND          |
|  VDD_EXT        |          3V3         |
|  GPIO8/SPI0_CS  |        spi_cs       |
|  SPI0_CLK       |        spi_clk,时钟       |
|  SPI0_MOSI      |  spi_mosi,主机输出,从机输入|
|  SPI0_MISO      |  spi_miso,主机输入,从机输出|


## 演示软件环境

1、Luatools下载调试工具： https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：
Air780EHM:https://docs.openluat.com/air780epm/luatos/firmware/version/
Air780EGH:https://docs.openluat.com/air780egh/luatos/firmware/version/
Air780EHV:https://docs.openluat.com/air780ehv/luatos/firmware/version/


## 演示核心步骤
1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板或开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```lua
（1）TF卡初始化与挂载
[2026-05-15 11:07:51.970][000000000.245] I/user.main tfcard 001.999.000
[2026-05-15 11:07:51.971][000000000.252] SPI_HWInit 445:APB MP 102400000
[2026-05-15 11:07:51.972][000000000.252] SPI_HWInit 556:spi0 speed 2000000,1994805,154
[2026-05-15 11:07:51.973][000000000.253] D/fatfs init sdcard at spi=0 cs=8
[2026-05-15 11:07:51.978][000000000.491] D/SPI_TF 卡容量 3932160KB
[2026-05-15 11:07:51.980][000000000.491] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 11:07:51.981][000000000.496] I/fatfs mount success at fat32
[2026-05-15 11:07:51.983][000000000.496] I/user.fatfs.mount 挂载成功 0
[2026-05-15 11:07:51.985][000000000.497] I/user.fatfs getfree {"free_sectors":7841920,"total_kb":3931584,"free_kb":3920960,"total_sectors":7863168}
[2026-05-15 11:07:51.986][000000000.498] I/user.fs lsmount [{"fs":"ec7xx","path":""},{"fs":"inline","path":"/lua/"},{"fs":"ram","path":"/ram/"},{"fs":"luadb","path":"/luadb/"},{"fs":"fatfs","path":"/sd"}]



（2）文件操作演示
[2026-05-15 11:07:51.988][000000000.498] I/user.文件操作 ===== 开始文件操作 =====
[2026-05-15 11:07:52.128][000000000.804] I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2026-05-15 11:07:52.274][000000000.858] I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2026-05-15 11:07:52.277][000000000.862] I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2026-05-15 11:07:52.281][000000000.866] I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2026-05-15 11:07:52.284][000000000.872] I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2026-05-15 11:07:52.288][000000000.877] I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2026-05-15 11:07:52.291][000000000.878] I/user.启动计数 当前值: 0
[2026-05-15 11:07:52.294][000000000.879] I/user.启动计数 更新值: 1
[2026-05-15 11:07:52.297][000000000.919] I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2026-05-15 11:07:52.314][000000000.997] I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2026-05-15 11:07:52.330][000000001.011] I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2026-05-15 11:07:52.345][000000001.018] I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2026-05-15 11:07:52.376][000000001.052] I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2026-05-15 11:07:52.380][000000001.057] I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2026-05-15 11:07:52.383][000000001.058] I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2026-05-15 11:07:52.386][000000001.059] I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2026-05-15 11:07:52.392][000000001.069] I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2026-05-15 11:07:52.395][000000001.076] D/fatfs f_open /io_test/test_a 4
[2026-05-15 11:07:52.398][000000001.077] D/vfs fopen /sd/io_test/test_a r not found
[2026-05-15 11:07:52.401][000000001.077] I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2026-05-15 11:07:52.404][000000001.077] I/user.目录操作 ===== 开始目录列举 =====
[2026-05-15 11:07:52.412][000000001.093] I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"testline","size":15,"type":0},{"name":"renamed_file.txt","size":6,"type":0}]
[2026-05-15 11:07:52.438][000000001.113] I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2026-05-15 11:07:52.442][000000001.117] D/fatfs f_open /io_test/renamed_file.txt 4
[2026-05-15 11:07:52.446][000000001.118] D/vfs fopen /sd/io_test/renamed_file.txt r not found
[2026-05-15 11:07:52.450][000000001.118] I/user.验证结果 renamed_file.txt文件删除验证成功
[2026-05-15 11:07:52.454][000000001.135] I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2026-05-15 11:07:52.457][000000001.139] D/fatfs f_open /io_test/testline 4
[2026-05-15 11:07:52.460][000000001.139] D/vfs fopen /sd/io_test/testline r not found
[2026-05-15 11:07:52.463][000000001.139] I/user.验证结果 testline文件删除验证成功
[2026-05-15 11:07:52.485][000000001.158] I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2026-05-15 11:07:52.488][000000001.161] D/fatfs f_open /io_test/boottime 4
[2026-05-15 11:07:52.491][000000001.162] D/vfs fopen /sd/io_test/boottime r not found
[2026-05-15 11:07:52.495][000000001.162] I/user.验证结果 boottime文件删除验证成功
[2026-05-15 11:07:52.500][000000001.180] I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2026-05-15 11:07:52.503][000000001.182] D/fatfs f_open /io_test 4
[2026-05-15 11:07:52.506][000000001.183] D/vfs fopen /sd/io_test r not found
[2026-05-15 11:07:52.509][000000001.183] I/user.验证结果 目录删除验证成功
[2026-05-15 11:07:52.512][000000001.183] I/user.文件操作 ===== 文件操作完成 =====
[2026-05-15 11:07:52.515][000000001.184] I/user.结束 开始执行关闭操作...
[2026-05-15 11:07:52.519][000000001.184] I/user.文件系统 卸载成功
[2026-05-15 11:07:52.523][000000001.185] I/user.SPI接口 已关闭



（3）网络连接与HTTP下载
[2026-05-15 11:09:05.686][000000000.408] I/user.main tfcard 001.999.000
[2026-05-15 11:09:05.691][000000000.413] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 11:09:06.216][000000001.414] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 11:09:07.206][000000002.415] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 11:09:08.202][000000003.416] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 11:09:09.251][000000004.459] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 11:09:10.248][000000005.460] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 11:09:10.584][000000005.728] I/mobile sim0 sms ready
[2026-05-15 11:09:10.587][000000005.728] D/mobile cid1, state0
[2026-05-15 11:09:10.590][000000005.729] D/mobile bearer act 0, result 0
[2026-05-15 11:09:10.594][000000005.729] D/mobile NETIF_LINK_ON -> IP_READY
[2026-05-15 11:09:10.598][000000005.730] I/user.HTTP下载 网络已就绪 1 1
[2026-05-15 11:09:10.603][000000005.731] SPI_HWInit 445:APB MP 102400000
[2026-05-15 11:09:10.606][000000005.731] SPI_HWInit 556:spi0 speed 2000000,1994805,154
[2026-05-15 11:09:10.609][000000005.732] D/fatfs init sdcard at spi=0 cs=8
[2026-05-15 11:09:10.754][000000005.971] D/SPI_TF 卡容量 3932160KB
[2026-05-15 11:09:10.757][000000005.971] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 11:09:10.771][000000005.976] I/fatfs mount success at fat32
[2026-05-15 11:09:10.774][000000005.976] I/user.HTTP下载 开始下载任务
[2026-05-15 11:09:10.777][000000005.981] dns_run 676:cdn.openluat-erp.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-05-15 11:09:10.779][000000005.982] D/mobile TIME_SYNC 0 tm 1778814555
[2026-05-15 11:09:10.878][000000006.083] dns_run 693:dns all done ,now stop
[2026-05-15 11:09:42.091][000000037.297] I/http http close c116480
[2026-05-15 11:09:42.094][000000037.299] I/user.HTTP下载 下载完成 success 200 
[2026-05-15 11:09:42.097][000000037.299] {"x-oss-hash-crc64ecma":"7570337686322137116","x-oss-server-time":"98","x-oss-object-type":"Normal","Content-Length":"3389723","Via":"cache17.l2cn1811[221,221,200-0,M], cache8.l2cn1811[222,0], kunlun4.cn8966[308,308,200-0,M], kunlun7.cn8966[311,0]","x-oss-cdn-auth":"success","Date":"Fri, 15 May 2026 03:09:16 GMT","x-oss-request-id":"6A068E5C28E012383718EF2E","Content-MD5":"Ap894+Aw36xpOHjjgfW0Cw==","Last-Modified":"Wed, 03 Sep 2025 07:26:20 GMT","Connection":"close","Server":"Tengine","ETag":"\"029F3DE3E030DFAC693878E381F5B40B\"","Timing-Allow-Origin":"*","X-Swift-CacheTime":"3600","Accept-Ranges":"bytes","x-oss-storage-class":"Standard","Content-Type":"application/octet-stream","X-Swift-SaveTime":"Fri, 15 May 2026 03:09:16 GMT","X-Cache":"MISS TCP_MISS dirn:-2:-2","Ali-Swift-Global-Savetime":"1778814556","EagleId":"701ddd0c17788145560227713e"}
[2026-05-15 11:09:42.105][000000037.300]  3389723
[2026-05-15 11:09:42.107][000000037.302] I/user.HTTP下载 文件大小验证 预期: 3389723 实际: 3389723
[2026-05-15 11:09:42.110][000000037.303] I/user.HTTP下载 资源清理完成


（4）网络连接与HTTP上传
[2026-05-15 11:12:32.423][000000000.458] I/user.main tfcard 001.999.000
[2026-05-15 11:12:32.428][000000000.472] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 11:12:32.995][000000001.473] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 11:12:33.996][000000002.474] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 11:12:34.994][000000003.475] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 11:12:36.002][000000004.476] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 11:12:36.994][000000005.477] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 11:12:37.298][000000005.721] I/mobile sim0 sms ready
[2026-05-15 11:12:37.300][000000005.722] D/mobile cid1, state0
[2026-05-15 11:12:37.303][000000005.722] D/mobile bearer act 0, result 0
[2026-05-15 11:12:37.307][000000005.723] D/mobile NETIF_LINK_ON -> IP_READY
[2026-05-15 11:12:37.309][000000005.724] I/user.HTTP上传 网络已就绪 1 1
[2026-05-15 11:12:37.311][000000005.724] SPI_HWInit 445:APB MP 102400000
[2026-05-15 11:12:37.315][000000005.724] SPI_HWInit 556:spi0 speed 2000000,1994805,154
[2026-05-15 11:12:37.319][000000005.725] D/fatfs init sdcard at spi=0 cs=8
[2026-05-15 11:12:37.396][000000005.876] D/SPI_TF 卡容量 3932160KB
[2026-05-15 11:12:37.399][000000005.876] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 11:12:37.412][000000005.881] I/fatfs mount success at fat32
[2026-05-15 11:12:37.416][000000005.883] I/user.HTTP上传 准备上传文件 /sd/3_23MB.bin 大小: 3389723 字节
[2026-05-15 11:12:37.420][000000005.883] I/user.HTTP上传 开始上传任务
[2026-05-15 11:12:37.424][000000005.889] D/socket connect to airtest.luatos.com,443
[2026-05-15 11:12:37.428][000000005.890] dns_run 676:airtest.luatos.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-05-15 11:12:37.432][000000005.892] D/mobile TIME_SYNC 0 tm 1778814761
[2026-05-15 11:12:37.579][000000006.052] dns_run 693:dns all done ,now stop
[2026-05-15 11:12:38.103][000000006.583] I/zbuff create large size: 128 kbyte, trigger force GC
[2026-05-15 11:13:13.337][000000041.808] I/user.httpplus 服务器已完成响应
[2026-05-15 11:13:13.340][000000041.811] I/user.HTTP上传 上传完成 success 200
[2026-05-15 11:13:13.342][000000041.812] I/user.HTTP上传 服务器响应头 {"Content-Length":"257","Date":"Fri, 15 May 2026 03:13:17 GMT","Connection":"close","Server":"nginx/1.28.2","Vary":"Access-Control-Request-Headers","Content-Type":"application/x-www-form-urlencoded;charset=UTF-8"}
[2026-05-15 11:13:13.352][000000041.813] I/user.HTTP上传 服务器响应体长度 257
[2026-05-15 11:13:13.355][000000041.813] I/user.HTTP上传 服务器响应内容 {"info":"iot->iam-server./iam/tenant/getbyoid/6268048492107342913./iot/luat_test_file/add","code":0,"trace":"iot->iam-server./iam/tenant/getbyoid/6268048492107342913./iot/luat_test_file/add trcace:clear 1 temp suc infos.","log":"^^^","value":"上传成功"}
[2026-05-15 11:13:13.358][000000041.814] I/user.HTTP上传 资源清理完成

```