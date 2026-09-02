# Air780EPM + excloud 云平台通信示例工程

基于 **LuatOS** 与 **excloud.lua** 扩展库，面向 **Air780EPM**（4G 主控）的云平台通信示例工程。
覆盖连接、鉴权、心跳、数据上报、服务器控制命令、文件上传（图片 / 音频 / 运维日志）等主要功能。

---

## 一、工程结构

```
air780epm/
├── main.lua                工程入口：定义 PROJECT/VERSION，require 加载全部模块，sys.run()
├── netdrv_device.lua       网络驱动设备：按配置选择并加载网卡驱动（默认 4G）
├── config.lua              全局配置：传输协议、心跳、上报周期、运维日志、命令协议说明
├── excloud_main.lua        excloud 服务核心：setup/on/open、等待网络、心跳、状态、事件分发
├── excloud_cmd.lua         服务器控制命令解析与执行（重点）
├── excloud_report.lua      业务数据上报（温度/湿度/信号/状态等）
├── excloud_upload.lua      文件上传（图片/音频/运维日志）与上传回调
├── test.jpg                真实图片上传测试资源（随工程编译进 /luadb/，鉴权后自动上传）
├── test.mp3                真实音频上传测试资源（随工程编译进 /luadb/，鉴权后自动上传）
├── netdrv/                 网卡驱动目录（由 netdrv_device.lua 按需 require）
│   ├── netdrv_4g.lua       4G 蜂窝网卡驱动（默认）
│   ├── netdrv_eth_spi.lua  SPI 以太网网卡驱动
│   ├── netdrv_multiple.lua 多网卡策略驱动
│   └── netdrv_pc.lua       PC 模拟器网卡驱动
└── readme1.md              本文档
```

| 模块 | 职责 |
|------|------|
| `main.lua` | 入口，`PROJECT/VERSION`，通过 `require` 统一加载各模块，末尾 `sys.run()` |
| `netdrv_device.lua` | 网络驱动设备：按配置选择并加载网卡驱动（默认 `netdrv_4g`），并订阅 `IP_READY`/`IP_LOSE` 网络事件 |
| `config.lua` | 集中管理可配置项：传输协议切换、心跳间隔、上报周期、运维日志、命令注册表 |
| `excloud_main.lua` | `excloud.setup` / `excloud.on` / `excloud.open`、等待 4G 网卡、自动心跳、状态查询、下行消息分发 |
| `excloud_cmd.lua` | 控制命令的解析 → 分发 → 执行 → 结果回传（`CONTROL_RESPONSE`） |
| `excloud_report.lua` | 封装 TLV 上报、周期上报、`trigger_report` 一次性触发上报 |
| `excloud_upload.lua` | 图片/音频上传、运维日志记录与批量上传、上传结果回调 |

---

## 二、运行前提

- **目标模组**：Air780EPM（4G 主控，`excloud` 会自动识别设备类型为 `1 = 4G 主控`，设备 ID 取 IMEI）
- **网络**：4G 数据卡已就绪
- **扩展库**：`excloud.lua` 需能被 `require("excloud")` 找到（见下文编译步骤）
- 依赖库：`log` / `sys` / `mcu` / `socket` / `json` / `io` 均为 LuatOS **内置库**，默认全局可用，无需 `require`

---

## 三、配置说明

所有配置集中在 `config.lua`。

### 1. 传输协议（TCP / UDP / MQTT）

```lua
transport = "tcp",   -- 可选 "tcp" / "udp" / "mqtt"
ssl = false,         -- SSL/TLS 开关（同时控制 TCP 与 MQTT 通道，默认 false；官方平台仅 MQTT 承载需 true，第三方按服务器要求）
```

| 协议 | 说明 | 相关配置 |
|------|------|----------|
| `tcp` | 基于 TCP socket 长连接（默认，最常用），**明文端口，`ssl` 必须保持 `false`** | `host` / `port` |
| `udp` | 基于 UDP socket 连接 | `udp_auth_key`（必填） |
| `mqtt` | 基于 MQTT 协议的连接，**合宙官方平台 MQTT 承载需将 `ssl` 设为 `true`** | `qos` / `keepalive` / `clean_session` / `ssl` / `username` / `password` / `mqtt_*_topic` |

> 当 `use_getip = true` 时，`excloud` 会自动调用 getip 做服务器发现，**自动**获取服务器地址、端口及上传参数，此时无需手动配置 `host` / `port` / `auth_key`。

**SSL 开关说明**：`config.ssl` 为全局开关（同时控制 TCP 与 MQTT 通道，默认 `false`）。
- **官方平台（合宙 AirCloud）**：TCP/UDP 承载走明文端口，**必须保持 `false`**（误设为 `true` 会导致 TCP 走 TLS 握手而连接失败）；MQTT 承载需要加密传输，使用官方平台 MQTT 时请设为 `true`（证书一般无需手动配置，按需见 config 第六部分）。
- **第三方平台**：按服务器实际要求配置——明文端口保持 `false`，TLS 端口设为 `true` 并按需配置证书。

### 2. 常用配置项

> 本示例默认 `use_getip = true`，由 getip 服务器发现自动获取服务器地址、端口及上传参数。**就下表而言**，该开关仅影响**连接类参数**（`host`/`port`，以及 `config.lua` 中的 `auth_key`/`udp_auth_key`）：开启时这些参数**默认保持 `nil`**，由 getip 自动获取；若用户手动填写了具体值，则以手动配置为准，getip 不会覆盖。表中其余配置项（重连、心跳、上报、日志、debug）与 getip 无关，默认值始终生效。

> 表中配置项分两类：`use_getip`/`host`/`port`/`ssl`/`auto_reconnect`/`reconnect_interval`/`max_reconnect`/`mtn_log_enabled`/`mtn_log_write_way`/`debug` 为 `excloud.setup()` 入参；`heartbeat_interval`/`auto_start_heartbeat`/`report_cycle`/`auto_upload_mtnlog`/`mtn_log_upload_cycle` 为业务层配置（非 setup 入参），由 `excloud_main`/`excloud_report`/`excloud_upload` 直接读取，不会传给 `excloud.setup()`。

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `use_getip` | `true` | 开启服务器自动发现 |
| `host` / `port` | `nil` | 服务器地址/端口（默认留空，交由 getip 自动获取；仅 `use_getip=false` 手动接入时才填写） |
| `ssl` | `false` | SSL/TLS 开关（同时控制 TCP 与 MQTT 通道）。官方平台 TCP/UDP 必须保持 `false`、MQTT 需 `true`；第三方平台按服务器要求配置 |
| `auto_reconnect` | `true` | 自动重连 |
| `reconnect_interval` | `10` | 重连间隔（秒） |
| `max_reconnect` | `3` | 最大重连次数 |
| `heartbeat_interval` | `300` | 自动心跳间隔（秒） |
| `auto_start_heartbeat` | `true` | 鉴权成功后自动启动心跳 |
| `report_cycle` | `60` | 周期上报间隔（秒） |
| `mtn_log_enabled` | `true` | 开启运维日志功能 |
| `mtn_log_write_way` | `MTN_LOG_ADD_WRITE` | 运维日志写入方式：`MTN_LOG_ADD_WRITE` 直接写盘（上传测试建议），`MTN_LOG_CACHE_WRITE` 缓存写（日志量小时可能不落盘导致文件大小 0） |
| `auto_upload_mtnlog` | `true` | 自动定时上传运维日志 |
| `mtn_log_upload_cycle` | `3600` | 运维日志上传周期（秒） |
| `debug` | `false` | excloud 底层调试日志 |

### 3. 虚拟设备调试（可选）

`config.force_virtual_device = true` 并填写 `virtual_phone_number` / `virtual_serial_num`，可在 PC 模拟器上以虚拟设备身份调试：
```lua
force_virtual_device = true,          -- 默认 false（真机 4G）
virtual_phone_number = "13800138000",
virtual_serial_num = 1,
```

---

## 四、命令协议

### 1. 下行控制命令（服务器 → 模组）

服务器通过 `CONTROL_COMMAND` 字段（`FIELD_MEANINGS.CONTROL_COMMAND = 19`）下发控制命令，其 `value` 采用 **JSON 字符串**承载，顶层为 **裸数组**（无 `fields` 外壳），按【消息 tag 路由】：

```json
[{"field_meaning":775,"data_type":0,"value":1}]
```

| 字段 | 说明 |
|------|------|
| `field_meaning` | 消息 tag，取值必须来自 `excloud.FIELD_MEANINGS`（代码里有多少就是多少，不支持自定义） |
| `data_type` | 数据类型（`excloud.DATA_TYPES.*`） |
| `value` | 该字段要设置的数值（类型由 `data_type` 决定） |

**示例下发：**
```json
[{"field_meaning":775,"data_type":0,"value":1}]
[{"field_meaning":800,"data_type":0,"value":12}]
[{"field_meaning":775,"data_type":0,"value":1},
 {"field_meaning":800,"data_type":0,"value":12}]
```

> **防呆**：若 `value` 不是合法 JSON 数组（如仅下发单个字符 `"1"`、纯文本、空数组等），视为误下发，模组**仅记录日志，不执行、不回传**，避免误动作。

#### 字段上/下行属性注意（仅供理解，模组不校验）

excloud 报文每个字段都有【传输方向】语义。**上下行属性的校验与约束由【平台端】负责**：平台在下发控制命令前，会按上下行属性自动识别并过滤，只会下发"可控制"（即"设备⇄平台"双向或"平台→设备"纯下行）的字段。**设备端（模组）不做上下行校验**，下发什么就处理什么，只需保证 `field_meaning` 存在于 `FIELD_MEANINGS` 中即可。

下表仅供开发者理解各字段语义，**不参与模组运行时逻辑**：

| 方向 | 含义 | 能否被平台下发 |
|------|------|----------------|
| `设备→平台`（纯上行） | 设备主动上报给平台的数据 | ❌ 平台端不会下发（模组收到也只按普通字段处理） |
| `设备⇄平台`（双向） | 既支持上报也支持平台下发 | ✅ 可由平台下发 |
| `平台→设备`（纯下行） | 平台下发数据 | ✅ 可由平台下发（当前协议暂无此类业务字段） |

> **注意**：A.1 控制信令（类型值 16~255，如 `CONTROL_COMMAND`/`AUTH_REQUEST`/`REPORT_RESPONSE` 等）属于协议"信封"信令，不属于控制命令里可下发的业务字段，不被当作可控制字段。

### 2. 内置可控制字段一览（示例，均为"设备⇄平台"双向字段）

> 以下为示例中"重点实现"的字段控制处理器，均执行**模拟动作**（真实项目请替换为实际硬件/业务操作）：

| 消息tag | 字段含义 | 建议类型 | 说明 |
|---------|----------|----------|------|
| `GPIO_LEVEL`(775) | GPIO高低电平 | `INTEGER` | 值为 0/1 |
| `SET_VOLTAGE`(800) | 设置电压 | `INTEGER` | 值需为数字 |
| `WORK_STATUS`(265) | 工作状态 | `INTEGER` | 无取值限制 |
| `SLEEP_MODE`(778) | 休眠模式 | `INTEGER` | 取值 0/1/3 |
| `WAKE_INTERVAL`(779) | 定时唤醒间隔 | `INTEGER` | 值需为数字 |
| `NETWORK_TYPE`(781) | 当前联网方式 | `INTEGER` | 无取值限制 |
| `BATTERY_LEVEL`(771) | 电池电压 | `INTEGER` | 值需为数字 |

> 其余字段（如 `TEMPERATURE`/`HUMIDITY`/`SMS_FORWARD`/`SMS_CONTENT` 等）若在 `field_handlers` 中未注册处理器，下发后回传 `UNREGISTERED`(3) 提示"该字段存在但未注册处理器"；你可在 `excloud_cmd.lua` 的 `field_handlers` 中为它们补充处理器。这里只关心字段是否存在与是否注册处理器，不涉及上下行校验。

### 3. 上行控制响应（模组 → 服务器）

命令执行完毕后，通过 `CONTROL_RESPONSE` 字段（`FIELD_MEANINGS.CONTROL_RESPONSE = 20`）回传结果，同样为 JSON 字符串（顶层为裸数组），**逐条对应下发的字段（回带 field_meaning）**：

```json
[{"field_meaning":775,"result":0,"value":1,"msg":"GPIO电平控制成功"}]
```

| 字段 | 说明 |
|------|------|
| `field_meaning` | 本条结果对应下发的消息 tag |
| `result` | 错误码：`0` 成功；`1` 参数错误；`2` 未知消息tag；`3` 字段存在但未注册处理器；`4` 执行出错 |
| `value` | 执行后回读/回显的数值 |
| `msg` | 结果描述 |

> 字段非法（`field_meaning` 不存在于 `FIELD_MEANINGS`）、字段未注册处理器、执行异常都会逐条回传明确错误码，避免云端长时间等待；若整个 `value` 不是合法 JSON 数组（如单字符 `"1"`），视为误下发，**仅记录日志、不执行、不回传**。模组侧不校验上下行属性，因此不会因字段为"纯上行"而拒绝处理。

### 4. 命令分发机制

`excloud_cmd.lua` 采用**字段路由表（field_meaning → 处理函数）**实现：

```lua
local field_handlers = {
    [excloud.FIELD_MEANINGS.GPIO_LEVEL]   = function(value, data_type) ... end,
    [excloud.FIELD_MEANINGS.SET_VOLTAGE]  = function(value, data_type) ... end,
    [excloud.FIELD_MEANINGS.WORK_STATUS]  = function(value, data_type) ... end,
    ...
}
```

新增"可被平台下发控制"的字段只需：① 确认其在 `excloud.FIELD_MEANINGS` 中已定义；② 在 `field_handlers` 中注册一个处理函数即可。真实的"哪些字段可下发"由平台端按上下行属性决定，模组侧无需关心。

---

## 五、数据上报

`excloud_report.lua` 提供：

- `send_one(field_meaning, data_type, value)`：单条 TLV 上报
- `send_multi(tlvs)`：批量 TLV 上报
- `trigger_report(type)`：一次性触发上报（`environment` / `status` / `all`）
- 周期上报任务：鉴权成功后每隔 `report_cycle` 秒自动上报

示例 TLV（含多种类型）：

| 字段 | 类型 | 示例值 |
|------|------|--------|
| `TEMPERATURE` | `FLOAT` | 26.5 |
| `HUMIDITY` | `FLOAT` | 60.0 |
| `SIGNAL_STRENGTH_4G` | `INTEGER` | 23 |
| `BATTERY_LEVEL` | `INTEGER` | 3700 |
| `WORK_STATUS` | `INTEGER` | 1 |
| `DEVICE_ID` | `ASCII` | "860000000000001" |

> 本示例中的传感器数据均为**模拟值**，真实项目请替换为实际采集数据。

---

## 六、文件上传

`excloud_upload.lua` 提供：

| 接口 | 说明 |
|------|------|
| `upload_demo_image()` | 上传演示图片（在 `/luadb/` 生成模拟文件后上传） |
| `upload_demo_audio()` | 上传演示音频 |
| `write_mtn_log(tag, ...)` | 写入一条运维日志（委托 `excloud.mtn_log`） |
| `trigger_upload_mtnlog()` | 主动触发一次运维日志上传（`excloud.upload_mtnlogs`） |

### 真实图片 / 音频自动上传（开机鉴权后自动执行一次）

工程内置两个**真实文件自动上传任务**（无需平台下发即可自测完整上传链路），设备开机鉴权成功后**并行**触发各一次：

| 任务 | 上传文件 | 目标类型 |
|------|----------|----------|
| `upload_real_image_task` | `/luadb/test.jpg` | 图片 |
| `upload_real_audio_task` | `/luadb/test.mp3` | 音频 |

**放置测试文件（用户可自行替换）：**

1. 准备真实图片/音频，分别命名为 `test.jpg`、`test.mp3`（音频也支持 wav 等格式）；
2. 将两个文件放入**编译目录**（与 `main.lua` 同级）；
3. 重新编译烧录，文件即位于设备 `/luadb/test.jpg`、`/luadb/test.mp3`，任务会在鉴权成功后自动上传。

**上传其他图片/音频：** 修改 `excloud_upload.lua` 末尾的两个常量即可（`*_PATH` 为设备内路径，`*_NAME` 为平台侧显示文件名）：

```lua
local REAL_IMAGE_PATH = "/luadb/test.jpg"   -- 设备内图片路径（随工程编译进 /luadb/）
local REAL_IMAGE_NAME = "test.jpg"          -- 平台侧显示的文件名
local REAL_AUDIO_PATH = "/luadb/test.mp3"   -- 设备内音频路径（随工程编译进 /luadb/）
local REAL_AUDIO_NAME = "test.mp3"          -- 平台侧显示的文件名
```

**不想自动上传：** 删除 `excloud_upload.lua` 末尾对应的 `sys.taskInit(upload_real_image_task)` / `sys.taskInit(upload_real_audio_task)` 一行即可。

**上传结果确认：** 由文件开头注册的 `excloud.set_upload_callback` 回调统一打印，串口可见 `[文件上传] 成功/失败 类型: 图片/音频 文件: xxx`；平台侧登录 iot.luatos.com → AirCloud 文件页面可查看上传结果。

### 上传回调（两类，勿混淆）

1. **单文件上传结果回调**（`excloud.set_upload_callback`）：
   ```lua
   function cb(file_type, file_name, result_ok, result_msg)
       -- file_type: 1=图片 2=音频 3=运维日志
   end
   ```

2. **批量运维日志上传事件**（`excloud.on` 全局回调）：
   - `mtn_log_upload_start`：开始上传（`data.file_count`）
   - `mtn_log_upload_progress`：上传进度（`data.current_file`/`data.total_files`/`data.file_name`/`data.status`）
   - `mtn_log_upload_complete`：上传完成（`data.success_count`/`data.failed_count`/`data.total_files`）

> 云端下发运维日志上传信令（字段 25）时，`excloud` 库内部会自动响应并启动上传；业务侧无需重复上传。

---

## 七、编译运行步骤

### 1. 准备 LuatOS 开发环境

- 下载并安装 LuatOS 官方开发环境（IDE / 命令行编译工具链），支持 Air780EPM 模组。
- 参考 LuatOS 官方文档完成环境搭建。

### 2. 放置文件

- 将本 `air780epm/` 目录下的 `main.lua`、`config.lua`、`excloud_main.lua`、`excloud_cmd.lua`、`excloud_report.lua`、`excloud_upload.lua` 作为**应用脚本**。
- 将 `excloud.lua` 扩展库放到 LuatOS 的库搜索路径中（通常为工程的 `lib/` 或 `script/libs/` 目录），确保 `require("excloud")` 可被解析。
- `main.lua` 应位于脚本根目录。
- 如需测试**真实图片/音频自动上传**，将 `test.jpg` / `test.mp3` 一并放入编译目录（与 `main.lua` 同级，编译后位于设备 `/luadb/`）；详见「六、文件上传」。

### 3. 配置

- 编辑 `config.lua`：
  - 选择 `transport`（`tcp` / `udp` / `mqtt`）
  - 如需手动指定服务器，关闭 `use_getip` 并填写 `host` / `port`
  - UDP 填 `udp_auth_key`，MQTT 填相应协议参数

### 4. 编译烧录

- 使用 LuatOS 编译工具将脚本与库打包成固件，烧录到 Air780EPM。
- 编译时以 `air780epm` 所在目录为脚本根。

### 5. 运行验证

- 通过串口观察日志：连接成功 → 鉴权成功 → 心跳 → 周期上报。
- 在云平台侧下发控制命令，观察 `excloud_cmd` 的解析与执行日志。
- 用串口/模拟器测试运维日志上传，观察 `mtn_log_upload_*` 事件。

### 6. PC 模拟器调试（可选）

- 设置 `force_virtual_device = true`，填写 `virtual_phone_number` / `virtual_serial_num`。
- 在 LuatOS PC 模拟器中运行，以虚拟设备身份接入云平台。

---

## 八、注意事项

1. **内置库无需 require**：`log`/`sys`/`mcu`/`socket`/`json`/`io` 为 LuatOS 内置库，默认全局可用，直接调用即可；仅 `excloud` 需 `require`。
2. **控制命令为模拟动作**：本示例中的命令执行（如 LED 控制、重启）均为模拟，仅打印日志并修改内部状态，便于在模拟器 / 无硬件环境验证逻辑。
3. **运维日志写入方式**：`MTN_LOG_CACHE_WRITE`（缓存写）在日志量小时可能不落盘，上传会出现文件大小为 0；测试上传时建议 `mtn_log_write_way = MTN_LOG_ADD_WRITE`（直接追加写），避免缓存未落盘导致文件大小为 0。
4. **传感器数据为模拟值**：请替换为真实采集数据。
