## 演示功能概述

### 1.1 远程文件管理系统概述

本工程基于 **780EXX 核心板** + **外挂 Air6205 WiFi核心板**，复用 LuatOS 标准扩展库 `exremotefile` 实现远程文件管理系统。

设备通过 UART2 连接 Air6205，创建 AP 热点并提供 HTTP 文件服务。用户连接到设备 WiFi 热点后，通过浏览器即可访问文件管理系统。

### 1.2 系统工作原理

```
780EXX核心板 ──UART2(airlink协议)── Air6205(WiFi核心板)
                                         │
                                   创建AP热点: LuatOS_FileHub
                                         │
                              ┌──────────┴──────────┐
                           手机连接热点        电脑连接热点
                              │                    │
                          浏览器访问 http://192.168.4.1:80/explorer.html
```

1. 设备上电后，按 boot 按键触发服务启动
2. `exremotefile` 扩展库自动检测到 780EXX 系列模组，先通过 airlink UART 协议初始化 Air6205（GPIO复位 + UART2 配置 + airlink 启动）
3. Air6205 初始化完成后，创建 `LuatOS_FileHub` 热点
4. 同时启动 HTTP 文件服务器，监听 `192.168.4.1:80`
5. 手机/电脑连接热点后，浏览器访问即可管理文件

### 1.3 核心功能特性

- **任务控制**：通过 boot 按键控制服务启停
- **热点创建**：设备自动创建名为 `LuatOS_FileHub` 的 WiFi 热点
- **文件浏览**：通过浏览器查看设备内部存储中的文件列表
- **文件下载**：支持直接通过 URL 下载文件
- **文件上传**：支持通过网页上传文件（<200KB）
- **文件删除**：支持通过网页删除文件
- **用户认证**：提供用户名密码认证机制

### 1.4 硬件接线

| Air780EXX核心板 | Air6205核心板 |
|-----------------|---------------|
| 28/U2RXD        | U1_TX         |
| 29/U2TXD        | U1_RX         |
| VBAT            | VBAT          |
| GND             | GND           |

> Air6205 通过 UART2 与 780EXX 通信，使用 airlink 协议，波特率 2000000。

### 1.5 系统控制方式

- **自动启动模式**：在 `task_control.lua` 中设置 `AUTO_START=true`，系统开机后自动初始化 Air6205、创建 AP 热点并启动 HTTP 文件服务器
- **手动控制模式**：默认设置 `AUTO_START=false`，通过短按 boot 按键（GPIO0）来控制系统的启动和停止

## 演示硬件环境

1. Air780EXX 核心板/开发板一块（如 Air780EHM、Air780EHV）
2. Air6205 WiFi核心板一块
3. 配套天线一套
4. TYPE-C USB数据线一根

Air780Exx 核心板 + Air6205 核心板

![](https://docs.openluat.com/common/image/780EXX+6205-1.jpg)

Air780EXX 开发板 + Air6205 核心板

![](https://docs.openluat.com/common/image/780EXX+6205-2.jpg)

## 演示软件环境

1. Luatools 下载调试工具
2. [Air780EHM 最新固件](https://docs.openluat.com/air780epm/luatos/firmware/780ehm_version/)

## 演示核心步骤

1. 按照接线表连接 780EXX 核心板与 Air6205 核心板
2. 确保 `script/libs/explorer.html` 文件烧录到设备中
3. 通过 Luatools 将本工程代码与固件烧录到核心板
4. 烧录完成后，给设备上电，观察串口日志
5. 按下 boot 按键（GPIO0），系统开始启动：

```
[xxxxx] I/user.main              启动系统服务
[xxxxx] I/user.exremotefile      启动文件管理系统
[xxxxx] I/user.WIFI              初始化Air6205 airlink UART通道
[xxxxx] I/user.WIFI              Air6205 airlink通道已建立
[xxxxx] I/user.WIFI              创建AP热点: LuatOS_FileHub
[xxxxx] I/user.WIFI              AP热点创建成功
[xxxxx] I/user.exremotefile      文件管理系统启动完成
[xxxxx] I/user.HTTP              文件服务器已启动
[xxxxx] I/user.HTTP              请连接WiFi: LuatOS_FileHub，密码: 12345678
[xxxxx] I/user.HTTP              然后访问: http://192.168.4.1:80/explorer.html
```

6. 在手机或电脑的WiFi设置中，搜索并连接名为 `LuatOS_FileHub` 的热点，密码 `12345678`
7. 连接成功后，打开浏览器，输入 `http://192.168.4.1/explorer.html`，进入文件管理登录页面
8. 输入默认用户名 `admin` 和密码 `123456` 登录
9. 登录成功后，即可查看、下载、上传、删除设备中的文件

## 系统参数说明

### AP参数

- SSID：LuatOS_FileHub
- 密码：12345678
- IP地址：192.168.4.1

### 认证参数

- 默认用户名：admin
- 默认密码：123456
- 会话超时：3600秒（1小时）

### HTTP服务器参数

- 端口：80
- 访问地址：`http://192.168.4.1/explorer.html`

## 注意事项

1. 确保 `script/libs/explorer.html` 文件烧录到设备中，否则无法启动文件管理界面
2. 本工程支持SD卡挂载，如需使用请在 `exremotefile.open()` 中传入 SD 卡参数（默认不挂载）
3. 如需修改WiFi名称、密码或认证信息，请修改 `exremotefile.open()` 的传入参数
4. Air6205 上电后需要约 2 秒完成硬件初始化，请耐心等待
5. 如果重启后无法连接热点，可以重新按 boot 按键重新启动服务
6. `D/airlink uart_transfer_task send basic info 216` 日志为 airlink UART 心跳包，不影响功能
