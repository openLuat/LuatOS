## 演示功能概述

本demo支持两种基于USB的网络连接模式：RNDIS和ECM。

- **RNDIS**（Remote NDIS）：基于USB实现的TCP/IP over USB，让USB设备在Windows系统上呈现为一块网卡，从而使Windows/Linux可以通过USB设备连接网络。

- **ECM**（Ethernet Control Model）：一种基于USB的通信设备类（CDC）子类协议，将"TCP/IP over USB"抽象成一条虚拟以太网链路，在主机侧呈现为一块标准的以太网卡。Linux、macOS等操作系统无需额外专用驱动即可使用。

#### 1、功能使用说明

本demo已将功能拆分为三个文件：
- `main.lua`：主入口文件，负责加载和调度各个功能模块
- `open_rndis.lua`：RNDIS功能实现模块
- `open_ecm.lua`：ECM功能实现模块

由于 Air780Exx 系列模组 只支持 LUATOS 模式，且RNDIS/ECM网卡应用默认关闭，需要使用接口打开。

**注意：**
- 本demo在Windows系统上主要测试RNDIS功能
- ECM功能由于Windows系统缺少测试环境，无法在Windows上完整测试

#### 2、启动 RNDIS 服务

- 运行 rndis_task 任务，来执行开启 RNDIS 的操作。

- RNDIS 需要在飞行模式下开启，所以首先进入飞行模式。

- 进入飞行模式后，使用 mobile.config(mobile.CONF_USB_ETHERNET, 3) 来启用 RNDIS 功能。

> 函数讲解：mobile.config(mobile.CONF_USB_ETHERNET, 3)
传入的第二个参数 3 ，实际为二进制的 0011
从右往前数第0个bit位为1,则开启USB以太网卡控制,第一个bit位为1,则使用NAT模式(基站分配ip),第二个bit位为0,则开启RNDIS模式。

#### 3、启动 ECM 服务

- 运行 ecm_task 任务，来执行开启 ECM 的操作。

- ECM 需要在飞行模式下开启，所以首先进入飞行模式。

- 进入飞行模式后，使用 mobile.config(mobile.CONF_USB_ETHERNET, 7) 来启用 ECM 功能。

> 函数讲解：mobile.config(mobile.CONF_USB_ETHERNET, 7)
传入的第二个参数 7 ，实际为二进制的 0111
从右往前数第0个bit位为1,则开启USB以太网卡控制,第一个bit位为1,则使用NAT模式(基站分配ip),第二个bit位为1,则开启ECM模式。

> 特别说明：由于Windows系统缺少测试环境，ECM功能无法在Windows系统上完整测试。在Linux、macOS等系统上可能需要不同的配置和测试方法。
>
>注：在v2013以下固件使用mobile.config()的返回值有bug，无论是否开启成功，返回值均为false，需要烧录V2013及以上固件才能完整验证此功能。

#### 4、运行效果

- **飞行模式进入成功**：日志打印 “进入飞行模式成功”

- **RNDIS 创建成功**：日志中会打印“我看看 RNDIS 是否启动成功： true”，并且在电脑网络上显示出RNDIS联网图标。

- **ECM 创建**：由于Windows系统缺少测试环境，ECM功能在Windows系统上无法完整测试。在日志中会打印“我看看 ECM 是否启动成功： [结果]”，但无法在Windows系统上验证网络连接状态。

> **注意**：在main.lua中，RNDIS和ECM功能默认只启用了RNDIS。如需测试ECM功能，请修改main.lua文件，注释掉`require "open_rndis"`并取消注释`require "open_ecm"`

## 演示硬件环境

1、Air780Exx 系列模组核心板/开发板一块

2、配套天线一套

3、TYPE-C USB数据线一根

## 演示软件环境

1、Luatools下载调试工具

2、[Air780Exx 系列模组 版本固件](https://docs.openluat.com/air780Exx 系列模组/luatos/firmware/)（V2013以下固件使用mobile.config()的返回值有bug，需要烧录V2013及以上固件才能完整验证此demo）

3、确保插入的sim卡可以正常上网。

## 演示核心步骤

### RNDIS功能测试步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中（默认启用RNDIS功能）

3、烧录好后，板子开机同时在luatools上查看日志，确认是否进入飞行模式、RNDIS是否启用成功。

`
[2025-08-22 09:55:54.459][000000000.210] I/user.main RNDIS_ECM 1.0.0
[2025-08-22 09:55:54.529][000000000.661] I/user.进入飞行模式成功,打开RNDIS模式
[2025-08-22 09:55:54.533][000000000.661] I/user.我看看 RNDIS 是否启动成功： true
[2025-08-22 09:55:54.649][000000000.815] I/user.退出飞行模式 false

`

4、日志提示成功后，可以在**Windows** → **设备管理器** → **网络适配器** 中查看是否有 **“Remote NDIS based Internet Sharing Device”** 来确认 RNDIS是否开启成功，如果被禁用请手动开启。

### ECM功能测试说明

1、**修改配置**：在测试ECM功能前，需要修改main.lua文件，注释掉`require = "open_rndis"`并取消注释`require = "open_ecm"`

2、**烧录程序**：通过Luatools将修改后的demo与固件烧录到核心板中

3、**查看日志**：板子开机后在luatools上查看日志，确认是否进入飞行模式、ECM是否尝试启动

`
[2025-08-22 09:55:54.459][000000000.210] I/user.main RNDIS_ECM 1.0.0
[2025-08-22 09:55:54.529][000000000.661] I/user.进入飞行模式成功,打开ECM模式
[2025-08-22 09:55:54.533][000000000.661] I/user.我看看 ECM 是否启动成功： [结果]
[2025-08-22 09:55:54.649][000000000.815] I/user.退出飞行模式 false

`

4、**特别说明**：由于Windows系统缺少测试环境，ECM功能在Windows系统上无法完整测试。即使日志显示ECM启动成功，也无法在Windows系统上验证网络连接状态。ECM功能主要适用于Linux、macOS等操作系统。
