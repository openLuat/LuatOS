# Air8700 系列出厂固件（Air8700Factory）

> 负责人：李源龙（8700 系列）
>
> 技术底座：**标准 iRTU 固件 + 预置配置**，不自研 Lua 工程
>
> 本期范围：Air8700P（板载 Air700ECP，与 Air780EPM 同固件系列，代码可复用）

## 一、项目简介

本工程基于 `Air8780/project/factory`（Air8780 出厂固件）拆分而来，作为 Air8700P 出厂固件：

1. **不允许请求网页端配置**：`default.lua` 已移除 `config_init`，开机直接加载预置 `irtu.cfg`，默认通道 = **AirCloud**。
2. **定位：串口透传 + AirCloud 基础心跳上报 + LBS 基站定位**（IMEI/CSQ/CPU温度/基站经纬度），不采集传感器、不做 GPS、无音频功能。
3. **无外置硬件看门狗**：Air8700 板载无 Air153 看门狗芯片，仅保留 LuatOS 软狗 wdt（9s/3s，main.lua 通用）。
4. **下行控制命令**：支持 `cycle:秒数` / `led:blink|on|off`，保留 iRTU 原有 rrpc 指令（`rrpc,getimei` 等）。
5. **产测 + iRTU 合一（V3）**：产测指令仅保留通用项 + 写号（OTP），WD_TEST 返回 ERROR（无外置看门狗）。

### V3 启动分流（与 Air8780 完全一致）

`main.lua` 中 `BOOT_MODE = "auto"`（默认），按以下顺序判断：

1. fskv 有返工标记 `model_retest` → 产测模式（**返工产测，全程不动 OTP1**）
2. fskv 无标记且 OTP1 为空 → 产测模式（**首次产测**，通过后 MODEL/HVERSION 写号入 OTP1）
3. fskv 无标记且 OTP1 有值 → 正常模式（require irtu_main）

返工指令（USB VUART_0 文本协议，见 [retest.lua](retest.lua)）：

| 指令 | 作用 | 回复 |
|---|---|---|
| `MODEL_RETEST#CONFIRM#` | 魔法字校验后写 fskv 返工标记，800ms 后重启进产测 | `OK#` / `ERROR#` |
| `MODEL_RETEST?#` | 查询返工标记是否存在 | `HAS#` / `NONE#` |

- 正常模式下在 [driver.lua](driver.lua) 的 read() 中拦截（仅 VUART_0），命中不走 config/rrpc/透传；
- 产测模式下在 [factory.lua](factory.lua) 的 proc 前由 extract_retest 提取拦截；
- TEST_DONE 收尾双分支：首测校验 OTP1 非空；返工删除 `model_retest` 标记；任一校验失败不重启并返回 ERROR。
- 调试可用 `BOOT_MODE = "normal" / "factory"` 强制模式。

## 二、版本说明

| 版本 | `DEVICE_VER` | 硬件 | 定位 |
|---|---|---|---|
| Air8700P | `"8700"` | Air700ECP | 串口透传 + AirCloud 基础心跳 + LBS 基站定位 |

> 说明：Air8700P 板载 Air700ECP（4MB Flash + 4MB RAM），与 Air780EPM 同固件系列
> （`Air700ECP/Air780EPM/Air780EGP` 共用 32/64 位固件），因此 iRTU 代码完全兼容。

## 三、目录结构

```
Air8700/project/factory/
├── main.lua                 # 入口（产测+iRTU合一，V3：fskv返工标记→OTP1判空分流）
├── factory.lua              # ⭐ 产测模式（USB VUART_0 响应产测指令，仅通用项+写号）
├── retest.lua               # ⭐ V3 返工模块（model_retest 标记 + MODEL_RETEST 指令）
├── prodmeta.lua             # OTP 写号（PROD型号/PCB版本）
├── irtu_main.lua            # iRTU 功能初始化（default/driver/create）
├── default.lua              # 配置加载（已移除网页拉取，直连 AirCloud）
├── create.lua               # 网络通道（aircloudTask 心跳上报 + 下行命令）
├── driver.lua               # 串口 / GPIO灯 / rrpc指令 / 自动任务
├── gnss.lua                 # iRTU 自带GNSS模块（保留未用，8700 无内置GNSS）
├── factory_config.lua       # ⭐ 版本配置（8700 定位差异集中在这里）
├── air153c_watchdog.lua     # 外置看门狗 app 底层（8700 配置 disable，自动跳过）
├── watchdog_app.lua         # 外置硬件看门狗（8700 配置 disable，自动跳过）
├── update.lua               # FOTA 升级（libfota3 默认扩展库，开机即检测）
├── factory_app.lua          # 业务编排：心跳上报 / 控制命令 / LED / 上报周期
├── irtu.cfg                 # 预置配置（烧录到 /luadb/irtu.cfg）
├── irtu.json                # 配置参考（可导入 iRTU 配置工具）
└── README.md
```

> 依赖：`../lib/` 下的 iRTU 扩展库（db/dtulib/excloud/lbsLoc2/libnet 等），与 irtu_basic 相同。
> 外置看门狗驱动 `exair153x_wdt` 直接使用公共扩展库 `script/libs/exair153x_wdt.lua`（user 目录不再放定制版）；音频相关库（exaudio/es8311/air1103/audio_config）本工程已全部移除，烧录时无需勾选。

## 四、出厂配置基线（irtu.cfg）

| 配置项 | 值 | 说明 |
|---|---|---|
| 通道 | `aircloud` | AirCloud 协议 |
| 传输 | `tcp` | TCP 承载 |
| 心跳 | `300` s | keepAlive 超时（无事件时发心跳） |
| 自动采集间隔 | `180` s | 基础心跳上报周期（web 端 `cycle:N` 可改，fskv 持久化） |
| AuthKey | `JQtKg5M7h8HTMw8CgqMpRh77hySLlUwx` | **必填**，错填连不上；按实际项目密钥修改 |
| 串口1 | `115200,8,N,1` | 透传串口 |
| pins | `["pio17","pio26"]` | netled=17、netready=26，GPIO27 留给用户状态 LED |

**注意**：
- 出厂固件不在开机时同步网页端配置，改配置需重新烧录 `irtu.cfg` 或修改代码常量。
- web 端下发 `cycle:N` 会写入 fskv 并立即生效，断电不丢失。

## 五、数据上报格式（AirCloud TLV）

| tag | 含义 | 类型 | 是否必填 | 来源 |
|---|---|---|---|---|
| 782 | 4G 信号强度 | INTEGER | 必填 | mobile.csq() |
| 798 | 设备ID（IMEI） | ASCII | 必填 | mobile.imei() |
| 1280 | 时间戳 | INTEGER | 必填 | os.time() |
| 263 | CPU 温度 | FLOAT | 必填 | adc.CH_CPU |
| 513/512 | LBS 纬度/经度 | FLOAT | 可选 | lbsLoc2 基站定位，定位失败自动跳过 |

> LBS 基站定位为免费单基站定位，随 180s 周期上报一并发送，未取到基站信息时该字段自动跳过。

## 六、下行控制命令（tag 19 → 回 tag 20）

| 指令 | 格式 | 适配 |
|---|---|---|
| 设置上报频率 | `cycle:秒数`（最小 5） | 8700 |
| LED 控制 | `led:blink` / `led:on` / `led:off` | 8700 |
| 查询 IMEI | `rrpc,getimei`（走 tag 21 IRTU_DOWN） | 8700 |

## 七、使用说明

1. 用 Luatools 将本工程目录 + `../lib/` 扩展库一并烧录到 Air8700P。
2. 修改 `irtu.cfg` 中的 AuthKey 为实际 AirCloud 项目密钥。
3. **产测**：新板子 OTP1 为空默认进产测模式（USB VUART_0，指令见 factory.lua 指令表），首测写号后 `TEST_DONE#` 校验 OTP1 非空再重启进正常模式；返工时发 `MODEL_RETEST#CONFIRM#` 置标记后重启进产测。
4. 正常模式：开机直接连接 AirCloud，UART1 透传 + 180s 基础心跳（含 LBS 基站经纬度）上报。
5. **看门狗**：Air8700 板载无外置看门狗，仅软狗 wdt（9s/3s）防程序卡死。

## 八、主要改动对照（相对 Air8780/project/factory）

| 文件 | 改动 |
|---|---|
| main.lua | PROJECT=Air8700Factory；版本注释改为 8700P |
| factory_config.lua | DEVICE_VER="8700"；移除传感器 I2C/开关全部配置；lbs_enable 8700=true（开启基站定位）；wdt 8700=disable |
| 文件删除 | sensor_task.lua、AirSHT30_1000.lua、AirVOC_1000.lua（8700 不接温湿度/VOC 传感器） |
| factory_app.lua | LBS 按版本开关（8700 已开启基站定位上报）；移除 TTS 相关全部逻辑 |
| factory.lua | exair153x_wdt 改 pcall 加载；8700 跳过看门狗初始化；WD_TEST 返回 ERROR；移除 RECORD/PLAY 等 8780V 音频指令 |
| create.lua | 移除 audio_result 订阅与 tcp/mqtt/aircloud 三处 audioresult_ 异步回包路由 |
| driver.lua | 移除 exaudio/audio_config require 与 ttsplay/fileplay/stopplay/setvol/getvol 五个音频 rrpc 指令 |
| 文件删除 | audio_config.lua、es8311.lua、exair153x_wdt.lua（看门狗改用 script/libs 扩展库） |
| watchdog_app.lua | 已支持 enable 开关（8700 disable 自动跳过） |
| README.md | 重写为 Air8700 版 |
