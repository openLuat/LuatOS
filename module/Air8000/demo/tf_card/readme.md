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

### 4、HTTP上传功能 (http_download_file.lua)

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
[2026-04-09 15:48:51.057][000000000.372] I/user.main tfcard 001.999.000
[2026-04-09 15:48:51.064][000000000.393] I/user.exmux 开发板 DEV_BOARD_8000_V2.0 初始化成功
[2026-04-09 15:48:51.072][000000000.394] I/user.exmux 设置引脚 cs2 (20) 为高电平
[2026-04-09 15:48:51.081][000000000.394] I/user.exmux 设置引脚 cs1 (12) 为高电平
[2026-04-09 15:48:51.087][000000000.394] I/user.exmux 设置引脚 pwr1 (140) 为高电平
[2026-04-09 15:48:51.094][000000000.400] I/user.exmux 分组 spi1 打开成功
[2026-04-09 15:48:51.101][000000000.400] SPI_HWInit 445:APB MP 102400000
[2026-04-09 15:48:51.107][000000000.400] SPI_HWInit 556:spi1 speed 2000000,1994805,154
[2026-04-09 15:48:51.115][000000000.401] D/fatfs init sdcard at spi=1 cs=20
[2026-04-09 15:48:51.121][000000000.431] D/SPI_TF 卡容量 61076480KB
[2026-04-09 15:48:51.133][000000000.431] D/SPI_TF sdcard init OK OCR:0xc0ff8080!
[2026-04-09 15:48:51.141][000000000.434] I/fatfs mount success at fat32
[2026-04-09 15:48:51.151][000000000.435] I/user.fatfs.mount 挂载成功 0
[2026-04-09 15:48:51.162][000000000.436] I/user.fatfs getfree {"free_sectors":122137792,"total_kb":61068928,"free_kb":61068896,"total_sectors":122137856}
[2026-04-09 15:48:51.173][000000000.437] I/user.fs lsmount [{"fs":"ec7xx","path":""},{"fs":"inline","path":"/lua/"},{"fs":"ram","path":"/ram/"},{"fs":"luadb","path":"/luadb/"},{"fs":"fatfs","path":"/sd"}]




（2）文件操作演示
[2026-04-09 15:48:51.182][000000000.437] I/user.文件操作 ===== 开始文件操作 =====
[2026-04-09 15:48:51.192][000000000.517] I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2026-04-09 15:48:51.199][000000000.528] I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2026-04-09 15:48:51.213][000000000.531] I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2026-04-09 15:48:51.224][000000000.533] I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2026-04-09 15:48:51.232][000000000.535] I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2026-04-09 15:48:51.240][000000000.538] I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2026-04-09 15:48:51.249][000000000.539] I/user.启动计数 当前值: 0
[2026-04-09 15:48:51.258][000000000.539] I/user.启动计数 更新值: 1
[2026-04-09 15:48:51.264][000000000.553] I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2026-04-09 15:48:51.272][000000000.565] I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2026-04-09 15:48:51.279][000000000.571] I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2026-04-09 15:48:51.287][000000000.574] I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2026-04-09 15:48:51.295][000000000.585] I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2026-04-09 15:48:51.303][000000000.590] I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2026-04-09 15:48:51.311][000000000.590] I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2026-04-09 15:48:51.319][000000000.590] I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2026-04-09 15:48:51.326][000000000.595] I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2026-04-09 15:48:51.334][000000000.599] D/fatfs f_open /io_test/test_a 4
[2026-04-09 15:48:51.340][000000000.599] D/vfs fopen /sd/io_test/test_a r not found
[2026-04-09 15:48:51.348][000000000.599] I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2026-04-09 15:48:51.355][000000000.600] I/user.目录操作 ===== 开始目录列举 =====
[2026-04-09 15:48:51.363][000000000.607] I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"testline","size":15,"type":0},{"name":"renamed_file.txt","size":6,"type":0}]
[2026-04-09 15:48:51.370][000000000.613] I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2026-04-09 15:48:51.379][000000000.615] D/fatfs f_open /io_test/renamed_file.txt 4
[2026-04-09 15:48:51.385][000000000.616] D/vfs fopen /sd/io_test/renamed_file.txt r not found
[2026-04-09 15:48:51.390][000000000.616] I/user.验证结果 renamed_file.txt文件删除验证成功
[2026-04-09 15:48:51.466][000000000.634] I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2026-04-09 15:48:51.478][000000000.636] D/fatfs f_open /io_test/testline 4
[2026-04-09 15:48:51.496][000000000.636] D/vfs fopen /sd/io_test/testline r not found
[2026-04-09 15:48:51.507][000000000.636] I/user.验证结果 testline文件删除验证成功
[2026-04-09 15:48:51.519][000000000.643] I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2026-04-09 15:48:51.528][000000000.645] D/fatfs f_open /io_test/boottime 4
[2026-04-09 15:48:51.539][000000000.645] D/vfs fopen /sd/io_test/boottime r not found
[2026-04-09 15:48:51.553][000000000.645] I/user.验证结果 boottime文件删除验证成功
[2026-04-09 15:48:51.562][000000000.652] I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2026-04-09 15:48:51.570][000000000.653] D/fatfs f_open /io_test 4
[2026-04-09 15:48:51.578][000000000.654] D/vfs fopen /sd/io_test r not found
[2026-04-09 15:48:51.589][000000000.654] I/user.验证结果 目录删除验证成功
[2026-04-09 15:48:51.603][000000000.654] I/user.文件操作 ===== 文件操作完成 =====
[2026-04-09 15:48:51.611][000000000.654] I/user.结束 开始执行关闭操作...
[2026-04-09 15:48:51.618][000000000.654] I/user.文件系统 卸载成功
[2026-04-09 15:48:51.628][000000000.654] I/user.SPI接口 已关闭
[2026-04-09 15:48:51.637][000000000.655] I/user.exmux 设置引脚 cs2 (20) 为低电平
[2026-04-09 15:48:51.646][000000000.655] I/user.exmux 设置引脚 cs1 (12) 为低电平
[2026-04-09 15:48:51.655][000000000.656] I/user.exmux 设置引脚 pwr1 (140) 为低电平
[2026-04-09 15:48:51.667][000000000.661] I/user.exmux 分组 spi1 关闭成功




（3）网络连接与HTTP下载
[2026-04-09 15:52:26.603][000000000.375] I/user.main tfcard 001.999.000
[2026-04-09 15:52:26.609][000000000.393] W/user.HTTP下载 等待网络连接 1 3
[2026-04-09 15:52:31.671][000000006.822] I/mobile sim0 sms ready
[2026-04-09 15:52:31.677][000000006.822] D/mobile cid1, state0
[2026-04-09 15:52:31.686][000000006.823] D/mobile bearer act 0, result 0
[2026-04-09 15:52:31.691][000000006.823] D/mobile NETIF_LINK_ON -> IP_READY
[2026-04-09 15:52:31.698][000000006.824] I/user.HTTP下载 网络已就绪 1 3
[2026-04-09 15:52:31.707][000000006.825] I/user.exmux 开发板 DEV_BOARD_8000_V2.0 初始化成功
[2026-04-09 15:52:31.714][000000006.825] I/user.exmux 设置引脚 cs2 (20) 为高电平
[2026-04-09 15:52:31.720][000000006.826] I/user.exmux 设置引脚 cs1 (12) 为高电平
[2026-04-09 15:52:31.728][000000006.827] I/user.exmux 设置引脚 pwr1 (140) 为高电平
[2026-04-09 15:52:31.735][000000006.832] I/user.exmux 分组 spi1 打开成功
[2026-04-09 15:52:31.741][000000006.832] SPI_HWInit 445:APB MP 102400000
[2026-04-09 15:52:31.748][000000006.832] SPI_HWInit 556:spi1 speed 2000000,1994805,154
[2026-04-09 15:52:31.753][000000006.833] D/fatfs init sdcard at spi=1 cs=20
[2026-04-09 15:52:31.759][000000006.863] D/SPI_TF 卡容量 61076480KB
[2026-04-09 15:52:31.765][000000006.863] D/SPI_TF sdcard init OK OCR:0xc0ff8080!
[2026-04-09 15:52:31.771][000000006.866] I/fatfs mount success at fat32
[2026-04-09 15:52:31.778][000000006.867] I/user.HTTP下载 开始下载任务
[2026-04-09 15:52:31.786][000000006.871] dns_run 676:cdn.openluat-erp.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-04-09 15:52:31.793][000000006.884] D/mobile TIME_SYNC 0 tm 1775721152
[2026-04-09 15:52:31.799][000000006.929] dns_run 693:dns all done ,now stop
[2026-04-09 15:53:08.621][000000043.820] I/http http close c15177c
[2026-04-09 15:53:08.634][000000043.823] I/user.HTTP下载 下载完成 success 200 
[2026-04-09 15:53:08.641][000000043.823] {"x-oss-hash-crc64ecma":"7570337686322137116","x-oss-server-time":"240","x-oss-object-type":"Normal","Content-Length":"3389723","Via":"cache19.l2cn1812[427,426,200-0,M], cache17.l2cn1812[429,0], kunlun7.cn5134[574,574,200-0,M], kunlun9.cn5134[578,0]","x-oss-cdn-auth":"success","Date":"Thu, 09 Apr 2026 07:52:33 GMT","x-oss-request-id":"69D75AC17CC18135381F3CFC","Content-MD5":"Ap894+Aw36xpOHjjgfW0Cw==","Last-Modified":"Wed, 03 Sep 2025 07:26:20 GMT","Connection":"close","Server":"Tengine","ETag":"\"029F3DE3E030DFAC693878E381F5B40B\"","Timing-Allow-Origin":"*","X-Swift-CacheTime":"3600","Accept-Ranges":"bytes","x-oss-storage-class":"Standard","Content-Type":"application/octet-stream","X-Swift-SaveTime":"Thu, 09 Apr 2026 07:52:33 GMT","X-Cache":"MISS TCP_MISS dirn:-2:-2","Ali-Swift-Global-Savetime":"1775721153","EagleId":"6f1d0b1d17757211530756149e"}
[2026-04-09 15:53:08.674][000000043.823]  3389723
[2026-04-09 15:53:08.681][000000043.825] I/user.HTTP下载 文件大小验证 预期: 3389723 实际: 3389723
[2026-04-09 15:53:08.695][000000043.825] I/user.HTTP下载 资源清理完成
[2026-04-09 15:53:08.707][000000043.826] I/user.exmux 设置引脚 cs2 (20) 为低电平
[2026-04-09 15:53:08.717][000000043.827] I/user.exmux 设置引脚 cs1 (12) 为低电平
[2026-04-09 15:53:08.728][000000043.828] I/user.exmux 设置引脚 pwr1 (140) 为低电平
[2026-04-09 15:53:08.736][000000043.833] I/user.exmux 分组 spi1 关闭成功



（4）网络连接与HTTP上传
[2026-04-09 15:53:53.575][000000000.376] I/user.main tfcard 001.999.000
[2026-04-09 15:53:53.582][000000000.413] W/user.HTTP上传 等待网络连接 1 3
[2026-04-09 15:53:58.634][000000006.826] I/mobile sim0 sms ready
[2026-04-09 15:53:58.646][000000006.826] D/mobile cid1, state0
[2026-04-09 15:53:58.652][000000006.827] D/mobile bearer act 0, result 0
[2026-04-09 15:53:58.660][000000006.827] D/mobile NETIF_LINK_ON -> IP_READY
[2026-04-09 15:53:58.666][000000006.828] I/user.HTTP上传 网络已就绪 1 3
[2026-04-09 15:53:58.678][000000006.829] I/user.exmux 开发板 DEV_BOARD_8000_V2.0 初始化成功
[2026-04-09 15:53:58.686][000000006.829] I/user.exmux 设置引脚 cs2 (20) 为高电平
[2026-04-09 15:53:58.697][000000006.830] I/user.exmux 设置引脚 cs1 (12) 为高电平
[2026-04-09 15:53:58.709][000000006.831] I/user.exmux 设置引脚 pwr1 (140) 为高电平
[2026-04-09 15:53:58.720][000000006.835] I/user.exmux 分组 spi1 打开成功
[2026-04-09 15:53:58.733][000000006.836] SPI_HWInit 445:APB MP 102400000
[2026-04-09 15:53:58.744][000000006.836] SPI_HWInit 556:spi1 speed 2000000,1994805,154
[2026-04-09 15:53:58.750][000000006.837] D/fatfs init sdcard at spi=1 cs=20
[2026-04-09 15:53:58.758][000000006.867] D/SPI_TF 卡容量 61076480KB
[2026-04-09 15:53:58.767][000000006.867] D/SPI_TF sdcard init OK OCR:0xc0ff8080!
[2026-04-09 15:53:58.773][000000006.870] I/fatfs mount success at fat32
[2026-04-09 15:53:58.778][000000006.872] I/user.HTTP上传 准备上传文件 /sd/3_23MB.bin 大小: 3389723 字节
[2026-04-09 15:53:58.788][000000006.872] I/user.HTTP上传 开始上传任务
[2026-04-09 15:53:58.798][000000006.875] D/socket connect to airtest.openluat.com,2900
[2026-04-09 15:53:58.807][000000006.876] dns_run 676:airtest.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-04-09 15:53:58.815][000000006.879] D/mobile TIME_SYNC 0 tm 1775721239
[2026-04-09 15:53:58.822][000000006.922] dns_run 693:dns all done ,now stop
[2026-04-09 15:53:58.828][000000007.007] I/zbuff create large size: 128 kbyte, trigger force GC
[2026-04-09 15:54:14.206][000000022.488] I/user.httpplus 服务器已完成响应,开始解析响应
[2026-04-09 15:54:14.237][000000022.512] I/user.HTTP上传 上传完成 success 200
[2026-04-09 15:54:14.245][000000022.513] I/user.HTTP上传 服务器响应头 {"Content-Type":"text/plain;charset=UTF-8","Connection":"close","Content-Length":"20","Vary":"Access-Control-Request-Headers","Date":"Thu, 09 Apr 2026 07:54:14 GMT"}
[2026-04-09 15:54:14.254][000000022.513] I/user.HTTP上传 服务器响应体长度 20
[2026-04-09 15:54:14.264][000000022.514] I/user.HTTP上传 服务器响应内容 uploadFileToStaticOK
[2026-04-09 15:54:14.273][000000022.514] I/user.HTTP上传 资源清理完成
[2026-04-09 15:54:14.280][000000022.515] I/user.exmux 设置引脚 cs2 (20) 为低电平
[2026-04-09 15:54:14.288][000000022.515] I/user.exmux 设置引脚 cs1 (12) 为低电平
[2026-04-09 15:54:14.295][000000022.516] I/user.exmux 设置引脚 pwr1 (140) 为低电平
[2026-04-09 15:54:14.302][000000022.521] I/user.exmux 分组 spi1 关闭成功

```