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
- 加载ch390_manager模块（通过require "ch390_manager"）。
- 加载tfcard_app模块（通过require "tfcard_app"）
- 加载http_download_file模块（通过require "http_download_file"）
- 最后运行sys.run()。

### 2、CH390控制模块（ch390_manager.lua）

在Air8000开发板上，spi1上同时外挂了tf卡和ch390h以太网芯片两种spi从设备，这两种外设通过不同的cs引脚区分；
测试tf功能前，需要将ch390h的cs引脚拉高，这样可以保证ch390h不会干扰到tf功能；
- 控制CH390供电引脚（GPIO140）的开关
- 控制CH390片选引脚（GPIO12）的电平状态


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

1、Air8000整机开发板一块

2、sim卡一张

3、TYPE-C USB数据线一根

4、闪迪C10高速TF卡一张（即micro SD卡，即微型SD卡）

5、Air8000整机开发板和数据线的硬件接线方式为

- Air8000整机开发板通过TYPE-C USB口供电；（USB旁边的开关拨到USB供电）
- TYPE-C USB数据线直接插到Air8000整机开发板的TYPE-C USB座子，另外一端连接电脑USB口；

## **演示软件环境**

1、Luatools下载调试工具：https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：https://docs.openluat.com/air8000/luatos/firmware/

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印

```lua
（1）TF卡初始化与挂载
[2025-08-24 19:51:24.152][000000001.389] SPI_HWInit 552:spi1 speed 2000000,1994805,154
[2025-08-24 19:51:24.213][000000002.390] D/fatfs init sdcard at spi=1 cs=20
[2025-08-24 19:51:24.286][000000002.390] SPI_SetNewConfig 996:spi1 speed 400000,400000
[2025-08-24 19:51:24.329][000000002.408] SPI_SetNewConfig 996:spi1 speed 24000000,25600000
[2025-08-24 19:51:24.383][000000002.408] D/SPI_TF 卡容量 122138624KB
[2025-08-24 19:51:24.430][000000002.408] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2025-08-24 19:51:24.477][000000002.412] I/user.fatfs.mount 挂载成功 0
[2025-08-24 19:51:24.535][000000002.617] I/user.fatfs getfree {"free_sectors":244262144,"total_kb":122132480,"free_kb":122131072,"total_sectors":244264960}
[2025-08-24 19:51:24.583][000000002.618] I/user.fs lsmount [{"fs":"ec7xx","path":""},{"fs":"inline","path":"\/lua\/"},{"fs":"ram","path":"\/ram\/"},{"fs":"luadb","path":"\/luadb\/"},{"fs":"fatfs","path":"\/sd"}]


（2）文件操作演示
[2025-08-24 19:51:24.685][000000002.619] I/user.文件操作 ===== 开始文件操作 =====
[2025-08-24 19:51:25.145][000000003.032] I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2025-08-24 19:51:25.231][000000003.043] I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2025-08-24 19:51:25.297][000000003.046] I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2025-08-24 19:51:25.376][000000003.049] I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2025-08-24 19:51:25.467][000000003.052] I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2025-08-24 19:51:25.547][000000003.056] I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2025-08-24 19:51:25.616][000000003.056] I/user.启动计数 当前值: 0
[2025-08-24 19:51:25.693][000000003.057] I/user.启动计数 更新值: 1
[2025-08-24 19:51:25.736][000000003.068] I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2025-08-24 19:51:25.795][000000003.081] I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2025-08-24 19:51:25.852][000000003.088] I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2025-08-24 19:51:25.909][000000003.091] I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2025-08-24 19:51:25.954][000000003.102] I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2025-08-24 19:51:26.001][000000003.106] I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2025-08-24 19:51:26.048][000000003.106] I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2025-08-24 19:51:26.093][000000003.107] I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2025-08-24 19:51:26.140][000000003.112] I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2025-08-24 19:51:26.188][000000003.116] D/fatfs f_open /io_test/test_a 4
[2025-08-24 19:51:26.238][000000003.116] D/vfs fopen /sd/io_test/test_a r not found
[2025-08-24 19:51:26.312][000000003.117] I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2025-08-24 19:51:26.367][000000003.117] I/user.目录操作 ===== 开始目录列举 =====
[2025-08-24 19:51:26.424][000000003.121] I/user.fs lsdir [{"name":"boottime","size":0,"type":0},{"name":"testline","size":0,"type":0},{"name":"renamed_file.txt","size":0,"type":0}]
[2025-08-24 19:51:26.478][000000003.127] I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2025-08-24 19:51:26.539][000000003.129] D/fatfs f_open /io_test/renamed_file.txt 4
[2025-08-24 19:51:26.593][000000003.130] D/vfs fopen /sd/io_test/renamed_file.txt r not found
[2025-08-24 19:51:26.656][000000003.130] I/user.验证结果 renamed_file.txt文件删除验证成功
[2025-08-24 19:51:26.734][000000003.137] I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2025-08-24 19:51:26.856][000000003.139] D/fatfs f_open /io_test/testline 4
[2025-08-24 19:51:26.922][000000003.140] D/vfs fopen /sd/io_test/testline r not found
[2025-08-24 19:51:27.113][000000003.140] I/user.验证结果 testline文件删除验证成功
[2025-08-24 19:51:27.197][000000003.147] I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2025-08-24 19:51:27.251][000000003.149] D/fatfs f_open /io_test/boottime 4
[2025-08-24 19:51:27.302][000000003.150] D/vfs fopen /sd/io_test/boottime r not found
[2025-08-24 19:51:27.365][000000003.150] I/user.验证结果 boottime文件删除验证成功
[2025-08-24 19:51:27.407][000000003.158] I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2025-08-24 19:51:27.461][000000003.159] D/fatfs f_open /io_test 4
[2025-08-24 19:51:27.536][000000003.159] D/vfs fopen /sd/io_test r not found
[2025-08-24 19:51:27.610][000000003.159] I/user.验证结果 目录删除验证成功
[2025-08-24 19:51:27.668][000000003.160] I/user.文件操作 ===== 文件操作完成 =====
[2025-08-24 19:51:27.712][000000003.160] I/user.系统清理 开始执行关闭操作...
[2025-08-24 19:51:27.772][000000003.160] I/user.文件系统 卸载成功
[2025-08-24 19:51:27.867][000000003.160] I/user.SPI接口 已关闭


（3）网络连接与HTTP下载
[2025-08-24 20:31:49.405][000000006.268] I/user.HTTP下载 开始下载任务
[2025-08-24 20:31:49.438][000000006.275] dns_run 674:gitee.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-08-24 20:31:49.471][000000006.277] D/mobile TIME_SYNC 0
[2025-08-24 20:31:49.503][000000006.297] dns_run 691:dns all done ,now stop
[2025-08-24 20:31:54.800][000000012.080] I/user.HTTP下载 下载完成 success 200 
[2025-08-24 20:31:54.872][000000012.080] {"Age":"0","Cache-Control":"public, max-age=60","Via":"1.1 varnish","Transfer-Encoding":"chunked","Date":"Sun, 24 Aug 2025 12:31:49 GMT","Access-Control-Allow-Credentials":"true","Vary":"Accept-Encoding","X-Served-By":"cache-ffe9","X-Gitee-Server":"http-pilot 1.9.21","Connection":"keep-alive","Server":"ADAS\/1.0.214","Access-Control-Allow-Headers":"Accept,Authorization,Cache-Control,Content-Type,DNT,If-Modified-Since,Keep-Alive,Origin,User-Agent,X-Requested-With,X-CustomHeader,Content-Range,Range,Set-Language","Content-Security-Policy":"default-src 'none'; style-src 'unsafe-inline'; sandbox","X-Request-Id":"1f7e4b55-53c8-440a-9806-8894aa823f50","Accept-Ranges":"bytes","Etag":"W\/\"6ea36a6c51a48eaba0ffbc01d409424e7627bc56\"","Content-Type":"text\/plain; charset=utf-8","Access-Control-Allow-Methods":"GET, POST, PUT, PATCH, DELETE, OPTIONS","X-Frame-Options":"DENY","X-Cache":"MISS","Set-Cookie":"BEC=1f1759df3ccd099821dcf0da6feb0357;Path=\/;Max-Age=126000"}
[2025-08-24 20:31:54.910][000000012.080]  411922
[2025-08-24 20:31:54.936][000000012.082] I/user.HTTP下载 文件大小验证 预期: 411922 实际: 411922
[2025-08-24 20:31:54.979][000000012.083] I/user.HTTP下载 资源清理完成

（4）网络连接与HTTP上传
[2025-09-24 18:07:54.587][000000000.360] I/user.main tfcard 001.000.000
[2025-09-24 18:07:54.601][000000000.396] W/user.HTTP上传 等待网络连接 1 3
[2025-09-24 18:07:56.758][000000004.693] D/mobile cid1, state0
[2025-09-24 18:07:56.763][000000004.694] D/mobile bearer act 0, result 0
[2025-09-24 18:07:56.774][000000004.695] D/mobile NETIF_LINK_ON -> IP_READY
[2025-09-24 18:07:56.779][000000004.696] I/user.HTTP上传 网络已就绪 1 3
[2025-09-24 18:07:56.791][000000004.696] SPI_HWInit 552:spi1 speed 2000000,1994805,154
[2025-09-24 18:07:56.796][000000004.697] D/fatfs init sdcard at spi=1 cs=20
[2025-09-24 18:07:56.809][000000004.716] D/SPI_TF 卡容量 122138624KB
[2025-09-24 18:07:56.828][000000004.716] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2025-09-24 18:07:56.833][000000004.725] I/user.HTTP上传 准备上传文件 /sd/30M_test.txt 大小: 31467520 字节
[2025-09-24 18:07:56.852][000000004.725] I/user.HTTP上传 开始上传任务
[2025-09-24 18:07:56.860][000000004.730] D/socket connect to airtest.openluat.com,2900
[2025-09-24 18:07:56.865][000000004.731] dns_run 676:airtest.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-09-24 18:07:56.869][000000004.799] dns_run 693:dns all done ,now stop
[2025-09-24 18:07:56.885][000000004.881] soc_cms_proc 2189:cenc report 1,51,1,15
[2025-09-24 18:07:57.063][000000005.068] D/mobile NETIF_LINK_ON -> IP_READY
[2025-09-24 18:07:58.364][000000006.364] D/mobile ims reg state 0
[2025-09-24 18:07:58.375][000000006.365] D/mobile LUAT_MOBILE_EVENT_CC status 0
[2025-09-24 18:07:58.385][000000006.365] D/mobile LUAT_MOBILE_CC_READY
[2025-09-24 18:09:32.042][000000100.039] I/user.httpplus 等待服务器完成响应
[2025-09-24 18:09:32.135][000000100.135] I/user.httpplus 等待服务器完成响应
[2025-09-24 18:09:32.982][000000100.973] I/user.httpplus 服务器已完成响应,开始解析响应
[2025-09-24 18:09:32.997][000000100.998] I/user.HTTP上传 上传完成 success 200
[2025-09-24 18:09:33.004][000000100.998] I/user.HTTP上传 服务器响应头 {"Content-Type":"text\/plain;charset=UTF-8","Connection":"close","Content-Length":"20","Vary":"Access-Control-Request-Headers","Date":"Wed, 24 Sep 2025 10"}
[2025-09-24 18:09:33.011][000000100.999] I/user.HTTP上传 服务器响应体长度 20
[2025-09-24 18:09:33.021][000000101.000] I/user.HTTP上传 服务器响应内容 uploadFileToStaticOK
[2025-09-24 18:09:33.027][000000101.000] I/user.HTTP上传 资源清理完成
```