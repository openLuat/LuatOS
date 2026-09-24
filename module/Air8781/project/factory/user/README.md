# Air878x 系列出厂固件（irtu_8780_factory）

> 负责人：李源龙（878x 系列）
>
> 技术底座：**标准 iRTU 固件 + 预置配置**，不自研 Lua 工程
>
> 本期范围：Air8780 全系（P/H/N/G/S/V/U）+ Air8781P / 8782P

## 一、项目简介

本工程基于 `irtu_basic`（标准 iRTU）改造，作为 Air878x 系列出厂固件：

1. **不允许请求网页端配置**：`default.lua` 已移除 `config_init`（原从 iot.openluat.com 拉取参数），开机直接加载预置 `irtu.cfg`，默认通道 = **AirCloud**。
2. **传感器走 I2C**：`sensor_task.lua` 读取 AirSHT30_1000（温湿度，地址 0x44）与 AirVOC_1000（TVOC，地址 0x1A），取代原先串口透传方案，采集失败不影响主数据上报。
3. **结构化 TLV 上报**：`factory_app.lua` 构建 AirCloud 结构化 TLV 数据（与 web 端字段一致），默认 180 秒上报一次。
4. **下行控制命令**：支持 `cycle:秒数` / `led:blink|on|off` / `tts:文本`（仅 8780V），保留 iRTU 原有 rrpc 指令（`rrpc,getimei` 等）。
5. **一套固件，5 个版本**：所有版本差异集中在 `factory_config.lua`，烧录时只需改 `DEVICE_VER` 一个变量。

## 二、5 个版本说明

| 版本 | `DEVICE_VER` | 硬件 | I2C | 差异能力 |
|---|---|---|---|---|
| **版本1** | `"8780"` | 8780 全系（P/H/N/U） | 硬件I2C(id=1) | 定时结构化上报(180s) + 串口透传（基准版） |
| **版本2** | `"8780V"` | 8780V（Air780EHV） | 硬件I2C(id=1) | 版本1基础上 + 开机播报一次欢迎语，收到服务器 `tts:` 命令时播报 |
| **版本3** | `"8780G"` | 8780G（Air780EGP/EGG） | 硬件I2C(id=1) | 版本1基础上 + 开机开GPS，每30秒上报GPS（无GPS回退LBS） |
| **版本4** | `"8781"` | 8781P 成品板 | **软件I2C**(GPIO26/28) | 版本1基础上，传感器改软件I2C |
| **版本5** | `"8782"` | 8782P 成品板 | **软件I2C**(GPIO27/21) | 版本4基础上，串口1配置为 RS485 |

> **看门狗**：5 个版本板子均带 Air153 外置硬件看门狗（默认 GPIO24 喂狗，180s 周期）+ LuatOS 软狗 wdt（9s/3s，main.lua 通用），全部默认启用。

> 切换版本：修改 [factory_config.lua](factory_config.lua) 顶部 `DEVICE_VER` 变量后重新烧录即可。

## 三、目录结构

```
irtu_8780_factory/
├── main.lua                 # 入口（产测+iRTU合一，test_done 分流）
├── factory.lua              # ⭐ 产测模式（USB VUART_0 响应产测指令，按版本聚合）
├── prodmeta.lua             # OTP 写号（PROD型号/PCB版本）
├── irtu_main.lua            # iRTU 功能初始化（default/driver/create）
├── default.lua              # 配置加载（已移除网页拉取，直连 AirCloud）
├── create.lua               # 网络通道（aircloudTask 结构化/GPS上报 + 下行命令）
├── driver.lua               # 串口 / GPIO灯 / rrpc指令 / 自动任务 / 8782的485配置
├── gnss.lua                 # iRTU 自带GNSS模块（保留，出厂用 factory_app 内置GPS逻辑）
├── audio_config.lua         # 音频/TTS（8780V 使用）
├── es8311.lua               # es8311 音频芯片驱动（8780V 产测录音/播放）
├── factory_config.lua       # ⭐ 版本配置（5个版本差异集中在这里，改DEVICE_VER即可切换）
├── watchdog_app.lua         # 外置硬件看门狗（Air153，按版本启用）
├── exair153x_wdt.lua        # Air153C/Air153D 看门狗扩展库
├── factory_app.lua          # 业务编排：TLV/GPS构建 / 控制命令 / LED / TTS / 上报周期
├── sensor_task.lua          # I2C 传感器采集（SHT30 + VOC，容错 + 按版本硬/软I2C）
├── AirSHT30_1000.lua        # SHT30 驱动（支持硬件/软件 I2C）
├── AirVOC_1000.lua          # AGS02MA VOC 驱动（支持硬件/软件 I2C）
├── irtu.cfg                 # 预置配置（烧录到 /luadb/irtu.cfg）
├── irtu.json                # 配置参考（可导入 iRTU 配置工具）
├── 产测指令文档.md           # ⭐ 产测指令说明（指令表/管脚/测试流程）
└── README.md
```

> 依赖：`../lib/` 下的 iRTU 扩展库（db/dtulib/excloud/lbsLoc2/libnet/exgnss 等），与 irtu_basic 相同。

## 四、出厂配置基线（irtu.cfg）

| 配置项 | 值 | 说明 |
|---|---|---|
| 通道 | `aircloud` | AirCloud 协议 |
| 传输 | `tcp` | TCP 承载 |
| 心跳 | `300` s | keepAlive 超时（无事件时发心跳） |
| 自动采集间隔 | `180` s | 结构化上报周期（web 端 `cycle:N` 可改，fskv 持久化） |
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
| 256 | 环境温度 | FLOAT | 可选 | SHT30 |
| 257 | 环境湿度 | FLOAT | 可选 | SHT30 |
| 258 | TVOC 颗粒数 | FLOAT | 可选 | AGS02MA |
| 513 | 纬度 | FLOAT | 可选 | LBS 基站定位 |
| 512 | 经度 | FLOAT | 可选 | LBS 基站定位 |

> 任一可选字段采集失败即跳过，不影响其余数据上报。
> 字段编号与 web 端（index.html 的 `list_by_tags` 查询 tag）一致。

## 六、下行控制命令（tag 19 → 回 tag 20）

| 指令 | 格式 | 适配 |
|---|---|---|
| 设置上报频率 | `cycle:秒数`（最小 5） | 全系 |
| LED 控制 | `led:blink` / `led:on` / `led:off` | 全系 |
| TTS 播报 | `tts:文本` | 仅 8780V |
| 查询 IMEI | `rrpc,getimei`（走 tag 21 IRTU_DOWN） | 全系 |

执行后以 tag 20（CONTROL_RESPONSE）回复执行结果。

## 七、传感器接入说明

- **硬件 I2C 优先**（默认）：`sensor_task.lua` 中 `I2C_MODE="hw"`，`HW_I2C_ID=1`（Air780EPM 常走 I2C1，SDA/SCL ≈ PIN66/67，400kHz）。
- **软件 I2C 兜底**：`I2C_MODE="sw"`，`SW_SCL_PIN/SW_SDA_PIN` 指定 GPIO（8781P：GPIO26/GPIO28；8782P：GPIO27/GPIO21，按接线修改），≤100kHz。
- 软件 I2C 必须外挂上拉电阻（典型 4.7kΩ 到 3.3V）；AGPIO 驱动能力弱，务必接好再调。
- **VCC 必须接板载 3.3V，禁止 GPIO 供电**（VOC 含加热元件，电流 20~30mA 级）。
- 两个传感器可挂同一条 I2C 总线（0x44 与 0x1A 不冲突）。
- 官方驱动库原只支持硬件 I2C，本工程驱动已改造为硬件/软件 I2C 双模式（`open(bus)` 传 number 或软 I2C 对象均可）。
- 每个传感器独立容错：失败不阻断上报，连续失败 10 次后停止重试该传感器。

## 八、使用说明

1. 用 Luatools 将本工程目录 + `../lib/` 扩展库一并烧录到模块。
2. **切换版本**：修改 `factory_config.lua` 顶部 `DEVICE_VER`（`"8780"` / `"8780V"` / `"8780G"` / `"8781"` / `"8782"`），重新烧录即可。
3. 修改 `irtu.cfg` 中的 AuthKey 为实际 AirCloud 项目密钥（`JQtKg5M7h8HTMw8CgqMpRh77hySLlUwx` 为 irtu_basic 预置值，需确认）。
4. 按板子接线确认软件I2C引脚（8781/8782）与 LED 引脚（`factory_config.lua` / `factory_app.lua`）。
5. **产测**：新板子默认进产测模式（USB VUART_0，指令见 [产测指令文档.md](产测指令文档.md)），完成 `TEST_DONE#` 后重启进正常模式。
6. 8780V：开机联网后播报一次欢迎语；收到服务器 `tts:文本` 命令时播报对应文本。
7. 8780G：烧录后自动开GPS，每30秒上报一次（无GPS自动回退LBS基站定位）。
8. 8782：串口1自动配置为 RS485（方向脚默认 GPIO26，按实际板子修改 `factory_config.lua` 的 `uart485.dir_pin`）。
9. **看门狗**：所有版本默认启用外置看门狗（GPIO24 喂狗，180s 周期），如板子喂狗脚不同，修改 `factory_config.lua` 的 `wdt.pin`。

## 九、主要改动对照（相对 irtu_basic）

| 文件 | 改动 |
|---|---|
| main.lua | 改为产测+iRTU 合一（test_done 分流）；PROJECT=Air8780Factory；VREF(GPIO23) 常开 |
| factory.lua | **新增**：产测模式，按版本聚合 5 型号产测指令（基础/写号/音频/GPS/485） |
| prodmeta.lua | **新增**：OTP 写号（PROD 型号 / PCB 硬件版本） |
| es8311.lua | **新增**：es8311 音频驱动（8780V 产测录音/播放） |
| default.lua | 移除 config_init（网页拉配置 + FOTA 循环），直接发布 DTU_PARAM_READY；联网后 NTP 同步 |
| create.lua | aircloudTask 增加周期结构化 TLV 上报 + GPS上报 + tag19 控制命令处理；保留串口透传/rrpc |
| factory_config.lua | **新增**：5 个版本差异集中配置（I2C模式/引脚、TTS、GPS、485、看门狗、上报周期） |
| factory_app.lua | **新增**：上报/GPS TLV 构建 / cycle、led、tts 命令处理 / LED 控制 / 上报周期 fskv / 按版本启动TTS与GPS |
| watchdog_app.lua | **新增**：外置看门狗按版本启用（Air153，exair153x_wdt 自动喂狗） |
| sensor_task.lua | 新增：SHT30 + VOC I2C 采集（按版本硬/软 I2C、独立容错） |
| driver.lua | 按版本覆盖串口配置（8782 串口1 配置为 RS485） |
| AirSHT30_1000.lua / AirVOC_1000.lua | 驱动支持硬件/软件 I2C 双模式 |
| irtu.cfg / irtu.json | 预置 AirCloud 通道（180s 采集 / 300s 心跳 / 115200 串口1） |
