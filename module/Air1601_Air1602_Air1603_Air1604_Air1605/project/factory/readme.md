# 引擎主机出厂工程 · TabOS 界面版（配置驱动架构）

> 本工程由 `app_engine/factory` 复制而来，UI 层按 `tablet-smart-home` 设计稿重做为 **深色玻璃态（TabOS）** 风格；
> 初始化方式参考桌面版 factory：**RGB 屏走 `display` 库初始化 + 全局 `lcd` 代理**。
>
> - 设计令牌与组件工厂：`ui/ui_theme.lua`
> - 图标资源清单（尺寸/命名）：`docs/ui_icons.md`
> - 视觉基调：底色 `#080B10` + 半透明白玻璃卡片 + 琥珀 `#FFB454` 强调色 + 大圆角
> - 已重做页面：欢迎页、桌面首页、设置主页、亮度和声音、触摸音效、标题栏组件
> - 其余页面（WiFi / 应用市场 / 文件管理 / 应用工厂 / AI 助手）已切换深色调色板与玻璃标题栏

## 初始化方式（参考桌面版 factory）

| 环节 | 实现 | 文件 |
|------|------|------|
| 编译清单 | 只打包当前机型配置 + 用到的驱动，缩小 LuaDB（800×480 脚本区仅 1024KB） | `core/platform_loader.lua` |
| 分辨率获取 | `screen_get_size()` 优先 `display.getSize()` → params 兜底 | `drv/lcd/lcd_common.lua` |
| 全局 `lcd` 代理 | 覆盖为 Lua 代理表，`getSize()` 优先返回 display 尺寸/`_G.screen_w`，其余字段透传原 lcd | `drv/lcd/lcd_common.lua` |
| RGB 屏驱动 | `lcd_display_rgb` 走 `display.init("custom", cfg)`，PC 模拟器跳过；`display` 路径不再额外 `setupBuff` | `drv/lcd/lcd_display_rgb.lua` |
| 背光 GPIO | `gpio.setup(pin, 1)` 输入上拉（与 PWM 模式二选一） | `drv/lcd/lcd_common.lua` |
| 窗口/应用库 | `exwin` / `exapp` 内置到 `libs/`，不再依赖固件内置版本 | `libs/exwin.lua` `libs/exapp.lua` |
| PC 模拟器 | `pcconf/pcconf.json`（存储/网络/模拟器开关） + `fskv.bin` | `pcconf/` `fskv.bin` |
| 业务容错 | `net_manager.init` 用 pcall 包裹，网络起不来不阻断 UI | `app/app_main.lua` |
| 内存裁剪 | `factory_win` / `llm_chat_win` 暂不打包（常驻窗口约占 1024KB） | `ui/ui_main.lua` |

> ⚠️ 当前 `PROJECT = "EVB_Air1601_5inch_800x480_000_V011"`（5 寸 800×480 RGB，display 底层），
> 编译清单已按该机型裁剪。若需恢复多机型支持，需把其余 config/驱动 require 加回 `core/platform_loader.lua`。

## 一、已支持的硬件型号

| 序号 | 主控 | 类型 | 硬件 | 支持功能 | 命名 | 正面视图 | 背面视图 |
|------|------|------|------|---------|------|---------|---------|
| 1 | Air1602 | 引擎主机 | Air1601 UI 畅玩板 V000 | 1024*600 7寸RGB触摸屏；Wifi；PWM背光调节 | Engine_Air1602_7inch_1024x600_000_V000 | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_7inch_1024x600_000_V000_front_view.png"> | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_7inch_1024x600_000_V000_back_view.png"> |
| 2 | Air1602 | 引擎主机 | Air1601 UI 畅玩板 V001 | 1024*600 10.1寸RGB触摸屏；Wifi；蜂鸣器；PWM背光调节 | Engine_Air1602_10inch1_1024x600_001_V000 | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_10inch1_1024x600_001_V000_front_view.png"> | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_10inch1_1024x600_001_V000_back_view.png"> |
| 3 | Air1602 | 引擎主机 | Air1601 UI 畅玩板 V002 | 720*1280 5寸RGB触摸屏；Wifi；PWM背光调节 | Engine_Air1602_5inch_720x1280_002_V000 | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_5inch_720x1280_002_V000_front_view.png"> | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_5inch_720x1280_002_V000_back_view.png"> |
| 4 | Air1602 | 引擎主机 | 合宙引擎AIR1602 V003 | 720*1280 5寸RGB触摸屏；Wifi；PWM背光调节；128MB NAND_FLASH；喇叭；MIC；按键; 电池管理 | Engine_Air1602_5inch_720x1280_003_V000 | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_5inch_720x1280_003_V000_front_view.png"> | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_5inch_720x1280_003_V000_back_view.png"> |
| 5 | Air1602 | 引擎主机 | 合宙引擎AIR1602 V004 | 1024*600 7寸RGB触摸屏；Wifi；PWM背光调节；128MB NAND Flash | Engine_Air1602_7inch_1024x600_004_V000 | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_7inch_1024x600_004_V000_front_view.png"> | <img src="https://docs.openLuat.com/cdn/image/Engine_Air1602_7inch_1024x600_004_V000_back_view.png"> |
| 6 | Air8000W | 引擎主机 | 合宙引擎主机8000W_V000 | 320*480 4寸SPI触摸屏；4G；Wifi；蜂鸣器；PWM背光调节 | Engine_Air8000W_4inch_320x480_000_V000 | <img src="https://docs.openLuat.com/cdn/image/Engine_Air8000W_4inch_320x480_000_V000_front_view.png"> | <img src="https://docs.openLuat.com/cdn/image/Engine_Air8000W_4inch_320x480_000_V000_back_view.png"> |
| 7 | Air8000 | turnkey开发板套装 | Air8000A trunkey 开发板 V020 | 480*320 3.5寸SPI触摸屏；4G；Wifi；蜂鸣器；SD卡 | EVB_Air8000A_3inch5_480x320_000_V020 | | |
| 7 | Air1601 | turnkey开发板套装 | EVB_Air1601_V1.1；AirLCD 10.1寸屏；AirSHT30；AirVOC_1000；AirCAMERA_1030 | 1024*600 10.1寸RGB触摸屏；4G；Wifi；以太网；蓝牙；tf/sd卡；喇叭；CAN；RS485；200万像素USB摄像头；I2C传感器 | EVB_Air1601_10inch1_1024x600_000_V011 | | |
| 8 | Air1601 | turnkey开发板套装 | EVB_Air1601_V1.1；AirLCD 7寸屏；AirSHT30；AirVOC_1000；AirCAMERA_1030 | 1024*600 7寸RGB触摸屏；4G；Wifi；以太网；蓝牙；tf/sd卡；喇叭；CAN；RS485；200万像素USB摄像头；I2C传感器 | EVB_Air1601_7inch_1024x600_000_V011 | | |
| 9 | Air1601 | turnkey开发板套装 | EVB_Air1601 V012；AirLCD 7寸屏 | 1024*600 7寸RGB触摸屏；4G(AirLink UART2)；WiFi(AirLink SPI2)；以太网；SD卡；PWM3背光调节；应用工厂(ES8311录音播放) | EVB_Air1601_7inch_1024x600_000_V012 | | |
| 10 | Air1601 | turnkey开发板+配件板 | EVB_Air1601_V1.1；AirLCD_1020；AirSHT30；AirVOC_1000；AirCAMERA_1030 | 800*480 5寸RGB触摸屏；4G；Wifi；以太网；蓝牙；tf/sd卡；喇叭；CAN；RS485；200万像素USB摄像头；I2C传感器 | EVB_Air1601_5inch_800x480_000_V011 | | |
| 10 | Air8101 | 引擎主机 | EVB_Air8101_V1.0；AirLCD_1090 | 1024*600 9寸RGB触摸屏；Wifi；以太网 | EVB_Air8101_AirLCD_1090_000_V020 | | |
| 11 | Air8101 | 引擎主机 | EVB_Air8101_V1.0；AirLCD_1070 | 1024*600 7寸RGB触摸屏；Wifi；以太网 | EVB_Air8101_AirLCD_1070_000_V020 | | |
| 12 | Air8101 | 引擎主机 | EVB_Air8101_V1.0；AirLCD_1100 | 1024*600 10寸RGB触摸屏；Wifi；以太网；应用工厂(内置DAC喇叭/麦克风) | EVB_Air8101_AirLCD_1100_000_V020 | | <img src="https://docs.openLuat.com/cdn/image/EVB_Air8101_10inch1_1024x600_000_V010_back_view.png"> |
| 13 | Air8101B | 引擎主机 | 合宙引擎 8101B V002 | 480*854 5寸RGB触摸屏；Wifi | EVB_Air8101B_5inch_480x854_000_V010 | | <img src="https://docs.openLuat.com/cdn/image/EVB_Air8101B_5inch_480x854_000_V010_back_view.png"> |
| 14 | Air1780H | 引擎主机 | 合宙引擎 AIR1780H V000 4.3寸 | 480*272 4.3寸SPI触摸屏(ST6201)；WiFi(airlink 6205)；ES8311录音播放；SD卡；NAND Flash；PWM0背光调节 | Engine_Air1780H_4inch_480x272_000_V000 | | |
| 15 | Air1603 | 引擎主机 | 合宙引擎 AIR8607 V000 10寸 | 1024*600 10寸RGB触摸屏；PWM背光调节；喇叭；SD卡 | Engine_Air8607_10inch_1024x600_000_V000 | | |
| 16 | Air1603 | 引擎主机 | 合宙引擎 AIR8607A V000 10寸 | 1024*600 10寸RGB触摸屏；PWM背光调节；喇叭；UVC摄像头(AirCAMERA_1032/AirUVC_1000)；无SD卡 | Engine_Air8607A_10inch_1024x600_000_V000 | | |
| 17 | Air1603 | 引擎主机 | 合宙引擎 AIR8603W1 V000 10寸 | 1024*600 10寸RGB触摸屏；WiFi(Airlink 6205, UART3)；Air1103语音(UART6)；PWM背光调节；UVC摄像头；三路RS485(非隔离×1/隔离×2)；UART2；SD卡 | Engine_Air8603W1_10inch_1024x600_000_WiFi_V000 | | |
| 18 | Air1603 | 引擎主机 | 合宙引擎 AIR8603M1 V000 10寸 | 1024*600 10寸RGB触摸屏；4G(Airlink 780ER2, UART3)；Air1103语音(UART6)；PWM背光调节；UVC摄像头；三路RS485(非隔离×1/隔离×2)；UART2；SD卡 | Engine_Air8603M1_10inch_1024x600_000_4G_V000 | | |

---

## 二、演示效果

本工程为完整的引擎主机出厂固件，包含开机动画、桌面启动器、系统设置、WiFi 管理、应用市场等完整功能。

| 首页| 系统设置 | 应用市场 | 应用列表 | 应用界面 |
|---------|--------|---------|---------|---------|
| <img src="https://docs.openLuat.com/cdn/image/idle_win.png"> | <img src="https://docs.openLuat.com/cdn/image/settings_win.png">| <img src="https://docs.openLuat.com/cdn/image/app_store_win.png">|<img src="https://docs.openLuat.com/cdn/image/app_2.png"> | <img src="https://docs.openLuat.com/cdn/image/app_1.png"> |

---

## 三、架构概览

### 配置驱动设计

**换硬件只需改 `main.lua` 中的一行 `PROJECT` 字符串**。所有硬件差异（LCD 型号、TP 引脚、GPIO 上电时序、功能开关）通过 `config/` 目录下的配置文件声明，框架自动适配。

```
main.lua（设 PROJECT）
    │
    ▼
platform_loader（平台检测 → PROJECT 映射 → 加载配置 → _G.project_config）
    │
    ├── lcd_common（动态 require LCD/TP 驱动 → 构建 _G.lcd_drv / _G.tp_drv）
    └── boot_ui（快速点亮：display → airui.init → logo+背光 → logo 展示期间加载
        字体与核心批 → 直接进桌面；可选批 app_main/ui_main.optional 独立协程并行）
```

### 目录结构

```
factory/
├── main.lua                   # 入口（设 PROJECT，串联 5 阶段初始化）
├── core/
│   └── platform_loader.lua    # 平台检测 + 配置映射 + 引脚初始化 + GPIO 上电
├── config/                    # 硬件配置文件（每个 PROJECT 一个）
│   ├── eng_1602_5i_v2.lua     # Air1602 5寸 V002
│   ├── eng_1602_5i_v3.lua     # Air1602 5寸 V003（NAND Flash）
│   ├── eng_1602_7i_v0.lua     # Air1602 7寸
│   ├── eng_1602_7i_v4.lua     # Air1602 7寸 V004（NAND Flash）
│   ├── eng_1602_10i_v0.lua    # Air1602 10.1寸
│   ├── pc_default.lua         # PC 模拟器回退
│   └── template.lua           # 配置参数完整说明
├── drv/                       # 配件驱动（参数驱动，不硬编码平台）
│   ├── lcd/                   # 3 个文件：lcd_display_rgb(统一驱动) / lcd_st7701s_5in(IC 序列) / lcd_common
│   └── tp/                    # GT911 触摸驱动
├── app/                       # 业务逻辑（事件驱动，模块解耦）
│   ├── app_main.lua           # 业务模块加载器
│   ├── network/net_init.lua   # 统一网络初始化（DNS + 事件日志）
│   ├── wifi/                  # WiFi 管理
│   ├── settings/              # 设置子模块（显示/声音/存储/内存/关于/IOT）
│   ├── ntp/ntp_app.lua        # NTP 校时
│   └── fota_app.lua           # OTA 固件升级
├── ui/                        # UI 层（纯事件驱动）
│   ├── boot_ui.lua            # 开机快速点亮 + 延迟初始化编排
│   ├── ui_main.lua            # UI 窗口清单（boot_ui 在 logo 展示期间延迟加载）
│   ├── idle_win.lua           # 桌面启动器
│   ├── settings/              # 设置页面（9 个子页面）
│   ├── wifi/                  # WiFi 页面
│   ├── app_store_win.lua      # 应用市场
└── res/                       # 图片资源 + RSA 公钥
```

---

## 四、配置文件格式

每个配置文件声明以下内容，示例（`eng_1602_5i_v3.lua`）：

```lua
return {
    name = "Engine_Air1602_5inch_720x1280_003_V000",
    chip = "Air1602",
    baseboard = "合宙引擎AIR1602 V003",

    -- 引脚复用配置（PWM、I2C、SPI 等功能指定）
    pins = {},

    -- GPIO 上电时序（Airlink WiFi 模组: GPIO55 拉低 50ms → 拉高 120ms）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50 },
        { pin = 55, dir = 0, level = 1, delay = 120 },
    },

    -- 硬件参数（LCD/TP 型号、引脚、分辨率、字体、背光）
    hw = {
        lcd = { model = "lcd_display_rgb", params = {...}, ... },
        tp  = { model = "tp_gt911",        params = {...} },
    },

    -- 功能开关（true=启用, false=禁用）
    features = {
        wifi = true, buzzer = false, nand_flash = true, ...
    },

    -- UI 显示控制
    ui = {
        show_wifi_icon = true, show_storage_settings = true, ...
    },

    -- 外设接口（UVC / RS485 / UART，同一 type 可配多条，靠 id 区分）
    -- 开关入口在桌面「功能测试」，需 features.other_func + ui.show_other_func 同时为 true
    peripherals = {
        { type = "uvc",   id = "uvc1",  name = "UVC摄像头", en_pin = 58, ready_delay = 200 },
        { type = "rs485", id = "485_1", name = "非隔离485", uart_id = 1, de_pin = 65,
          power_pin = 14, baud = 9600 },
        { type = "rs485", id = "485_2", name = "隔离485",   uart_id = 1, de_pin = nil,
          power_pin = 14, baud = 9600 },
        { type = "uart",  id = "uart2", name = "UART2",     uart_id = 2, baud = 115200,
          databits = 8, parity = "N", stopbits = 1 },
    },

    -- 存储设备配置（sd_card、nand_flash、little_flash）
    storage = {
        sd_card = { spi_id = 0, pin_cs = 32, speed = 20000000},
    },
}
```

---

## 五、如何适配新硬件

### 5.1 新增已有芯片的新型号

1. 在 `config/` 创建配置文件（如 `eng_1602_5i_v4.lua`）
2. 在 `core/platform_loader.lua` 的 `PROJECT_MAP` 中添加映射
3. 在编译清单中添加 `require("eng_1602_5i_v4")`
4. 在 `main.lua` 中修改 `PROJECT` 为新命名

### 5.2 新增配件驱动

1. 在 `drv/lcd/` 或 `drv/tp/` 创建驱动文件，遵循 `init(params)` 接口
2. 在配置文件 `hw.lcd.model` 中引用新驱动名
3. 在 `platform_loader.lua` 编译清单中添加 `require` 声明

### 5.3 PROJECT 命名规范

```
{类型}_{芯片}_{尺寸}_{版本}
  类型: Engine引擎主机 / EVB开发板 / Core核心板
  芯片: Air1602 / Air8000W / Air8101 / Air780EGG ...
  尺寸: 5inch_720x1280 / 10inch1_1024x600 ...
  版本: 002_V000 / 003_V000 ...
```

---

## 六、功能模块

### 6.1 核心框架

| 模块 | 文件 | 职责 |
|------|------|------|
| 入口 | `main.lua` | 设 PROJECT，串联 6 阶段启动流程 |
| 平台加载器 | `core/platform_loader.lua` | 平台检测 → 配置映射 → 引脚初始化 → GPIO 上电 |
| 驱动构建 | `drv/lcd/lcd_common.lua` | 动态加载 LCD/TP 驱动，构建全局接口 |
| 业务加载器 | `app/app_main.lua` | 按序 require 所有业务模块 |
| UI 入口 | `ui/ui_main.lua` | 加载 UI 页面，创建硬件初始化协程 |

### 6.2 网络与通信

| 模块 | 文件 | 职责 |
|------|------|------|
| 网络初始化 | `app/network/net_init.lua` | DNS 配置 + IP/WLAN 事件日志 + 多网融合状态 |
| WiFi 管理 | `app/wifi/wifi_app_real.lua` | 扫描/连接/断开/自动连接（Air8000W/Air8101/Air160x） |
| WiFi 公共 | `app/wifi/wifi_app_common.lua` | 状态构建、网络刷新、扫描校验、断连原因 |
| WiFi 存储 | `app/wifi/wifi_storage.lua` | 凭证持久化（基于 fskv） |

### 6.3 业务服务

| 模块 | 文件 | 职责 |
|------|------|------|
| 状态提供器 | `app/common/status_provider_app.lua` | 时间/信号/电量定时更新 |
| NTP 校时 | `app/ntp/ntp_app.lua` | 联网后自动向 ntp.aliyun.com 校时 |
| FOTA 升级 | `app/fota_app.lua` | 定时检查云端固件更新 |
| IOT 账号 | `app/settings/settings_iot_app.lua` | 合宙 IoT 平台登录/登出 |

### 6.4 设置与配置

| 模块 | 文件 | 职责 |
|------|------|------|
| 设置框架 | `app/settings/settings_app.lua` | 设置主框架，级联加载子模块 |
| 亮度和声音 | `app/settings/settings_display_app.lua` | PWM 背光 + 媒体音量管理 |
| 设置当前时间 | `app/settings/settings_time_app.lua` | 手动校准系统时钟（rtc.set 写入） |
| 触摸音效 | `app/settings/settings_buzz_app.lua` | 触摸反馈音管理 |
| 存储信息 | `app/settings/settings_storage_app.lua` | 多挂载点容量采集 + 快速/全量双通道 |
| 内存信息 | `app/settings/settings_memory_app.lua` | 系统/LuaVM/PSRAM 内存采集 |
| 存储优先级 | `app/settings/storage_pri_app.lua` | 外部应用安装位置优先级管理 |
| 设备信息 | `app/settings/settings_about_app.lua` | 型号/唯一ID/固件版本采集 |

### 6.5 UI 页面

| 窗口 | 文件 | 功能 |
|------|------|------|
| 桌面 | `ui/idle_win.lua` | 时间/日期/信号/快捷入口/外部应用网格 |
| 设置主页 | `ui/settings/settings_win.lua` | 功能入口列表（WiFi/亮度和声音/设置当前时间/存储/声音/关于/更新） |
| 亮度和声音 | `ui/settings/settings_display_win.lua` | 亮度滑块 + 媒体音量滑块（有音频硬件时默认启用） |
| 设置当前时间 | `ui/settings/settings_time_win.lua` | 年月日时分秒加减调节 + 直接输入，保存写入系统时钟 |
| 存储页 | `ui/settings/settings_storage_win.lua` | 文件系统容量 + 内存占用（6 卡片，两阶段加载） |
| 存储优先级 | `ui/settings/storage_pri_win.lua` | 拖拽排序应用安装位置 |
| 声音设置 | `ui/settings/settings_sound_win.lua` | 蜂鸣器开关/音量/时长 |
| 关于设备 | `ui/settings/settings_about_win.lua` | 设备名称/型号/ID/版本 |
| IOT 账号 | `ui/settings/settings_iot_win.lua` | 登录/登出/账号信息 |
| 系统更新 | `ui/settings/settings_fota_win.lua` | 固件版本检查与更新 |
| WiFi 列表 | `ui/wifi/wifi_list_win.lua` | 开关/扫描/网络列表 |
| WiFi 详情 | `ui/wifi/wifi_detail_win.lua` | SSID/IP/MAC/信号/断开 |
| WiFi 连接 | `ui/wifi/wifi_connect_win.lua` | 密码输入/高级配置 |
| 应用市场 | `ui/app_store_win.lua` | 搜索/分类/安装/卸载/分页 |
| 功能测试 | `ui/other_func_win.lua` | UVC / RS485 / 串口 外设分组开关与状态；485 不管几路只出一行「RS485 测试」 |
| UVC 预览 | `ui/uvc_preview_win.lua` | 预览 / 拍照(.jpg) / 录像(.mjpg，本固件无 MP4 封装)（点功能测试页的 UVC 行进入） |
| 485 测试 | `ui/rs485_test_win.lua` | 多路通道卡 + 统一收发日志 + 交叉线判定（点功能测试页的「RS485 测试」行进入） |

### 6.6 外设接口

由 `config.peripherals` 声明式配置，同一 `type` 可配多条（UART1 / UART2 / 多路 485），靠 `id` 区分。
开关由 `features.other_func` + `ui.show_other_func` 控制（桌面图标显示，两处都要 true）。
列表里 `type = "rs485"` 的多条配置**合并成一行**「RS485 测试」，几路全在同一个收发测试页
逐路列出；其余 type 一条配置一行，每条独立开关。
已配该段的型号：eng_8605_10i_wifi / eng_8605_10i_4g / eng_8605b_10i_v0 / eng_8607a_10i_v0 /
eng_8601_7i_wifi / eng_8601_7i_4g（8601 的 UVC_EN = GPIO73，见配置文件头第 12 条）/
eng_8602_9i_wifi / eng_8602_9i_4g（双路 485，无独立供电脚）/
eng_8603w_10i_v0 / eng_8603m_10i_v0（三路 485 + UART2，其中 485_3 与 uart2 共用物理 UART2
不可同时开、UVC_EN 与 485_3 的 DE 共用 GPIO58，见配置文件头第 7、8 条）。

| 模块 | 文件 | 职责 |
|------|------|------|
| 外设框架 | `drv/periph/periph_loader.lua` | 按 config.peripherals 逐条初始化，未实现 type 记日志跳过 |
| UVC 摄像头 | `drv/periph/periph_uvc.lua` | 纯供电开关（数据流由 UVC 预览页独占） |
| RS485 | `drv/periph/periph_rs485.lua` | 多路 DE 方向控制 + 供电脚引用计数 |
| 通用串口 | `drv/periph/periph_uart.lua` | 任意 UART 接口（波特率/数据位/校验/停止位） |
| 功能测试 | `app/other_func/other_func_app.lua` | 外设实例开关与状态（订阅 OTHER_FUNC_*） |

---

## 七、演示硬件环境

- type-c 数据线 x 1
- 合宙引擎主机 x 1，可通过[合宙引擎主机购买链接](https://luat.taobao.com/category-1841239809.htm) 进行购买

---

## 八、演示软件环境

### 7.1 开发工具

- [Luatools 下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/) - 固件烧录和代码调试

### 7.2 内核固件

- Air8000W：[点击下载 Air8000W 最新版本内核固件](https://docs.openluat.com/air8000/luatos/firmware/)
- Air8101：[点击下载 Air8101 最新版本内核固件](https://docs.openluat.com/air8101/luatos/firmware/)
- Air1601/Air1602：[点击下载 Air1601 最新版本内核固件](https://docs.openluat.com/air1601/luatos/firmware/)

---

## 九、使用步骤

### 8.1 选择硬件型号

在 `main.lua` 中修改 `PROJECT` 为对应型号的命名：

```lua
PROJECT = "Engine_Air1602_5inch_720x1280_003_V000"
```

`main.lua` 文件头部已列出所有可用的 PROJECT 值及对应硬件说明。

### 8.2 软件烧录

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载并烧录本工程所有脚本文件
3. 将 `res/` 目录下的图片资源随脚本一起烧录
4. 设备自动重启后开始运行
5. [点击查看 Luatools 下载和详细使用](https://docs.openluat.com/air8000/common/Luatools/)

### 8.3 功能测试

**开机流程**：上电 → 固件启动 → 平台检测 → 配置加载 → GPIO 上电 → 驱动初始化 → 业务模块加载 → 欢迎页 → 桌面

**桌面操作**：时间/日期/信号显示、设置/应用市场入口、外部应用网格

**设置操作**：亮度和声音调节、WiFi 管理、存储空间查看、触摸音效设置、设备信息查看、IOT 账号管理、系统更新

**WiFi 操作**：开关/扫描/连接/断开、已保存网络管理、密码显隐切换

**应用市场**：搜索/分类/安装/卸载/更新/分页浏览

---

## 十、故障排除

1. **持续重启**：检查 `PROJECT` 是否正确、配置文件是否存在、LCD 驱动 model 名是否匹配
2. **桌面没有「功能测试」图标**：看开机日志有无「未找到 PROJECT 映射」——`PROJECT` 写错会静默
   回退 PC 配置（屏幕靠型号名还能点亮，但外设与功能测试全没了）。旧命名与大小写变体已在
   `core/platform_loader.lua` 的 PROJECT_MAP 留了别名；另请确认 `features.other_func` 与
   `ui.show_other_func` 两处都为 true。
3. **显示异常**：检查 LCD 接线，确认配置文件中 `direction` 旋转参数正确
4. **触摸无响应**：检查 I2C 接线，确认 GT911 `pin_rst`/`pin_int` 引脚配置正确
5. **WiFi 无法扫描**：Air160x 系列检查 airlink `pin_cs`/`pin_rdy` 配置，Air8000W/Air8101 检查 exnetif 配置
6. **4G 无信号**：检查 SIM 卡是否插入、`features.net_4g` 是否设为 true、芯片是否支持 4G
7. **存储页面卡顿**：NAND Flash 的 `io.fsstat` 耗时较长（2-8 秒），页面使用两阶段加载避免 UI 冻结
8. **图片无法显示**：确认图片资源已正确烧录到设备
9. **UVC 拍照 / 录像失败**（日志出现 `D/camera not support yet` / `无法启动摄像头`）：`excamera.photo` / `excamera.video` 走的是 `camera.start` + `camera.capture` 的 DVP/SPI 采集通路，USB 摄像头上不适用；本工程 UVC 预览页直接取 MJPEG 推流帧落盘（.jpg / .mjpg）。
10. **RS485 测试不通 / 485 供电脚（如 8603 的 485_EN = GPIO64）实测低电平**：先看开机日志的
    `POWER_ON n GPIOxx 高 回读 1`，回读为 0 或打出 `POWER_ON 引脚设置失败` 就是该脚没配成输出。
    `power_on` 的电平直接写进 `gpio.setup` 第 2 参（0/1 都是输出、数字即初始电平，`dir`
    只在 `level` 缺省时兜底，不要拿它表达「输入/输出」）。进 485 测试页后，驱动每次
    start 都重申高电平（日志 `485 供电上电`）；常供电域在配置里写
    `power_hold = true`，驱动只补高不关断（日志 `485 供电保持`，末路 stop 不拉低）。
    仍不通则查 `power_pin` / `de_pin` 与硬件引脚表是否一致。
11. **两路 485 交叉互接（A 接 A、B 接 B）测不出「通过」**：交叉线判定只认**分属不同串口**的两路。
    同一 `uart_id` 上的多路共用一根 TX/RX，谁发谁都互相看得见（那是串口镜像，没过外部接线），
    接线断了也会互相「收到」，所以同串口的一律不计通过；全部路都同串口时测试页不判定，
    进页面会写明「板上无法自测交叉线」。要互测就得分属不同 UART——两个收发器共用一根
    TX/RX 时对发本身就是电气冲突。本机型可自测的通道对见进页时的日志行。
12. **点了发送但屏上一直「对端未收到」**：先看设备日志里的收发标记，分清是没发出去、
    DE 没切成发送态、发了但 DE 提前松、还是发出去了对端没回——
    `发送 <id> UART<n> <len> 字节 DE=<脚号:电平,…>`、
    `发送完成 <id> 等Xms 预算Yms sent已到|sent未到 wait485=<N> DE=<脚号:电平,…>`、
    `发送失败 <id> <原因>`、`收到 UART<n> <len> 字节 广播<N>路`、
    `UART<n> 发送期间丢弃回环`、`收包回调空读`。
    一条 `发送` 都没有说明发送没走到驱动；`DE=` 那段带回读电平，发前是 `脚:1`、发完是 `脚:0`，
    电平不对说明方向脚没写进去；`收包回调空读` 说明串口中断到了但读不出字节，
    连这条都没有就是链路上根本没进数据。
    DE 必须盖住整帧：即使 `sent` 提前到，也要等满按波特率估算的帧时长才松 DE，
    提前松会把帧尾截掉，对端收不全就当没收到；`wait485` 不为 0 说明估算的等待还不够长。
    本路 `de_pin` 没配却在同一串口上配了别的 DE 脚时，发送翻的是兄弟路的 DE，本路的收发器
    仍停在接收态发不出去，日志会打 `本路缺 de_pin，发送时翻的是同串口其它路的 DE`，
    这种路必须补上真实 DE 脚。
    另外注意 8603W / 8603M1 的 `485_EN2 = GPIO58` 与 `UVC_EN` 同脚：UVC 那一路开着时
    GPIO58 被拉高，485_3 的收发器就停在发送态收不到数据；测 485_3 前先把 UVC 关掉。
13. **万用表量 DE（方向脚）一直 0V、以为方向脚没驱动**：这是对的，别按它判断。485 是半双工，
    空闲时方向脚必须停在接收态（**低电平**），只有每一帧的发送窗口里才拉高；9600 波特率发
    3 字节，那个窗口只有 6~8 毫秒，万用表积分下来永远读 0V。软件这边已经把时序算好了：
    日志 `发送完成 <id> 等Xms 预算Yms sent已到` 里 `等` 不小于 `预算` 就说明 DE 盖满了整帧。
    要确认方向脚真的会翻，进 485 测试页点右上角「**DE 自检**」，驱动把全部已登记的 DE 脚拉高
    2 秒再回接收态，这段时间量得到高电平（日志 `DE 自检拉高` / `DE 自检回接收态`）。
    自检量到的还是 0V，才是方向脚真没驱动，回头查 `de_pin` 配置。

