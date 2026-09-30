# Air8602 智能寄存柜方案

## 一、项目简介

1. **成品整机**：Air8602（主控 Air1602）+ 10.1 寸 1024×600 RGB 屏（HX8282）+ GT911 电容触摸，界面全部用 AirUI 绘制。
2. **四个入口**：取件（取件码开柜）/ 管理（管理员密码）/ 存件（小程序码）/ 帮助；本工程不含人脸识别与 FOTA。
3. **联网**（按硬件版本二选一）：WiFi 版本板用 Air6205（UART3 airlink，2M）；4G 版本板用 Air780ER2（UART3 airlink，`4G_RST`=GPIO58）。
4. **云端**：AirCloud 长连接（excloud，自动识别设备类型）做鉴权、控制命令（`save,柜号,取件码`）、事件 TLV 上报；业务数据走 HTTP（`api.luatos.com/iot/smart_locker`）。
5. **本地留痕**：开箱/关箱/存件/取件事件写流水 CSV（TF 卡，未挂载回退 `/ram`），断网先入补传队列，联网自动补录。
6. **语音播报**：内置 DAC + PA（GPIO73 低电平使能），开机播报欢迎语，播放失败自动重试 3 次。

## 二、功能入口与业务流程

| 入口 | 触发消息 | 流程 | 关键点 |
|---|---|---|---|
| 取件 | `OPEN_EXPRESS_RECEIVE_WIN` | 键盘输入取件码 → 本地映射（内存 + fskv）查柜号 → `OPEN_BOX` 开柜 → 成功后删除该取件码 | 开柜结果弹窗提示 |
| 存件 | `OPEN_EXPRESS_SEND_WIN` | 显示服务器下发的小程序码  |
| 管理 | `OPEN_COURIER_MANAGEMENT_WIN` | 管理员密码 → 管理中心 | 查看所有箱子状态 / 指定柜号开箱（二次确认）/ 公众号二维码 |
| 帮助 | `OPEN_EXPRESS_HELP_WIN` | 使用说明页 | — |

**服务器下发存件**：AirCloud 收到 `save,柜号,取件码` → 存映射（`pickup_code_map` + fskv `pickup_code_{code}`）→ 回 `CONTROL_RESPONSE`；`main.lua` 另保留 3 条本地模拟命令（柜 1/2/3，`aircloud.test_send_save_command`）用于演示，对接真机后可删掉这 3 行。

**服务器接口（HTTP）**：`/init`（柜子初始化，首次开机自动做一次，fskv 记标志）、`/status`（柜子状态）、`/sync_status`、`/face_store`、`/pickup`、`verify_pickup_code`、小程序码 `wx_gen_app_code`；取件窗口当前走本地校验，服务器接口保留在 `ecbusiness` 供其它流程调用。

## 三、目录结构

```
Air8602_deposit_cabinet/
├── readme.md
├── res/                            # 界面图片（jicungui/cunjian/qujian/guanli/bangzhu…）
└── user/
    ├── main.lua                    # 入口：模块加载 + 初始化任务（挂卡/校时/开窗/欢迎语）
    ├── config.lua                  # 集中配置（server/locker/serial/rs485/network/system/business/aircloud/sd/report）
    ├── hardware.lua                # GPIO 上电时序 + LCD + AirUI + 背光 + 触摸 + 密度缩放
    ├── netdrv_wifi.lua             # WiFi 网卡（Air6205/airlink，当前使用）
    ├── network_4g.lua              # 4G 网卡（备用，Air780ER2/airlink）
    ├── uart_controller.lua         # 485 锁控板通讯（开锁/读状态/主动上报）
    ├── aircloud.lua                # AirCloud：鉴权/控制命令/取件码映射/事件 TLV/取件包
    ├── server_api.lua              # 服务器 HTTP 接口 + 设备号获取
    ├── ecbusiness.lua              # 业务逻辑：柜子初始化/存取件/取件码校验
    ├── event_reporter.lua          # 事件流水 CSV + 云端事件上报 + 断网补传
    ├── sd_card.lua                 # TF 卡挂载（SPI1，失败回退 /ram）
    ├── ectts.lua                   # TTS 播报（队列 + 后台任务，失败重试 3 次）
    ├── ecabinet.lua                # 主窗口（4 入口）
    ├── ecsend.lua / ecrecv.lua     # 存件窗口 / 取件窗口
    ├── eccourier.lua               # 管理员密码
    ├── eccourier_detail.lua        # 管理中心（箱子状态/开箱/公众号二维码）
    ├── ecboxstatus.lua / echelp.lua# 箱子状态页 / 帮助页
    ├── tp_gt911.lua                # GT911 触摸驱动
    └── lcd_hx8282_10in.lua         # HX8282 10.1 寸屏驱动
```

> `require` 按文件名解析。`excloud` / `exnetif` / `exwin` / `exaudio` 不在工程目录内，烧录时要附加默认扩展库，否则 `require` 失败。

## 四、硬件引脚（主控 Air1602）

| 功能 | 接口 / GPIO | 说明 |
|---|---|---|
| RGB LCD | HX8282，RST=GPIO15 | 1024×600，总线 50MHz，背光 GPIO13；**无 LCD_EN**（代码里不传 `pin_pwr`） |
| 电容触摸 | GT911，I2C PORT1 | RST=GPIO72、INT=GPIO51，下降沿触发 |
| 485 锁控板 | UART1，9600 8N1 | 收发方向脚 GPIO65（`uart.setup` 第 8 参数自动切换） |
| WiFi 模组（WiFi 版本板） | UART3 airlink，2M | Air6205，仅支持 2.4G 热点；WiFi_RST=GPIO64（8602 默认 4G 版，用 WiFi 需改电阻 31→32、33→34）；**脚本不做任何 GPIO 操作**（GPIO57 是 485_EN2，与 WiFi 无关） |
| 4G 模组（4G 版本板） | UART3 airlink | Air780ER2，`4G_RST`=GPIO58（拉低） |
| TF 卡 | SPI1 | CS=GPIO8，SD_EN=GPIO74（高电平使能） |
| 音频功放 | GPIO73 | `AUDIOPA_EN` 低电平打开，内置 DAC 输出 |

**上电时序（hardware.power_on，按顺序、带延时）**

| 顺序 | 引脚 | 动作 |
|---|---|---|
| 1 | GPIO42 | 拉高，延时 50ms |
| 2 | GPIO43 / GPIO52 / GPIO56 / GPIO57 | 依次拉高（43 为背光；57 是 485_EN2（第二路隔离 485 使能），与 WiFi/LCD 无关） |

> GPIO65 是 485 方向脚，**不能**在上电时序里 gpio.setup（会抢走该脚、破坏 uart 方向控制），这也是 SD_EN 用 GPIO74 而不是 GPIO65 的原因。

## 五、柜子与业务规则

| 项目 | 取值 | 说明 |
|---|---|---|
| 柜子数量 | 7（7 路锁控板） | 首次开机自动 `POST /init` 上报柜子配置，fskv 记 `locker_initialized` 标志 |
| 取件码校验 | 本地校验 | `pickup_code_map`（内存）+ `fskv pickup_code_{code}`，无错误锁定机制 |
| 取件后处理 | 删除该取件码映射 | 开柜成功后再删；`aircloud.delete_pickup_code` |
| 开锁兜底 | 3 秒无应答按失败 | 未收到锁板 0x8A 反馈帧即上报 `success=false` |
| 事件 ID | 设备号 + fskv 预占自增号 | 号段预占 1000 条，把“每条一次 flash 写”降为“每 1000 条一次” |

## 六、出厂配置基线（user/config.lua）

| 配置项 | 值 | 说明 |
|---|---|---|
| PROJECT / VERSION | `DEPOSIT_CABINET` / `001.999.001` | 与 8601 同名，注意区分工程目录 |
| 服务器 | `api.luatos.com:443` + `/iot/smart_locker` | 超时 5000ms，重试 3 次 / 间隔 2000ms |
| 设备号 | 由 `server_api.get_device_id()` 生成 | 主控 MCU 唯一 ID → WiFi MAC → IMEI（本工程 config 无 `device` 段，需要固定号时自行添加） |
| AirCloud | 无需配 auth_key | 新版 excloud 自动识别 `device_type`；传输 TCP，自动重连 10s × 5，开启运维日志 |
| TF 卡 | `sd.pin_cs=8`，`sd.pin_en=74` | SPI1，24MHz，挂载失败回退 `/ram` |
| 事件上报 | `report.enabled=true` | 流水目录 `/sd/log`（保留 30 天）；关箱轮询 5s / 超时 60s；补传队列 `/sd/log/pending_upload.jsonl`（上限 500 条，重试 30s） |
| 时区 | `system.time_zone = 8` | 开机 SNTP 校时后生效 |
| 风险开关 | `locker.ignore_server_status` / `ignore_local_occupied` / `ignore_server_reject` | 当前均为 **true**（测试态），生产必须改 **false** |

## 七、数据上报与本地流水

**本地流水（始终写，掉电不丢）**：`/sd/log/cabinet_event_YYYYMMDD.csv`，SD 未挂载回退 `/ram/log`。

| 列 | 说明 |
|---|---|
| 时间, 事件, 说明, 事件ID, 柜号, 设备号, 业务标识, 附加信息, 照片, 结果 | 事件类型：OPEN(开箱)/CLOSE(关箱)/DEPOSIT(扫码存件)/PICKUP(取件码取件)；写盘在独立协程里异步做，SD 慢/坏块不阻塞开柜与界面 |

**云端上报（长连接 TLV，受 `report.enabled` 控制）**

| 场景 | 字段 | 说明 |
|---|---|---|
| 事件 | `BUSINESS_SN(1282)` + `TIMESTAMP(1280)` | 整条事件串用 BUSINESS_SN 承载，时间戳用 TIMESTAMP；事件 ID = 设备号 + fskv 预占自增号（补传与直传同一 ID，云端可幂等去重） |
| 存件包 | `BUSINESS_SN = "save,柜号,时间戳,包大小"` + `TIMESTAMP` | `aircloud.report_send_package` |
| 取件包 | `BUSINESS_SN = "receive,柜号,时间戳,取件码"` + `TIMESTAMP` | `aircloud.report_receive_package` |

> 本工程无照片上传通道（`upload_photo` / `upload_image` 只在 8601 使用）。`OPERATION_TYPE` / `BOX_NUMBER` / `PASSWORD` / `PACKAGE_SIZE` 在固件 `excloud.FIELD_MEANINGS` 里不存在，故统一用 `BUSINESS_SN + TIMESTAMP` 承载。

**断网补传**：事件先入 `/sd/log/pending_upload.jsonl`（上限 500 条，超出丢最旧），联网后按 30s 轮询补录，云平台连上会立刻补一次；`report.enabled=false` 时只写本地 CSV 并清掉残留队列。

**关箱判定**：锁控板 0x81 主动上报为主，另配 5 秒轮询读状态 + 开箱 60 秒超时按估算记录（`config.report.box_close`）。

## 八、AirCloud 下行命令

| 命令 | 格式 | 行为 |
|---|---|---|
| 存件 | `CONTROL_COMMAND` 或 `RANDOM_DATA` = `save,柜号,取件码` | 存入 `pickup_code_map` + fskv，并回 `CONTROL_RESPONSE`：“开柜码已保存，柜子N准备完毕” |
| 本地测试 | `aircloud.test_send_save_command(柜号, 取件码)` | `main.lua` 开机调用 3 次（柜 1/2/3），仅用于演示，对接真机后删掉这 3 行 |

> 与 8601 的区别：本工程**没有**服务器存件命令轮询（`/status` + `store_ack`）这一段，存件依赖 AirCloud 下发命令或小程序扫码侧完成。

## 九、485 锁控板协议（自定义，9600 8N1）

| 功能 | 帧格式（hex） | 反馈 |
|---|---|---|
| 开锁 | `8A 板地址 锁地址 11 BCC` | `8A 板 锁 状态 BCC`（`0x11`=成功，`0x00`=失败） |
| 读全部锁状态 | `80 板地址 00 33 BCC` | `80 板 [状态字节…] 33 BCC` |
| 读单锁状态 | `80 板地址 锁地址 33 BCC` | `80 板 锁 状态 BCC` |
| 主动上报 | — | `81 板地址 锁地址 状态 BCC`（关箱判定来源之一） |

> BCC = 各字节异或；板地址由锁控板拨码决定（当前 `BOARD_ADDR=0x01`）。实际使用请按锁控板厂家协议调整 `user/uart_controller.lua`。

## 十、使用说明

1. **烧录**：Luatools 烧工程目录（`user/` + `res/`，core = Air1602）。脚本依赖 `excloud`/`exnetif`/`exwin`/`exaudio`，需附加默认扩展库。
2. **上电自检**：开机日志应出现 `DEPOSIT_CABINET 001.999.001` → `模拟服务器下发存件命令: save,1,665501` → `系统初始化完成` → `主窗口打开成功` → `收到读取锁状态请求`，以及 `TTS 音频初始化成功`、`SD 卡挂载成功`、`事件记录初始化`。
3. **日常操作**：主界面 4 入口（取件 / 管理 / 存件 / 帮助）；取件码开柜结果用弹窗提示；开机播报欢迎语。
4. **管理页**（需管理员密码）：查看所有箱子状态 / 指定柜号开箱 / 公众号二维码。
5. **生产前必做**：确认硬件版本与 `main.lua` 里的网卡选择一致（WiFi 版 `require "netdrv_wifi"` / 4G 版 `require "network_4g"`，WiFi 版还需改 `netdrv_wifi.lua` 的 ssid/密码）；`config.locker` 三个测试开关改 `false`；删掉 `main.lua` 里 3 条 `test_send_save_command`；替换 `config.server` 为现场服务器。
6. **调试技巧**：取件码映射可直接打印 `aircloud.pickup_code_map`；要复位柜子初始化标志就清 fskv 的 `locker_initialized`。
7. **常见问题**

| 现象 | 原因 / 处理 |
|---|---|
| 点了开箱没反应 | 锁板未回 0x8A 反馈帧，3 秒后按失败弹出；查 485 接线与板地址 |
| 输入取件码提示错误 | 取件码是本地映射（AirCloud `save` 命令或测试接口写入），服务器侧下单不会自动同步到本机 |
| 事件时间戳不对 | RTC 掉电不保存，开机需联网 SNTP 校时；未同步时时间会停在 2020-01-01 |
| 事件/照片文件不在 SD | SD 未挂载回退 `/ram`（掉电丢），日志有提示；检查 CS=GPIO8、SD_EN=GPIO74 |
| TTS 不响 | 需联网做语音合成；PA=GPIO73 低电平使能；播放失败会自动重试 3 次 |
| 二维码显示默认码 | 服务器 `wx_gen_app_code` 未返回有效 JPEG（已兼容非 16 倍数尺寸），或网络未就绪 |
