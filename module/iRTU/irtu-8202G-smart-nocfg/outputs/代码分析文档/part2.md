
# 3. 设备通信流程

## 3.1 开机启动流程（时序）

![开机启动流程](./images/fig2_boot_flow.png)

**逐步说明：**

| 步 | 动作 | 代码位置 | 说明 |
|---|---|---|---|
| 1 | `fskv.init()`；`mobile.simid(1)` | main.lua | 固定使用卡槽 SIM1（双卡槽硬件，SIM0 不用） |
| 2 | `update.init()` | main.lua | libfota3：开机检测一次 + 每 8h 自动检测；不阻塞启动 |
| 3 | BOOT_MODE=2 分发 | main.lua L104 | 默认强制正常模式，跳过产测（产测分支仅 0/1 时可达） |
| 4 | `cfg_fetch.init()` 加载本地配置 | main.lua L53 | 读取 `/luadb/air8201.cfg`，判定是否有"有效定位版配置"（gnss.network.conf 非空） |
| 5 | 有有效配置 → `config.load_from_server` + `remote.init()` + `create.start(sheet)`；无 → `create.start({gnss={network=config.DEFAULT_NETWORK}})` | main.lua L67-85 | 云通道启动；DEFAULT_NETWORK = 通道1 AIRCLOUD/TCP |
| 6 | `app.start()`（延迟 2s） | main.lua L93-95 | 进入 app_task |
| 7 | `boot_lbs_report.start()` | main.lua L98 | 独立任务：联网后先做一次 LBS 定位并双通道上报（不等 GNSS） |
| 8 | app_task：读唤醒原因、监听 Power 键、`init_all_modules()` | app.lua | 初始化顺序：kvstore → battery → location → gsensor → charge → air153c_wdt → remote → lowpower_app |
| 9 | work_mode 校验 | app.lua L110 | 若旧设备存 -1（未激活），强制 `set_work_mode(2)` 进寻宠模式 |
| 10 | `require("active_mode")` | app.lua L118 | 模块加载即 `sys.taskInit(main_loop)`，进入 GNSS 三态主循环 |

## 3.2 网络连接与鉴权流程（AirCloud 通道）

![网络连接鉴权流程](./images/fig3_comm_flow.png)

**连接链路（create.aircloudTask → excloud）：**

1. `create.start` 筛选 `conf_on[i]==1` 的通道 → `sys.taskInit(connect, active_conf)`；
2. `connect()` 分发：`AIRCLOUD` 类型 → `sys.taskInitEx(aircloudTask, "DTU_k", ...)`（默认通道 k=1）；
3. `aircloudTask`：
   - **先注册两个发送订阅**（连接前注册避免丢消息）：
     - `AIRCLOUD_SEND_1` ← `create.send_aircloud(TLV数组)` → 直接 `excloud.send(tlvs)`
     - `NET_SENT_RDY_1` ← `create.send(JSON串)` → 封装为 `RANDOM_DATA(1281)` ASCII 字段 `excloud.send`
   - 等待 `IP_READY`；
   - `excloud.on(cb)` 注册回调（connect_result / auth_result / message / disconnect / send_result）；
   - `excloud.setup()`（transport=tcp、use_getip=true、auto_reconnect、mtn_log 开启）→ `excloud.open()`；
4. `excloud.open()` 内部：getip（POST api.luatos.com/iot/getip 拿 host/port/auth_key，重试 3 次）→ TCP connect → 发鉴权请求（字段16 `AUTH_REQUEST`，ASCII 值 `auth_key-IMEI-MUID`）；
5. 服务器回字段 17 `AUTH_RESPONSE`：`ok/success` → `is_authenticated=true`、回调 `auth_result(success)`；**非 ok/success → 判鉴权失败，武装复位看门狗**（10 分钟复位，当日 ≤5 次，超限降级 1 小时慢速重试）；
6. `create` 侧收到 `connect_result.success` → `datalink[cid]=true` + 发布 `CLOUD_CONNECTED`；`active_mode` 主循环 `waitUntil("CLOUD_CONNECTED",30000)` 后执行开机上报。

**心跳保活**：aircloudTask 主循环 `keepAlive(300s)` 轮询——若距上次成功发送 ≥300s 则发心跳（RANDOM_DATA 字段内容为 `{csq,eci,rsrp,band}` JSON），有数据上报则自动跳过（数据即保活）。

## 3.3 上行数据上报流程

**一条典型周期上报（GNSS 开启期间，10s 节奏）的数据流：**

```
collect_data_and_report()  [active_mode.lua]
   │
   ├─ pm.power(WORK_MODE,0)        恢复全功率
   ├─ 等 IP_READY（≤30s）
   ├─ battery.force_check()         读电池缓存（YHM2712A 后台轮询刷新）
   ├─ location.get_report_location(gnss_active)  → {gps="lat,lng", gps_status}
   │      GNSS 优先锁定：开机以来成功过一次 → 恒走 GNSS（当前成功用当前值，否则用最近成功值）
   │      从未成功 → LBS（lbsLoc2/AirLBS），gps_status=3/4/5
   ├─ mobile.csq() / iccid() / scell()         信号/ICCID/频段
   ├─ gsensor.read_xyz()                        "x,y,z"（g 值，3 位小数）
   ├─ gsensor.get_stream_data(200)  ← GNSS开&非实时上报时：20Hz×10s=200 样本 12bit 紧凑编码 ≈900B
   ├─ exgnss.gsv() → top4 CN / 搜星数
   ├─ location.get_nmea_stream()    ← GNSS开&非实时上报时：1Hz×10 样本 ×10B =100B 差值编码
   │
   ├─ 组装 JSON 报文 {msg_id,imei,ts,type:"property_report",data:{...}}
   │      → create.send(json)  ──► publish NET_SENT_RDY_1
   │                               └─► aircloudTask 订阅 → RANDOM_DATA TLV → excloud.send
   │
   └─ 组装 TLV 数组 build_aircloud_tlv(d, xyz_stream, nmea_stream, gnss_active)
          → create.send_aircloud(tlvs) ──► publish AIRCLOUD_SEND_1
                                          └─► excloud.send(tlvs)  ★二进制数据只走此通道
```

**JSON 报文格式（示例，type=property_report）：**

```json
{
  "msg_id": "861234567890123-1767300000",   // IMEI-时间戳，服务器判重用
  "imei": "861234567890123",
  "ts": 1767300000,
  "type": "property_report",                // startup / property_report / command_reply / boot_lbs_report
  "data": {
    "work_mode": 2,              // 0常规 1智能 2寻宠
    "vbat": 3980,                // 电池电压 mV
    "bat_change": 0,             // 1=充电器在位
    "gps": "23.12845,113.32187", // WGS84 坐标（lat,lng）
    "gps_status": 2,             // 2=GPS 3=失败 4=免费LBS 5=付费LBS
    "signal": 18,                // CSQ
    "iccid": "8986000000000000000",
    "chip_model": "Air8202",
    "boot_reason": "power_on",
    "band": "LTE B3",
    "wake_interval": 10,         // 本次上报周期（1/10/300）
    "top4_cn": "31,29,28,27",    // 最强 4 星 CN
    "sat_total": 24, "sat_visible": 9,
    "gsensor_xyz": "0.021,-0.015,0.998"
  }
}
```

## 3.4 下行命令流程

![下行命令处理流程](./images/fig3_comm_flow.png)

```
服务器下行 TLV 报文
   └─ excloud socket 回调 → parse_data() → 字段 17/18 走鉴权/回应判定；其余 → callback("message", msg)
        └─ create.lua on() 回调：message → 逐 TLV → publish REMOTE_COMMAND {command=tlv.value, raw=tlv}
             └─ remote.handle_command → execute_command（独立协程）
                  ├─ json.decode 失败 → 忽略
                  ├─ 命中 command_handlers 表 → 执行 handler
                  └─ 未知命令 → send_reply(result=1, "未知命令")
```

**11 种命令一览（command_handlers）：**

| # | 命令 | 行为 | 回执 result |
|---|---|---|---|
| 1 | `get_device_data` | publish `FORCE_REPORT` → active_mode 立即上报一次 | 0 ok |
| 2 | `change_mode` | 校验 mode ∈{-1,0,1,2} → kvstore 写 work_mode → 按设备模式设功耗 → 3s 后 reboot | 0/2 参数错 |
| 3 | `call` | 无 SIP 硬件，拒绝 | 4 不支持 |
| 4 | `play_sound` | 无音频硬件，拒绝 | 4 不支持 |
| 5 | `open_light` | LED 手动开(1)/恢复自动(0) | 0/2 参数错 |
| 6 | `close_device` | 回执后 3s `pm.shutdown()` | 0 ok |
| 7 | `set_report_interval` | 校验范围后**回执不支持**（GNSS 三态固定节奏） | 4 不支持 |
| 8 | `set_volume` | 保存音量到 kvstore，回执不支持 | 4 不支持 |
| 9 | `update` | 触发 OTA 检查 | 0 ok |
| 10 | `fota_mode` | 切换 libfota2/3 | 0 ok / 1 缺参 |
| 11 | `fast_report` | publish `FAST_REPORT_START` → 进入 1s 实时上报 1 分钟 | 0 ok |

**命令触发的三个关键事件：**

| 事件 | 发布方 | 订阅方/效果 |
|---|---|---|
| `FORCE_REPORT` | remote.get_device_data | active_mode 置 force_report_pending → 清零节流基准 → 立即上报一帧 |
| `FAST_REPORT_START` | remote.fast_report | active_mode 进入实时上报：未开 GNSS 先强制开；60s 倒计时（重复下发续期） |
| `REMOTE_COMMAND` | create（一切下行） | remote 命令分发 + tools 记 last_rx_time（LED 通信正常证据） |

**回执（command_reply）经 JSON 通道返回**：`{msg_id, reply_to, type:"command_reply", data:{command,result,message}}` → `create.send` → RANDOM_DATA TLV 上送。
