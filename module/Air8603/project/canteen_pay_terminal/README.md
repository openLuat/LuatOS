# 食堂收费终端 · 示例工程说明

> **这是示例代码，不是可直接上线的现场工程。**
> 原工程中的 API Key、应用 ID / 表单 ID、员工姓名、工牌二维码、客户名称、内部项目编号、本地绝对路径以及调试记录中的个人信息，均已替换为占位符或虚构数据。
> 示例默认 `C.pay.enable = false`（本地演示模式），**不会发起任何真实扣费请求**。
> **要改哪里？** 见 §0.3「修改点地图」；在代码里全文搜索「【必改」即可逐条跳到具体行。最常改的两处都在 `config/config.lua`：**WiFi 密码** `C.wifi.password`（E02）、**API Key** `C.jdy.api_key`（E03）。
> 接入自己的系统前请按 §5.0「接入前准备清单」逐项填写；填好真实凭据后**不要**把配置文件提交到公开仓库或打进对外发布的压缩包。

**Air8603 W 系列（WiFi 版）LuatOS 触屏收费终端示例。**

操作人员在触摸屏输入金额并确认，终端播报金额、提示扫码；USB 摄像头识别二维码后，屏幕显示「收款成功 + 本次金额」并语音播报，随后自动回到输入态。

**主要功能**

| 功能 | 说明 |
| --- | --- |
| 触屏输入 | 1024×600 界面，3 列数字键盘 + 确认键，金额大字显示，单笔限额 1000.00 元 |
| 语音播报 | 离线中文 TTS，播报金额、扫码提示与收款结果；播完自动关闭功放 |
| 二维码识别 | USB UVC 摄像头后台解码，只扫码、不显示取景；2 秒内同码去重 |
| 取消交易 | 误按确认后、识别到二维码之前可取消，已输金额保留 |
| 收款提示 | 左侧卡片式提示，不遮挡键盘；按任意键关闭提示，不打断正在播报的语音 |
| 状态显示 | 顶栏网络状态、状态栏流程提示、结果栏交易结果 |
| 双模式 | 演示模式不发 HTTP；对接模式演示「查余额 → 记消费」的报文结构 |

---

## 0. 示例工程说明（先看这个）

### 0.1 与真实工程的差别

| 项 | 示例工程（当前） | 接入真实系统时 |
| --- | --- | --- |
| `C.pay.enable` | `false`（演示模式） | 凭据就绪后改 `true` |
| API Key | 空字符串 `""` | 填自己的 Key，且只留在本机 |
| 应用 / 表单 ID | `YOUR_APP_ID` / `YOUR_EMPLOYEE_FORM_ID` / `YOUR_CONSUME_FORM_ID` | 换成自己后台的 ID |
| WiFi | `YOUR_WIFI_SSID` / `YOUR_WIFI_PASSWORD` | 现场 SSID 与密码 |
| 员工姓名 / 工牌码 | 「示例员工A」、`badge9000000000000001-DEMO0001`（虚构） | 换成真实数据（建议只放在后台，不写进设备代码） |
| 二维码素材 | `AMOUNT:12.54`（虚构测试码） | 换成现场测试码 |
| 后端名称 | 「后端收费系统」「表单型开放 API v5」 | 按自己的系统命名 |
| 项目编号 / 本地路径 | 已移除 | — |

示例代码中的接口路径与字段名用于演示**报文结构**，来源于公开的表单型开放 API v5；接入自建后端时请替换 `C.jdy.base_url` 与 `app/pay.lua` 里的请求字段。

### 0.2 安全建议

- 真实 API Key 只保存在设备本地的 `config/config.lua`，**不要**提交到 Git、不要打进对外分发的 zip。
- 若必须版本管理，仓库里只保留本占位符版本，另建 `config.local.lua`（加入 `.gitignore`）覆盖敏感字段。
- 发布前用下列关键词全目录搜一遍，确认无残留：`YOUR_`、真实 Key、真实姓名、真实工牌号、内部项目号、本地绝对路径。
- `docs/` 下的二维码素材（`qr_amount_12_54.html` / `.png` / `.svg`）内容 `AMOUNT:12.54` 是虚构测试数据，可随示例一起分发。

### 0.3 修改点地图（要添加 / 要修改的位置）

代码与本文使用同一套标记，**全文搜索即可定位**，不依赖行号：

| 标记 | 含义 | 搜索关键词 |
| --- | --- | --- |
| `★【必改 E0x】` | 接入真实系统必须填 / 必须改，不改功能不可用 | `【必改` 或 `E02` |
| `+【需新增 A0x】` | 在代码之外**要添加**的数据或文件 | `【需新增` |
| `▲【按需 Oxx】` | 现场调优，可选 | `【按需` |

> **★ 最常改的两处，都在 `config/config.lua`**
> - **WiFi 密码** → `C.wifi.password`（`★【必改 E02】`）：把 `"YOUR_WIFI_PASSWORD"` 换成现场密码。
> - **API Key** → `C.jdy.api_key`（`★【必改 E03】`）：把 `""` 换成后台生成的 Key。
>
> 这两处没填的直接表现：设备连不上网，或对接模式播报「未配置 API Key」（且不会发出请求）。

**① 必须修改的位置（按接入顺序）**

| 标记 | 精确位置（文件 → 字段） | 当前值 | 改成什么 | 不做的后果 |
| --- | --- | --- | --- | --- |
| E01 | `config/config.lua` → `C.wifi.ssid` | `YOUR_WIFI_SSID` | 现场 WiFi 名称 | 连不上网 |
| **E02** | `config/config.lua` → `C.wifi.password` | `YOUR_WIFI_PASSWORD` | **现场 WiFi 密码** | 连不上网 |
| **E03** | `config/config.lua` → `C.jdy.api_key` | `""` | **后台生成的 API Key** | 返回「未配置 API Key」，不发请求 |
| E04 | `config/config.lua` → `C.jdy.app_id` | `YOUR_APP_ID` | 自己的应用 ID | 接口报参数错误 |
| E05 | `config/config.lua` → `C.jdy.emp_entry_id` | `YOUR_EMPLOYEE_FORM_ID` | 员工账户表单 ID | 查不到员工 |
| E06 | `config/config.lua` → `C.jdy.pay_entry_id` | `YOUR_CONSUME_FORM_ID` | 消费记录表单 ID | 记不了消费 |
| E07 | `config/config.lua` → `C.jdy.base_url` | 公开服务地址 | 自建后端域名（沿用公开平台可跳过） | 请求发到错误地址 |
| E08 | `config/config.lua` → `C.jdy.emp_number_field` / `emp_name_field` / `emp_match_field` / `emp_balance_field` | `number` / `nametext` / `nametext` / `balance` | 与自己后台表单一致的字段名 | 查询或记账字段不匹配 |
| E09 | `config/config.lua` → `C.card.parse_rule` / `take_n` | `after_dash` / `0` | 按现场卡码格式调整 | 账户键取错，播「未登记识别码」 |
| E10 | `config/config.lua` → `C.pay.enable` | `false` | 全部就绪后改 `true` | 一直停留在演示模式（不扣费） |

**② 需要「添加」的位置（不在现有代码里）**

| 标记 | 添加到哪里 | 添加什么 | 为什么 |
| --- | --- | --- | --- |
| A01 | 后端「员工账户表」 | 给每位员工补录 `number`（识别有效位数），值要与扫码得到的账户键一致 | 否则按 `number` 查不到人，拒绝扣费 |
| A02 | 后端自动化 / 公式字段 | 「消费表新增 → 更新员工表 `balance`」 | 设备只读余额不写余额；不配则连刷两笔余额不递减 |
| A03 | 可选：新建 `config/config.local.lua`，并在 `config/config.lua` 末尾 `return C` 之前加几行覆盖逻辑；同时把该文件写进 `.gitignore` | 只放真实 Key / 密码，仓库里只留占位符版 | 避免真实凭据进版本库或对外 zip（见 §0.2） |

> A03 是**可选工程实践**，本示例没有内置，也不需要改 `main.lua` / `app.lua`。

**③ 按需修改的位置（不改也能跑）**

| 标记 | 精确位置 | 说明 |
| --- | --- | --- |
| O01 | `config/config.lua` → `C.limit.*`、`C.pay.timeout_ms` | 单笔限额、扫码 / 结果停留时长、HTTP 超时 |
| O02 | `config/config.lua` → `C.ui.*` | 货币符号、金额字号 |
| O03 | `config/config.lua` → `C.hw.*` | 引脚与屏时序、板载外部硬狗的喂狗脚 `ext_wdt_pin` 与开关 `ext_wdt_enable`，换板型才动 |
| O04 | `config/config.lua` → `C.jdy.consume_type` | 消费类别（就餐 / 夜宵…） |
| O05 | `config/config.lua` → `C.jdy.account_map` | 兜底映射，默认停用，生产不建议开 |
| O06 | `main.lua` → `PROJECT` / `VERSION` | 版本标识，Luatools 与 FOTA 会用到 |
| O07 | `drv/voice.lua` → `PLAY_VOL` | 播报音量，示例 15，现场约 70 |
| O08 | `drv/scan.lua` → `RES_INDEX` | 摄像头分辨率档位 |
| O09 | `app/pay.lua` → `http_post(...)` 两处请求体与路径 | 自建后端协议不同时改这里 |
| O10 | `ui/ui.lua` → 静态文案、配色、控件尺寸 | 界面外观 |

**最小路径**：只想跑演示模式 → 只改 **E01 / E02**；要接真实后端 → 按 E01 → E09 顺序填，确认 A01 / A02 已在后台完成，最后再改 **E10**。

---

## 1. 安装与首次运行

### 1.1 设备组成

| 部件 | 规格 |
| --- | --- |
| 主控板 | Air8603 W 系列（主控 Air1603，WiFi 版） |
| 显示屏 | 10 寸 RGB 屏，1024 × 600 |
| 触摸屏 | GT911 电容触摸，I2C1 |
| 摄像头 | USB HOST 接口 UVC 摄像头（MJPEG） |
| 扬声器 | 4Ω / 3W，板载 DAC + 功放 |
| 联网 | Air6205A WiFi 模组（Airlink UART 方式） |
| 电源 | 5V 供电，摄像头建议独立足流供电 |

### 1.2 连接

按 §3.2 的引脚定义接线，重点确认：

- 摄像头接 **USB HOST** 口，供电使能 `UVC_EN = GPIO58`；
- 扬声器接板载功放，使能 `AUDIOPA_EN = GPIO73`；`GPIO58` 与 `GPIO73` 不可互换；
- 板内 5V 使能 `5V_EN = GPIO12`，开机由程序自动拉高；
- 串口日志使用 **UART4，波特率 6000000**。

安装要求：USB 线尽量短且带屏蔽；摄像头为高速复合设备，供电不足或接触不良会导致反复枚举失败；扫码距离 **10~20cm**，光线充足。

### 1.3 烧录

工程按官方分层组织，Luatools 会把各子目录的 `.lua` 扁平打包，因此 `require "config"` / `require "ui"` 等名称**不带目录前缀**；不要在不同目录放置同名 `.lua`。

```
canteen_pay_terminal/
├── README.md                   本说明（工程根目录）
├── code/                      ← Luatools 工程目录，烧录这一层
│   ├── main.lua                入口：PROJECT / VERSION、软狗 + 外部硬狗、sys.run()
│   ├── app/    app.lua         交易状态机（业务核心）
│   │           pay.lua         扣费与支付信息回传（HTTP POST JSON）
│   ├── config/ config.lua      ★ 全部可配置参数（示例均为占位符）
│   ├── drv/    hw_init.lua     屏 / 触摸 / 字库 / 背光 / 供电
│   │           wifi.lua        WiFi 联网
│   │           voice.lua       TTS 播报与金额中文读法（require "exaudio"）
│   │           scan.lua        UVC 扫码
│   └── ui/     ui.lua          界面、键盘、收款提示卡片
└── docs/                      ← 预览与测试素材，不参与烧录
    ├── ui_preview.html         PC 静态预览
    └── qr_amount_12_54*        虚构测试二维码（html / png / svg）
```

> 下文及 §5 中的模块路径（如 `main.lua`、`app/pay.lua`、`config/config.lua`）均相对于 `code/` 目录；`docs/` 与 `code/` 平级，README 位于工程根目录。

步骤：

1. 打开 Luatools，工程目录选择 `canteen_pay_terminal/code`（含 `main.lua` 的那一层，不是外层目录）；
2. 底层固件选择 **Air1603 / Air8603 W 系列 `.soc`**（组件要求见 §3.3，4G 版固件不适用）；
3. 确认脚本清单包含 `main.lua` 与 `app/ config/ drv/ ui/` 下共 **9 个** `.lua`，并**额外加入两个仓库公共库**：`script/libs/exaudio.lua`（`drv/voice.lua` 的 `require "exaudio"` 依赖，缺少会报模块找不到）与 `script/libs/exair153x_wdt.lua`（`main.lua` 喂板载 Air153D 外部硬狗依赖，缺少**不会**开机报错、但会每 10 多分钟自动重启）；本工程不自带这两个库，`docs/` 下文件为预览与测试素材，可排除；
4. 在 `config/config.lua` 中填写 WiFi 名称与密码；若暂时只跑演示模式，其余占位符可保持原样；
5. 点击「下载 / 烧录」，上电。

### 1.4 首次上电检查

| 检查项 | 正常表现 |
| --- | --- |
| 屏幕 | 显示「食堂收费终端」界面，金额 `￥ 0.00`，右侧键盘可点 |
| 触摸 | 点数字键，金额随之变化；点 C 清空 |
| 网络 | 顶栏显示「网络：已连接」 |
| 摄像头 | 串口出现摄像头接入、格式设置、开流成功的日志 |
| 语音 | 点确认后能听到金额播报与「请扫码」 |
| 外部看门狗 | 串口出现 `exair153x_wdt` 的「初始化成功: GPIO57」与周期喂狗日志；连续运行 28 分钟以上不重启 |

**验收交易（演示模式，`C.pay.enable = false`，示例默认）**：输入 `12.50` → 确认 → 听两句播报 → 对准 `docs/qr_amount_12_54.html` 里的测试码 → 屏幕左侧显示「收款成功 ￥ 12.50」并播报 → 按任意键关闭提示（语音不中断）→ 约 4 秒后回到输入态；串口**无** HTTP 请求记录，后端不会新增任何消费记录。

**验收交易（对接模式，`C.pay.enable = true`）**：需先按 §5.0 填完占位符再切换。流程相同，但串口应依次出现 `list`（查余额）与 `create`（记消费）两次 POST 且均为 `HTTP 200`，屏幕额外显示余额。示例报文见 §5.4。建议先跑一遍演示模式隔离硬件问题，再切到对接模式。

---

## 2. 操作说明

### 2.1 屏幕布局（1024 × 600）

| 区域 | 位置 | 内容 |
| --- | --- | --- |
| 顶栏 | y=0..64 | 标题 + 右上网络状态 |
| 金额卡 | x=28..588, y=88..278 | 「本次金额」+ 大字金额（字号 100） |
| 扫码提示框 | x=28..588, y=298..468 | 扫码距离与流程说明 |
| 状态栏 / 结果栏 | x=28..588, y=500 / 526 | 流程提示、交易结果 |
| 收款成功提示卡片 | x=28..588, y=88..478 | 出现时覆盖金额卡与扫码框 |
| 数字键盘 | x=612..998, y=88..538 | `1-9`、`C`、`0`、`.` + 整行「确认」 |

提示卡片与键盘之间保留 24px 间隔，显示期间右侧按键仍可正常操作。

### 2.2 键盘

| 按键 | 作用 |
| --- | --- |
| `0` ~ `9` | 追加数字；输入最多 8 个字符、最多 2 位小数，超过单笔限额的输入被忽略 |
| `.` | 输入小数点，最多一个且不能位于开头 |
| `C` | 清空当前金额，回到 `￥ 0.00` |
| `确认` | 金额大于 0 时进入交易；否则提示「请先输入金额」 |

### 2.3 标准交易流程

1. 输入金额 → 点「确认」；
2. 播报「本次消费 + 金额中文读法」；
3. 播报「请扫码」，进入 **30 秒**扫码窗口；
4. 摄像头识别到二维码 → 演示模式直接判定收款成功；
5. 结果栏显示「收款成功 ￥ XX.XX」，左侧弹出提示卡片，同时播报「收款成功 + 金额中文读法」；
6. 结果停留 **4 秒**后清空金额与结果，回到输入态。

### 2.4 取消交易

- **可取消区间**：按下「确认」之后，至识别到二维码之前（含金额播报、扫码提示播报、等待扫码期间）。
- 在区间内按 **C**：立即结束本笔交易，**已输入金额保留**在屏幕上，可继续修改或再按 C 清空重输。
- 取消时不扣费、不回传、不播报收款结果、不进入 4 秒结果停留。
- **不打断当前正在播报的一句语音**：屏幕立即给出「已取消」提示，当前语音播完后才退出（最长约 2.6 秒）。
- 识别到二维码后取消窗口关闭，此后按 C 只关闭提示卡片，避免"本地取消但服务端已扣款"的不一致。

### 2.5 收款提示卡片

- 内容：标题「收款成功」、本次金额、提示「按任意键关闭」。
- 显示期间**按任意键**仅关闭卡片；按键不进入金额输入、不触发下一笔交易，语音继续播完。
- 卡片关闭后结果栏仍保留收款结果，直至 4 秒停留结束。

### 2.6 异常提示

| 情况 | 终端表现 |
| --- | --- |
| 30 秒内未识别到二维码 | 播报「扫码超时，请重试」，结果栏显示超时，不显示收款卡片 |
| 摄像头未就绪 | 播报「摄像头不可用，请联系管理员」 |
| 未输入金额即确认 | 状态栏提示「请先输入金额」 |
| 对接模式下扣费失败 | 播报「扣费失败 + 原因」，结果栏显示原因，不显示收款卡片 |

---

## 3. 硬件与固件规格

### 3.1 主要规格

| 项目 | 参数 |
| --- | --- |
| 主控 | Air1603，内核 480MHz |
| 显示屏 | 10 寸 RGB 1024×600，像素时钟 50MHz；时序 hbp=140 / hspw=20 / hfp=160，vbp=20 / vspw=3 / vfp=12 |
| 背光 | PWM3，1000Hz，占空比 100 |
| 触摸 | GT911，I2C1（低速），中断下降沿 |
| 摄像头 | USB HOST UVC，MJPEG；分辨率档位 960×480 / 864×480 / 800×480 / 480×320 / 320×240，均 20fps；默认 **320×240** |
| 音频 | 板载 DAC + HT6873 功放，离线中文 TTS，单声道 |
| 联网 | Air6205A，Airlink **UART3 @ 2Mbps** → WHALE 网卡 → DHCP |
| 日志串口 | UART4 @ 6Mbps |
| 看门狗 | 内部硬件狗由固件自动开启；任务级软件狗 `wdt.init(9000)` + 3 秒喂狗；板载 **Air153D 外部硬狗**由 `exair153x_wdt` 每 180 秒喂一次（GPIO57） |

### 3.2 引脚定义

| 信号 | GPIO | 方向 / 说明 |
| --- | --- | --- |
| `5V_EN` | 12 | 输出，板内 5V 供电使能，开机拉高 |
| `UVC_EN` | 58 | 输出，USB 摄像头供电使能，开机拉高 |
| `AUDIOPA_EN` | 73 | 输出，功放使能，**高电平有效** |
| Air153D `WTDOG` | 57 | 输出，经 NPN 三极管反相后接外部硬狗喂狗脚；空闲低电平，由 `exair153x_wdt` 发脉冲 |
| `LCD_DISP / RST` | 15 | 输出，屏复位 / 显示使能 |
| GT911 `RST` | 14 | 输出，触摸复位 |
| GT911 `INT` | 51 | 输入，触摸中断 |
| GT911 `I2C` | I2C1 | SCL / SDA |
| 背光 | PWM3 | 输出 |
| Airlink | UART3 | TX / RX，2Mbps；GPIO22 / GPIO23 上电时序下拉 1 秒后释放 |
| 日志 | UART4 | TX，6Mbps |

> 摄像头是 UVC + UAC 高速复合设备，自带音频接口；该接口与本终端板载 DAC / 功放无关，功放只由 GPIO73 控制。

### 3.3 固件组件要求

底层固件须为 **Air1603 / Air8603 W 系列 LuatOS `.soc`**，且包含以下能力：

| 组件 | 用途 | 缺失表现 |
| --- | --- | --- |
| `display` + `rgb_lcd` | RGB 屏驱动 | 屏幕不亮 |
| `airui` + 内置 `hzfont` 中文字库 | 界面与中文渲染（无需外部字体文件） | 界面空白、中文变方块 |
| `tp` (gt911) / `i2c` / `gpio` / `pwm` | 触摸、GPIO、背光 | 界面可见但无法点击 |
| `camera` + USB HOST + `zbuff` + `pm` | UVC 枚举、MJPEG 帧缓冲、二维码解码 | 无法扫码 |
| `audio_core` / `audio_v2` + `luat_tts` + DAC 驱动 | 离线 TTS 与功放控制 | 无声或播完有底噪 |
| `airlink` / `netdrv` (WHALE) / `wlan` / `lwip` / `socket` | WiFi 联网、DHCP、DNS | 顶栏一直显示「网络：连接中…」 |
| `http` / `json` | 对接模式下的 HTTP 请求 | 扣费请求失败 |
| `wdt` / `sys` / `mcu` / `log` | 芯片内部看门狗、协程、计时、日志 | 异常无法自恢复、日志缺失 |
| `gpio` + 扩展库 `exair153x_wdt` | 板载 Air153D 外部硬狗喂狗脉冲 | **未喂狗时约每 10 多分钟整机复位** |

- 离线 TTS 需要固件支持 **audio_v2 新音频框架**与 `type=1` 文本转语音。
- 中文使用固件内置字库；半角货币符号 `¥` (U+00A5) 不在裁剪字库中，界面统一使用**全角「￥」(U+FFE5)**。
- 语音依赖 **LuatOS 公共扩展库 `exaudio`**（仓库根目录 `script/libs/exaudio.lua`，v3.13）。本工程**不附带** `core/exaudio.lua`，`drv/voice.lua` 的 `require "exaudio"` 由该公共库提供；烧录时必须把 `script/libs/exaudio.lua` 一并加入脚本清单，否则开机报模块找不到（见 §1.3 步骤 3）。
- 板载 **Air153D 外部硬件看门狗**由公共扩展库 `exair153x_wdt`（仓库根目录 `script/libs/exair153x_wdt.lua`，v1.0）在 `main.lua` 中初始化；`wdt` 库只管芯片内部看门狗，喂不到这颗外部芯片。该库须一并加入脚本清单，否则芯片计时到 STRAP 档位（10 分钟 / 60 分钟 / 12 小时 / 24 小时）就会拉 `PWR_OFF` 整机复位（见 §1.3 步骤 3、§3.2）。
- 4G 版（M 系列）联网方式不同，不在本说明适用范围内。

### 3.4 摄像头子系统

- USB HOST 上电后由固件枚举；识别为 UVC 控制接口 + 数据接口（复合设备还包含 UAC）。
- 开流采用「只扫码」模式：不输出视频预览，MJPEG 帧送入解码器，解出的字符串由事件回调送给业务层。
- 帧缓冲在模块加载时一次性分配 `960×480 × 2`，连接断开后复用，不随重连重建。
- 默认选择 320×240 档；可配置为自动选档（优先 MJPEG、面积接近 640×480）。
- 断线或接收异常时不主动复位 USB 总线，等待下一次接入自动恢复。

### 3.5 音频子系统

- 参数：`model="dac"`、`pa_ctrl=73`、`pa_on_level=1`、`dac_delay=6`、`pa_delay=10`。
- 每句播报结束后**仅关闭功放**（保持音频驱动与 CODEC 运行），以避免功放常开放大本底噪声形成持续嘶嘶声；下一句起播时固件按 `pa_delay` 自动重新使能功放。
- 音量默认 **15**（范围 0~100，DAC 模式下 100 为原音量，仅缩放 PCM、不改变功放底噪）；现场可调整。
- TTS 音色 `[m55]`，可更换 `m51`~`m55`。
- 金额以**分**为单位在内部流转，播报前转换为中文读法（1250 → 「十二元五角」）。

---

## 4. 代码内核

采用 Lua 5.3 / LuatOS `sys` 协程消息模型：单一业务主协程负责流程编排，硬件模块通过 `sys.publish` / `sys.subscribe` 传递事件，模块之间不直接调用业务函数。

### 4.1 模块结构

```
main.lua  软狗 wdt.init(9000) + 外部硬狗 exair153x_wdt.init → require "app" → sys.run()
              │
   app/app.lua（业务主协程 sys.taskInit）
      ├── config/config.lua   全部现场参数（纯数据）
      ├── drv/hw_init.lua     屏 / 触摸 / 字库 / 背光 / 供电
      ├── drv/wifi.lua        独立联网任务，等待 IP_READY
      ├── ui/ui.lua           airui 界面；按键只发布 UI_KEY
      ├── drv/voice.lua       require "exaudio"（公共库 script/libs/exaudio.lua）；播完发布 VOICE_DONE
      ├── drv/scan.lua        camera usb_raw → 发布 SCAN_RESULT
      └── app/pay.lua         HTTP POST（仅对接模式调用）
```

`app/` 负责流程编排，`drv/` 负责硬件，`ui/` 只发布按键事件，`config/` 只提供数据。

### 4.2 启动流程

```
main.lua：定义 PROJECT / VERSION → 初始化内部软狗 wdt.init(9000) → 初始化外部硬狗 exair153x_wdt.init(GPIO57，内部起自动喂狗任务) → require "app" → sys.run()
app.lua ：sys.taskInit(main_task)
  HW.init()    供电 → RGB 屏 → airui + 中文字库 → 背光 → GT911 绑定
  UI.init()    构建界面与键盘、创建默认隐藏的收款提示卡片
  VOICE.setup()配置 DAC 与功放
  WIFI.start() 启动独立联网任务（Airlink → wlan.connect）
  SCAN.init()  拉高 5V_EN / UVC_EN → USB HOST 上电 → 等待约 3 秒枚举
  WIFI.wait_ready() 等待 IP_READY，设置 DNS，刷新顶栏网络状态
  进入主循环：sys.waitUntil("UI_KEY") → 处理按键 / 执行交易
```

摄像头枚举与开流在开机阶段完成并**保持常开流**；交易开始只是打开接收门控，交易结束关闭门控，不反复启停 USB 流。

### 4.3 事件与消息

| 消息 | 发布者 | 订阅者 | 载荷 |
| --- | --- | --- | --- |
| `UI_KEY` | 界面按键 | 主循环 + 顶层常驻订阅 | 键值 `0-9` / `.` / `C` / `OK` |
| `SCAN_RESULT` | 扫码模块 | 顶层常驻订阅 | 提取出的账户键字符串 |
| `VOICE_DONE` | 语音模块 | `say()` 内部等待（10 秒兜底） | 播放结束事件 |
| `IP_READY` | 固件（拿到 IP 时一次性发布） | WiFi 模块 | IP、网卡编号 |

**常驻订阅的必要性**：交易期间主协程阻塞在语音播报或结果停留里，普通按键处理函数不会被调用。取消键、提示卡片关闭键与扫码结果均由顶层常驻函数订阅收集；等待扫码使用 100ms 短轮询检查标志，避免反复订阅/退订之间的间隙丢失扫码消息。`IP_READY` 是一次性事件，开机流程中不得在其之前插入长时间等待。

### 4.4 交易状态机

```
主循环：等待 UI_KEY → 更新金额显示；收到「确认」且金额有效则进入 do_trade()
  do_trade(fen)
    打开取消窗口
    播报金额 ──────────── 检测取消请求
    播报「请扫码」─────── 检测取消请求
    打开扫码门控 → 30 秒轮询（扫码结果 / 取消 / 超时）
      取消 → 关闭门控，保留金额，直接回输入态
      超时 → 播报超时 → 结果停留
      扫码 → 关闭取消窗口与门控
             ├─ 本地演示模式：直接判定成功
             └─ 对接模式：HTTP 扣费，按服务端返回值判定
                  成功 → 结果栏 + 提示卡片 + 播报「收款成功 + 金额」
                  失败 → 播报「扣费失败 + 原因」
    结果停留 4 秒 → 隐藏提示卡片 → 清空金额与结果 → 清空残留按键 → 回输入态
```

提示卡片**先显示、后播报**，保证播报期间按任意键关闭卡片时语音不被打断。

### 4.5 扫码模块要点

| 环节 | 实现 |
| --- | --- |
| 回调注册 | 先清除 `scanned` 回调（与 `usb_raw` 互斥），再注册 `usb_raw` |
| 连接处理 | 枚举格式档位 → 设置分辨率与格式 → 绑定双缓冲 → 以「只扫码」模式开流 |
| 设备标识 | 开流使用连接事件返回的真实 `app_id`，不使用 `camera.USB` 设备类型常量 |
| 解码结果 | 帧回调收到解码字符串后，经门控、同码去重、横杠分段提取账户键与最小长度校验，发布 `SCAN_RESULT` |
| 对外接口 | `init()` / `start()` / `stop()` 恒返回成功；`stop()` 只关闭接收门控，摄像头保持就绪 |
| 账户键 | 由 `C.card.parse_rule` / `take_n` 从二维码提取的「识别有效位数」，直接作为员工表 `number` 字段的查询值；演示模式下任意非空内容均可通过 |

### 4.6 语音模块要点

`say(text)` 为阻塞调用：启动 TTS → 等待 `VOICE_DONE`（10 秒兜底）→ 关闭功放 → 间隔 200ms，保证多句播报不叠音。播放完成回调与调用末尾各执行一次关功放，防止回调丢失时功放常开。`amount_text(fen)` 负责分 → 中文金额读法。

### 4.7 界面模块要点

- `airui.container / label / button` 构建，按键 `on_click` 只发布 `UI_KEY`。
- 控件字号字段为 `font_size`（写成 `size` 会被忽略）；引擎按字号动态生成字库实例。
- 提示卡片用**外层容器整体显隐**（`label` 不支持单独隐藏），在界面初始化末尾创建以获得最高层级；导出 `show_pay_ok()` / `hide_pay_ok()` / `popup_visible()` 供业务层调用。
- 金额字号、货币符号、配色与静态文案均由配置或本文件集中定义。

### 4.8 网络与支付

WiFi 链路：GPIO22/23 下拉 1 秒后释放 → `uart.setup(UART3, 2Mbps)` → `airlink.config / init` → `netdrv.setup(LWIP_STA, WHALE)` → `airlink.start(MODE_UART)` → `wlan.connect` → 取得 `IP_READY` 后设置 DNS。

支付模块使用 `http.request("POST", url, headers, body, {timeout})`，请求头为 `Content-Type: application/json` 与 `Authorization: Bearer <C.jdy.api_key>`；不含签名或额外身份信息。仅上传交易必需字段，不上传图像、日志或卡面附加信息。**示例默认 `enable=false`，支付模块不会被调用。**

顺序为：B2 `list` 按 `number` 查员工（一次取回 `nametext` + `balance`）→ 余额足够才 A1 `create` 写消费记录（姓名用查到的 `nametext`）→ 两步都成功才播报「收款成功」并显示余额；任一步失败播报「扣费失败，<原因>」，不会留下半条记录。`PAY.report()` 为空实现（消费记录本身即回传）。

### 4.9 运行约束（修改代码时须遵守）

| 约束 | 说明 |
| --- | --- |
| 帧缓冲在模块顶层一次性创建 | 界面已有 1024×600 帧缓冲，反复分配 450KB×2 会触发强制 GC 并影响 USB 稳定性 |
| 开机 USB 枚举等待固定约 3 秒，且位于网络就绪等待之前 | `IP_READY` 是一次性事件，顺序变化会导致界面误报「网络：未连接」 |
| 扫码模块三个接口恒返回成功 | 否则流程会误判摄像头不可用并立即退出 |
| 开流使用真实 `app_id` | `camera.USB` 是设备类型常量，不是设备 id |
| 断线不主动复位 USB 总线 | 由下一次接入事件自愈 |
| 播报结束只关功放、保持音频驱动 | 停止整个驱动或手动拉低 GPIO73 会导致后续播报无声 |
| 提示卡片限于左侧区域 | 右边界 x=588、下边界 y=478，键盘从 x=612 开始 |
| 字号字段 `font_size`、货币符号全角「￥」 | 与字库和 AirUI 实现相关 |

---

## 5. 配置与系统集成

### 5.0 接入前准备清单

全部现场参数集中在 `config/config.lua`。示例版本里的敏感值都是占位符，接入真实系统前按下面顺序逐项替换。**每一项的精确位置（文件 → 字段）见 §0.3 修改点地图**，在代码里搜 `E0x` 可直接跳到对应行。

| 标记 | 项 | 示例占位符 / 默认值 | 换成什么 | 不做的后果 |
| --- | --- | --- | --- | --- |
| ★ E01 | WiFi 名称 | `YOUR_WIFI_SSID` | 现场 SSID | 连不上网 |
| ★ E02 | **WiFi 密码** | `YOUR_WIFI_PASSWORD` | 现场密码 | 连不上网 |
| ★ E03 | **API Key** | `""` | 后台生成的 Key | 对接模式直接返回「未配置 API Key」，不发起请求 |
| ★ E04 | 应用 ID | `YOUR_APP_ID` | 自己的应用 ID | 接口报参数错误 |
| ★ E05 | 员工表单 ID | `YOUR_EMPLOYEE_FORM_ID` | 员工账户表单 ID | 查不到员工 |
| ★ E06 | 消费表单 ID | `YOUR_CONSUME_FORM_ID` | 消费记录表单 ID | 记不了消费 |
| ★ E07 | 服务地址 | `https://api.jiandaoyun.com` | 自建后端域名（沿用公开平台可不改） | 请求发到错误地址 |
| ★ E08 | 字段别名（4 个） | `number` / `nametext` / `nametext` / `balance` | 与自己后台表单一致 | 查询或记账字段不匹配 |
| ★ E09 | 二维码规则 | `after_dash` + `take_n=0` | 按现场卡码格式调整 | 账户键取错，播「未登记识别码」 |
| + A01 | 员工表 `number`（后台添加） | 无 | 给每位员工补录识别码 | 对接模式拒绝扣费 |
| + A02 | 余额自动化（后台添加） | 无 | 消费表新增 → 更新 `balance` | 连刷两笔余额不递减 |
| ★ E10 | 后端开关 | `false` | 上述全部就绪后改 `true`（最后一步） | 一直停留在演示模式（不扣费） |
| ▲ O07 | 播报音量 | `PLAY_VOL = 15` | 现场调到 70 左右 | 声音偏小 |

> 示例中的「示例员工A」、`badge9000000000000001-DEMO0001`、`AMOUNT:12.54`、余额 100 等均为虚构数据，不存在对应真实账户，可直接删除或替换。
> 板载 Air153D 外部硬狗的开关与喂狗脚（`C.hw.ext_wdt_*`）已按 Air8603/8605 配好，不需要填；换板型才按 §0.3 的 O03 调整。

### 5.1 配置文件

| 分组 | 字段 | 示例值 | 说明 |
| --- | --- | --- | --- |
| WiFi | `C.wifi.ssid` / `password` | `YOUR_WIFI_*` | WiFi 名称与密码 |
| | `C.wifi.uart_id` / `baud` | `3` / `2000000` | Airlink 串口，W 系列固定 |
| 后端 | `C.pay.enable` | `false` | `false` 本地演示；`true` 启用后端对接 |
| | `C.pay.timeout_ms` | `8000` | 单次 HTTP 超时（查余额 / 记消费各算一次） |
| 接口 | `C.jdy.api_key` | `""` | API Key，用于 `Authorization: Bearer <key>`；示例留空 |
| | `C.jdy.base_url` | 公开服务地址 | 自建后端时替换 |
| | `C.jdy.app_id` | `YOUR_APP_ID` | 应用 ID |
| | `C.jdy.emp_entry_id` | `YOUR_EMPLOYEE_FORM_ID` | 员工账户表单 ID（查余额） |
| | `C.jdy.pay_entry_id` | `YOUR_CONSUME_FORM_ID` | 消费记录表单 ID（记消费） |
| | `C.jdy.emp_number_field` | `number` | **主路径**：「识别有效位数」字段别名 |
| | `C.jdy.emp_name_field` | `nametext` | 查到的姓名，写入消费记录 |
| | `C.jdy.emp_match_field` | `nametext` | 兜底路径：按姓名过滤 |
| | `C.jdy.emp_balance_field` | `balance` | 余额字段名 |
| | `C.jdy.fallback_to_name` | `false` | 是否允许 `number` 查不到时回退到姓名映射；默认关 |
| | `C.jdy.account_map` | `{}` | 兜底映射，示例为空表 |
| | `C.jdy.consume_type` | `就餐` | 消费类别 |
| 硬件 | `C.hw.*` | 见 §3.2 | 引脚与屏时序，换板型时才调整 |
| | `C.hw.ext_wdt_enable` | `true` | 是否喂板载 Air153D 外部硬狗；换成无该芯片的板型才关 |
| | `C.hw.ext_wdt_pin` | `57` | 喂狗 GPIO（8603/8605），经三极管接 WTDOG |
| 业务 | `C.limit.max_amount_fen` | `100000` | 单笔上限 1000.00 元 |
| | `C.limit.max_decimals` | `2` | 最大小数位数 |
| | `C.limit.scan_timeout_ms` | `30000` | 等待扫码时长 |
| | `C.limit.result_hold_ms` | `4000` | 结果停留时长 |
| | `C.limit.scan_dup_ms` | `2000` | 同码去重窗口 |
| | `C.limit.wifi_wait_ms` | `30000` | 开机等待网络就绪 |
| 界面 | `C.ui.currency` | `"￥"` | 货币符号，须为全角 |
| | `C.ui.amount_font_size` | `100` | 金额字号 |
| 二维码 | `C.card.parse_rule` | `"after_dash"` | 取横杠后；可选 `before_dash` / `before_dash_digits` / `digits` / `raw` |
| | `C.card.take_n` | `0` | `0` 全取，正数取前 N 位，负数取后 N 位 |
| | `C.card.mode` | `""` | 旧版兜底：原文 / 只留数字 / Lua 模式捕获组 |
| | `C.card.min_len` | `1` | 账户键最小长度 |

### 5.2 启用后端收费系统

1. 按 §5.0 填完 `config/config.lua` 的全部占位符；
2. 在后端给每位员工的 `number`（识别有效位数）字段补录对应码值 —— 这是唯一必须后台准备的数据，设备端不再需要逐人登记（见 §5.2.1）；
3. 按现场二维码格式设置 `C.card.parse_rule` / `take_n`（示例默认 `after_dash` + `take_n=0`）；
4. 现场把 `drv/voice.lua` 的 `PLAY_VOL` 由 15 调至 70 左右；
5. 确认字段别名与自己表单一致，再把 `C.pay.enable` 改成 `true`；
6. 重新烧录并验证：扫测试码 → 串口出现 `list` 与 `create` 两次 POST → 余额足够才显示收款成功与剩余余额 → 余额不足播报「余额不足」。

对接模式下**只有按 `number` 精确命中 1 条员工、余额足够、消费记录写入成功，才显示收款成功**；否则播报原因（未登记识别码 / 账户重复 / 余额不足）并显示失败结果。

> **余额归属（示例方案）**：余额由**后端**维护，设备端**只读不写**。终端显示的余额 = 本次读到的 `balance` 减去本笔消费，由本地计算展示，`create` 只往消费表追加流水。
> 后台必须配置「消费表新增 → 更新员工表 `balance`」的自动化（或把 `balance` 改为按流水汇总的公式字段），否则连续刷两笔时第二笔仍读到原始余额、显示值不递减。
> `app/pay.lua` 已对 `balance` 做 `tonumber()` 兜底，兼容后台把该字段改成公式后返回字符串的情况。

### 5.2.1 二维码格式与「识别有效位数」

示例协议把员工表的 `number` 命名为**「识别有效位数」**，查询示例就是拿横杠后那一段去过滤。虚构的示例二维码内容：

```
badge9000000000000001-DEMO0001
```

| 段 | 值 | 性质 |
| --- | --- | --- |
| 横杠前 | `badge9000000000000001` | 工牌 ID，**可能随发卡时间变化**，只作备用参考 |
| 横杠后 | `DEMO0001` | ★ 稳定的**「识别有效位数」**，对应员工表 `number` 字段 |

> 以上字符串纯属虚构，仅用于演示分段规则；不要把它当作任何真实卡号。

处理链路：`drv/scan.lua` 按 `C.card.parse_rule` 取段 → `take_n` 截有效位数 → 得到账户键 → `app/pay.lua` 用 `filter field=number` 查员工表 → **从同一条记录取 `nametext` 与 `balance`** → `create` 时把查到的姓名写进消费记录。`SCAN_RESULT` 的第二个参数是横杠前的备用工牌 ID，仅兜底路径使用。

- 若规定横杠后只认前 N 位，把 `C.card.take_n` 改成 N 即可，代码结构不动；
- 若二维码以后去掉横杠，现行 `parse_rule="after_dash"` 会把所有码判为空并忽略，必须同步改配置；
- 串口日志每次扫码打印「横杠前 工牌ID段 / 横杠后 识别有效位数 / 账户键 / 备用键」，可据此核对；
- 可选兜底：`C.jdy.fallback_to_name = true` 时，`number` 查不到才回退到 `C.jdy.account_map`（默认关闭）。开启后未登记 `number` 的码可能扣到旧映射的人头上，**生产环境不建议开**。

### 5.3 常用可调项

| 标记 | 文件 | 位置 | 用途 |
| --- | --- | --- | --- |
| ▲ O07 | `drv/voice.lua` | `PLAY_VOL`（文件头） | 播报音量，0~100 |
| ▲ O07 | `drv/voice.lua` | `M.say()` 中的 `[m55]` | TTS 音色 |
| ▲ O07 | `drv/voice.lua` | `M.setup()` 的 `pa_delay` / `dac_delay` | 功放与 DAC 起播延时 |
| ▲ O08 | `drv/scan.lua` | `RES_INDEX` | 摄像头分辨率档位；`5` = 320×240，`0` = 自动选档 |
| ▲ O08 | `drv/scan.lua` | `HEARTBEAT_ENABLE` | 排查 USB 连接问题时开启状态日志 |
| ▲ O10 | `ui/ui.lua` | 提示卡片容器尺寸与字号、配色、静态文案 | 视觉与提示语调整，须保持不越过键盘区域 |
| ▲ O10 | `app/app.lua` | 状态栏文案与播报文案 | 提示话术调整 |
| ▲ O09 | `app/pay.lua` | 两处 `http_post` 的请求字段与成功判定 | 适配自己的后端协议 |
| ▲ O03 | `config/config.lua` | `C.hw.ext_wdt_enable` / `ext_wdt_pin` | 板载外部硬狗开关与喂狗脚，换板型才改 |
| ▲ O06 | `main.lua` | `PROJECT` / `VERSION` | 版本标识 |

> 表中标记与 §0.3 一致，代码里全文搜 `Oxx` 可直接跳到对应行。

`docs/ui_preview.html` 为 PC 静态预览（可模拟按键与金额流程，不模拟提示卡片），位于工程根目录 `docs/` 下，不参与烧录；设备端文案以 `ui/ui.lua` 为准。

### 5.4 接口协议（仅对接模式，示例报文）

请求头固定：`Authorization: Bearer <C.jdy.api_key>`，`Content-Type: application/json`。服务地址取 `C.jdy.base_url`。

**① 查员工（账户 + 余额）** `POST /api/v5/app/entry/data/list`（B2 查询多条）

```json
{
  "app_id": "YOUR_APP_ID",
  "entry_id": "YOUR_EMPLOYEE_FORM_ID",
  "fields": ["balance", "nametext"],
  "filter": { "rel": "and", "cond": [
    { "field": "number", "type": "text", "method": "eq", "value": ["DEMO0001"] }
  ] }
}
```

响应（取 `data[1]` 的 `nametext` 与 `balance`）：

```json
{ "data": [ { "_id": "EXAMPLE_RECORD_ID", "nametext": "示例员工A", "balance": 100, "appId": "YOUR_APP_ID", "entryId": "YOUR_EMPLOYEE_FORM_ID" } ] }
```

`fields` 必须同时包含 `nametext`，否则响应里没有姓名，消费记录就不知道写谁。未命中 →「未登记识别码」；命中多条 →「账户重复」并拒绝扣费；`balance` 非数值/数字字符串 →「余额字段异常」。

**② 记消费** `POST /api/v5/app/entry/data/create`（A1 新建单条）

```json
{
  "app_id": "YOUR_APP_ID",
  "entry_id": "YOUR_CONSUME_FORM_ID",
  "data": {
    "type":     { "value": "就餐" },
    "consume":  { "value": 12.35 },
    "time":     { "value": "2026-01-01T00:00:00.000Z" },
    "nametext": { "value": "示例员工A" }
  }
}
```

响应（取 `data._id` 作为交易号）：

```json
{ "data": { "_id": "EXAMPLE_RECORD_ID", "nametext": "示例员工A", "type": "就餐", "consume": 12.35, "time": "2026-01-01T00:00:00.000Z" } }
```

`time` 取自 HTTP 响应头 `Date`（GMT → UTC ISO8601），设备 RTC 未校时也不会写出错误年份，误差 < 1 秒。

交易顺序：按 `number` 查员工（同时得到姓名与余额）→ **余额不足直接失败、不写消费记录** → 余额足够再记消费；新余额 = 旧余额 − 金额（本地计算并展示）。金额单位：`consume` 为**元**（如 12.35），由终端把「分」换算后上传。

> **示例接口不含余额更新能力**：演示的 A1/A2 新建与 B1/B2 查询里没有 update 接口。设备端**只读 `balance`、只追加消费流水**，余额递减必须由后端自动化/公式字段完成（见 §5.2）。

---

## 6. 故障排查

串口日志使用 UART4 @ 6Mbps；`I/user.*` 为业务日志，`[CAPP/N]` 为固件 USB / 网络栈日志。

| 现象 | 检查与处理 |
| --- | --- |
| 顶栏一直「网络：连接中…」 | 检查 WiFi 名称与密码、Airlink 链路与 DHCP 日志；`IP_READY` 是一次性事件，开机流程中不要在其之前插入长时间等待 |
| 每隔约 10 多分钟自动重启，无 Lua 报错 | 板载 Air153D 外部硬狗没喂上：确认 `C.hw.ext_wdt_enable=true`、`script/libs/exair153x_wdt.lua` 已加入烧录清单、串口有「初始化成功: GPIO57」；若仍重启再查 VBAT 跌落与 USB 供电 |
| 摄像头反复断开、偶发才能扫上 | 优先检查供电、USB 线材与接触：使用短屏蔽线、独立 5V 足流供电、重新插拔。日志中出现 `ep0 timeout`、`Failed to get device descriptor`、`New full-speed device` 表示物理层枚举失败 |
| 无法扫码 | 确认日志依次出现摄像头接入、格式设置、缓冲绑定、只扫码开流成功；检查 GPIO58 供电、扫码距离 10~20cm 与光照；确认 `C.card.min_len` 未过滤掉二维码内容 |
| 识别到码但无收款结果 | 检查是否在 30 秒扫码窗口内、日志里的「账户键」是否符合预期、`C.card.min_len` 是否过滤、2 秒同码去重是否命中 |
| 播报「未配置 API Key」 | 示例默认 `C.jdy.api_key` 为空且 `C.pay.enable=false`。按 §5.0 填 Key 与 ID 后再把开关改成 `true` |
| 播报「未登记识别码」 | 员工表该员工的 `number`（识别有效位数）为空或与扫码账户键不一致；对照串口日志到后端补录，或调整 `parse_rule` / `take_n` |
| 播报「账户重复」 | 同一个 `number` 被录到多条员工记录，命中多条时设备拒绝扣费，需去后台去重 |
| 连刷两笔余额不递减 | 后端未配「消费表新增 → 更新员工表 `balance`」；设备端只读余额，需配自动化或公式字段 |
| 无声音 | 检查 GPIO73、音频初始化日志、固件是否包含 `audio_v2` 与 `luat_tts`、音量是否设为 0 |
| 播完有持续嘶嘶底噪 | 功放未关闭。确认播放完成回调中的关功放逻辑存在，且只关闭 PA、不停止音频驱动、不手动拉低 GPIO73 |
| 第二句播报无声 | 关功放时一并停止了音频驱动或未清除固件功放状态；恢复「仅关 PA」方式 |
| 提示卡片常显或无法关闭 | 检查串口是否提示容器不支持 `set_hidden`；检查常驻 `UI_KEY` 订阅中的关闭分支 |
| 提示卡片显示时按键误输入金额 | 检查该阶段主协程是否仍在订阅 `UI_KEY`（应只由常驻回调处理） |
| `HTTP -8` / 非 200 | 服务地址不可达、API Key 缺失或无效、字段不匹配；本地演示模式（`enable=false`）不应产生任何 HTTP 请求 |
| 金额字太小 | 调整 `C.ui.amount_font_size`；注意字段名为 `font_size` |
| 货币符号显示成 `*` 或空白 | 使用全角「￥」，或改为「元」「RMB」 |
| 触摸无响应 | 检查 GT911 的 I2C1、RST(GPIO14)、INT(GPIO51) 与触摸初始化日志 |
| 大量 `[CAPP/N]` 日志 | 固件 USB HOST 枚举复合设备的正常输出；`W/audio_core print from irq 2 0 0` 为播报结束填静音的正常日志，均非故障 |

---

## 附录：文件清单

| 目录 | 文件 | 作用 |
| --- | --- | --- |
| 工程根目录 | `README.md` | 本说明（示例工程 / 脱敏版） |
| `code/` | `main.lua` | 入口、版本标识、内部软狗 + 板载外部硬狗喂狗、`sys.run()` |
| `code/app/` | `app.lua` | 交易状态机、取消逻辑、演示 / 对接分叉 |
| | `pay.lua` | 对接后端：按 `number` 查员工（姓名 + 余额）+ 记消费 |
| `code/config/` | `config.lua` | ★ 全部可配置参数（占位符版） |
| `code/drv/` | `hw_init.lua` | 屏 / 触摸 / 字库 / 背光 / 供电 |
| | `wifi.lua` | Airlink WiFi 联网 |
| | `voice.lua` | TTS 播报、金额读法、关功放（`require "exaudio"`） |
| | `scan.lua` | UVC 扫码、去重、横杠分段与账户键提取 |
| `code/ui/` | `ui.lua` | 界面、键盘、收款提示卡片 |
| `docs/` | `ui_preview.html` | PC 静态预览，不参与烧录 |
| | `qr_amount_12_54*` | 虚构测试二维码（内容 `AMOUNT:12.54`） |

> `docs/` 与 `code/` 平级，均位于 `canteen_pay_terminal/` 根目录下。
> `drv/voice.lua` 通过 `require "exaudio"` 使用仓库公共库 `script/libs/exaudio.lua`，`main.lua` 通过 `require "exair153x_wdt"` 使用 `script/libs/exair153x_wdt.lua`；本工程不重复附带这两个库，烧录时须一并加入脚本清单（见 §1.3 / §3.3）。
