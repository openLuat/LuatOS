# 引擎主机出厂工程（配置驱动架构）

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
| 9 | Air1601 | turnkey开发板+配件板 | EVB_Air1601_V1.1；AirLCD_1020；AirSHT30；AirVOC_1000；AirCAMERA_1030 | 800*480 5寸RGB触摸屏；4G；Wifi；以太网；蓝牙；tf/sd卡；喇叭；CAN；RS485；200万像素USB摄像头；I2C传感器 | EVB_Air1601_5inch_800x480_000_V011 | | |
| 10 | Air8101 | 引擎主机 | EVB_Air8101_V1.0 | 1024*600 10.1寸RGB触摸屏；4G；Wifi；以太网；tf/sd卡；MIC；喇叭；CAN；200万像素USB摄像头 | EVB_Air8101_10inch1_1024x600_000_V010 | | <img src="https://docs.openLuat.com/cdn/image/EVB_Air8101_10inch1_1024x600_000_V010_back_view.png"> |
| 11 | Air8101B | 引擎主机 | 合宙引擎 8101B V002 | 854*480 5寸RGB触摸屏；Wifi | EVB_Air8101B_5inch_480x854_000_V010 | | <img src="https://docs.openLuat.com/cdn/image/EVB_Air8101B_5inch_480x854_000_V010_back_view.png"> |
| 12 | Air8101 | 引擎主机 | 合宙引擎 8101 V002 | 854*480 5寸RGB触摸屏；Wifi | EVB_Air8101_5inch_480x854_000_V010 | | |

---

## 二、演示效果

本工程为完整的引擎主机出厂固件，包含开机动画、桌面启动器、系统设置、WiFi 管理、应用市场、网络测速等完整功能。

| 首页| 系统设置 | 应用市场 | 网速测速 | 应用列表 | 应用界面 |
|---------|--------|---------|---------|---------|---------|
| <img src="https://docs.openLuat.com/cdn/image/idle_win.png"> | <img src="https://docs.openLuat.com/cdn/image/settings_win.png">| <img src="https://docs.openLuat.com/cdn/image/app_store_win.png">| <img src="https://docs.openLuat.com/cdn/image/speedtest_win.png"> |<img src="https://docs.openLuat.com/cdn/image/app_2.png"> | <img src="https://docs.openLuat.com/cdn/image/app_1.png"> |

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
    ├── app_main（加载业务模块：net_init → wifi_app → ntp → speedtest → settings → fota）
    └── ui_main（LCD 初始化 → TP 初始化 → 欢迎页 → 背光 → sys.run() 事件循环）
```

### 目录结构

```
factory/
├── main.lua                   # 入口（设 PROJECT，串联 6 阶段初始化）
├── core/
│   └── platform_loader.lua    # 平台检测 + 配置映射 + 引脚初始化 + GPIO 上电
├── config/                    # 硬件配置文件（每个 PROJECT 一个）
│   ├── eng_1602_5i_v2.lua     # Air1602 5寸 V002
│   ├── eng_1602_5i_v3.lua     # Air1602 5寸 V003（NAND Flash）
│   ├── eng_1602_7i_v0.lua     # Air1602 7寸
│   ├── eng_1602_7i_v4.lua     # Air1602 7寸 V004（NAND Flash）
│   ├── eng_1602_10i_v0.lua    # Air1602 10.1寸
│   ├── eng_8000w_4i_v0.lua    # Air8000W 4寸
│   ├── evb_8101_10i_v1.lua    # Air8101 10.1寸
│   ├── evb_8101b_5i_v1.lua    # Air8101 5寸
│   ├── evb_8000a_3i5_v0.lua   # Air8000A trunkey 3.5寸
│   ├── pc_default.lua         # PC 模拟器回退
│   └── template.lua           # 配置参数完整说明
├── drv/                       # 配件驱动（参数驱动，不硬编码平台）
│   ├── lcd/                   # 5 款 LCD 驱动（HX8282 已四合一）
│   └── tp/                    # GT911 触摸驱动
├── app/                       # 业务逻辑（事件驱动，模块解耦）
│   ├── app_main.lua           # 业务模块加载器
│   ├── network/net_init.lua   # 统一网络初始化（DNS + 事件日志）
│   ├── wifi/                  # WiFi 管理
│   ├── settings/              # 设置子模块（显示/声音/存储/内存/关于/IOT）
│   ├── ntp/ntp_app.lua        # NTP 校时
│   ├── speedtest/             # 网络测速
│   └── fota_app.lua           # OTA 固件升级
├── ui/                        # UI 层（纯事件驱动）
│   ├── ui_main.lua            # UI 入口 + 硬件初始化序列
│   ├── welcome_win.lua        # 开机欢迎页
│   ├── idle_win.lua           # 桌面启动器
│   ├── settings/              # 设置页面（9 个子页面）
│   ├── wifi/                  # WiFi 页面
│   ├── app_store_win.lua      # 应用市场
│   └── speedtest_win.lua      # 测速页面
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
        lcd = { model = "lcd_nv3052c_5in", params = {...}, ... },
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
| 测速 | `app/speedtest/speedtest_app.lua` | Cloudflare 延迟/抖动/下载/上传 |
| FOTA 升级 | `app/fota_app.lua` | 定时检查云端固件更新 |
| IOT 账号 | `app/settings/settings_iot_app.lua` | 合宙 IoT 平台登录/登出 |

### 6.4 设置与配置

| 模块 | 文件 | 职责 |
|------|------|------|
| 设置框架 | `app/settings/settings_app.lua` | 设置主框架，级联加载子模块 |
| 显示亮度 | `app/settings/settings_display_app.lua` | PWM 背光管理 |
| 触摸音效 | `app/settings/settings_buzz_app.lua` | 触摸反馈音管理 |
| 存储信息 | `app/settings/settings_storage_app.lua` | 多挂载点容量采集 + 快速/全量双通道 |
| 内存信息 | `app/settings/settings_memory_app.lua` | 系统/LuaVM/PSRAM 内存采集 |
| 存储优先级 | `app/settings/storage_pri_app.lua` | 外部应用安装位置优先级管理 |
| 设备信息 | `app/settings/settings_about_app.lua` | 型号/唯一ID/固件版本采集 |

### 6.5 UI 页面

| 窗口 | 文件 | 功能 |
|------|------|------|
| 欢迎页 | `ui/welcome_win.lua` | 开机引导动画 |
| 桌面 | `ui/idle_win.lua` | 时间/日期/信号/快捷入口/外部应用网格 |
| 设置主页 | `ui/settings/settings_win.lua` | 功能入口列表（WiFi/显示/存储/声音/关于/更新） |
| 显示设置 | `ui/settings/settings_display_win.lua` | 亮度滑动条 + 加减按钮 |
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
| 测速 | `ui/speedtest_win.lua` | 延迟/抖动/下载/上传结果 |

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

**桌面操作**：时间/日期/信号显示、设置/应用市场/测速入口、外部应用网格

**设置操作**：显示亮度调节、WiFi 管理、存储空间查看、触摸音效设置、设备信息查看、IOT 账号管理、系统更新

**WiFi 操作**：开关/扫描/连接/断开、已保存网络管理、密码显隐切换

**应用市场**：搜索/分类/安装/卸载/更新/分页浏览

**网络测速**：延迟/抖动/下载速度/上传速度

---

## 十、故障排除

1. **持续重启**：检查 `PROJECT` 是否正确、配置文件是否存在、LCD 驱动 model 名是否匹配
2. **显示异常**：检查 LCD 接线，确认配置文件中 `direction` 旋转参数正确
3. **触摸无响应**：检查 I2C 接线，确认 GT911 `pin_rst`/`pin_int` 引脚配置正确
4. **WiFi 无法扫描**：Air160x 系列检查 airlink `pin_cs`/`pin_rdy` 配置，Air8000W/Air8101 检查 exnetif 配置
5. **4G 无信号**：检查 SIM 卡是否插入、`features.net_4g` 是否设为 true、芯片是否支持 4G
6. **存储页面卡顿**：NAND Flash 的 `io.fsstat` 耗时较长（2-8 秒），页面使用两阶段加载避免 UI 冻结
7. **图片无法显示**：确认图片资源已正确烧录到脚本分区
8. **字体显示异常**：确认字体文件已正确烧录，或使用固件内置字库
9. **设备名称不保存**：确认 fskv 存储空间正常
