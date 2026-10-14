# Air8784 出厂固件（产测 + SIP/CC 业务合一）

本固件基于 Air8784（主控 Air780EHM + 外挂 Air1103 语音芯片），将**产测**与**SIP 通话业务**合一：整批只烧一次，产测完成后自动进入业务模式。业务逻辑参考 AirCloud SIP 通话与任务配置示例：用户在网页配置任务，设备保存配置后，通过本机按键发起/停止通话。


## 一、项目简介

1. **产测 + 业务合一**：开机读 `fskv test_done` 分流。未产测 → 进产测模式；产测完成后写标记重启，进业务模式。
2. **一个设备只保存一个当前任务**。任务类型分为 `pair`、`round`、`phone`；运行分支分为 `single`（单 SIP）和 `phone`（SIP_CC），同一时间只加载一套通话与音频模块。
3. **业务参数来自网页**：不再使用本地产测预设参数，改为由 AirCloud 网页下发任务配置，设备持久保存后按任务执行。
4. **AirCloud 收发**：Tag19 接收 JSON 命令，Tag20 上报任务状态快照。
5. **FOTA**：libfota3，开机检测 + 每 8 小时自动检测 + 云端 `update` 命令触发；仅合宙可据 IMEI 推送。


## 二、启动模式

| 模式 | 触发条件 | 加载模块 | 业务 |
|---|---|---|---|
| 产测 | 无 `test_done` | `factory.lua` | USB VUART_0 响应产测指令 |
| 业务 · 单 SIP | `test_done` + 运行模式 `single` | `task/task_main` → `single/` | 单 SIP 通话（pair/round） |
| 业务 · SIP_CC | `test_done` + 运行模式 `phone` | `task/task_main` → `cc/` | SIP↔手机(VoLTE) 桥接（phone） |
| 调试 BOOT_MODE | `main.lua` 顶部常量 | — | `auto`(默认)/`normal`(强制业务)/`factory`(强制产测) |

- 业务分支由 `task/task_runtime.lua` 读 `fskv["sip_task_v1"]` 的 `runtime_mode` 决定，缺省为 `phone`。
- 运行模式切换（网页 `set_mode`）需固件具备 `cc.setBridge` 和 `rtos.reboot`，否则只提供 `phone` 模式。


## 三、目录结构

```
factory/
├── readme.md
└── user/                        # 业务代码（见下）；脚本库统一引用仓库共享库 script/libs，本工程不再内置 lib/
    ├── main.lua                 # 入口：test_done 分流产测/业务；FOTA 启动；全局定义
    ├── factory.lua              # 产测模式
    ├── update.lua               # FOTA 封装（libfota3）
    ├── tv_ok.pcm                # “任务已生效”提示音（烧录到 /luadb/tv_ok.pcm）
    ├── netdrv/
    │   └── netdrv_4g.lua        # 4G 网卡
    ├── task/                    # 共用：网页任务 / 云端 / 按键 / 语音 / 共用配置
    │   ├── task_main.lua        #   业务入口（按运行模式加载分支）
    │   ├── task_runtime.lua     #   运行模式选择
    │   ├── task_cloud.lua       #   AirCloud 收发（Tag19/20）
    │   ├── task_engine.lua      #   任务校验 / 状态机 / 轮拨
    │   ├── task_adapter.lua     #   分支适配 / 跨模式重启 / 主灯
    │   ├── task_keys.lua        #   按键（SOS / UP）
    │   ├── task_voice.lua       #   提示音播放
    │   ├── task_voice_config.lua#   提示音配置
    │   └── sip_config.lua       #   共用 SIP + 硬件配置
    ├── single/                  # 单 SIP 分支
    │   ├── single_app.lua       #   业务状态机（注册/拨号/接听/挂断）
    │   ├── single_audio.lua     #   Air1103 音频（PCM 上下行）
    │   └── single_config.lua    #   单 SIP 配置（复用 sip_config 账号）
    └── cc/                      # SIP_CC 桥接分支
        ├── cc_app.lua           #   启动流程（音频→SIP→VoLTE→心跳）
        ├── cc_sip.lua           #   SIP 半边状态机
        ├── cc_main.lua          #   蜂窝(VoLTE) 半边状态机
        ├── cc_bridge.lua        #   两侧桥接协调器
        ├── cc_phone_route.lua   #   SIP 来电转拨号码读取
        ├── cc_incoming_round.lua#   SIP 来电手机顺序轮拨
        └── cc_audio.lua         #   CC 分支本地音频初始化
```

> 子目录仅为组织层级：LuatOS `require` 按**文件名**解析，文件名在工程内必须全局唯一。


## 四、硬件引脚（主控 Air780EHM）

| 功能 | GPIO / 接口 | 说明 |
|---|---|---|
| 主 LED | GPIO24 | 通话/来电/拨号中常亮，空闲熄灭 |
| SMS 灯 | GPIO26 | 产测三灯同步 |
| 网络灯 | GPIO27 | — |
| SOS 按键 | GPIO20 | 上拉、下降沿；执行任务 / 接听 |
| UP 按键 | GPIO21 | 上拉、双沿；长按(≥1s)挂断，短按预留 |
| Air1103 供电 | GPIO22 | 拉高供电（`single_config.audio.power_gpio`） |
| VREF | GPIO23 | 上拉参考电压，开机常开 |
| 语音芯片 | UART1 | Air1103，固定 2M 波特率，仅 PCM |


## 五、演示功能

| 场景 | 网页入口 | 任务类型 | 发起设备运行分支 |
|---|---|---|---|
| 设备与手机/电脑 SIP 软终端通话 | 双设备互通，目标选择本机对端账号 | pair | single |
| 两台 Air8784 设备互通 | 双设备互通 | pair | single |
| 按顺序呼叫多个设备或软终端 | 多设备轮拨 | round | single |
| 蜂窝电话与 SIP 通话桥接 | 设备与手机 | phone | phone |

- pair 任务只有一个目标；round 和 phone 最多三个目标。任务等待接听时间固定 **30 秒**。
- 轮拨过程中，未接通的目标结束后才会尝试下一目标；一旦某个目标接通，本轮后续不再继续拨打其他目标。
- **网页下发配置不会自动开始通话**：发起设备通过 SOS 按键执行任务，UP 按键停止通话；single 分支收到来电时，SOS 用于接听。
- 任务保存并就绪后，本机会尝试播放“任务已生效”；没有主动任务的接收设备在运行模式发生切换并就绪后，播放两声短音（详见第八章）。


## 六、SIP 账号与通话规则

### 6.1 账号约定

| 对象 | SIP 账号 |
|---|---|
| 设备自身 | 设备的 15 位 IMEI 后追加 `0` |
| 该设备对应的软终端 | 同一 IMEI 后追加 `1` |
| 网页选择其他设备时 | 选择其 15 位 IMEI，设备侧自动转换为 IMEI 后追加 `0` |

- 服务器默认 `cc.luatos.com:8910`（密码 `123456`），以 `task/sip_config.lua` 实际配置为准。
- 手机呼入时设备呼叫的 SIP 对端由 `sip_config.remote_sip_uri` 决定（默认 `sip:IMEI+1@cc.luatos.com`）；修改账号约定后需一并核对。

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


## 七、按键

| 键 | 空闲+有任务 | 来电中 | 通话/任务中 | 无任务/离线 |
|---|---|---|---|---|
| SOS (GPIO20) | 启动任务拨号 | 接听 | 忽略 | 忽略 |
| UP (GPIO21) 长按(≥1s) | 无动作 | 挂断 | 挂断/停止 | 无动作 |
| UP (GPIO21) 短按 | 预留（当前不动作） | — | — | — |

- 按下即发事件：SOS → `SIP_TASK_PRIMARY`；UP 长按 → `SIP_TASK_STOP`。
- 按键会取消正在播放的任务提示音。


## 八、任务提示音与提示条件

`task/task_voice_config.lua` 默认配置：

| 参数 | 默认值 | 说明 |
|---|---|---|
| enabled | true | 是否启用任务语音和双提示音 |
| volume | 20 | 提示期间的 Air1103 本地喇叭档位（0～31） |
| path | /luadb/ | tv_ok.pcm 所在目录；目录末尾保留斜杠 |
| timeout_ms | 10000 | 单次提示播放超时上限（毫秒） |

- 成功保存新的主动任务（put）后，播放固定的 `tv_ok.pcm`，不朗读任务名称/号码/目标列表。
- `set_mode` 实际改变运行模式时才设置待提示标记；没有主动任务的接收端就绪后，播放程序生成的两声短音，不依赖额外音频文件。
- 查询、删除任务、重复的同一请求，以及没有模式变化的 `set_mode`，不会新建一次提示。普通重启仅可能继续尚未消费的待提示任务，不会重播已经消费的提示。
- 播放前需确认无待重启状态、SIP 已注册、音频就绪、通话及媒体空闲，并且没有 Air1103 队列播放占用。
- 提示按每帧 320 字节、约 10 ms 的节奏发送 PCM，不停止 MIC，也不为这次任务提示复位 Air1103；来电进入非空闲、SOS 操作或网页停止指令会取消提示。
- 结束/超时/打断后恢复原音量：single 恢复其 `volume`；phone 根据当前本地音频开关恢复 `air1103_volume` 或静音。

> 待提示标记在播放前就已持久化清除。禁用提示、资源缺失、播放失败或中途被打断，都不会自动循环重播该提示。没有听到提示不代表任务没有保存，应读取设备配置确认。


## 九、AirCloud 协议与运行流程

### 9.1 代码运行流程

1. `main.lua` 读 `fskv test_done`：未产测 → `factory.lua`（产测）；已产测 → `task/task_main.lua`（业务），并开机启动 FOTA。
2. `task_runtime.lua` 根据 `fskv["sip_task_v1"]` 的 `runtime_mode` 选择 `single` 或 `phone` 分支。
3. 对应分支初始化 SIP 与音频。
4. `task_adapter.lua` 对接任务引擎（`task_engine.lua`）及 AirCloud 控制（`task_cloud.lua`）。
5. 网页指令经 AirCloud 下发，设备校验后保存配置并上报；需要切换分支时等待空闲重启。
6. SOS 触发任务或接听来电，UP 停止通话；任务执行期间继续上报状态。

### 9.2 上报（Tag20，JSON）

- 触发：每 30 秒定时上报，以及鉴权成功、命令执行后。
- 内容：任务配置与状态快照（`schema=air8784.sip.v1`, `kind=snapshot`），字段包括
  `imei / revision / task / modes / state / index / req / result / runtime_mode /
  reboot_pending / health(sip_registered, audio_ready, call_idle)` 等。

### 9.3 下发升级指令（Tag19）

| 命令 | 说明 |
|---|---|
| `update` / `fota` | 触发一次 FOTA 升级检查（libfota3） |

- 在 AirCloud 消息下发工具里，命令类型选 **控制命令 (Tag19)**、数据类型 **ASCII字符**，消息内容填 `update` 或 `fota`。
- 兼容 JSON（`{"op":"update"}` / `{"type":"update"}` / `{"command":"update"}`）与文本短命令 `update` / `fota`。
- 触发升级不需要填 `imei` / `revision`。

## 十、网页端操作

控制台地址：[AirCloud SIP 配置控制台](https://iot.luatos.com/ai_app/luatos/SIP_setting/tasks.html?mode=pair)。

以下操作名称与流程按当前公开网页代码整理。控制台需要登录后才能读取和操作账号下的设备。

### 10.1 登录并确认设备

1. 打开控制台，按页面提示使用合宙 IoT 账号登录。
2. 进入“我的设备”，确认设备已在当前账号下可见且在线。
3. 进入需要的通话页面，选择项目及发起设备。
4. 点击“读取设备配置”，检查当前任务、运行模式、SIP 注册及音频就绪状态。

选择设备时页面可能先显示平台保存的最近一次快照；需要确认实时状态时，应主动点击“读取设备配置”。**AirCloud 在线和 SIP 注册成功是两个独立条件**。

### 10.2 双设备互通

以设备 A 呼叫设备 B 为例：

1. 确认两台设备均烧录配套脚本、已联网并接入同一账号可管理的项目。
2. 打开“双设备互通”，填写任务名称，选择 A 为发起设备。
3. 在目标中选择 B（该任务只允许一个目标）。
4. 如需保留当前表单，点击“保存任务”（仅保存浏览器草稿）。
5. 点击“检查并下发”，等待页面完成设备检查、模式准备及任务确认。
6. 页面提示任务配置完成后，按 A 的 SOS 键发起呼叫，按 B 的 SOS 键接听。
7. 按 UP 键停止通话，也可在网页选择相应设备后点击“停止通话”。

接收设备 B 不需要创建反向任务；网页会先检查参与设备，并在需要时将接收设备准备为 single 模式。测试设备与软终端通话时，在目标中选择“本机对端账号”（本机 `IMEI+1`），并确保软终端已注册。

### 10.3 多设备轮拨

1. 打开“多设备轮拨”，填写任务名称并选择发起设备。
2. 使用“＋ 添加目标”添加目标，最多三个；用“↑”调整顺序、“×”移除；不要重复添加同一目标。
3. 点击“检查并下发”，等待所有参与设备及发起设备准备完成。
4. 按发起设备 SOS 键开始按顺序呼叫。

每个目标等待接听 30 秒；未接通时设备会先结束当前呼叫并等待资源释放，再尝试下一目标。任一目标接通后本轮停止推进。

### 10.4 设备与手机

这里的“手机”指蜂窝电话号码，与手机上安装 SIP 软终端的场景不同。

1. 打开“设备与手机”，填写任务名称并选择设备。
2. 添加手机号码，最多三个（当前脚本接受以 `1` 开头的 11 位号码），按需调整顺序，点击“检查并下发”。
3. 若设备原来运行 single 分支，等待其保存配置、空闲重启并重新上线。
4. 确认 phone 分支就绪，且 `sip_config.lua` 指定的 SIP 对端已正确注册，再进行通话测试。

可验证的流程：

- 按设备 SOS 键执行手机任务，按配置顺序尝试呼叫；
- SIP 对端呼叫设备 SIP 账号，设备使用当前 phone 任务中的号码进行手机轮拨；
- 手机呼入设备 SIM 卡号码，由 SIP_CC 分支连接配置中的 SIP 对端。

SIP 来电使用最新保存的 phone 任务号码；缺少可用 phone 任务时，不会使用隐藏的备用号码。手机轮拨切换目标前会等待蜂窝通话释放并保留稳定间隔；若释放超时则结束本轮。

### 10.5 理解保存、下发与就绪状态

| 操作或状态 | 实际含义 |
|---|---|
| 保存任务 | 保存当前浏览器中的表单草稿，不修改设备 |
| 检查并下发 | 查询设备状态、准备运行模式、下发任务并复查 |
| 平台接受指令 | 平台已经接收请求，尚不能据此认定设备已保存 |
| 设备保存成功 | 设备已持久化配置，跨模式时仍可能等待重启 |
| 任务配置完成 | 网页已完成本次检查与配置确认，可以按键执行任务 |

- 当前网页先检查全部参与设备，再准备接收设备，最后配置发起设备并复查。就绪条件包括运行模式一致、没有待重启状态、SIP 已注册、音频已就绪以及通话空闲。
- 任务提示播放期间，设备任务状态可能短暂显示 busy，新的修改或删除请求也可能被拒绝；等待提示结束后再读取或操作。
- 操作期间请保持当前网页可见。切换页面或使页面进入后台可能暂停流程，**已经保存到设备的配置不会自动回滚**；返回后先读取设备配置，再按需重新执行“检查并下发”。
- 接收设备存在 phone 任务等冲突时，网页可能终止本次配置并提示处理冲突。

### 10.6 停止、删除与切换任务

- **停止通话**：向选中设备发送停止请求；请求受理后需等待设备结束通话，可再次读取状态确认。
- **删除任务**：确认后删除设备当前任务；不删除浏览器草稿，也不自动切换运行模式。
- **pair 与 round 互换**：都使用 single 分支，通常不需要重启。
- **phone 与 pair/round 互换**：需要切换运行分支，设备保存后标记待重启，至少等待 3 秒并确认通话和媒体均空闲后才重启。
- **设备正在通话**：修改、删除任务或切换模式可能被拒绝；先停止通话并确认空闲再重试。

> 任务与运行模式独立保存。首次没有已保存模式时默认使用 `phone` 分支；删除 single 任务后仍可保持 single 模式接听来电。清除 Flash 数据可能同时清除持久化任务及模式。


## 十一、产测指令

> 工程位置：`user/factory.lua`
> 通信：USB 虚拟串口 `uart.VUART_0`，波特率 115200，指令与回复均以 `#` 结尾（循环解析 `#` 分帧，支持粘包连发）

### 1. 启动模式（main.lua）

| test_done | 行为 |
|---|---|
| 无（默认） | 进入产测模式（`require "factory"`，独占 VUART_0 响应指令） |
| 有 | 进入业务模式（`require "task_main"`），串口不再响应产测指令 |

> 产测完成后发 `TEST_DONE#` 写 test_done 并重启进入业务模式。
> 需要重新产测：清 fskv 的 test_done 键（重烧勾「清除 KV」），或烧一个“清标记小工程”（`fskv.del("test_done")`）。

### 2. 管脚定义（板子统一）

| 功能 | GPIO | 说明 |
|------|------|------|
| 主 LED | GPIO24 | `LED,1#` 同时控 24/26/27 |
| SMS LED | GPIO26 | 同上，一条指令三灯同亮同灭 |
| NET LED | GPIO27 | 同上 |
| SOS 按键 | GPIO20 | `KEY,20,1#` 开启后按下/松开上报 `KEY20_PRESS#` / `KEY20_RELEASE#` |
| UP 按键 | GPIO21 | `KEY,21,1#` 开启后上报 `KEY21_PRESS#` / `KEY21_RELEASE#` |
| 电池电压 | ADC `CH_VBAT` | `VBAT#` 读 |
| 充电电压 | ADC0 | `CHG#` 读（若前端有分压需按电路换算） |
| Air1103 供电 | GPIO22 | 进产测时已拉高；UART1 固定 2M 波特率 |

### 3. 指令列表

#### 通用指令

| 指令 | 功能 | 返回值 |
|------|------|--------|
| `VERSION#` | 固件版本 | `Air8784_Factory_001.000.000#` |
| `IMEI#` | IMEI | 15 位# / ERROR# |
| `IMSI#` | SIM IMSI | IMSI# / ERROR# |
| `ICCID#` | SIM ICCID | ICCID# / ERROR# |
| `CSQ#` | 信号强度 | 数字#（0=无信号）/ ERROR# |
| `MUID#` | 模组唯一标识 | 非空# / ERROR# |
| `VBAT#` | 电池电压 | 电压值(mV，两位小数)# / ERROR# |
| `CHG#` | 充电电压 | 电压值(mV)#（前端分压需换算） |
| `LED,1#` / `LED,0#` | 三灯同亮/同灭（GPIO24/26/27） | OK# |
| `ECNPICFG#` | RF 校准标志位（只读） | `true#` / `false#` / ERROR# |
| `FLYMODE,1#` / `FLYMODE,0#` | 飞行模式 进入/退出（仅主 LTE，`mobile.flymode`） | `OK#` / 参数非 0/1 回 `ERROR#` |

#### 按键检测（异步上报）

| 指令 | 功能 | 返回值 |
|------|------|--------|
| `KEY,20,1#` / `KEY,21,1#` | 开启对应脚检测（onoff=1 开 / 0 关） | OK#（pin 非 20/21 回 ERROR#） |
| 主动上报 `KEY20_PRESS#` / `KEY20_RELEASE#` | GPIO20 按下/松开 | 设备自发，无请求 |
| 主动上报 `KEY21_PRESS#` / `KEY21_RELEASE#` | GPIO21 按下/松开 | 设备自发，无请求 |

> 必须用 `KEY,<pin>,1#` 打开检测后才会上报；按键事件是异步的，上位机要异步收，不能用请求-应答模型等。

#### 写号指令（OTP，写错无法改）

| 指令 | 功能 | 返回值 |
|------|------|--------|
| `MODEL,型号#` | 写工业模组型号（OTP PROD） | OK# / ERROR#（空串） |
| `MODEL?#` | 读回型号（未写 ERROR） | 型号# / ERROR# |
| `HVERSION,版本#` | 写硬件版本（OTP PCB） | OK# / ERROR#（空串） |
| `HVERSION#` | 读回硬件版本（未写 ERROR） | 版本# / ERROR# |

#### 完成指令

| 指令 | 功能 | 返回值 |
|------|------|--------|
| `RST#` | 单独重启（不写 test_done，重启后还进产测） | OK#（回 OK 后 500ms 重启） |
| `TEST_DONE#` | 测试完成（写 `fskv["test_done"]=true`，3s 重启进业务模式） | OK# |
| `PCBA_TEST_DONE#` | 测试完成关机（不写 fskv，`pm.shutdown`） | OK#（回 OK 后 3s 关机） |

#### 音频指令（Air1103）

| 指令 | 功能 | 返回值 |
|------|------|--------|
| `RECORD#` | 录音 5 秒（16kHz PCM，存 `/record.pcm`） | 约 5s 后 OK# / ERROR# |
| `PLAY#` | 回放录音文件（喇叭测试） | 播完才 OK# / 未录过 ERROR# |

> `RECORD#` / `PLAY#` 为异步：指令发出后由音频任务在动作完成后补发 OK#/ERROR#。必须先确认日志有 `Air1103 音频初始化成功`，否则这两步必然 ERROR#。

### 4. 测试流程（参考）

```
VERSION#                  校验固件版本
IMEI#  IMSI#  ICCID#      记录三码
CSQ#                      判信号强度阈值
ECNPICFG#                 必须为 true#
VBAT#  CHG#               电池与充电电压
LED,1# → 目视 → LED,0#    三灯同亮同灭
KEY,20,1# → 按 SOS → 收 KEY20_PRESS# → KEY,20,0#
KEY,21,1# → 按 UP  → 收 KEY21_PRESS# → KEY,21,0#
RECORD# → 等 OK#          对人说话 5 秒
PLAY#   → 等 OK#          听回放
MODEL,Air8784#  → MODEL?#      写型号并核对
HVERSION,V1.0#  → HVERSION#    写硬件版本并核对
TEST_DONE#               3 秒后自动重启进业务模式
```

### 5. 时序注意（上位机必须照做）

| 指令 | 多久回 | 坑 |
|---|---|---|
| `RECORD#` | ≥5 秒 | 固定录 5 秒，等待超时按 **10 秒**设 |
| `PLAY#` | 播完才回，最长 15 秒 | 依赖 RECORD 产生的文件，没录过直接 ERROR#，超时按 **15 秒**设 |
| `RST#` | 立即回 OK# | 回 OK 后 500ms 就重启，别在回 OK 后立刻关串口 |
| `TEST_DONE#` | 立即回 OK# | 回 OK 后 3 秒重启，之后进业务模式不再响应产测 |
| `KEY,20,1#` | 立即回 OK# | 真正的按键事件后面异步来，要异步收 |


## 十二、FOTA

- 使用 libfota3（只能合宙人员按客户提供的 IMEI 升级，客户无法自行操作）。
- `main.lua` 开机即 `update.init()`：首次烧录检测一次，之后每 8 小时自动检测。
- 云端下发 `update` / `fota` 命令可手动触发一次检测（见第九章）。
- 不要仅凭某一个失败返回码判断“没有新版本”，应结合完整升级日志区分无需升级、网络异常及升级失败。升级文件、平台侧配置需与实际项目匹配。


## 十三、其他参数说明

### 13.1 音量参数的作用范围

| 配置项 | 作用 |
|---|---|
| `single_config.lua` 的 volume | 单 SIP 分支本机 Air1103 喇叭档位，范围 0～31，当前为 31 |
| `single_config.lua` 的 mic_gain | 单 SIP 上行 PCM 重采样使用的软件增益，当前为 2 |
| `sip_config.lua` 的 air1103_volume | SIP_CC 分支本地 Air1103 音量设置 |
| `sip_config.lua` 的 local_audio_default | 是否默认开启 SIP_CC 本地音频，当前为 false |
| `task_voice_config.lua` 的 volume | 任务语音及双提示音的本地喇叭档位，范围 0～31，当前为 20 |

- 修改 MIC 软件增益后，需要重新创建对应重采样器（例如重启设备）才能应用到该音频通路。
- SIP_CC 两向桥接音频由固件直接转发，不经过 `single_audio.lua` 的 MIC 重采样器；修改上述本地喇叭或单 SIP MIC 参数，不会改变手机与 SIP 之间的桥接增益。
- 当前网页及任务协议没有实现远程音量设置。

### 13.2 phone 分支的 Air1103 就绪检查

`cc/cc_audio.lua` 复用 `single_config.lua` 中的电源控制与等待参数，上电后初始化 exaudio，再复位 Air1103 并等待新的 MIC 帧。当前启动等待为 1500 ms，就绪检查最长为 10000 ms，检测到至少三帧新的 MIC 数据后才认为芯片响应正常。

检查结束后，无论成功还是失败，都会停止 Air1103 MIC 上行并关闭接收解析，避免持续上行影响 SIP_CC 消息处理。该分支的手机与 SIP 桥接数据仍由固件转发；Air1103 就绪检查用于确认本地音频及任务提示条件。

若出现 `Air1103 no MIC response`，应检查供电、GPIO22 电源控制电路、UART1 接线以及扩展库接口。仅 `exaudio.setup` 返回成功不再等同于硬件就绪；检查失败时 `health.audio_ready` 为 false，会影响网页的就绪确认和本地任务提示。


## 十四、常见问题

| 现象 | 排查方法 |
|---|---|
| 网页没有项目或设备 | 核对登录账号、设备归属、项目名称及 AirCloud 项目标识 |
| 设备在线但不能呼叫 | 分别检查 SIP 注册、音频就绪、运行分支及目标账号，云端在线不等于通话就绪 |
| 无法选择 pair 或 round | 读取设备能力，核对固件是否支持切换及单 SIP 音频所需接口 |
| 点击保存任务后设备没有变化 | 保存仅作用于浏览器草稿，还需点击“检查并下发” |
| 下发成功后没有自动呼叫 | 本工程通过 SOS 执行任务，下发配置本身不拨号 |
| 下发提示忙或版本冲突 | 等待设备空闲，重新读取配置后再操作 |
| 提示播放期间短暂显示 busy | 等提示播放结束后再操作；任务语音也会占用适配器的空闲状态 |
| 没听到“任务已生效” | 检查 enabled、提示音量、`/luadb/tv_ok.pcm`、play_direct 接口及 SIP/音频就绪状态；读取配置确认任务是否已保存 |
| 接收设备没有双提示音 | 确认它没有主动任务且本次确实改变了运行模式；原本已在目标模式时不会重复提示 |
| phone 分支一直音频未就绪 | 检查 Air1103 实际 MIC 响应、供电、串口和 get_rx_stats 接口，参考 13.2 |
| 检查并下发超时或暂停 | 保持页面可见，核对设备网络及重启后的 SIP、音频状态；重新读取，确认已完成的部分 |
| 删除任务后没有切回 phone | 任务和运行模式独立保存，删除任务不切换分支 |
| 手机轮拨失败 | 检查 SIM 语音业务、号码格式、当前 phone 任务、SIP 对端及蜂窝呼叫释放日志 |
| SIP_CC 本机喇叭没有声音 | 核对本地音频开关；默认关闭本地音频与桥接通话本身是不同事项 |
| 调整单 SIP 音量后桥接音量不变 | 两者属于不同音频通路，参考 13.1 |


## 十五、使用说明

1. Luatools 烧录工程目录（user/）+ 仓库共享库 `script/libs`（core = Air780EHM；lib 选择该目录），同时将 `user/tv_ok.pcm` 加入烧录文件，确保设备上可通过 `/luadb/tv_ok.pcm` 读取（16 kHz、16 bit、单声道原始 PCM，不要用 WAV/MP3 改名替代；FOTA 更新时也需保留）。本工程已移除内置 `lib/`，库文件以 `script/libs` 为准。仓库共享库 `script/libs` 在线地址：https://gitee.com/openLuat/LuatOS/tree/master/script/libs （本地找不到该目录时，可在此获取最新版）。
2. **产测→业务**：上位机发 `TEST_DONE#` → 重启进业务模式，无需重烧。
3. **返修→产测**：重烧并勾「清除 KV」，或烧一个“清标记小工程”（`fskv.del("test_done")`）。
4. **模式切换**：云端 `set_mode`（`single` / `phone`）→ 空闲后重启；SIP_CC 需插手机卡（VoLTE），单 SIP 用流量卡。
5. **FOTA**：合宙按 IMEI 推送；云端发 `update` 即时检测；开机与每 8h 自动检测。
6. **调试**：`main.lua` 顶部 `BOOT_MODE` 改 `normal`/`factory` 可跳过产测检查。
7. **看门狗**：LuatOS 内置硬狗 9s 超时 / 3s 喂狗，默认启用。
8. 业务参数以 `task/sip_config.lua`、`single/single_config.lua`、`task/task_voice_config.lua` 为准，烧录前按实际环境核对。


## 十六、SIP over TLS 传输

业务模式支持 SIP 信令走 TLS（端口默认 5061），由 `task/sip_config.lua` 的 `sip_transport` 控制（可选 `udp` / `tcp` / `tls`）。

### 16.1 启用方式

1. 将 CA 证书烧录到设备 `/luadb/sip-ca.pem`（对应 `sip_config` 的 `sip_tls_ca_path`）。
2. 设 `sip_transport = "tls"`（默认端口 5061；非标准端口经 `sip_server_port` 覆盖）。
3. 也可由云端经 `set_transport` 切换：`{"op":"set_transport","sip_transport":"tls"}`；切回 UDP：`{"op":"set_transport","sip_transport":"udp"}`。切换后设备约 1 秒重启生效并持久化。

### 16.2 注意事项

- **证书缺失**：开启 tls 但 `/luadb/sip-ca.pem` 不存在时，业务停在 `CONFIG_REQUIRED` 状态（日志 `TLS 开启但 CA 证书缺失`），经 OTA 补证书后无需重启即可自愈。
- **固件版本要求**：TLS 功能需搭配 **v2054 及之后版本**的 22/122 固件；低于该版本的底层不支持 SIP over TLS，切勿在旧固件上启用 `sip_transport = "tls"`。


## 十七、版本更新记录

| 版本 | 状态 | 说明 |
|------|------|------|
| v001.000.004 | 当前版本 | 见下 |
| v001.000.003 |         | 见下 |
| v001.000.002 | 初始版本 | 初始发布 |

### v001.000.004（当前版本）

1. **支持 SIP over TLS**：`sip_transport` 可设为 `tls`（默认端口 5061），CA 证书烧录到 `/luadb/sip-ca.pem`；云端可经 `set_transport` 切换。
2. **产测新增 FLYMODE 飞行模式指令**：`FLYMODE,1#` 进入飞行模式、`FLYMODE,0#` 退出（`mobile.flymode`，仅主 LTE；参数非 0/1 回 `ERROR#`）。

### v001.000.003

1. **脚本库统一**：删除 `factory/lib/` 内置脚本库，统一引用仓库共享库 `script/libs`。
2. **SIM 卡自适应（main.lua）**：支持双卡自动切换、优先 SIM0（`mobile.simid(2, true)`）。
3. **OPTIONS 保活修复（script/libs/exsipclient.lua）**：保活由仅 UDP 扩展为 UDP/TCP，修复服务器静默死亡（断电/宕机/拔线未发 FIN）时 TCP 不触发 CLOSED、导致永远不重连的问题。

### v001.000.002（初始版本）

- 初始发布版本。
