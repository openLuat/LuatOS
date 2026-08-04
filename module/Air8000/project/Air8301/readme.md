# Air8301 网关主机出厂工程

## 一、功能简介

Air8301 网关主机是基于 **Air8000W** 主控（4G + WiFi + BLE + SPI 屏）的工业物联网网关固件。通过 4.3 寸 ST6201 触摸屏提供人机交互，实现以下功能：

1. **多网通信**：以太网1 > 以太网2 > WiFi > 4G 自动切换（exnetif 统一管理，双 CH390H 网卡）
2. **双 RS485 / 双 RS232**：4 路工业串口收发，支持 8N1 115200（RS485 使用 uart 内置 RE/DE 方向控制）
3. **DI/DO**：2 路数字输入监测（GPIO16/17 中断）、2 路继电器输出控制（GPIO24/25）
4. **系统外设**：蜂鸣器、状态灯（4G/WiFi）、外部看门狗（Air153C，240s 超时）、SPI NAND Flash 存储、RELOAD 按键（长按 5 秒恢复出厂）
5. **触摸屏 UI**：12 个功能页面，基于 exwin 窗口管理 + AirUI 渲染引擎

---

## 二、硬件准备

| 硬件 | 数量 | 备注 |
|------|------|------|
| Air8301 网关主机 | 1 | 基于 Air8000W 主控，4.3寸 480x272 ST6201 SPI 屏 + GT911 触摸 |
| 电源 | 1 | 适配网关输入电压 |
| RS485/RS232 设备 | 可选 | 用于串口收发测试 |
| 网线 | 可选 | 用于以太网 1/2 测试 |
| SPI Flash | 1 | 板载 W25N01KVZEIR（或兼容 SPI NAND） |

---

## 三、硬件引脚速查

| 外设 | 引脚 | 说明 |
|------|------|------|
| LCD | LCD_EN=GPIO28, LCD_RST=GPIO36, 背光 PWM0=GPIO1_PWM0 | ST6201 4.3寸 480x272 SPI 屏 |
| 触摸 | GT911, I2C0, TP_RESET=GPIO26, TP_INT=WAKEUP0 | |
| 以太网1 | CH390H, SPI1/CS=GPIO12, INT=GPIO20, 供电=GPIO32 | 映射 LWIP_ETH |
| 以太网2 | CH390H, SPI1/CS=GPIO5, INT=CHG_DET, 供电=GPIO33 | 映射 LWIP_USER1 |
| RS485_1 | UART1, RE/DE=GPIO2, 供电=GPIO29 | uart 内置 RS485 模式 |
| RS485_2 | UART11, RE/DE=GPIO153, 供电=GPIO147 | |
| RS232_1 | UART2, 供电=GPIO30 | |
| RS232_2 | UART12, 供电=GPIO146 | |
| DI1/DI2 | GPIO16/GPIO17 | 输入中断，需上拉 |
| DO1/DO2 | GPIO24/GPIO25 | 继电器，高电平导通 |
| 蜂鸣器 | PWM2 (PIN98) | |
| 看门狗 | GPIO27 | air153C_wtd 扩展库，240s 超时/180s 喂狗 |
| Flash | SPI1/CS2=GPIO4, 供电=GPIO140 | W25N01KVZEIR，挂载 /flash |
| 状态灯 | 4G=GPIO21, WiFi=GPIO141 | 高电平亮 |
| 复位 | WAKEUP2 | 长按 5 秒恢复出厂 |

---

## 四、架构概览

### 分层事件驱动架构

main.lua 只负责加载程序，所有初始化由模块自身完成（require 即初始化），模块间通过全局消息解耦。

```
main.lua（设 PROJECT/VERSION）
    │
    ├── exwin（窗口管理器，全局）
    ├── lcd_st6201_43in（LCD + AirUI 初始化 → 发布 DISPLAY_READY）
    ├── tp_gt911（等待 DISPLAY_READY → 触摸初始化 → 绑定 AirUI）
    ├── app_main（加载业务模块 app/*）
    └── ui_main（加载窗口模块 ui/* → sys.run()）
```

### 启动流程

1. `board_init` 上电时序：引脚复用 → 各外设供电 → DO/蜂鸣器/状态灯默认关闭
2. `lcd_st6201_43in` 初始化 LCD → AirUI 引擎 + 字库 → 注册背光（PWM0）→ 发布 `DISPLAY_READY`
3. `tp_gt911` 收到 `DISPLAY_READY` 后初始化 GT911 并绑定 AirUI
4. `idle_win` 收到 `DISPLAY_READY` 后发布 `BACKLIGHT_ON` 并打开首页
5. 各业务 app 订阅消息自初始化（network/flash/watchdog/uart 等）
6. `sys.run()` 进入事件循环

### 目录结构

```
Air8301_Gateway/
├── main.lua                # 程序入口（只 require）
├── readme.md               # 本文件
├── app/                    # 业务逻辑层（事件驱动，模块解耦）
│   ├── app_main.lua        # 业务模块加载器
│   ├── board_init.lua      # 上电时序 + 板级初始化 + 恢复出厂
│   ├── network_app.lua     # exnetif 多网优先级 + 网络状态广播
│   ├── wifi_app.lua        # WiFi 扫描
│   ├── rs485_app.lua       # 双 RS485 收发
│   ├── rs232_app.lua       # 双 RS232 收发
│   ├── di_app.lua          # DI 输入监测
│   ├── do_app.lua          # DO 继电器控制
│   ├── buzzer_app.lua      # 蜂鸣器
│   ├── led_app.lua         # 状态灯
│   ├── watchdog_app.lua    # 外部看门狗
│   ├── reload_app.lua      # RELOAD 按键（长按5秒恢复出厂）
│   └── flash_app.lua       # SPI Flash 挂载 /flash
├── drv/                    # 硬件驱动层
│   ├── lcd/lcd_st6201_43in.lua   # ST6201 LCD + AirUI 初始化
│   └── tp/tp_gt911.lua            # GT911 触摸初始化
└── ui/                     # UI 层（exwin 窗口，纯事件驱动）
    ├── ui_main.lua         # 窗口模块加载器
    ├── idle_win.lua        # 首页（功能菜单网格）
    ├── network_win.lua     # 网络状态（4G/WiFi/以太网）
    ├── wifi_win.lua        # WiFi 扫描结果
    ├── rs485_win.lua       # RS485 终端（双端口）
    ├── rs232_win.lua       # RS232 终端（双端口）
    ├── di_win.lua          # DI 状态
    ├── do_win.lua          # DO 控制
    ├── buzzer_win.lua      # 蜂鸣器测试
    ├── led_win.lua         # 状态灯控制
    ├── watchdog_win.lua    # 看门狗状态/喂狗/启停
    ├── reload_win.lua      # RELOAD 按键状态
    ├── flash_win.lua       # Flash 存储信息
    └── sysinfo_win.lua     # 系统信息（版本/内存/恢复出厂）
```

---

## 五、全局消息约定

| 消息 | 方向 | 参数 | 说明 |
|------|------|------|------|
| `DISPLAY_READY` | LCD驱动 → 各模块 | - | LCD/AirUI 初始化完成 |
| `BACKLIGHT_ON` | idle_win → LCD驱动 | - | 开启背光 |
| `NETWORK_INIT_DONE` | network_app → flash_app | - | 网卡初始化完成，可挂载 Flash |
| `NETWORK_STATUS_QUERY` | 窗口 → network_app | - | 主动查询网络状态 |
| `STATUS_SIGNAL_UPDATED` | network_app → 窗口 | level | 4G 信号等级 |
| `STATUS_WIFI_UPDATED` | network_app → 窗口 | connected,ssid,level,rssi | WiFi 状态 |
| `STATUS_ETH_UPDATED` | network_app → 窗口 | eth1,ip1,eth2,ip2 | 以太网状态 |
| `WIFI_SCAN_REQ` | wifi_win → wifi_app | - | 请求扫描 |
| `WIFI_SCAN_RESULT` | wifi_app → wifi_win | results | 扫描结果 |
| `RS485_DATA_RECEIVED` / `RS485_SEND_REQUEST` | 收发 | port,data | RS485 数据 |
| `RS232_DATA_RECEIVED` / `RS232_SEND_REQUEST` | 收发 | port,data | RS232 数据 |
| `DI_STATUS_CHANGED` | di_app → di_win | di1,di2 | DI 状态 |
| `DO_SET_REQUEST` | do_win → do_app | ch,state | DO 控制 |
| `LED_SET_REQUEST` | led_win → led_app | type,state | 状态灯控制 |
| `BUZZER_BEEP_REQUEST` | buzzer_win → buzzer_app | - | 蜂鸣器发声 |
| `WATCHDOG_STATUS` / `WATCHDOG_FEED_REQUEST` / `WATCHDOG_ENABLE_REQUEST` | 看门狗 | - | 看门狗管理 |
| `KEY_EVENT` | reload_app → reload_win | "reload_down"/"reload_up" | 按键事件 |
| `FACTORY_RESET_REQUEST` | 页面/reload_app → board_init | - | 恢复出厂设置 |
| `FLASH_MOUNT_STATUS` / `REQUEST_STATUS_REFRESH` | Flash | mounted,total,used,cap | Flash 状态 |

---

## 六、运行步骤

1. 使用 LuatOS 开发环境（LuatIDE / VS Code + LuatOS 插件）打开本工程
2. 编译下载脚本固件至 Air8301 网关（Air8000W 芯片，选对应 SOC 固件）
3. 上电后触摸屏显示首页，12 个功能入口可点击进入
4. 各功能页面按需操作（详见下一节）

---

## 七、演示效果 / 使用说明

- **首页**：12 个功能卡片，点击进入对应页面
- **网络状态**：查看 4G 信号、WiFi 连接、以太网1/2 IP
- **WiFi**：刷新扫描附近热点（仅显示，不提供开关）
- **RS485/RS232**：双端口同屏，输入框发送，接收数据十六进制/ASCII 显示
- **DI 状态**：DI1/DI2 指示灯 + 变更历史
- **DO 控制**：点击卡片切换继电器 ON/OFF
- **蜂鸣器**：点击测试按钮响 0.5 秒
- **状态灯**：4G 灯 / WiFi 灯手动开关
- **看门狗**：显示启用状态/超时时间，手动喂狗、启用、禁用
- **RELOAD**：按键按下/抬起状态（长按 5 秒触发恢复出厂）
- **Flash 存储**：芯片容量 + 文件系统使用情况
- **系统信息**：固件版本、运行时间、内存占用、文件系统，底部恢复出厂按钮

---

## 八、注意事项

1. **RS485 半双工**：RE/DE 方向由 uart.setup 内置 RS485 模式自动控制，Lua 层勿手动操作 GPIO2/GPIO153
2. **SPI1 总线共享**：Flash 与双 CH390 共用 SPI1，Flash 挂载必须等待 `NETWORK_INIT_DONE` 消息（flash_app 已处理）；Flash 速率对齐 25.6MHz，CS 脚空闲拉高
3. **看门狗禁用**：Air153C 无"关闭"寄存器，禁用通过 700ms 关闭脉冲实现；喂狗间隔务必 >1s（测试模式下 1s 内连续 2 个喂狗脉冲会立即复位）
4. **恢复出厂**：系统信息页按钮或 RELOAD 长按 5 秒，会清空 fskv 配置并重启
5. **以太网映射**：网口1 用 ETHERNET→LWIP_ETH，网口2 用 ETHUSER1→LWIP_USER1，两者不能都用 ETHUSER1
6. **GPIO146/GPIO31 上拉**：开启后会上拉 RELOAD 与 DI1/DI2，注意上电时序
7. **SPI Flash 文件系统**：默认 lfs2，首次挂载失败（-84 无文件系统）会自动格式化，勿传 "pgfs"

---


