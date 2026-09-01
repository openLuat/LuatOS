## 功能模块介绍

1、main.lua：主程序入口，加载硬件/业务/网络/串口/界面模块后，启动系统初始化任务并进入主循环；

2、user/config.lua：系统配置模块，提供服务器地址、柜子数量、串口参数等配置参数的读写，各业务模块通过 config.get(key)/config.set(key, value) 读写配置；

3、user/hardware.lua：硬件初始化模块，完成 GPIO 上电、LCD 屏幕初始化、AirUI 初始化、背光开启、触摸初始化、屏幕密度缩放等；

4、user/network_4g.lua：4G 网卡驱动模块，通过 UART 接口外挂 4G 模组（Air780EPM）接入互联网，自动获取 IP；

5、user/uart_controller.lua：485 锁控板通讯模块，实现开锁、读取锁状态、接收锁控板主动上报等功能（9600 8N1，协议见文件头注释）；

6、user/aircloud.lua：AirCloud 云平台模块，基于 excloud 库实现设备鉴权、业务数据上报、服务器控制指令接收等功能；

7、user/server_api.lua：服务器接口模块，实现存件、取件、柜子状态同步、微信小程序码生成等 HTTP API 通信；

8、user/ecbusiness.lua：寄存柜业务逻辑模块，实现存件、取件、验证取件码等业务流程的调度与状态管理；

9、user/ecabinet.lua：主窗口模块，显示智能寄存柜主界面，提供存件、取件、帮助、管理四个功能入口；

10、user/ecsend.lua：存件窗口模块，显示微信小程序码并引导用户扫码存件；

11、user/ecrecv.lua：取件窗口模块，支持键盘输入取件码并触发开柜取件；

12、user/eccourier.lua：快递员管理窗口模块，管理员密码验证后进入管理功能；

13、user/eccourier_detail.lua：快递员管理详情模块，开箱、查看柜子状态等管理操作；

14、user/echelp.lua：帮助窗口模块，显示系统使用说明；

15、user/ecboxstatus.lua：柜子状态窗口模块，显示各柜子的占用/空闲状态；

16、user/tp_gt911.lua：GT911 电容触摸屏驱动模块，完成触摸芯片初始化与事件绑定；

17、user/lcd_hx8282_10in.lua：HX8282 10.1 寸 LCD 驱动模块，完成屏幕初始化；

## 演示功能概述

1、AirUI 图形界面：1024x600 分辨率的智能寄存柜主界面，提供存件、取件、帮助、管理四个功能入口；

2、4G 网络通信：通过 UART 外挂 Air780EPM 4G 模组（airlink over uart）接入互联网，自动获取 IP；

3、AirCloud 云平台：设备通过 excloud 库连接 AirCloud 平台，完成鉴权、业务数据上报、服务器控制指令接收；

4、微信小程序码：存件时自动请求服务器生成微信小程序二维码（wx_gen_app_code），保存到本地并显示在存件窗口；

5、485 锁控板控制：通过 uart1 + 485 芯片（GPIO8 使能）与 7 路锁控板通信，支持开锁、读取锁状态、接收主动上报；

6、存件流程：用户扫码 → 选择柜子 → 调服务器 face_store 接口 → 开柜 → 显示取件码/存件码；

7、取件流程：输入取件码 → 校验 → 调服务器取件接口 → 开柜；

8、服务器命令下发：服务器通过 AirCloud 下发存件命令（save,柜号,取件码），设备保存取件码与柜号映射，取件时校验。

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

1、Air8602 开发板一块

2、TYPE-C USB 数据线一根

3、Air8602 开发板和数据线的硬件接线方式为：

- Air8602 开发板通过 TYPE-C USB 口连接 TYPE-C USB 数据线，数据线的另外一端连接电脑的 USB 口；
- 在 Air8602 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

4、4G 模组一块（Air780EPM），通过 UART3 与 Air1601 开发板连接（airlink 协议），需插入可上网的 SIM 卡；

5、智能寄存柜锁控板一套（7 路），通过 485 总线（uart1 + GPIO8 使能）与 Air1601 开发板连接；

6、10.1 寸 RGB LCD 屏（HX8282 驱动）与 GT911 电容触摸屏一套，通过 RGB/I2C 接口与 Air1601 开发板连接；

7、棒状天线一根

![](https://docs.openluat.com/cdn/image/Air1601/8601_jicungui.jpg)

## 演示软件环境

1、[Luatools 工具](https://docs.openluat.com/air1601/common/Luatools/)；

2、内核固件文件（底层 core 固件文件）：本 demo 开发测试时使用的固件为 [Air8602 最新版本固件](https://docs.openluat.com/air1601/luatos/firmware/)；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools 烧录内核固件和 demo 脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-08-31 08:19:03.292][LTOS/N][000000001.758]:I/user.aircloud 模拟服务器下发存件命令: save,1,665501
[2026-08-31 08:19:03.357][LTOS/N][000000001.801]:I/user.main 系统初始化完成
[2026-08-31 08:19:03.507][LTOS/N][000000002.014]:I/user.ecabinet 主窗口打开成功 1
[2026-08-31 08:19:03.514][LTOS/N][000000002.014]:I/user.uart_controller 收到读取锁状态请求
[2026-08-31 08:19:03.519][LTOS/N][000000002.014]:I/user.uart_controller 发送命令 80010033B2 10
```

存件流程日志示例：

``` lua
[2026-08-31 08:38:45.519][LTOS/N][000000189.628]:I/user.存件按键触发
[2026-08-31 08:38:45.526][LTOS/N][000000189.629]:I/user.ecsend 准备打开存件窗口
[2026-08-31 08:38:45.532][LTOS/N][000000189.629]:I/user.ecsend 打开存件窗口
[2026-08-31 08:38:45.538][LTOS/N][000000189.639]:I/user.ecsend 小程序码图片文件有效，直接显示
[2026-08-31 08:38:45.574][LTOS/N][000000189.681]:I/airui.jpg use hardware jpeg decode: /qr_code.jpeg
```

取件流程日志示例：

``` lua
[2026-08-31 08:37:13.943][LTOS/N][000000098.054]:D/user.ecrecv 输入的取件码: 123456, 类型: string
[2026-08-31 08:37:13.957][LTOS/N][000000098.054]:I/user.ecrecv 发布开柜请求 3
[2026-08-31 08:37:13.962][LTOS/N][000000098.058]:I/user.uart_controller 收到开锁请求 3
[2026-08-31 08:37:13.967][LTOS/N][000000098.058]:I/user.uart_controller 发送命令 8A01031199 10
[2026-08-31 08:37:13.972][LTOS/N][000000098.059]:I/user.uart_controller 命令发送成功
```

## 注意事项

1、本 demo 使用 Air8601 开发板，通过 UART3 外挂 Air780ER2 4G 模组实现网络通信（airlink over uart），外挂模组需烧录配套固件与脚本；

2、服务器接口地址在 user/config.lua 中配置，接入生产环境时请修改为实际服务器地址；

3、锁控板协议为自定义 485 协议（9600 8N1），协议格式见 user/uart_controller.lua 头注释，实际使用时按锁控板厂家协议调整；

4、main.lua 中保留了 3 条模拟服务器下发存件命令（test_send_save_command），用于本地演示存件/取件流程；对接真实服务器后如需移除，删除对应 3 行即可；

5、存件二维码显示依赖服务器 wx_gen_app_code 接口返回有效的 JPEG 图片（已兼容非 16 倍数尺寸，如 280x280），若接口异常会自动回退显示默认二维码（docs.openluat.com）。
