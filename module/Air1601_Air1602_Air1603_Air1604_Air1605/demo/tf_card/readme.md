## 功能模块介绍：

本 demo 演示了在 Air1601 模组对 TF 卡（SD 卡）的完整操作流程，覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为以下核心模块：

1、main.lua：主程序入口

2、tfcard_app.lua：TF 卡基础应用模块，实现文件系统管理、文件操作和目录管理功能

3、http_download_file.lua：HTTP 下载模块，实现网络检测与文件下载到 TF 卡的功能

4、http_upload_file.lua：HTTP 上传模块，实现网络检测与 TF 卡内大文件上传服务器的功能

联网说明：当使用 HTTP 下载或者上传功能时，需先完成联网配置。需引入网卡驱动相关文件：

netdrv_device.lua/netdrv 文件夹：网卡驱动设备配置文件，可配置使用 netdrv 文件夹内的五种网卡（单 4G 网卡、单 WIFI 网卡、单 SPI 以太网卡、多网卡、PC 模拟器上的网卡）中的任意一种；


## 演示功能概述：

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

- 下载状态码解析
- 自动文件大小验证
- 资源清理（卸载/spi关闭）

## 演示硬件环境

![alt text](https://docs.openluat.com/air1601/luatos/common/hwenv/image/1280X1280.JPEG)

[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)

1、Air1601开发板一块+可上网的sim卡一张或者网线一根：

- sim卡插入开发板的sim卡槽

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线两根(使用4g或者wifi功能需要) ，Air1601开发板和数据线的硬件接线方式为：

- Air1601开发板通过USB口供电；

- TYPE-C USB数据线直接插到开发板的USB1口(串口下载)座子，另外一端连接电脑USB口；

拨码开关位置请参考[1601开发板使用说明](https://docs.openluat.com/air1601/product/shouce/) 2.2章节

3、使用4g airlink网络接线方式请参考[1601开发板使用说明](https://docs.openluat.com/air1601/product/shouce/) 2.4章节

4、使用以太网网络接线方式请参考[1601开发板使用说明](https://docs.openluat.com/air1601/product/shouce/) 2.8章节
## 演示软件环境

1、 Luatools下载调试工具：https://docs.openluat.com/air1601/luatos/common/download/

2、[Air1601 V1012版本固件](https://docs.openluat.com/air1601/luatos/firmware/)（理论上，2026年4月16日之后发布的固件都可以）


## 演示核心步骤

1、搭建好硬件环境

2、联网说明：当使用 HTTP 下载或者上传功能时，需先完成联网配置，在netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

* 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

* 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、如果使用自定义NTP服务器 地址，脚本文件ntp_test.lua中，在ntp_servers表中修改为自己的服务器地址。

4、通过Luatools将demo与固件烧录到开发板中

5、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印网络就绪、时间同步成功、本地时间以及URC时间等信息，如下log显示：

```lua
（1）TF卡初始化与挂载
[2026-04-21 18:51:42.407][CAPP/N][000000000.087]:spi_set_new_config 386:spi1 目标速度24000000 实际速度20000000 BR 20
[2026-04-21 18:51:42.409][LTOS/N][000000000.088]:D/SPI_TF 卡容量 3932160KB
[2026-04-21 18:51:42.412][LTOS/N][000000000.088]:D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-04-21 18:51:42.415][LTOS/N][000000000.091]:I/fatfs mount success at fat32
[2026-04-21 18:51:42.417][LTOS/N][000000000.092]:I/user.fatfs.mount 挂载成功 0
[2026-04-21 18:51:42.421][LTOS/N][000000000.092]:I/user.fatfs getfree {"free_sectors":7863104,"total_kb":3931584,"free_kb":3931552,"total_sectors":7863168}
[2026-04-21 18:51:42.424][LTOS/N][000000000.093]:I/user.fs lsmount [{"fs":"soc","path":""},{"fs":"inline","path":"/lua/"},{"fs":"luadb","path":"/luadb/"},{"fs":"ram","path":"/ram/"},{"fs":"fatfs","path":"/sd"}]
```

（2）文件操作演示
```lua
[2026-04-21 18:51:42.427][LTOS/N][000000000.093]:I/user.文件操作 ===== 开始文件操作 =====
[2026-04-21 18:51:42.450][LTOS/N][000000000.208]:I/airlink AIRLINK_READY 208 t 208
[2026-04-21 18:51:42.589][LTOS/N][000000000.354]:I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2026-04-21 18:51:42.619][LTOS/N][000000000.380]:I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2026-04-21 18:51:42.623][LTOS/N][000000000.383]:I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2026-04-21 18:51:42.626][LTOS/N][000000000.385]:I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2026-04-21 18:51:42.629][LTOS/N][000000000.389]:I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2026-04-21 18:51:42.632][LTOS/N][000000000.393]:I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2026-04-21 18:51:42.636][LTOS/N][000000000.393]:I/user.启动计数 当前值: 0
[2026-04-21 18:51:42.639][LTOS/N][000000000.393]:I/user.启动计数 更新值: 1
[2026-04-21 18:51:42.697][LTOS/N][000000000.452]:I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2026-04-21 18:51:42.728][LTOS/N][000000000.482]:I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2026-04-21 18:51:42.731][LTOS/N][000000000.495]:I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2026-04-21 18:51:42.734][LTOS/N][000000000.499]:I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2026-04-21 18:51:42.759][LTOS/N][000000000.525]:I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2026-04-21 18:51:42.762][LTOS/N][000000000.529]:I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2026-04-21 18:51:42.765][LTOS/N][000000000.530]:I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2026-04-21 18:51:42.768][LTOS/N][000000000.530]:I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2026-04-21 18:51:42.771][LTOS/N][000000000.540]:I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2026-04-21 18:51:42.790][LTOS/N][000000000.546]:D/fatfs f_open /io_test/test_a 4
[2026-04-21 18:51:42.793][LTOS/N][000000000.546]:D/vfs fopen /sd/io_test/test_a r not found
[2026-04-21 18:51:42.796][LTOS/N][000000000.546]:I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2026-04-21 18:51:42.799][LTOS/N][000000000.546]:I/user.目录操作 ===== 开始目录列举 =====
[2026-04-21 18:51:42.801][LTOS/N][000000000.556]:I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"testline","size":15,"type":0},{"name":"renamed_file.txt","size":6,"type":0}]
[2026-04-21 18:51:42.804][LTOS/N][000000000.571]:I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2026-04-21 18:51:42.808][LTOS/N][000000000.574]:D/fatfs f_open /io_test/renamed_file.txt 4
[2026-04-21 18:51:42.811][LTOS/N][000000000.574]:D/vfs fopen /sd/io_test/renamed_file.txt r not found
[2026-04-21 18:51:42.813][LTOS/N][000000000.574]:I/user.验证结果 renamed_file.txt文件删除验证成功
[2026-04-21 18:51:42.838][LTOS/N][000000000.591]:I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2026-04-21 18:51:42.841][LTOS/N][000000000.594]:D/fatfs f_open /io_test/testline 4
[2026-04-21 18:51:42.843][LTOS/N][000000000.594]:D/vfs fopen /sd/io_test/testline r not found
[2026-04-21 18:51:42.846][LTOS/N][000000000.594]:I/user.验证结果 testline文件删除验证成功
[2026-04-21 18:51:42.849][LTOS/N][000000000.616]:I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2026-04-21 18:51:42.852][LTOS/N][000000000.619]:D/fatfs f_open /io_test/boottime 4
[2026-04-21 18:51:42.855][LTOS/N][000000000.619]:D/vfs fopen /sd/io_test/boottime r not found
[2026-04-21 18:51:42.858][LTOS/N][000000000.619]:I/user.验证结果 boottime文件删除验证成功
[2026-04-21 18:51:42.869][LTOS/N][000000000.637]:I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2026-04-21 18:51:42.873][LTOS/N][000000000.638]:D/fatfs f_open /io_test 4
[2026-04-21 18:51:42.876][LTOS/N][000000000.638]:D/vfs fopen /sd/io_test r not found
[2026-04-21 18:51:42.878][LTOS/N][000000000.638]:I/user.验证结果 目录删除验证成功
[2026-04-21 18:51:42.881][LTOS/N][000000000.638]:I/user.文件操作 ===== 文件操作完成 =====
[2026-04-21 18:51:42.885][LTOS/N][000000000.639]:I/user.结束 开始执行关闭操作...
[2026-04-21 18:51:42.888][LTOS/N][000000000.639]:I/user.文件系统 卸载成功
[2026-04-21 18:51:42.891][LTOS/N][000000000.639]:I/user.SPI接口 已关闭
```

（3）网络连接与HTTP下载
```lua
[2026-05-15 18:48:54.264][CAPP/N][000000000.050]:Uart_ChangeBR 385:uart3 波特率 目标 2000000 实际 2000000
[2026-05-15 18:48:54.266][LTOS/N][000000000.050]:D/airlink 配置UART ID为 3
[2026-05-15 18:48:54.268][LTOS/N][000000000.050]:D/airlink 初始化AirLink
[2026-05-15 18:48:54.270][LTOS/N][000000000.050]:I/user.创建桥接网络设备
[2026-05-15 18:48:54.273][LTOS/N][000000000.051]:D/airlink 启动AirLink UART模式
[2026-05-15 18:48:54.275][CAPP/N][000000000.051]:soc_create_event_task 180:task airlink have 0 isr_event, total 64 static event
[2026-05-15 18:48:54.277][CAPP/N][000000000.056]:soc_create_event_task 180:task uart_transfer have 0 isr_event, total 64 static event
[2026-05-15 18:48:54.280][CAPP/N][000000000.057]:soc_create_event_task 180:task uart_receive have 0 isr_event, total 64 static event
[2026-05-15 18:48:54.282][LTOS/N][000000000.057]:I/netdrv 设置IP[15] 192.168.111.1 255.255.255.0 192.168.111.2 ret 0
[2026-05-15 18:48:54.284][LTOS/N][000000000.057]:I/user.netdrv 订阅socket连接状态变化事件 airlink_4G
[2026-05-15 18:48:54.286][LTOS/N][000000000.057]:I/user.airlink_4G网卡已开启 15
[2026-05-15 18:48:54.289][LTOS/N][000000000.058]:I/user.设置网卡 airlink_4G
[2026-05-15 18:48:54.292][LTOS/N][000000000.058]:I/user.exnetif publish network status airlink_4G 15
[2026-05-15 18:48:54.293][LTOS/N][000000000.064]:W/user.HTTP下载 等待网络连接 15 15
[2026-05-15 18:48:55.249][LTOS/N][000000001.065]:W/user.HTTP下载 等待网络连接 15 15
……
[2026-05-15 18:49:09.661][LTOS/N][000000015.476]:D/airlink 4G代理网卡上线了
[2026-05-15 18:49:09.663][LTOS/N][000000015.476]:D/netdrv 网卡(15)设置为UP
[2026-05-15 18:49:09.666][LTOS/N][000000015.476]:D/net network ready 15, setup dns server
[2026-05-15 18:49:09.668][LTOS/N][000000015.476]:D/netdrv IP_READY 15 192.168.111.1
[2026-05-15 18:49:09.670][LTOS/N][000000015.477]:D/net 设置DNS服务器 id 15 index 0 ip 223.5.5.5
[2026-05-15 18:49:09.673][LTOS/N][000000015.477]:D/net 设置DNS服务器 id 15 index 1 ip 114.114.114.114
[2026-05-15 18:49:09.675][LTOS/N][000000015.477]:I/user.netdrv_4g.ip_ready_func IP_READY 192.168.111.1 255.255.255.0 192.168.111.2 nil
[2026-05-15 18:49:09.677][LTOS/N][000000015.477]:I/user.dnsproxy 开始监听
[2026-05-15 18:49:09.680][LTOS/N][000000015.478]:I/user.HTTP下载 网络已就绪 15 15
[2026-05-15 18:49:09.682][CAPP/N][000000015.478]:spi_set_new_config 386:spi1 目标速度400000 实际速度375000 BR 45
[2026-05-15 18:49:09.685][LTOS/N][000000015.478]:D/fatfs init sdcard at spi=1 cs=8
[2026-05-15 18:49:09.693][CAPP/N][000000015.521]:spi_set_new_config 386:spi1 目标速度24000000 实际速度20000000 BR 20
[2026-05-15 18:49:09.695][LTOS/N][000000015.521]:D/SPI_TF 卡容量 3872256KB
[2026-05-15 18:49:09.698][LTOS/N][000000015.521]:D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 18:49:09.701][LTOS/N][000000015.525]:I/fatfs mount success at fat32
[2026-05-15 18:49:09.702][LTOS/N][000000015.526]:I/user.HTTP下载 开始下载任务
……
[2026-05-15 18:49:30.504][LTOS/N][000000036.320]:I/http http close 1c3cefe4
[2026-05-15 18:49:30.525][LTOS/N][000000036.321]:I/user.HTTP下载 下载完成 success 200 {"Content-Disposition":"attachment; filename=\"1.mp3\"","Accept-Ranges":"bytes","Date":"Fri, 15 May 2026 10:49:12 GMT","Content-Type":"audio/mpeg","Connection":"close","MD5":"EAA4E71C01B46EDE53D4E4BF9322058D","Vary":"Access-Control-Request-Headers","Content-Length":"411922"} 411922
[2026-05-15 18:49:30.531][LTOS/N][000000036.322]:I/user.HTTP下载 文件大小验证 预期: 411922 实际: 411922
[2026-05-15 18:49:30.536][LTOS/N][000000036.322]:I/user.HTTP下载 资源清理完成
```


（4）网络连接与HTTP上传
```lua
[2026-05-15 17:03:50.113][LTOS/N][000000000.016]:I/user.main tfcard 001.999.000
[2026-05-15 17:03:50.114][CAPP/N][000000000.050]:Uart_ChangeBR 385:uart3 波特率 目标 2000000 实际 2000000
[2026-05-15 17:03:50.117][LTOS/N][000000000.050]:D/airlink 配置UART ID为 3
[2026-05-15 17:03:50.119][LTOS/N][000000000.050]:D/airlink 初始化AirLink
[2026-05-15 17:03:50.120][LTOS/N][000000000.050]:I/user.创建桥接网络设备
[2026-05-15 17:03:50.122][LTOS/N][000000000.051]:D/airlink 启动AirLink UART模式
[2026-05-15 17:03:50.124][CAPP/N][000000000.051]:soc_create_event_task 180:task airlink have 0 isr_event, total 64 static event
[2026-05-15 17:03:50.126][CAPP/N][000000000.056]:soc_create_event_task 180:task uart_transfer have 0 isr_event, total 64 static event
[2026-05-15 17:03:50.127][CAPP/N][000000000.056]:soc_create_event_task 180:task uart_receive have 0 isr_event, total 64 static event
[2026-05-15 17:03:50.129][LTOS/N][000000000.057]:I/netdrv 设置IP[15] 192.168.111.1 255.255.255.0 192.168.111.2 ret 0
[2026-05-15 17:03:50.130][LTOS/N][000000000.057]:I/user.netdrv 订阅socket连接状态变化事件 airlink_4G
[2026-05-15 17:03:50.133][LTOS/N][000000000.057]:I/user.airlink_4G网卡已开启 15
[2026-05-15 17:03:50.135][LTOS/N][000000000.057]:I/user.设置网卡 airlink_4G
[2026-05-15 17:03:50.136][LTOS/N][000000000.058]:I/user.exnetif publish network status airlink_4G 15
[2026-05-15 17:03:50.137][LTOS/N][000000000.075]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:51.131][LTOS/N][000000001.076]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:52.117][LTOS/N][000000002.076]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:53.104][LTOS/N][000000003.077]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:54.124][LTOS/N][000000004.077]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:55.110][LTOS/N][000000005.078]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:56.120][LTOS/N][000000006.078]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:57.133][LTOS/N][000000007.079]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:58.118][LTOS/N][000000008.079]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:03:59.107][LTOS/N][000000009.079]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:04:00.131][LTOS/N][000000010.080]:W/user.HTTP上传 等待网络连接 15 15
[2026-05-15 17:04:00.979][LTOS/N][000000010.930]:D/airlink 4G代理网卡上线了
[2026-05-15 17:04:00.981][LTOS/N][000000010.930]:D/netdrv 网卡(15)设置为UP
[2026-05-15 17:04:00.982][LTOS/N][000000010.930]:D/net network ready 15, setup dns server
[2026-05-15 17:04:00.984][LTOS/N][000000010.930]:D/netdrv IP_READY 15 192.168.111.1
[2026-05-15 17:04:00.988][LTOS/N][000000010.931]:I/user.dnsproxy 开始监听
[2026-05-15 17:04:00.990][LTOS/N][000000010.931]:D/net 设置DNS服务器 id 15 index 0 ip 223.5.5.5
[2026-05-15 17:04:00.992][LTOS/N][000000010.931]:D/net 设置DNS服务器 id 15 index 1 ip 114.114.114.114
[2026-05-15 17:04:00.993][LTOS/N][000000010.931]:I/user.netdrv_4g.ip_ready_func IP_READY 192.168.111.1 255.255.255.0 192.168.111.2 nil
[2026-05-15 17:04:00.996][LTOS/N][000000010.931]:I/user.HTTP上传 网络已就绪 15 15
[2026-05-15 17:04:00.997][CAPP/N][000000010.932]:spi_set_new_config 386:spi1 目标速度400000 实际速度375000 BR 45
[2026-05-15 17:04:01.000][LTOS/N][000000010.932]:D/fatfs init sdcard at spi=1 cs=8
[2026-05-15 17:04:01.001][CAPP/N][000000010.952]:spi_set_new_config 386:spi1 目标速度24000000 实际速度20000000 BR 20
[2026-05-15 17:04:01.003][LTOS/N][000000010.952]:D/SPI_TF 卡容量 3872256KB
[2026-05-15 17:04:01.004][LTOS/N][000000010.952]:D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 17:04:01.006][LTOS/N][000000010.954]:I/fatfs mount success at fat32
[2026-05-15 17:04:01.010][LTOS/N][000000010.955]:I/user.HTTP上传 准备上传文件 /sd/1.mp3 大小: 411922 字节
[2026-05-15 17:04:01.012][LTOS/N][000000010.955]:I/user.HTTP上传 开始上传任务
[2026-05-15 17:04:01.013][LTOS/N][000000010.957]:D/socket connect to airtest.openluat.com,2900
[2026-05-15 17:04:01.015][LTOS/N][000000010.957]:D/DNS airtest.openluat.com state 0 id 1 ipv6 0 use dns server0, try 0
[2026-05-15 17:04:01.016][LTOS/N][000000010.957]:D/net adatper 15 dns server 223.5.5.5
[2026-05-15 17:04:01.018][LTOS/N][000000010.958]:D/net dns udp sendto 223.5.5.5:53 from 192.168.111.1
[2026-05-15 17:04:01.117][LTOS/N][000000011.062]:I/DNS dns all done ,now stop
[2026-05-15 17:04:01.119][LTOS/N][000000011.063]:D/net adapter 15 connect 47.96.229.157:2900 TCP
[2026-05-15 17:04:07.213][LTOS/N][000000017.171]:I/user.httpplus 服务器已完成响应
[2026-05-15 17:04:07.215][LTOS/N][000000017.171]:I/user.HTTP上传 上传完成 success 200
[2026-05-15 17:04:07.216][LTOS/N][000000017.172]:I/user.HTTP上传 服务器响应头 {"Content-Type":"text/plain;charset=UTF-8","Connection":"close","Content-Length":"20","Vary":"Access-Control-Request-Headers","Date":"Fri, 15 May 2026 09:04:09 GMT"}
[2026-05-15 17:04:07.218][LTOS/N][000000017.172]:I/user.HTTP上传 服务器响应体长度 20
[2026-05-15 17:04:07.219][LTOS/N][000000017.172]:I/user.HTTP上传 服务器响应内容 uploadFileToStaticOK
[2026-05-15 17:04:07.221][LTOS/N][000000017.172]:I/user.HTTP上传 资源清理完成

```