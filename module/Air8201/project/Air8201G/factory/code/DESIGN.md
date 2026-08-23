# Air8201G-IRTU 项目 — 业务逻辑与详细设计

版本: 1.2.0
日期: 2026-06-01

## 1. 项目概述

该项目为 Air8201G-IRTU 定位器固件的应用层代码，使用 LuatOS 平台。主要职责包括设备启动与初始化、低功耗常驻运行、定位采集（LBS/GNSS）、GSensor 震动检测、4G 网络通信（含 MQTT/TCP/UDP）、文件与运维日志上传、以及与云端的双向控制交互。

核心运行模式：`MODE1`（低功耗常驻）。

主要模块（工作目录下相关文件）：
- `user/main.lua`：系统启动与任务调度入口。
- `excloud.lua`：通用云通信库（TLV 编码、getip、MQTT/TCP/UDP、文件上传、运维日志）。
- `user/excloud_module.lua`：项目级 excloud 使用封装（硬编码常量、心跳策略、回调分发）。
- 其它业务模块：`user/mygps.lua`、`user/mypower.lua`、`user/gsensor.lua`、`user/report.lua` 等（定位、电源、传感与上报逻辑）。

## 2. 业务逻辑概要

1. 启动与初始化流程（`user/main.lua`）
   - 初始化子模块：电源（`mypower`）、Gsensor（`gsensor`）、定位（`mygps`），并设置各模块就绪标志。
   - 等待网络可用（通过 `socket.adapter(socket.dft())` / `IP_READY` 事件）后，调用 `excloud_module.init()` 建立云连接。
   - 启动定时/事件上报任务（`report.start()`）。主循环只做电池采样以节省 CPU。

2. 云连接与鉴权（`excloud.lua` / `excloud_module.lua`）
   - `excloud.setup(params)`：配置设备类型、传输方式、getip 开关等并打包 `device_id_binary`。
   - `excloud.open()`：若启用 `use_getip`，先调用 `getip_with_retry()` 获取 `conninfo`（IP/SSL/port/username/password/auth_key 等）；然后根据 `transport` 建立 TCP/UDP socket 或 MQTT 客户端并触发连接。
   - 连接到服务器后，发送鉴权请求 `AUTH_REQUEST`（payload 包含 `auth_key` 与设备标识）。MQTT 模式下使用 `/AirCloud/up/<device>/auth` 主题。鉴权成功后 `is_authenticated` 置位。

3. 心跳与上报
   - `excloud_module` 提供心跳控制，默认 `HEARTBEAT_AUTO_START=true`：在 `connect_result` 成功后自动调用 `excloud.start_heartbeat()`，周期默认 300s。
   - `report` 模块在定时或事件触发时按需调用定位（LBS/GNSS）并构建上报 TLV，调用 `excloud_module.send_location/send_battery/send_system_status` 等接口发送。

4. 文件与运维日志上传
   - `excloud.getip()` 提供文件上传配置（`imginfo`/`audinfo`/`mtninfo`），`excloud.upload_image/upload_audio/upload_mtnlog` 使用这些配置通过 `httpplus` 上传。
   - 对大文件支持 ZBUFF 流式上传以减少内存峰值，上传前后发送 `FILE_UPLOAD_START` / `FILE_UPLOAD_FINISH` TLV 通知。

5. 重连与错误处理
   - 支持自动重连（`auto_reconnect`），`schedule_reconnect` 管理重连次数与策略。超过 `max_reconnect` 会触发重新 `getip` 再尝试重连。
   - 连接与消息相关的超时使用 `start_connect_timeout` / `stop_connect_timeout` 保护，失败时会清理连接并报告回调。

## 3. 数据格式与协议

- 传输消息采用自定义头 + TLV 数据格式：头部 16 字节（设备ID 8B + 序列2B + 数据长度2B + flags4B）；TLV: field_type(2B = data_type<<12 | field) + length(2B) + value。
- 数据类型由 `DATA_TYPES` 指定（INTEGER/FLOAT/BOOLEAN/ASCII/BINARY/UNICODE）。`FLOAT` 使用乘以1000 的整数编码（非 IEEE754）。
- 设备字段定义参考 `FIELD_MEANINGS`（控制/传感/设备参数/文件/运维日志等多类常量）。
- MQTT topic 约定：上行 `/AirCloud/up/<device_hex>/all|auth`，下行 `/AirCloud/down/<device_hex>/all|auth`。

## 4. 模块接口（简要）

- `excloud.setup(params)` → 初始化配置。
- `excloud.open()` / `excloud.close()` → 打开/关闭服务。
- `excloud.send(data, need_reply, is_auth_msg)` → 发送一组 TLV。
- `excloud.getip()` / `getip_with_retry()` → 从 getip 服务获取连接与上传配置。
- `excloud.upload_image/audio/mtnlog(file, name)` → 上传文件（同步或异步）。
- `excloud.on(cb)`、`excloud.set_upload_callback(cb)` → 注册事件回调与上传回调。

在项目层：
- `excloud_module.init()` 封装 `excloud.setup` + `excloud.open` 并注册事件分发。
- `user/main.lua` 通过 `excloud_module.register_callback()` 将云端消息回调转给业务函数（如 `on_excloud_message`）。

## 5. 详细运行时序（主要场景）

1. 启动 → 模块初始化 → 等待网络
   - `sys.taskInit` 在 `main.lua` 中等待 `IP_READY`，网络就绪后调用 `excloud_module.init()`。

2. 建立连接与鉴权（MQTT 举例）
   - `excloud.open()` → `getip_with_retry()` 获取 `conninfo` → 创建 `mqtt.create()` 客户端 → `connect()` → 订阅下行主题 → 发送鉴权（`AUTH_REQUEST` TLV）→ 服务器返回 `AUTH_RESPONSE`。

3. 心跳与上报
   - `excloud.start_heartbeat()` 周期性调用 `excloud.send()` 发送 TIMESTAMP TLV。

4. 文件上传
   - 上报请求触发 `excloud.getip()`，获取 `imginfo/audinfo` → `excloud.upload_image()` 调用 `do_upload_file()` → 使用 `httpplus` POST multipart 或 ZBUFF 流上传。

## 6. 配置与敏感项管理

- 运行时配置点在 `excloud.setup(params)`，包含 `device_type, transport, auth_key, use_getip, ssl` 等。
- 当前发现风险：`AUTH_KEY` 在 `user/excloud_module.lua` 被硬编码为常量 `AUTH_KEY`。必须避免将项目密钥写死在源码中，应改为：
  - 从受限配置区读取（设备安全分区、或由引导器注入）
  - 或在运行时通过外部流程注入（如 OTA 私有配置或工厂写入）

## 7. 安全与隐私注意事项（建议）

1. 移除或掩码日志中输出的敏感信息：`auth_key`、`password`、`udp_auth_key`、MQTT 密码等。`excloud.lua` 若打印这些字段请删除或掩码。
2. 强制 TLS 验证：确认 `httpplus` 与 MQTT 的 TLS 模式进行 CA 验证，必要时增加证书钉扎或客户端证书校验（`client_cert`/`client_key` 支持）。
3. 在 `excloud.close()` 中清理回调引用：将 `callback_func = nil`、`upload_callback = nil`，并退订 `IP_READY` 以避免内存/回调泄露。
4. 上传内容要有访问控制与审计：确保上传 URL 与响应不会导致敏感日志外泄，必要时加密敏感文件再上传。

## 8. 错误处理与鲁棒性建议

- 统一处理 `json.decode`/`httpplus.request` 的错误路径并记录可追踪但不包含敏感信息的错误码。
- `getip` 失败策略已实现重试，但应避免无限重试导致耗电；建议在重试策略中加入退避算法和最大累计重试窗口。
- 对 TLV 编解码的边界检查（例如 `parse_message` 中 offset 与长度判断）已存在，但应增加错误日志计数器以便远端诊断。

## 9. 资源与性能

- ZBUFF 流式上传用于减少峰值内存分配，上传完成后调用 `collectgarbage("step", N)` 来释放内存。需在低内存场景下增加预估与监控。
- rxbuff 初始大小为 2048 字节，若高吞吐或大 TLV 场景需合理调整 `zbuff`/`mqtt_rx_size` 参数。

## 10. 测试建议

- 单元/集成测试要覆盖：TLV 编解码边界、`getip` 成功/失败、MQTT 订阅/发布流程、文件上传（包括 ZBUFF 与普通文件）、重连与断线场景。
- 在仿真或 CI 中模拟网络波动、getip 返回错误与大文件上传以验证内存与重连策略。

## 11. 建议修复清单（可作为 PR 列表）

1. 移除 `user/excloud_module.lua` 顶部硬编码 `AUTH_KEY`，改为从安全配置或运行时参数注入。
2. 在 `excloud.lua` 的日志打印处掩码 `auth_key`/`password`/`udp_auth_key`（例如只显示前后 2 位或固定 `****`）。
3. `excloud.close()` 中将 `callback_func = nil`、`upload_callback = nil` 并退订 `IP_READY`（若有订阅句柄）。
4. 明确 `ssl`/`ssl_config` 行为：在 `excloud.open()` 中加入对 `ssl_config.ca_verify` 或类似开关的显式校验。
5. 为 `getip` 与上传增加更细粒度的错误统计与退避策略。

## 12. 附录：关键文件参考

- 主入口：`user/main.lua`
- 云库：`excloud.lua`
- 项目封装：`user/excloud_module.lua`
- 上传流与运维日志：`excloud.lua` 中 `do_upload_file`, `upload_mtn_log_files`

---
文档生成：由快速审查得出，若需我将按照以上建议自动生成 PR（修改点：移除硬编码密钥、掩码日志、清理回调）。请确认是否继续自动修复实现。
