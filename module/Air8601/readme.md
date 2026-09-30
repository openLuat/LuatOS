# Air8601 智能寄存柜（刷脸存取 + 485 锁控 + AirCloud + 语音播报 + FOTA）

## 一、项目简介

1. **成品整机**：Air8601（主控 Air1601）+ 10.1 寸 1024×600 RGB 屏（HX8282）+ GT911 电容触摸，界面全部用 AirUI 绘制。
2. **四种存取路径**：刷脸存件 / 刷脸取件（AirCAMERA_1034：UART2 识别 + USB UVC 预览）、扫码存件（小程序码）、取件码取件、服务器下发存件命令（AirCloud 控制命令或 `/status` 轮询）。
3. **联网 + 自愈**（按硬件版本二选一）：WiFi 版本板用 Air6205（UART3 airlink，2M，EN=GPIO57 低电平使能）；4G 版本板用 Air780ER2（UART3 airlink，`4G_RST`=GPIO64）。WiFi 板断网 30s 未恢复 → 硬复位 6205，再 15s 仍无网 → 业务空闲时整机重启（≤5 次）。
4. **云端双通道**：AirCloud 长连接（excloud）做鉴权、控制命令、事件 TLV、刷脸照片上传；业务数据走 HTTP（`api.luatos.com/iot/smart_locker`）。
5. **本地留痕**：事件流水 CSV + 留底照片存 TF 卡（未挂载回退 `/ram`），断网事件/照片先入补传队列，联网自动补录。
6. **运维能力**：管理页（服务器对账 / 重初始化柜子 / 清空本地记录 / 人脸管理 / 指定开箱 / 公众号二维码）、TTS 语音播报、按需 FOTA（libfota3 + SHA256 + 开机版本比对上报）。

## 二、功能入口与业务流程

| 入口 | 触发消息 | 流程 | 关键点 |
|---|---|---|---|
| 刷脸存件 | `OPEN_FACE_DEPOSIT_WIN` | 开窗启动 UVC 预览 → 画面就绪后人脸注册 → 选空闲柜 → `/face_store` 登记 → 开柜 → 保留最后一帧停流 | 等 `FACE_PREVIEW_READY` 才发起识别；照片留底 `/sd/photo` |
| 刷脸取件 | `OPEN_FACE_RECEIVE_WIN` | 开窗预览 → 人脸验证 → 按 `face_bind_{uid}` 找柜号 → 开柜 → 解绑 + 删对应取件码 + `/carry` | 事件与照片上云（FACE_PICKUP） |
| 取件 | `OPEN_EXPRESS_RECEIVE_WIN` | 键盘输入 6 位取件码 → 本地映射（内存 + fskv）查柜号 → `OPEN_BOX` 开柜 | 连续错 5 次锁定 60s（防爆破） |
| 存件 | `OPEN_EXPRESS_SEND_WIN` | 显示服务器下发的小程序码 `/qr_code_v288.jpeg` | 文件无效自动重新下载，失败回退默认码 |
| 管理 | `OPEN_COURIER_MANAGEMENT_WIN` | 管理员密码 → 管理中心 | 见下方“管理页功能” |
| 帮助 | `OPEN_EXPRESS_HELP_WIN` | 使用说明页 | — |

**服务器下发存件（无人值守）**：AirCloud 收到 `save,柜号,取件码` 直接存映射并回响应；另有 10s 轮询 `POST /status` 取存件命令 → 开柜 → 存映射 → `POST /store_ack` 确认（FOTA 下载中或业务繁忙时跳过本轮）。

**管理页功能**：查看所有箱子状态 / 人脸管理 / 指定柜号开箱（1-30，二次确认）/ 服务器对账（`POST /sync` 上报设备侧空闲柜号）/ 重初始化柜子（`POST /init`）/ 清空本地记录（清 fskv 的 `pickup_code_*`、`face_bind_*`）/ 公众号二维码。

## 三、目录结构

```
Air8601_deposit_cabinet/
├── readme.md
├── lib/                            # 随工程走的扩展库
│   ├── libfota3.lua                # 官方整机成品 FOTA 库（原版，version 202609151040）
│   └── exfacecam.lua               # AirCAMERA_1034 人脸模组扩展库（本地做了小改）
├── res/                            # 界面图片（jicungui/cunjian/qujian/guanli/bangzhu…）
└── user/
    ├── main.lua                    # 入口：模块加载 + 看门狗 + 系统初始化任务
    ├── config.lua                  # 集中配置（server/device/locker/serial/rs485/fota/face/report/sd/main）
    ├── hardware.lua                # GPIO 上电时序 + LCD + AirUI + 背光 + 触摸 + 密度缩放
    ├── netdrv_wifi.lua             # WiFi 网卡（Air6205/airlink）+ 断网自愈
    ├── network_4g.lua              # 4G 网卡（备用，Air780ER2/airlink）
    ├── uart_controller.lua         # 485 锁控板通讯（开锁/读状态/主动上报）
    ├── aircloud.lua                # AirCloud：鉴权/控制命令/取件码映射/事件 TLV/照片/存件命令轮询
    ├── server_api.lua              # 服务器 HTTP 接口（init/status/store_ack/face_store/pickup/carry…）
    ├── ecbusiness.lua              # 业务逻辑：选柜分配/存取件/刷脸存取/对账/清记录
    ├── event_reporter.lua          # 事件流水 CSV + 云端事件/照片上报 + 断网补传
    ├── sd_card.lua                 # TF 卡挂载（SPI1，失败回退 /ram）
    ├── audio_tts.lua               # TTS 播报（DAC + LM4871）
    ├── fota_manager.lua            # FOTA 封装（业务保护 + 状态维护）
    ├── ecabinet.lua                # 主窗口（6 入口，点击带语音）
    ├── ecsend.lua / ecrecv.lua     # 存件窗口 / 取件窗口
    ├── eccourier.lua               # 管理员密码
    ├── eccourier_detail.lua        # 管理中心（对账/重初始化/清记录/开箱/人脸管理入口）
    ├── ecboxstatus.lua / echelp.lua# 箱子状态页 / 帮助页
    ├── ecface.lua                  # 刷脸窗口与流程编排
    ├── ecface_manage.lua           # 人脸管理界面
    ├── face_manager.lua            # 人脸注册/验证/列表/删除 + 柜号绑定（fskv）
    ├── face_preview.lua            # UVC 预览（airui.camera，可并行识别、停流后保留最后一帧）
    ├── face_photo.lua              # 抓帧 JPEG 留底（/sd/photo）
    ├── face_demo.lua               # 人脸单板验证 demo（不在业务路径）
    ├── tp_gt911.lua                # GT911 触摸驱动
    └── lcd_hx8282_10in.lua         # HX8282 10.1 寸屏驱动
```

> `require` 按文件名解析（子目录只是组织层级）。`excloud` / `exnetif` / `exwin` / `exaudio` / `excamera` 不在工程目录内，烧录时要附加默认扩展库，否则 `require` 失败。

## 四、硬件引脚（主控 Air1601）

| 功能 | 接口 / GPIO | 说明 |
|---|---|---|
| RGB LCD | HX8282，RST=GPIO15 | 1024×600，总线 50MHz，背光 PIN43/GPIO13 |
| 电容触摸 | GT911，I2C PORT1 | RST=GPIO56、INT=GPIO51，下降沿触发 |
| 485 锁控板 | UART1，9600 8N1 | 收发方向脚 GPIO72（`uart.setup` 第 8 参数自动切换，脚本不手动控制） |
| WiFi 模组（WiFi 版本板） | UART3 airlink，2M | Air6205，EN=GPIO57 **低电平使能**，仅支持 2.4G 热点 |
| 4G 模组（4G 版本板） | UART3 airlink | Air780ER2，`4G_RST`=GPIO64（拉低） |
| 人脸识别模组 | UART2，115200 8N1 | AirCAMERA_1034，只走 UART |
| USB 摄像头 | USB Host | UVC 预览（320×240），模组使能 GPIO73 |
| TF 卡 | SPI1 | CS=GPIO8，SD_EN=GPIO65（高电平使能） |
| 音频功放 | GPIO74 | `AUDIOPA_EN` 低电平打开（LM4871），内置 DAC 输出 |
| I2C1 SDA | GPIO38 | 触摸总线引脚，非背光（代码里置高只为复位默认态） |

**上电时序（hardware.power_on，按顺序、带延时）**

| 顺序 | 引脚 | 动作 |
|---|---|---|
| 1 | GPIO42 | 拉高，延时 50ms |
| 2 | GPIO65 | 先拉低 100ms → 再拉高 1000ms（TF 卡供电） |
| 3 | GPIO43 | 拉高（背光，PIN43/GPIO13） |
| 4 | GPIO52 / GPIO56 | 拉高 |
| 5 | GPIO73 | 拉高，延时 200ms（UVC 摄像头使能） |

> GPIO57（Air6205 的 EN）**不在**上电时序里，由 netdrv_wifi.lua 单独拉低使能；不要传给 exnetif（库内部会拉高使能，导致模组被关掉）。

## 五、柜子与业务规则

| 项目 | 取值 | 说明 |
|---|---|---|
| 柜子数量 | 7（7 路锁控板） | 开机向服务器 `/init` 注册，全部按小箱型 `type=0` 上报 |
| 分配策略 | `round_robin` 1-5 轮询 | 全占用时回退 6-7（`allocation.fallback_outside`） |
| 空闲判定 | 服务器状态 + 本地占用 | 本地占用源：`pickup_code_*`（取件码）、`face_bind_*`（人脸） |
| 取件码 | 6 位，本地校验 | 连续错 5 次锁定 60 秒 |
| 人脸绑定 | `fskv face_bind_{user_id}` → 柜号 | 刷脸取件后解绑并删除对应取件码 |
| 开柜结果匹配 | 按柜号过滤 | `BOX_OPEN_RESULT` 是全局消息，非本次柜号的结果丢弃重等（避免误判开柜成功） |
| 开锁兜底 | 3 秒无应答按失败 | 未收到锁板 0x8A 反馈帧即上报 `success=false` |
| 业务繁忙门禁 | `ecbusiness.is_busy()` / `face_manager.is_busy()` | FOTA 下载/重启、网络自愈整机重启前先查 |

## 六、出厂配置基线（user/config.lua）

| 配置项 | 值 | 说明 |
|---|---|---|
| PROJECT / VERSION | `DEPOSIT_CABINET` / `001.999.001` | FOTA 的 script_name/script_version 默认取这两个值 |
| 服务器 | `api.luatos.com:443` + `/iot/smart_locker` | 超时 5000ms，重试 3 次 / 间隔 2000ms |
| 设备号 | `config.device.device_id = ""` | 留空自动生成：MCU 唯一 ID → WiFi MAC → IMEI（`server_api.get_device_id`） |
| AirCloud | `auth_key = JQtKg5M7h8HTMw8CgqMpRh77hySLlUwx` | `device_type` 按默认网卡自动取 1(4G)/2(WiFi)/4(以太网)；传输 TCP，自动重连 10s × 5，开启运维日志 |
| FOTA | `enabled=true`，`project_key=6Olgc34lgwPUOzTAXWqGbMLS1DMUPMok` | `auto=false`（按需，入口 `fota_manager.check_update()`），interval 86400s |
| 人脸 | UART2 115200，`power_pin=73`，`usb_port=1` | 预览 320×240、`mode="auto"`（预览与识别并行）、就绪兜底 6s；照片保留 30 天 |
| 事件上报 | `report.enabled=true`，`upload_photo=true` | 流水目录 `/sd/log`（保留 30 天）；关箱轮询 5s / 超时 60s；补传队列 `/sd/log/pending_upload.jsonl`（重试 30s） |
| 485 / 串口 | `rs485.pin=72`，uart1 9600 8N1 | 见 `config.serial` |
| 语音 | — | PA=GPIO74，音量 80（`audio_tts` 内部） |
| 风险开关 | `locker.ignore_server_status` / `ignore_local_occupied` / `ignore_server_reject` | 当前均为 **true**（测试态），生产必须改 **false** |
| 二维码预下载 | `main.qr_predownload = false` | 默认关闭，原因见第十节 |

## 七、数据上报与本地流水

**本地流水（始终写，掉电不丢）**：`/sd/log/cabinet_event_YYYYMMDD.csv`，SD 未挂载回退 `/ram/log`。

| 列 | 说明 |
|---|---|
| 时间, 事件, 说明, 事件ID, 柜号, 设备号, 业务标识, 附加信息, 照片, 结果 | 事件类型：OPEN(开箱)/CLOSE(关箱)/DEPOSIT(扫码存件)/PICKUP(取件码取件)/FACE_STORE(刷脸存件)/FACE_PICKUP(刷脸取件)/FACE_FAIL(刷脸失败) |

**云端上报（长连接 TLV，受 `report.enabled` 控制）**

| 场景 | 字段 | 说明 |
|---|---|---|
| 事件 | `BUSINESS_SN(1282)` + `TIMESTAMP(1280)` + `DEVICE_ID(798)` | 事件内容打包进 BUSINESS_SN 一条串；事件 ID = 设备号 + fskv 预占自增号（补传与直传同一 ID，云端可幂等去重） |
| 存件包 | `BUSINESS_SN = "save,柜号,时间戳,包大小"` + `TIMESTAMP` | `aircloud.report_send_package` |
| 取件包 | `BUSINESS_SN = "receive,柜号,时间戳,取件码"` + `TIMESTAMP` | `aircloud.report_receive_package` |
| 照片 | 文件上传通道 `excloud.upload_image` | **仅** FACE_STORE / FACE_PICKUP 带照片 |

> `OPERATION_TYPE` / `BOX_NUMBER` / `PASSWORD` / `PACKAGE_SIZE` 这些字段在固件 `excloud.FIELD_MEANINGS` 里不存在（取到 nil 会让 TLV 构造失败），因此统一用 `BUSINESS_SN + TIMESTAMP` 承载。

**断网补传**：事件与照片先入 `/sd/log/pending_upload.jsonl`（上限 500 条，超出丢最旧），联网后按 30s 轮询补录，云平台连上会立刻补一次；`report.enabled=false` 时只写本地 CSV 并清掉残留队列。

## 八、AirCloud 下行命令

| 命令 | 格式 | 行为 |
|---|---|---|
| 存件（即时） | `CONTROL_COMMAND` 或 `RANDOM_DATA` = `save,柜号,取件码` | 存入 `pickup_code_map` + fskv，并回 `CONTROL_RESPONSE`：“开柜码已保存，柜子N准备完毕” |
| 存件（轮询） | 无（设备主动） | 每 10s `POST /status`（quiet）取存件命令 → 开柜（等 3s、按柜号过滤结果）→ 存映射 → `POST /store_ack` 回执；FOTA 下载中或业务繁忙跳过本轮，失败下轮重试 |

## 九、485 锁控板协议（自定义，9600 8N1）

| 功能 | 帧格式（hex） | 反馈 |
|---|---|---|
| 开锁 | `8A 板地址 锁地址 11 BCC` | `8A 板 锁 状态 BCC`（`0x11`=成功，`0x00`=失败） |
| 读全部锁状态 | `80 板地址 00 33 BCC` | `80 板 [状态字节…] 33 BCC` |
| 读单锁状态 | `80 板地址 锁地址 33 BCC` | `80 板 锁 状态 BCC` |
| 主动上报 | — | `81 板地址 锁地址 状态 BCC`（关箱判定来源之一） |

> BCC = 各字节异或；板地址由锁控板拨码决定（当前 `BOARD_ADDR=0x01`）。实际使用请按锁控板厂家协议调整 `user/uart_controller.lua`。

## 十、使用说明

1. **烧录**：Luatools 烧工程目录（`user/` + `lib/` + `res/`，core = Air1601，音频播报需固件 ≥ V1024）。脚本依赖 `excloud`/`exnetif`/`exwin`/`exaudio`/`excamera`，需附加默认扩展库。**按硬件版本选网卡**：WiFi 版本板保持 `require "netdrv_wifi"`，4G 版本板改成 `require "network_4g"`。
2. **上电自检**：开机日志应出现 `DEPOSIT_CABINET 001.999.001` → 看门狗 → `系统初始化完成` → `主窗口打开成功` → `收到读取锁状态请求`。
3. **日常操作**：主界面 6 入口（刷脸取件/取件/管理/刷脸存件/存件/帮助），点击带语音播报；取件码 6 位，连错 5 次锁 60 秒。
4. **管理页**（入口需管理员密码）：对账 / 重初始化柜子 / 清空本地记录 / 查看箱子状态 / 指定开箱 / 人脸管理 / 公众号二维码。
5. **生产前必做**：确认硬件版本与 `main.lua` 里的网卡选择一致（WiFi 版 `netdrv_wifi` / 4G 版 `network_4g`）；把 `config.locker` 的 `ignore_server_status`、`ignore_local_occupied`、`ignore_server_reject` 全部改 `false`；替换 `config.server` 为现场服务器；确认 `config.fota.project_key`。
6. **调试技巧**：`user/face_demo.lua` 可单板验证人脸注册/识别；手动触发升级用 `fota_manager.check_update()`。
7. **常见问题**

| 现象 | 原因 / 处理 |
|---|---|
| 点了开箱没反应 | 锁板未回 0x8A 反馈帧，3 秒后按失败弹出；查 485 接线与板地址 |
| 联网后 HTTP 报 -8/-4、DNS 无应答 | 二维码是 HTTPS 大帧下载，会打爆 UART3(airlink→6205) RX FIFO 导致链路损坏 → 重启恢复；不要在开机阶段开 `main.qr_predownload` |
| 断网后一直连不上 | 脚本层无法重建 airlink 链路：netdrv_wifi 会硬复位 6205（1 次）→ 业务空闲时整机重启（≤5 次） |
| 人脸注册/识别失败 | 模组上电有 1 秒稳定等待 + 8 秒初始化看门狗；预览数据流不要常驻，并行模式帧率已压到 3fps |
| 事件/照片文件不在 SD | SD 未挂载回退 `/ram`（掉电丢），日志有提示；检查 CS=GPIO8、SD_EN=GPIO65 |
| TTS 不响 | 需联网做语音合成；PA=GPIO74 低电平使能；固件需 ≥ V1024 |
