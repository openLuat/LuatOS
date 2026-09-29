# Air8784 出厂固件（产测 + SIP/CC 业务合一）


## 一、项目简介

1. **产测 + 业务合一**：开机读 `fskv test_done` 分流，产测写完 `TEST_DONE#` 重启进业务，整批只烧一次。
2. **不请求网页端配置**：开机直接加载预置参数，默认通道 = AirCloud。
3. **两种业务模式**：SIP 云端通话（默认）/ CC（SIP↔手机 VoLTE 中转），靠 `fskv work_mode` 切换、重启生效。
4. **AirCloud 上报 + 下行**：结构化 TLV 周期上报（默认 180s）+ 控制命令（Tag 19/21/1281）。
5. **FOTA**：libfota3，开机检测 + 每 8h 自动检测 + 云端 `update` 命令触发；仅合宙可据 IMEI 推送。

## 二、模式说明

| 模式 | 触发条件 | 加载模块 | 业务 |
|---|---|---|---|
| 产测 | 无 `test_done` | factory.lua | USB VUART_0 响应产测指令 |
| 业务 SIP | `test_done` + `work_mode=sip`（默认） | app_main | SIP 通话 + 按键 + AirCloud 上报 |
| 业务 CC | `test_done` + `work_mode=cc` | cc_app_main | SIP↔手机(VoLTE) 中转 |
| 调试 BOOT_MODE | main.lua 顶部常量 | — | `auto`(默认)/`normal`/`factory`/`cc` 强制指定 |

> 产测↔业务：上位机 `TEST_DONE#` → 写 `test_done` → 3s 重启，无需重烧。
> SIP 与 CC 音频驱动对 Air1103 的 MIC 处理互斥，不能运行时热切换，故用"切标记 + 重启"。

## 三、目录结构

```
air8784_factory/
├── lib/                        
│   ├── libfota3.lua            # FOTA 升级库
│   ├── exsip.lua               # SIP 协议栈
│   ├── voip.lua / excloud.lua / httpplus.lua / exmtn
│   ├── exaudio.lua / air1103.lua# 音频（Air1103 语音芯片）
│   └── prodmeta.lua            # OTP 写号
└── user/
    ├── main.lua                # 入口：test_done 分流 SIP/CC/产测
    ├── factory.lua             # 产测模式
    ├── update.lua              # FOTA 封装（产测与业务模式都加载）
    ├── aircloud_data.lua       # AirCloud 上报 + 云端下行（业务模式共用）
    ├── netdrv_device.lua / netdrv/netdrv_4g.lua  # 网卡
    ├── sip/                    # SIP 云端通话模式
    │   ├── app_main.lua        #   业务编排：网络→SIP→按键→状态灯→心跳
    │   ├── config.lua          #   集中配置（SIP 服务器/账号/音频/按键/管脚）
    │   ├── sip_app_main.lua    #   SIP 状态机
    │   ├── audio_drv.lua       #   Air1103 音频适配
    │   ├── key_app.lua         #   按键：SOS 呼出/接听、UP 挂断
    │   └── msg_player.lua      #   语音留言播放
    └── cc/                     # CC 模式（sip_cc_demo 整套加 cc_ 前缀）
        ├── cc_app_main.lua        #   业务编排：音频→SIP→VoLTE→心跳
        ├── cc_sip_main.lua        #   SIP 状态机
        ├── cc_main.lua            #   VoLTE(CC) 状态机
        ├── cc_config.lua          #   CC 桥接配置（目标号读 fskv）
        ├── cc_audio_drv.lua       #   音频（CC 版）
        └── cc_bridge.lua          #   两侧通话桥接协调器
```

> 子目录仅为组织层级，`require` 按文件名解析；文件名必须全局唯一（不能有两个 `config.lua`）。

## 四、硬件引脚（主控 Air780EHM）

| 功能 | GPIO / 接口 | 说明 |
|---|---|---|
| 主 LED | GPIO24 | 高电平点亮，通话中常亮 |
| SMS 灯 | GPIO26 | |
| 网络灯 | GPIO27 | 联网成功点亮 |
| SOS 按键 | GPIO20 | 按下拉低；来电接听，空闲时向 IMEI+1 拨号；通话中忽略 |
| UP 按键 | GPIO21 | 短按播语音留言，长按（1s）挂断/拒接 |
| 语音芯片供电 | GPIO22 | `Air1103_EN`，拉高供电 |
| VREF | GPIO23 | 上拉参考电压，开机常开 |
| 语音芯片 | UART1 | Air1103，固定 2M 波特率，仅 PCM |
| 充电检测 | ADC0 | TP4055，无控制脚 |
| pwrkey | 接地 | 不可控 |

## 五、SIP 账号与通话规则

| 角色 | 账号 | 服务器 |
|---|---|---|
| 本机 | `IMEI + "0"` | cc.luatos.com:8910（密码 123456） |
| 软终端（microSIP/linphone） | `IMEI + "1"` | 同上 |

默认行为：单击 SOS → 向 `IMEI+1` 拨号（用户需先在软终端登录 `IMEI+1` 账号）。来电与呼叫目标同为一人，故 SOS 无需判断状态。

## 六、出厂配置基线

| 配置项 | 值 | 说明 |
|---|---|---|
| PROJECT | `Air8784_Factory` | |
| VERSION | `001.000.000` | |
| PRODUCT_KEY / AirCloud AuthKey | `AVbrqZ5tldhyJV8oXqLqa2jPmTey2zMg` | 必填，错填连不上 |
| SIP 服务器 | `cc.luatos.com:8910`（密码 `123456`） | |
| 上报周期 | `180` s | `cycle:N` 可改，fskv 持久化 |
| 主控 / core | Air780EHM / `LuatOS-SoC_V2052_Air780EHM_113.soc` | |

## 七、数据上报格式（AirCloud TLV）

| tag | 含义 | 类型 | 来源 |
|---|---|---|---|
| 782 | 4G 信号强度 | INTEGER | mobile.csq() |
| 783 | SIM ICCID | ASCII | mobile.iccid() |
| 798 | 设备 IMEI | ASCII | mobile.imei() |
| 799 | 电池电压 | INTEGER(mV) | adc.CH_VBAT |
| 263 | CPU 温度 | FLOAT(℃) | adc.CH_CPU（必须 /1000） |
| 1280 | 时间戳 | INTEGER(s) | os.time() |
| 269 | SIP 通话状态 | ASCII | SIP 状态机（CC 模式不上报） |

> 263 必须用 FLOAT 且 /1000：excloud 的 FLOAT 编码为 `value*1000`、平台 `/1000` 解码；用 INTEGER 传原始值会显示 33000℃。

## 八、下行控制命令（Tag 19/21/1281 → 回 Tag 20）

| 命令 | 格式 | 说明 |
|---|---|---|
| 上报频率 | `cycle:秒数`（最小 30） | fskv 持久化 |
| 主灯 | `led:on` / `led:off` / `led:blink` | GPIO24（blink 亮 5s 后灭） |
| 模式切换 | `mode:cc` / `mode:sip` | 写 `work_mode` 后 3s 重启 |
| 目标手机号 | `phone:号码` | 写 `cc_target_phone`，重启后生效（CC 模式） |
| 状态回读 | `status` / `read_all` | 返回 JSON（cpu_temp/vbat/csq/imei/sip_state/...） |
| 升级检查 | `update` / `fota` | 触发一次 FOTA 检测 |

通话控制（dial/hangup/answer）走后续 SIP MESSAGE 通道，不在 AirCloud。

## 九、产测指令

> 工程位置：`user/factory.lua`
> 通信：USB 虚拟串口 `uart.VUART_0`，波特率 115200，指令与回复均以 `#` 结尾（接收侧循环解析 `#` 分帧，支持粘包连发）

### 1. 启动模式（main.lua）

| test_done | 行为 |
|---|---|
| 无（默认） | 进入产测模式（`require "factory"`，独占 VUART_0 响应指令） |
| 有 | 进入正常模式（`require "app_main"`，SIP 通话 + 按键 + AirCloud 上报），串口不再响应任何产测指令 |

> 产测完成后发 `TEST_DONE#` 写 test_done 并重启进入正常模式。
> 需要重新产测：清 fskv 的 test_done 键（重烧勾「清除 KV」），或烧一个"清标记小工程"（`fskv.del("test_done")`）。

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
| `TEST_DONE#` | 测试完成（写 `fskv["test_done"]=true`，3s 重启进正常模式） | OK# |
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

## 十、使用说明

1. Luatools 烧录工程目录 + `lib/`（core = Air780EHM）。
2. **产测→业务**：上位机发 `TEST_DONE#` → 重启进业务模式，无需重烧。
3. **返修→产测**：重烧并勾「清除 KV」，或烧一个"清标记小工程"（`fskv.del("test_done")`）。
4. **模式切换**：云端 `mode:cc` / `mode:sip` → 3s 重启；CC 模式需插手机卡（VoLTE），SIP 模式用流量卡。
5. **FOTA**：合宙按 IMEI 推送；云端发 `update` 即时检测；开机与每 8h 自动检测。
6. **调试**：`main.lua` 顶部 `BOOT_MODE` 改 `normal`/`factory`/`cc` 可跳过产测检查。
7. **看门狗**：LuatOS 内置硬狗 9s 超时 / 3s 喂狗，默认启用。
