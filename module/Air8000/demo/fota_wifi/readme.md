## 演示功能概述

本demo演示Air8000核心板的WiFi固件自动升级功能。

- **WiFi固件升级**：自动检查Air8000模组的WiFi固件是否为最新版本，若不是则自动启动升级过程。
- **全自动化流程**：从版本检查、下载到安装重启，整个过程无需手动干预。

#### 1、功能使用说明

本demo已将功能拆分为两个文件：
- `main.lua`：主入口文件，负责加载和调度升级模块
- `check_wifi.lua`：WiFi固件检查和升级功能实现模块

Air8000核心板在启动后会自动执行WiFi固件版本检查，若检测到有新版本，将自动下载并升级，升级完成后自动重启设备。

> **注意**：升级功能会自动将WiFi固件升级到最新版本，可能会导致与现有程序兼容性问题。在测试完毕后，建议取消对该模块的调用，防止后续版本更新影响程序稳定性。

#### 2、WiFi固件升级流程

- 设备启动后，`check_wifi.lua`模块会自动初始化并执行升级检查任务
- 系统会调用`exfotawifi.request()`接口检查是否有可用的WiFi固件更新
- 如发现新版本，系统会自动下载并安装新固件
- 下载完成后，系统会等待`AIRLINK_SFOTA_DONE`事件
- 事件触发后，设备将自动重启以完成固件更新

## 演示硬件环境

1、Air8000核心板/开发板一块

2、配套天线一套

3、TYPE-C USB数据线一根

4、可用SIM卡一张（确保可以正常联网）

## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（注意：固件版本需≥V2017版本才有`AIRLINK_SFOTA_DONE`事件）

3、确保插入的SIM卡可以正常上网

## 演示核心步骤

### WiFi固件升级测试步骤

1、搭建好硬件环境，确保Air8000开发板已连接电源和天线，插入可用的SIM卡

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机同时在luatools上查看日志，观察WiFi固件检查和升级过程：

```lua
[2025-10-28 19:51:06.947][000000002.240] I/airlink AIRLINK_READY 2240 version 11 t 2085
[2025-10-28 19:51:06.949][000000002.243] D/airlink Air8000s启动完成, 等待了 14 ms
[2025-10-28 19:51:06.950][000000002.265] I/user.main project name is  fota_wifi version is  001.000.000
[2025-10-28 19:51:14.761][000000010.617] D/mobile cid1, state0
[2025-10-28 19:51:14.763][000000010.618] D/mobile bearer act 0, result 0
[2025-10-28 19:51:14.765][000000010.618] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-28 19:51:14.766][000000010.619] I/user.exfotawifi 开始执行升级任务
[2025-10-28 19:51:14.768][000000010.625] I/user.exfotawifi 正在请求升级信息, URL: http://wififota.openluat.com/air8000/update.json?imei=864793080175404&version=11&muid=20250722125744A057364A8677024255&hw=A13&coreversion=V2017&model=Air8000
[2025-10-28 19:51:14.770][000000010.626] dns_run 676:wififota.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-10-28 19:51:14.830][000000010.714] dns_run 693:dns all done ,now stop
[2025-10-28 19:51:14.833][000000010.716] D/mobile TIME_SYNC 0
[2025-10-28 19:51:15.004][000000010.885] I/user.exfotawifi 获取服务器响应成功
[2025-10-28 19:51:15.007][000000010.886] I/user.exfotawifi 解析服务器响应成功
[2025-10-28 19:51:15.009][000000010.886] I/user.exfotawifi 需要升级, 本地版本: 11 服务器版本: 14
[2025-10-28 19:51:15.050][000000010.934] D/vfs fopen /http_download/fotawifi.bin r not found
[2025-10-28 19:51:15.053][000000010.935] dns_run 676:wififota.openluat.com state 0 id 2 ipv6 0 use dns server2, try 0
[2025-10-28 19:51:15.114][000000010.996] dns_run 693:dns all done ,now stop
[2025-10-28 19:51:34.266][000000030.150] I/user.exfotawifi 下载升级文件成功,文件路径: /http_download/fotawifi.bin
[2025-10-28 19:51:34.269][000000030.155] D/airlink.fota 执行g_airlink_fota 0 c0c3e64
[2025-10-28 19:51:34.271][000000030.156] I/user.exfotawifi 升级成功
[2025-10-28 19:51:34.274][000000030.156] I/user.exfotawifi 升级任务执行成功
[2025-10-28 19:51:34.276][000000030.160] I/airlink.fota 开始执行sFOTA file size 809680
[2025-10-28 19:51:34.277][000000030.163] I/airlink.fota 等待sFOTA初始化 500ms
[2025-10-28 19:51:34.814][000000030.697] D/airlink.fota sfota sent 4096/809680 head 696D696C
[2025-10-28 19:51:34.863][000000030.746] D/airlink.fota sfota sent 8192/809680 head A4024B78
[2025-10-28 19:51:42.896][000000038.780] D/airlink.fota sfota sent 12288/809680 head C1B17347
...
[2025-10-28 19:51:52.344][000000048.229] D/airlink.fota sfota sent 802816/809680 head 88AC2008
[2025-10-28 19:51:52.392][000000048.278] D/airlink.fota sfota sent 806912/809680 head 8AD61D93
[2025-10-28 19:51:52.454][000000048.327] I/airlink.fota 文件数据发送结束, 等待100ms,执行done操作
[2025-10-28 19:51:53.042][000000048.927] I/airlink.fota done发送结束, 等待100ms, 执行end操作
[2025-10-28 19:51:53.153][000000049.028] I/airlink.fota end发送结束, 等待3000ms, 执行重启操作
[2025-10-28 19:51:56.157][000000052.028] I/airlink.fota 使用命令复位
[2025-10-28 19:52:26.142][000000082.029] I/airlink.fota FOTA执行完毕
[2025-10-28 19:52:26.145][000000082.030] I/user.fotawifi WIFI下载完毕，开始重启

```

4、设备重启后，WiFi固件已更新到最新版本

```lua
[2025-11-06 14:06:13.564][000000000.649] I/airlink AIRLINK_READY 649 version 14 t 557
[2025-11-06 14:06:13.568][000000000.679] I/user.main project name is  fota_wifi version is  001.000.000
[2025-11-06 14:06:14.093][000000006.884] I/user.exfotawifi 开始执行升级任务
[2025-11-06 14:06:14.093][000000006.890] I/user.exfotawifi 正在请求升级信息, URL: http://wififota.openluat.com/air8000/update.json?imei=864793080175404&version=14&muid=20250722125744A057364A8677024255&hw=A13
[2025-11-06 14:06:14.142][000000006.962] dns_run 693:dns all done ,now stop
[2025-11-06 14:06:14.263][000000007.082] I/user.exfotawifi 获取服务器响应成功
[2025-11-06 14:06:14.264][000000007.082] I/user.exfotawifi 解析服务器响应成功
[2025-11-06 14:06:14.267][000000007.083] I/user.exfotawifi 当前已是最新WIFI固件
[2025-11-06 14:06:14.267][000000007.083] I/user.exfotawifi 升级任务执行成功
```

## 常见问题和注意事项

1、**升级失败问题**：
   - 确保SIM卡正常联网
   - 检查网络信号强度是否良好

2、**版本兼容性**：
   - 最新的WiFi固件可能与部分API或功能存在兼容性问题
   - 测试完成后，建议在生产环境中注释掉`require "check_wifi"`，避免自动升级到未经测试的版本

3、**无法获取系统消息问题**：
   - 需要检查下固件版本，固件版本需≥V2017版本才有`AIRLINK_SFOTA_DONE`事件
