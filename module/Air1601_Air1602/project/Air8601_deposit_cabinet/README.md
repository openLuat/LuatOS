# Air1601 智能寄存柜（8601寄存柜+人脸识别摄像头）

## 功能模块介绍

1、user/main.lua：主程序入口，加载硬件/业务/网络/串口/界面/人脸/FOTA 模块后，初始化看门狗（超时 60 秒、每 3 秒喂狗）并启动系统初始化任务，最后进入主循环；

2、user/config.lua：系统配置模块，提供服务器地址、柜子数量、串口参数、FOTA 配置等配置参数的读写，各业务模块通过 config.get(key)/config.set(key, value) 读写配置；

3、user/hardware.lua：硬件初始化模块，完成 GPIO 上电、LCD 屏幕初始化、AirUI 初始化、背光开启、触摸初始化、屏幕密度缩放等；

4、user/netdrv_wifi.lua：WiFi 网卡驱动模块，通过 UART3 外挂 Air6205 WiFi 模组（airlink over uart，GPIO57 拉低使能）接入互联网，自动获取 IP；

5、user/network_4g.lua：4G 网卡驱动模块（备用，当前 main.lua 未 require），通过 UART 接口外挂 4G 模组接入互联网；

6、user/uart_controller.lua：485 锁控板通讯模块，实现开锁、读取锁状态、接收锁控板主动上报等功能（9600 8N1，协议见文件头注释）；

7、user/aircloud.lua：AirCloud 云平台模块，基于 excloud 库实现设备鉴权、业务数据上报、服务器控制指令接收、取件码与柜号映射持久化（fskv）等功能；

8、user/server_api.lua：服务器接口模块，实现柜子状态同步、刷脸存件登记、刷脸取件上报、微信小程序码获取等 HTTP API 通信；

9、user/ecbusiness.lua：寄存柜业务逻辑模块，实现存件、取件、刷脸存件、刷脸取件、验证取件码等业务流程的调度与状态管理，提供业务繁忙保护接口（is_busy）供 FOTA 检测时避开业务高峰；

10、user/ecabinet.lua：主窗口模块，显示智能寄存柜主界面，提供存件、取件、帮助、管理四个功能入口；

11、user/ecsend.lua：存件窗口模块，显示微信小程序码并引导用户扫码存件；

12、user/ecrecv.lua：取件窗口模块，支持键盘输入取件码并触发开柜取件；

13、user/eccourier.lua：快递员管理窗口模块，管理员密码验证后进入管理功能；

14、user/eccourier_detail.lua：快递员管理详情模块，开箱、查看柜子状态等管理操作；

15、user/echelp.lua：帮助窗口模块，显示系统使用说明；

16、user/ecboxstatus.lua：柜子状态窗口模块，显示各柜子的占用/空闲状态；

17、user/ecface.lua：刷脸界面模块，提供刷脸存件、刷脸取件窗口及流程编排；

18、user/ecface_manage.lua：人脸管理界面模块，提供人脸注册、删除、列表管理等入口；

19、user/face_manager.lua：人脸识别模块管理，完成人脸模组供电稳定等待、打开/注册/验证人脸、人脸与柜号绑定关系维护等；

20、user/exfacecam.lua：人脸识别模组通信封装，通过 UART2（115200 8N1）与人脸识别模组交互（仅 UART 通信，不初始化 USB 摄像头）；

21、user/face_preview.lua：人脸预览模块，通过 USB 摄像头（AirCAMERA，320x240 MJPEG）实现刷脸前的人脸画面预览，预览结束后复位人脸模组；

22、user/face_demo.lua：人脸识别演示模块，用于单板快速验证人脸注册/识别流程；

23、user/tp_gt911.lua：GT911 电容触摸屏驱动模块，完成触摸芯片初始化与事件绑定；

24、user/lcd_hx8282_10in.lua：HX8282 10.1 寸 LCD 驱动模块，完成屏幕初始化；

25、user/fota_manager.lua：FOTA 升级管理模块，配置注入、业务保护（on_confirm 检查 ecbusiness.is_busy）、状态维护（downloading 下载让道）、下

载失败整机重启兜底（≤3 次）、下载完成后 EN(GPIO57) 断电隔离 6205 保护写 flash；

26、user/libfota3.lua：官方原版 FOTA 库（v2.0，2026.06.18），负责检测/下载/SHA256 校验/写 flash/开机版本比对上报，保持原版未做任何定制；

## 演示功能概述

1、AirUI 图形界面：1024x600 分辨率的智能寄存柜主界面，提供存件、取件、帮助、管理四个功能入口；

2、WiFi 网络通信：通过 UART3 外挂 Air6205 WiFi 模组（airlink over uart，GPIO57 拉低使能）接入互联网，自动获取 IP；

3、AirCloud 云平台：设备通过 excloud 库连接 AirCloud 平台，完成鉴权、业务数据上报、服务器控制指令接收；

4、微信小程序码：存件时自动请求服务器生成微信小程序二维码，保存到本地并显示在存件窗口；

5、485 锁控板控制：通过 uart1 + 485 总线与 7 路锁控板通信，支持开锁、读取锁状态、接收主动上报；

6、刷脸存件流程：点击刷脸存件 → USB 摄像头预览 → 人脸模组注册 → 服务器 face_store 登记 → 选柜开柜 → 显示取件码/存件码；

7、刷脸取件流程：点击刷脸取件 → USB 摄像头预览 → 人脸模组验证 → 匹配绑定柜号 → 开柜取件 → 服务器 carry 上报；

8、取件码存件/取件流程：输入取件码 → 本地校验（内存 + fskv 持久化）→ 开柜取件，服务器可通过 AirCloud 下发存件命令（save,柜号,取件码）预存取件码；

## 演示硬件环境

1、Air8601 开发板一块

2、TYPE-C USB 数据线一根

3、Air1601 开发板和数据线的硬件接线方式为：

- Air1601 开发板通过 TYPE-C USB 口连接 TYPE-C USB 数据线，数据线的另外一端连接电脑的 USB 口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；

5、智能寄存柜锁控板一套，通过 485 总线（uart1）与 Air1601 开发板连接；

6、10.1 寸 RGB LCD 屏（HX8282 驱动）与 GT911 电容触摸屏一套，通过 RGB/I2C 接口与 Air1601 开发板连接；

7、AirCAMERA 1034一个，插入 Air8601 开发板 USB Host 口，过 UART2（115200 8N1）与 Air8601 开发板连接用于刷脸预览；

![](https://docs.openluat.com/cdn/image/Air1601/8601jicungui1.jpg)

## 演示软件环境

1、[Luatools 工具](https://docs.openluat.com/air1601/common/Luatools/)；

2、内核固件文件（底层 core 固件文件）：本 demo 开发测试时使用的固件为 [Air1601 最新版本固件](https://docs.openluat.com/air1601/luatos/firmware/)；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools 烧录内核固件和 demo 脚本代码（含 res/ 目录资源文件）

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-09-01 19:35:29.477][LTOS/N][000000000.021]:I/user.main DEPOSIT_CABINET 001.999.005
[2026-09-01 19:35:31.527][LTOS/N][000000002.124]:I/user.main 系统初始化完成
[2026-09-01 19:35:31.746][LTOS/N][000000002.354]:I/user.ecabinet 主窗口打开成功 1
[2026-09-01 19:35:31.748][LTOS/N][000000002.354]:I/user.uart_controller 收到读取锁状态请求
[2026-09-01 19:35:31.750][LTOS/N][000000002.355]:I/user.uart_controller 发送命令 80010033B2 10
```

刷脸存件流程日志示例：

``` lua
[2026-09-01 17:23:23.468][LTOS/N][000000019.083]:I/user.刷脸存件按键触发
[2026-09-01 17:23:23.477][LTOS/N][000000019.083]:I/user.ecface 打开刷脸窗口，模式: deposit
[2026-09-01 17:23:30.028][LTOS/N][000000025.618]:I/user.face_manager 人脸注册成功，user_id=1
[2026-09-01 17:23:31.282][LTOS/N][000000026.799]:I/user.ecbusiness 人脸存件成功，箱子: 6, 取件码: 310185
```

取件码取件流程日志示例：

``` lua
[2026-09-01 17:23:52.844][LTOS/N][000000048.454]:D/user.ecrecv 输入的取件码: 123456, 类型: string
[2026-09-01 17:23:52.859][LTOS/N][000000048.454]:I/user.ecrecv 发布开柜请求 3
[2026-09-01 17:23:52.865][LTOS/N][000000048.457]:I/user.uart_controller 收到开锁请求 3
[2026-09-01 17:23:52.877][LTOS/N][000000048.458]:I/user.uart_controller 发送命令 8A01031199 10
```

FOTA 升级成功日志示例：

``` lua
[2026-09-01 19:34:18.780][LTOS/N][000000078.304]:I/user.libfota3 sha256 verified
[2026-09-01 19:35:05.136][LTOS/N][000000124.632]:I/user.libfota3 download and flash complete
[2026-09-01 19:35:29.477][LTOS/N][000000000.021]:I/user.main DEPOSIT_CABINET 001.999.005
[2026-09-01 19:35:29.929][LTOS/N][000000000.519]:I/user.libfota3 upgrade success core_changed true script_changed true
```

## 注意事项

1、本 demo 使用 Air1601 开发板，通过 UART3 外挂 Air6205 WiFi 模组实现网络通信（airlink over uart，2M 波特率），GPIO57 拉低使能；FOTA 写 flash 前 fota_manager 会拉高 GPIO57 断电隔离 WiFi 模组，升级完成后重启自动恢复使能；

2、服务器接口地址在 user/config.lua 中配置，接入生产环境时请修改为实际服务器地址；FOTA 项目密钥（project_key）也在 config.lua 的 fota 段配置，发版请到合宙云平台对应项目操作；

3、锁控板协议为自定义 485 协议（9600 8N1），协议格式见 user/uart_controller.lua 头注释，实际使用时按锁控板厂家协议调整；

4、人脸识别模组通过 UART2（115200 8N1）与主控通信，USB 摄像头仅用于刷脸画面预览；人脸模组初始化有供电稳定等待，勿在上电瞬间直接调用注册/验证接口；
