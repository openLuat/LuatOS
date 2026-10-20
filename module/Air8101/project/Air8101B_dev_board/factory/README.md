# Air8101B 开发板出厂固件（Air8101BFactory）

> 技术底座：**LuatOS Air8101B + AirUI + exnetif / excloud / airlbs 扩展库**
>
> 适用硬件：**EVB_Air8101 V3.0 开发板**（5 寸 800×480 / 10 寸 1024×600 两套配置）
>
> 日期：2026.10.19

## 一、项目简介

本工程是 Air8101B 开发板出厂固件，**产测 + 用户双模合一**：首次上电进产测，`TEST_DONE#` 后写 fskv 标记，之后每次上电直接进用户模式。

1. **产测模式**：`factory.lua` 独占 UART1（115200），按 `xxx_TEST#` 指令逐项检测，不加载任何业务模块。
2. **多网融合**：以太网（CH390H）/ WiFi STA / 4G（airlink UART 外挂 780EPM）交给 `exnetif` 按优先级调度，优先级存 fskv、界面可改。
3. **AirCloud 上报**：`aircloud_app.lua` 用 `excloud` 组结构化 TLV，默认 180 秒一包，60 秒心跳。
4. **多 WiFi 定位**：`airlbs_app.lua` 扫描周围热点，交给官方 `airlbs` 库换经纬度，默认 60 秒一次。
5. **FOTA**：`fota_app.lua` 用 `libfota3` 后台升级，默认每天检测一次，发现新版本自动下载刷写。
6. **界面**：AirUI（1.2.x），设计基准 800×480，1024×600 自动等比放大；页面含桌面、网络、WiFi 配网、温湿度、空气质量、音频、摄像头。

## 二、目录结构

```
factory/
├── main.lua                 入口：软狗 + fskv + 产测/用户分流
├── platform_loader.lua      板型选择（静态 require 对应 config）
├── board_init.lua           上电时序 + SPI0 / I2C1 / UART1 pinmux
├── board_pins.lua           板级引脚常量（唯一来源）
├── factory.lua              产测主控（指令解析 + 串口回包）
├── prod_*.lua               产测项：lcd/tp/cam/audio/sd/nand/eth/485/4g/wifi/i2c/meta
├── user_main.lua            用户模式入口（按顺序拉起各模块）
├── app_net.lua              网卡调度（exnetif）+ 对时
├── app_status.lua           时间 / 网络状态转发
├── app_storage.lua          TF 卡挂载
├── app_devsel.lua           配件板选择（温湿度 / 空气质量）
├── app_voc.lua              VOC 采集任务
├── aircloud_app.lua         AirCloud 上报 + 下行命令
├── airlbs_app.lua           多 WiFi 定位（官方 airlbs 库）
├── fota_app.lua             FOTA 后台升级（libfota3）
├── net_config.lua           网卡优先级存取（fskv）
├── temp_hum.lua             485 温湿度（Modbus RTU 主站）
├── AirVOC_1000.lua          AGS02MA 空气质量驱动
├── drv_lcd.lua / drv_tp.lua / drv_i2c.lua   显示 / 触摸 / I2C
├── ui_main.lua              UI 初始化（显示 + 字库 + 触摸）
├── ui_welcome.lua           开机画面
├── ui_idle.lua              桌面
├── ui_net.lua / ui_wifi.lua 网络状态 / WiFi 配网
├── ui_485.lua / ui_air.lua / ui_audio.lua / ui_cam.lua   功能页
├── ui_theme.lua / ui_kit.lua   主题令牌 / 公共组件
├── ui_font.ttf              字库（font_subset 生成）
├── config_5i_800x480.lua    5 寸板配置
├── config_10i_1024x600.lua  10 寸板配置
└── .airmaster/              详细文档、全量注释源码、下线资源（不烧录）
```

> 依赖扩展库：`airlbs`（含 `libnet`）、`excloud`、`exaudio`、`libfota3`、`exnetif`、`exwin`。烧录时必须一起打包。

## 三、开机流程

`main.lua`：

1. 打印 `PROJECT` / `VERSION`。
2. 启动内核软狗 `wdt`（9s 超时 / 3s 喂狗）。
3. `fskv.init()`，读 `test_done` 决定模式（`BOOT_MODE` 可强制 `factory` / `normal`）。
4. `platform_loader.load()` 按板型加载 `config_*.lua`。
5. **产测模式** → `board.power_on()` → `factory.lua`。
6. **用户模式** → `board.power_on()` → `user_main.lua`：
   `app_status` → `ui_main`（起屏）→ 300ms 后 `app_net.init` → `aircloud_app.init` → `airlbs_app.init` → `app_storage.init` → 配件板探测 → `app_net.sntp` → `fota_app.start`。

## 四、出厂配置基线

| 配置项 | 值 | 说明 |
|---|---|---|
| 默认板型 | `config_10i_1024x600` | 1024×600 HX8282 + GT911；5 寸改 `platform_loader` |
| 界面旋转 | `180` | 屏幕倒装；fskv `ui_rotation` 优先 |
| 网卡优先级 | 以太网 > WiFi > 4G | 存 fskv `net_priority`，界面可上下调 |
| 4G | airlink UART（UART1，2 Mbps） | 外挂 780EPM 系列，DNS 用模块侧代理 |
| AirCloud | 180 s 上报 / 60 s 心跳 | fskv `aircloud_cycle` / `aircloud_enable` 可覆盖 |
| airlbs | 60 s | 多 WiFi 定位，代码下限 60 s |
| FOTA | 86400 s | 每天检测一次 |
| 音频 | DAC 通道 0，PA=GPIO27，音量 40 | 功放峰值电流小，接稳压电源后可调高 |
| 485 温湿度 | UART2 9600 8N1，从站 1，寄存器 `0x001E` | EN=GPIO52，DE=GPIO37 |
| VOC | AGS02MA（0x1A），软 I2C 38/39，约 25 kHz | 与 GT911 触摸共用总线 |

**注意**：出厂固件不在开机时拉取网页配置，改配置只能改 `config_*.lua` 后重烧；`cycle:N` 这类下行命令写 fskv，断电不丢。

## 五、数据上报格式（AirCloud TLV）

| tag | 含义 | 类型 | 来源 |
|---|---|---|---|
| 256 | 温度 | FLOAT | 485 温湿度 |
| 257 | 湿度 | FLOAT | 485 温湿度 |
| 258 | TVOC（ppb） | INTEGER | AirVOC_1000 |
| 771 | VBAT 电压（mV） | INTEGER | `adc.CH_VBAT` |
| 798 | 设备 ID | ASCII | `mcu.muid()` |
| 1027 | 固件版本 | ASCII | `_G.VERSION` |
| 781 | 网络类型 | INTEGER | `exnetif` 当前出口 |
| 782 | 4G 信号强度 | INTEGER | `mobile.csq()` |
| 783 | SIM ICCID | ASCII | `mobile.iccid()` |
| 1295 | WiFi RSSI（rssi+100） | INTEGER | `wlan.getInfo()` |
| 512 | 经度 | ASCII | airlbs |
| 513 | 纬度 | ASCII | airlbs |
| 1280 | 时间戳 | INTEGER | `os.time()` |
| 1284 | 在线时长（秒） | INTEGER | 开机起算 |
| 776 | 开机原因 | INTEGER | `rtos.rebootReason()` |
| 777 | 开机次数 | INTEGER | fskv 累计 |
| 1034 | Lua 内存占用 | INTEGER | `rtos.meminfo()` |

> 任一可选字段取不到就跳过，不影响整包上报。

## 六、下行控制命令（tag 19 → 回 tag 20）

| 指令 | 格式 | 说明 |
|---|---|---|
| 设置上报频率 | `cycle:秒数`（最小 5） | 写 fskv 并重排定时器，立即生效 |
| 立即上报 | `report:once` / `report` | 触发一轮上报 |
| 开关上报 | `report:on` / `report:off` | 写 fskv，断电保持 |
| 查询状态 | `status` | 回复当前连接 / 周期 / 结果 |

## 七、传感器与配件板

- **485 温湿度**（默认）：SP3485 + UART2，Modbus RTU 主站，5 秒一次；`temp_hum.lua` 手动切方向脚，避免错过从机回包。
- **空气质量**：`AirVOC_1000`（AGS02MA），走工程软 I2C（GPIO38/39），采集 5 秒一次；总线速率约 25 kHz，与触摸共用。
- **板载 SHT30**：已被 485 温湿度替代，驱动保留但不在用户模式加载。
- **配件板单接**：现场一次只接一块，`app_devsel` 启动对应任务；没接的配件板不探测、不占总线。

## 八、使用说明

1. 用烧录工具把本目录 + 扩展库一并烧入；脚本区 512 KB，当前约 **415 KB**（含字库 137 KB）。
2. 首次上电进产测：按 `VERSION#` / `MODEL,型号#` / `HVERSION,版本#` 核对，逐项 `xxx_TEST#`，最后 `TEST_DONE#` 写标记并重启进用户模式。
3. 配网：桌面 → WiFi，扫描后点热点输密码；凭据存 fskv，重启自动重连。
4. 音频：把 wav/mp3 放 TF 卡根目录（工程内 `sd_audio/` 有 10 秒测试音），音频页自动列出。
5. FOTA：`main.lua` 的 `PROJECT` 必须与平台脚本名一致，`config_*.lua` 的 `fota.project_key` 填 Turnkey 密钥。
6. 排查日志前缀：`main` / `board_init` / `ui_*` / `app_net` / `aircloud` / `airlbs` / `fota` / `temp_hum` / `AirVOC_1000`。

## 九、官方支持渠道

- https://docs.openluat.com/ 查找文档
- https://gitee.com/openLuat/LuatOS/tree/master/module 查找代码
- 合宙官方企业微信群（https://docs.openluat.com/ 网站底部二维码，扫码加入）
- https://luat.taobao.com/ 选购核心板和开发板产品，对比验证
