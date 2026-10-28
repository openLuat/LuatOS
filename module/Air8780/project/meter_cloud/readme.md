# meter_cloud — 三相电表采集 + AirCloud 上报 demo

设备：Air780EPM 方案（板载 RS485，串口2），
Modbus-RTU 轮询三相电表，把电压/电流/功率/电能等数据
按合宙 IOT 通用报文协议（AirCloud）上报云端，Web 端查看实时/历史数据并可下发命令。

## 目录结构

```
meter_cloud/
├── main.lua                 入口：PROJECT / PROJECT_KEY / sys.run()
├── app/
│   ├── app_main.lua         模块加载编排（板级 → 网络 → 采集 → 控制 → 上报）
│   ├── board_hw.lua         板级资源（3.3V 电平/485 供电/LED/按键/看门狗/ADC）
│   ├── meter/meter_app.lua  RS485 Modbus-RTU 电表采集（串口2）+ 485 总线互斥
│   ├── ctrl_app.lua         开关控制（0x05/0x0F 继电器 + 0x02 DI）+ 本地操作限制
│   ├── alarm_app.lua        越限报警（阈值远程配置、掉电保存）
│   └── aircloud/aircloud_app.lua  AirCloud TLV 组包上报 + 下行命令
├── drv/                     网络适配（netdrv_device / netdrv_4g / netdrv_pc）
└── web/
    ├── login.html           Web 登录页
    ├── index.html           控制台（开关控制 / 实时数据 / 历史 / 报警 / 命令）
    └── README.md            控制台操作说明（面向操作人员）
```

## 接线与板级初始化

| 设备 | 连接 | 说明 |
|------|------|------|
| RS485-A / RS485-B | 电表 485 端子 A / B | 注意 A 对 A、B 对 B |

板级初始化统一由 `app/board_hw.lua` 的 `board_hw.init()` 完成（`app_main` 最先调用）：

| 资源 | 处理 | 说明 |
|------|------|------|
| `pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)` | 自动调用 | 所有 GPIO 高电平输出 3.3V，必须先于 UART/GPIO 初始化 |
| GPIO25 485 芯片可控电源 | 上电拉高 | 不拉高 485 芯片不上电，通信必失败 |
| GPIO23 RS485 EN / 方向脚 | 交 `uart.setup` 硬件换向 | 收发器 DE+RE；手动拉高会把总线钉在发送态、收不到应答 |
| GPIO22 运放电源 | 默认关 | 做模拟量检测时调 `board_hw.opamp_power(true)` |
| GPIO24 可控电源输出 | 默认关 | `board_hw.power_out(true)` 打开 |
| GPIO27 NET LED | 采集中常亮/超时闪烁 | 由 `METER_STATUS` 驱动 |
| GPIO30 Reload 键 | 输入上拉 | 短按/长按（3s）分别发 `RELOAD_KEY_SHORT/LONG`，长按时重启 |
| GPIO28 硬件看门狗 | 直接调扩展库 | `require "exair153x_wdt"` → `init{ wdt_pin = 28, auto_feed_period_s = 150 }`，自动喂狗由库内部任务完成；芯片默认没贴，引脚动作无副作用 |
| ADC2 / ADC0 / ADC1 | 10s 采样 | 主控供电电压（≤36V，**仅本地采样，不上报**）、模拟量1电压、模拟量2电流 |

- 串口2 为硬件自动换向 RS485，**无需方向脚**（`CFG.dir_gpio` 保持 `nil`）；
- 外接带方向脚的 485 模块时，在 `CFG.dir_gpio` 填 GPIO 号。

## 参数配置

1. **PROJECT_KEY**：在 iot.openluat.com 创建项目获取密钥，填入 `main.lua` 的 `PROJECT_KEY`（当前为占位值，必须替换）。
2. **电表参数**：`app/meter/meter_app.lua` 顶部 `CFG`：
   - `slave_id = 1` — 电表 Modbus 从站地址（对齐电表面板设置）；
   - `baud = 9600`、`parity = uart.None`、8N1 — 对齐电表 485 通讯参数；
   - `poll_interval = 2000` — 采集周期 ms；
   - `dir_gpio = 23` — RS485 方向脚（接 DE+RE），交给 `uart.setup` 自动换向；填 nil 会导致发送时 DE 不抬高、收不到回包；
   - 485 芯片电源 / RS485 EN 已移入 `app/board_hw.lua` 的 `PIN` 表（GPIO25 / GPIO23），
     一般无需改动；
   - `debug` **默认关闭**。需要抓报文时远程下发：
     `{"type":"debug","val":1}`（文本 `debug:on`）打开，`val:0`（`debug:off`）关闭；
     Web「控制命令」卡片有「开启/关闭」按钮。开启后设备打印每帧 TX/RX 原始十六进制与每块寄存器值。
     说明：`exmodbus` 自带 debug 在 create 时被捕获、运行期无法切换，所以这里用自有开关。
3. **上报周期**：`app/aircloud/aircloud_app.lua` 中 `report_cycle = 60`（秒），也可 Web 端远程修改（5~86400s）。

## 上报字段（TLV）

| tag | 含义 | 类型 | 单位 |
|-----|------|------|------|
| 1300-1302 | Ua/Ub/Uc 三相电压 | FLOAT | V |
| 1303-1305 | Ia/Ib/Ic 三相电流 | FLOAT | A |
| 1306-1308 | P/Q/S 有功/无功/视在功率 | FLOAT | kW/kvar/kVA |
| 1309 | PF 功率因数 | FLOAT | - |
| 1310 | F 频率 | FLOAT | Hz |
| 1311 | EP 正向有功电能 | FLOAT | kWh |
| 1313 | 越限报警位图（bit0 电压/bit1 电流/bit2 功率/bit3 频率） | INTEGER | - |
| 1314 | 越限报警描述（如 `OV,OC`） | ASCII | - |
| 1320 / 1321 | DI1 总开关反馈（1=合闸 0=断开）/ DI2 未使用恒 0 | INTEGER | - |
| 1322 | 平台目标位图（bit0 总开关合闸） | INTEGER | - |
| 1323 | 限制位图（bit0 总限制 / bit1 单路限制） | INTEGER | - |
| 1324 | 故障位图（bit0 开关拒动，bit2 通信异常） | INTEGER | - |
| 1325 | 继电器输出位图（bit0=合闸继电器 DO1A/B，bit1=断开继电器 DO2A/B） | INTEGER | - |
| 1326 | DI 原始位图（bit0..3 = 电表开入量 0~3，排查 DI 映射/接线） | INTEGER | - |
| 782 | 4G 信号 | INTEGER | - |
| 1280 | 时间戳 | INTEGER | s |
| 1293 / 1294 | 设备ID / 项目名 | ASCII | - |
| 19 / 20 | 控制命令 / 命令应答 | ASCII | - |

## 越限报警（`app/alarm_app.lua`）

纯软件实现，不依赖电表 DO/AO（说明书地址表无对应寄存器）。网关订阅 `METER_DATA` 判断越限，
阈值可通过 tag19 远程配置并写入 fskv 掉电保存：

```json
{"type":"alarm","enable":1,"hi_u":250,"lo_u":180,"hi_i":10,"hi_p":50,"hi_f":50.5,"lo_f":49.5,"hys":2}
{"type":"alarm_get"}
```

- 阈值填 `0` 表示不判该项；`hys` 为回差，触发后需回到 门限∓hys 才解除，防止抖动；
- 报警位图随每轮上报走 tag1313，描述走 tag1314（`OV` 电压 / `OC` 电流 / `OP` 功率 / `OF` 频率）；
- 文本命令 `alarm:on`、`alarm:off` 可快速启停。

## 开关控制（`app/ctrl_app.lua`）

用说明书 5.2 的线圈指令操作电表继电器（需继电器处于**遥控模式**，面板 `DO-i` 里不要设成报警项目）：

本板只有 **2 路继电器**，只做 **1 个总开关**（只有“合闸 / 断开”，无保护跳闸语义）：

| 硬件 | 作用 | 电表接口 |
|---|---|---|
| 继电器1（DO1A + DO1B 是其两端子） | 总开关**合闸** | 0x05 写线圈 0 |
| 继电器2（DO2A + DO2B 是其两端子） | 总开关**断开** | 0x05 写线圈 1 |
| DI1 | 总开关反馈（1=合闸，0=断开） | 0x02 读开入量 bit0 |
| DI2 | 未使用（恒 0） | — |
| 继电器状态 | 回读输出 | 0x01 读线圈 0x0000+4 |

- 合闸/跳闸动作均为 **2 秒脉冲**（写 1 → 等 2s → 写 0），避免继电器长吸合；
- 动作后等待 1.2s 读 DI 回校验，不到位记故障位并上报 `CTRL_FAULT`；
- 采集与控制共用一条 485，通过 `meter_app.bus_lock()` 串行化，不会互相打断帧；

**本地操作限制**：
- 总限制（`lock_all`）生效时，单路限制被清除并忽略；
- 生效限制下：平台目标=跳闸 而 DI=1（本地手动合闸）→ 自动给对应 DO_B 打 2s 脉冲跳闸，
  1.2s 后复查 DI，仍为 1 记 `fault` 并上报，5s 后重试，最多 3 次后只上报不再动作；
- 生效限制下：平台目标=合闸 而 DI=0 → 只上报，**不自动重合闸**（安全考虑）；
- Web 指令不受限制影响，限制只约束现场本地操作；
- **合闸与解除等效**：平台下发「合闸」时会同步解除该路单路限制（`CFG.auto_unlock_on_close`），
  总限制开启时不受影响，需先解除总限制。

**变化触发上报**：`aircloud_app` 订阅 `CTRL_STATE`，DI/目标/限制/故障 任一项变化才
`publish("REPORT_NOW")` 立即上报一次（3s 节流）；状态无变化不额外上报。

**Web 展示**：单张「总开关 · DO1」卡片 + 刀闸图示（DI=1 红色合闸 / DI=0 深灰断开）；
下方功能区「限制本地合闸」含状态徽标 + **「限制」/「解除」两个按钮**。

限制状态规则：

| 触发 | 限制状态 | 说明 |
|---|---|---|
| 平台**断开** | 自动开启（日志 `AUTOLOCK`） | 现场强行合闸 → 自动断开并上报 |
| 平台**合闸** | **不变** | 只合闸，不解除限制（避免"一合闸就顺带解除"） |
| 点「解除」 | 解除 | 独立操作，**不改变开关状态** |
| 点「限制」 | 开启 | 用于现场检修时临时上锁 |

限制生效时的**双向纠偏 + 监守模式**：

- DI 与平台目标不一致 → 输出 2s 脉冲强制纠正（日志 `CORRECT`）；
- 纠正后仍不一致 → 进入**监守模式**（`GUARD ON`），此后**每 2s 再输出一次 2s 脉冲**，
  直到 DI 与目标一致（`GUARD OFF`），期间故障位 bit0 持续上报；
- 不限次数（旧版本最多 3 次的限制已移除）；
- 平台新指令或限制变化会重置监守状态。

**持久化**：目标状态与限制写入 fskv 键 `ctrl_state`，重启后继续生效
（`load_state()` 内已先 `fskv.init()`，修复重启后限制丢失的问题）。

配置项：`CFG.auto_lock_on_open = true`（断开自动加限）、
`CFG.auto_unlock_on_close = false`（合闸不自动解除，改成 true 可恢复自动解除）。

命令：

```json
{"type":"sw","ch":1,"act":1}     // ch 0=全部 1/2=单路；act 1=合闸 0=跳闸
{"type":"sw_get"}
{"type":"lock","all":1}          // 总限制
{"type":"lock","ch":1,"val":1}   // 单路限制（总限制开启时无效）
```

文本：`sw:on`、`sw:off`、`sw1:on`、`sw2:off`、`lock:on`、`lock:off`。

### 控制日志

设备端维护最近 40 条控制事件（环形缓冲，fskv 掉电保存），
记录：平台合闸/跳闸指令与结果、限制开关、本地合闸被拦截、强制跳闸成功/失败。

> 日志正文**只用 ASCII**（`CMD DO1 CLOSE`、`DO1 CLOSE OK`、`BLOCK DO1 TRY1`、
> `DO1 FORCE FAIL DI=0`、`LOCK ALL ON`、`AUTOUNLOCK DO1`），因为 AirCloud 的 ASCII
> 字段装不下中文，直传会变成 `������`；Web 端 `trLog()` 负责翻译成中文再展示。

Web「控制日志」卡片点「刷新日志」读取，每次操作后自动刷新。

```json
{"type":"log_get","n":40}   // 返回 JSON 数组：[{"t":时间戳,"s":"开关1 合闸 完成"}, ...]
```
文本命令：`log` 或 `log:20`。

> 注意：目标状态与限制写入 fskv 掉电保存。**开机时若总限制为开且目标为跳闸**，
> 而现场开关处于合闸，设备会按限制策略自动跳闸——启用限制前建议先下发目标状态。
> **继电器输出必须通过 0x05/0x0F 控制**，说明书未提供“遥控模式”的寄存器开关，
> 若面板 `DO-i` 被设成报警项目，继电器会由电表自身报警逻辑驱动，遥控可能无效。

> FLOAT 为 ×1000 无符号定点编码（协议约定），负值（如发电反送 Q）钳到 0 上报；
> 云端按类型解码后 Web 端直接显示工程值。

## 下行命令（Web → 设备，tag 19）

| 命令 | 说明 | 应答（tag 20） |
|------|------|----------------|
| `report:now` | 立即上报一次 | `report:now` |
| `cycle:N` | 修改上报周期 N 秒（5~86400） | `cycle:N` |
| `{"type":"cycle","value":N}` | JSON 写法，同上 | `{"code":0,...}` |
| `{"type":"report","value":1}` | JSON 写法，立即上报 | `{"code":0,...}` |

## Web 端使用

1. 把 `web/login.html` 和 `web/index.html` 部署到 AirCloud 应用（device.luatos.com 应用空间，与 factory 相同方式）。
2. 打开页面 → 右上角「登录」→ 合宙账号授权。
3. 选择**项目**（PROJECT_KEY 对应项目）与**设备**，即可查看：
   - **实时数据**：12 张卡片 + 在线状态（最近上报 ≤3min 显示在线）；
   - **历史数据**：日期范围查询、电压/电流/功率趋势图、历史表格、「加载更多」分页；
   - **控制命令**：`report:now` 立即上报、`cycle:N` 设置上报周期，tag20 显示设备应答。

> 接口限频红线：同设备 ≥3s、跨设备 ≥150ms（页面内 `pacedApi` 已统一节流，勿绕过）。

## 验证要点

1. 烧录后日志出现 `AirCloud 已开启`，随后周期性打印 `数据上报成功`；
2. 电表掉线时日志打印 `电表离线，本次仅上报心跳基础字段`，Web 端仅刷新时间戳/信号；
3. Web 端点击 `report:now`，设备日志打印 `下行命令: report:now`，页面 1.5s 后显示应答；
4. Web 端数值与电表面板对照：电压 ±1V、电流 ±0.01A、电能 ±0.01kWh 为正常（受 CT/PT 与寄存器口径影响）。
