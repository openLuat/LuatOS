# Air780EGH/EGP/EGG 出厂固件（Air780EGHFactory）

> 技术底座：**标准 iRTU 固件 + 预置配置**，产测模式与正常上报模式合一
>
> 适用硬件：**Air780EGH / Air780EGP / Air780EGG 内置 GNSS 核心板（单一固定配置，不区分型号/版本）**
>
> 日期：2026.10.14

## 一、项目简介

本工程基于标准 iRTU 改造，作为 Air780EGH/EGP/EGG 核心板出厂固件。**固定单一硬件配置，不再用 `DEVICE_VER` 等变量在多型号间切换**：

1. **不请求网页端配置**：`default.lua` 开机直接加载预置 `irtu.cfg`，默认通道 = **AirCloud**。
2. **开机即开内置 GNSS**：由 `factory_app.lua` 经 `exgnss` 常开模组内置 GNSS，固定挂 **UART2 / 115200**，电源走模组电源轨 `pm.power(pm.GPS)`，**无外挂供电脚**（不传 `gnss_volgpio`）。
3. **30 秒定位上报**：默认每 **30 秒**构建一次 GPS TLV 上报；GNSS 未定位时**回退 LBS 基站定位**，并在 TLV 中带定位方式（2=GNSS / 1=LBS）。
4. **不采集 I2C 传感器**：`sensor_enable=false`，`sensor_task.get_env()` 直接返回 nil，TLV 自动跳过温度/湿度/VOC 字段（传感器接口保留以便复用）。
5. **串口透传 + 下行控制**：UART1（115200）透传；支持 `cycle:秒数` / `led:blink|on|off`，保留 iRTU 原有 rrpc 指令。
6. **仅内核软狗**：使用 main.lua 中的 LuatOS 软狗 `wdt`（9s 超时 / 3s 喂狗）。**无外置看门狗、无音频 codec**。

> 与 Air8780G 的差异：Air8780G 的 GNSS 为外挂方案，靠 GPIO21 拉高供电（`gnss_volgpio=21`）；Air780EGH/EGP/EGG 为**内置** GNSS，由 `pm.GPS` 电源轨供电，故本工程无 GPIO21 / gnssPower 相关代码。

## 二、目录结构

```
factory_egh/
├── lib/                     # iRTU 通用扩展库（db/dtulib/mapTile/testdebug/utils）
└── user/
    ├── main.lua             # 入口（BOOT_MODE + fskv test_done 分流；软狗 wdt；FOTA；IRTU_DISABLE_UART2）
    ├── factory.lua          # ⭐ 产测模式（USB VUART_0 响应以 # 结尾指令；GPSTEST 内置 GNSS 透传）
    ├── prodmeta.lua         # OTP 写号（PROD 型号 / PCB 版本）
    ├── irtu_main.lua        # 正常模式初始化（default/driver/create）
    ├── default.lua          # 配置加载 + 固定 GPIO 引脚集（直连 AirCloud，已移除网页拉取）
    ├── create.lua           # 网络通道（aircloudTask 结构化/GPS上报 + 下行命令 + 串口透传）
    ├── driver.lua           # 串口 / GPIO 灯 / rrpc 指令 / 自动任务（UART2 受门控不初始化）
    ├── gnss.lua             # iRTU 自带 GNSS 模块（本套用 exgnss，保留供复用）
    ├── factory_config.lua   # ⭐ Air780EGH/EGP/EGG 固定配置（内置GNSS 30s / LBS / 不采传感器）
    ├── factory_app.lua      # 业务编排：TLV/GPS 构建 / 控制命令 / LED / 上报周期
    ├── sensor_task.lua      # I2C 传感器采集接口（本套禁用，get_env 返回 nil）
    ├── AirSHT30_1000.lua    # SHT30 驱动（open(bus) 兼容硬件 I2C id，保留）
    ├── AirVOC_1000.lua      # AGS02MA VOC 驱动（open(bus) 兼容硬件 I2C id，保留）
    ├── libfota3.lua         # FOTA 升级库
    ├── update.lua           # 升级任务（开机检测 + 每 8h）
    ├── irtu.cfg             # 预置配置（烧录到 /luadb/irtu.cfg）
    ├── irtu.json            # 配置参考（可导入 iRTU 配置工具）
    └── README.md
```

> 依赖：`../lib/` 下的 iRTU 扩展库（db/dtulib 等），与标准 iRTU 相同。

## 三、开机分流（产测 / 正常合一）

`main.lua` 顶部 `BOOT_MODE` 决定开机行为，量产固定为 `"auto"`：

- `BOOT_MODE = "auto"`：读 fskv `test_done`
  - **未完成产测** → 进 `factory.lua` 产测模式（USB VUART_0 收发指令）。
  - **已完成产测** → 进 `irtu_main.lua` 正常 AirCloud 上报模式（开机即开内置 GNSS）。
- 另保留 `"factory"`（强制产测）/ `"normal"`（强制正常）两档，供调试。

产测模式下下发 `TEST_DONE#`：关闭内置 GNSS、网络灯灭、写 fskv `test_done=true`、3 秒后重启进入正常模式。

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
| GNSS 上报间隔 | `30` s | 内置 GNSS 定位上报周期（`factory_config.gps.interval`） |
| AuthKey | `JQtKg5M7h8HTMw8CgqMpRh77hy2hZ0o` | **必填**，错填连不上；按实际项目密钥修改 |
| 串口1 | `115200,8,N,1` | 透传串口（UART2 被 GNSS 独占，不可配） |
| pins | `["pio17","pio26"]` | netled=17、netready=26；**GPIO27 留给用户状态 LED** |

**注意**：

- 出厂固件不在开机时同步网页端配置，改配置需重新烧录 `irtu.cfg` 或修改代码常量。
- web 端下发 `cycle:N` 会写入 fskv 并立即生效，断电不丢失（影响结构化 report 周期；GPS 30s 周期由 `factory_config.gps.interval` 固定）。

## 六、定位与上报格式（AirCloud TLV）

定位策略：**GNSS 优先，未定位回退 LBS**。

GPS 事件 TLV（`build_gps_tlv`，每 30s）：

| tag | 含义 | 类型 | 来源 |
|---|---|---|---|
| 513 | 纬度 | FLOAT | 内置 GNSS（rmc(2).lat），回退 LBS |
| 512 | 经度 | FLOAT | 内置 GNSS（rmc(2).lng），回退 LBS |
| 1281 | 定位方式 | INTEGER | 2=GNSS / 1=LBS |
| 1280 | 时间戳 | INTEGER | os.time() |

结构化 report TLV（`build_report_tlv`，周期可配）：

| tag | 含义 | 类型 | 是否必填 | 来源 |
|---|---|---|---|---|
| 782 | 4G 信号强度 | INTEGER | 必填 | mobile.csq() |
| 798 | 设备ID（IMEI） | ASCII | 必填 | mobile.imei() |
| 1280 | 时间戳 | INTEGER | 必填 | os.time() |
| 263 | CPU 温度 | FLOAT | 必填 | adc.CH_CPU |
| 256/257/258 | 温度/湿度/TVOC | FLOAT | — | 本套禁用，不上报 |
| 513/512 | LBS 纬度/经度 | FLOAT | 可选 | LBS 基站定位 |

> GNSS 与 LBS 都无定位时，该次 GPS 事件不上报位置。

## 七、下行控制命令（tag 19 → 回 tag 20）

| 指令 | 格式 | 说明 |
|---|---|---|
| 设置上报频率 | `cycle:秒数`（最小 5） | 写 fskv 并重启上报定时器 |
| LED 控制 | `led:blink` / `led:on` / `led:off` | blink 闪烁 5 秒 |
| iRTU rrpc | `rrpc,getimei` 等（走 tag 21） | 保留全部原有 rrpc 查询指令 |

执行后以 tag 20（CONTROL_RESPONSE）回复执行结果。

## 八、产测指令（factory.lua）

产测模式经 USB（VUART_0）收发，指令以 `#` 结尾，多参数以逗号分隔，自动 trim + 大写。支持：

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
| `TEST_DONE#` | 产测完成 → 关 GNSS + 灭灯 + 写 test_done + 3s 重启进正常模式 |
| `PCBA_TEST_DONE#` | PCBA 测试完成 → 3s 后关机 |

> 本套不设 `GS_STATE`：EGG/EGP 的 DA221 加速度传感器走内置 `exvib` 库（中断 `gpio.WAKEUP2`），并非 Air8780G 的 I2C1(0x27) 访问方式；且 EGH 核心板未引出 gsensor。如需振动检测应改用 `exvib.open(1)` + `exvib.read_xyz()`，不能照搬 I2C 方案。

## 九、使用说明

1. 用 Luatools 将本工程 `user/` 目录 + `lib/` 扩展库一并烧录到 Air780EGH/EGP/EGG。
2. 修改 `irtu.cfg` 中的 AuthKey 为实际 AirCloud 项目密钥。
3. 新板默认进产测模式，可用 `GPSTEST,1#` 验证 GNSS 定位，完成 `TEST_DONE#` 后重启进正常模式。
4. 正常模式开机即开内置 GNSS，每 30s 上报定位（未定位回退 LBS），UART1 透传；不采集 I2C 传感器。
5. FOTA：`PROJECT = "Air780EGHFactory"`、`VERSION`、`PRODUCT_KEY` 决定升级目标，改名/换项目时需同步（见 main.lua、update.lua）。

## 十、官方支持渠道

- https://docs.openluat.com/ 查找文档
- https://gitee.com/openLuat/LuatOS/tree/master/module 查找代码
- 合宙官方企业微信群（https://docs.openluat.com/ 网站底部二维码，扫码加入）
- https://luat.taobao.com/ 选购核心板和开发板产品，对比验证
