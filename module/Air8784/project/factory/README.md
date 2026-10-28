# Air8784 出厂固件（产测 + SIP/CC 业务合一）— new_web（TCP 云通道 + TTS 播报）

本固件基于 Air8784（主控 Air780EHM + 外挂 Air1103 语音芯片），将**产测**与**SIP 通话业务**合一：整批只烧一次，产测完成后自动进入业务模式。业务逻辑由 AirCloud 后台（`https://iot.luatos.com/ai_app/luatos/8786_SIP/index.html`）下发 SOS 通话配置（`sos_mode` + 号码），设备保存后通过本机按键发起/停止通话。


## 一、项目简介

1. **产测 + 业务合一**：开机按 `fskv` 返工标记 → `fskv` 首测保护标记 `model_firsttest` → OTP1（型号/硬件版本/IMEI）三级分流。裸板（无标记且 OTP1 为空）自动进产测并写 `model_firsttest`；首测中途看门狗 / `RST#` / 掉电复位后凭该标记仍回产测，避免写号后误入业务模式；`TEST_DONE#` 写 OTP1（PROD/PCB/IMEI）并删 `model_firsttest` 后重启进业务模式；有返工标记 → 进返工产测。产测完成后重启，进业务模式。
2. **一台设备只保存一套当前 SOS 通话配置**（`sos_mode` + 号码）。SOS 模式分为 `sip`（单 SIP 顺序拨打）/ `sip_cc`（SIP 不通转手机卡）/ `cc`（直接手机卡）/ `sip_grade`（分组逐级拨打）；固件内部归一为 `single`（单 SIP）/ `phone`（SIP_CC 桥接）运行分支，同一时间只加载一套通话与音频模块。
3. **业务参数来自网页**：由 AirCloud 后台（`https://iot.luatos.com/ai_app/luatos/8786_SIP/index.html`）经 `set_config` 下发 SOS 通话配置，设备持久保存后按配置执行。
4. **AirCloud 收发**：TCP 长连接上报状态快照；下发的 JSON 命令经 `cloud/` 解析；兼容旧文本短命令（`version` / `update`）经 Tag19 下发、`version` 经 Tag1027 回包。
5. **FOTA**：libfota3，开机检测 + 每 8 小时自动检测 + 网页「固件更新」一键升级（或云端 `update` 命令触发）；升级包由合宙按设备标识提供。

![Air8784 整机外观：主控板 + SIP 通话终端（SOS 紧急求助键 / 左侧红键）](https://docs.openluat.com/air8784/product/images/air8784_hardware.png)


## 二、启动模式

| 模式 | 触发条件 | 加载模块 | 业务 |
|---|---|---|---|
| 产测 · 返工产测 | 有 `fskv["model_retest"]` 返工标记 | `factory.lua` | USB VUART_0 响应产测指令 |
| 产测 · 首次产测 | 无返工标记 且 OTP1 为空（PROD 未写） | `factory.lua` | USB VUART_0 响应产测指令（进入前写首测保护标记） |
| 产测 · 首测中途复位 | 无返工标记 且 有 `model_firsttest` | `factory.lua` | 凭首测保护标记仍回产测，避免写号后误入业务 |
| 业务 · 单 SIP | 无返工标记 且 OTP1 有值 + 运行模式 `single`（sos_mode=`sip`） | `task/task_main` → `single/` | 单 SIP 顺序拨打（SOS 设置「SIP」） |
| 业务 · SIP_CC | 无返工标记 且 OTP1 有值 + 运行模式 `phone`（sos_mode=`sip_cc`/`cc`） | `task/task_main` → `cc/` | SIP↔手机(VoLTE) 桥接（SOS 设置「SIP_CC」/「CC」） |
| 调试 BOOT_MODE | `main.lua` 顶部常量 | — | `auto`(默认)/`normal`(强制业务)/`factory`(强制产测) |

- 分流顺序（`main.lua` `decide_mode`）：`fskv` 返工标记 → `fskv` 首测保护标记 `model_firsttest` → OTP1（型号/硬件版本/IMEI）。返工标记优先；其次首测保护标记（首测中途复位后回到产测）；最后按 OTP1 是否有值决定产测或业务。裸板（无标记且 OTP1 为空）进产测前自动写 `model_firsttest`。
- 业务分支由 `task/task_runtime.lua` 读 `fskv["sip_task_v1"]` 的 `runtime_mode`（`single`/`phone`）决定，缺省为 `phone`。网页经 `set_config` 下发 `sos_mode`（sip / sip_cc / cc / sip_grade），由 `cloud/aircloud_settings.lua` 归一化后写入该记录（含兼容旧字段 `task` / `modes`）。正常模式仅注册 `MODEL_RETEST` 一条产测指令（返工用）。
- 运行模式（single/phone）由 `sos_mode` 经归一化映射决定，切换需固件具备 `cc.setBridge` 和 `rtos.reboot`，否则只提供 `phone` 模式；`set_mode` 命令仍保留用于单 SIP/SIP_CC 分支切换与传输切换（兼容）。


## 三、目录结构

```
factory/
├── README.md
├── user/
│   ├── main.lua                       # 入口：按 fskv 返工标记 → 首测保护标记 → OTP1 分流 产测/业务；FOTA 启动；全局定义
│   ├── factory/                       # 产测 + 返工
│   │   ├── factory.lua                #   产测模式（含返工产测）
│   │   └── retest.lua                 #   返工标记 + MODEL_RETEST 指令 + 首测保护标记（产测与正常模式共用 USB VUART_0）
│   ├── cloud/                         # AirCloud TCP 云通道（IoT 平台后台）
│   │   ├── aircloud_tcp_adapter.lua   #   TCP 适配层（封装上游 excloud，业务侧重连/退避/关机门控）
│   │   ├── aircloud_protocol.lua      #   v1 上报/下发协议封装（分片、字段、SOS 状态）
│   │   ├── aircloud_settings.lua      #   配置后端（sos_mode/号码归一化，持久化到 fskv）
│   │   ├── sos_config.lua             #   SOS 号码/模式纯校验，无硬件与存储副作用
│   │   └── task_cloud.lua             #   统一收发入口（保留旧文本协议、远程 TTS、FOTA 触发）
│   ├── audio/                         # 提示音与 TTS 播报
│   │   ├── business_voice.lua         #   TTS 播报引擎（远程 play_tts / 配置变更 / 开机完成 / 就绪提示）
│   │   ├── call_voice.lua             #   通话相关播报
│   │   ├── task_voice.lua             #   SOS 通话提示音（替代原 .pcm）
│   │   └── task_voice_config.lua      #   提示音配置
│   ├── task/                          # 共用：网页 SOS 配置 / 云端 / 按键 / 语音 / 共用配置
│   │   ├── task_main.lua              #   业务入口（按运行模式加载分支）
│   │   ├── task_runtime.lua           #   运行模式选择
│   │   ├── task_engine.lua            #   SOS 通话校验 / 状态机 / 顺序拨打
│   │   ├── task_adapter.lua           #   分支适配 / 跨模式重启 / 主灯
│   │   ├── task_keys.lua              #   按键（SOS / UP）
│   │   └── sip_config.lua             #   共用 SIP + 硬件配置
│   ├── single/                        # 单 SIP 分支
│   │   ├── single_app.lua             #   业务状态机（注册/拨号/接听/挂断）
│   │   ├── single_audio.lua           #   Air1103 音频（PCM 上下行）
│   │   ├── single_config.lua          #   单 SIP 配置（复用 sip_config 账号）
│   │   └── incoming_answer.lua        #   来电接听策略
│   ├── cc/                            # SIP_CC 桥接分支
│   │   ├── cc_app.lua                 #   启动流程（音频→SIP→VoLTE→心跳）
│   │   ├── cc_sip.lua                 #   SIP 半边状态机
│   │   ├── cc_main.lua                #   蜂窝(VoLTE) 半边状态机
│   │   ├── cc_bridge.lua              #   两侧桥接协调器（引用 incoming_answer）
│   │   ├── cc_phone_route.lua         #   SIP 来电转拨号码读取
│   │   ├── cc_incoming_round.lua      #   SIP 来电手机顺序轮拨
│   │   └── cc_audio.lua               #   CC 分支本地音频初始化
│   ├── netdrv/
│   │   └── netdrv_4g.lua              # 4G 网卡
│   ├── ota/
│   │   └── update.lua                 # FOTA 封装（libfota3）
│   └── certs/
│       └── sip-ca.pem                 # SIP over TLS 的 CA 证书（烧录到 /luadb/sip-ca.pem）
└── lib/                               # 内置扩展库（air1103 / exaudio / httpplus；exsip / excloud 仍取自 script/libs）
    ├── air1103.lua                    #   Air1103 语音芯片驱动
    ├── exaudio.lua                    #   音频/录音/播放/桥接
    └── httpplus.lua                   #   HTTP 辅助
```

> 子目录仅为组织层级：LuatOS `require` 按**文件名**解析，文件名在工程内必须全局唯一；电脑端子目录不保留到设备，烧录时按文件原名落入 `/luadb/`。


## 四、硬件引脚（主控 Air780EHM）

| 功能 | GPIO / 接口 | 说明 |
|---|---|---|
| 主 LED | GPIO24 | 通话/来电/拨号中常亮，空闲熄灭 |
| SMS 灯 | GPIO26 | 产测三灯同步 |
| 网络灯 | GPIO27 | — |
| SOS 按键 | GPIO20 | 上拉、下降沿；执行 SOS 通话 / 接听 |
| UP 按键 | GPIO21 | 上拉、双沿；长按(≥1s)挂断，短按预留 |
| Air1103 供电 | GPIO22 | 拉高供电（`single_config.audio.power_gpio`） |
| VREF | GPIO23 | 上拉参考电压，开机常开 |
| 语音芯片 | UART1 | Air1103，固定 2M 波特率，仅 PCM |


## 五、演示功能

| 场景 | 网页入口 | SOS 模式 | 运行分支 |
|---|---|---|---|
| 设备与 SIP 软终端 / 另一台设备通话 | 设备设置 → SOS 设置「SIP」 | sip | single |
| 按顺序呼叫多个 SIP 号码 / 设备 | 设备设置 → SOS 设置「SIP」（多个号码） | sip | single |
| SIP 呼叫失败转手机卡拨打 | 设备设置 → SOS 设置「SIP_CC」 | sip_cc | phone |
| 直接用工信手机卡拨打 | 设备设置 → SOS 设置「CC」 | cc | phone |
| 分组逐级拨打（低级拨上级） | 分组管理 + SOS 设置「分组管理」 | sip_grade | 映射为 single/phone |

> 旧版「双设备互通 / 多设备轮拨 / 设备与手机」三类任务，已合并为新版 SOS 四通道：pair≈sip（单/多号码顺序拨打），phone（蜂窝）≈ cc / sip_cc。

- SIP 通道最多 **3 个**号码、按顺序呼叫；SIP_CC / CC 通道最多 3 个手机号。每个目标等待接听时间固定 **30 秒**（与旧轮拨一致）。
- 顺序拨打过程中，未接通的目标结束后才会尝试下一目标；一旦某个目标接通，本轮后续不再继续拨打其他目标。
- **网页下发配置不会自动开始通话**：按设备 SOS 键触发当前 SOS 模式拨打，UP 键（长按 ≥1s）停止通话；single 分支收到来电时，SOS 用于接听。
- SOS 配置保存并就绪后，本机 TTS 播报“任务已生效”；无主动配置（纯接收）的设备在运行模式切换就绪后，播放两声短音（详见第八章）。


## 六、SIP 账号与通话规则

### 6.1 账号约定

| 对象 | SIP 账号 |
|---|---|
| 设备自身 | 设备的 15 位 IMEI 后追加 `0` |
| 该设备对应的软终端 | 同一 IMEI 后追加 `1` |
| 网页选择其他设备时 | 选择其 15 位 IMEI，设备侧自动转换为 IMEI 后追加 `0` |

- 服务器默认 `cc.luatos.com:8910`（密码 `123456`），以 `task/sip_config.lua` 实际配置为准。
- 手机呼入时设备呼叫的 SIP 对端由 `sip_config.remote_sip_uri` 决定（默认 `sip:IMEI+1@cc.luatos.com`）；修改账号约定后需一并核对。

![SIP 账号映射：设备用 IMEI+0，对端软终端用 IMEI+1](https://docs.openluat.com/air8784/product/images/img_06.png)

### 6.2 配置手机或电脑 SIP 软终端

| 参数 | 填写内容 |
|---|---|
| 用户名 / 注册账号 | 本设备 IMEI 后追加 `1` |
| 认证用户名 | 按服务器要求填写，通常与注册账号一致 |
| 密码 | 实际分配的 SIP 密码 |
| SIP 服务器 / 域名 | `cc.luatos.com` |
| 端口 | `8910` |
| 传输协议 | 按软终端和服务器配置选择 TCP 或 UDP |

不同软终端字段名称略有差异；MicroSIP 可在代理服务器字段填 `cc.luatos.com:8910`。软终端注册成功后，呼叫“设备 IMEI 后追加 0”即可呼叫该设备。软终端账号不作为 AirCloud 设备参与模式准备。

![MicroSIP 拨号盘与「编辑账户」页：服务器 cc.luatos.com:8910、用户名 IMEI+1、传输 UDP](https://docs.openluat.com/air8784/product/images/img_07.png)

![Linphone 拨号 / 通话界面](https://docs.openluat.com/air8784/product/images/img_10.png)


## 七、按键

| 键 | 空闲+有 SOS 配置 | 来电中 | 通话/拨打中 | 无配置/离线 |
|---|---|---|---|---|
| SOS (GPIO20) | 启动 SOS 拨打 | 接听 | 忽略 | 忽略 |
| UP (GPIO21) 长按(≥1s) | 无动作 | 挂断 | 挂断/停止 | 无动作 |
| UP (GPIO21) 短按 | 预留（当前不动作） | — | — | — |

- 按下即发事件：SOS → `SIP_TASK_PRIMARY`；UP 长按 → `SIP_TASK_STOP`。
- 按键会取消正在播放的 SOS 通话提示音。

![合宙 SIP 通话终端的两个按键：① 紧急求助 SOS＝SOS 键，② 左侧红键＝UP 键](https://docs.openluat.com/air8784/product/images/img_02.png)


## 八、SOS 通话提示音与提示条件（TTS）

原 `user/` 的 4 个 `.pcm` 提示音（`tv_ok` / `air1103_busy` / `air1103_gap` / `air1103_hangup`）已在 `new_web` 中**移除**，改由 Air1103 本地 **TTS**（`audio_v2.tts_pcm_start/read/stop`）播报，由 `audio/task_voice_config.lua` 配置：

| 参数 | 默认值 | 说明 |
|---|---|---|
| enabled | true | 是否启用 SOS 通话语音和双提示音 |
| volume | 20 | 提示期间的 Air1103 本地喇叭档位（0～31） |
| path | /luadb/ | 目录（末尾保留斜杠） |
| timeout_ms | 10000 | 单次提示播放超时上限（毫秒） |

播报场景：
- 成功保存新的 SOS 配置（put）后，TTS 播报“任务已生效”；不再依赖 `.pcm` 文件或朗读任务名称/号码。
- 运行模式切换（`sos_mode` 改变并触发重启）时才设置待提示标记；没有主动配置的接收端就绪后，播放程序生成的两声短音，不依赖额外音频文件。
- 查询、删除配置、重复的同一请求，以及没有模式变化的切换，不会新建一次提示。普通重启仅可能继续尚未消费的待提示任务，不会重播已经消费的提示。
- 远程 `play_tts`：网页可经云通道下发任意文本，由 `business_voice` 通过 Air1103 本地 TTS 播报（`task_cloud.play_tts` → `speech.remote`）；通话优先，通话及播报期间返回 `audio_busy`。

> 待提示标记在播放前就已持久化清除。禁用提示、资源缺失、播放失败或中途被打断，都不会自动循环重播该提示。没有听到提示不代表任务没有保存，应读取设备配置确认。


## 九、AirCloud 协议与运行流程

### 9.1 代码运行流程

1. `main.lua` 按 `fskv` 返工标记 → 首测保护标记 → OTP1 分流：无返工标记且 OTP1 为空 → `factory.lua`（产测）；OTP1 有值 → `task/task_main.lua`（业务）；有返工标记 → `factory.lua`（返工产测），并开机启动 FOTA。
2. `task_runtime.lua` 根据 `fskv["sip_task_v1"]` 的 `runtime_mode`（`single`/`phone`）选择分支；网页经 `set_config` 下发的 `sos_mode` 由 `aircloud_settings.lua` 归一化后写入。
3. 对应分支初始化 SIP 与音频。
4. `task_adapter.lua` 对接任务引擎（`task_engine.lua`）及 AirCloud 控制（`cloud/task_cloud.lua`）。
5. 网页通过 `set_config` 下发 SOS 配置（sos_mode + 号码），经 AirCloud 后台（TCP；`https://iot.luatos.com/ai_app/luatos/8786_SIP/index.html`）下发，设备校验后保存并上报；`sos_mode` 变更触发 single/phone 分支切换，等待空闲重启。
6. SOS 触发拨打或接听来电，UP 停止通话；执行期间继续上报状态。

### 9.2 上报（TCP 长连接，JSON）

- 触发：定时心跳上报，以及鉴权成功、命令执行后。
- 内容：SOS 通话配置与状态快照（`schema=air8784.sip.v1`），字段包括
  `device_id(hmeta.devid()) / revision / sos_mode / task(兼容旧字段) / modes / state / index / req / result / runtime_mode /
  reboot_pending / health(sip_registered, audio_ready, call_idle)` 等（`sos_mode` 为网页侧主字段，`task`/`modes` 为兼容旧协议保留）。
- 大负载自动分片（`aircloud_protocol.packets` 按 500 字节分片，单帧 body ≤ 1400 字节）。
- 设备标识使用 `hmeta.devid()`（区别于旧版 IMEI 直传）。

### 9.3 固件升级（FOTA）下发

现在**无需在平台手动下发指令**，可直接在网页操作：

入口：`https://iot.luatos.com/ai_app/luatos/8786_SIP/index.html` → 设备管理 → 选择项目（如 `8784_SIP`）→ 点目标设备卡片头部的「版本」→ 打开固件更新弹窗。

- **重新读取版本**：页面经 Tag1027 读取设备当前版本（如 `Air8784_Factory_001.000.007`）。
- **开始更新**：页面经 Tag19 / Tag1281 下发升级指令，设备触发一次 FOTA 检查（libfota3），完成后自动重启并重新联网。
- 升级期间保持供电与网络稳定，**切勿断电**。

兼容说明：设备仍响应手动下发的 `update` / `fota` 命令（JSON `{"op":"update"}` / `{"type":"update"}` / `{"command":"update"}` 或文本 `update` / `fota`），但通常无需再手动下发。

### 9.4 版本查询（兼容旧文本协议）

- 经 TCP 下发裸文本 `version`（忽略大小写及首尾空白），设备经 **Tag1027** 返回 ASCII 字符串，类型为 3，内容为运行时 `_G.PROJECT .. "_" .. _G.VERSION`。
- 保留请求流水号，不包装 JSON，也不额外返回上报帧；通话及播报期间可查询，队列满时记录 `VERSION_REPLY_QUEUE_FULL`，稍后重查。

### 9.5 云通道实现说明

- `cloud/aircloud_tcp_adapter.lua`：封装上游 `excloud`（原版不动），业务侧接管重连/退避/关机门控，屏蔽原库的 `IP_READY` 钩子，避免绕过门控；按 16 字节帧头 + body 解析（长度位于第 11~12 字节，上限 1400）。
- `cloud/aircloud_protocol.lua`：v1 信封（兼容 SOS 028），含分片、SOS 状态、SIP/CC 配置段、远程 TTS 队列。
- `cloud/aircloud_settings.lua`：配置后端，复用 8786 线字段名，持久化到 `fskv["sip_task_v1"]`（8784）。
- `cloud/sos_config.lua`：SOS 模式（sip / sip_cc / cc / sip_grade）与号码纯校验，无硬件/存储副作用。
- AirCloud 仅用 TCP，不改变 SIP 的传输选择（UDP/TCP/TLS 由 `sip_config.sip_transport` 决定）。


## 十、网页端操作

后台地址：**`https://iot.luatos.com/ai_app/luatos/8786_SIP/index.html`**（SIP 话机管理 · 设备管理 / 分组管理）。需使用合宙 IoT 账号登录后读取和操作账号下的设备。以下操作名称与流程按当前公开网页代码（构建 `20261026-04`）整理；左侧导航只有「设备管理」与「分组管理」两个视图。

![登录控制台 · Air8784（8786_SIP）：使用合宙 IoT 账号登录](https://docs.openluat.com/air8784/product/images/sip_console/01_login.png)

> 与旧版的重要区别：旧版是「创建任务（双设备互通 / 多设备轮拨 / 设备与手机）→ 检查并下发 → 按 SOS 执行 → UP 停止」的任务式流程；**新版改为以单台设备为中心**——每台设备在「设备设置」里独立配置 SIP 与 SOS 通道，点「保存并启用」即立即下发，不再有「保存任务 / 检查并下发 / 停止通话」这类集中按钮。停止设备通话仍由设备 UP 键完成（固件行为）；网页侧只对「网页拨号」软电话提供「挂断」。

### 10.1 登录并查看设备

1. 打开控制台，按页面提示使用合宙 IoT 账号登录。
2. 进入「设备管理」，在顶部「项目」下拉里选择名称带 `SIP` 的项目（如 `8784_SIP`）。
3. 页面以卡片形式列出该项目下的设备（一张卡片一台设备）；可用「按 IMEI 筛选」过滤，或点「刷新列表」重新拉取。
4. 卡片左下角的 SIP 在线状态由账号在线状态接口定时刷新（默认开启「自动刷新 SIP 在线状态」，也可点「立即刷新」查一次）；设备上报只补充「通话中 / 拨号中」这类瞬时状态。

选择设备时页面可能先显示平台保存的最近快照；需要实时状态时点卡片上的 **「刷新状态」**：页面经云通道下发 `get_status`，设备回传 `sip / battery / location / audio` 共 4 段 JSON，卡片据此更新 SIP 参数、电量、定位与音频就绪。**AirCloud 在线和 SIP 注册成功是两个独立条件**。

![登录后的工作台首页：左侧导航（设备管理 / 分组管理）+ 设备卡片列表](https://docs.openluat.com/air8784/product/images/sip_console/02_console_home.png)

### 10.2 设备设置

点卡片「设备设置」打开弹窗，分五块，**每一栏独立提交，提交后立即下发到设备**（不再有「检查并下发」）。

![设备设置面板：SIP 设置 + SOS 设置（四通道）](https://docs.openluat.com/air8784/product/images/sip_console/03_device_settings.png)

**SIP 设置**：服务器地址 / 端口 / 域（可留空）/ 传输协议（UDP / TCP / TLS）/ 账号 / 密码 / 自动接听（勾选后响铃到设定秒数自动接听，延时 0~20 秒）。点「提交 SIP 设置」下发 `set_config`，设备按新参数重注册；密码仅本次提交使用，不写入浏览器存储、也不回填。点卡片「刷新状态」可让设备回传当前 SIP 参数与自动接听设置，页面自动回填供核对。

**SOS 设置（四通道互斥）**：四个选项卡——`SIP` / `SIP_CC` / `CC` / `分组管理`，同一时刻只能有一种生效（设备侧 `sos_mode` 互斥）。提交某一选项卡时，设备里其余通道的号码会被清空（本机草稿仍保留，切回重提即可恢复）；卡片「当前生效」标识显示当前模式。

| 通道 | 含义 | 号码规则 | 启用按钮 |
|---|---|---|---|
| SIP | SOS 触发后优先拨打的 **SIP 号码** | 最多 3 个，按顺序呼叫 | 保存并启用 SIP |
| SIP_CC | SIP 呼叫失败后转**手机卡**拨打 | 每个 11 位手机号绑定一个对端 SIP 账号，最多 3 个；对端账号相同则顺序拨打，不同则按来电对端账号匹配 | 保存并启用 SIP_CC（需实名手机卡） |
| CC | 直接用工信**手机卡**拨打 | 11 位手机号，最多 3 个 | 保存并启用 CC（需实名手机卡） |
| 分组管理 | 归属分组 + 逐级拨打链（`sip_grade`） | 号码写入 `sos_numbers`，最多 3 个，可为空 | 保存设备分组 / 同步拨打链并启用分组管理 |

> `分组管理` 通道：把设备归属到某分组（在「分组管理」页维护，数字越小等级越高）。低级分组的 SOS 优先拨打上一级分组的 SIP 账号，每个连拨 3 次、隔 1 分钟一次，不通则逐级向上。当前**只保存配置，设备端按等级拨打的调度尚未实现**（页面会显式提示）。

![SOS 设置：SIP_CC 子标签（四通道互斥，卡片显示当前生效通道）](https://docs.openluat.com/air8784/product/images/sip_console/04_sos_sipcc.png)

![SOS 设置：CC 子标签（直接用工信手机卡拨打）](https://docs.openluat.com/air8784/product/images/sip_console/05_sos_cc.png)

**音量调节**：喇叭音量 `volume` 0~31（默认 28）、麦克音量 `mic_gain` 1~8（默认 2），拖动进度条后「提交音量设置」即下发。

![音量调节：喇叭音量 0~31 / 麦克音量 1~8 滑条](https://docs.openluat.com/air8784/product/images/sip_console/06_volume.png)

**TTS 下发**：输入要播报的内容，点「提交 TTS 内容」由设备本地语音合成播放；中文会自动转成 JSON Unicode 转义再下发，中文请控制在 190 字以内。

![TTS 下发：输入播报内容后提交，由设备本地语音合成](https://docs.openluat.com/air8784/product/images/sip_console/07_tts.png)

**设备上报记录（诊断）**：点「读取最近上报」看设备最近一次 `get_status` 回执原文（标 `report_id` 与「分段 x/4 段」），用于核对 `cmd`、字段名与 Tag；点「查看最近下发」核对网页到底发了几次、平台每次返回什么（下发固定走 TCP）。

![设备上报记录（诊断）：最近一次上报原文 + 最近下发记录](https://docs.openluat.com/air8784/product/images/sip_console/08_diagnostic.png)

### 10.3 查看定位

点卡片「查看定位」打开弹窗：显示经度 / 纬度 / 坐标获取时间 / 地址，并在地图上标记（设备上报为 WGS84 原值，地图按腾讯 GCJ-02 绘制，点击标记可同时看两套坐标）。设备离线时只读平台保存的最后一次上报，并标注坐标时间与来源。可设置 **主动上报定位间隔（5~60 分钟）** 并「下发间隔」；也可「重新获取当前定位」或「读取平台最后一次上报」。浏览器端还能「定位到我（浏览器）」。

### 10.4 通话记录

点卡片「通话记录」打开弹窗：按**日期 / 快捷时间范围 / SIP 账号 / 接通情况**筛选后点「查询」，表格列：开始时间 / 方向 / 主叫 / 被叫 / 客户名 / 状态 / 时长 / 录音，支持分页。

![通话记录：日期 / SIP 账号 / 接通情况筛选 + 查询](https://docs.openluat.com/air8784/product/images/sip_console/10_call_records.png)

### 10.5 网页拨号（软电话）

在「设备管理」卡片或「分组管理」右键菜单点「拨号」，打开软电话弹窗：输入**要拨打的 SIP 号码**点「呼叫」，由浏览器内 JsSIP 经 WebSocket 发起（需授权麦克风，SIP 服务器需支持 WS/WSS）；设备端通常由「自动接听」接起，点「挂断」结束。拨号所用的**超级管理员 SIP 账号**仅在「超级管理员账号」弹窗里配置、只存本机浏览器、不上报平台。

![网页拨号账号配置：超级管理员 SIP 账号（仅本机保存）](https://docs.openluat.com/air8784/product/images/sip_console/13_dial.png)

### 10.6 分组管理

点左侧「分组管理」进入：以一级 / 二级 / 三级…树形列出分组与组内设备（默认折叠），点「新建一级分组」或分组编辑弹窗（名称 / 等级 1~6 / 上级分组 / 分组 SIP 账号，逗号分隔）维护分组；右键设备（或行尾 ⋯）可「拨号 / 查看定位 / 分组移动」。「超级管理员账号」按钮用于配置网页拨号账号。

![分组管理：分组树 + 新建一级分组 + 超级管理员账号](https://docs.openluat.com/air8784/product/images/sip_console/11_groups.png)

### 10.7 固件更新（FOTA）

点卡片头部的「版本」打开弹窗：显示当前设备版本（点「重新读取版本」经 Tag1027 读取），点「开始更新」经 Tag19 / Tag1281 下发升级。**升级期间一定不能断电**；升级完成后设备自动重启，重启期间短暂离线属正常。

![固件更新面板：当前版本 + 重新读取版本 / 开始更新](https://docs.openluat.com/air8784/product/images/sip_console/14_firmware_update.png)

## 十一、产测指令

> 工程位置：`factory/factory.lua`（返工标记与 MODEL_RETEST 指令在 `factory/retest.lua`）
> 通信：USB 虚拟串口 `uart.VUART_0`，波特率 115200，指令与回复均以 `#` 结尾（循环解析 `#` 分帧，支持粘包连发）

### 1. 启动模式（main.lua）

| 条件 | 行为 |
|---|---|
| 有 `fskv["model_retest"]` 返工标记 | 进入产测模式（返工产测），`require "factory"`，独占 VUART_0 响应指令 |
| 无返工标记 且 OTP1 为空（PROD 未写） | 进入产测模式（首次产测），`require "factory"`；进入前写首测保护标记 `model_firsttest` |
| 无返工标记 且 有 `model_firsttest` | 进入产测模式（首测中途复位后继续产测） |
| 无返工标记 且 OTP1 有值 | 进入业务模式，`require "task_main"`；仅注册 `MODEL_RETEST` 一条产测指令 |

> 分流顺序：返工标记优先，其次首测保护标记 `model_firsttest`（首测中途复位后回到产测），最后按 OTP1 是否有值决定产测或业务。
> 首次产测完成：`TEST_DONE#` 写 OTP1（PROD/PCB/IMEI）并删除 `model_firsttest` 后重启进业务模式；未写号（PROD 为空）禁止结束。
> 返工产测完成：`TEST_DONE#` 仅清返工标记（不动 OTP1、不动 `model_firsttest`）并重启进业务模式。
> 已在业务模式需要返工：发 `MODEL_RETEST#CONFIRM` 写返工标记并重启进返工产测（无需重烧）；或重烧并勾「清除 KV」。

### 2. 管脚定义（板子统一）

| 功能 | GPIO | 说明 |
|---|---|---|
| 主 LED | GPIO24 | `LED,1#` 同时控 24/26/27 |
| SMS LED | GPIO26 | 同上，一条指令三灯同亮同灭 |
| NET LED | GPIO27 | 同上 |
| SOS 按键 | GPIO20 | `KEY,20,1#` 开启后按下/松开上报 `KEY20_PRESS#` / `KEY20_RELEASE#` |
| UP 按键 | GPIO21 | `KEY,21,1#` 开启后上报 `KEY21_PRESS#` / `KEY21_RELEASE#` |
| 电池电压 | ADC `CH_VBAT` | `VBAT#` 读 |
| 电池电压(ADC0 分压) | ADC0 | `CHG#` 读，BAT 经 R33(1MΩ)+R34(300kΩ) 分压，读数 ×13/3×1.0345(单点校准) 还原为电池电压(mV)；CHRG 未引主控 GPIO，充电中状态读不出 |
| Air1103 供电 | GPIO22 | 进产测时已拉高；UART1 固定 2M 波特率 |

### 3. 指令列表

#### 通用指令

| 指令 | 功能 | 返回值 |
|---|---|---|
| `VERSION#` | 固件版本 | `Air8784_Factory_XXX#`（以 main.lua VERSION 为准） |
| `IMEI#` | IMEI | 15 位# / ERROR# |
| `IMSI#` | SIM IMSI | IMSI# / ERROR# |
| `ICCID#` | SIM ICCID | ICCID# / ERROR# |
| `CSQ#` | 信号强度 | 数字#（0=无信号）/ ERROR# |
| `MUID#` | 模组唯一标识 | 非空# / ERROR# |
| `VBAT#` | 电池电压 | 电压值(mV，两位小数)# / ERROR# |
| `CHG#` | 电池电压(ADC0 分压) | 电压值(mV)#，BAT 经 R33(1MΩ)+R34(300kΩ) 分压，读数 ×13/3×1.0345 校准还原；ADC0 需先 `adc.setRange(ADC_RANGE_1_2)` 再 open |
| `LED,1#` / `LED,0#` | 三灯同亮/同灭（GPIO24/26/27） | OK# |
| `ECNPICFG#` | RF 校准标志位（只读） | `true#` / `false#` / ERROR# |
| `FLYMODE,1#` / `FLYMODE,0#` | 飞行模式 进入/退出（仅主 LTE，`mobile.flymode`） | `OK#` / 参数非 0/1 回 `ERROR#` |

#### 按键检测（异步上报）

| 指令 | 功能 | 返回值 |
|---|---|---|
| `KEY,20,1#` / `KEY,21,1#` | 开启对应脚检测（onoff=1 开 / 0 关） | OK#（pin 非 20/21 回 ERROR#） |
| 主动上报 `KEY20_PRESS#` / `KEY20_RELEASE#` | GPIO20 按下/松开 | 设备自发，无请求 |
| 主动上报 `KEY21_PRESS#` / `KEY21_RELEASE#` | GPIO21 按下/松开 | 设备自发，无请求 |

> 必须用 `KEY,<pin>,1#` 打开检测后才会上报；按键事件是异步的，上位机要异步收，不能用请求-应答模型等。

#### 写号指令（OTP，写错无法改）

| 指令 | 功能 | 返回值 |
|---|---|---|
| `MODEL,型号#` | 写工业模组型号（OTP PROD） | OK# / ERROR#（空串） |
| `MODEL?#` | 读回型号（未写 ERROR） | 型号# / ERROR# |
| `HVERSION,版本#` | 写硬件版本（OTP PCB） | OK# / ERROR#（空串） |
| `HVERSION#` | 读回硬件版本（未写 ERROR） | 版本# / ERROR# |

#### 完成指令

| 指令 | 功能 | 返回值 |
|---|---|---|
| `RST#` | 单独重启（不改产测/返工状态，重启后还进产测） | OK#（回 OK 后 500ms 重启） |
| `TEST_DONE#` | 测试完成：首次产测校验 OTP1 非空（未写号禁止结束）→ 写 OTP1（PROD/PCB/IMEI）→ 删除 `model_firsttest`；返工产测仅清返工标记；3s 重启进业务模式 | OK# |
| `PCBA_TEST_DONE#` | 测试完成关机（不写 fskv，`pm.shutdown`） | OK#（回 OK 后 3s 关机） |

#### 返工指令（MODEL_RETEST，产测/正常模式共用）

`#` 在 `MODEL_RETEST` 指令中为“命令/数据”分隔符（末尾不带 `#`），与产测指令表“命令,数据#”的 `#` 结束符不同，故在通用解析前单独解析（`retest.parse`）。

| 指令 | 功能 | 返回值 |
|---|---|---|
| `MODEL_RETEST#CONFIRM` | 校验魔法字 `CONFIRM`（区分大小写，去空白后全匹配）→ 写 `fskv["model_retest"]` 返工标记 → 重启进返工产测 | `OK#`（回 OK 后 500ms 重启）/ `ERROR#` |
| `MODEL_RETEST?` | 查询返工标记状态 | `有#` / `无#` |

> 正常模式仅响应此一条产测指令，业务运行不受影响。返工产测完成后 `TEST_DONE#` 会清掉返工标记并自动进业务模式，无需重烧。

#### 音频指令（Air1103）

| 指令 | 功能 | 返回值 |
|---|---|---|
| `RECORD#` | 录音 5 秒（16kHz PCM，存 `/record.pcm`） | 约 5s 后 OK# / ERROR# |
| `PLAY#` | 回放录音文件（喇叭测试） | 播完才 OK# / 未录过 ERROR# |

> `RECORD#` / `PLAY#` 为异步：指令发出后由音频任务在动作完成后补发 OK#/ERROR#。必须先确认日志有 `Air1103 音频初始化成功`，否则这两步必然 ERROR#。

### 4. 测试流程（参考）

```
VERSION#                  校验固件版本
IMEI#  IMSI#  ICCID#      记录三码
CSQ#                      判信号强度阈值
ECNPICFG#                 必须为 true#
VBAT#  CHG#               电池电压(VBAT 供电 / ADC0 分压校准)
LED,1# → 目视 → LED,0#    三灯同亮同灭
KEY,20,1# → 按 SOS → 收 KEY20_PRESS# → KEY,20,0#
KEY,21,1# → 按 UP  → 收 KEY21_PRESS# → KEY,21,0#
RECORD# → 等 OK#          对人说话 5 秒
PLAY#   → 等 OK#          听回放
MODEL,Air8784#  → MODEL?#      写型号并核对
HVERSION,V1.0#  → HVERSION#    写硬件版本并核对
TEST_DONE#               3 秒后自动重启进业务模式
```

> 返工产测流程与首次产测基本相同（通常不重写 OTP1），完成后 `TEST_DONE#` 仅清返工标记；正常模式发 `MODEL_RETEST#CONFIRM` 即可进入返工产测，无需重烧。

### 5. 时序注意（上位机必须照做）

| 指令 | 多久回 | 坑 |
|---|---|---|
| `RECORD#` | ≥5 秒 | 固定录 5 秒，等待超时按 **10 秒**设 |
| `PLAY#` | 播完才回，最长 15 秒 | 依赖 RECORD 产生的文件，没录过直接 ERROR#，超时按 **15 秒**设 |
| `RST#` | 立即回 OK# | 回 OK 后 500ms 就重启，别在回 OK 后立刻关串口 |
| `TEST_DONE#` | 立即回 OK# | 回 OK 后 3 秒重启，之后进业务模式不再响应产测 |
| `KEY,20,1#` | 立即回 OK# | 真正的按键事件后面异步来，要异步收 |


## 十二、FOTA

升级基于 libfota3，固件包由合宙按项目 / 设备标识提供；`main.lua` 开机即 `update.init()`，首次烧录检测一次，之后每 8 小时自动检测（与工作模式无关，产测模式下同样检测）。除自动检测外，手动升级有下面两种方式。

### 12.1 方式一：网页一键升级（推荐）

1. 打开 `https://iot.luatos.com/ai_app/luatos/8786_SIP/index.html` → **设备管理** → 选择项目（如 `8784_SIP`）。
2. 点目标设备卡片头部的 **版本**，打开「固件更新」面板（面板显示当前设备版本与 Tag1027 上报时间）。
3. 点 **重新读取版本**，页面经 Tag1027 读取设备当前脚本版本（如 `Air8784_Factory_001.000.007`）。
4. 点 **开始更新**，页面经 Tag19 / Tag1281 下发升级指令；设备触发一次 FOTA 检查（libfota3），完成后自动重启并重新联网。

![固件更新面板：当前版本 + 重新读取版本 / 开始更新](https://docs.openluat.com/air8784/product/images/sip_console/14_firmware_update.png)

### 12.2 方式二：AirCloud 手动下发 `fota`

控制台入口不可用、或需要脱离控制台单独触发时，在合宙 IoT 平台顶部菜单 **基础能力 → AirCloud → AirCloud 上报记录** 找到目标设备点「下发」：

![AirCloud 上报记录：基础能力 → AirCloud → AirCloud 上报记录](https://docs.openluat.com/air8784/product/images/aircloud_upgrade_menu.png)

消息下发工具里：接收设备号填目标设备，命令类型选 **控制命令 (Tag19)**，数据类型选 **ASCII 字符**，消息内容填 `fota`（或 `update`），点 **下发**：

![消息下发工具：控制命令 Tag19 + ASCII 字符 + 消息内容 fota](https://docs.openluat.com/air8784/product/images/aircloud_upgrade_send.png)

设备同时兼容 JSON 形式（`{"op":"update"}` / `{"type":"update"}` / `{"command":"update"}`），效果与文本命令一致，均只触发一次升级检查。

### 12.3 注意事项

- 升级期间保持供电与网络稳定，**切勿断电**；升级完成后设备自动重启，重启期间短暂离线属正常。
- 不要仅凭某一个失败返回码判断“没有新版本”，应结合完整升级日志区分无需升级、网络异常及升级失败；升级文件与平台侧配置需与实际项目匹配。
- 升级包由合宙按项目 / 设备标识提供，客户端无法自行指定版本或上传固件。


## 十三、其他参数说明

### 13.1 音量参数的作用范围

| 配置项 | 作用 |
|---|---|
| `single_config.lua` 的 volume | 单 SIP 分支本机 Air1103 喇叭档位，范围 0～31，当前为 31 |
| `single_config.lua` 的 mic_gain | 单 SIP 上行 PCM 重采样使用的软件增益，当前为 2 |
| `sip_config.lua` 的 air1103_volume | SIP_CC 分支本地 Air1103 音量设置 |
| `sip_config.lua` 的 local_audio_default | 是否默认开启 SIP_CC 本地音频，当前为 false |
| `audio/task_voice_config.lua` 的 volume | SOS 通话语音及双提示音的本地喇叭档位，范围 0～31，当前为 20 |

- 修改 MIC 软件增益后，需要重新创建对应重采样器（例如重启设备）才能应用到该音频通路。
- SIP_CC 两向桥接音频由固件直接转发，不经过 `single_audio.lua` 的 MIC 重采样器；修改上述本地喇叭或单 SIP MIC 参数，不会改变手机与 SIP 之间的桥接增益。
- 网页「设备设置 → 音量调节」可远程下发喇叭 `volume`（0~31）与麦克 `mic_gain`（1~8），提交即生效；SIP_CC 桥接音量由固件直接转发，不在此调节范围（见 13.1）。

### 13.2 phone 分支的 Air1103 就绪检查

`cc/cc_audio.lua` 复用 `single_config.lua` 中的电源控制与等待参数，上电后初始化 exaudio，再复位 Air1103 并等待新的 MIC 帧。当前启动等待为 1500 ms，就绪检查最长为 10000 ms，检测到至少三帧新的 MIC 数据后才认为芯片响应正常。

检查结束后，无论成功还是失败，都会停止 Air1103 MIC 上行并关闭接收解析，避免持续上行影响 SIP_CC 消息处理。该分支的手机与 SIP 桥接数据仍由固件转发；Air1103 就绪检查用于确认本地音频及 SOS 通话提示条件。

若出现 `Air1103 no MIC response`，应检查供电、GPIO22 电源控制电路、UART1 接线以及扩展库接口。仅 `exaudio.setup` 返回成功不再等同于硬件就绪；检查失败时 `health.audio_ready` 为 false，会影响网页的就绪确认和本地 SOS 通话提示。


## 十四、常见问题

| 现象 | 排查方法 |
|---|---|
| 网页没有项目或设备 | 核对登录账号、设备归属、项目名称及 AirCloud 项目标识 |
| 设备在线但不能呼叫 | 分别检查 SIP 注册、音频就绪、运行分支及目标账号，云端在线不等于通话就绪 |
| 无法选择 sip / sip_cc / cc 等 SOS 模式 | 读取设备能力，核对固件是否支持切换及单 SIP 音频所需接口 |
| 提交 SOS 配置后设备没有变化 | 看卡片「当前生效」标识与下发回执；提交即下发，若提示冲突或 busy 需等设备空闲后重新提交 |
| 下发成功后没有自动呼叫 | 本工程通过 SOS 键触发拨打，下发配置本身不拨号 |
| 下发提示忙或版本冲突 | 等待设备空闲，重新读取配置后再操作 |
| 配置下发超时或暂停 | 保持页面可见，核对设备网络及重启后的 SIP、音频状态；重新读取设备配置，确认已完成的部分 |
| 删除 SOS 配置后没有切回 phone | SOS 模式与运行分支独立保存，删除配置不切换分支 |
| 手机卡拨打失败 | 检查 SIM 语音业务、号码格式、当前 cc/sip_cc 配置、SIP 对端及蜂窝呼叫释放日志 |
| SIP_CC 本机喇叭没有声音 | 核对本地音频开关；默认关闭本地音频与桥接通话本身是不同事项 |
| 调整单 SIP 音量后桥接音量不变 | 两者属于不同音频通路，参考 13.1 |
| 没听到“任务已生效” TTS | 检查 enabled、提示音量、Air1103 TTS 接口（`audio_v2.tts_*`）、SIP/音频就绪状态；读取配置确认 SOS 配置是否已保存 |
| 远程 play_tts 返回 audio_busy | 通话或本地播报占用中，等待释放后再下发 |
| 设备标识与旧平台不一致 | new_web 上报用 `hmeta.devid()`（IoT 平台后台），与旧版 IMEI 直传不同，需在新控制台核对 |


## 十五、使用说明

1. Luatools 烧录工程目录（本目录 `factory/`）+ 设备所需底层固件（core = Air780EHM）。本工程已内置 `lib/`（air1103 / exaudio / httpplus）与 `certs/`；`exsip` / `excloud` 仍需从仓库共享库 `script/libs` 加入 Luatools 下载列表（`excloud.lua` 由 `aircloud_tcp_adapter.lua` 以 `if false then require "excloud" end` 声明依赖，Luatools 据此发现，运行时由适配层加载）。
2. 添加根目录 `main.lua` 与所有功能子目录中的脚本；不要只添加根目录文件，避免漏烧依赖；同名库不要重复添加。子目录仅电脑端分类，设备按文件原名加载。
3. **证书**：`certs/sip-ca.pem` 需加入烧录文件并映射到设备 `/luadb/sip-ca.pem`（SIP over TLS 开启时读取；不开启可不烧）。
4. **产测→业务**：上位机发 `TEST_DONE#` → 重启进业务模式，无需重烧。
5. **返修→产测**：正常模式发 `MODEL_RETEST#CONFIRM` 写返工标记并重启进返工产测（无需重烧）；或重烧并勾「清除 KV」清掉 OTP1 与返工标记。
6. **模式切换**：网页下发 `sos_mode` 经 `aircloud_settings` 归一映射为 `single`/`phone` 运行分支，空闲后重启；SIP_CC 需插手机卡（VoLTE），单 SIP 用流量卡。`set_mode` 命令仍保留用于兼容分支切换与传输切换。
7. **FOTA**：网页「设备管理 → 固件更新」一键升级（Tag1027 读版本、Tag19/Tag1281 下发）；亦兼容云端 `update` 手动触发；开机与每 8h 自动检测。
8. **调试**：`main.lua` 顶部 `BOOT_MODE` 改 `normal`/`factory` 可跳过产测检查。
9. **看门狗**：LuatOS 内置硬狗 9s 超时 / 3s 喂狗，默认启用。
10. 业务参数以 `task/sip_config.lua`、`single/single_config.lua`、`audio/task_voice_config.lua` 为准，烧录前按实际环境核对。
11. README 不需要烧录。启动后确认日志中的应用版本与 `main.lua` 的 `VERSION` 一致（当前 `main.lua` 为 `001.000.007`，与本文档记录的 `001.000.018` 待对齐）。


## 十六、SIP over TLS 传输

业务模式支持 SIP 信令走 TLS（端口默认 5061），由 `task/sip_config.lua` 的 `sip_transport` 控制（可选 `udp` / `tcp` / `tls`）。

**新版网页已在「设备设置 → SIP 设置」中提供「传输协议」下拉（UDP / TCP / TLS，默认 UDP），「保存并启用」即下发 `set_sip` 更新 `sip_transport`，无需改固件文件或发云端命令。**

### 16.1 启用方式

**方式一：网页设置（推荐）**

1. 将 CA 证书烧录到设备 `/luadb/sip-ca.pem`（对应 `sip_config` 的 `sip_tls_ca_path`，即工程内 `certs/sip-ca.pem`）。注意：当前网页不提供证书上传，仍需通过烧录或文件推送写入设备。
2. 进入「设备设置 → SIP 设置」，将「传输协议」下拉从 UDP 改为 TLS（需要 TCP 也可选 TCP）。
3. 点击「提交 SIP 设置」，网页以 `set_config` 下发 `sip_transport=tls`（SIP 服务器 / 端口 / 账号等一并下发）；设备回执确认形如「设备已确认保存：<server>:<port>（TLS）」。切回 UDP/TCP 同理，改下拉后重新提交即可。
4. 非标准端口：在 SIP 设置里把「端口」一并改为对应值（TLS 默认 5061，UDP/TCP 默认 8910）。

![SIP 设置：传输协议下拉选择 TLS 后提交](https://docs.openluat.com/air8784/product/images/sip_console/15_sip_tls.png)

**方式二：改固件配置文件**

修改 `task/sip_config.lua`：`sip_transport = "tls"`（默认端口 5061；非标准端口把 `sip_server_port` 改为对应值，如 `sip_server_port = 5062`）。

**方式三：AirCloud 控制台云端下发**

经 AirCloud 控制台云端下发 `set_transport` 切换（命令类型选控制命令，消息内容填 `{"op":"set_transport","sip_transport":"tls"}`；切回 UDP 则填 `{"op":"set_transport","sip_transport":"udp"}`）；切换后设备约 1 秒重启生效并持久化（`task_cloud.lua` 的 `switch_transport` 默认端口：udp/tcp=8910、tls=5061）。

![消息下发工具：控制命令 Tag19 + 消息内容 {"op":"set_transport","sip_transport":"tls"}](https://docs.openluat.com/air8784/product/images/aircloud_tls_send.png)

### 16.2 注意事项

- **证书缺失**：开启 tls 但 `/luadb/sip-ca.pem` 不存在时，业务停在 `CONFIG_REQUIRED` 状态（日志 `TLS 开启但 CA 证书缺失`），经 OTA 补证书后无需重启即可自愈。
- **固件版本要求**：TLS 功能需搭配支持 SIP over TLS 的底层固件；低于该版本的底层不支持，切勿在旧固件上启用 `sip_transport = "tls"`。


## 十七、版本更新记录

| 版本 | 状态 | 说明 |
|------|------|------|
| v001.000.007 | 当前版本 | 见下 |
| v001.000.006 |         | 见下 |
| v001.000.005 |         | 见下 |
| v001.000.004 |         | 见下 |
| v001.000.003 |         | 见下 |
| v001.000.002 | 初始版本 | 初始发布 |


### v001.000.007

1. 适配新SIP Web平台：https://iot.luatos.com/ai_app/luatos/8786_SIP/index.html

### v001.000.006

1. **新增首测保护标记 `model_firsttest`**：裸板（OTP1 为空）进入产测前自动写入并读回校验（失败重试 3 次，仍失败仅告警不堵产线）；首测中途看门狗 / `RST#` / 掉电复位后凭该标记仍回产测，`TEST_DONE#` 正常结束并写号后删除。修复"写号在复位类测试（看门狗）之前，重启后误入正常模式"的问题。
2. **启动分流**：`fskv` 返工标记 → `fskv` 首测保护标记 → OTP1（型号/硬件版本/IMEI）。标记的写入/删除全部由固件内部完成，产测工具零改动。

### v001.000.005

1. **返工（retest）机制**：一套固件同时含产测与正式逻辑，启动按 `fskv` 返工标记 → OTP1（型号/硬件版本/IMEI）分流；正常模式经 `MODEL_RETEST#CONFIRM` 写返工标记并重启进返工产测，全程不动 OTP1，无需重烧。
2. **新增 `retest.lua`**：返工标记读写 + `MODEL_RETEST#CONFIRM` / `MODEL_RETEST?` 指令（产测与正常模式共用 USB VUART_0）。
3. **新增 Air1103 提示音**：`air1103_busy.pcm` / `air1103_gap.pcm` / `air1103_hangup.pcm`（忙/间隔/挂断提示音）。
4. **启动分流改为三级路由**：返工标记 → OTP1；`TEST_DONE#` 区分首次产测（写 OTP1）与返工产测（仅清返工标记）。

### v001.000.004

1. **支持 SIP over TLS**：`sip_transport` 可设为 `tls`（默认端口 5061），CA 证书烧录到 `/luadb/sip-ca.pem`；云端可经 `set_transport` 切换。
2. **产测新增 FLYMODE 飞行模式指令**：`FLYMODE,1#` 进入飞行模式、`FLYMODE,0#` 退出（`mobile.flymode`，仅主 LTE；参数非 0/1 回 `ERROR#`）。

### v001.000.003

1. **脚本库统一**：删除 `factory/lib/` 内置脚本库，统一引用仓库共享库 `script/libs`。
2. **SIM 卡自适应（main.lua）**：支持双卡自动切换、优先 SIM0（`mobile.simid(2, true)`）。
3. **OPTIONS 保活修复（script/libs/exsipclient.lua）**：保活由仅 UDP 扩展为 UDP/TCP，修复服务器静默死亡（断电/宕机/拔线未发 FIN）时 TCP 不触发 CLOSED、导致永远不重连的问题。

### v001.000.002（初始版本）

- 初始发布版本。
