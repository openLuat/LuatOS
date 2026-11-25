# Air8607C1_Air8607W1 引擎主机出厂工程 · TabOS 界面版（配置驱动架构）

> 本工程由 `app_engine_tablet_home` 桌面工程裁剪而来，UI 层按 TabOS 设计稿实现为 **深色玻璃态** 风格；
> 初始化方式参考桌面版 factory：**RGB 屏走 `display` 库初始化 + 全局 `lcd` 代理**。
>
> - 当前 `PROJECT = "Air8607C1_Air8607W1_10inch_1024x600"`
> - 当前 `VERSION = "001.999.007"`
> - 主配置：`config/air8607c1_config.lua`
> - 厂测状态机：`app/air8607c1_factory.lua`
> - 厂测页面：`ui/air8607c1_test_win.lua`、`ui/air8607w1_test_win.lua`
> - 设计令牌与组件工厂：`ui/ui_theme.lua`
> - 视觉基调：底色 `#080B10` + 半透明白玻璃卡片 + 琥珀 `#FFB454` 强调色 + 大圆角
>
> 本目录只保存脚本源码与资源；未附带内核 SOC、PDF、验证记录或 `wifi.local.json`。历史设计依据为 `AIR8607C1_V0_20261112_1500.pdf` 第 1～4 页和 `AIR8607W1_V0_20261114.pdf` 第 2～7 页，使用前请按实物工装核对。

## 初始化方式（参考桌面版 factory）

| 环节 | 实现 | 文件 |
|------|------|------|
| 编译清单 | 动态 require 的文件登记在永不调用的 `_compile_manifest()`，供编译系统文本扫描；运行时不提前加载 | `core/platform_loader.lua` |
| PROJECT 映射 | `Air8607C1_Air8607W1_10inch_1024x600` → `air8607c1_config`；未命中回退 PC 配置 | `core/platform_loader.lua` |
| PC 模拟器回退 | 未命中 PROJECT 时加载 `pc_default.lua`，仅用于 PC 模拟 | `config/pc_default.lua` |
| 分辨率获取 | `screen_get_size()` 优先 `display.getSize()`，再用 `hw.lcd.params` 兜底 | `drv/lcd/lcd_common.lua` |
| 全局 `lcd` 代理 | 覆盖为 Lua 代理表，`getSize()` 优先返回 display 尺寸 / `_G.screen_w`，其余字段透传原 lcd | `drv/lcd/lcd_common.lua` |
| RGB 屏驱动 | `lcd_display_rgb` 走 `display.init("custom", cfg)` 分配 FrameBuffer；PC 模拟器跳过 | `drv/lcd/lcd_display_rgb.lua` |
| 背光 | PWM3 上电即压灭，Logo 首帧后再按恢复亮度点亮；厂测页可切 20% / 40% | `core/platform_loader.lua`、`ui/boot_ui.lua`、`drv/air8607c1_board.lua` |
| 触摸 | GT911 走 I2C1，`pin_rst = 14`、`pin_int = 51`；等 `POWER_ON_DONE` 后初始化，失败 200 ms 重试 | `ui/boot_ui.lua`、`drv/tp/tp_gt911.lua` |
| 板级输出 | BUZ1 / AUDIOPA_EN = GPIO73，Air6205 电源 = GPIO72，J8 VBUS / PWM1 = GPIO65 | `drv/air8607c1_board.lua` |
| 窗口 / 应用库 | `exwin` / `exapp` / `sys` 随工程放在 `shared/`，显示完成后加载 | `shared/`、`ui/boot_ui.lua` |
| 网络 | `config.network` 声明 Air6205 SPI5；`net_manager.init` 用 pcall 包裹，网络异常不阻断桌面 | `config/air8607c1_config.lua`、`app/app_main.lua` |
| 厂测 | 「C1 本机」与「扩展底板」两页签，测试结果仅本次开机有效 | `ui/air8607c1_test_win.lua`、`app/air8607c1_factory.lua` |
| FOTA / AirCloud | 当前工程尚无 `PROJECT_KEY`，`features.fota`、`features.aircloud` 及相关 UI 开关均为 false | `main.lua`、`config/air8607c1_config.lua` |

> ⚠️ 当前工程只登记 `Air8607C1_Air8607W1_10inch_1024x600` 一个 PROJECT，映射到 `air8607c1_config.lua`；`main.lua` 与 `core/platform_loader.lua` 必须同时更新。

## 一、已支持的硬件型号

| 序号 | 主控 | 类型 | 硬件 | 支持功能 | 命名 | 正面视图 | 背面视图 |
|------|------|------|------|---------|------|---------|---------|
| 1 | Air1101 | 引擎主机 | 合宙引擎 Air8607C1 V0 + Air8607W1 扩展底板 10 寸 | 1024*600 10寸RGB触摸屏；WiFi(Airlink 6205, SPI5)；PWM3背光调节；本机蜂鸣器；J102 DAC喇叭；隔离RS485(UART1)；TTL串口(UART2)；UVC摄像头(AirCAMERA_1034)；SD/TF卡；CR2032 VRTC | Air8607C1_Air8607W1_10inch_1024x600 | | |

本工程只维护 Air8607C1 V0 + Air8607W1 扩展底板 + 10 寸 1024×600 这一套硬件，底板固定为 Air8607W1。

Air8607W1 的扩展测试项：Wi-Fi、SD/TF、TTL、隔离 RS485、UVC、DAC、CR2032 VRTC。J3-1 为 VIN_24V，正常测试时留空。

「功能测试」页只有「C1 本机」和「扩展底板」两个页签，分别覆盖：

| 页签 | 测试项 |
|------|--------|
| C1 本机 | 蜂鸣器、SPI Flash、屏幕、PWM、背光、触摸 |
| 扩展底板 | Wi-Fi、SD/TF、TTL、隔离 RS485、UVC、DAC、CR2032 VRTC |

---

## 二、演示效果

本工程为桌面主机固件 + 硬件验收页，开机后显示 Logo、进入桌面，再点桌面「功能测试」进入两页签验收界面。测试结果在本次开机期间显示于页面，并同步输出到调试日志；不写入 FSKV，重启后清空。

| 首页 | 系统设置 | 应用市场 | 应用列表 | 应用界面 |
|------|----------|----------|----------|----------|
| <img src="https://docs.openLuat.com/cdn/image/idle_win.png"> | <img src="https://docs.openLuat.com/cdn/image/settings_win.png"> | <img src="https://docs.openLuat.com/cdn/image/app_store_win.png"> | <img src="https://docs.openLuat.com/cdn/image/app_2.png"> | <img src="https://docs.openLuat.com/cdn/image/app_1.png"> |

以上为同系列 TabOS 通用页面截图，功能测试页以实机为准。

---

## 三、架构概览

### 配置驱动设计

本工程固定使用 `Air8607C1_Air8607W1_10inch_1024x600`；LCD、TP、GPIO 时序、功能开关和 UI 入口由 `config/air8607c1_config.lua` 声明，框架按配置初始化。

```text
main.lua（PROJECT / VERSION / PROJECT_KEY）
    │
    ▼
platform_loader（平台检测 → PROJECT_MAP → 加载配置 → 引脚初始化 → GPIO 上电）
    │
    ├── lcd_common（动态 require LCD/TP 驱动 → 构建 _G.lcd_drv / _G.tp_drv）
    │       └── display.init("custom", cfg) → FrameBuffer
    │
    └── boot_ui（fskv → display → airui.init → logo + 背光 → 等 POWER_ON_DONE → TP）
            ├── app_main.core() / ui_main.core() → 桌面
            └── optional_task → app_main.optional() / ui_main.optional()
                    └── features 门控：网络、AI、网盘、应用工厂、C1 功能测试等
```

厂测消息链：

```text
桌面「功能测试」
  → OPEN_OTHER_FUNC_WIN
  → ui/air8607c1_test_win.lua
  → air8607c1_factory / air8607w1_factory
  → C1_TEST_RESULT(id, result)
  → 页面状态标签 + 调试日志
```

### 目录结构

```text
factory/
├── main.lua                       # 入口：PROJECT / VERSION / 4 阶段启动
├── config/
│   ├── air8607c1_config.lua       # C1 主板、扩展底板、网络、外设与测试参数
│   ├── air8607c1_baseboard.lua    # 底板能力判断
│   └── pc_default.lua             # PC 模拟器回退配置
├── core/
│   ├── platform_loader.lua        # 平台检测、PROJECT_MAP、配置加载、上电时序
│   ├── airlink_pin.lua            # WiFi 侧 GPIO 延后下发
│   └── tick_time.lua              # tick / 毫秒换算
├── drv/
│   ├── air8607c1_board.lua        # C1 PWM / 背光 / 输出初始化
│   ├── lcd/                       # LCD 公共层、RGB 驱动、ST7701S IC 序列
│   ├── tp/                        # GT911 触摸
│   └── periph/                    # UVC / RS485 / UART / 音频 / 共享脚仲裁
├── app/
│   ├── app_main.lua               # 业务核心批与可选批
│   ├── air8607c1_factory.lua      # C1 厂测状态机、蜂鸣器 / PWM / Flash 调度
│   ├── air8607w1_factory.lua      # SD、DAC、串口、WiFi、UVC、RTC 测试实现
│   ├── common/                    # 状态栏、天气、音频、TTS、看门狗等
│   ├── factory/                   # 应用工厂、录音、AI 助手
│   ├── network/ wifi/ ntp/        # 网络与 WiFi
│   ├── settings/                  # 设置业务
│   ├── cloud/ file_manager/ file_transfer/ usb_hid/ other_func/ battery/ nes/
├── ui/
│   ├── boot_ui.lua                # 快速点亮 + 分批加载编排
│   ├── ui_main.lua                # 核心窗口批与可选窗口批
│   ├── ui_theme.lua / ui_theme_themes.lua
│   ├── idle_win.lua               # 桌面
│   ├── air8607c1_test_win.lua     # C1 本机 + 扩展底板两页签
│   ├── air8607w1_test_win.lua     # WiFi / 串口 / UVC / 下载口 / RTC 面板
│   ├── settings/ wifi/ net/       # 设置、Wi-Fi、网络页面
│   └── app_store_win / factory_win / llm_chat_win / cloud_disk_win / file_manager_win / file_transfer_win / video_win 等
├── shared/                        # sys / exwin / exapp / exaudio / exnetif / hzadb / libfota3 等
├── res/                           # logo.png、图标、fruit.hzv、public.pem
└── readme.md
```

## 四、配置文件格式

`config/air8607c1_config.lua` 使用与 Air8603 系列一致的配置驱动 schema：

```lua
return {
    name = "Air8607C1",
    chip = "Air1603",
    baseboard = "Air8607C1",
    pins = {},

    power_on = {
        { pin = 73, dir = 0, level = 0 },
        { pin = 72, dir = 0, level = 1, delay = 50 },
        { pin = 65, dir = 0, level = 0 },
    },

    -- 本工程固定 Air8607W1
    default_expansion_model = "Air8607W1",
    expansion_models = {
        { name = "Air8607W1", wifi = true, uart2 = "ttl", audio = "buzzer", dac = true },
    },

    network = {
        { type = "wifi_airlink_spi", spi_id = 5, cs_pin = 56, rdy_pin = 12,
          speed = 4000000 },
    },

    features = {
        wifi = true,
        sd_card = true,
        other_func = true,
        ai_chat = true,
        cloud_disk = true,
        file_transfer = true,
        iot = true,
        fota = false,
        aircloud = false,
        buzzer = false,
        usb_hid = false,
        battery = false,
        app_factory = true,
    },

    ui = {
        show_wifi_icon = true,
        show_brightness_slider = true,
        show_storage_settings = true,
        show_other_func = true,
        show_ai_chat = true,
        show_cloud_disk = true,
        show_file_transfer = true,
        show_iot = true,
        show_fota = false,
        show_aircloud = false,
        show_autostart = true,
        show_app_factory = true,
        show_video_area = false,
    },

    storage = {
        sd_card = { spi_id = 1, pin_cs = 8, pin_power = 22, speed = 10000000 },
    },

    peripherals = {
        { type = "uvc", id = "uvc1", name = "UVC摄像头", title = "摄像头",
          w = 480, h = 320, rotation = 0 },
    },

    hw = {
        lcd = {
            model = "lcd_display_rgb", screen_size = 10,
            params = { interface = "rgb", pin_rst = 15, w = 1024, h = 600,
                hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12,
                pclk_hz = 50000000 },
            font = { size = 20 },
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 70 },
        },
        tp = {
            model = "tp_gt911",
            params = { port = 1, pin_rst = 14, pin_int = 51, w = 1024, h = 600,
                int_type = tp and tp.FALLING, i2c_speed = i2c and i2c.SLOW },
        },
        audio = {
            model = "dac",
            pa_ctrl = 73,
            pa_on_level = 1,
            dac_delay = 6,
            pa_delay = 10,
            play_vol = 9,
        },
    },

    buzzer = { pin = 73, hz = 2700, duration_ms = 100 },
    pwm_test = { channel = 1, pin = 65, connector = "J100-25",
        hz = 1000, duty = 50, duration_ms = 2000 },
    flash_test = { mount_point = "/", size = 8192 },

    -- Air8607W1 的扩展接线与测试参数
    w1 = {
        wifi = { spi = 5, cs = 56, rdy = 12, power = 72, hz = 4000000,
            url = "https://httpbin.luatos.com/bytes/2048" },
        sd = { spi = 1, cs = 8, clk = 9, miso = 10, mosi = 11,
            power = 22, hz = 10000000, mount_point = "/sd", size = 8192 },
        serial = { power = 23, baud = 9600,
            ttl = { id = 2 }, rs485 = { id = 1, de = 74 } },
        uvc = { model = "AirCAMERA_1034", bus = 0, w = 480, h = 320 },
        dac = { pa = 73, volume = 50, text = "音频播放测试" },
        wifi_dl = { connector = "J21", pin1 = "VBAT_5V", pin2 = "GND",
            pin3 = "W_DBG_RX", pin4 = "W_DBG_TX", pin5 = "WIFI_RESET" },
        vrtc = { key = "air8607c1_vrtc_base", off_seconds = 15 },
    },
}
```

必填字段：
- `name`、`chip`、`baseboard`：平台标识；`chip` 当前为 Air1603。
- `pins`：需要显式复用的 GPIO；C1 的 PWM3 背光与 I2C1 触摸无需复用，保持空表。
- `power_on`：GPIO 上电时序；背光 PWM 由平台层先压灭，Logo 首帧后再点亮。
- `hw.lcd` / `hw.tp`：RGB 屏和 GT911 参数，驱动按 `model` 动态 require。
- `network`：Air6205 走 SPI5，`cs = 56`、`rdy = 12`。
- `features` / `ui`：功能与 UI 入口双重门控，成对修改。
- `w1`：Air8607W1 的 Wi-Fi、SD、串口、UVC、DAC、下载口和 VRTC 测试参数。

---

## 五、如何适配新硬件

> 本工程当前只维护 `Air8607C1_Air8607W1_10inch_1024x600`；以下步骤仅说明在本工程内扩展配置和驱动的方法。

### 5.1 修改现有配置

1. 在 `config/air8607c1_config.lua` 修改 `hw.lcd`、`hw.tp`、`pins`、`power_on`、`features` 和 `ui`。
2. 同步 `main.lua` 的 `PROJECT`、`VERSION`。
3. 在 `core/platform_loader.lua` 的 `PROJECT_MAP` 中登记 `PROJECT` 到配置文件的映射。
4. 在 `_compile_manifest()` 中添加 `require ("配置文件名")`，否则动态 require 扫不到，脚本不会打包。
5. 下载时同时更新 `main.lua` 和 `core/platform_loader.lua`，避免映射未命中回退 PC 配置。

### 5.2 新增配件驱动

1. 在 `drv/lcd/`、`drv/tp/` 或 `drv/periph/` 创建驱动，遵循 `init(params)` 接口。
2. 在配置中通过 `hw.lcd.model`、`hw.tp.model` 或 `peripherals` 引用新驱动。
3. 在 `_compile_manifest()` 添加驱动文件的 `require`。
4. 如需交互测试，在 `app/air8607w1_factory.lua` 实现动作，在 `ui/air8607w1_test_win.lua` 的 `panels` 中挂页面，并加入 `ui/air8607c1_test_win.lua` 的 `expansion_items`。

### 5.3 PROJECT 命名规范

```text
{类型}_{主控}_{扩展底板}_{尺寸}_{版本}
  Air8607C1: C1 主控
  Air8607W1: W1 扩展底板
  10inch_1024x600: 10 寸 1024×600 屏
本工程实际值：Air8607C1_Air8607W1_10inch_1024x600
```

`VERSION` 为 `001.999.007`。本工程只维护 Air8607C1 + Air8607W1 + 10 寸 1024×600 这一套硬件配置。

---

## 六、功能模块

### 6.1 核心框架

| 模块 | 作用 | 文件 |
|------|------|------|
| 启动编排 | 平台检测 → 配置加载 → LCD/TP → 显示 → 网络/应用分批加载 | `main.lua`、`core/platform_loader.lua`、`ui/boot_ui.lua` |
| 平台适配 | `PROJECT_MAP`、引脚初始化、GPIO 上电、背光压灭与恢复 | `core/platform_loader.lua` |
| 显示公共层 | 分辨率获取、全局 `lcd` 代理、动态 LCD/TP 驱动加载 | `drv/lcd/lcd_common.lua` |
| RGB 驱动 | `display.init("custom", cfg)` 分配 FrameBuffer，PC 模拟器跳过 | `drv/lcd/lcd_display_rgb.lua` |
| 触摸驱动 | GT911 I2C1 初始化、复位、中断注册 | `drv/tp/tp_gt911.lua` |
| 窗口 / 应用库 | `exwin` / `exapp` / `sys` / `exaudio` 等 | `shared/` |
| 主题令牌 | 颜色、圆角、字号、卡片和按钮工厂 | `ui/ui_theme.lua`、`ui/ui_theme_themes.lua` |

### 6.2 网络与时间

| 能力 | 说明 | 文件 |
|------|------|------|
| Air6205 Wi-Fi | SPI5，`cs = 56`、`rdy = 12`，普通 SPI Airlink 从机固件 | `app/network/`、`shared/exnetif/` |
| WiFi 页面 | 扫描、连接、手动输入密码、状态同步 | `ui/wifi/` |
| 网络测试 | `w1.wifi.url` 下载 2048 字节，验证链路 | `app/air8607w1_factory.lua` |
| NTP | 网络就绪后校时，断网不阻断桌面 | `app/ntp/` |
| FOTA / AirCloud | 当前无 `PROJECT_KEY`，相关功能关闭 | `main.lua`、`config/air8607c1_config.lua` |

### 6.3 业务服务

| 模块 | 作用 | 文件 |
|------|------|------|
| 桌面 | 首页、Dock、状态栏、快捷入口 | `ui/idle_win.lua` |
| 状态栏 | 时间、Wi-Fi、亮度、存储等状态 | `app/common/status_bar.lua` |
| 天气 | 网络天气与本地缓存 | `app/common/weather.lua` |
| 音频 / TTS | 媒体播放、提示音、TTS | `app/common/audio*.lua`、`app/common/tts.lua` |
| 应用工厂 | 应用打包、安装、卸载 | `app/factory/`、`ui/factory_win.lua` |
| AI 助手 | LLM 对话入口 | `ui/llm_chat_win.lua`、`app/factory/ai_chat*.lua` |
| 云盘 / 文件管理 | 云盘、文件浏览、文件传输 | `app/cloud/`、`app/file_manager/`、`ui/cloud_disk_win.lua`、`ui/file_manager_win.lua` |
| 看门狗 | 可选业务看门狗 | `app/common/watchdog.lua` |

### 6.4 设置中心

| 设置项 | 说明 | 文件 |
|--------|------|------|
| 显示 / 亮度 | 背光 PWM3，默认 70%，可调 | `ui/settings/`、`drv/air8607c1_board.lua` |
| Wi-Fi / 网络 | 扫描、连接、网络状态 | `ui/wifi/`、`ui/net/` |
| 存储 | SD/TF 容量与挂载状态 | `ui/settings/` |
| 外设模式 | UVC 摄像头等外设能力展示 | `ui/settings/`、`config/air8607c1_config.lua` |
| 开机自启 / 应用工厂 | 桌面与 Dock 入口 | `ui/settings/`、`ui/idle_win.lua` |
| FOTA / AirCloud | 当前关闭，缺少云端机型密钥 | `ui/settings/`、`main.lua` |

### 6.5 UI 页面

| 模块 | 说明 | 文件 |
|------|------|------|
| 启动页 | Logo、首帧、背光恢复、触摸初始化 | `ui/boot_ui.lua` |
| 桌面 | TabOS 首页、Dock、状态栏 | `ui/idle_win.lua`、`ui/ui_theme.lua` |
| 应用市场 | 应用列表与安装入口 | `ui/app_store_win.lua` |
| 应用工厂 | 应用打包与安装 | `ui/factory_win.lua` |
| 文件管理 / 传输 | 本地文件、U 盘、传输进度 | `ui/file_manager_win.lua`、`ui/file_transfer_win.lua` |
| 云盘 | 云端文件浏览与下载 | `ui/cloud_disk_win.lua` |
| AI 对话 | LLM 对话界面 | `ui/llm_chat_win.lua` |
| 视频区 | 默认关闭，`show_video_area = false` | `ui/ui_main.lua`、`ui/video_win.lua` |
| 功能测试 | C1 本机 + 扩展底板两页签 | `ui/air8607c1_test_win.lua`、`ui/air8607w1_test_win.lua` |

### 6.6 工厂测试

功能测试页由 `ui/air8607c1_test_win.lua` 管理，C1 本机测试走 `app/air8607c1_factory.lua`，扩展底板测试走 `app/air8607w1_factory.lua`。测试结果只保存在本次开机的 Lua 内存表，不写 FSKV。

#### C1 本机测试项

| 测试项 | 操作与判定 |
|--------|------------|
| 蜂鸣器 | 点「播放短音」。GPIO73 经 Q202 驱动 BUZ1 发出约 100 ms、2.7 kHz 声音，听到后点「通过」。 |
| SPI Flash | 读取根文件系统挂载点，核对容量约 8 MB；通过后点「通过」。 |
| 屏幕 | 看 Logo、桌面和测试页是否完整显示，无花屏、偏色、闪屏后点「通过」。 |
| PWM | J100-25 / GPIO65 输出 1 kHz、50% 方波，用示波器或工装确认后点「通过」。 |
| 背光 | 点「20%」「40%」切换 PWM3 占空比，确认亮度变化后点「通过」。 |
| 触摸 | 按提示点四角或画线，确认 GT911 坐标与显示一致后点「通过」。 |

#### 扩展底板测试项

| 测试项 | 操作与判定 |
|--------|------------|
| Wi-Fi | Air6205 走 SPI5，J21 可下载并核对天线。点「开始测试」，通过 `w1.wifi.url` 下载 2048 字节后点「通过」。 |
| SD/TF | 插入 FAT32 TF 卡，挂载 `/sd`，读取容量与目录后点「通过」。 |
| TTL 串口 | 使用 3.3 V USB–TTL。J3-2 为板端 TX、J3-3 为 RX、J3-4 为 GND，TX/RX 交叉连接；J3-1 VIN_24V 留空。9600、8N1，收发一致后点「通过」。 |
| 隔离 RS485 | J1-6 接 A，J1-5 接 B，J1-4 接隔离侧参考地。UART1 由 GPIO74 自动控制方向，高发低收；GPIO23 给隔离 RS485 支路供 3.3 V。9600、8N1 收发一致后点「通过」。 |
| UVC 摄像头 | AirCAMERA_1034 接 J8 USB。摄像头 UART 插头的 VBAT（4 脚）和 GND（1 脚）从 J8 同一组受控 5 V / GND 分接，UART 信号线可留空。点「开始预览」，看到实时 MJPEG 图像后点「通过」。优先 480×320。 |
| DAC 音频播放 | 使用 J102（HT6873）喇叭通路。测试前断开 C1 的 BUZ1 / R422 支路，将喇叭接 J102-1 SPK+ 和 J102-2 SPK−，点「播放测试语音」，听到「音频播放测试」后点「通过」。 |
| CR2032 VRTC | 装好 CR2032，点「开始计时」，断电 15 秒后恢复，RTC 时间保持则点「通过」。 |

#### Air8607W1 接线速查

| 接口 | 引脚 |
|------|------|
| J3 | 1=VIN_24V（正常测试留空）、2=板端 TX、3=板端 RX、4=GND；UART2 为 TTL |
| J1 | 4=隔离侧参考地、5=B、6=A；UART1 为隔离 RS485，DE=GPIO74 |
| J21 | 1=VBAT_5V、2=GND、3=W_DBG_RX、4=W_DBG_TX、5=WIFI_RESET；PIN1 是 5 V，不是 24 V |
| J8 | USB UVC 摄像头；VBAT/GND 从同一组受控 5 V / GND 分接 |
| J102 | 1=SPK+、2=SPK−；使用前断开 C1 的 BUZ1 / R422 支路 |

Wi-Fi 测试前确认 Air6205 已烧录普通 SPI Airlink 从机固件，J21 天线连接可靠；需要重新冷启动 Airlink 时重启设备。手动填写的密码只用于当次连接，工厂账号从随包烧录的 `wifi.local.json` 读取。

TTL 和隔离 RS485 均使用 SSCOM 的 **9600、8N1**。点「发送三条」后核对电脑收到三条，再用 SSCOM 发数据，核对屏幕上的文本或 HEX；两边内容正确后点「收发正常」。判定或返回时释放串口和电源。

### 6.7 音频与外设

| 模块 | 说明 | 文件 |
|------|------|------|
| 本机蜂鸣器 | GPIO73 驱动 BUZ1，厂测页单独测试；`features.buzzer` 为 false，不显示蜂鸣器设置 | `drv/air8607c1_board.lua`、`app/air8607c1_factory.lua` |
| DAC 喇叭 | J102 HT6873 通路，厂测页播放「音频播放测试」 | `app/air8607w1_factory.lua` |
| UVC 摄像头 | AirCAMERA_1034 接 J8，优先 480×320 MJPEG | `drv/periph/uvc*.lua`、`ui/air8607w1_test_win.lua` |
| RS485 | UART1，GPIO74 方向控制，GPIO23 隔离侧供电 | `drv/periph/rs485.lua` |
| TTL | UART2，J3 对外，9600、8N1 | `drv/periph/uart*.lua` |
| SD/TF | SPI1，CS GPIO8，电源 GPIO22，挂载 `/sd` | `drv/periph/sd*.lua`、`app/air8607w1_factory.lua` |
| 共享脚仲裁 | 串口、SD、UVC 等共享电源/引脚时按需申请和释放 | `drv/periph/shared_pin.lua` |

---

## 七、演示硬件环境

- Air8607C1 V0 主控板 x 1，Air8607W1 扩展底板 x 1
- 10 寸 1024×600 RGB 触摸屏 + GT911 触摸排线 x 1
- Type-C 数据线 x 1
- USB–TTL、USB–RS485 工装各 1
- AirCAMERA_1034 UVC 摄像头 x 1
- J102 喇叭 x 1，CR2032 纽扣电池 x 1，FAT32 TF 卡 x 1
- 5 V / 24 V 电源与对应工装线束

注意事项：
- J3-1 为 VIN_24V，正常测试时留空，避免把 24 V 引入工装。
- Air6205 使用普通 SPI Airlink 从机固件，不用 Wi-Fi 透传固件。
- DAC 测试前必须断开 C1 的 BUZ1 / R422 支路，避免蜂鸣器和功放同时驱动。
- 插拔屏线、触摸排线、摄像头和 TF 卡前先断电。

---

## 八、演示软件环境

### 8.1 开发工具

- [Luatools 下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)
- SSCOM 串口工具，用于 TTL / RS485 收发
- Air6205 下载工具，用于 J21 从机固件升级
- 合宙引擎主机购买链接：<https://luat.taobao.com/category-1841239809.htm>

### 8.2 内核固件

- Air1603 / CCM4211 对应 LuatOS 内核固件
- 本工程只提供脚本与资源，不附带内核 SOC、PDF、验证记录
- `wifi.local.json` 为随包烧录的工厂 Wi-Fi 配置，需单独维护
- 下载脚本后确认内核版本与 `display`、`airui`、`exwin` 等库匹配

---

## 九、使用步骤

### 9.1 确认硬件配置

本工程只适用于 Air8607C1 V0 主控板 + Air8607W1 扩展底板 + 10 寸 1024×600 屏。确认底板为 Air8607W1，屏线、触摸排线、摄像头、Wi-Fi 天线已接好；J3-1 VIN_24V 正常测试时留空。

### 9.2 烧录软件

1. 用 Luatools 选择 Air1603 / CCM4211 对应内核固件。
2. 将 `factory` 目录作为脚本工程下载。
3. 同时更新 `main.lua` 和 `core/platform_loader.lua`，避免 PROJECT 映射未命中回退 PC 配置。
4. 首次启动确认日志出现 `platform_loader 配置加载成功: air8607c1_config`。

### 9.3 功能测试

1. 上电后确认 Logo、桌面正常显示，背光已点亮。
2. 点桌面「功能测试」，进入测试页。
3. 页面顶部有「C1 本机」和「扩展底板」两个页签；列表标题显示 Air8607W1 和版本号。
4. 先完成 C1 本机项，再按工装接线完成扩展底板项。
5. 所有项通过后记录日志；测试结果不写 FSKV，重启后清空。

---

## 十、故障排除

1. **桌面没有「功能测试」图标**：先确认日志中是否出现 `未找到 PROJECT 映射`。C1/W1 必须使用 `Air8607C1_Air8607W1_10inch_1024x600`；写错会回退 PC 配置，屏幕可能仍能点亮，但硬件与测试入口全丢。另需确认 `features.other_func` 与 `ui.show_other_func` 均为 true。
2. **屏幕黑屏 / 背光不亮**：查看 `display.init` 与 `lcd_common 背光已开启` 日志；确认 `hw.lcd.params` 的 `w/h/pclk_hz` 与屏一致，PWM3 通道和 `level` 正确；确认 `main.lua` 与 `platform_loader.lua` 已同时下载。
3. **外设无电 / 上电失败**：查看日志 `POWER_ON <i> GPIO<n> 高/低 回读 <x>` 和 `POWER_ON 引脚设置失败`。重点核对 GPIO22（TF 电源）、GPIO23（隔离 RS485 电源）、GPIO65（J8 VBUS / PWM1）、GPIO72（Wi-Fi 电源）、GPIO73（蜂鸣器 / 功放）。
4. **触摸无响应 / 坐标错**：确认 GT911 的 I2C1、`pin_rst = 14`、`pin_int = 51`；确认 `POWER_ON_DONE` 后初始化；坐标错时核对 `w/h` 与旋转方向。
5. **Wi-Fi 扫描不到**：确认 Air6205 电源 GPIO72、SPI5 的 CS 56 / RDY 12、从机固件和天线；查看 `net_manager` 初始化日志。
6. **Wi-Fi 连接失败**：核对 `wifi.local.json` 的 `ssid` / `password`；手动密码只对当次连接有效；必要时重启设备冷启动 Airlink。
7. **SD/TF 挂载失败**：确认 FAT32、SPI1 的 CS 8 / CLK 9 / MISO 10 / MOSI 11、电源 GPIO22；查看挂载日志。
8. **UVC 无图像**：确认 AirCAMERA_1034 接 J8、VBAT/GND 已分接、UART 信号线可留空；确认 USB 主机与 MJPEG 描述符；优先 480×320。
9. **DAC 无声**：确认喇叭接 J102-1/2，GPIO73 功放使能，测试前断开 BUZ1 / R422；确认 `w1.dac.volume` 不为 0。
10. **VRTC 不保持**：确认 CR2032 电压、电池座接触和 `w1.vrtc.off_seconds`；断电时间要覆盖设定值。
11. **串口不通**：TTL / RS485 都是 9600、8N1。RS485 由 GPIO23 供电，DE 为 GPIO74；TTL 的 TX/RX 要交叉接。退出测试页会关串口和电源，重新进入需再点「发送三条」。
12. **PWM 测试无输出**：确认 `pwm_test.channel = 1`、`pin = 65`、J100-25 接线；用示波器看 1 kHz、50% 方波。
13. **FOTA / AirCloud 不可用**：当前工程没有 `PROJECT_KEY`，因此 `features.fota`、`features.aircloud` 与 UI 开关均为 false。拿到云端机型密钥后需同步修改 `main.lua` 和 `config/air8607c1_config.lua`。
14. **测试结果重启后丢失**：结果保存在 Lua 内存表 `results` 中，只在本次开机期间显示并输出日志；没有写入 FSKV。需要留存时请保存调试日志。

