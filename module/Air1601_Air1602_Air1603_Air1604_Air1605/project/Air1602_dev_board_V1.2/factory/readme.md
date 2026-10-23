# Air1602 开发板 V1.2 默认出厂固件

## 项目简介

Air1602 开发板（EVB_Air1602 V1.2）套装默认出厂固件，采用**配置驱动架构 + TabOS 深色玻璃态界面**：

- 换硬件只改 `main.lua` 中的 `PROJECT` 一行，LCD / 触摸 / 音频 / GPIO 上电时序 / 网络 / 存储全部由 `config/` 下的配置文件声明
- LCD 走 `display` 底层初始化，再用全局 `lcd` 代理兼容原有 UI 绘制代码
- 开机快速点亮（logo + 背光），其余业务模块由 `boot_ui` 在 logo 展示期间分批延迟加载，缩短开机黑屏时间
- 默认机型：**7 寸 1024×600 RGB（AirLCD_1070），PWM3 背光可调光**

> 本文档对应的硬件资料见 <https://docs.openluat.com/air1601/product/from0to1/>、
> <https://docs.openluat.com/air1601/product/air1601_turnkey_devboard/hardware/>
> 与 <https://docs.openluat.com/accessory/AirLCD_1070/>。

## 一、已支持机型

| 序号 | 主控 | 屏幕 | 驱动 IC | 分辨率 | 触摸 | 网络 | PROJECT |
|------|------|------|---------|--------|------|------|---------|
| 1 | Air1602 | AirLCD_1070 7 寸 RGB | 免初始化 IC | 1024×600 | GT911 | 以太网(CH390) + WiFi(AirLink SPI2) 或 4G(AirLink UART3) / SD | `EVB_Air1602_7inch_1024x600_000_V012` |
| 2 | PC | 模拟器窗口 | - | 320×480 | 模拟 | ETH0 | `PC` |

> AirLCD_1070 为 RGB 接口、带 GT911 电容触摸的 7 寸 1024×600 屏。
> 该屏驱动 IC 属于**免初始化 IC**（无 SPI 引脚、无寄存器初始化序列），面板由硬件绑带引脚
> 配置，因此配置文件中**不需要** `pin_clk` / `pin_sda` / `pin_cs` / `ic_init`。
> 本工程只保留 7 寸真机配置（`config/evb_1602_7i_v12.lua`）与 PC 模拟器回退，其他尺寸如需支持请新增配置文件。

## 二、硬件配置

| 组件 | 型号 | 接口 | 引脚 / 参数 |
|------|------|------|-------------|
| 主控 | Air1602（Cortex-M7，32MB RAM + 18MB Flash） | - | - |
| 屏幕 | AirLCD_1070（7" 1024×600，免初始化 IC） | RGB565，50MHz | 复位 GPIO15，LCD_EN=GPIO57（LCD 供电使能），背光 PWM3（1KHz，支持亮度调节） |
| 屏幕时序 | - | - | HBP/HSPW/HFP = 140/20/160；VBP/VSPW/VFP = 20/3/12 |
| 触摸 | GT911（AirLCD_1070 板载） | I2C1 | SDA/SCL 走 I2C1，`pin_rst=3`，`pin_int=51`，下降沿触发 |
| 音频 | ES8311 | I2C1 + DAC0 + I2S2 | 8311_EN=GPIO43，PA_EN=GPIO73（低电平使能），播放走 DAC0，录音走 I2S2 |
| WiFi 模组 | 6205 | **AirLink SPI2**，8MHz | CS=GPIO4，RDY=GPIO13，WiFi_EN=GPIO12，WIFI_IRQ=GPIO2，WAKEUP=GPIO0 |
| 4G 模组 | Air780ER | **AirLink UART3**，2Mbps | 4G_EN=GPIO42（低电平使能），4G_RST=GPIO65（拉高复位、拉低释放），4G_IRQ=GPIO2 |
| 总供电 | - | - | GPIO58（power_on 拉高） |
| 以太网 | CH390H | SPI1 | CS=GPIO14，LAN_INT=GPIO1，LAN_EN=GPIO52 |
| SD/TF 卡 | - | SPI1 | CS=GPIO8，SD_EN=GPIO56，8MHz |
| 配件（可选） | AirSHT30 / AirVOC_1000 / AirCAMERA_1030 | I2C / USB | 见官方接线说明 |

### 以太网 + WiFi / 4G（WiFi 与 4G 二选一）

WiFi 走 AirLink SPI2（CS=GPIO4、RDY=GPIO13），4G 走 AirLink UART3（2Mbps），物理总线互不冲突。
但 **6205 WiFi 模组与 Air780ER 4G 模组都是 airlink 从机，当前固件不支持同时运行两个从机**，
因此 `features.wifi` / `features.net_4g` 与 `network` 中对应条目只能二选一。**本工程默认启用 WiFi。**

网络优先级由 `network` 数组顺序决定（`exnetif.set_priority_order`，从高到低）：**以太网 > WiFi > 4G**。
插上网线且链路正常时走以太网，否则回落到已启用的无线网络。

```lua
-- 默认配置：以太网 + WiFi
features = {
    wifi = true,                         -- AirLink SPI2（6205）
    -- net_4g = true,                    -- 切到 4G 时：打开本行并注释 wifi
    ethernet = true,                     -- SPI 以太网 CH390H
    ...
}

network = {
    -- 以太网（CH390，SPI1，CS=GPIO14）—— 最高优先级
    { type = "eth_spi", chip = "CH390", spi_id = 1, cs_pin = 14,
      irq_pin = 1, pwr_pin = 52 },
    -- WiFi（6205，AirLink SPI2）—— 第二优先级
    { type = "wifi_airlink_spi", spi_id = 2, cs_pin = 4, rdy_pin = 13,
      speed = 8 * 1000000 },
    -- 4G（Air780ER，AirLink UART3）—— 与 WiFi 二选一，默认注释
    -- { type = "4g_airlink_uart", uart_id = 3, baud = 2000000,
    --   adapter = socket.LWIP_GP_GW },
}

ui = {
    show_wifi_icon = true,               -- 顶栏 WiFi 图标
    show_4g_icon = true,                 -- 顶栏 4G 信号图标
    ...
}
```

> 切换到 4G：注释 `features.wifi` 和 `wifi_airlink_spi` 条目，打开 `features.net_4g` 与 `4g_airlink_uart` 条目。
> 反过来切回 WiFi 同理。两处必须成对切换，只改一处会导致 `features` 与 `network` 不一致。

- 以太网与 SD 卡共用 SPI1，靠不同片选区分：以太网 CS=GPIO14，SD 卡 CS=GPIO8，互不影响。
- 顶栏以太网图标由 `network` 中是否存在 `eth_*` 条目自动启用（`idle_win.lua`），无需额外开关。
- WiFi 使用 SPI 模式时需要配置 IRQ / WAKEUP 引脚（WIFI_IRQ=GPIO2、WAKEUP=GPIO0），详见配置文件尾部注释。

## 三、功能特性

- **开机流程**：`display` 初始化 → `airui` 初始化 → logo → 延时开背光（PWM3 调光）→ 分批加载业务模块 → 进入桌面
- **桌面**：时间 / 日期 / 网络状态图标 / 快捷入口 / 外部应用网格
- **设置**：音量调节、触摸音效、存储空间、内存信息、存储优先级、设备信息、IOT 账号、系统更新
- **WiFi 管理**：开关 / 扫描 / 连接 / 断开 / 保存凭证（fskv 持久化）；WiFi 走 AirLink SPI2，由 `features.wifi` 门控加载（与 4G 二选一）
- **应用市场**：搜索 / 分类 / 安装 / 卸载 / 分页
- **文件管理 / 文件传输**：本地文件浏览与局域网互传
- **多媒体**：视频播放、NES 游戏、LLM 对话、云盘、TTS
- **录音与语音链路**：Air1602 具备 I2S2 + ES8311，可录音；应用工厂的「录音 → 识别」链路可用
  （Air1601 只有内置 DAC，无法录音）
- **内置应用（出厂已开启）**：应用工厂（`app_factory`）、AI 助手（`ai_chat`）、合宙网盘（`cloud_disk`）出现在桌面 Dock；文件传输（`file_transfer`）入口在文件管理页顶部。网盘需先在设置 → IOT 账号登录（取到 `space_key` 才能浏览/下载）
- **FOTA 升级**：`libfota3`，需在 <https://iot.openluat.com> 创建项目并填写 `PROJECT_KEY`
- **AirCloud 接入**：`aircloud_app`，与 FOTA 共用项目密钥
- **外设热插拔**：`periph_loader` 按配置探测 I2C 配件（温湿度 / VOC 等）

## 四、目录结构

```
factory/
├── main.lua                       # 入口：PROJECT / VERSION / PROJECT_KEY + 4 阶段初始化
├── core/
│   └── platform_loader.lua        # 平台检测 → PROJECT 映射 → 加载 config → 引脚初始化 → GPIO 上电
├── config/
│   ├── evb_1602_7i_v12.lua        # 7 寸 AirLCD_1070 1024×600 + PWM 背光 + ES8311
│   ├── pc_default.lua             # PC 模拟器配置
│   └── template.lua               # 配置字段完整说明
├── drv/
│   ├── lcd/
│   │   ├── lcd_common.lua         # 构建 _G.lcd_drv / _G.tp_drv、全局 lcd 代理
│   │   ├── lcd_display_rgb.lua    # RGB 屏统一驱动（display 库初始化）
│   │   └── lcd_st7701s_5in.lua    # ST7701S 5 寸屏驱动（备用）
│   ├── tp/tp_gt911.lua            # GT911 触摸驱动
│   └── periph/periph_loader.lua   # 外设探测与加载
├── app/
│   ├── app_main.lua               # 业务模块加载器（core / optional 两批）
│   ├── network/                   # net_manager（多网优先级）、net_init（DNS/事件）
│   ├── wifi/                      # WiFi 管理 + fskv 凭证存储
│   ├── cloud/                     # AirCloud 接入、云盘
│   ├── settings/                  # 设置子模块（显示/声音/存储/内存/关于/IOT/自动）
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
│   ├── settings/                  # 设置页（12 个文件）
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
   │         → 延时开背光（PWM3）→ require exwin/exapp
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
    name = "EVB_Air1602_7inch_1024x600_000_V012",
    chip = "Air1602",
    baseboard = "Air1602 EVB V012",

    pins = {},                          -- 引脚复用（Air1602 无特殊需求）

    power_on = {                        -- 上电时序
        { pin = 58, dir = 0, level = 1 },                          -- 总供电
        { pin = 56, dir = 0, level = 1 },                          -- SD_EN
        { pin = 57, dir = 0, level = 1 },                          -- LCD_EN
        { pin = 43, dir = 0, level = 1 },                          -- 8311_EN
        { pin = 12, dir = 0, level = 1, delay = 50 },              -- WiFi_EN（6205 上电）
        { pin = 42, dir = 0, level = 0, delay = 50 },              -- 4G_EN 拉低使能
        { pin = 65, dir = 0, level = 1, delay = 100 },             -- 4G_RST 拉高复位
        { pin = 65, dir = 0, level = 0, delay = 1000 },            -- 4G_RST 拉低释放
        { pin = 52, dir = 0, level = 1 },                          -- LAN_EN
    },

    hw = {
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb", pin_rst = 15, pin_pwr = 57,
                w = 1024, h = 600,
                hbp = 140, hspw = 20, hfp = 160,   -- 实测时序
                vbp = 20,  vspw = 3,  vfp = 12,
                bus_speed = 50 * 1000 * 1000,
                -- 免初始化 IC：无需 pin_clk / pin_sda / pin_cs / ic_init
            },
            need_buffer = true,
            screen_size = 7.0,
            font = { size = 20 },
            backlight = { pwm_ch = 3, pwm_freq = 1000 },  -- PWM3 调光
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 1, pin_rst = 3, pin_int = 51,
                int_type = tp.FALLING,
                w = 1024, h = 600,
            },
        },
        audio = {
            model = "es8311", i2c_id = 1,
            tx_bus_type = 2, tx_bus_id = 0,    -- DAC0 播放
            rx_bus_type = 1, rx_bus_id = 2,    -- I2S2 录音
            dac_ctrl = 43, pa_ctrl = 73, pa_on_level = 0,
            record_format = "AMR_NB", max_record_time = 30,
            ...
        },
    },

    features = {
        wifi = true,                    -- AirLink SPI2（6205）
        net_4g = true,                  -- AirLink UART3（Air780ER）
        ethernet = true,                -- SPI 以太网 CH390H（SPI1_CS=GPIO14）
        sd_card = true,                 -- SD/TF 卡（SPI1_CS=GPIO8）
        speaker = true,
        mic = true,                     -- I2S2 + ES8311 录音
    },

    network = {
        { type = "eth_spi", chip = "CH390", spi_id = 1, cs_pin = 14,
          irq_pin = 1, pwr_pin = 52 },
        { type = "wifi_airlink_spi", spi_id = 2, cs_pin = 4, rdy_pin = 13,
          speed = 8 * 1000000 },
        { type = "4g_airlink_uart", uart_id = 3, baud = 2000000,
          adapter = socket.LWIP_GP_GW },
    },

    ui = {
        show_wifi_icon = true,
        show_4g_icon = true,
        show_storage_settings = true,
    },

    storage = {
        sd_card = { spi_id = 1, pin_cs = 8, speed = 8 * 1000 * 1000 },
    },
}
```

`features` 中的布尔字段**只写 `= true` 表示开启，不写即关闭**。
`network` 段缺失时，`net_manager.legacy_to_network()` 会按 `features` 推断，Air1601/Air1602 上默认推断为
`wifi_airlink_spi`（spi_id=1、cs=8、rdy=14），与本底板 WiFi 的 SPI2（cs=4、rdy=13）接法不符，
因此**必须显式写出 `network`**。

## 七、如何适配新硬件

1. 在 `config/` 新建配置文件（可复制 `evb_1602_7i_v12.lua` 修改）
2. 在 `core/platform_loader.lua` 的 `PROJECT_MAP` 中添加 `["新PROJECT名"] = "配置文件名"`
3. 在同文件头部的 `_compile_manifest()` 中加一行 `require ("配置文件名")`
4. 在 `main.lua` 中把 `PROJECT` 改为新命名

PROJECT 命名规范：

```
{类型}_{芯片}_{尺寸}_{分辨率}_{序号}_{版本}
  EVB_Air1602_7inch_1024x600_000_V012
```

## 八、烧录

1. 用 [Luatools](https://docs.openluat.com/air1601/luatos/common/download/) 烧录 **Air1602** 最新内核固件
   （<https://docs.openluat.com/air1601/luatos/firmware/>）
2. 将本目录全部 `.lua` 脚本与 `res/` 资源一起烧录到脚本分区
3. 设备重启后自动进入出厂固件：开机 logo → 桌面
4. 本工程只保留 7 寸机型配置；新增机型按第七节操作后再重新烧录（编译清单按机型裁剪，未登记的配置文件不会打包）

### 调试串口

Air1602 的 DBG_UART 固定 **6 Mbps**，常见 CH340 不支持该波特率，需使用 **CH343** USB 转串口模块。

## 九、注意事项

- **`PROJECT_KEY` 已填写本项目密钥**：`main.lua` 中为 `LAtg2gJkhBEeQVex6Lf73V4VBwr6NlUP`，供 FOTA 与 AirCloud 鉴权使用。若更换为其他 iot.openluat.com 项目，需同步替换：

  ```lua
  PROJECT_KEY = "在 iot.openluat.com 创建项目后获得的密钥"
  ```
- **`VERSION` 必须是 `XXX.YYY.ZZZ` 三段格式**，使用合宙 FOTA 时每次发布需递增。
- **WiFi 与 4G 二选一**：WiFi 走 AirLink SPI2（CS=GPIO4、RDY=GPIO13），4G 走 AirLink UART3（2Mbps），物理总线互不冲突；但 6205 与 Air780ER 都是 airlink 从机，当前固件不支持同时运行两个从机。本工程默认启用 WiFi，切到 4G 需同时注释 `features.wifi` 与 `network` 中的 `wifi_airlink_spi`、打开 `features.net_4g` 与 `4g_airlink_uart`。
- **背光支持 PWM 调光**：V1.2 底板 LED 背光接 PWM3，设置页亮度滑块通过 `DISPLAY_BRIGHTNESS_SET` 生效，亮度值保存在 fskv（默认 100）。
- **RGB 屏残影**：`platform_loader` 上电时先以 0 占空比压灭 PWM3，`hw_init` 阶段写完首帧后才由 `backlight_on` 点亮，不要改成一开始就点亮。
- **ES8311 与触摸共用 I2C1**：`8311_EN=GPIO43` 必须保持常供电，否则会钳位 I2C1 导致触摸失效；PA_EN=GPIO73 为**低电平使能**。
- **SD 卡与以太网共用 SPI1**：CS 分别为 GPIO8 / GPIO14，可同时使用，但二者共享总线带宽。
- **配件传感器引脚**：官方配件文档中 AirSHT30 / AirVOC_1000 使用 GPIO8(CS0) / GPIO14(CS1)，与出厂固件的 SD_CS / ETH_CS 存在冲突，同时使用配件时需确认底板实际接线。

## 十、故障排除

1. **反复重启**：检查 `PROJECT` 是否与 `PROJECT_MAP` 中的键完全一致、对应 config 文件是否存在、`hw.lcd.model` 驱动名是否匹配
2. **黑屏 / 白屏**：检查 FPC 排线方向与 50PIN 接口；确认 `pin_rst=15`、`pin_pwr=57`（LCD_EN）配置，以及 PWM3 背光是否被点亮
3. **触摸无响应**：确认 GT911 在 I2C1、`pin_rst=3`、`pin_int=51`，并用 `i2c.scan()` 确认地址 0x5D/0x14；同时确认 `8311_EN=GPIO43` 已拉高
4. **4G / WiFi 上不了网**：先确认 `features` 与 `network` 是否**成对**启用（二者只能选一个）——启 WiFi 时 `features.wifi=true` 且 `network` 含 `wifi_airlink_spi`；启 4G 时 `features.net_4g=true` 且 `network` 含 `4g_airlink_uart`。再核对引脚：WiFi `spi_id=2`、`cs=4`、`rdy=13`、`WiFi_EN=GPIO12` 拉高；4G `uart_id=3`、`EN=GPIO42` 拉低、`RST=GPIO65` 拉高复位后再拉低释放
5. **以太网不通**：确认 CH390H 的 `cs_pin=14`、`LAN_EN=GPIO52` 已拉高、SPI1 已初始化、网线指示灯正常
6. **SD 卡不识别**：确认 `storage.sd_card.pin_cs=8`、`SD_EN=GPIO56` 已拉高，卡为 FAT32 格式
7. **录音失败 / 无声音**：确认 `hw.audio.rx_bus_id=2`（I2S2）、`record_format` 合法，且 `features.mic = true`
8. **FOTA 提示鉴权失败**：`PROJECT_KEY` 与 iot.openluat.com 上的项目不匹配，按第九节核对
9. **PC 模拟器无法运行**：`platform_loader` 会自动回退 `pc_default.lua`，检查模拟器是否支持 `display` 库
