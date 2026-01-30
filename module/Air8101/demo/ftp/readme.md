## 功能模块介绍：

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的五种网卡(单wifi网卡，单rmii以太网卡，单spi以太网卡，多网卡，pc模拟器上的网卡)中的任何一种网卡；

3、netdrv文件夹：五种网卡，单wifi网卡、单rmii以太网卡、单spi以太网卡、多网卡、pc模拟器上的网卡，供netdrv_device.lua加载配置；

4、ftp_up_download.lua:   功能演示核心脚本，操作ftp文件、上传和下载文件等,在main.lua中加载运行。

## 演示功能概述：

1、 配置FTP客户端登录服务器的参数和文件路径

2、 封装一个重试机制，在登录失败、上传文件失败或者下载文件失败时尝试重新执行操作

3、 登录FTP服务器，通过重试机制确保登录成功

4、 ftp.push上传本地文件到服务器，在本地新建文件并写入内容后上传到服务器指定路径，通过重试机制确保上传成功

5、 ftp.pull从服务器下载文件，保存在本地指定路径，并读取文件长度，当长度小于指定字节时，读取文件内容，通常是设定512字节，如果文件太大，会消耗ram。

6、 主函数循环运行以下流程： 登录服务器、用 ftp.command 操作 ftp 服务器目录以及文件上传下载处理后关闭服务器。



## 演示硬件环境

![netdrv_multi](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/8101.jpg)



1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

* Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

* 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

4、可选AirETH_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
|:----------:|:--------------:|
| 59/3V3     | 3.3v           |
| GND        | GND            |
| 28/DCLK    | SCK            |
| 54/DISP    | CSS            |
| 55/HSYN    | SDO            |
| 57/DE      | SDI            |
| 14/GPIO8   | INT            |

 5、可选AirPHY_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

| Air8101核心板 | AirPHY_1000配件板 |
| ---------- | -------------- |
| 59/3V3     | 3.3v           |
| GND        | GND            |
| 5/D2       | RX1            |
| 72/D1      | RX0            |
| 71/D3      | CRS            |
| 4/D0       | MDIO           |
| 6/D4       | TX0            |
| 74/PCK     | MDC            |
| 70/D5      | TX1            |
| 7/D6       | TXEN           |
| 不接         | NC             |
| 69/D7      |                |

## 演示软件环境

1、 Luatools下载调试工具

2、 测试服务器，非 ssl 加密：
   local server_ip = "121.43.224.154" -- 服务器 IP   
   local server_port = 21 -- 服务器端口号   
   local server_username = "ftp_user" -- 服务器登陆用户名   
   local server_password = "3QujbiMG" -- 服务器登陆密码

3、固件版本：LuatOS-SoC_V2002_Air8101_101.soc，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

4、 脚本文件：
   main.lua

   ftp_up_download.lua

   netdrv_device.lua

   netdrv文件夹

5、 pc 系统 win11（win10 及以上）



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("Mayadan", "12345678", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

* 如果需要RMII以太网卡，打开require "netdrv_eth_rmii"，其余注释掉

* 如果需要SPI以太网卡，打开require "netdrv_eth_spi"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、如果是自己的ftp服务器，脚本代码ftp_up_download.lua中，在config表中按自己的服务器IP，端口号，用户名，密码修改参数。

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印ftp登录成功，空操作和文件目录打印，上传下载文件结果以及关闭FTP连接等信息，如下log显示：

```
[2026-01-30 16:45:20.036] luat:U(1004):I/user.main ftp_demo 001.000.000
[2026-01-30 16:45:20.175] wifid:I(1137):mm_add_if_req: vif_idx=0, type=0, p2p=0, status=0
[2026-01-30 16:45:20.175] wpa:I(1142):State: DISCONNECTED -> INACTIVE
[2026-01-30 16:45:20.175] wpa:I(1142):State: INACTIVE -> DISCONNECTED
[2026-01-30 16:45:20.175] lwip:I(1142):mac c8:c2:c6:8d:52:84
[2026-01-30 16:45:20.203] wpa:I(1147):Setting scan request: 0.000000 sec
[2026-01-30 16:45:20.203] wpa:I(1148):State: DISCONNECTED -> SCANNING
[2026-01-30 16:45:20.203] wifid:I(1149):[KW:]scanu_start_req:src_id=15,vif=0,dur=0,chan_cnt=14,ssid_len=7,bssid=0xffff-ffff-ffff
[2026-01-30 16:45:20.203] wifid:I(1149):[KW:]scanu_start_req:ssid=Mayadan
[2026-01-30 16:45:20.203] os:I(1153):psram:0x607a0000,size:131072
[2026-01-30 16:45:20.486] wpa:I(1455):update psk, scan pending 1
[2026-01-30 16:45:20.564] luat:U(1523):W/user.ftp_login wait IP_READY 2 2
[2026-01-30 16:45:21.560] luat:U(2525):W/user.ftp_login wait IP_READY 2 2
[2026-01-30 16:45:21.902] wifid:I(2855):[KW:]scanu_confirm:status=0,req_type=0,upload_cnt=5,recv_cnt=66,time=1705960us,result=1,rfcli=0
[2026-01-30 16:45:21.902] wpa:I(2856):Scan completed in 1.704000 seconds
[2026-01-30 16:45:21.902] hitf:I(2856):get scan result:1
[2026-01-30 16:45:21.902] wpa:I(2857):State: SCANNING -> ASSOCIATING
[2026-01-30 16:45:21.902] wifid:I(2858):[KW:]conn vif0-0,auth_type:0,bssid:9952-1895-2324,ssid:Mayadan,is encryp:8.
[2026-01-30 16:45:21.902] wifid:I(2858):chan_ctxt_add: CTXT0,freq2412MHz,bw20MHz,pwr27dBm
[2026-01-30 16:45:21.902] wifid:I(2858):chan_reg_fix:VIF0,CTXT0,type3,ctxt_s0,nb_vif0
[2026-01-30 16:45:21.902] wifid:I(2859):mm_sta_add:vif 0,sta 0,status 0
[2026-01-30 16:45:21.902] wifid:I(2861):[KW:]auth_send:seq1, txtype1, auth_type0, seq46
[2026-01-30 16:45:21.940] wifid:I(2921):[KW:]sm_auth_handler: status code 0, tx status 0x80800000
[2026-01-30 16:45:21.940] wifid:I(2921):[KW:]assoc_req_send:is ht, seq_num:47
[2026-01-30 16:45:21.940] wifid:I(2924):[KW:]assoc_rsp:status0,tx_s0x80800000
[2026-01-30 16:45:21.953] wifid:I(2924):[KW:]mm_set_vif_state,vif=0,vif_type=0,is_active=1, aid=0x3,rssi=-42
[2026-01-30 16:45:21.953] wpa:I(2925):State: ASSOCIATING -> ASSOCIATED
[2026-01-30 16:45:21.992] wifid:I(2956):[KW:]sm_disassoc_handler: reason code 2, state 0
[2026-01-30 16:45:21.992] wifid:I(2956):[KW:]mm_set_vif_state,vif=0,vif_type=0,is_active=0, aid=0x0,rssi=-42
[2026-01-30 16:45:21.992] wifid:I(2956):sta_del_req 0
[2026-01-30 16:45:21.992] wifid:I(2957):chan_unreg_fix:VIF0,CTXT0,nb_vif1
[2026-01-30 16:45:21.992] wpa:I(2958):Setting scan request: 0.100000 sec
[2026-01-30 16:45:21.992] wpa:I(2958):State: ASSOCIATED -> DISCONNECTED
[2026-01-30 16:45:21.992] luat:D(2960):wlan:event_module 1 event_id 3
[2026-01-30 16:45:21.992] luat:D(2960):wlan:STA disconnected, reason(2) is_local 0
[2026-01-30 16:45:22.100] wpa:I(3058):State: DISCONNECTED -> SCANNING
[2026-01-30 16:45:22.100] wifid:I(3059):[KW:]scanu_start_req:src_id=15,vif=0,dur=0,chan_cnt=14,ssid_len=7,bssid=0xffff-ffff-ffff
[2026-01-30 16:45:22.100] wifid:I(3059):[KW:]scanu_start_req:ssid=Mayadan
[2026-01-30 16:45:22.554] luat:U(3525):W/user.ftp_login wait IP_READY 2 2
[2026-01-30 16:45:23.563] luat:U(4525):W/user.ftp_login wait IP_READY 2 2
[2026-01-30 16:45:23.797] wifid:I(4763):[KW:]scanu_confirm:status=0,req_type=0,upload_cnt=5,recv_cnt=67,time=1705807us,result=1,rfcli=0
[2026-01-30 16:45:23.797] wpa:I(4764):Scan completed in 1.704000 seconds
[2026-01-30 16:45:23.797] hitf:I(4764):get scan result:1
[2026-01-30 16:45:23.818] wpa:I(4765):State: SCANNING -> ASSOCIATING
[2026-01-30 16:45:23.818] wifid:I(4766):[KW:]conn vif0-0,auth_type:0,bssid:9952-1895-2324,ssid:Mayadan,is encryp:8.
[2026-01-30 16:45:23.818] wifid:I(4766):chan_ctxt_add: CTXT1,freq2412MHz,bw20MHz,pwr27dBm
[2026-01-30 16:45:23.818] wifid:I(4766):chan_reg_fix:VIF0,CTXT1,type3,ctxt_s0,nb_vif0
[2026-01-30 16:45:23.818] wifid:I(4767):mm_sta_add:vif 0,sta 1,status 0
[2026-01-30 16:45:23.818] wifid:I(4769):[KW:]auth_send:seq1, txtype1, auth_type0, seq92
[2026-01-30 16:45:23.860] wifid:I(4824):[KW:]sm_auth_handler: status code 0, tx status 0x80800000
[2026-01-30 16:45:23.860] wifid:I(4824):[KW:]assoc_req_send:is ht, seq_num:93
[2026-01-30 16:45:23.860] wifid:I(4828):[KW:]assoc_rsp:status0,tx_s0x80800000
[2026-01-30 16:45:23.872] wifid:I(4828):[KW:]mm_set_vif_state,vif=0,vif_type=0,is_active=1, aid=0x8,rssi=-42
[2026-01-30 16:45:23.872] wpa:I(4829):State: ASSOCIATING -> ASSOCIATED
[2026-01-30 16:45:23.872] wpa:I(4854):State: ASSOCIATED -> 4WAY_HANDSHAKE
[2026-01-30 16:45:23.872] wpa:I(4855):WPA: TK 56559313bf9995192ad8fc88257b846a
[2026-01-30 16:45:23.886] wpa:I(4861):State: 4WAY_HANDSHAKE -> 4WAY_HANDSHAKE
[2026-01-30 16:45:23.886] hitf:I(4862):add CCMP
[2026-01-30 16:45:23.886] wpa:I(4862):State: 4WAY_HANDSHAKE -> GROUP_HANDSHAKE
[2026-01-30 16:45:23.886] hitf:I(4863):add CCMP
[2026-01-30 16:45:23.886] wpa:I(4863):State: GROUP_HANDSHAKE -> COMPLETED
[2026-01-30 16:45:23.886] lwip:I(4864):sta ip start
[2026-01-30 16:45:23.886] lwip:I(4864):[KW:]sta:DHCP_DISCOVER()
[2026-01-30 16:45:23.906] lwip:I(4871):[KW:]sta:DHCP_OFFER received in DHCP_STATE_SELECTING state
[2026-01-30 16:45:23.906] lwip:I(4871):[KW:]sta:DHCP_REQUEST(netif=0x28065588) en   1
[2026-01-30 16:45:23.906] lwip:I(4880):[KW:]sta:DHCP_ACK received
[2026-01-30 16:45:23.906] wifid:I(4881):[KW:]me dhcp done vif:0
[2026-01-30 16:45:23.906] event:W(4882):event <2 0> has no cb
[2026-01-30 16:45:23.906] ap0:lwip:I(4768):sta ip start
[2026-01-30 16:45:23.906] luat:D(4885):wlan:event_module 1 event_id 2
[2026-01-30 16:45:23.906] luat:D(4885):wlan:STA connected Mayadan 
[2026-01-30 16:45:23.906] luat:D(4885):wlan:event_module 2 event_id 0
[2026-01-30 16:45:23.906] luat:D(4885):wlan:ipv4 got!! 192.168.43.169
[2026-01-30 16:45:23.906] luat:D(4886):net:network ready 2, setup dns server
[2026-01-30 16:45:23.937] luat:D(4895):wlan:sta ip 192.168.43.169
[2026-01-30 16:45:23.937] luat:U(4898):I/user.netdrv_wifi.ip_ready_func IP_READY {"gw":"192.168.43.1","rssi":-33,"bssid":"529995182423"}
[2026-01-30 16:45:23.937] luat:U(4899):I/user.ftp_login recv IP_READY 2 2
[2026-01-30 16:45:23.937] luat:D(4909):net:adapter 2 connect 121.43.224.154:21 TCP
[2026-01-30 16:45:24.156] luat:U(5114):I/user.FTP登录成功
[2026-01-30 16:45:24.373] luat:U(5351):I/user.空操作，防止连接断掉 200 NOOP ok.
[2026-01-30 16:45:24.373] 
[2026-01-30 16:45:24.433] luat:U(5399):I/user.报告远程系统的操作系统类型 215 UNIX Type: L8
[2026-01-30 16:45:24.433] 
[2026-01-30 16:45:24.480] luat:U(5440):I/user.指定文件类型 200 Switching to Binary mode.
[2026-01-30 16:45:24.480] 
[2026-01-30 16:45:24.589] luat:U(5552):I/user.显示当前工作目录名 257 "/"
[2026-01-30 16:45:24.589] 
[2026-01-30 16:45:24.636] luat:U(5591):I/user.创建一个目录 目录名为QWER 257 "/QWER" created
[2026-01-30 16:45:24.636] 
[2026-01-30 16:45:24.792] luat:U(5760):I/user.改变当前工作目录为QWER 250 Directory successfully changed.
[2026-01-30 16:45:24.792] 
[2026-01-30 16:45:24.839] luat:U(5806):I/user.返回上一层目录 250 Directory successfully changed.
[2026-01-30 16:45:24.839] 
[2026-01-30 16:45:25.009] luat:D(5964):net:adapter 2 connect 121.43.224.154:30006 TCP
[2026-01-30 16:45:25.132] luat:U(6090):I/user.获取当前工作目录下的文件名列表 luat:U(6090):drwx------    2 ftp      ftp          4096 Apr 29  2025 080307100000002
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 11  2025 080307100000003
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 11  2025 080307100000004
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 11  2025 080307100000005
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 11  2025 080307100000006
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 30  2025 080307100000022
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 30  2025 080307100000023
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 30  2025 080307100000024
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 30  2025 080307100000025
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 30  2025 080307100000026
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Jul 25  2025 080307100000027
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Jul 25  2025 080307100000028
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp            62 Nov 14 00:38 1222.txt
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp            62 Jan 27 05:12 12222.txt
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Dec 18 07:46 20251218.
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Apr 19  2025 23543121001
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp         53248 Jan 05 08:41 54540D1C37_srv.txt
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Oct 13 07:26 867920071472626
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp         10108 Nov 14 06:22 BL-SE110_2016.001.001_LuatOS-SoC_Air780EPM.bin
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Jan 11 15:41 BlackV
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Nov 10 06:39 CAMERA
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp          8067 Jan 27 02:51 GPS20260127.txt
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Aug 31 10:11 MT_T
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Jan 30 08:45 QWER
[2026-01-30 16:45:25.132] drwx------    3 ftp      ftp          4096 Jan 06 09:34 Test
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp         59532 Dec 26 09:26 YBJZ.txt
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp         19408 Dec 26 06:21 YBJZ_0_0_1_20251219.bin
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp           169 Jan 30 04:30 YBJZ_0_0_1_2025130.bin
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Oct 14 08:00 YKZ
[2026-01-30 16:45:25.132] -rw-------    1 ftp      ftp            29 Dec 23 05:52 downloaded_by_ftp.txt
[2026-01-30 16:45:25.132] drwx------    2 ftp      ftp          4096 Jan 06 03:19 ftp_folder
[2026-01-30 16:45:25.247] drwx------    2 ftp      ftp         36864 Jan 30 08:44 hhhan
[2026-01-30 16:45:25.247] drwx------    3 ftp      ftp          4096 Oct 22 11:00 rfid
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp       8949760 Sep 09  2024 rustup-init.exe
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp           273 Nov 10 07:49 source2.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32160 Dec 24 02:05 test_upload.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 04 04:32 test_upload_862116069303544.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 05 03:47 test_upload_862289053733641.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 25 02:29 test_upload_864793080180727.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 30 05:10 test_upload_864793080341360.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Dec 25 03:29 test_upload_864793080344190.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 29 11:19 test_upload_864865086824506.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Dec 31 08:49 test_upload_864865086828150.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 30 04:58 test_upload_866965083927845.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 24 23:03 test_upload_866965083928207.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 03 15:43 test_upload_C8C2C68C5BEE.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Jan 21 08:46 test_upload_C8C2C68CD5EA.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp         32768 Dec 24 01:59 test_upload_TT
[2026-01-30 16:45:25.247] 
0.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp            35 Jan 05 15:44 uploaded_by_Black.txt
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp            29 Jan 30 04:52 uploaded_by_luatos.bin
[2026-01-30 16:45:25.247] -rw-------    1 ftp      ftp            29 Jan 30 08:44 uploaded_by_luatos.txt
[2026-01-30 16:45:25.247] luat:U(6091):
[2026-01-30 16:45:25.247] luat:U(6120):I/user.本地文件/ftp_upload.txt创建成功，并写入文件内容: Luatos FTP上传测试数据 
[2026-01-30 16:45:25.247] luat:U(6121):I/user.开始上传文件:/ftp_upload.txt
[2026-01-30 16:45:25.363] luat:D(6232):net:adapter 2 connect 121.43.224.154:30099 TCP
[2026-01-30 16:45:26.238] luat:U(7195):I/user.本地文件上传成功，保存在服务器路径: /uploaded_by_luatos.txt
[2026-01-30 16:45:26.238] luat:U(7196):I/user. 开始下载文件:/12222.txt
[2026-01-30 16:45:26.441] luat:D(7398):net:adapter 2 connect 121.43.224.154:30023 TCP
[2026-01-30 16:45:27.066] luat:U(8029):I/user.服务器上文件/12222.txt下载成功，保存在本地路径: /ftp_download.txt 大小: 62 字节
[2026-01-30 16:45:27.066] luat:U(8030):I/user.下载文件内容长度小于512字节，内容是: 23noianfdiasfhnpqw39fhawe;fuibnnpw3fheaios;fna;osfhisao;fadsfl
[2026-01-30 16:45:27.113] luat:U(8080):I/user.删除测试目录QWER 250 Remove directory operation successful.
[2026-01-30 16:45:27.113] 
[2026-01-30 16:45:27.238] luat:U(8224):I/user.FTP连接关闭结果: 221 Goodbye.
[2026-01-30 16:45:27.238] 
[2026-01-30 16:45:27.246] luat:U(8224):I/user.meminfo内存信息 238200 42152 54656

```
