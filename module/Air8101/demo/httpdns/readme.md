## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统环境和加载httpdns_task模块；

2、netdrv_wifi.lua：WIFI STA网卡驱动模块，负责初始化WIFI网络、连接WIFI路由器并监控连接状态；

3、httpdns_task.lua：HTTPDNS功能实现模块，演示如何使用阿里DNS和腾讯DNS进行域名解析；

## 演示功能概述

1、httpdns_task：演示如何通过HTTPDNS功能，在LuatOS环境下实现域名解析，从而绕过运营商DNS污染或劫持，提高网络访问稳定性。

2、netdrv_wifi：WIFI STA网卡功能
   - 初始化WIFI网络并连接到指定的WIFI热点
   - 监控WIFI连接状态，通过"IP_READY"和"IP_LOSE"消息通知网络变化
   - 支持WIFI连接异常时自动重连
   - 仅支持2.4G WIFI，不支持5G WIFI

HTTPDNS的主要功能特性：

1、**绕过DNS污染**：通过直接向指定DNS服务器发起HTTP/HTTPS请求获取域名解析结果，不依赖本地UDP 53端口，有效避免运营商DNS劫持问题；

2、**支持多种DNS服务**：内置支持阿里DNS和腾讯DNS两种主流的HTTPDNS服务提供商；

3、**简单易用**：仅需调用一行API即可完成域名解析；

4、**自动处理错误**：内置错误处理机制，当解析失败时会返回nil；

## 演示硬件环境

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 固件](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

1、搭建好硬件环境，确保开发板能正常联网

2、配置WIFI连接信息：打开`netdrv_wifi.lua`文件，修改以下代码行中的WIFI热点名称和密码：

```lua
-- 连接WIFI热点，连接结果会通过"IP_READY"或者"IP_LOSE"消息通知
-- Air8101仅支持2.4G的WIFI，不支持5G的WIFI
-- 此处前两个参数表示WIFI热点名称以及密码，更换为自己测试时的真实参数即可
-- 第三个参数1表示WIFI连接异常时，内核固件会自动重连
wlan.connect("你的WIFI热点名称", "你的WIFI密码", 1)
```

**重要注意事项**：
- Air8101仅支持2.4GHz频段的WIFI网络，不支持5GHz频段
- 确保WIFI热点信号稳定，建议距离不要太远
- 密码区分大小写，请确保输入正确

3、使用Luatools烧录内核固件和demo脚本代码

4、烧录成功后，设备自动开机运行，等待网络就绪

5、当网络就绪后，设备会自动执行HTTPDNS解析任务，默认解析以下域名：
   - 通过阿里DNS解析 "air32.cn"
   - 通过腾讯DNS解析 "openluat.com"

6、通过串口调试工具，可以查看设备的运行日志，包括域名解析结果：

```lua
[2025-10-29 11:10:21.571][000000000.689] I/user.main HTTPDNS 001.000.000
[2025-10-29 11:10:22.614][000000007.414] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-29 11:10:22.615][000000007.415] I/user.已联网
[2025-10-29 11:10:22.633][000000007.454] D/mobile TIME_SYNC 0
[2025-10-29 11:10:23.726][000000008.548] I/user.httpdns air32.cn 49.232.89.122
[2025-10-29 11:10:23.882][000000008.697] I/user.httpdns openluat.com 121.40.220.186
```

7、如需修改解析的域名，只需修改httpdns_task.lua文件中的域名参数：

```lua
-- 示例：修改为解析其他域名
local ip = httpdns.ali("example.com")  -- 使用阿里DNS解析example.com
local ip = httpdns.tx("example.org")   -- 使用腾讯DNS解析example.org
```
