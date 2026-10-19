# Air780EGG/EGP/EGH 出厂固件（Air780EGxFactory）

> 技术底座：**标准 iRTU 固件 + 预置配置**，开机直接进入正常上报模式
>
> 适用硬件：**Air780EGG / Air780EGP / Air780EGH 内置 GNSS 核心板（单一固定配置，不区分型号/版本）**
>
> 日期：2026.10.16

## 一、项目简介

本工程基于标准 iRTU 改造，作为 Air780EGG / Air780EGP / Air780EGH 三款核心板共用的出厂固件。**固定单一硬件配置，不用 `DEVICE_VER` 等变量在型号间切换**：

1. **不请求网页端配置**：`default.lua` 开机直接加载预置 `irtu.cfg`，默认通道 = **AirCloud**。
2. **开机即开内置 GNSS**：由 `factory_app.lua` 经 `exgnss` 常开模组内置 GNSS，固定挂 **UART2 / 115200**，电源走模组电源轨 `pm.power(pm.GPS)`，**无外挂供电脚**（不传 `gnss_volgpio`）。
3. **单一 30 秒上报通道**：仅保留一条周期上报，默认每 **30 秒**构建一次结构化 TLV，包含 4G 信号 / 模组型号 / IMEI / 时间戳 / CPU 温度 + 定位；型号由 `rtos.bsp()` 动态读取（Air780EGG 上报 `Air780EGG`，EGP/EGH 同理）；GNSS 未定位时**回退 LBS 基站定位**，并在 TLV 中带定位方式（2=GNSS / 1=LBS）。
4. **无传感器**：本工程已移除 SHT30 温湿度、AGS02MA VOC 驱动及 `sensor_task` 采集模块，TLV 不上报任何温湿度/VOC 字段（CPU 温度来自模组内部 ADC，非外接传感器）。
5. **串口透传 + 下行控制**：UART1（115200）透传；支持 `cycle:秒数` / `led:blink|on|off`，保留 iRTU 原有 rrpc 指令。
6. **仅内核软狗**：使用 main.lua 中的 LuatOS 软狗 `wdt`（9s 超时 / 3s 喂狗）。**无外置看门狗、无音频 codec**。

> 与 Air8780G 的差异：Air8780G 的 GNSS 为外挂方案，靠 GPIO21 拉高供电（`gnss_volgpio=21`）；本系列三款为**内置** GNSS，由 `pm.GPS` 电源轨供电，故本工程无 GPIO21 / gnssPower 相关代码。
>
> 与产测 V3 工程（Air8780 / Air780EHV）的差异：本工程**不含** fskv/OTP 自动分流与 `MODEL_RETEST#CONFIRM` 返工指令，main.lua 开机无条件加载 `irtu_main`。

## 二、目录结构

```
factory_egg_p_h/
├── lib/                     # iRTU 通用扩展库（db/dtulib/mapTile/testdebug/utils）
└── user/
    ├── main.lua             # ⭐ 入口：开机直接 require "irtu_main"；软狗 wdt；FOTA；IRTU_DISABLE_UART2
    ├── irtu_main.lua        # 正常模式初始化（default/driver/create）
    ├── default.lua          # 配置加载 + 固定 GPIO 引脚集（直连 AirCloud，已移除网页拉取）
    ├── create.lua           # 网络通道（aircloudTask 单一30s结构化上报 + 下行命令 + 串口透传）
    ├── driver.lua           # 串口 / GPIO 灯 / rrpc 指令 / 自动任务（UART2 受门控不初始化）
    ├── gnss.lua             # iRTU 自带 GNSS 模块（本套用 exgnss，保留供复用）
    ├── factory_config.lua   # ⭐ Air780EGG/EGP/EGH 固定配置（内置GNSS常开 / LBS兜底 / 30s上报）
    ├── factory_app.lua      # 业务编排：build_uplink_tlv / 控制命令 / LED / 上报周期
    ├── factory.lua          # 旧版产测模式（保留供复用，main.lua 不会自动加载，见第八节）
    ├── update.lua           # 升级任务（开机检测 + 每 8h；require 默认库 libfota3）
    ├── irtu.cfg             # 预置配置（烧录到 /luadb/irtu.cfg）
    ├── irtu.json            # 配置参考（可导入 iRTU 配置工具）
    └── README.md
```

> 依赖：
> - `../lib/` 下的 iRTU 扩展库（db/dtulib 等），与标准 iRTU 相同。
> - **默认扩展库 `script/libs`** 中的 `libfota3`、`prodmeta`：工程内不再放同名本地副本，LuaTools 烧录时需勾选「添加默认 lib」。

## 三、开机行为

`main.lua` 开机**无条件**进入正常模式：

1. `fskv.init()` → GPIO23 上拉常开 → 内核软狗 wdt（9s/3s）→ `update.init()` 后台 FOTA。
2. 直接 `require "irtu_main"`：`default.init()` 加载预置 irtu.cfg → `driver.init()` 串口/GPIO → `create.start()` AirCloud 连接，同时开机即开内置 GNSS。

> 烧录即正常，重烧同样固件行为不变（本工程不读 OTP/fskv 做开机判断）。

## 四、UART2 独占（关键）

内置 GNSS 固定占用 **UART2（115200）**。为防止 iRTU 串口驱动抢占 UART2，`main.lua` 在加载任何 iRTU 代码前**无条件**置位：

```lua
_G.IRTU_DISABLE_UART2 = true
```

`driver.lua` 的 UART2 初始化受该标志门控，置位后不会 `uart.setup(2)`，从而保证 GNSS 独占。

## 五、出厂配置基线（irtu.cfg）

| 配置项 | 值 | 说明 |
|---|---|---|
| 通道 | `aircloud` | AirCloud 协议 |
| 传输 | `tcp` | TCP 承载 |
| 心跳 | `300` s | keepAlive 超时（无事件时发心跳） |
| 周期上报间隔 | `30` s | 唯一上报通道周期（`factory_config.report_cycle`） |
| AuthKey | `JQtKg5M7h8HTMw8CgqMpRh77hy2hZ0o` | **必填**，错填连不上；按实际项目密钥修改 |
| 串口1 | `115200,8,N,1` | 透传串口（UART2 被 GNSS 独占，不可配） |
| pins | `["pio17","pio26"]` | netled=17、netready=26；**GPIO27 留给用户状态 LED** |

**注意**：

- 出厂固件不在开机时同步网页端配置，改配置需重新烧录 `irtu.cfg` 或修改代码常量。
- web 端下发 `cycle:N` 会写入 fskv 并立即生效，断电不丢失（直接修改这唯一一条上报通道的周期，最小 5 秒）。

## 六、定位与上报格式（AirCloud TLV）

定位策略：**GNSS 优先，未定位回退 LBS**。唯一周期通道（`build_uplink_tlv`，默认每 30s，`cycle:N` 可改）每次上报字段：

| tag | 含义 | 类型 | 是否必填 | 来源 |
|---|---|---|---|---|
| 782 | 4G 信号强度 | INTEGER | 必填 | mobile.csq() |
| 774 | 模组型号（COMPONENT_MODEL） | ASCII | 必填 | rtos.bsp()，如 `Air780EGG` |
| 798 | 设备ID（IMEI） | ASCII | 必填 | mobile.imei() |
| 1280 | 时间戳 | INTEGER | 必填 | os.time() |
| 263 | CPU 温度 | FLOAT | 必填 | adc.CH_CPU（模组内部测温，非外接传感器） |
| 513 | 纬度 | FLOAT | 定位成功才带 | 内置 GNSS（rmc(2).lat），回退 LBS |
| 512 | 经度 | FLOAT | 定位成功才带 | 内置 GNSS（rmc(2).lng），回退 LBS |
| 1281 | 定位方式 | INTEGER | 定位成功才带 | 2=GNSS / 1=LBS |

> GNSS 与 LBS 都无定位时，该周期只发前 5 个必填字段，不带位置。

## 七、下行控制命令（tag 19 → 回 tag 20）

| 指令 | 格式 | 说明 |
|---|---|---|
| 设置上报频率 | `cycle:秒数`（最小 5） | 写 fskv 并重启上报定时器 |
| LED 控制 | `led:blink` / `led:on` / `led:off` | blink 闪烁 5 秒 |
| iRTU rrpc | `rrpc,getimei` 等（走 tag 21） | 保留全部原有 rrpc 查询指令 |

执行后以 tag 20（CONTROL_RESPONSE）回复执行结果。

## 八、旧版产测程序 factory.lua（默认不加载）

`factory.lua` 为早期「产测/正常合一」版本的产测模式实现，经 USB（VUART_0）收发、指令以 `#` 结尾、多参数逗号分隔、自动 trim + 大写。**当前 main.lua 不会加载它**，仅保留源文件供复用或产线需要时手动 `require "factory"` 调试。其依赖的 `prodmeta` 由默认扩展库提供。

支持的指令：

| 指令 | 说明 |
|---|---|
| `VERSION#` | 固件版本 |
| `IMEI#` / `IMSI#` / `ICCID#` / `MUID#` | 设备标识 |
| `CSQ#` | 信号强度 |
| `VBAT#` | 电池电压 |
| `MODEL#` | 型号（prodmeta） |
| `HVERSION#` | 硬件版本 |
| `GPSTEST,1#` | 开启内置 GNSS，NMEA 直接透传 USB 上位机（含提频指令） |
| `GPSTEST,0#` | 关闭内置 GNSS（exgnss.close_all + uart.close(2)，不操作供电 GPIO） |
| `LED,1#` / `LED,0#` | 状态灯（GPIO27）亮 / 灭 |
| `FLYMODE,1#` / `FLYMODE,0#` | 飞行模式开（关 GNSS）/ 关 |
| `ECNPICFG,...#` | 写网络配置 |
| `RST#` | 重启 |
| `TEST_DONE#` | 产测完成 → 关 GNSS + 灭灯 + 写 test_done + 3s 重启（注：本固件 main 不读该标记） |
| `PCBA_TEST_DONE#` | PCBA 测试完成 → 3s 后关机 |

> 本套不设 `GS_STATE`：EGG/EGP 的 DA221 加速度传感器走内置 `exvib` 库（中断 `gpio.WAKEUP2`），并非 Air8780G 的 I2C1(0x27) 访问方式；且 EGH 核心板未引出 gsensor。如需振动检测应改用 `exvib.open(1)` + `exvib.read_xyz()`，不能照搬 I2C 方案。
>
> 如需「首测自动进产测、USB 指令返工进产测」的 V3 分流能力，请参考 Air8780 / Air780EHV 工程。

## 九、使用说明

1. 用 Luatools 烧录本工程：选择 `user/` 目录 + `lib/` 扩展库，并**勾选「添加默认 lib」**（提供 libfota3 / prodmeta）。
2. 修改 `irtu.cfg` 中的 AuthKey 为实际 AirCloud 项目密钥。
3. 烧录后开机即正常模式：每 30s 上报一次（信号/模组型号/IMEI/时间戳/CPU温度 + GNSS 定位，未定位回退 LBS），UART1 透传；本工程无任何 I2C 传感器。
4. FOTA：`main.lua` 顶部 `PROJECT` 按型号注释切换（`Air780EGG` / `Air780EGP` / `Air780EGH`，一次只放行为对应型号出固件），配合 `VERSION`、`PRODUCT_KEY` 决定升级目标，改名/换项目时需同步（见 main.lua、update.lua）。

## 十、官方支持渠道

- https://docs.openluat.com/ 查找文档
- https://gitee.com/openLuat/LuatOS/tree/master/module 查找代码
- 合宙官方企业微信群（https://docs.openluat.com/ 网站底部二维码，扫码加入）
- https://luat.taobao.com/ 选购核心板和开发板产品，对比验证
