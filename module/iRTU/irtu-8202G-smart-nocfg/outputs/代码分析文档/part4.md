
# 6. 函数调用 / 事件订阅 / 数据表逻辑关系

## 6.1 运行时协程全景（sys.taskInit 常驻任务）

LuatOS 是"协程 + 事件驱动"模型：`sys.taskInit(func)` 生成一个独立协程，协程内部通过 `sys.wait/sys.waitUntil` 挂起等待事件。本工程运行期的常驻协程如下（按启动顺序）：

| 协程 | 创建处 | 职责 | 生命周期 |
|---|---|---|---|
| start_app | main.lua L106 | 开机主流程：加载配置→云连接→app→boot_lbs_report | 执行完即退 |
| cfg_fetch 后台配置任务 | cfg_fetch.lua L58 | HTTP 拉远端配置（当前 main.lua 已禁用入口） | 执行完即退 |
| app_task | app.lua L124 | 读唤醒原因、初始化全部模块、require active_mode | 执行完即退 |
| connect → 通道 task | create.lua L458/L416 | 按激活通道 taskInitEx 启动 tcpTask/mqttTask/aircloudTask（**常驻**） | 断线自愈循环，永不退 |
| aircloudTask | create.lua L427 | AirCloud 心跳保活 + 双订阅转发（AIRCLOUD_SEND_/NET_SENT_RDY_） | 常驻 |
| main_loop | active_mode.lua L585（模块加载即启动） | **核心状态机**：GNSS 开关评估 + 上报节流 + 数据采集上报 | 常驻 |
| battery_monitor_task | active_mode.lua L495 | 每 60s 低电量检测，<20% 发 BATTERY_LOW | 常驻 |
| do_lbs_report | boot_lbs_report.lua L141 | 开机一次性 LBS 双通道上报 | 执行完即退 |
| battery_poll_task | battery.lua L136 | 每 30s 轮询 YHM2712A，刷新电池缓存 + 充电事件 | 常驻 |
| charge setup task | charge.lua L22 | YHM2712A setup + start | 执行完即退 |
| xyz_capture_task | gsensor.lua L182 | 订阅 GSENSOR_XYZ_CAPTURE，读 I2C 存三轴快照 | 随 close 退出 |
| stream_task | gsensor.lua L188 | 20Hz 三轴流采样（stream_on 门控） | 常驻 |
| nmea_stream_task | location.lua L39 | 1Hz NMEA 五元组采样（on 门控） | 常驻 |
| execute_command 协程 | remote.lua L203 | 每个下行命令一个一次性协程（处理函数内可 sys.wait） | 执行完即退 |
| lowpower 驱动任务 | drv_normal/lowpower/psm L35/L99/L95 | 各功耗档配置（每次切换 taskInit） | 执行完即退 |
| 看门狗喂狗循环 | lib/exair153x_wdt L235 | Air153C 自动喂狗 | 常驻 |

> 关键技巧：active_mode 主循环阻塞在上报/等网络期间，gsensor/location 的**采样协程独立运行不中断**——这保证 1293/1294 的 10 秒窗口内采样连续（代码注释明确说明这一设计）。

## 6.2 全局事件总线：订阅/发布关系总表

事件名（业务侧；库内部事件用"—"标注）：

| 事件 | 发布方（时机） | 订阅方（作用） |
|---|---|---|
| `MOTION_EVENT` | ① gsensor 震动回调（active_mode 注册，2s 限流后）；② FORCE_REPORT 订阅回调（顺带唤醒）；③ drv_lowpower WAKEUP2 唤醒 | ① main_loop `waitUntil(MOTION_EVENT, 剩余ms)`（提前醒评估 GNSS）；② main_loop 常驻订阅置 motion_event_flag（兜底阻塞期丢失） |
| `FAST_REPORT_START` | remote.fast_report（云命令） | active_mode 订阅：进实时上报态（开 GNSS、置 60s 倒计时、续期） |
| `FORCE_REPORT` | remote.get_device_data（云命令） | active_mode 订阅：置 force_report_pending → 步骤 3.1 清零节流立即上报一帧 |
| `REMOTE_COMMAND` | create 三通道收包（TCP 原样 / MQTT payload / AirCloud 逐 TLV） | ① remote.handle_command（命令分发）；② tools 订阅（刷新 last_rx_time，LED 通信正常证据） |
| `CLOUD_CONNECTED` | create 各通道 task 连接成功（tcp/mqtt/aircloud） | active_mode main_loop `waitUntil(...,30000)` 后做 startup 上报；boot_lbs_report `waitUntil(...,60000)` |
| `IP_READY` | 系统网络注册成功 | 各 task 等待联网；create 模块级订阅打日志 |
| `IP_LOSE` | 系统网络掉线 | create 模块级订阅打日志 |
| `BATTERY_LOW` | active_mode.battery_monitor_task（<20%） | lowpower_app.handle_low_battery（低电量降级） |
| `CHARGING_START/STOP` | battery 轮询任务（YHM2712A 充电器插拔变化） | tools 订阅：更新 vbus_state + 刷 LED |
| `DRV_SET_NORMAL` | lowpower.set_mode(normal) | drv_normal（pm.power WORK_MODE 0） |
| `DRV_SET_LOWPOWER` | lowpower.set_mode(power_save) | drv_lowpower（中断唤醒 + 关 GPS + WORK_MODE 1） |
| `DRV_SET_PSM` | lowpower.set_mode(psm_sleep) | drv_psm（WORK_MODE 3） |
| `NET_SENT_RDY_1` | create.send(JSON 串) | 默认：aircloudTask 订阅→封装 RANDOM_DATA TLV；若启用 MQTT/TCP 通道则由对应 task 原样上送（两路并存） |
| `AIRCLOUD_SEND_1` | create.send_aircloud(TLV 数组) | aircloudTask 订阅→excloud.send 直发 |
| `GSENSOR_XYZ_CAPTURE` | gsensor 中断回调（限流后） | xyz_capture_task `waitUntil`（协程读 I2C 存快照） |
| `GNSS_STATE` | exgnss（OPEN/CLOSE/FIXED/LOSE 等） | location.gnss_state_callback（FIXED→写 last_gps_data 缓存）；exgnss 内部多处 |
| `BOOT_LBS_REPORT_DONE` | boot_lbs_report（完成后） | 可选监听（当前无订阅方） |
| `CFG_FETCH_READY` | cfg_fetch（配置拉取完成） | 可选（当前无订阅方） |
| `FOTA_CHECK_DONE` | update/libfota2 回调 | 可选 |
| — `mqtt_conack<cid>` | mqttTask mqtt.on conack | mqttTask 等待连接成功 |
| — `YHM27XX_REG` | exs_yhm2712a 单线通信响应 | 充电 IC 驱动内部 |
| — `NTP_UPDATE` | exgnss（GNSS 校时成功） | location/airlbs/libfota3 等等待时间同步 |
| — `WLAN_SCAN_DONE` | wlan 扫描完成 | location（付费 AirLBS WiFi 辅助） |
| — `CELL_INFO_UPDATE` / `LBS_*` / `SIM_IND` | 各库内部 | 库内部 |

### 事件流图（简化版）

![事件订阅关系图](./images/fig5_event_bus.png)

## 6.3 主要函数调用链

### 6.3.1 开机装配链（main → app）

```
main.lua(模块加载)
 ├─ fskv.init() → mobile.simid(1) → update.init()(FOTA)
 └─ BOOT_MODE=2 → sys.taskInit(start_app)
       └─ start_app
            ├─ cfg_fetch.init()            → db.new("/luadb/air8201.cfg"):export() → sheet
            ├─ has_valid_gnss(sheet) ? 
            │    ├─ 是 → config.load_from_server(sheet.gnss) → remote.init() → create.start(sheet)
            │    └─ 否 → create.start({gnss={network=config.DEFAULT_NETWORK}})
            ├─ app.start() (延迟2s)
            │     └─ app_task
            │          ├─ pm.lastReson() 唤醒原因解析
            │          └─ init_all_modules():
            │               kvstore.init → battery.init(轮询任务)
            │               → location.init(exgnss.setup + GNSS_STATE订阅 + nmea_stream_task + wlan.init)
            │               → gsensor.init(exvib.open + WAKEUP2中断 + 两采样任务)
            │               → charge.init(YHM setup task)
            │               → air153c_wdt.init(喂狗循环)
            │               → remote.init(订阅 REMOTE_COMMAND)
            │               → lowpower_app.init(订阅 BATTERY_LOW；require drv_* 三驱动)
            │          └─ work_mode==-1 → 强制 set_work_mode(2)
            │          └─ require("active_mode")   ← 模块加载即 taskInit(main_loop)
            └─ boot_lbs_report.start() → taskInit(do_lbs_report)
```

### 6.3.2 上报数据组装链（每帧执行一次）

```
main_loop（节流到点 / FORCE_REPORT / MOTION_EVENT 提前醒）
 └─ collect_data_and_report()
      ├─ pm.power(WORK_MODE,0)                     # 临时全功率
      ├─ 等 IP_READY ≤30s（socket.adapter 轮询 + waitUntil）
      ├─ battery.force_check() → {voltage,level,charging,...}  # 读缓存（非阻塞）
      ├─ location.get_report_location(gnss_active) → {gps,gps_status}   # GNSS 优先锁定（见 6.4.3）
      ├─ mobile.csq()/iccid()/scell() → 信号/ICCID/EARFCN
      ├─ gsensor.read_xyz() → "x,y,z" 字符串
      ├─ [GNSS开&非实时] gsensor.get_stream_data(200) → 1293 载荷
      ├─ exgnss.gsv() → top4_cn/sat_total/sat_visible
      ├─ [GNSS开&非实时] location.get_nmea_stream(ref) → 1294 载荷
      ├─ build_msg("property_report") → json.encode → create.send(payload)
      │     └─ publish NET_SENT_RDY_1 → aircloudTask → RANDOM_DATA(1281) → excloud.send
      └─ create.send_aircloud(build_aircloud_tlv(...))
            └─ publish AIRCLOUD_SEND_1 → aircloudTask → excloud.send(tlvs)
                  └─ build_tlv 逐个 → build_header → socket.tx / mqtt publish
```

### 6.3.3 下行命令链（REMOTE_COMMAND 消费顺序）

```
服务器 → excloud.parse_data
   ├─ 17/18/25 字段 → excloud 内部处理（鉴权/日志上传），不转发
   └─ 其余 → callback("message") → create.on 回调 → 逐 TLV publish REMOTE_COMMAND
        ├─ tools（模块加载即订阅，先于 remote.init？不——tools 由 active_mode require 链加载，remote 由 app 初始化）
        │    └─ led_server_rx(): last_rx_time=now（LED 常亮证据）
        └─ remote.handle_command（remote.init 订阅）
             └─ execute_command(raw)：sys.taskInit 协程内
                  ├─ pcall(json.decode) 失败→忽略
                  ├─ command_handlers[cmd] 命中 → handler(parsed, parsed)
                  └─ 未命中 → send_reply(result=1,"未知命令")
```

### 6.3.4 功耗切换链

```
active_mode（GNSS 状态切换/上报完成）
 └─ lowpower.set_mode(POWER_SAVE/NORMAL)
      ├─ 校验 mode ∈ config.POWER_MODE
      ├─ publish DRV_SET_LOWPOWER / DRV_SET_NORMAL / DRV_SET_PSM
      └─ drv_lowpower 订阅回调 → taskInit(lowpower_task)
           ├─ set_lowpower_interrupt_wakeup()   # PWR_KEY + WAKEUP2 中断唤醒
           ├─ location.close()                  # 关 GPS（减少功耗）
           ├─ pm.power(pm.WORK_MODE, 1)         # 真正切低功耗
           └─ gsensor._restore_interrupt()      # 唤醒后恢复 DA221 中断
```

## 6.4 数据表 / 状态表及其逻辑关系

### 6.4.1 fskv 键值表（kvstore 封装，掉电不丢）

| 键 | 初值 | 写入方 | 读取方 | 用途 |
|---|---|---|---|---|
| `initialized` | "true"（首启写） | kvstore.init | kvstore.init | 首启标记 |
| `work_mode` | "2" | kvstore.init / remote.change_mode / app.lua(-1修正) | app / active_mode / boot_lbs_report / lowpower_app / remote | 设备工作模式 |
| `low_power_mode` | "false" | active_mode（低电检测） | lowpower_app（set_mode_by_device_mode 等） | 低电量状态 |
| `audio_volume` | "80" | remote.set_volume | remote（预留） | 音量（无音频硬件） |
| `test_done` | — | 产测 | main.lua（BOOT_MODE=0 分支） | 产测完成标记 |
| `auth_fail_count`（约） | — | excloud（复位看门狗计数） | excloud | 当日鉴权失败复位次数 |

### 6.4.2 持久化配置文件 /luadb/air8201.cfg（db.lua 表序列化）

| 字段 | 内容 | 生产方 |
|---|---|---|
| `uconf` | true（有本地配置标记） | cfg_fetch（云端拉取后 import） |
| `param_ver` | 服务端参数版本号 | cfg_fetch |
| `project_key` | 云项目密钥 | cfg_fetch |
| `gnss` | `{network={conf,conf_on}, loc_strategy, battery, charge, wdt, alarm...}` | 服务端下发的定位版配置（parameter_gnss） |

读取链：`main.lua → cfg_fetch.init() → db:export() → sheet`；有有效 `gnss.network.conf` → `config.load_from_server(sheet.gnss)` 覆盖 config 默认值 → `create.start(sheet)` 按 `network.conf` + `conf_on` 启通道。

### 6.4.3 核心内存状态表（模块内缓存，只读接口导出）

| 状态表 | 位置 | 关键字段 | 维护方 → 消费方 |
|---|---|---|---|
| `location.location_state` | location.lua | `last_gps_data`（最近定位成功 RMC）、`last_gps_time`、`last_lbs_data/time`、`_gps_started`、`first_wifi_scan` | **GNSS 优先锁定**：FIXED 回调写 last_gps_data；`get_report_location` 读：非 nil → 恒走 GNSS（当前 fix 用当前值，否则用最近值，status 恒 2）；nil → LBS(4/5)/失败(3) |
| `nmea_stream` | location.lua | `on`、`buf`（≤10 样本 {lat,lng,speed,course,altitude}） | nmea_stream_start/stop；get_nmea_stream 消费（1294） |
| `battery.battery_state` | battery.lua | voltage/level/charging/charge_stage/charger_present/... | battery_poll_task 30s 刷新 → 业务只读缓存（**禁止同步调 IC**：status() 单次可阻塞 20s） |
| `gsensor.state` | gsensor.lua | initialized/is_moving/last_motion_time/motion_timeout/pending_gps/last_xyz/stream_on/stream_buffer(≤205 样本 6B 编码) | 中断回调写运动态；active_mode 读 get_status() 判 GNSS 需求 |
| `active_mode` 模块级变量 | active_mode.lua | gnss_active/last_report_time/fast_report_active/fast_report_deadline/fast_report_hold_until/force_report_pending/motion_event_flag/boot_ticks | main_loop 状态机自维护 |
| `lowpower.power_state` | lowpower_app.lua | `mode`（当前功耗档） | set_mode/set_mode_by_device_mode 维护 |
| `create.datalink` | create.lua | `datalink[cid]`（通道连接态） | 各通道 task 维护；`create.is_connected()` 读 |
| `tools.led` / `device_state` | tools.lua | boot_time/gnss_on_until/last_rx_time/manual_on/blink_phase、vbus_state | LED 状态机（500ms 定时器 + 事件触发刷新） |
| `kvstore` → fskv | 文件系统 | 见 6.4.1 | — |

### 6.4.4 GNSS 优先锁定策略（location.lua 核心决策表）

| 场景 | 判断 | 输出 gps / gps_status |
|---|---|---|
| 曾 GNSS 成功 + 当前 GNSS 开 + 实时 fix | `last_gps_data` 非 nil 且 exgnss.is_fix() 且 rmc valid | 当前坐标 / **2** |
| 曾 GNSS 成功 + 当前未 fix（掉星/GNSS 关） | last 非 nil | **最近一次成功坐标** / **2**（位置随报文"滞后"，换取一致性） |
| 从未成功（last 为 nil） | 免费模式(AIRLBS.MODE=0) → lbsLoc2 | LBS 坐标 / **4**；失败 / 3 |
| 从未成功 + 付费模式(MODE=1) | AirLBS（多基站+WiFi） | LBS 坐标 / **5**；失败 / 3 |

### 6.4.5 上报字段映射表（JSON 通道 ↔ TLV 通道）

一份 `msg.data` 同时驱动两条通道，映射关系如下（★=仅在特定运行态携带）：

| msg.data 键（active_mode 组装） | JSON 报文 | TLV 字段 | 编码 |
|---|---|---|---|
| work_mode | ✓ | **1290** 工作模式 | INTEGER 4B |
| vbat (mV) | ✓ | **799** VOLTAGE | INTEGER 4B |
| bat_change (0/1) | ✓ | **1291** 充电状态 | INTEGER 4B |
| signal (CSQ) | ✓ | **782** SIGNAL_STRENGTH_4G | INTEGER 4B |
| gps "lat,lng" | ✓ | **513** GNSS_LATITUDE + **512** GNSS_LONGITUDE（拆分） | ASCII |
| gps_status | ✓ | **519** LOCATION_METHOD（tostring） | ASCII |
| band "LTE B3" | ✓ | **772** SERVING_CELL | ASCII |
| gsensor_xyz | ✓ | **1292** 单点三轴 ★GNSS关/实时上报 | ASCII |
| gsensor_stream（二进制） | ✗ 不进 JSON | **1293** 20Hz 流 ★GNSS开且非实时 | BINARY |
| nmea_stream（二进制） | ✗ 不进 JSON | **1294** 1Hz 五元组流 ★GNSS开且非实时 | BINARY |
| chip_model | ✓ | **774** COMPONENT_MODEL | ASCII |
| boot_reason | ✓ | **776** BOOT_REASON | ASCII |
| wake_interval (1/10/300) | ✓ | **779** WAKE_INTERVAL | INTEGER 4B |
| iccid | ✓ | **783** SIM_ICCID | ASCII |
| top4_cn | ✓ | **515** GNSS_CN ★gps_status==2 | ASCII |
| sat_total / sat_visible | ✓ | **516** SATELLITES_TOTAL / **517** SATELLITES_VISIBLE ★gps_status==2 | INTEGER |
| position_active_report | ✓ | ✗ 无 TLV 映射 | — |
| msg_id/imei/ts/type（框架字段） | ✓ | ✗（TLV 通道靠消息头 seq + 字段语义识别；512/513 同时作 1294 差值基准） | — |

---

# 7. 本工程 TLV 字段详细格式

## 7.0 自定义字段总览（1290~1294）

| 字段号 | 名称 | 类型 | 典型长度 | 携带时机 | 数据源 |
|---|---|---|---|---|---|
| 1290 | work_mode 工作模式 | INTEGER | 4B | 每帧 | kvstore |
| 1291 | bat_change 充电状态 | INTEGER | 4B | 每帧 | battery.is_charging() |
| 1292 | 单点三轴（ASCII "x,y,z"） | ASCII | ~20B | GNSS 关 / 实时上报 | gsensor.read_xyz() |
| 1293 | 20Hz 三轴原始流（12bit 紧凑） | BINARY | 4B+900B=904B | GNSS 开且非实时上报 | gsensor 流采样缓冲 |
| 1294 | 1Hz 定位五元组流（int16 差值） | BINARY | 4B+100B=104B | 同上 | location NMEA 采样缓冲 |

## 7.1 字段 1290：工作模式（INTEGER）

```
TLV 头部：field_type = 0x0000 | 1290 = 0x050A；length = 0x0004
value    ：00 00 00 02          ← work_mode（大端 4B）
编码源   ：active_mode msg.data.work_mode / boot_lbs_report d.work_mode
取值     ：0=常规 1=智能 2=寻宠(GPS定位)（-1 未激活已废弃）
```

## 7.2 字段 1291：充电状态（INTEGER）

```
value：00 00 00 00  → 充电器不在位（未充电）
       00 00 00 01  → 充电器在位（含充满未拔，charging 语义）
编码源：battery.is_charging() 返回 true/false → 1/0
```

## 7.3 字段 1292：单点三轴加速度（ASCII）

```
value："0.021,-0.015,0.998"
         └─ x ─┘  └─ y ─┘  └─ z ─┘
格式  ：x,y,z 逗号分隔，各 3 位小数，单位 g（重力加速度）
编码源：string.format("%.3f,%.3f,%.3f", x_acc, y_acc, z_acc)
读取  ：gsensor.read_xyz() → exvib.read_xyz（I2C 主动读，g 值）
携带策略：GNSS 关闭（整包无 1293 原始流，用单点代替）或 实时上报（每秒报文只带常规字段）时携带；
         GNSS 开启且非实时上报时不带（1293 流已含完整运动信息，避免冗余撑长报文）
```

## 7.4 字段 1293：20Hz 三轴原始数据流（BINARY，12bit 紧凑编码）

### 7.4.1 采集侧（gsensor.lua）

| 参数 | 值 | 说明 |
|---|---|---|
| 采样率 | 20Hz（STREAM_INTERVAL_MS=50ms） | 流采样协程用 mcu.ticks 时间片调度，自动补偿 I2C 耗时 |
| 缓冲 | ≤205 样本 | 10s=200 + 少量余量；超出丢最旧 |
| 内存格式 | 每样本 **6B**：`string.pack(">i2i2i2", rx, ry, rz)` | x/y/z 各 2B 有符号 int16 大端，样本时间正序 |
| 数据源 | DA221 原始 12 位计数值（-2048~2047，2g 量程） | `exvib.read_xyz()` 的 raw 返回值 |
| 开关 | `stream_start()`（GNSS 开）/ `stream_stop()`（GNSS 关，清空缓冲） | active_mode 状态机驱动 |

### 7.4.2 编码规则（get_stream_data 输出）

- 取最近 N=min(count=200, #buf) 个样本；N 为奇数时**丢弃最旧 1 个**（保证两两成组）；
- 每 **2 个样本** = 6 个 12bit 值 = 72bit → 压成 **9 字节**；
- 字节内位序：**x1,y1,z1,x2,y2,z2**（12bit 值 MSB 在前），即 72bit 大端位流按 12bit 切成 6 段；
- 实现：`pack12(a,b)` 把两个 12bit 值装入 3 字节：
  ```
  byte1 = (a >> 4) & 0xFF
  byte2 = ((a & 0x0F) << 4) | ((b >> 8) & 0x0F)
  byte3 = b & 0xFF
  每样本组拼接：pack12(x1,y1) .. pack12(z1,x2) .. pack12(y2,z2)
  ```
- 200 样本 → 100 组 × 9B = **900 字节**；加 TLV 4B 头 = **904B**（≤ AirCloud 单包 1400B 约束）；
- DA221 原始值 12 位有符号 → `a & 0xFFF` 两补码截断**无损**。

### 7.4.3 编码示例

样本1：(x1=0x000, y1=0x001, z1=0x002)　样本2：(x2=0x003, y2=0x004, z2=0x005)

```
组内 9 字节 = pack12(0x000,0x001) .. pack12(0x002,0x003) .. pack12(0x004,0x005)
            = 00 00 01 | 00 20 03 | 00 40 05
整段（16 进制）：
  样本1   样本2
  x1 y1 z1 x2 y2 z2        （每值 12bit）
  000 001 002 003 004 005
  └──00 00 01──┘└──00 20 03──┘└──00 40 05──┘
  解码：9B → 连续 72bit 位流 → 每 12bit 一切：
  0x000 0x001 0x002 0x003 0x004 0x005（最高位为符号位，>0x7FF 则减 4096 还原负数）
```

### 7.4.4 解码方法（服务端）

1. 每 9 字节一组；
2. 读成 72bit 连续位流，按 12bit 切出 6 个值；
3. 符号扩展：值 > 0x7FF(2047) → 值 - 4096；
4. 得原始计数 (raw_x1, raw_y1, raw_z1, raw_x2, raw_y2, raw_z2)；如需 g 值：raw / 满量程 × 量程（2g 配置下 LSB≈0.00098g，具体量程需与 exvib 配置核对）。

## 7.5 字段 1294：1Hz 定位五元组数据流（BINARY，int16 差值编码）

### 7.5.1 采集侧（location.lua）

| 参数 | 值 | 说明 |
|---|---|---|
| 采样率 | 1Hz（每秒一次） | nmea_stream_task：读 `exgnss.rmc(2)` + `exgnss.gga(2)` |
| 入缓冲条件 | `rmc.valid=true` 且 lat/lng 非空 | 无效定位不入缓冲 |
| 缓冲 | ≤10 样本（NMEA_STREAM_KEEP） | 对应 10 秒（GNSS 开 10s 一报） |
| 样本字段 | {lat, lng, speed(节), course(度), altitude(米, GGA)} | speed 单位节，编码时换算 km/h |

### 7.5.2 编码规则（get_nmea_stream(ref_lat, ref_lng)）

每样本 **10 字节** = 5 个有符号 int16 大端（`string.pack(">i2i2i2i2i2")`），时间正序（最早在前）：

| 偏移 | 内容 | 编码 | 分辨率/范围 |
|---|---|---|---|
| 0-1 | 经度差 dLng | (s.lng − ref_lng) × 100000 | 1LSB≈0.00001°≈1.1m；范围 ±0.33° |
| 2-3 | 纬度差 dLat | (s.lat − ref_lat) × 100000 | 同上 |
| 4-5 | 速度 | s.speed(节) × 1.852 × 10 | 1LSB=0.1km/h；上限 3276.7km/h |
| 6-7 | 航向 | s.course × 10 | 1LSB=0.1°；0~3599（静止时不可信） |
| 8-9 | 海拔 | s.altitude(米) | 1LSB=1m |

- **差值基准**：ref_lat/ref_lng = 同包 TLV 512/513 字段坐标（服务端用"报文坐标 + 差值"还原每秒绝对坐标）；
- 舍入钳位：`to_i16` = floor(v+0.5)，超 ±32767 钳位（防 string.pack 溢出报错）；
- 10 样本 × 10B = **100 字节**；TLV 4B 头 = 104B。

### 7.5.3 编码示例

ref = (23.12845, 113.32187)，样本 = (23.13000, 113.32200)、速度 0.5 节、航向 90.0°、海拔 15m：

```
dLat = (23.13000 − 23.12845) × 100000 = 155  → 0x009B
dLng = (113.32200 − 113.32187) × 100000 = 13  → 0x000D
speed = 0.5 × 1.852 × 10 = 9.26 → 9         → 0x0009
course = 90.0 × 10 = 900                     → 0x0384
alt = 15                                      → 0x000F
样本 10 字节：00 9B | 00 0D | 00 09 | 03 84 | 00 0F
```

### 7.5.4 服务端还原公式

```
绝对经度 = TLV 512 字段(经度) + dLng / 100000
绝对纬度 = TLV 513 字段(纬度) + dLat / 100000
速度(km/h) = speed_raw × 0.1
航向(°) = course_raw × 0.1
```

## 7.6 整包大小与携带矩阵

| 运行态 | 携带的二进制流 | 整包 body 估算 |
|---|---|---|
| GNSS 开（10s 周期） | 1293(904B) + 1294(104B) + 常规字段(≈80B) | ≈1100B（上限内） |
| GNSS 关（300s 周期） | 无 1293/1294；1292 单点三轴(≈25B) + 常规字段 | ≈100B |
| 实时上报（1s 周期） | 无流；1292 单点三轴每帧 + 常规字段 | ≈100B × 60 帧 |
| 开机 LBS（boot_lbs_report） | 无流 | ≈80B |
