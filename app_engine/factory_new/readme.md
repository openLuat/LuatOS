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
| 17 | Air1603 | 引擎主机 | 合宙引擎 AIR8603W1 V000 10寸 | 1024*600 10寸RGB触摸屏；WiFi(Airlink 6205, UART3)；PWM背光调节；喇叭(HT6873)；隔离RS485(UART1)；UVC摄像头(UART2控制串口)；SD卡 | Engine_Air8603W1_10inch_1024x600_000_WiFi_V000 | | |
| 18 | Air1603 | 引擎主机 | 合宙引擎 AIR8603W2 V000 10寸 | 1024*600 10寸RGB触摸屏；WiFi(Airlink 6205, UART3)；PWM背光调节；喇叭(HT6873)；非隔离RS485(UART1)；UVC摄像头(UART2控制串口)；SD卡 | Engine_Air8603W2_10inch_1024x600_000_WiFi_V000 | | |
| 19 | Air1603 | 引擎主机 | 合宙引擎 AIR8603W3 V000 10寸 | 1024*600 10寸RGB触摸屏；WiFi(Airlink 6205, UART3)；PWM背光调节；喇叭(HT6873)；隔离RS485(UART1/UART2) 两路；SD卡 | Engine_Air8603W3_10inch_1024x600_000_WiFi_V000 | | |
| 20 | Air1603 | 引擎主机 | 合宙引擎 AIR8603W4 V000 10寸 | 1024*600 10寸RGB触摸屏；WiFi(Airlink 6205, UART3)；PWM背光调节；喇叭(HT6873)；非隔离RS485(UART1)；隔离RS485(UART2)；SD卡 | Engine_Air8603W4_10inch_1024x600_000_WiFi_V000 | | |
| 21 | Air1603 | 引擎主机 | 合宙引擎 AIR8603W5 V000 10寸 | 1024*600 10寸RGB触摸屏；WiFi(Airlink 6205, UART3)；PWM背光调节；喇叭(HT6873)；TTL串口(UART1)；隔离RS485(UART2)；SD卡 | Engine_Air8603W5_10inch_1024x600_000_WiFi_V000 | | |
| 22 | Air1603 | 引擎主机 | 合宙引擎 AIR8603M1 V000 10寸 | 1024*600 10寸RGB触摸屏；4G(Airlink 780ER2, UART3)；PWM背光调节；喇叭(HT6873)；隔离RS485(UART1)；UVC摄像头(UART2控制串口)；SD卡 | Engine_Air8603M1_10inch_1024x600_000_4G_V000 | | |
| 23 | Air1603 | 引擎主机 | 合宙引擎 AIR8603M2 V000 10寸 | 1024*600 10寸RGB触摸屏；4G(Airlink 780ER2, UART3)；PWM背光调节；喇叭(HT6873)；非隔离RS485(UART1)；UVC摄像头(UART2控制串口)；SD卡 | Engine_Air8603M2_10inch_1024x600_000_4G_V000 | | |
| 24 | Air1603 | 引擎主机 | 合宙引擎 AIR8603M3 V000 10寸 | 1024*600 10寸RGB触摸屏；4G(Airlink 780ER2, UART3)；PWM背光调节；喇叭(HT6873)；隔离RS485(UART1/UART2) 两路；SD卡 | Engine_Air8603M3_10inch_1024x600_000_4G_V000 | | |
| 25 | Air1603 | 引擎主机 | 合宙引擎 AIR8603M4 V000 10寸 | 1024*600 10寸RGB触摸屏；4G(Airlink 780ER2, UART3)；PWM背光调节；喇叭(HT6873)；非隔离RS485(UART1)；隔离RS485(UART2)；SD卡 | Engine_Air8603M4_10inch_1024x600_000_4G_V000 | | |
| 26 | Air1603 | 引擎主机 | 合宙引擎 AIR8603M5 V000 10寸 | 1024*600 10寸RGB触摸屏；4G(Airlink 780ER2, UART3)；PWM背光调节；喇叭(HT6873)；TTL串口(UART1)；隔离RS485(UART2)；SD卡 | Engine_Air8603M5_10inch_1024x600_000_4G_V000 | | |
| 27 | Air1603 | 引擎主机 | Air8603W | 1024*600 10寸RGB触摸屏(HX8282)；WiFi(Airlink 601S, SPI5)；PWM3背光调节；喇叭(内置DAC)；非隔离RS485(UART1)；人脸识别摄像头(AirCAMERA_1034, UART2)；SD卡；USB HID/UVC 二选一 | Engine_Air8607W_10inch_1024x600_000_V000 | | |

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
│   ├── evb_8101b_5i_v1.lua    # Air8101B 5寸
│   ├── evb_8101_9i_v0.lua     # Air8101 9寸 (AirLCD_1090)
│   ├── evb_8101_10i_v0.lua    # Air8101 10寸 (AirLCD_1100)
│   ├── evb_8101_7i_v0.lua     # Air8101 7寸 (AirLCD_1070)
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
        wdt = { pin = 57 },   -- 外部看门狗喂狗脚（开关在 features.wdt）
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
        -- rotation 是画面旋转角，顺时针 0 / 90 / 180 / 270，不写不转；逆时针 90 度写 270
        -- 摄像头是人脸识别模组（AirCAMERA_1034）时把上一条换成下面这条（见 6.6）：
        -- { type = "uvc", id = "uvc1", name = "人脸识别摄像头", title = "摄像头",
        --   en_pin = 73, ready_delay = 200, rotation = 270,
        --   face = { uart_id = 2, rst_pin = nil, register_timeout = 15, verify_timeout = 15 } },
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
| 外部看门狗 | `app/common/watchdog_app.lua` | Air153D 自动喂狗 + `WATCHDOG_*` 状态消息（`features.wdt` 开关 + `hw.wdt` 配脚） |

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
| 功能测试 | `ui/other_func_win.lua` | UVC / RS485 / 串口 / 音频 外设分组开关与状态；485 不管几路只出一行「RS485 测试」；分组标题可用配置条目的 `title` 覆盖 |
| 摄像头测试 | `ui/uvc_preview_win.lua` | 预览 / 拍照(.jpg) / 录像(.mjpg，本固件无 MP4 封装)；摄像头是人脸识别模组时多一个「人脸识别」页签（录入 / 验证 / 清空 / 版本）（点功能测试页的摄像头行进入） |
| 485 测试 | `ui/rs485_test_win.lua` | 多路通道卡 + 统一收发日志 + 交叉线判定（点功能测试页的「RS485 测试」行进入） |
| 录音播放 | `ui/audio_test_win.lua` | 录音时长选择 + 录音/播放/停止 + 测试日志（点功能测试页的音频行进入） |

### 6.6 外设接口

由 `config.peripherals` 声明式配置，同一 `type` 可配多条（UART1 / UART2 / 多路 485），靠 `id` 区分。
开关由 `features.other_func` + `ui.show_other_func` 控制（桌面图标显示，两处都要 true）。
列表里 `type = "rs485"` 的多条配置**合并成一行**「RS485 测试」，几路全在同一个收发测试页
逐路列出；其余 type 一条配置一行，每条独立开关。
`type = "audio"` 是录音播放测试点，硬件参数读 `config.hw.audio`（Air1103 走 UART6），
没配 `hw.audio` 的机型 init 直接失败，列表里也不会出现「音频」组。
有 `hw.audio` 却不配 `type = "audio"` 的机型（8603 除 M1/W1 的八型号 / 8607 / 8607A）是只播放不录音，
「功能测试」里同样没有「音频」组，声音走 TTS / MP4 那几条路（见 6.7）。
`type = "uvc"` 条目带 `face` 子表表示这颗摄像头是人脸识别模组（AirCAMERA_1034）：USB 出 UVC 画面，
UART 走人脸协议（录入 / 验证 / 删除全部 / 版本），两条通路共用 `en_pin` 供电，断电一起掉。
带了才会在摄像头测试页多出「人脸识别」页签，不带的型号页面与原来完全一致。
录入 / 验证前页面会把条目的 `en_pin` 断电重枚举一次（模组出完图停流后停在出图模式，
录入指令不回包，见 `ui/uvc_preview_win.lua` 文件头「人脸识别边界」第 1 条），
所以这颗摄像头的 `en_pin` 必须是可拉低的独立供电脚。
`type = "uvc"` 条目的 `rotation` 是画面旋转角（顺时针 0 / 90 / 180 / 270，逆时针 90 度写 270），
按模组实际安装方向填，不写不转。旋转在缩放前对帧生效，转 90 / 270 时帧的宽高互换，
预览区与取档都跟着按旋转后的宽高比算（见 `ui/uvc_preview_win.lua` 的 `disp_dims`）。
已配该段的型号：eng_8605_10i_v0（非隔离 485 一路）/
eng_8605w_10i_v0 / eng_8605m_10i_v0（隔离 485 一路 + Air1103 录音播放）/
eng_8605b_10i_v0（双隔离 485，UART1/UART6）/ eng_8607a_10i_v0 /
eng_8601_7i_wifi / eng_8601_7i_4g（8601 的 UVC_EN = GPIO73，摄像头是人脸识别模组，见配置文件头第 12、14 条）/
eng_8602_9i_wifi / eng_8602_9i_4g（双路 485，无独立供电脚）/
eng_8603w1_10i_v0 ~ eng_8603w5_10i_v0 / eng_8603m1_10i_v0 ~ eng_8603m5_10i_v0
（Air8603 十型号，UART1 / UART2 按出货型号分档，见配置文件头第 1 条；M1 / W1 另带 Air1103 录音播放）/
eng_8607w_10i_v0（Air8607W 10寸：UART1 = 非隔离 485、UART2 = 人脸识别摄像头控制串口、
UART13 通用串口；USB HID 与 UVC 二选一，见 6.8）。

| 模块 | 文件 | 职责 |
|------|------|------|
| 外设框架 | `drv/periph/periph_loader.lua` | 按 config.peripherals 逐条初始化，未实现 type 记日志跳过 |
| UVC 摄像头 | `drv/periph/periph_uvc.lua` | 纯供电开关（数据流由摄像头测试页独占） |
| 人脸识别 | `script/libs/exfacecam.lua`（共享扩展库） | AirCAMERA_1034 人脸协议（UART 115200/8N1）：录入 / 验证 / 用户管理 |
| RS485 | `drv/periph/periph_rs485.lua` | 多路 DE 方向控制 + 供电脚引用计数 |
| 通用串口 | `drv/periph/periph_uart.lua` | 任意 UART 接口（波特率/数据位/校验/停止位） |
| 录音播放 | `drv/periph/periph_audio.lua` | 录音/回放（Air1103 录 PCM_16000 走流式回放） |
| 功能测试 | `app/other_func/other_func_app.lua` | 外设实例开关与状态（订阅 OTHER_FUNC_*） |

### 6.7 音频通路（`hw.audio`）

全固件**只有一处**组装 `exaudio.setup` 的入参：`app/common/audio_hw.lua`。
六个消费方 `app/common/tts_app.lua`、`app/factory/llm_chat.lua`、`app/factory/factory_rec.lua`、
`app/settings/settings_display_app.lua`、`ui/video_util.lua`、`drv/periph/periph_audio.lua`
一律调它，字段不再各自维护一份拷贝。这样收口的原因是 `uart_id` / `audio_mode` 只要漏传一处，
全局音频就废掉，而且现象离原因很远：`exaudio` 内部 `uart_id` 缺省取 1，
而 Air1103 实际挂在 UART6；`app/common/audio_hw.lua` 又把 `exaudio.setup`
收口成只执行首次、`air1103.init` 也不换串口，所以**第一次 setup 的入参决定终身**。

`hw.audio.play_model` 决定**播放**走哪条通路，只对 `model = "air1103"` 的板子有意义：
录音固定走 Air1103，播放默认走芯片内置 DAC（不写就是 `"dac"`），显式写 `"air1103"` 退回单通路。
两条通路对 `exaudio.model` 的要求互斥，`audio_route` 在录音前 / 播放前各重跑一次
`exaudio.setup` 切过去；其它 `model`（es8311 / dac / 无音频）下 `enabled()` 恒为假，
调用形态与没有该模块时完全一致，其它型号一个字节都不用动。

音量与静音开关经全局消息 **`AUDIO_CFG_SYNC(level, mute)`**（`level` 0-100，`mute` = true 静音）
同步，任何一处改动都收敛到 `audio_route.apply` 这一个生效点：它同时下发 `exaudio.vol`
与 `audio_v2.soft_volume`。两者缺一不可——Air1103 机型上 `exaudio.vol` 只写语音芯片的音量寄存器，
够不着内置 DAC 的数字增益，MP4 音轨的音量只能靠 `soft_volume` 控；反之一样。
其它模块也可 `sys.publish(AUDIO_CFG_SYNC, vol, mute)` 驱动同一套生效逻辑。

| 模块 | 文件 | 职责 |
|------|------|------|
| 参数组装 | `app/common/audio_hw.lua` | `hw.audio` → `exaudio.setup` 入参（必带 `uart_id`/`audio_mode`）+ 音量套用 |
| 录音/播放分路 | `app/common/audio_route.lua` | Air1103 机型录音走语音芯片、播放走内置 DAC，按需重跑 `exaudio.setup`；`AUDIO_CFG_SYNC` 的生效点 |
| MP4 伴音 | `app/common/pcm_play.lua` | 同名 `.pcm` 伴音流式播（16kHz/16bit/单声道），跟着主播放通路走 |
| TTS 播报 | `app/common/tts_app.lua` | 云端/本地文本播报（`type = 1`） |
| 录音回放 | `drv/periph/periph_audio.lua` | 录音 + 流式回放（Air1103 录 PCM_16000） |

**内置 DAC + 直驱 PA**（8603 除 M1/W1 的八型号 / 8607 / 8607A / eng_8607w_10i_v0，无麦克风）：
声音由芯片内置 DAC 播放，PA 功放使能脚直驱控制，`hw.audio` 写 `model = "dac"` + `pa_ctrl` + `pa_on_level`。
8603 / 8607 的功放是 HT6873、高电平使能：`pa_ctrl = 73`（AUDIOPA_EN）、`pa_on_level = 1`，
`power_on` 里先拉低关断，起播时拉高，`pa_delay` 是起播后延时开 PA 的毫秒数。
MP4 的声音由 mplayer → C 层音频框架直接出，不需要 `.pcm` 伴音。

**Air1103 语音芯片**（8605W / 8605M / 8603M1 / 8603W1，UART6，固定 2M 波特率）单芯片集成
MIC + 喇叭 + AEC，`exaudio` 走 `model = "air1103"` + `audio_mode = "new"`，只认两种起播方式：
`type = 1`（TTS 文本）与 `type = 2`（流式 PCM），`type = 0`（文件）直接返回 `unsupported`。
这几个型号「既接了 Air1103 也支持内置 DAC」，因此走分路：录音出 Air1103、播放出内置 DAC
（`model = "air1103"` + `play_model = "dac"`），`type = 0` 在 DAC 通路上是合法的。
只有显式写 `play_model = "air1103"` 退回单通路时，MJPG 的同名 `.mp3` 伴音才不成立，
日志会明确提示并跳过。

**MP4 伴音（兜底）**：MP4 的声音走 mplayer → C 层音频框架 → 芯片内置 DAC，与 `play_model = "dac"`
的播放通路同一路。个别素材实测不出声时，给它配一份**同目录同名**的 `.pcm` 伴音兜底
（16kHz/16bit/单声道小端）：画面由 mplayer 照常放，声音由 `pcm_play` 流式播，
起播同刻启动即自然同步；暂停记断点续播，循环重播从头，都跟着播放器走。素材预转：

```bash
ffmpeg -i fruit.mp4 -ac 1 -ar 16000 -f s16le fruit.pcm
```

没配同名 `.pcm` 不报错；分路板只在日志里记「MP4 音轨走内置 DAC」，
仍留在 Air1103 单通路的机型才提示缺伴音。伴音只在文件存在时启用，
若某支素材的 mplayer 音轨本来就有声，两者会叠成双声，删掉同名 `.pcm` 即可。

### 6.8 USB HID 与 UVC 二选一

USB 键鼠与 UVC 摄像头共用同一个 USB Host 与同一条供电轨，同一时刻只能有一方占用，
所以两者做成**互斥开关**：模式写 fskv（键 `usb_mode_config`，值 `"uvc"` / `"hid"`），
出厂默认 `"uvc"`（摄像头）。切换入口在「设置 → 外设模式」，交互与网络设置页同款
（逐条开关 + 互斥预演 + 「确定并重启」弹窗），写完 fskv 重启生效。

| 模块 | 文件 | 职责 |
|------|------|------|
| 模式存取 | `app/usb_hid/usb_mode.lua` | fskv 读写 + 互斥预演 + 开机按模式上电/断电 UVC + 过滤 uvc 条目 |
| 切换页面 | `ui/settings/settings_usb_win.lua` | 「外设模式」设置页（两行开关 + 互斥确认 + 重启生效弹窗） |
| USB 键鼠 | `app/usb_hid/usb_hid_app.lua` | USB Host + Input 事件；VBUS 脚由 `hw.usb.vbus_gpio` 决定 |

`hw.usb.vbus_gpio` 是 usb_hid_app 驱动的 USB 供电脚，缺省 `12`（8605 系列的 VBUS 与 5V_EN 同脚）。
本板若把 GPIO12 拿去做别的信号（如 eng_8607w_10i_v0 的 Airlink RDY），必须写 `vbus_gpio = false`
关掉这条驱动，否则会与该信号抢脚。

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
    另外注意 8603W3/W4/W5 与 8603M3/M4/M5 的 `485_EN2 = GPIO58` 是 UART2 那路 485 的 DE，
    而带 UVC 的 W1/W2/M1/M2 同一脚是 `UVC_EN`：混刷配置会把方向脚当供电脚用，务必按出货型号取配置。
    8603 十型号 UART1 那路 485（隔离与非隔离共用）的 DE 都是 `485_EN1 = PIN51 = GPIO65`，
    不是收发器自动方向；`485_EN = GPIO64` 是 485 功能总供电，两者别混。
13. **万用表量 DE（方向脚）一直 0V、以为方向脚没驱动**：这是对的，别按它判断。485 是半双工，
    空闲时方向脚必须停在接收态（**低电平**），只有每一帧的发送窗口里才拉高；9600 波特率发
    3 字节，那个窗口只有 6~8 毫秒，万用表积分下来永远读 0V。软件这边已经把时序算好了：
    日志 `发送完成 <id> 等Xms 预算Yms sent已到` 里 `等` 不小于 `预算` 就说明 DE 盖满了整帧。
    要确认方向脚真的会翻，进 485 测试页点右上角「**DE 自检**」，驱动把全部已登记的 DE 脚拉高
    2 秒再回接收态，这段时间量得到高电平（日志 `DE 自检拉高` / `DE 自检回接收态`）。
    自检结束日志直接给结论：`DE 自检通过：GPIO65/GPIO46 拉高 2000 ms 回读高电平，已回接收态`
    是软件侧驱动到位；`DE 自检不通过：… 回读不是高电平，查 de_pin 配置` 是该脚没写进去。
    自检显示通过、量到的却还是 0V，才是方向脚真没驱动到收发器，查硬件与接线。

14. **设备用一段时间自己重启 / 断电**：先看是不是外置看门狗复位。8603 与 8605 系列板上都挂了
    Air153D，喂狗脚都是 `PIN47 = GPIO57`。配置里开 `features.wdt = true` + `hw.wdt = { pin = 57 }`，
    `app/common/watchdog_app.lua` 就会自动喂狗（默认 180 秒一次）；不想喂狗就去掉 `features.wdt`，
    这个模块根本不加载。启动日志里有 `watchdog_app init done, pin: 57` 说明喂狗已接管；
    出现 `exair153x_wdt not packed in firmware` 或 `config.hw.wdt.pin missing` 就是没在喂，
    会在 STRAP 设定的超时档（10分钟 / 60分钟 / 12小时 / 24小时）到点后被芯片拉 PWR_OFF 复位。
    芯片侧 WTDOG 是喂狗输入、PWR_OFF 是复位输出，固件不碰 PWR_OFF；1 秒内连发 3 次喂狗脉冲
    是芯片的强制复位序列，手动喂狗有 2 秒冷却，别在脚本里密集发 `WATCHDOG_FEED_REQUEST`。


15. **「录音播放」报「录音失败：没有采到数据」/「未收到MIC数据」**：先看 `hw.audio` 的 `uart_id` 写没写对。
    Air1103 挂在 UART6（8605W / 8605M / 8603M1 / 8603W1），`exaudio` 内部缺省取 1，漏写或写错就会把语音芯片绑到
    UART1（那是隔离 485），MIC 的上行帧一个都收不到。现在 `uart_id` / `audio_mode` 由
    `app/common/audio_hw.lua` 统一组装，六个消费方不会再漏传；还报没数据就查硬件侧：
    `AUDIOPA_EN = GPIO73` 有没有拉高（8605W / 8605M 上它是 Air1103 的**供电脚**，`power_on` 拉高常供电、
    `hw.audio` 故意不写 `pa_ctrl`；8603（含 M1/W1）/ 8607 上同名脚是本地功放使能，`hw.audio` 照常写
    `pa_ctrl`，两种含义别混，见 6.7）、
    UART6 的 TX/RX 有没有接反、语音芯片固件版本对不对。日志 `periph_audio 未收到MIC数据
    audio1 model: air1103 uart: 6` 里 `uart:` 是本次申请的串口号，跟实际不符说明配置没生效。
    另外 Air1103 每次录音都会复位芯片，约 1.4 秒后才恢复 MIC 上行，这段时间落盘是静音，
    驱动已按 2 秒补时长抵消，录出来的就是你要的时长。

16. **播放 MP4 没有声音**：这几款（8605W / 8605M / 8603M1 / 8603W1）是 Air1103 录音 + 内置 DAC 播放，
    MP4 的音轨走 mplayer → C 层音频框架 → 内置 DAC，与 TTS / 录音回放共用一路。
    先看「设置 → 亮度和声音」的音量：DAC 那一路的音量靠 `audio_v2.soft_volume` 控，
    `AUDIO_CFG_SYNC` 会把它和 `exaudio.vol` 一起下发，任何一处没跟上都会表现为没声或音量不变。
    素材本身没声就给 MP4 配一份同目录同名的 `.pcm` 伴音兜底（见 6.7「MP4 伴音」）。
    录音与播放是两套通路，「功能测试 → 录音播放」录得到但 MP4 没声，问题在 DAC 侧而不是语音芯片侧。
    8603 其余八型号 / 8607 是内置 DAC + 直驱 PA，MP4 声音直接出。

17. **人脸识别摄像头测不出 / 录入一直「未检测到人脸」**：先分清是串口链路还是识别问题。
    点「版本」读得到模组固件版本，说明 UART2 链路与协议是通的；读不到先查接线
    （Air1601 UART2 TX/RX → 模组 RX/TX，115200/8N1，波特率在 `exfacecam` 库里写死）
    与摄像头条目里 `face` 子表的 `uart_id`。识别阶段页面按模组回调给引导文案
    （请正对摄像头 / 请抬头 / 请靠近一些…），一直卡在「未检测到人脸」多半是补光或角度问题。
    录入 / 验证期间本页会**停掉 UVC 推流**（不停会让识别超时），画面停在最后一帧属正常，
    动作结束自动恢复。停流之后模组还停在出图模式，这时发录入指令它不回包（串口日志是
    `exfacecam cmd timeout 0x1D`），所以录入 / 验证前会**把摄像头断电重枚举一次**
    （`en_pin` 拉低 400ms 再拉高），让它回到人脸采集模式，人脸串口随之重开，
    这一段约 2 秒属正常等待。取版本 / 删除全部是纯串口指令，不做重枚举。
    供电与出图共用 `UVC_EN`，断电人脸模组一起掉，功能测试页把摄像头断电会连带杀掉人脸模组。
