## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统环境和加载httpdns_task模块；

2、httpdns_task.lua：HTTPDNS功能实现模块，演示如何使用阿里DNS和腾讯DNS进行域名解析；

## 演示功能概述

本demo演示如何通过HTTPDNS功能，在LuatOS环境下实现域名解析，从而绕过运营商DNS污染或劫持，提高网络访问稳定性。

HTTPDNS的主要功能特性：

1、**绕过DNS污染**：通过直接向指定DNS服务器发起HTTP/HTTPS请求获取域名解析结果，不依赖本地UDP 53端口，有效避免运营商DNS劫持问题；

2、**支持多种DNS服务**：内置支持阿里DNS和腾讯DNS两种主流的HTTPDNS服务提供商；

3、**简单易用**：仅需调用一行API即可完成域名解析；

4、**自动处理错误**：内置错误处理机制，当解析失败时会返回nil；

## 演示硬件环境

![](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、Air780EPM V1.3版本开发板一块+可上网的sim卡一张+4g天线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

2、TYPE-C USB数据线一根，Air780EPM V1.3版本开发板和数据线的硬件接线方式为：

- Air780EPM V1.3版本开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM 固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境，确保开发板能正常联网

2、使用Luatools烧录内核固件和demo脚本代码

3、烧录成功后，设备自动开机运行，等待网络就绪

4、当网络就绪后，设备会自动执行HTTPDNS解析任务，默认解析以下域名：
   - 通过阿里DNS解析 "air32.cn"
   - 通过腾讯DNS解析 "openluat.com"

5、通过串口调试工具，可以查看设备的运行日志，包括域名解析结果：

```lua
[2025-10-29 11:10:21.571][000000000.689] I/user.main HTTPDNS 001.000.000
[2025-10-29 11:10:22.614][000000007.414] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-29 11:10:22.615][000000007.415] I/user.已联网
[2025-10-29 11:10:22.633][000000007.454] D/mobile TIME_SYNC 0
[2025-10-29 11:10:23.726][000000008.548] I/user.httpdns air32.cn 49.232.89.122
[2025-10-29 11:10:23.882][000000008.697] I/user.httpdns openluat.com 121.40.220.186

```

6、如需修改解析的域名，只需修改httpdns_task.lua文件中的域名参数：

```lua
-- 示例：修改为解析其他域名
local ip = httpdns.ali("example.com")  -- 使用阿里DNS解析example.com
local ip = httpdns.tx("example.org")   -- 使用腾讯DNS解析example.org
```
