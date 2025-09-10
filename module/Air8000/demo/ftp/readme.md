## 功能模块介绍：

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、netdrv文件夹：四种网卡，单4g网卡、单wifi网卡，、单spi以太网卡、多网卡，供netdrv_device.lua加载配置；

4、ftp_up_download.lua:   功能演示核心脚本，操作ftp文件、上传和下载文件等,在main.lua中加载运行。

## 演示功能概述：

1、 配置FTP客户端登录服务器的参数和文件路径

2、 封装一个重试机制，在登录失败、上传文件失败或者下载文件失败时尝试重新执行操作

3、 登录FTP服务器，通过重试机制确保登录成功

4、 ftp.push上传本地文件到服务器，在本地新建文件并写入内容后上传到服务器指定路径，通过重试机制确保上传成功

5、 ftp.pull从服务器下载文件，保存在本地指定路径，并读取文件长度，当长度小于指定字节时，读取文件内容，通常是设定512字节，如果文件太大，会消耗ram。

6、 主函数循环运行以下流程： 登录服务器、用 ftp.command 操作 ftp 服务器目录以及文件上传下载处理后关闭服务器。
   
   

## 演示硬件环境

![netdrv_multi](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)



1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根+网线一根：

* sim卡插入开发板的sim卡槽

* 天线装到开发板上

* 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 ，Air8000开发板和数据线的硬件接线方式为：

* Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、 Luatools下载调试工具

2、 测试服务器，非 ssl 加密：
   local server_ip = "121.43.224.154" -- 服务器 IP   
   local server_port = 21 -- 服务器端口号   
   local server_username = "ftp_user" -- 服务器登陆用户名   
   local server_password = "3QujbiMG" -- 服务器登陆密码

3、 固件版本：LuatOS-SoC_V2014_Air8000_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8000/luatos/firmware/](https://docs.openluat.com/air8000/luatos/firmware/)

4、 脚本文件：
   main.lua

   ftp_up_download.lua

   netdrv_device.lua

   netdrv文件夹

5、 pc 系统 win11（win10 及以上）
   
   

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

* 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

* 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、如果是自己的ftp服务器，脚本代码ftp_up_download.lua中，在config表中按自己的服务器IP，端口号，用户名，密码修改参数。

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印ftp登录成功，空操作和文件目录打印，上传下载文件结果以及关闭FTP连接等信息，如下log显示：

```
[2025-08-22 16:34:47.428][000000001.784] I/user.ftp_login recv IP_READY 1 3
[2025-08-22 16:34:47.434][000000001.830] D/mobile TIME_SYNC 0
[2025-08-22 16:34:47.506][000000002.077] I/user.FTP登录成功
[2025-08-22 16:34:47.552][000000002.128] I/user.空操作，防止连接断掉 200 NOOP ok.

[2025-08-22 16:34:47.598][000000002.178] I/user.报告远程系统的操作系统类型 215 UNIX Type: L8

[2025-08-22 16:34:47.644][000000002.229] I/user.指定文件类型 200 Switching to Binary mode.

[2025-08-22 16:34:47.706][000000002.278] I/user.显示当前工作目录名 257 "/"

[2025-08-22 16:34:47.751][000000002.329] I/user.创建一个目录 目录名为QWER 257 "/QWER" created

[2025-08-22 16:34:47.797][000000002.379] I/user.改变当前工作目录为QWER 250 Directory successfully changed.

[2025-08-22 16:34:47.843][000000002.427] I/user.返回上一层目录 250 Directory successfully changed.

[2025-08-22 16:34:48.062][000000002.647] I/user.获取当前工作目录下的文件名列表 
[2025-08-22 16:34:48.071][000000002.647] drwx------    2 ftp      ftp          4096 Apr 29 08:43 080307100000002
drwx------    2 ftp      ftp          4096 Apr 11 01:22 080307100000003
drwx------    2 ftp      ftp          4096 Apr 11 01:22 080307100000004
drwx------    2 ftp      ftp          4096 Apr 11 01:22 080307100000005
drwx------    2 ftp      ftp          4096 Apr 11 01:23 080307100000006
drwx------    2 ftp      ftp          4096 Apr 30 06:16 080307100000022
drwx------    2 ftp      ftp          4096 Apr 30 06:16 080307100000023
drwx------    2 ftp      ftp          4096 Apr 30 06:16 080307100000024
drwx------    2 ftp      ftp          4096 Apr 30 06:16 080307100000025
drwx------    2 ftp      ftp          4096 Apr 30 06:16 080307100000026
drwx------    2 ftp      ftp          4096 Jul 25 10:40 080307100000027
drwx------    2 ftp      ftp          4096 Jul 25 10:04 080307100000028
-rw-------    1 ftp      ftp         27588 Jun 03 07:04 12222.mp4
-rw-------    1 ftp      ftp            62 Aug 22 08:32 12222.txt
-rw-------    1 ftp      ftp        174016 Jun 02 15:43 122224.mp4
-rw-------    1 ftp      ftp         27588 Jun 02 03:54 1__19700101080014.mp4
drwx------    2 ftp      ftp          4096 Apr 19 04:49 23543121001
drwx------    2 ftp      ftp          4096 Aug 04 11:46 MT_T
drwx------    2 ftp      ftp          4096 Aug 22 08:34 QWER
drwx------    3 ftp      ftp          4096 Jul 09 08:02 Test
drwx------    2 ftp      ftp          4096 Apr 19 04:45 YKZ
-rw-------    1 ftp      ftp       1186492 Apr 19 06:12 data.dat
-rw-------    1 ftp      ftp        189943 Jun 27 07:04 ftp_test.mp4
-rw-------    1 ftp      ftp             0 Jun 02 04:00 新建 文本文档.txt

[2025-08-22 16:34:48.079][000000002.651] I/user.本地文件/ftp_upload.txt创建成功，并写入文件内容: Luatos FTP上传测试数据 
[2025-08-22 16:34:48.086][000000002.652] I/user.开始上传文件:/ftp_upload.txt
[2025-08-22 16:34:48.452][000000003.027] I/user.本地文件上传成功，保存在服务器路径: /uploaded_by_luatos.txt
[2025-08-22 16:34:48.546][000000003.127] I/user. 开始下载文件:/12222.txt
[2025-08-22 16:34:48.871][000000003.446] I/user.服务器上文件/12222.txt下载成功，保存在本地路径: /ftp_download.txt 大小: 62 字节
[2025-08-22 16:34:48.880][000000003.447] I/user.下载文件内容长度小于512字节，内容是: 23noianfdiasfhnpqw39fhawe;fuibnnpw3fheaios;fna;osfhisao;fadsfl
[2025-08-22 16:34:48.932][000000003.517] I/user.删除测试目录QWER 250 Remove directory operation successful.

[2025-08-22 16:34:49.056][000000003.636] I/user.FTP连接关闭结果: 221 Goodbye.

[2025-08-22 16:34:49.061][000000003.636] I/user.meminfo内存信息 3208112 279932 285960

```
