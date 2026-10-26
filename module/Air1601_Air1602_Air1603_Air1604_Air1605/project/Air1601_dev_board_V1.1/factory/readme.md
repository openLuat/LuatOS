# Air1601 开发板 V1.1 默认出厂固件

## 项目简介

Air1601 开发板（EVB_Air1601 V1.1）套装默认出厂固件，采用**配置驱动架构 + TabOS 深色玻璃态界面**：

- 换硬件只改 `main.lua` 中的 `PROJECT` 一行，LCD / 触摸 / GPIO 上电时序 / 网络 / 存储全部由 `config/` 下的配置文件声明
- LCD 走 `display` 底层初始化，再用全局 `lcd` 代理兼容原有 UI 绘制代码
- 开机快速点亮（logo + 背光），其余业务模块由 `boot_ui` 在 logo 展示期间分批延迟加载，缩短开机黑屏时间
- 默认机型：**7 寸 1024×600 RGB（AirLCD_1070，驱动 IC JD9165BA）**

> 本文档对应的硬件资料见 <https://docs.openluat.com/air1601/product/from0to1/>、
> <https://docs.openluat.com/air1601/product/air1601_turnkey_devboard/hardware/>
> 与 <https://docs.openluat.com/accessory/AirLCD_1070/>。

## 一、已支持机型

| 序号 | 主控 | 屏幕 | 驱动 IC | 分辨率 | 触摸 | 网络 | PROJECT |
|------|------|------|---------|--------|------|------|---------|
| 1 | Air1601 | AirLCD_1070 7 寸 RGB | JD9165BA | 1024×600 | GT911 | 以太网(CH390) + 4G(Air780)（WiFi 注释） / SD | `EVB_Air1601_7inch_1024x600_000_V011` |
| 2 | PC | 模拟器窗口 | - | 320×480 | 模拟 | ETH0 | `PC` |

> AirLCD_1070 为 RGB 接口、带 GT911 电容触摸的 7 寸 1024×600 屏，驱动 IC 为 **JD9165BA**。
> JD9165BA 属于**免初始化 IC**（无 SPI 引脚、无寄存器初始化序列），面板由硬件绑带引脚
> （MODE / L-R / U-D / DITHB）配置，因此配置文件中**不需要** `pin_clk` / `pin_sda` / `pin_cs` / `ic_init`。
> 本工程只保留 7 寸真机配置（`config/evb_1601_7i_v11.lua`）与 PC 模拟器回退，其他尺寸如需支持请新增配置文件。

## 二、硬件配置

| 组件 | 型号 | 接口 | 引脚 / 参数 |
|------|------|------|-------------|
| 主控 | Air1601（Cortex-M7，16MB RAM + 18MB Flash） | - | - |
| 屏幕 | AirLCD_1070（JD9165BA，7" 1024×600） | RGB565，50MHz | 复位 GPIO15，背光 GPIO2（仅亮灭，不支持 PWM 调光） |
| 屏幕时序 | - | - | HBP/HSPW/HFP = 140/20/160；VBP/VSPW/VFP = 20/3/12 |
| 触摸 | GT911（AirLCD_1070 板载） | I2C1 | SDA/SCL 走 I2C1，`pin_rst=3`，`pin_int=51`，下降沿触发 |
| WiFi | Air6205（Airlink UART） | UART3，2Mbps | 使能 EN = GPIO12（拉高 120ms） |
| 以太网 | CH390H | SPI1 | CS = GPIO14 |
| SD/TF 卡 | - | SPI1 | CS = GPIO8，40MHz |
| 4G（可选外挂） | Air780EPM 等 | UART3，2Mbps | 与 WiFi **共用 UART3**，两路模组不能同时插着工作 |
| RS485 | 底板 RS485 收发器 | UART2，9600 8N1 | 方向脚（DE/RE）= GPIO12，高=发送、低=接收 |
| USB 摄像头 | AirCAMERA_1034（UVC） | USB 主机口 1 | 960×480 MJPEG 预览（不支持的档自动降档）；5V 由 GPIO12（5V_EN）可控供电，进页掉电重上电再开流 |
| GNSS（可选外挂） | Air510W | UART3，115200 | 与 WiFi / 4G **三方共用 UART3**，由底板硬件切换；模块 VBAT 直供，无可控供电脚 |
| 蓝牙 | Air5101S（串口 BLE 模组） | UART3，9600 8N1 | 与 WiFi / 4G / GNSS **四方共用 UART3**，由底板硬件切换；AT 指令模式，单包 ≤ 80 字节 |
| CAN | 底板 CAN 收发器（CAN2 通道） | 复用 UART2 | 与 RS485 **共用 UART2 及同一组引脚**，由 S3 选 CAN2 通路、U17 把 UART2 切到 CAN2（不能选 485）；收发器 S 脚接地、VIO 接 VDD_EXT，软件无需管 STB |
| 配件（可选） | AirSHT30 / AirVOC_1000 / AirCAMERA_1030 | I2C / USB | 见官方接线说明 |

### 以太网 + 4G（当前启用，以太网优先）

网络优先级由 `network` 数组顺序决定（`exnetif.set_priority_order`，从高到低）：**以太网 > 4G**。
插上网线且链路正常时走以太网；网线未插或链路不通时自动回落到 4G。

Air1601 的 Airlink WiFi（6205）与 Airlink 4G（外挂 Air780 系列）**都占用 UART3**，V1.1 底板上两路模组无法同时工作。
当前 WiFi 保持注释状态：

```lua
features = {
    ethernet = true,                     -- SPI 以太网 CH390H
    net_4g = true,                       -- AirLink UART 4G
    -- wifi = true,                      -- WiFi 与 4G 共用 UART3，二选一
    ...
}

network = {
    -- 以太网（CH390H，SPI1，CS=GPIO14）—— 最高优先级
    { type = "eth_spi", chip = "CH390", spi_id = 1, cs_pin = 14 },
    -- 4G（Air780EPM/Air780ER2，UART3）—— 第二优先级，以太网不通时回落
    { type = "4g_airlink_uart", uart_id = 3, baud = 2000000,
      adapter = socket.LWIP_GP_GW },
    -- WiFi（6205 模组，同样占用 UART3，与 4G 互斥）
    -- { type = "wifi_airlink_uart", uart_id = 3, baud = 2000000,
    --   irq = 13, adapter = socket.LWIP_STA },
}

ui = {
    show_4g_icon = true,                 -- 顶栏 4G 信号图标
    -- show_wifi_icon = true,
    ...
}
```

- 以太网与 SD 卡共用 SPI1，靠不同片选区分：以太网 CS=GPIO14，SD 卡 CS=GPIO8，互不影响。
- 顶栏以太网图标由 `network` 中是否存在 `eth_*` 条目自动启用（`idle_win.lua`），无需额外开关。
- 切换到 WiFi 时需同时互换三处：`features.wifi` ↔ `features.net_4g`、`network` 数组中的 WiFi / 4G 两条、`ui` 中的两个图标。
- `app/app_main.lua` 中 `wifi_app_real` 由 `features.wifi` 门控，当前配置下不会加载 WiFi 业务层，避免 fskv 中残留的 WiFi 凭证触发原生 WIFI 网卡干扰 airlink 4G。

若需要 WiFi 与 4G 同时在线，需换用 V1.2 底板（WiFi 走 AirLink SPI2），把 WiFi 项改成 `wifi_airlink_spi`。

## 三、功能特性

- **开机流程**：`display` 初始化 → `airui` 初始化 → logo → 延时开背光（GPIO 直控）→ 分批加载业务模块 → 进入桌面
- **桌面**：时间 / 日期 / 网络状态图标 / 快捷入口 / 外部应用网格
- **设置**：音量调节、触摸音效、存储空间、内存信息、存储优先级、设备信息、IOT 账号、系统更新、RS485 测试、USB 摄像头、GNSS 定位、蓝牙测试、CAN 测试
- **WiFi 管理**：开关 / 扫描 / 连接 / 断开 / 保存凭证（fskv 持久化）
- **应用市场**：搜索 / 分类 / 安装 / 卸载 / 分页
- **文件管理 / 文件传输**：本地文件浏览与局域网互传
- **多媒体**：视频播放、NES 游戏、LLM 对话、云盘、TTS
- **内置应用（出厂已开启）**：应用工厂（`app_factory`）、AI 助手（`ai_chat`）、合宙网盘（`cloud_disk`）出现在桌面 Dock；文件传输（`file_transfer`）入口在文件管理页顶部。网盘需先在设置 → IOT 账号登录（取到 `space_key` 才能浏览/下载）；Air1601 无 ADC 录音，应用工厂的「录音 → 识别」链路上录不到有效声音
- **FOTA 升级**：`libfota3`，需在 <https://iot.openluat.com> 创建项目并填写 `PROJECT_KEY`
- **AirCloud 接入**：`aircloud_app`，与 FOTA 共用项目密钥
- **外设热插拔**：`periph_loader` 按配置探测 I2C 配件（温湿度 / VOC 等）
- **RS485 测试**：设置页左侧入口，UART2 + 方向脚 GPIO12，固定发送 `RS485 test`（纯字符串，不做 HEX），
  下方日志按时间倒序显示收发；进页面自动开串口，退出页面自动关，UART2 不会一直被占着
- **USB 摄像头**：设置页左侧入口，UVC 摄像头画面实时预览（`airui.camera` 组件显示，帧不经过 Lua）；
  进页面先给供电脚上电等 200ms，再开流；开流（回调注册完成）后立刻掉电 300ms 重上电，
  强制 USB 主机重新枚举 —— 顺序不能反，反了会一直「等待摄像头连接」；
  开流后 6 秒还没连上会自动重开一次（兜底，最多 2 次）；
  分辨率按 960×480 申请，摄像头不支持时自动枚举实际档位并重开一次流；
  底栏状态行显示连接状态、实际分辨率与旋转角度，`重开` 再走一次上电 + 开流，
  `旋转` 当场切画面方向（0/90/180/270 顺时针），`适配` 切画面填充方式
  （适应 / 铺满 / 居中 / 拉伸）。用 AirCAMERA_1034 实测通过
- **GNSS 定位**：设置页左侧入口，外挂 Air510W 走 UART3 + 115200，`exgnss` 扩展库 + 内核 `libgnss`；
  页面上显示定位状态、参与定位卫星数、海拔、HDOP、UTC 时间与经纬度/速度/航向，每秒刷新一帧；
  进页面自动 `exgnss.open`，退出页面自动关，UART3 不会一直被占着；
  用的是 **exgnss 应用模式 1（`exgnss.DEFAULT`，常开）**：定位成功不会自己关、也没有超时关，
  只有点页面上的「停止定位」或退出本页才关 —— 页面标题下方已把这句写进界面；
  **与 WiFi / 4G 共用 UART3**，由底板硬件切换，软件不做仲裁（见第九节）；
  **AGPS 暂关**（`agps_enable = false`）：开 true 后 exgnss 会走「下星历 → 基站定位」，
  而基站定位那步 `require("lbsLoc2")`，`lbsLoc2` 在加载时就执行 `mobile.imei()`；
  本板 `mobile` 是 airlink 代理、真实 4G 挂在 UART3，GNSS 占用后 RPC 超时返回 nil，
  直接把 Lua VM 打崩。硬件能保证 4G 在位后再改回 true（见第九节）；
  **调试日志已关**（`debug = false`）：改 true 后 `libgnss.debug(true)` 会把每条 NMEA
  原始报文刷进日志（1Hz 下每秒一大段），排障时临时打开即可，不影响 `hz` 配置和页面解析；
  打开后 6 秒仍未收到任何 NMEA 会在日志里提示一次，用于区分「串口没通」和「信号没搜到」
- **蓝牙测试**：设置页左侧入口，Air5101S 板载 BLE 模组走 UART3 + 9600，`exril_5101` 扩展库；
  页面显示设备名称（手机搜到的广播名，缺省 `Air1601_Test`）、串口号、波特率、模块 MAC、固件版本与连接状态，
  下方日志按时间倒序显示「发送 / 接收 / 提示」；进页面自动打开蓝牙（切 AT 指令模式 + 写设备名 + 查信息），
  退出页面释放串口；点「发送测试数据」发一包纯字符串（`peripherals` 里的 `test_data`，缺省 `BLE test`），
  手机端写进来的数据原样显示在日志里；另有「断开手机连接」按钮，方便手机重连做多轮测试；
  **与 WiFi / 4G / GNSS 共用 UART3**：进页面前会先 `uart.close` 把串口从 4G 手里抢过来再按 9600 重开
  （不 close 的话 `uart.setup` 会被 C 层跳过，表现是发指令没有任何回包），
  退出后**不会**把 UART3 还给 4G，要继续联网请重启设备（见第九节）
- **CAN 测试**：设置页左侧入口，走 CAN2（复用 UART2），内置 `can` 库，无需外挂模组，
  入口常驻（不看 `features`，业务层只判断全局 `can` 是否存在）；
  参数写在 config 顶层的 `can = {...}`（不进 `peripherals`，开机不初始化）；
  页面显示通道（CAN2 / UART2）、波特率、发送帧 ID 与帧格式、工作模式、测试数据与总线状态，
  下方日志按时间倒序显示「发送 / 接收 / 提示」（数据全为可打印 ASCII 时直接显示文本，
  含二进制字节则显示 HEX）；进页面自动 `can.init` + `can.timing` + 设模式，
  退出页面 `can.deinit`；点「发送测试数据」发一帧（ID/帧格式/内容取 `config.can` 里的
  `tx_id` / `ext` / `test_data`，缺省 `0x12345677` 扩展帧 + `CAN test`），
  另有「切换到自测模式 / 切换到正常模式」按钮；
  **自测模式（`test`）自收自发**：不需要对端与终端电阻，点发送即可在日志里看到同一 ID 的
  「接收」行，单板就能判定收发通路正常；**正常模式（`normal`）是真总线**：
  须接对端（另一台 CAN 设备或分析仪）、两端各 120Ω 终端电阻、波特率一致，
  否则发送会因无应答反复重试、错误计数上涨，状态从「主动错误」掉到「被动错误 / 离线」；
  **CAN2 与 RS485 共用 UART2 与同一组引脚**，靠底板 S3 / U17 拨码切换（见第九节）

## 四、目录结构

```
factory/
├── main.lua                       # 入口：PROJECT / VERSION / PROJECT_KEY + 4 阶段初始化
├── core/
│   └── platform_loader.lua        # 平台检测 → PROJECT 映射 → 加载 config → 引脚初始化 → GPIO 上电
├── config/
│   ├── evb_1601_7i_v11.lua        # 7 寸 AirLCD_1070 / JD9165BA 1024×600
│   ├── pc_default.lua             # PC 模拟器配置
│   └── template.lua               # 配置字段完整说明
├── drv/
│   ├── lcd/
│   │   ├── lcd_common.lua         # 构建 _G.lcd_drv / _G.tp_drv、全局 lcd 代理
│   │   ├── lcd_display_rgb.lua    # RGB 屏统一驱动（display 库初始化）
│   │   └── lcd_st7701s_5in.lua    # ST7701S 5 寸屏驱动（备用）
│   ├── tp/tp_gt911.lua            # GT911 触摸驱动
│   └── periph/
│       ├── periph_loader.lua      # 外设探测与加载
│       ├── periph_rs485.lua       # RS485 驱动（DE 方向脚切换 + 发送完成等待）
│       └── periph_uvc.lua         # USB 摄像头驱动（可选供电脚 + 分辨率参数，不管数据流）
├── app/
│   ├── app_main.lua               # 业务模块加载器（core / optional 两批）
│   ├── network/                   # net_manager（多网优先级）、net_init（DNS/事件）
│   ├── wifi/                      # WiFi 管理 + fskv 凭证存储
│   ├── cloud/                     # AirCloud 接入、云盘
│   ├── settings/                  # 设置子模块（显示/声音/存储/内存/关于/IOT/自动/RS485/摄像头/GNSS/蓝牙/CAN）
│   ├── file_manager/              # 本地文件浏览
│   ├── file_transfer/             # 局域网文件传输
│   ├── fota/fota_app.lua          # FOTA 升级
│   ├── ntp/ntp_app.lua            # NTP 校时
│   ├── battery/battery_app.lua    # 电量采集
│   ├── nes/                       # NES 游戏
│   ├── usb_hid/                   # USB HID（键鼠）
│   ├── common/                    # 状态提供器、天气、TTS
│   └── factory/                   # 产测、录音、LLM 对话
├── ui/
│   ├── boot_ui.lua                # 开机快速点亮 + 分批加载编排
│   ├── ui_main.lua                # 窗口清单（core 9 个 + optional 4 个）
│   ├── ui_theme.lua               # 设计令牌与组件工厂（TabOS 深色玻璃态）
│   ├── idle_win.lua               # 桌面
│   ├── settings/                  # 设置页（17 个文件）
│   ├── wifi/                      # WiFi 列表 / 详情 / 连接
│   ├── app_store_win.lua          # 应用市场
│   ├── file_manager_win.lua       # 文件管理
│   ├── file_transfer_win.lua      # 文件传输
│   ├── cloud_disk_win.lua         # 云盘
│   ├── llm_chat_win.lua           # AI 对话
│   ├── factory_win.lua            # 应用工厂
│   ├── video_win.lua              # 视频播放（含 video_util / video_picker）
│   └── factory_rec_win.lua        # 录音
└── res/                           # 图标、logo、开机图、RSA 公钥
```

> `exwin` / `exapp` 为固件内置扩展库，由 `boot_ui` 在显示完成后加载，工程内**不再放入 `libs/`**。
> PC 模拟器的存储与网络由固件默认行为处理，工程内**没有 `pcconf/` 与 `fskv.bin`**。

## 五、启动流程

```
main.lua（PROJECT / VERSION / PROJECT_KEY）
   │
   ├─ 阶段1  require "platform_loader"
   │         平台检测 → PROJECT 短名映射（PROJECT_MAP）→ require config/xxx.lua
   │         → _G.project_config → pins.setup 循环 → power_on 协程 → 发布 POWER_ON_DONE
   │
   ├─ 阶段2  require "lcd_common"
   │         按 hw.lcd / hw.tp 动态 require 驱动 → 构建 _G.lcd_drv / _G.tp_drv
   │
   ├─ 阶段3  require "boot_ui"
   │         fskv.init → lcd_drv.hw_init() → airui_init() → logo → 恢复亮度
   │         → 延时开背光（10 寸 100ms / 7 寸 200ms）→ require exwin/exapp
   │         → 等 POWER_ON_DONE → tp.init → guard_audio_init
   │         → optional 协程（app_main.optional + ui_main.optional）
   │         → airui_core_init → app_main.core() → ui_main.core() → ui_theme.restore()
   │         → publish OPEN_IDLE_WIN
   │
   └─ 阶段4  sys.run()  事件循环，所有模块 publish/subscribe 解耦
```

`core/platform_loader.lua` 文件头部的 `_compile_manifest()` 是**给编译系统做文本扫描用的 require 清单**，函数永不调用，运行时不会提前加载模块。

## 六、配置文件格式

每个机型一个配置文件，字段说明见 `config/template.lua`。以默认 7 寸（AirLCD_1070）为例（节选）：

```lua
return {
    name = "EVB_Air1601_7inch_1024x600_000_V011",
    chip = "Air1601",
    baseboard = "Air1601 EVB V011",

    pins = {},                          -- 引脚复用（Air1601 无特殊需求）

    power_on = {                        -- WiFi 6205 使能
        { pin = 12, dir = 0, level = 1, delay = 120 },
    },

    hw = {
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb", pin_rst = 15, pin_bl = 2,
                w = 1024, h = 600,
                hbp = 140, hspw = 20, hfp = 160,   -- JD9165BA 实测时序
                vbp = 20,  vspw = 3,  vfp = 12,
                bus_speed = 50 * 1000 * 1000,
                -- JD9165BA 免初始化 IC：无需 pin_clk / pin_sda / pin_cs / ic_init
            },
            need_buffer = true,
            screen_size = 7.0,
            font = { size = 20 },
            -- 不配 backlight：GPIO2 背光由 pin_bl 直接控制亮灭，无 PWM 调光
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 1, pin_rst = 3, pin_int = 51,
                int_type = tp.FALLING,
                w = 1024, h = 600, gpio_reset = 3,
            },
        },
    },

    features = {
        wifi = true,                    -- Airlink WiFi
        net_4g = true,                  -- Airlink 4G（与 WiFi 共用 UART3，实际以插入的模组为准）
        ethernet = true,                -- SPI 以太网 CH390H（SPI1_CS=GPIO14）
        sd_card = true,                 -- SD/TF 卡（SPI1_CS=GPIO8）
    },

    network = {
        { type = "eth_spi", chip = "CH390", spi_id = 1, cs_pin = 14 },
        { type = "wifi_airlink_uart", uart_id = 3, baud = 2000000, irq = 13 },
        { type = "4g_airlink_uart", uart_id = 3, baud = 2000000,
          adapter = socket.LWIP_GP_GW },
    },

    ui = {
        show_wifi_icon = true,
        show_storage_settings = true,
    },

    storage = {
        sd_card = { spi_id = 1, pin_cs = 8, speed = 40000000 },
    },
}
```

`features` 中的布尔字段**只写 `= true` 表示开启，不写即关闭**。
`network` 段缺失时，`net_manager.legacy_to_network()` 会按 `features` 推断，Air1601 上易推出不存在的 `4g_native`，因此建议显式写出 `network`。

## 七、如何适配新硬件

1. 在 `config/` 新建配置文件（可复制 `evb_1601_7i_v11.lua` 修改）
2. 在 `core/platform_loader.lua` 的 `PROJECT_MAP` 中添加 `["新PROJECT名"] = "配置文件名"`
3. 在同文件头部的 `_compile_manifest()` 中加一行 `require ("配置文件名")`
4. 在 `main.lua` 中把 `PROJECT` 改为新命名

PROJECT 命名规范：

```
{类型}_{芯片}_{尺寸}_{分辨率}_{序号}_{版本}
  EVB_Air1601_7inch_1024x600_000_V011
```

## 八、烧录

1. 用 [Luatools](https://docs.openluat.com/air1601/luatos/common/download/) 烧录 Air1601 最新内核固件
   （<https://docs.openluat.com/air1601/luatos/firmware/>）
2. 将本目录全部 `.lua` 脚本与 `res/` 资源一起烧录到脚本分区
3. 设备重启后自动进入出厂固件：开机 logo → 桌面
4. 本工程只保留 7 寸机型配置；新增机型按第七节操作后再重新烧录（编译清单按机型裁剪，未登记的配置文件不会打包）

### 调试串口

Air1601 的 DBG_UART 固定 **6 Mbps**，常见 CH340 不支持该波特率，需使用 **CH343** USB 转串口模块。

## 九、注意事项

- **`PROJECT_KEY` 已填写本项目密钥**：`main.lua` 中为 `4AMuUDgSjjzZ3yNaQXmoYWHeUXjOYbV0`，供 FOTA 与 AirCloud 鉴权使用。若更换为其他 iot.openluat.com 项目，需同步替换：

  ```lua
  PROJECT_KEY = "在 iot.openluat.com 创建项目后获得的密钥"
  ```
- **`VERSION` 必须是 `XXX.YYY.ZZZ` 三段格式**，使用合宙 FOTA 时每次发布需递增。
- **WiFi / 4G / GNSS 三方共用 UART3**：见第二节说明，工程内 WiFi 与 4G 都已配置，实际以插入
  UART3 的模组为准；GNSS 是外挂 Air510W，也挂在这条线上，同样由底板硬件切换，软件不做仲裁。
  串口是「谁先 setup 谁占住」：若 4G 那一路在位、`4g_airlink_uart` 已按 2Mbps 打开 UART3，
  进 GNSS 定位页会失败并显示「打开失败：串口可能已被占用」，日志里是 `uart3 is already opened`
  —— 把硬件切到 GNSS 那一路再进页面即可，不是代码问题。
  若打开成功但 6 秒内一条 NMEA 都收不到，页面日志会提示一次，用来区分「串口没通」和「信号没搜到」。
- **蓝牙测试页会抢占 UART3（与 GNSS 页不同）**：Air5101S 固定 9600，而 `net_manager` 启动时
  就按 2Mbps 把 UART3 开给了 4G，直接 `uart.setup` 会被 C 层跳过（日志 `uart3 is opened!`），
  发 AT 指令没有任何回包。所以 `settings_ble_app` 打开前先 `uart.close(3)` 把口抢回来再按 9600 重开，
  退出页面只 `uart.close`，**不会**把 UART3 还给 4G；要继续用 4G 联网需重启设备。
  `exril_5101` 在 `require` 时就会把 UART1 按 9600 打开（库的默认槽位），
  `platform_loader` 里补登记后紧接着 `pcall(uart.close, 1)` 立刻释放，避免空占一个串口。
- **CAN 测试页与 RS485 共用 UART2**：本板 CAN 走 CAN2 通道，而 CAN2 在芯片内部复用 UART2，
  与 RS485 是**同一个串口、同一组引脚**，只能靠底板拨码二选一：S3 选 CAN2 通路、
  U17 把 UART2 切到 CAN2（不能停在 485 那一路）。软件侧的约定：
  - `settings_can_app` 打开前先 `uart.close(2)` 把串口抢回来（RS485 页正常退出会关，
    但异常退出或别处占用时口还开着，此时直接 `can.init` 收不到任何帧）；
  - 退出 CAN 页 `can.deinit` 之后再补一次 `uart.close(2)`，把串口彻底还给 RS485 页
    （不 close 的话 RS485 页打开时 `uart.setup` 会被 C 层跳过，一个字节都收不到）；
    不动 RS485 的方向脚 GPIO12（该脚由 `power_on` 常拉高）；
  - **can 编号在本版固件是 1-based**：Lua 写 `1` = CAN1（复用 UART1）、`2` = CAN2，
    所以 config 里 `can_id = 2` 才是板载 CAN2，按 0-based 的文档思维写 1 会去开 UART1；
  - **不要调 `can.node` / `can.filter`**：本版固件非 FIFO 模式的过滤有 bug，调了会一帧都收不到，
    默认就是收全部帧，测试页也刻意不做 ID 过滤；
  - 自测模式（`can.MODE_TEST`）是自收自发，单板即可验证收发自检通路；接对端测正常模式时
    两端各需 120Ω 终端电阻、波特率一致，否则发送会反复重试并累积错误（状态掉到被动错误 / 离线）。
- **GNSS 的 AGPS 需要 4G 在位**：`agps_enable = true` 时 `exgnss.fnc_open` 会
  `sys.taskInit(is_agps)`，等联网后走「下星历 → 基站定位 → 写 `$AIDPOS`」。
  其中基站定位那步 `require("lbsLoc2")`，而 `lbsLoc2.lua` 在**加载时**就无条件执行
  `lbsLoc2.imei = numToBcdNum(mobile.imei())`。本板 UART3 与 4G 硬件互斥，4G 不在位时
  `mobile.imei()` 返回 nil 会把 VM 打崩（跑在 `sys.taskInit` 里，`pcall` 拦不住）。
  所以用 AGPS 时须先把硬件切到 4G 在位的那一路；若只想纯 GNSS 定位，
  把 `agps_enable` 改成 `false` 即可 —— 解算不受影响，只是首次定位慢些。
- **背光不可调光**：V1.1 开发板背光由 GPIO2 直接控制亮灭，设置页只提供「音量调节」，`DISPLAY_BRIGHTNESS_SET`（含 AirCloud 的 `backlight:` 指令）会被忽略。
- **RGB 屏残影**：驱动在 `hw_init` 阶段先压低 `pin_bl`，首帧写入帧缓冲后才由 `backlight_on` 点亮背光，不要改成一开始就拉高。
- **SD 卡与以太网共用 SPI1**：CS 分别为 GPIO8 / GPIO14，可同时使用，但二者共享总线带宽。
- **配件传感器引脚**：官方配件文档中 AirSHT30 / AirVOC_1000 使用 GPIO8(CS0) / GPIO14(CS1)，与出厂固件的 SD_CS / ETH_CS 存在冲突，同时使用配件时需确认底板实际接线。
- **GPIO12 身兼三职**：本底板 GPIO12 既是 PA_EN / 5V_EN / 6205 EN（`power_on` 常拉高），
  又被用作 RS485 方向脚，同时还是 USB 摄像头的供电脚。三者**不同时使用**，靠「页面互斥」保证：
  - RS485 测试页：驱动把它在「接收态低 / 发送态高」之间切换，退出时靠 `de_restore = 1`
    恢复成高电平，把 5V 轨还回去；
  - USB 摄像头页：进页面只拉高供电脚并等 200ms（`ready_delay`），**不掉电**
    （重新枚举由 `excamera.preview` 内部触发），退出时**不断电**
    （`power_hold`，该脚还带 PA / 6205 的 5V）。
  若 5V 轨上的负载（外挂模组 / 音频 PA）一刻都不能断电，请改用别的 GPIO 作方向脚与
  摄像头供电脚，并同步修改 `config/evb_1601_7i_v11.lua` 里 `peripherals` 的
  `de_pin` 与 `en_pin`。
- **USB 摄像头「一直等待摄像头连接」的根因与对策**：`excamera.preview` **只靠
  `usb.EV_CONNECT` 事件驱动、不查设备是否已经连着**，且它上电后只等 100ms 就注册回调
  （它假设枚举要 1~2 秒，而本设备实测只要 ~70ms）。于是：
  - 在 preview **之前**触发枚举（给摄像头供电脚掉电上电）→ 设备提前枚举完 →
    回调注册时事件早已发过 → **永远等不到连接**；
  - 设备一直供着电没断过 → 压根没有新的 EV_CONNECT → 同样等不到。
  表现为「第二次进页面不出画面，手动点重开才出」。
  对策：**掉电重上电必须放在 preview 注册回调之后**（`settings_uvc_app` 的
  `cam_power_cycle` → 驱动 `h.recycle()`），设备的断开→重连一定被回调看见。
  因此 config 里**不开** `power_cycle`（开了会在注册前就触发枚举）。
  另加开流后 6 秒看门狗，未连上就自动重开一次（最多 2 次）兜底。
  若仍偶发失败，另查 USB 口 5V 在推流瞬间是否跌落（万用表量，低于 4.5V 即供电不足）
  与 USB 线是否过长/转接过多。
- **摄像头预览的四条硬约束**（改 `settings_uvc_win.lua` 前必读，见该文件头）：
  `airui.camera` 组件必须建在开流之前（建晚了全程黑屏且无任何日志）；
  关窗必须先关数据流、`UVC_CLOSED` 之后才能销毁组件（反序会让解码线程往已释放的组件里画，
  触发非对齐访问死机）；预览区尺寸要按剩余内存收口（显示缓冲 = 视口宽×高×2 字节×2 块）；
  **退到桌面要先让位**（下一条）。
- **退到桌面时的让位时序**（USB 摄像头页独有的坑，其它页面没有这条）：
  点左栏「桌面」是**同步**清场 —— `exwin.close_children_of` 销毁整棵子树后立刻结算焦点，
  桌面 `on_get_focus` 随即 `VP.start_play` 起视频播放器，抢硬件解码器与帧缓冲
  （480×270 双缓冲近 506KB，见 idle_win 的 on_lose_focus 注释）。
  而本页释放资源是**异步**的：关流含 `sys.wait`，`on_destroy` 里做不到当场释放完。
  两者撞上必崩（表现：只有在本页点「桌面」死机，点标题栏「返回」不死）。
  对策三件套：关流请求**插到队首**、`CLOSE_GRACE` 压到 120ms、桌面起播延后 800ms
  （`idle_win` 的 `on_get_focus`，到点还会再确认一次桌面仍在焦点上）。
- **摄像头分辨率取档**：默认档 1280×720，`peripherals` 条目里写 `w / h` 即首选档，
  超过 `max_pixels`（缺省即默认档像素数）时作废退回默认档。连上摄像头后枚举它真正
  支持的 MJPEG 档位，取「首选档命中 → 不超上限的最大档 → 最小档」，与申请档不一致时
  按实际档重开一次流。相机侧固定开销约 4.25×w×h 字节，越大预览区越小；
  本板 AirCAMERA_1034 实测支持 960×480 / 864×480 / 800×480 / 480×320 / 320×240。
- **画面方向歪了用 `rotation` 纠正**：摄像头物理摆正后画面仍是歪的，改 `peripherals` 里
  uvc 条目的 `rotation`（**顺时针** 0 / 90 / 180 / 270，本板默认 90），重新烧录生效；
  改完预览区会自动按旋转后的宽高比算（90/270 时宽高互换），画面不会被压小。
  页面上的「旋转」按钮调 `set_rotation` 当场切，用来**试角度**——但它改不了预览区尺寸，
  旋转 90/270 时画面会被 `contain` 压小，确认方向后仍要写进 config。
  底层那条 `camera.config(0, CONF_PREVIEW_ROTATE, ...)` 在本固件是空壳
  （即开流时打的 `D/camera not support yet`），不能用。

## 十、故障排除

1. **反复重启**：检查 `PROJECT` 是否与 `PROJECT_MAP` 中的键完全一致、对应 config 文件是否存在、`hw.lcd.model` 驱动名是否匹配
2. **黑屏 / 白屏**：检查 FPC 排线方向与 50PIN 接口；确认 `pin_rst` / `pin_bl` 配置
3. **触摸无响应**：确认 GT911 在 I2C1、`pin_rst=3`、`pin_int=51`，并用 `i2c.scan()` 确认地址 0x5D/0x14
4. **WiFi 扫描不到**：确认 GPIO12 已拉高使能 6205、`wifi_airlink_uart` 的 `uart_id=3`，且 UART3 上插的是 WiFi 模组（不是 4G 模组）
5. **以太网不通**：确认 CH390H 的 `cs_pin=14`、SPI1 已初始化、网线指示灯正常
6. **SD 卡不识别**：确认 `storage.sd_card.pin_cs=8`，卡为 FAT32 格式
7. **FOTA 提示鉴权失败**：`PROJECT_KEY` 与 iot.openluat.com 上的项目不匹配，按第九节核对
8. **PC 模拟器无法运行**：`platform_loader` 会自动回退 `pc_default.lua`，检查模拟器是否支持 `display` 库
