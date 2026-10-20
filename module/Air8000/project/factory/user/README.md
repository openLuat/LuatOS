# Air8000 系列出厂固件（Air8000Factory）

> 技术底座：**标准 iRTU 固件 + 预置配置**，参考 Air8780 出厂固件架构移植到 Air8000（EC718）平台
>
> 本期范围：Air8000 全系（A/W/G/T 等）+ Air8101（WiFi）+ PC 模拟器，共 6 个版本一套固件

## 一、项目简介

本工程基于标准 iRTU 固件改造，作为 Air8000 系列出厂固件：

1. **不允许请求网页端配置**：`default.lua` 已移除网页拉取（原从 iot.openluat.com 拉取参数），开机直接加载预置 `irtu.cfg`，默认通道 = **AirCloud**。
2. **产测 + 正常模式合一（V3 分流）**：`main.lua` 按 fskv 返工标记 `model_retest` → OTP1 判空 → 分流到 `factory`（产测）或 `irtu_main`（正常）。
3. **多网卡适配**：`netdrv_device.lua` 按版本把网卡分流到 `netdrv/` 下 5 个文件（4G / WiFi / SPI 外挂 CH390H 以太网 / 多网融合 / PC）；4G 走 `socket.LWIP_GP`，WiFi 走 `LWIP_STA`，以太网走 `LWIP_ETH`。
4. **非 4G 版本无 mobile 库**：WiFi/ETH 版本调用任何 `mobile.*` 都会崩溃，全工程以 `factory_config.get_netdev()` 派生 `MOBILE_SUPPORT` 守卫；无 IMEI 的版本用 `mcu.unique_id()` 生成设备 ID 并落 fskv `dev_id`。
5. **传感器走硬件 I2C0**：`sensor_task.lua` 读取 AirSHT30_1000（温湿度，地址 0x44）与 AirVOC_1000（TVOC，地址 0x1A），采集失败不影响主数据上报。
6. **结构化 TLV 上报**：`factory_app.lua` 构建 AirCloud 结构化 TLV 数据（经 excloud），默认 180 秒上报一次。
7. **下行控制命令**：支持 `cycle:秒数` / `led:blink|on|off` / `tts:文本`（仅 8000T），保留 iRTU 原有 rrpc 指令。
8. **一套固件，6 个版本**：所有版本差异集中在 `factory_config.lua`，烧录时只需改 `DEVICE_VER` 一个变量。

## 二、6 个版本说明

| 版本 | `DEVICE_VER` | 网卡 | device_type | 差异能力 |
|---|---|---|---|---|
| **版本1** | `"8000"` | 4G（LWIP_GP） | 1 | 定时结构化上报(180s) + 串口透传（基准版，覆盖 A/W/G/T/U/N 等 4G 形态） |
| **版本2** | `"8000T"` | 4G | 1 | 基准版基础上 + 每 10 秒 exaudio 播报"上海合宙欢迎你"（es8311），传感器/GNSS 默认关 |
| **版本3** | `"8000G"` | 4G | 1 | 基准版基础上 + 开机开内置 GNSS（默认串口2/115200），每 30 秒上报（无 GNSS 回退 LBS） |
| **版本4** | `"8000W"` | WiFi STA（LWIP_STA，Air8101） | 2 | 网卡改 WiFi，exnetif 配 WIFI 优先；无 IMEI，设备 ID 用 unique_id |
| **版本5** | `"8000D"` | SPI 外挂 CH390H 以太网（LWIP_ETH） | 1 | pwrpin=GPIO140 / spi1(38,39) / cs=GPIO12；设备 ID 用 unique_id |
| **版本6** | `"8000M"` | 多网融合 | 1 | exnetif 优先级 ETHERNET → WIFI → LWIP_GP，具备 mobile 库 |

> **看门狗**：6 个版本默认启用 Air153 外置硬件看门狗（GPIO160 喂狗，180s 周期，exair153x_wdt）+ LuatOS 软狗 wdt（main.lua 中 `wdt.init(9000)`），两者共存互不影响。
>
> **音频硬件**：开发板 es8311 走 I2C0，功放使能 pa_ctrl=GPIO162、dac_ctrl=GPIO164（核心板为 17/16），`audio_config.lua` 按固件能力自适应；play_start/play_stop 只在 task 中调用。
>
> 切换版本：修改 [factory_config.lua](factory_config.lua) 顶部 `DEVICE_VER` 后重新烧录即可。

## 三、目录结构

```
factory/
├── user/
│   ├── main.lua                 # 入口（V3：fskv返工标记→OTP1判空→产测/正常分流；软狗/FOTA）
│   ├── factory.lua              # ⭐ 产测模式（USB VUART_0 响应产测指令，首测/返工区分）
│   ├── retest.lua               # ⭐ V3 返工指令（MODEL_RETEST#CONFIRM 写fskv标记/查询/删除）
│   ├── prodmeta.lua             # OTP 写号（PROD型号/PCB版本，air8000 zone=1/max256）
│   ├── irtu_main.lua            # iRTU 正常模式初始化（netdrv_device→default→driver→create→watchdog）
│   ├── netdrv_device.lua        # ⭐ 网卡分流（bsp PC/Air8101 + config netdev → netdrv/ 5 文件）
│   ├── netdrv/
│   │   ├── netdrv_4g.lua        #   4G：socket.LWIP_GP
│   │   ├── netdrv_wifi.lua      #   WiFi STA：socket.LWIP_STA
│   │   ├── netdrv_eth_spi.lua   #   SPI 外挂 CH390H：socket.LWIP_ETH（pwr140/spi1/cs12）
│   │   ├── netdrv_multiple.lua  #   多网：exnetif 优先级 ETHERNET→WIFI→LWIP_GP
│   │   └── netdrv_pc.lua        #   PC 模拟器：ETH0
│   ├── default.lua              # 配置加载（预置irtu.cfg直连AirCloud）/GPIO集/NTP/功耗
│   ├── create.lua               # 网络通道（TCP/UDP/MQTT/AirCloud任务工厂，MOBILE_SUPPORT守卫）
│   ├── driver.lua               # 串口 / GPIO灯（4G按注网、非4G按链路双分支）/ rrpc / 自动采集
│   ├── gnss.lua                 # iRTU 自带 GNSS 模块（exgnss，保留）
│   ├── audio_config.lua         # ⭐ exaudio 新框架（es8311/I2C0/pa162/dac164，单播放队列）
│   ├── factory_config.lua       # ⭐ 6 版本差异集中配置（改 DEVICE_VER 即可切换）
│   ├── watchdog_app.lua         # 外置硬件看门狗（Air153，exair153x_wdt 按版本启用）
│   ├── air153c_watchdog.lua     # Air153C 独立驱动参考件（当前业务走 exair153x_wdt，保留）
│   ├── factory_app.lua          # 业务编排：TLV/GNSS构建 / 控制命令 / LED / TTS / 上报周期
│   ├── sensor_task.lua          # I2C 传感器采集（SHT30 + VOC，硬件I2C0，独立容错）
│   ├── AirSHT30_1000.lua        # SHT30 驱动（支持硬件 id/软I2C 对象双入参）
│   ├── AirVOC_1000.lua          # AGS02MA VOC 驱动（同上）
│   ├── update.lua               # libfota3 远程升级（project=Air8000Factory，8h 周期）
│   ├── irtu.cfg                 # 预置配置（烧录到 /luadb/irtu.cfg）
│   ├── irtu.json                # 配置参考（可导入 iRTU 配置工具）
│   └── README.md
└── lib/                         # iRTU 扩展库（db/dtulib/mapTile/testdebug/utils 等）
```

> es8311 / exaudio / exgnss / exair153x_wdt / libfota3 均直接引用 `script/libs` 公共库（烧录时勾选「添加默认 lib」），本目录不放副本。

## 四、出厂配置基线（irtu.cfg）

| 配置项 | 值 | 说明 |
|---|---|---|
| 通道 | `aircloud` | AirCloud 协议 |
| 传输 | `tcp` | TCP 承载 |
| 心跳 | `300` s | keepAlive 超时 |
| 自动采集间隔 | `180` s | 结构化上报周期（web 端 `cycle:N` 可改，fskv 持久化） |
| AuthKey | `JQtKg5M7h8HTMw8CgqMpRh77hySLlUwx` | AirCloud 项目鉴权密钥（沿用 iRTU 预置值，**量产前必须替换为 Air8000 在 AirCloud 注册的项目密钥**） |
| 串口1 | `115200,8,N,1` | 透传串口 |
| pins | `["pio17","pio26"]` | netled=GPIO17、netready=GPIO26，均在 Air8000 全部版本可用 GPIO 集合内 |

注意：

- `irtu.cfg` 的 AuthKey（AirCloud 鉴权）与 `main.lua` 的 `PRODUCT_KEY`（iotda FOTA 升级鉴权，`SIsRml1ImTsP6XR4lvRAQVuksbZZuUpO`）是**两套独立密钥**，互不通用，均需按 Air8000 实际项目核对替换。
- 出厂固件开机不同步网页端配置，改配置需重新烧录 `irtu.cfg` 或修改代码常量。
- web 端下发 `cycle:N` 会写入 fskv 并立即生效，断电不丢失。

## 五、数据上报格式（AirCloud TLV）

| tag | 含义 | 类型 | 4G 版 | 非 4G 版 | 来源 |
|---|---|---|---|---|---|
| 782 | 信号强度 | INTEGER | mobile.csq() | 跳过/固定值 | 仅 MOBILE_SUPPORT |
| 798 | 设备 ID | ASCII | mobile.imei() | unique_id 派生 `dev_id` | fskv 持久化 |
| 1280 | 时间戳 | INTEGER | 必填 | 必填 | os.time()（NTP 后） |
| 263 | CPU 温度 | FLOAT | 必填 | 必填 | adc.CH_CPU |
| 256/257/258 | 环境温度/湿度/TVOC | FLOAT | 可选 | 可选 | SHT30(0x44) / AGS02MA(0x1A)，I2C0 |
| 513/512 | 纬经度 | FLOAT | 可选 | 可选 | 8000G 走 GNSS，其余 LBS |

> 任一可选字段采集失败即跳过，不影响其余数据上报。

## 六、下行控制命令（tag 19 → 回 tag 20）

| 指令 | 格式 | 适配 |
|---|---|---|
| 设置上报频率 | `cycle:秒数`（最小 5） | 全系 |
| LED 控制 | `led:blink` / `led:on` / `led:off` | 全系（GPIO21） |
| TTS 播报 | `tts:文本` | 仅 8000T |
| rrpc 查询 | `rrpc,getimei` / `getcsq` / `getnetmode` / `geticcid` 等（tag 21 IRTU_DOWN） | 非 4G 版 unsupported 字段返回 `unsupported`，getimei 返回 dev_id |

执行后以 tag 20（CONTROL_RESPONSE）回复执行结果。

## 七、网卡与联网说明

- **等待 IP 固定模式**：`while not socket.adapter(socket.dft()) do sys.waitUntil("IP_READY", 1000) end`，超时参数 1000ms 不可改长。
- **exnetif 多网优先级**（8000M/WiFi/ETH）：`exnetif.set_priority_order(...)` 必须在 task 中调用；IP_READY 后统一 `socket.setDNS(socket.dft(), 223.5.5.5, 114.114.114.114)`。
- netdrv 文件内含官方测试热点（ssid=`茶室-降功耗,找合宙!` / password=`Air123456`），量产前替换为实际 SSID 或改为配置下发。
- netled 行为：4G 版按 `mobile.status()` 注网阶段呼吸闪烁；非 4G 版只按数据链路（`create.getDatalink()`）快慢闪。

## 八、传感器接入说明

- Air8000 全部 6 版本传感器统一走**硬件 I2C0**（SCL=pin80 / SDA=pin81，`i2c.FAST` 400kHz）。
- VCC 必须接板载 3.3V，禁止 GPIO 供电（VOC 含加热元件，20~30mA 级）。
- SHT30（0x44）与 AGS02MA（0x1A）可挂同一条 I2C0，地址不冲突。
- 驱动 `open(bus)` 同时支持 number（硬件 id 0/1）与 userdata（软 I2C 对象），便于成品板改软 I2C。
- 每个传感器独立容错：失败不阻断上报，连续失败 10 次（MAX_FAIL）后该传感器停止重试。

## 九、产测模式与产测指令

裸板 OTP1 为空时开机自动进产测模式，经 **USB VUART_0** 收发，指令统一以 `#` 结尾。

| 指令 | 说明 | 适配版本 |
|---|---|---|
| `VERSION#` | 返回工程名_版本号（Air8000Factory_001.001.000） | 全系 |
| `IMEI#` / `IMSI#` / `ICCID#` / `CSQ#` / `MUID#` | 模组身份与信号查询 | 4G 版有效 |
| `VBAT#` | 电池电压 | 全系 |
| `ECNPICFG#` | eSIM 配置检测（需固件开 LUAT_USE_MOBILE_ECNPICFG） | 4G 版 |
| `MODEL,xxx#` / `MODEL?#` | 写入/查询 OTP PROD 型号 | 全系 |
| `HVERSION,xxx#` | 写入 OTP PCB 硬件版本 | 全系 |
| `LED#` | LED 测试（GPIO21） | 全系 |
| `WD_TEST#` / `WD_TEST,1#` | 停止喂狗触发硬复位 / 恢复正常喂狗 | 全系 |
| `FLYMODE,0#` / `FLYMODE,1#` | 退出/进入飞行模式 | 4G 版 |
| `RECORD#` / `PLAY#` | 录音 5s / 回放（exaudio） | 仅 8000T |
| `GPSTEST#` | 内置 GNSS 串口透传测试（exgnss 串口2） | 仅 8000G |
| `PCBA_TEST_DONE#` | PCBA 段测试完成标记 | 全系 |
| `TEST_DONE#` | 首测：校验 OTP1 非空后重启进正常模式；返工：删 fskv 标记（不动 OTP1）后重启 | 全系 |
| `RST#` | 软重启 | 全系 |
| `MODEL_RETEST#CONFIRM#` | 正常/产测模式均可收：写 fskv 返工标记并重启进产测 | 全系 |
| `MODEL_RETEST?#` | 查询返工标记状态 | 全系 |

> 非 4G 版本（8000W/8000D）收到 `IMEI/IMSI/ICCID/CSQ/MUID/ECNPICFG/FLYMODE` 指令时直接返回 `ERROR,unsupported`（MOBILE_SUPPORT 守卫），不调用 mobile 库，避免崩溃。

产测流程：裸板进产测 → `MODEL,xxx#` / `HVERSION,xxx#` 写号入 OTP1（air8000：zone=1，max_len=256，擦后重写，4 字节对齐补 0xFF）→ 各项测试 → `TEST_DONE#` 校验非空后重启进正常模式。返工时正常模式 USB 发 `MODEL_RETEST#CONFIRM#` 即回产测。

## 十、使用说明

1. 用 Luatools 将本工程目录 + `lib/` 扩展库一并烧录，勾选「添加默认 lib」。
2. **切换版本**：修改 `factory_config.lua` 顶部 `DEVICE_VER`（`8000`/`8000T`/`8000G`/`8000W`/`8000D`/`8000M`），重新烧录。
3. 量产前替换两处密钥：`irtu.cfg` 的 AuthKey（AirCloud）与 `main.lua` 的 PRODUCT_KEY（FOTA）。
4. WiFi/ETH 版替换 netdrv 文件内测试热点为实际网络配置。
5. 产测写号与流程见第九章；8000T 联网后周期播报，8000G 烧录后自动开 GNSS。
6. 外置看门狗默认 GPIO160/180s，喂狗脚不同时改 `factory_config.lua` 的 `wdt.pin`。

## 十一、相对 Air8780 出厂固件的主要移植改动

| 文件 | 改动 |
|---|---|
| factory_config.lua | 版本矩阵改 6 版本（8000/T/G/W/D/M）；新增 netdev、device_type、net_pin；I2C 全改硬件 id=0；GNSS 默认 uart=2；wdt.pin=160；led=21 |
| main.lua | PROJECT=Air8000Factory；VERSION=001.001.000；PRODUCT_KEY 改 Air8000 iotda key；prodmeta 走 air8000 分支；保留 V3 分流与软狗 |
| netdrv_device.lua / netdrv/ | **新增**：bsp(PC/Air8101) + config 双维度网卡分流，5 个网卡文件 |
| irtu_main.lua | 顶部 `require "netdrv_device"` 先建链再初始化业务；watchdog_app 照旧加载 |
| create.lua | 全部 mobile 直调加 MOBILE_SUPPORT 守卫；新增 get_dev_id（非4G unique_id 落 fskv）；excloud device_type 改 config 取值 |
| default.lua | GPIO 集按 Air8000 引脚体系（含 140/160/162/164 扩展脚）；APN/ipv6/RNDIS 加 4G 守卫；Air8000G GNSS 复用 Air8000A 引脚集 |
| driver.lua | APN/simcross/LBS 等指令加守卫；rrpc 非4G 返回 unsupported/dev_id；netled 重写为注网状态/数据链路双分支；透传识别码用 get_dev_id |
| audio_config.lua | **重写**：exaudio 新框架替旧音频 API，es8311 + I2C0 + pa162/dac164 + dac_delay 版本自适应，单播放任务队列 |
| factory_app.lua | COMPONENT_MODEL=Air8000；exgnss setup 用 `uart` 键；信号/LBS 字段加守卫；按版本 TTS/GNSS |
| prodmeta.lua | 新增 air8000 分支（zone=1/max256/append_only=false，擦后写补 0xFF） |
| update.lua | FOTA script_name 改 Air8000Factory |
| gnss.lua / sensor_task.lua / AirSHT30_1000.lua / AirVOC_1000.lua | 复核确认 API 兼容（exgnss uart 键、I2C0、地址 0x44/0x1A、CRC 校验），无改动 |
