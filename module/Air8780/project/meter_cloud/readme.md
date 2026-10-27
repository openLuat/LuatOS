# meter_cloud — 三相电表采集 + AirCloud 上报 demo

设备：Air780EPM 方案（板载 RS485，串口2），
Modbus-RTU 轮询三相电表，把电压/电流/功率/电能等数据
按合宙 IOT 通用报文协议（AirCloud）上报云端，Web 端查看实时/历史数据并可下发命令。

## 目录结构

```
meter_cloud/
├── main.lua                 入口：PROJECT / PROJECT_KEY / sys.run()
├── app/
│   ├── app_main.lua         模块加载编排（网络 → 采集 → 上报）
│   ├── meter/meter_app.lua  RS485 Modbus-RTU 电表采集（串口2）+ 板级初始化
│   └── aircloud/aircloud_app.lua  AirCloud TLV 组包上报 + 下行命令
├── drv/                     网络适配（netdrv_device / netdrv_4g / netdrv_pc）
└── web/
    ├── login.html           Web 登录页
    └── index.html           电表数据查看页（实时/历史/命令）
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
| ADC2 / ADC0 / ADC1 | 10s 采样 | 供电电压（≤36V）、模拟量1电压、模拟量2电流 |

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
     一般无需改动；`debug = true` 会打印每帧收发原始报文与每块寄存器值，定位后建议关掉。
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
| 1312 | 供电电压（ADC2 采集） | FLOAT | V |
| 1313 | 越限报警位图（bit0 电压/bit1 电流/bit2 功率/bit3 频率） | INTEGER | - |
| 1314 | 越限报警描述（如 `OV,OC`） | ASCII | - |
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
