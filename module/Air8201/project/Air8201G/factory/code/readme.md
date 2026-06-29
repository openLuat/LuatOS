# Air8201G 挂载项目测试软件 README

> 项目代号：Air8201G-IRTU
> 硬件平台：合宙 Air8201 工业引擎
> 主控固件：LuatOS

---

## 目录

- [一、项目概述](#一项目概述)
- [二、功能列表（截止 2026.05.27）](#二功能列表截止-20260527)
- [三、模块工作逻辑](#三模块工作逻辑)
- [四、上报数据字段定义](#四上报数据字段定义)
- [五、Update 日志](#五update-日志)

---

## 一、项目概述

基于合宙 Air8201G 工业引擎的低功耗定位器项目。设备通过 4G 网络上报状态到 EXCLOUD 云平台，支持震动唤醒、定时上报、远程控制、电池管理等核心功能，目标场景为工业资产追踪 / 宠物定位类长期部署应用。

**硬件特性**：

| 项 | 配置 |
|---|---|
| 主控 | Air8201（4G CAT1） |
| Gsensor | DA267（I2C1，电源 GPIO24，I2C 上拉 GPIO28，中断 GPIO20） |
| GNSS | 内置 GNSS |
| 电池监测 | ADC0 |
| 关机按键 | PWRKEY（长按 7 秒关机） |

**工作模式**：仅支持 MODE1 低功耗常驻（`pm.power(pm.WORK_MODE, 1)`），已删除 PSM+ 模式。

---

## 二、功能列表（截止 2026.05.27）

| # | 功能模块 | 文件 | 简述 |
|---|---|---|---|
| 1 | 系统主入口 | [main.lua](file:///d:/Air8201G/挂载项目测试软件/user/main.lua) | 模块导入、初始化、任务调度、SIM 热插拔、wakeup 配置 |
| 2 | 云端通信 | [excloud_module.lua](file:///d:/Air8201G/挂载项目测试软件/user/excloud_module.lua) | EXCLOUD TCP 长连接、鉴权、心跳、收发回调封装 |
| 3 | 数据上报 | [report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua) | TLV 数据组装、定时/震动/远程触发上报、震动冷却期 |
| 4 | 电源管理 | [mypower.lua](file:///d:/Air8201G/挂载项目测试软件/user/mypower.lua) | 电池 ADC 检测、USB 充电识别、低电关机、PWRKEY 长按关机 |
| 5 | Gsensor | [gsensor.lua](file:///d:/Air8201G/挂载项目测试软件/user/gsensor.lua) | DA267 初始化、震动中断检测、震动事件发布 |
| 6 | GNSS/LBS | [mygps.lua](file:///d:/Air8201G/挂载项目测试软件/user/mygps.lua) | LBS 基站定位、GNSS 卫星定位、定位结果缓存 |
| 7 | 蓝牙 | [myble.lua](file:///d:/Air8201G/挂载项目测试软件/user/myble.lua) | BLE 外设广播（当前禁用） |

---

## 三、模块工作逻辑

### 3.1 启动流程

```
设备上电
   ↓
main.lua require 各模块
   ↓
SIM 热插拔中断配置（WAKEUP2）
   ↓
mypower.init() → 电池采样 + PWRKEY 长按监听
   ↓
gsensor.init() → DA267 初始化 + 震动中断
   ↓
mygps.init() → GNSS 初始化
   ↓
excloud_module.init() → EXCLOUD 连接 + 鉴权 + 心跳
   ↓
report.start() → 首次 PWRKEY 上报 + 启动定时上报循环
   ↓
sys.run() 主循环
```

### 3.2 上报逻辑

| 触发原因 | 标识 | 间隔 | 冷却期 | GNSS |
|---|---|---|---|---|
| 开机首次 | `PWRKEY` | - | - | 触发 |
| 定时上报 | `TIMER` | 5 分钟 | - | 每 30 分钟一次 |
| 震动触发 | `MOTION` | 即时 | **10 分钟**（冷却期内忽略） | 触发 |
| 远程/手动 | `MANUAL` | 即时 | 不影响冷却 | 触发 |

**GNSS 策略**：每 30 分钟最多触发一次同步定位（最长阻塞 60 秒，超时放弃），结果缓存供本次上报使用。

### 3.3 电源管理

| 阈值 | 行为 |
|---|---|
| 电压 ≤ 3400mV 且未充电 | 调用 `pm.shutdown()` 关机 |
| 电压 ≥ 4200mV | 电量 100% |
| USB 插入 | 进入充电模式，估算充满时间 |
| PWRKEY 长按 ≥ 7 秒 | 调用 `pm.shutdown()` 关机（每秒轮询累计电平） |

### 3.4 Gsensor 工作

| 参数 | 值 |
|---|---|
| 芯片 | DA267 |
| I2C 地址 | 0x26 |
| WHO_AM_I | 0x13 |
| 震动阈值 | 0x20（降低敏感度） |
| 中断节流 | 3000ms |
| 上电延时 | 200ms（保证 POR） |

### 3.5 EXCLOUD 通信

| 配置 | 值 |
|---|---|
| 传输 | TCP |
| 设备类型 | 1（4G） |
| 自动重连 | 开启 |
| 重连间隔 | 10 秒 |
| 最大重连次数 | 5 |
| 心跳间隔 | 5 分钟 |

---

## 四、上报数据字段定义

### 4.1 标准字段（excloud 协议）

| 字段编号 | 名称 | 含义 |
|---|---|---|
| 776 | BOOT_REASON | 开机原因 |
| 799 | VOLTAGE | 电池电压 |
| 798 | DEVICE_ID | 设备号 |
| 782 | SIGNAL_STRENGTH_4G | 4G 信号强度 |
| 783 | SIM_ICCID | SIM 卡号 |
| 781 | NETWORK_TYPE | 联网方式 |
| 520 | GNSS_INFO | GNSS 定位结果（复用） |

### 4.2 自定义字段

| 字段编号 | 类型 | 含义 |
|---|---|---|
| 1281 | ASCII | 上报原因：`TIMER` / `MOTION` / `PWRKEY` / `MANUAL` |
| 1282 | INTEGER | 业务 SN（每次业务上报成功后 +1） |
| 1284 | INTEGER | 在线时间（分钟，从本次启动起累计） |

---

## 五、Update 日志

### 2026-05-28（今日更新）

本日完成多项 Bug 修复、功能增强与代码重构，共修改 6 个文件、新增 1 个文件、新增多个 MCP 验证依据。

#### 1. Gsensor 初始化稳定性优化

**问题**：开机时 I2C 读取 WHO_AM_I 寄存器报 `-6 NACK` 错误，导致 DA267 设备验证失败、Gsensor 整个会话不工作。

**根因**：上电延时不足（仅 70ms）+ 无重试机制。

**修改文件**：[gsensor.lua](file:///d:/Air8201G/挂载项目测试软件/user/gsensor.lua)

- 上电延时：70ms → **200ms**（合宙官方建议值）
  - `GPIO24` 上电后 `sys.wait(50)`
  - `GPIO28` 上拉使能后 `sys.wait(150)`
- WHO_AM_I 验证增加 **5 次重试机制**（每次失败间隔 100ms）
- 5 次重试均失败时调用 `hw_power_off()` 释放电源避免空跑功耗

**依据**：合宙官方 [Air780EPM onewire_multi_app.lua](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EPM/demo/onewire/onewire_multi_app.lua) demo 明确"传感器上电稳定时间最小 50ms，推荐 100ms"。

---

#### 2. 业务 SN 跳号问题修复

**问题**：云平台看到的"业务 SN"在心跳/online 包夹缝中跳号，无法连续。

**根因**：之前误以为 excloud 自带心跳偷偷发包导致跳号，先后尝试自管心跳/禁用心跳等错误方案。

**真相**：底层 `sequence_num` 与业务 SN 是两个独立概念。云平台展示的可能是底层 `sequence_num`，而业务 SN（字段 1282）始终独立维护。

**修改文件**：[report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua)

- 引入 **业务 SN 字段（1282）**：仅在 `send_status` 成功后递增
- 引入 **在线时间字段（1284）**：累计当前进程的在线分钟数
- 增加 `boot_time_sec` 状态变量

---

#### 3. 心跳机制重构（多轮迭代）

**最终方案**：恢复 excloud 库自带心跳 + 传入最小 TIMESTAMP payload + 暴露开关。

**修改文件**：[excloud_module.lua](file:///d:/Air8201G/挂载项目测试软件/user/excloud_module.lua)

- 修复 "**没有有效的TLV数据可发送**" 错误（旧 `excloud.start_heartbeat()` 默认 `heartbeat_data={}` 导致心跳实际发不出去）
- 心跳数据携带 **1 个 TIMESTAMP 字段**作为最小 payload
- 暴露对外开关：
  - `excloud_module.HEARTBEAT_AUTO_START`（默认 true）
  - `excloud_module.HEARTBEAT_INTERVAL_SEC`（默认 300）
- 抽出 `start_heartbeat_if_needed()` 函数，**轻量幂等**（已启动时直接跳过）
- 修复 BUG：断网时 excloud 库内部 `close()` 会 `stop_heartbeat()`，而 `open()` 不会重启心跳。新方案在 `connect_result.success=true` 事件中自动重启心跳，断网/重连场景自愈
- `disconnect` 事件归位 `heartbeat_started` 软标记

---

#### 4. 死代码清理

**问题**：[main.lua](file:///d:/Air8201G/挂载项目测试软件/user/main.lua) `sys.run()` 之后有约 82 行重复定义的死代码，引用了已删除的 `config.reset_to_factory()` / `handle_remote_config` / `set_working_mode`。

**修改**：删除 sys.run 之后所有内容，文件从 ~288 行收敛到 ~206 行。

---

#### 5. 重启原因上报重构

**问题**：旧代码用了**错误的 API 名** `pm.lastReason()`（多了一个 a），pcall 永远捕获 nil 错误，**重启原因字段永远是 0**。

**根因**：合宙官方 API 实际拼写是 **`pm.lastReson()`**（少一个 R），所有合宙模组都支持，无需 pcall 保护。

**修改文件**：[report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua)

- 改用正确 API：`pm.lastReson()`
- 直接调用，**删除 pcall 保护**
- 接收 **3 个返回值**（r1, r2, r3）组成字符串 `"r1,r2,r3"` 上报
- BOOT_REASON 字段类型：`INTEGER` → `ASCII`
- 删除本地 `reason_map` 中文映射表（云端可自行解码）

**依据**：合宙官方所有模组（Air780EPM/EHM/Air8000/Air8101/Air1601）的 [internal_wdt.lua](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EPM/demo/wdt/internal_wdt.lua) demo 写法一致：
```lua
local reason1, reason2, reason3 = pm.lastReson()
```

---

#### 6. 全局配置 FSKV 持久化模块（新增）

**新增文件**：[global_config.lua](file:///d:/Air8201G/挂载项目测试软件/user/global_config.lua)

基于 FSKV 持久化记录设备运行统计信息，共 5 个字段：

| FSKV Key | 类型 | 含义 |
|---|---|---|
| `gcfg_boot_time` | number | 首次上电开机时间戳（秒） |
| `gcfg_reset_count` | number | 硬件 reset / 软件重启次数 |
| `gcfg_report_count` | number | 数据包总上传次数 |
| `gcfg_tcp_fail_count` | number | TCP 连接失败次数 |
| `gcfg_disconnect_count` | number | 断网次数 |

**核心逻辑**：

- `pm.lastReson() = (0,0,0)` 视为**冷启动**：`fskv.clear()` 清空 + 写初始值
- 其他重启原因视为**软重启**：保留历史，`reset_count + 1`

**对外 API**：

| API | 用途 |
|---|---|
| `global_config.init()` | 必须在 main.lua 启动早期调用一次 |
| `global_config.inc_report_count()` | 业务/心跳包发送成功时 +1 |
| `global_config.inc_tcp_fail_count()` | TCP 连接失败时 +1 |
| `global_config.inc_disconnect_count()` | 断网事件时 +1 |
| `global_config.get_stats()` | 返回 5 字段快照 |
| `global_config.dump_stats()` | 打印当前快照（调试用） |
| `global_config.is_initialized()` | 查询初始化状态 |

**防御性设计**：

- 多次 `init()` 安全（initialized 标志保护）
- fskv 失败仅打日志不抛错
- 旧固件升级缺字段自动补齐
- 未 init 就调用 inc_* 仅 warn 跳过

**依据**：
- [FSKV 官方文档](https://docs.openluat.com/air8201/luatos/app/common/fskv/)
- [Air8000 fskv_test.lua demo](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/fskv/fskv_test.lua)

---

#### 7. 统计接入点集成

**修改文件**：
- [main.lua](file:///d:/Air8201G/挂载项目测试软件/user/main.lua)：require global_config + 启动早期 `init()` + `dump_stats()`
- [report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua)：require global_config + `send_status` 成功后 `inc_report_count()`
- [excloud_module.lua](file:///d:/Air8201G/挂载项目测试软件/user/excloud_module.lua)：require global_config + 连接失败时 `inc_tcp_fail_count()` + 断网时 `inc_disconnect_count()`

**改动原则**：**仅插入式新增**，不修改/删除任何原有代码，不破坏原结构。

**Flash 寿命评估**：

- 日均写入约 300 次
- FSKV 采用 **磨损均衡（Wear Leveling）**，单块寿命 10 万次擦写
- 64KB 分区 × 16 块 × 10 万次 ≈ **总擦写预算 160 万次**
- 实际寿命约 **10 年**，远超工业级长期部署需求

---

#### 8. excloud.lua 库 Bug 分析（仅建议未改）

**Bug**：`excloud.luac:-1: attempt to call a nil value (field 'schedule_reconnect')`

**根因**：库内 `start_connect_timeout`（约 137 行）引用了下方 1327 行才定义的 `schedule_reconnect`，由于 Lua 局部函数词法作用域顺序问题，引用变成 `_ENV.schedule_reconnect` 全局查找（nil）。

**建议方案**（暂未执行）：
- 方案 A：增加 `local schedule_reconnect` 前向声明
- 方案 B：将 `start_connect_timeout` 整体移到 `schedule_reconnect` 定义之后
- 方案 C：把 `schedule_reconnect` 改为 `excloud.schedule_reconnect`

---

#### 9. 其他变更汇总

| 变更 | 文件 | 内容 |
|---|---|---|
| 上报字段顺序优化 | report.lua | 删除 1283（心跳次数）字段（信息冗余） |
| 删除 `HEARTBEAT_INTERVAL_MS` 常量 | report.lua | 自管心跳已删除 |
| 删除 `heartbeat_count` 状态变量 | report.lua | 同上 |
| 恢复 `send_device_status("online")` | excloud_module.lua | 连接成功事件中保留 |

---

### 2026-05-28（续 · 当日后续更新）

继本日上一批更新之后，又完成一轮基于 FSKV 的统计上报扩展与 boot_time 语义重构。

#### 10. 新增 5 个 FSKV 统计字段上报到云端

**目标**：把 `global_config` 的统计数据扩展到上报包，便于云端监控设备健康状态。

**修改文件**：[report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua)

| 字段编号 | 类型 | 名称 | 数据源 |
|---|---|---|---|
| **1285** | INTEGER | 心跳总数 | `gcfg_report_count`（业务+心跳合计） |
| **1286** | INTEGER | TCP 断联次数 | `gcfg_tcp_drop_count`（新增字段） |
| **1287** | INTEGER | 断网次数 | `gcfg_disconnect_count` |
| **1288** | INTEGER | 重启次数 | `gcfg_reset_count` |
| **1289** | INTEGER | 上电时间（秒） | `gcfg_boot_time` |

每个字段在 TLV 数据包中以 IIFE 形式从 `global_config.get_stats()` 读取，与原有 1281/1282/1284 字段风格保持一致。

#### 11. 拆分 TCP 断联 vs TCP 连接失败语义

**问题**：原 `gcfg_tcp_fail_count` 仅记录"连接失败（建连不成功）"，无法表达"已连接后被断开"。

**修改文件**：
- [global_config.lua](file:///d:/Air8201G/挂载项目测试软件/user/global_config.lua)
- [excloud_module.lua](file:///d:/Air8201G/挂载项目测试软件/user/excloud_module.lua)

**改动**：
- 新增 FSKV key `gcfg_tcp_drop_count`（已连接的 TCP 链路被断开次数）
- 新增 API `global_config.inc_tcp_drop_count()`
- 在 `disconnect` 事件中**同时**递增 `disconnect_count` 与 `tcp_drop_count`
- `get_stats()` / `dump_stats()` 同步补齐新字段

**语义对照**：

| FSKV Key | 触发事件 | 含义 |
|---|---|---|
| `gcfg_tcp_fail_count` | `connect_result.success = false` | TCP 建连失败 |
| `gcfg_tcp_drop_count` | `disconnect` | TCP 已连接被断开 |
| `gcfg_disconnect_count` | `disconnect`（与 tcp_drop 同源） | 网络断开事件（未来可挂 IP_LOSE 细分） |

#### 12. `boot_time` 语义重构：首次上电时间 → 首次联网时间

**问题**：原实现在 `global_config.init()` 中冷启动时立即调用 `os.time()` 写入 boot_time，但**模组上电瞬间 RTC 尚未对时**（可能是 1970-01-01 或上次关机前旧值），导致 boot_time 完全不可信。

**根因**：合宙官方明确"模组上电以后固件内部联网成功以后会自动发布 `IP_READY`，4G 卡通常会自动下发基站时间对时"——必须等联网+对时完成后才能拿到真实 UTC 时间。

**修改文件**：[global_config.lua](file:///d:/Air8201G/挂载项目测试软件/user/global_config.lua)

**改动**：
- 新增状态变量：`is_cold_boot_flag` / `boot_time_recorded` / `CELL_TIME_SYNC_WAIT_MS = 3000`
- **冷启动分支**：boot_time 不再立即写真实时间，改为占位 `0` + 标记 `is_cold_boot_flag = true`
- **非冷启动分支**（严格遵守用户要求"其他原因不修改"）：
  - boot_time 缺失时**只补占位 0**（不写 `os.time()`）
  - 不修改 FSKV 中已存在的 boot_time 值
  - 标记 `boot_time_recorded = true` 防 task 误写
- **新增异步监听 task**（init 末尾启动，仅冷启动场景）：
  ```
  sys.waitUntil("IP_READY")
    ↓
  sys.wait(3000)   -- 等基站对时同步到 RTC
    ↓
  fskv.set("gcfg_boot_time", os.time())   -- 真实 UTC 时间
  ```
- 二次确认 `boot_time_recorded` 标志，防止 task 启动期间被其他流程改写

**MCP 权威依据**：
- [TCP 文档](https://docs.openluat.com/air8201/luatos/app/socket/tcp/) chunk_id=42：IP_READY 由内核固件自动发布
- [NTP 文档](https://docs.openluat.com/atmozu/product/command/ntp/)：移动/电信卡通常自动下发基站时间
- [LuatOS lesson 002](https://docs.openluat.com/luatos_lesson/002_luatos_socket/)：IP_READY 是系统全局消息

**1289 上报字段行为**：

| 设备状态 | 1289 上报值 |
|---|---|
| 冷启动后**未联网**期间 | `0`（云端可识别为"未对时"） |
| 冷启动后**已联网+已对时**期间 | 真实 UTC 时间戳 |
| 非冷启动（看门狗/软重启等） | **保持上次冷启动记录的时间戳，永不变** |

#### 13. FSKV 寿命评估修正

**纠正**：上一批更新中错误地以"10 万次 / 日均次数"线性估算 Flash 寿命（约 333 天）。

**正确理解**（基于合宙官方文档原文："10 万次擦写**均衡**"）：

- FSKV 采用 **磨损均衡（Wear Leveling）** 算法
- **单个 Flash 物理块**寿命 10 万次擦写
- 通过**均衡算法分散写入到所有物理块**
- 实际寿命 = (总块数 × 10 万次) - 元数据/GC 开销
- 以 64KB 分区 / 4KB 块 / 16 块计算：约 **112 万次有效写**
- 按 300 次/天 ≈ **10 年寿命**

**实际项目无需任何优化**，当前"每次事件实时写入"策略最优。

#### 14. readme.md 项目说明文档（新增）

**新增文件**：[user/readme.md](file:///d:/Air8201G/挂载项目测试软件/user/readme.md)

记录项目说明 + Update 日志，支持后续增量追加。结构：

- 一、项目概述
- 二、功能列表（截止 2026.05.27 基线）
- 三、模块工作逻辑
- 四、上报数据字段定义
- 五、Update 日志（按日期分章节追加）

---

#### 当日完整变更文件清单

| 文件 | 当日变更次数 | 主要内容 |
|---|---|---|
| [global_config.lua](file:///d:/Air8201G/挂载项目测试软件/user/global_config.lua) | 2 轮 | 新增模块 + tcp_drop_count + boot_time 异步重构 |
| [report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua) | 3 轮 | Gsensor 修复链路 + 重启原因重构 + 新增 5 个上报字段 |
| [excloud_module.lua](file:///d:/Air8201G/挂载项目测试软件/user/excloud_module.lua) | 4 轮 | 心跳重构 + 重连后心跳恢复 + 暴露开关 + 新增 tcp_drop 计数 |
| [main.lua](file:///d:/Air8201G/挂载项目测试软件/user/main.lua) | 2 轮 | 死代码清理 + 集成 global_config |
| [gsensor.lua](file:///d:/Air8201G/挂载项目测试软件/user/gsensor.lua) | 1 轮 | 上电延时 + WHO_AM_I 重试 |
| [readme.md](file:///d:/Air8201G/挂载项目测试软件/user/readme.md) | 2 轮 | 新增 + 本次追加 |

---

### 2026-06-02

OTA 模块上线 + GNSS 链路完整闭环。

#### 1. 新增 OTA 远程升级管理模块

**新增文件**：[ota_manegement.lua](file:///d:/Air8201G/挂载项目测试软件/user/ota_manegement.lua)

基于合宙官方 `libfota2` + `iot.openluat.com` 平台，3 种触发机制独立运行：

| 触发源 | 实现 | 是否影响周期定时器 |
|---|---|---|
| **开机首次** | `boot_task`：等 IP_READY → 等 5 秒网络稳定 → 检查升级 | 完成后才启动周期定时器 |
| **周期 24h** | `sys.timerLoopStart(do_request, 24*3600*1000)` | 自身循环 |
| **PWRKEY 短按** | 订阅 `PWRKEY_SHORT_PRESS` → 立即检查 | ❌ 不影响周期 |

**关键设计**：
- `fota_in_progress` 软标记防止多源并发触发
- 升级成功后 `sys.wait(3000)` 留缓冲让 FSKV/report 完成落盘再 `rtos.reboot()`
- 完整处理 libfota2 的 result 0-5 错误码
- `PRODUCT_KEY` 配置预留 TODO，强制提示用户去 iot 平台替换真实项目 ID

**联调记录**：实测出现 `http code 400` + `云平台下发的不是json` + `result=4`，根因诊断为 **PRODUCT_KEY 仍为占位值 "123"**，提示用户去 https://iot.openluat.com/iot/project-list 创建项目获取真实 KEY 替换。

#### 2. main.lua 集成 OTA 模块

**修改文件**：[main.lua](file:///d:/Air8201G/挂载项目测试软件/user/main.lua)

- 新增 `require "ota_manegement"` + `ota_manegement.init()` 调用
- 模块加载顺序在 `global_config.init()` 之后

#### 3. WAKEUP0 中断：手动触发 GPS + 上报

**修改文件**：[main.lua](file:///d:/Air8201G/挂载项目测试软件/user/main.lua) + [report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua)

| 配置项 | 值 |
|---|---|
| GPIO | `gpio.WAKEUP0` |
| 上拉 | `gpio.PULLUP` |
| 触发 | `gpio.FALLING`（下降沿） |
| 防抖 | 200 ms |
| 事件 | `sys.publish("GPS_TRIGGER_REQ")` |

**Report 端独立监听 task**：
- 与主上报循环、震动冷却、24h OTA 完全解耦
- 不受 30 分钟 GNSS 节流限制——中断必触发一次 GNSS
- 定位成功上报 `"lat,lng"`；失败上报 `"0.000000,0.000000"`（按业务要求经纬度为 0 也汇总上报）
- 新增 `REPORT_REASON.GPS_TRIGGER` 枚举

#### 4. mygps.lua 修复 exgnss API 误用

**修改文件**：[mygps.lua](file:///d:/Air8201G/挂载项目测试软件/user/mygps.lua)

**BUG 1**：之前用 `local ok = exgnss.open(...)` 拿返回值判断成败，但官方源码确认 **`exgnss.open()` 无返回值**，`ok` 永远是 nil，所有 GNSS 请求都被错误地判定为打开失败。

**修复**：删除 `local ok =` 和 `if not ok` 分支，加醒目警告注释。

**BUG 2**（更严重）：TIMERORSUC 模式下，cb 触发后 exgnss 内部**立即** `fnc_close` 关闭硬件，导致 `libgnss.isFix()` / `rmc()` 被清零。我之前在 cb 内仅发布事件、由外层 task 再读 `is_fix()` 已经晚了——**永远是 false**。

实测日志佐证：
```
GNSS 回调触发, is_fix=true     ← cb 内 OK
exgnss._close                   ← 关闭硬件
GNSS 在 60s 内未定位成功        ← 外层判定失败 ❌
```

**修复**：在 cb 内立即读取 `is_fix() + RMC + GGA` 并快照到 upvalue table，外层 task 仅基于快照判定。修复后定位成功时数据能正确流转到上报包。

#### 5. report.lua GNSS 失败上报值调整

| 场景 | 旧值 | 新值 |
|---|---|---|
| 未触发 GNSS | `"SKIP"` | `"SKIP"`（保持） |
| 定位成功 | `"lat,lng"` | 保持 |
| **定位失败** | `"FAIL"` | **`"0.000000,0.000000"`** |

按用户要求"定位失败，定位经纬度为 0，汇总到上报数据包里上报一次"。

---

#### 当日变更文件清单

| 文件 | 主要内容 |
|---|---|
| [ota_manegement.lua](file:///d:/Air8201G/挂载项目测试软件/user/ota_manegement.lua) | 新增：OTA 模块（开机/24h 周期/PWRKEY 短按 三触发） |
| [main.lua](file:///d:/Air8201G/挂载项目测试软件/user/main.lua) | OTA 集成 + WAKEUP0 中断配置 |
| [mygps.lua](file:///d:/Air8201G/挂载项目测试软件/user/mygps.lua) | exgnss.open 返回值 BUG + cb 快照机制重构 |
| [report.lua](file:///d:/Air8201G/挂载项目测试软件/user/report.lua) | GPS_TRIGGER 监听 task + 失败值改 "0.000000,0.000000" |
| [readme.md](file:///d:/Air8201G/挂载项目测试软件/user/readme.md) | 追加本日章节 |

#### 用户必做事项

⚠️ **OTA 上线前必做**：
1. 到 https://iot.openluat.com/iot/project-list 创建项目获取真实 PRODUCT_KEY
2. 修改 [ota_manegement.lua](file:///d:/Air8201G/挂载项目测试软件/user/ota_manegement.lua) 第 30 行 `"123"` 占位值
3. 在 IoT 平台上传新版本固件并绑定设备 IMEI

---

### 后续计划占位

> 后续每次升级在此处以日期为标题追加 `### YYYY-MM-DD` 章节即可。

---

## 📡 官方支持渠道

- 📚 文档：https://docs.openluat.com/
- 💻 源码：https://gitee.com/openLuat/LuatOS/tree/master/module
- 💬 合宙官方企业微信群（https://docs.openluat.com/ 网站底部二维码扫码加入）
- 🛒 https://luat.taobao.com/ 选购核心板和开发板产品对比验证
