## 演示功能概述

1.1 蓝牙配网是什么
蓝牙配网是一种利用蓝牙低功耗（BLE）链路，在未联网设备与手机之间建立本地安全通道，把 Wi-Fi 的 SSID、密码及其他网络参数传递给设备，使其独立完成 STA 或 SOFTAP 联网的技术方案。

1.3 蓝牙配网原理
设备在上电后进入配网模式，作为 BLE Peripheral 持续广播自定义的配网服务 UUID；手机 APP 作为 Central 扫描并建立 GATT 连接，随后通过加密特征值把网络参数下发给设备。设备收到参数后，启用 Wi-Fi 并执行联网流程。

1.4 蓝牙配网流程：
> 1\. 广播
设备以固定间隔广播配网服务，等待手机连接。
>
> 2\.  连接
手机 APP 扫描 → 选择目标设备 → 建立 BLE 连接。
>
> 3\. 选择配网方式
在 APP 界面选择：
station 模式：设备直接作为 Station 连接路由器。
softap 模式：设备通过 4G 开 AP 热点，用于其他设备连接（由于Air8101本身内部没有4G，所以暂时不支持配置AP功能）。

蓝牙配网就是让Air8101工作在蓝牙配网模式下，手机app通过蓝牙连接Air8101,通过app内界面实现配网功能。

本示例基于合宙 Air8101 模组，演示 **“STA + SoftAP 双模式 BLE 配网”** 的完整流程。手机通过 BLE 下发 Wi-Fi 账号/密码或热点参数，模组自动完成 STA 连接或 SoftAP 创建，并验证网络可用性。核心流程如下：

---

#### 1、初始化蓝牙协议栈

调用 `bluetooth.init()` 完成 BLE 协议栈加载。

---

#### 2、启动 BLE 配网服务

- 加载 `espblufi` 模块，注册回调 `espblufi_callback`

- 广播自定义名称 **BLUFI\_xxx**（xxx = 模组型号）

- 手机端使用 **ESP Blufi** 官方 App 连接并配置参数

---

#### 3、STA 配网流程

1. App 通过 BLE 发送 **SSID + Password**

2. 模组收到后调用 `wlan.connect()` 连接目标路由器

3. 轮询 `netdrv.ipv4()` 直至拿到有效 IP（30 s 超时）

4. 成功后通过 HTTP GET `https://httpbin.air32.cn/bytes/2048` 验证外网

5. 若连接失败，主动断开并上报 `STA_DISCONNED` 事件

---

#### 4、SoftAP 创建流程（Air8101暂不支持）

1. App 通过 BLE 发送 **AP_SSID / AP_Password / Channel / MaxConn**

2. 模组调用 `wlan.createAP()` 创建 2.4 GHz 热点

3. 设置静态 IP：`192.168.4.1/24`

4. 启动 DHCP：`dhcpsrv.create()` 为终端分配 192.168.4.100–200

5. 启用 DNS 代理：`dnsproxy.setup()`，把终端 DNS 请求转发到模组已有出口（蜂窝或 STA），实现零配置上网

6. 订阅 `WLAN_AP_INC` 实时打印终端连接/断开日志

---

#### 5、多网融合（可选）

通过 `exnetif.setproxy()` 把 **4G/STA/以太网** 设为数据出口，供热点终端共享上网。

---

#### 6、运行效果

- **STA 配网成功**：日志打印 `STA CONNED OK!`，并输出 HTTP 200 结果

- **SoftAP 创建成功**：手机搜索到指定热点，连接后即可直接访问互联网

- **实时日志**：终端连接/断开、IP 分配、HTTP 测试结果全程可见

---

#### 7、快速上手

1. 烧录固件后上电，模组自动进入 BLE 广播

2. 手机安装 **ESP Blufi**（或微信搜索“ESP Config”小程序）

3. 选择 **“BLUFI\_xxx”** 设备 → 连接 → 配网 → 选择 **“STA 模式”** 或 **“AP 模式”（Air8101暂不支持）** → 填写参数 → 一键下发

4. 观察串口日志即可确认结果

## 演示硬件环境

1、Air8101核心板/开发板一块

2、配套天线一套

3、TYPE-C USB数据线一根

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1005版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1005固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、在main.lua文件中选择好要使用的功能，通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机同时在luatools上查看日志，确认WiFi是否为最新版本：

4、下载手机端APP：

- [安卓测试APP下载地址1](https://github.com/EspressifApp/EspBlufiForAndroid/releases)（如果打不开就用下面的）

- [安卓测试APP下载地址2](https://docs.openluat.com/cdn2/apk/blufi-1.6.5-31.apk)

5、确认APP 下载好后，使用APP 连接核心板的蓝牙，APP会自动搜索到**BLUFI_xxx**（xxx = 模组型号） 本篇demo 的设备名应该为 BLUFI_Air8101（app端可能存在问题，有时候搜索不到设备蓝牙，但是用手机可以搜到。**如果搜索不到，就重启一下模组，并且在APP端下拉刷新一下**）

6、点击**BLUFI_Air8101**设备，进入配网页面。

7、在配网页面中，依次点击**设备** → **连接** → **配网** → 选择 **“STA 模式”** 或 **“AP 模式”（Air8101暂不支持）** → 填写参数 → 一键下发

8、如果是STA模式，连接上配置的WIFI热点后，会进行`HTTP GET`测试。

9、（Air8101暂不支持）如果是AP模式，会根据在APP端配置的SSID、passwd、channel、maxconn来创建一个WIFI热点，供设备使用。
