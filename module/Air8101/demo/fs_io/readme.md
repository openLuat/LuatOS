## **功能模块介绍**

本 Demo 演示了在Air8101内置Flash文件系统中的完整操作流程，覆盖了从文件系统读写到高级文件操作的完整功能链。项目分为两个核心模块：

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

- 连接WiFi
- 1秒循环等待IP就绪
- 网络故障处理机制

#### 安全下载

- HTTP下载

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 获取文件系统信息( io.fsstat)

## **演示硬件环境**

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（正面的开关拨到3.3v，背面的开关拨到off）

- TYPE-C USB数据线直接插到Air8101核心板的TYPE-C USB座子，另外一端连接电脑USB口

## **演示软件环境**

1、Luatools下载调试工具：https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：https://docs.openluat.com/air8101/luatos/firmware/

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印

```lua

（1）文件操作演示
[2025-10-22 16:32:47.705] luat:U(172):I/user.文件系统操作 ===== 开始文件系统操作 =====
[2025-10-22 16:32:47.705] luat:U(174):I/user. io.fsstat成功: 总空间=64块 已用=2块 块大小=4096字节 类型=lfs
[2025-10-22 16:32:47.767] luat:U(215):I/user.io.mkdir 目录创建成功 路径:/flash_demo
[2025-10-22 16:32:47.767] luat:U(224):I/user.文件创建 文件写入成功 路径:/flash_demo/boottime
[2025-10-22 16:32:47.767] luat:U(226):I/user.io.exists 文件存在 路径:/flash_demo/boottime
[2025-10-22 16:32:47.767] luat:U(228):I/user.io.fileSize 文件大小:59字节 路径:/flash_demo/boottime
[2025-10-22 16:32:47.767] luat:U(230):I/user.文件读取 路径:/flash_demo/boottime 内容:这是内置Flash文件系统API文档示例的测试内容
[2025-10-22 16:32:47.767] luat:U(232):I/user.启动计数 文件内容: 这是内置Flash文件系统API文档示例的测试内容 十六进制: E8BF99E698AFE58685E7BDAE466C617368E69687E4BBB6E7B3BBE7BB9F415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 118
[2025-10-22 16:32:47.767] luat:U(233):I/user.启动计数 当前值: 0
[2025-10-22 16:32:47.767] luat:U(233):I/user.启动计数 更新值: 1
[2025-10-22 16:32:47.767] luat:U(238):I/user.文件写入 路径:/flash_demo/boottime 内容: 1
[2025-10-22 16:32:47.831] luat:U(249):I/user.文件创建 路径:/flash_demo/test_a 初始内容:ABC
[2025-10-22 16:32:47.831] luat:U(255):I/user.文件追加 路径:/flash_demo/test_a 追加内容:def
[2025-10-22 16:32:47.831] luat:U(257):I/user.文件验证 路径:/flash_demo/test_a 内容:ABCdef 结果: 成功
[2025-10-22 16:32:47.831] luat:U(266):I/user.文件创建 路径:/flash_demo/testline 写入3行文本
[2025-10-22 16:32:47.831] luat:U(268):I/user.按行读取 路径:/flash_demo/testline 第1行: abc
[2025-10-22 16:32:47.831] luat:U(269):I/user.按行读取 路径:/flash_demo/testline 第2行: 123
[2025-10-22 16:32:47.831] luat:U(269):I/user.按行读取 路径:/flash_demo/testline 第3行: wendal
[2025-10-22 16:32:47.831] luat:U(277):I/user.os.rename 文件重命名成功 原路径:/flash_demo/test_a 新路径:/flash_demo/renamed_file.txt
[2025-10-22 16:32:47.831] luat:D(281):vfs:fopen /flash_demo/test_a r not found
[2025-10-22 16:32:47.831] luat:U(281):I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2025-10-22 16:32:47.831] luat:U(282):I/user.目录操作 ===== 开始目录列举 =====
[2025-10-22 16:32:47.831] luat:U(291):I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"renamed_file.txt","size":6,"type":0},{"name":"testline","size":15,"type":0}]
[2025-10-22 16:32:47.831] luat:U(297):I/user.os.remove 文件删除成功 路径:/flash_demo/renamed_file.txt
[2025-10-22 16:32:47.831] luat:D(299):vfs:fopen /flash_demo/renamed_file.txt r not found
[2025-10-22 16:32:47.831] luat:U(299):I/user.验证结果 renamed_file.txt文件删除验证成功
[2025-10-22 16:32:47.831] luat:U(305):I/user.os.remove testline文件删除成功 路径:/flash_demo/testline
[2025-10-22 16:32:47.831] luat:D(307):vfs:fopen /flash_demo/testline r not found
[2025-10-22 16:32:47.831] luat:U(307):I/user.验证结果 testline文件删除验证成功
[2025-10-22 16:32:47.831] luat:U(313):I/user.os.remove 文件删除成功 路径:/flash_demo/boottime
[2025-10-22 16:32:47.831] luat:D(315):vfs:fopen /flash_demo/boottime r not found
[2025-10-22 16:32:47.831] luat:U(316):I/user.验证结果 boottime文件删除验证成功
[2025-10-22 16:32:47.988] luat:U(326):I/user.io.rmdir 目录删除成功 路径:/flash_demo
[2025-10-22 16:32:47.988] luat:U(327):I/user.验证结果 目录删除验证成功
[2025-10-22 16:32:47.988] luat:U(329):I/user. io.fsstat 操作后文件系统信息: 总空间=64块 已用=2块 块大小=4096字节 类型=lfs
[2025-10-22 16:32:47.988] luat:U(330):I/user.文件系统操作 ===== 文件系统操作完成 =====





（2）网络连接与HTTP下载
[2025-10-24 10:51:10.116] luat:U(2895):I/user.HTTP下载 网络已就绪 2 2
[2025-10-24 10:51:10.116] luat:U(2896):I/user.HTTP下载 开始下载任务
[2025-10-24 10:51:10.202] luat:D(2967):DNS:www.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0
[2025-10-24 10:51:10.202] luat:D(2967):net:adatper 2 dns server 192.168.1.1
[2025-10-24 10:51:10.202] luat:D(2968):net:dns udp sendto 192.168.1.1:53 from 192.168.1.116
[2025-10-24 10:51:10.202] luat:D(2971):wlan:sta ip 192.168.1.116
[2025-10-24 10:51:10.202] luat:D(2971):wlan:设置STA网卡可用
[2025-10-24 10:51:10.222] luat:I(2989):DNS:dns all done ,now stop
[2025-10-24 10:51:10.222] luat:D(2990):net:adapter 2 connect 49.232.89.122:443 TCP
[2025-10-24 10:51:14.599] luat:U(7368):I/user.HTTP下载 下载完成 success 200 {"Last-Modified":"Thu, 23 Oct 2025 03:14:41 GMT","Accept-Ranges":"bytes","ETag":"\"68f99da1-1929e\"","Date":"Fri, 24 Oct 2025 02:51:09 GMT","Connection":"keep-alive","Server":"openresty\/1.27.1.2","Content-Length":"103070","Content-Type":"audio\/mpeg"} 103070
[2025-10-24 10:51:14.599] luat:U(7384):I/user.HTTP下载 文件大小验证 预期: 103070 实际: 103070
[2025-10-24 10:51:14.630] luat:U(7409):I/user.HTTP下载 下载后文件系统信息: 总空间=64块 已用=30块 块大小=4096字节 类型=lfs



```