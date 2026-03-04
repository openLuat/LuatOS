## **功能模块介绍**

本demo演示了在嵌入式环境中对TF卡（SD卡）的完整操作流程，覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为两个核心模块：

1、main.lua：主程序入口 <br> 
2、AirMICROSD_1010.lua：TF卡基础应用模块，实现文件系统管理、文件操作和目录管理功能。<br> 
3、http_download_file.lua：HTTP下载模块，实现网络检测与文件下载到TF卡的功能

## **演示功能概述**

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载AirMICROSD_1010模块（通过require "AirMICROSD_1010"）
- 加载http_download_file模块（通过require "http_download_file"）
- 最后运行sys.run()

### 2、TF卡核心演示模块（AirMICROSD_1010.lua）

#### 文件系统管理

- 挂载：
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

- 资源清理（卸载）

### 3、HTTP下载功能 (http_download_file.lua)

#### 文件系统管理

- 挂载sd卡

#### 网络就绪检测

- wifi链接
- 1秒循环等待IP就绪
- 网络故障处理机制

#### 安全下载

- HTTP下载

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 资源清理（卸载）

## **演示硬件环境**

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、闪迪C10高速TF卡一张（即micro SD卡，即微型SD卡）

4、AirMICROSD_1010配件板一块

5、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过板上的TYPE-C USB口供电。（正面的开关拨到3.3V，背面的开关拨到off）
- TYPE-C USB数据线直接插到Air8101核心板的TYPE-C USB座子，另外一端连接电脑USB口；

6、Air8101核心板与AirMICROSD_1010配件板通过杜邦线连接，对应管脚为
| Air8101/Air6101核心板 | AirMICROSD_1010配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3V3               |
| gnd           | gnd               |
| 65/GPIO2      | spi_clk           |
| 67/GPIO4      | spi_mosi          |
| 66/GPIO3      | spi_cs            |
| 8/GPIO5       | spi_miso          |

## **演示软件环境**

1、Luatools下载调试工具： https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：https://docs.openluat.com/air8101/luatos/firmware/

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印

```lua
（1）TF卡初始化与挂载
[2026-03-04 14:39:10.096] luat:U(702):I/user.fatfs.mount 挂载成功 0
[2026-03-04 14:39:10.096] luat:U(702):I/user.fatfs getfree {"free_sectors":122114816,"total_kb":61057440,"free_kb":61057408,"total_sectors":122114880}
[2026-03-04 14:39:10.096] luat:U(703):I/user.fs lsmount [{"fs":"lfs2","path":"/"},{"fs":"inline","path":"/lua/"},{"fs":"ram","path":"/ram/"},{"fs":"luadb","path":"/luadb/"},{"fs":"fatfs","path":"/sd"}]




（2）文件操作演示
[2026-03-04 14:39:10.096] luat:U(704):I/user.文件操作 ===== 开始文件操作 =====
[2026-03-04 14:39:10.245] luat:U(782):I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2026-03-04 14:39:10.245] luat:U(794):I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2026-03-04 14:39:10.245] luat:U(796):I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2026-03-04 14:39:10.245] luat:U(798):I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2026-03-04 14:39:10.245] luat:U(801):I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2026-03-04 14:39:10.245] luat:U(804):I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2026-03-04 14:39:10.245] luat:U(805):I/user.启动计数 当前值: 0
[2026-03-04 14:39:10.245] luat:U(805):I/user.启动计数 更新值: 1
[2026-03-04 14:39:10.245] luat:U(821):I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2026-03-04 14:39:10.245] luat:U(834):I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2026-03-04 14:39:10.245] luat:U(840):I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2026-03-04 14:39:10.245] luat:U(843):I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2026-03-04 14:39:10.324] luat:U(855):I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2026-03-04 14:39:10.324] luat:U(858):I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2026-03-04 14:39:10.324] luat:U(859):I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2026-03-04 14:39:10.324] luat:U(859):I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2026-03-04 14:39:10.324] luat:U(864):I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2026-03-04 14:39:10.324] luat:D(868):fatfs:f_open /io_test/test_a 4
[2026-03-04 14:39:10.324] luat:D(868):vfs:fopen /sd/io_test/test_a r not found
[2026-03-04 14:39:10.324] luat:U(868):I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2026-03-04 14:39:10.324] luat:U(868):I/user.目录操作 ===== 开始目录列举 =====
[2026-03-04 14:39:10.324] luat:U(875):I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"testline","size":15,"type":0},{"name":"renamed_file.txt","size":6,"type":0}]
[2026-03-04 14:39:10.324] luat:U(883):I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2026-03-04 14:39:10.324] luat:D(885):fatfs:f_open /io_test/renamed_file.txt 4
[2026-03-04 14:39:10.324] luat:D(885):vfs:fopen /sd/io_test/renamed_file.txt r not found
[2026-03-04 14:39:10.324] luat:U(885):I/user.验证结果 renamed_file.txt文件删除验证成功
[2026-03-04 14:39:10.324] luat:U(893):I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2026-03-04 14:39:10.324] luat:D(894):fatfs:f_open /io_test/testline 4
[2026-03-04 14:39:10.324] luat:D(895):vfs:fopen /sd/io_test/testline r not found
[2026-03-04 14:39:10.324] luat:U(895):I/user.验证结果 testline文件删除验证成功
[2026-03-04 14:39:10.324] luat:U(902):I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2026-03-04 14:39:10.324] luat:D(904):fatfs:f_open /io_test/boottime 4
[2026-03-04 14:39:10.324] luat:D(904):vfs:fopen /sd/io_test/boottime r not found
[2026-03-04 14:39:10.324] luat:U(904):I/user.验证结果 boottime文件删除验证成功
[2026-03-04 14:39:10.324] luat:U(913):I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2026-03-04 14:39:10.324] luat:D(914):fatfs:f_open /io_test 4
[2026-03-04 14:39:10.324] luat:D(914):vfs:fopen /sd/io_test r not found
[2026-03-04 14:39:10.324] luat:U(914):I/user.验证结果 目录删除验证成功
[2026-03-04 14:39:10.324] luat:U(914):I/user.文件操作 ===== 文件操作完成 =====
[2026-03-04 14:39:10.324] luat:U(914):I/user.结束 开始执行关闭操作...
[2026-03-04 14:39:10.324] luat:U(915):I/user.文件系统 卸载成功
[2026-03-04 14:39:10.324] luat:U(915):I/user.SPI接口 已关闭



（3）网络连接与HTTP下载
[2026-03-04 14:56:38.981] luat:U(3270):I/user.HTTP下载 开始下载任务
[2026-03-04 14:56:38.981] luat:D(3272):DNS:gitee.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-03-04 14:56:38.981] luat:D(3272):net:adatper 2 dns server 192.168.1.1
[2026-03-04 14:56:38.981] luat:D(3272):net:dns udp sendto 192.168.1.1:53 from 192.168.1.106
[2026-03-04 14:56:38.981] luat:I(3291):DNS:dns all done ,now stop
[2026-03-04 14:56:38.981] luat:D(3292):net:adapter 2 connect 180.76.199.13:443 TCP
[2026-03-04 14:56:39.382] luat:I(3739):http:event 00000005 -1 host gitee.com port 443
[2026-03-04 14:56:39.394] luat:W(3758):http:download fail, remove file /sd/1.mp3
[2026-03-04 14:56:39.427] luat:I(3777):http:http close 0x609c4cf8
[2026-03-04 14:56:39.427] luat:E(3780):http:http_ctrl is NULL for idg 1
[2026-03-04 14:56:39.441] luat:U(3781):I/user.HTTP下载 下载完成 error 404 luat:U(3781):{"BDWAF-Request-ID":"afd00252-f8a4-43d2-a638-2aa77f246231","X-Served-By":"cache-ffe9","Age":"0","Access-Control-Allow-Headers":"Accept,Authorization,Cache-Control,Content-Type,DNT,If-Modified-Since,Keep-Alive,Origin,User-Agent,X-Requested-With,X-CustomHeader,Content-Range,Range,Set-Language","Connection":"close","Content-Length":"47","Via":"1.1 varnish","Access-Control-Allow-Methods":"GET, POST, PUT, PATCH, DELETE, OPTIONS","X-Request-Id":"ffacb4ea-01ff-4cae-8c13-6931b988f002","Access-Control-Allow-Credentials":"true","X-Gitee-Server":"http-pilot 1.9.28","Content-Type":"text/plain; charset=UTF-8","X-Cache":"MISS","X-Frame-Options":"DENY","Date":"Wed, 04 Mar 2026 06:56:39 GMT","Server":"ADAS/1.0.214"}luat:U(3782): 47
[2026-03-04 14:56:39.441] luat:U(3782):I/user.HTTP下载 资源清理完成

```