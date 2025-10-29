## **功能模块介绍**

本 Demo 演示了在Air780EPM内置Flash文件系统中的完整操作流程，覆盖了从文件系统读写到高级文件操作的完整功能链。项目分为两个核心模块：

1、main.lua：主程序入口 <br> 
2、flash_fs_io.lua：内置Flash文件系统的操作测试流程模块，实现文件系统管理、文件操作和目录管理功能。<br> 
3、http_download_flash.lua：HTTP下载模块，演示HTTP下载文件到内置Flash中的功能

## **演示功能概述**

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载flash_fs_io模块（通过require "flash_fs_io"）
- 加载http_download_flash模块（通过require "http_download_flash"）
- 最后运行sys.run()。

### 2、内置Flash文件系统演示模块（flash_fs_io.lua）

#### 文件操作
- 获取文件系统信息( io.fsstat)
- 创建目录：io.mkdir("/flash_demo")
- 创建/写入文件： io.open("/flash_demo/boottime", "wb")
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

### 3、HTTP下载功能 (http_download_flash.lua)


#### 网络就绪检测

- 1秒循环等待IP就绪
- 网络故障处理机制

#### 安全下载

- HTTP下载

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 获取文件系统信息( io.fsstat)

## **演示硬件环境**

1、Air780EPM核心板一块

2、TYPE-C USB数据线一根

3、SIM卡一张

4、Air780EPM核心板和数据线的硬件接线方式为

- Air780EPM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## **演示软件环境**

1、Luatools下载调试工具：https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：https://docs.openluat.com/air780epm/luatos/firmware/version/

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印

```lua

（1）文件操作演示
[2025-10-22 16:04:28.032][000000000.214] I/user.文件系统操作 ===== 开始文件系统操作 =====
[2025-10-22 16:04:28.064][000000000.218] I/user. io.fsstat成功: 总空间=42块 已用=4块 块大小=4096字节 类型=lfs
[2025-10-22 16:04:28.085][000000000.319] I/user.io.mkdir 目录创建成功 路径:/flash_demo
[2025-10-22 16:04:28.105][000000000.328] I/user.文件创建 文件写入成功 路径:/flash_demo/boottime
[2025-10-22 16:04:28.114][000000000.331] I/user.io.exists 文件存在 路径:/flash_demo/boottime
[2025-10-22 16:04:28.130][000000000.334] I/user.io.fileSize 文件大小:59字节 路径:/flash_demo/boottime
[2025-10-22 16:04:28.142][000000000.337] I/user.文件读取 路径:/flash_demo/boottime 内容:这是内置Flash文件系统API文档示例的测试内容
[2025-10-22 16:04:28.167][000000000.340] I/user.启动计数 文件内容: 这是内置Flash文件系统API文档示例的测试内容 十六进制: E8BF99E698AFE58685E7BDAE466C617368E69687E4BBB6E7B3BBE7BB9F415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 118
[2025-10-22 16:04:28.192][000000000.340] I/user.启动计数 当前值: 0
[2025-10-22 16:04:28.217][000000000.340] I/user.启动计数 更新值: 1
[2025-10-22 16:04:28.221][000000000.345] I/user.文件写入 路径:/flash_demo/boottime 内容: 1
[2025-10-22 16:04:28.234][000000000.357] I/user.文件创建 路径:/flash_demo/test_a 初始内容:ABC
[2025-10-22 16:04:28.242][000000000.360] I/user.文件追加 路径:/flash_demo/test_a 追加内容:def
[2025-10-22 16:04:28.248][000000000.363] I/user.文件验证 路径:/flash_demo/test_a 内容:ABCdef 结果: 成功
[2025-10-22 16:04:28.253][000000000.367] I/user.文件创建 路径:/flash_demo/testline 写入3行文本
[2025-10-22 16:04:28.271][000000000.370] I/user.按行读取 路径:/flash_demo/testline 第1行: abc
[2025-10-22 16:04:28.279][000000000.370] I/user.按行读取 路径:/flash_demo/testline 第2行: 123
[2025-10-22 16:04:28.302][000000000.371] I/user.按行读取 路径:/flash_demo/testline 第3行: wendal
[2025-10-22 16:04:28.331][000000000.377] I/user.os.rename 文件重命名成功 原路径:/flash_demo/test_a 新路径:/flash_demo/renamed_file.txt
[2025-10-22 16:04:28.347][000000000.383] D/vfs fopen /flash_demo/test_a r not found
[2025-10-22 16:04:28.361][000000000.383] I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2025-10-22 16:04:28.382][000000000.383] I/user.目录操作 ===== 开始目录列举 =====
[2025-10-22 16:04:28.393][000000000.396] I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"renamed_file.txt","size":6,"type":0},{"name":"testline","size":15,"type":0}]
[2025-10-22 16:04:28.417][000000000.400] I/user.os.remove 文件删除成功 路径:/flash_demo/renamed_file.txt
[2025-10-22 16:04:28.435][000000000.403] D/vfs fopen /flash_demo/renamed_file.txt r not found
[2025-10-22 16:04:28.449][000000000.403] I/user.验证结果 renamed_file.txt文件删除验证成功
[2025-10-22 16:04:28.469][000000000.407] I/user.os.remove testline文件删除成功 路径:/flash_demo/testline
[2025-10-22 16:04:28.479][000000000.410] D/vfs fopen /flash_demo/testline r not found
[2025-10-22 16:04:28.489][000000000.411] I/user.验证结果 testline文件删除验证成功
[2025-10-22 16:04:28.507][000000000.417] I/user.os.remove 文件删除成功 路径:/flash_demo/boottime
[2025-10-22 16:04:28.514][000000000.420] D/vfs fopen /flash_demo/boottime r not found
[2025-10-22 16:04:28.519][000000000.421] I/user.验证结果 boottime文件删除验证成功
[2025-10-22 16:04:28.532][000000000.427] I/user.io.rmdir 目录删除成功 路径:/flash_demo
[2025-10-22 16:04:28.538][000000000.430] I/user.验证结果 目录删除验证成功
[2025-10-22 16:04:28.547][000000000.435] I/user. io.fsstat 操作后文件系统信息: 总空间=42块 已用=4块 块大小=4096字节 类型=lfs
[2025-10-22 16:04:28.554][000000000.435] I/user.文件系统操作 ===== 文件系统操作完成 =====





（2）网络连接与HTTP下载
[2025-10-22 15:34:04.507][000000007.471] I/user.HTTP下载 网络已就绪 1 3
[2025-10-22 15:34:04.550][000000007.471] I/user.HTTP下载 开始下载任务
[2025-10-22 15:34:04.579][000000007.478] dns_run 676:gitee.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-10-22 15:34:04.604][000000007.508] D/mobile TIME_SYNC 0
[2025-10-22 15:34:04.734][000000007.517] dns_run 693:dns all done ,now stop
[2025-10-22 15:34:06.390][000000009.741] I/user.HTTP下载 下载完成 success 200 
[2025-10-22 15:34:06.422][000000009.741] {"Age":"0","Cache-Control":"public, max-age=60","Via":"1.1 varnish","Transfer-Encoding":"chunked","Date":"Wed, 22 Oct 2025 07:34:04 GMT","Access-Control-Allow-Credentials":"true","Vary":"Accept-Encoding","X-Served-By":"cache-ffe9","X-Gitee-Server":"http-pilot 1.9.21","Connection":"keep-alive","Server":"ADAS\/1.0.214","Access-Control-Allow-Headers":"Accept,Authorization,Cache-Control,Content-Type,DNT,If-Modified-Since,Keep-Alive,Origin,User-Agent,X-Requested-With,X-CustomHeader,Content-Range,Range,Set-Language","Content-Security-Policy":"default-src 'none'; style-src 'unsafe-inline'; sandbox","X-Request-Id":"fa536af1-51bd-400f-8d4b-7322355a9db2","Accept-Ranges":"bytes","Etag":"W\/\"2aaa2788d394a924e258d6f26ad78b8c948950f5\"","Content-Type":"text\/plain; charset=utf-8","Access-Control-Allow-Methods":"GET, POST, PUT, PATCH, DELETE, OPTIONS","X-Frame-Options":"DENY","X-Cache":"MISS","Set-Cookie":"BEC=1f1759df3ccd099821dcf0da6feb0357;Path=\/;Max-Age=126000"}
[2025-10-22 15:34:06.477][000000009.742]  103070
[2025-10-22 15:34:06.492][000000009.745] I/user.HTTP下载 文件大小验证 预期: 103070 实际: 103070
[2025-10-22 15:34:06.525][000000009.751] I/user.HTTP下载 下载后文件系统信息: 总空间=42块 已用=32块 块大小=4096字节 类型=lfs


```