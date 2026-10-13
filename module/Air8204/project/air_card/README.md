# 智能录音工牌 · LuatOS 固件项目

基于 **合宙 Air780EGH** 4G Cat.1 模组 + **LuatOS** 物联网操作系统开发的智能录音工牌固件，集成音频录制、GPS/基站定位、震动检测、远程云管等功能。

---

## 目录

- [功能特性](#功能特性)
- [硬件需求](#硬件需求)
- [软件环境](#软件环境)
- [项目结构](#项目结构)
- [快速开始](#快速开始)
- [配置说明](#配置说明)
- [模块详解](#模块详解)
- [引脚映射](#引脚映射)
- [FAQ / 常见问题](#faq--常见问题)
- [参考资源](#参考资源)

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 🎤 录音采集 | 通过 ES7243E 音频 ADC 芯片采集 I2S 音频，编码为 AMR 格式存储至 TF 卡 |
| 🗺️ 双模定位 | GPS 卫星定位 + AirLBS 基站/WiFi 辅助定位，支持室内外无缝切换 |
| 📡 云平台接入 | 基于合宙 excloud 扩展库，实现 MQTT 连接、数据上报、远程控制 |
| 📤 文件远程上传 | 录音文件通过 HTTP 上传至云端，支持断点续传 |
| 🔄 OTA 远程升级 | 基于合宙 IoT 平台的 FOTA 差分升级能力 |
| 📊 设备状态监控 | 定时上报电量、存储、内存等设备运行状态 |
| 💡 LED 状态指示 | 双路 WS2812 RGB LED，直观显示网络/录音/OTA 状态 |
| 📳 震动感知 | DA221 震动传感器，智能识别设备移动/静止状态，动态控制定位策略 |

---

## 硬件需求

### 核心模组

| 器件 | 型号 | 说明 |
|------|------|------|
| 4G 模组 | **Air780EGH** | 合宙 4G Cat.1 模组，集成 GNSS |
| 固件版本 | **LuatOS-SoC_V2013** | `.soc` 固件包已随项目提供 |

### 外设清单

| 外设 | 型号 | 接口 | 功能 |
|------|------|------|------|
| 音频 ADC | **ES7243E** | I2C + I2S | 模拟麦克风 → 数字音频转换 |
| 震动传感器 | **DA221** | GPIO 中断 + I2C | 3 轴加速度检测，运动/静止判断 |
| TF 卡座 | SPI 模式 | SPI0 | 存储 AMR 录音文件和 JSON 数据库 |
| LED 指示灯 | WS2812 RGB | GPIO(27/28) | 双路可编程 LED |
| GPS 天线 | 有源陶瓷天线 | — | 卫星定位信号接收 |
| 麦克风 | 模拟 MEMS 麦克风 | — | 音频信号输入 |

---

## 软件环境

### 开发工具

| 工具 | 用途 | 下载地址 |
|------|------|----------|
| **LuaTools** | 固件烧录、脚本下载、日志查看 | [合宙官网](https://docs.openluat.com/common/Luatools/) |
| **VS Code** | 代码编辑（可选） | — |
| **串口工具** | 串口调试（如 LLCOM） | — |

### 依赖库

本项目依赖以下 LuatOS 扩展库

| 库名 | 用途 |
|------|------|
| `excloud` | 云平台连接、数据上报、音频上传、运维日志 |
| `exgnss` | GNSS 卫星定位管理 |
| `exvib` | DA221 震动传感器驱动 |
| `airlbs` | 基站/WiFi 辅助定位（收费服务） |
| `libfota2` | 远程差分升级 |
| `libnet` | 网络适配层 |
| `httpplus` | HTTP 扩展库 |
| `json` | JSON 编码/解码 |

---

## 项目结构

```
公开demo/
├── main.lua              # 项目入口，加载所有模块，启动看门狗和内存监控
├── config.lua            # 全局配置（录音时长、定位频率、状态模式定义）
│
├── es7243e.lua           # ES7243E 音频驱动 + 录音任务
├── sd_test.lua           # TF 卡管理 + 录音记录数据库（JSON）
├── http_app.lua          # 录音文件 HTTP 上传
├── excloud_test.lua      # 云平台连接认证、心跳、数据收发
│
├── normal.lua            # GPS/GNSS 卫星定位驱动
├── fota.lua              # OTA 远程升级 + AirLBS 基站定位
│
├── da221.lua             # DA221 震动传感器驱动 + 运动检测逻辑
├── gpio_util.lua         # GPIO 控制（录音模式切换）+ 电池电量 ADC
├── led_util.lua          # WS2812 LED 状态指示控制
│
├── app.lua               # 业务调度：录音上传、设备状态上报、GPS 数据上报
│
├── pins_Air780EGH.json   # Air780EGH 引脚定义文件（LuaTools 使用）
├── LuatOS-SoC_V2013_Air780EGH_110.soc  # Core 固件包
└── ES7243E.pdf           # ES7243E 音频芯片数据手册（可选）
```

### 模块依赖关系

```
main.lua
├── config.lua              ← 全局配置
├── excloud_test.lua        ← 云平台连接
│   └── led_util.lua        ← LED 状态指示
├── es7243e.lua             ← 音频录制
│   ├── gpio_util.lua       ← 录音模式控制
│   └── sd_test.lua         ← 录音记录管理
├── app.lua                 ← 业务调度
│   ├── http_app.lua        ← 录音上传
│   │   └── sd_test.lua
│   ├── normal.lua          ← GPS 定位
│   ├── fota.lua            ← OTA + 基站定位
│   └── led_util.lua
├── da221.lua               ← 震动检测
│   ├── normal.lua
│   └── fota.lua
├── led_util.lua            ← LED 控制
├── gpio_util.lua           ← GPIO + ADC
└── sd_test.lua             ← 录音数据库
```

---

## 快速开始

### 1. 烧录 Core 固件

1. 打开 **LuaTools**
2. 选择模组型号：**Air780EGH**
3. 固件文件选择：`LuatOS-SoC_V2013_Air780EGH_110.soc`
4. 点击 **下载固件**
5. 按住模块 BOOT 键 → 上电 → 松开，等待烧录完成

### 2. 下载脚本

1. 在 LuaTools 中点击 **脚本下载**
2. 选择项目文件夹 `公开demo/`
3. 确认所有 `.lua` 和 `.json` 文件已选中
4. 点击 **下载**

### 3. 验证运行

- 打开 LuaTools 的 **串口日志** 窗口
- 模块启动后应看到 `"aircloud_connected"` 日志
- LED1 应显示绿色（MQTT 在线）

---

## 配置说明

所有可配置项集中在 `config.lua`：

```lua
config.UPLOAD_CONFIG = {
    ip = "",                    -- 服务器地址（excloud 使用内置地址，可不填）
    port = "",                  -- 服务器端口
    limitDuration = 300,        -- 单段录音最大时长（秒），默认 5 分钟
    locateFreq = 40,            -- 定位上传频率
    locateType = 2,             -- 定位模式
                                --   0: 仅在录音时开启 GPS + 基站定位
                                --   1: 仅在录音时开启 GPS + 基站定位
                                --   2: 始终开启 GPS + 基站定位（推荐）
}
```

### 关键配置项说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `limitDuration` | number | 300 | 单段录音文件的最大时长（秒）。到时自动分段 |
| `locateType` | number | 2 | 定位策略：0/1 为录音时才定位，2 为常规定位 |
| `appVersion` | string | "v1.14" | 设备版本号，用于状态上报 |
| `device_status_mode` | table | — | 设备状态枚举：ota / no_network / no_mqtt / mqtt_online |
| `record_status_mode` | table | — | 录音状态枚举：recording / record_error / uploading / no_record / ota |

---

## 模块详解

### 🎤 ES7243E 音频驱动 (`es7243e.lua`)

使用 I2C 配置 ES7243E 寄存器，通过 I2S 接口接收 PCM 音频数据，使用 `codec` 库编码为 AMR 格式。

**双缓冲写入机制：**
- `amr_buff1` / `amr_buff2`：两个 32KB 缓冲区
- 每接收约 100 个 I2S 数据包切换一次缓冲区
- 切换时触发 `"write_file"` 事件将已填满的缓冲区写入 TF 卡

**文件命名规则：** `YYYYMMDD_HHMMSS.amr`

### 🗺️ 定位系统 (`normal.lua` + `fota.lua`)

采用 **GPS + 基站辅助定位** 双模方案：

| 定位方式 | 模块 | 精度 | 适用场景 |
|----------|------|------|----------|
| GNSS 卫星定位 | `exgnss` | 2-5 米 | 室外开阔环境 |
| AirLBS 基站定位 | `airlbs` | 50-1000 米 | 室内或 GPS 信号弱环境 |

定位数据格式上报（JSON）：
```json
[{"date": 1700000000, "longitude": "113.123456", "latitude": "23.123456"}]
```

### 📡 云平台接入 (`excloud_test.lua`)

通过 `excloud` 库实现：

1. **连接认证**：使用 `auth_key` 进行设备身份认证
2. **数据上报**：基础状态 + GPS 位置，通过 `excloud.send()` 以 TLV 格式上报
3. **命令接收**：接收平台下发的控制命令
4. **心跳保活**：默认 5 分钟自动心跳
5. **文件上传**：通过 `excloud.upload_audio()` 上传录音文件
6. **运维日志**：支持设备端日志自动上传

### 📳 震动检测 (`da221.lua`)

DA221 传感器用于判断设备运动状态，动态控制 GPS 开关以节省功耗：

| 状态 | 判定条件 | GPS 行为 |
|------|---------|---------|
| 运动中 (`is_moving`) | 10 秒内震动 ≥ 5 次 | 开启定位 |
| 静止 (`is_standby`) | 60 秒内震动 < 3 次 | 关闭 GPS 节能 |

### 💡 LED 状态指示 (`led_util.lua`)

**LED1（设备状态）：**

| 颜色 | 状态 |
|------|------|
| 🟢 绿色 | MQTT 在线 |
| 🔵 蓝色 | MQTT 已断线 |
| 🔴 红色 | 无网络 |
| 🟣 紫色 | OTA 升级中 |

**LED2（录音状态）：**

| 颜色 | 状态 |
|------|------|
| 🟢 绿色 | 正在录音 |
| 🔴 红色 | 录音异常（写文件失败） |
| 🟡 黄色 | 文件上传中 |
| ⚫ 熄灭 | 未录音 |
| 🟣 紫色 | OTA 升级中 |

### 📝 录音记录管理 (`sd_test.lua`)

在 TF 卡上维护一个 `recording_db.json` 数据库，记录每段录音的元数据：

```json
[{
    "filename": "20250101_120000.amr",
    "uploadStatus": "pending",
    "startTime": 1700000000,
    "endTime": 1700000300,
    "uploadAttempts": 0,
    "lastUploadTime": 0,
    "fileSize": 12800,
    "record_start": "20250101120000",
    "record_end": "20250101120500",
    "open_record_time": "20250101120000"
}]
```

**上传状态流转：**
```
recording → pending → uploading → success → 自动删除
                              └→ failed → 重试(最多5次)
```

---

## 引脚映射

参考 `pins_Air780EGH.json`，关键引脚分配：

| 引脚编号 | 功能 | 连接设备 |
|---------|------|---------|
| GPIO27 | LED1 DATA | WS2812 灯珠 1 |
| GPIO28 | LED2 DATA | WS2812 灯珠 2 |
| GPIO22 | 录音模式检测 | 硬件开关（低电平=录音） |
| GPIO32 | ES724E 复位 | 音频芯片复位 |
| GPIO20 | 震动传感器使能 | DA221 VDD 控制 |
| WAKEUP0 | 震动中断输入 | DA221 中断输出 |
| SPI0_CS(8) | TF 卡 CS | TF 卡 SPI 片选 |
| ADC0 | 电池电压检测 | 电池分压电路 |
| UART1_RXD/TXD | 调试串口 | 调试/日志输出 |
| I2C0_SCL/SDA | I2C 总线 | ES7243E 配置 |
| I2S 接口 | I2S 音频数据 | ES7243E 音频输出 |

> 完整引脚定义详见 `pins_Air780EGH.json`

---

## FAQ / 常见问题

### Q1: 录音文件在哪里？

录音文件存储在 TF 卡根目录，文件名为 `YYYYMMDD_HHMMSS.amr`。录音元数据保存在 `/sd/recording_db.json`。

### Q2: 如何远程控制录音启停？

云平台下发 `CONTROL_COMMAND` 类型的 TLV 消息，设备通过 `excloud.send()` 接收并处理。通过 `config.record_ctrl` 字段控制：
- `-1`：由本地 GPIO 开关控制
- `"recording"`：远程开启录音
- `"not_recording"`：远程关闭录音

### Q3: 如何触发 OTA 升级？

模块启动后会自动通过 `libfota2` 检查 IoT 平台是否有新固件，同时每隔 24 小时自动检查一次。需先在 [iot.openluat.com](https://iot.openluat.com) 配置好产品密钥和升级包。

### Q4: 基站定位无法使用？

AirLBS 为 **付费服务**，需联系合宙销售开通。在 `fota.lua` 中正确配置 `airlbs_project_id` 和 `airlbs_project_key`。

### Q5: 电池续航如何？

续航取决于定位模式：
- **`locateType = 0`**（录音时定位）：续航最长
- **`locateType = 2`**（常规定位）：续航最短
- 震动检测进入静止状态后自动关闭 GPS，可显著延长续航

---

## 参考资源

| 资源 | 链接 |
|------|------|
| Air780EGH 模组资料 | [合宙官网](https://docs.openluat.com/air780egh/product/air780exxpins/) |
| 合宙 IoT 平台 | [iot.openluat.com](https://iot.openluat.com) |

---
