# Air780EPM 出厂固件（Air780EPMFactory）

> 技术底座：**标准 iRTU 固件 + 预置配置**，开机直接进入正常上报模式
>
> 适用硬件：**Air780EPM 开发板（单一固定配置，不区分型号/版本）**
>
> 日期：2026.10.14

## 一、项目简介

本工程基于标准 iRTU 改造，作为 Air780EPM 开发板出厂固件。**固定单一硬件配置，不再用 `DEVICE_VER` 等变量在多型号间切换；已移除产测模式与 RFA 校准逻辑，开机即进入正常模式**：

1. **不请求网页端配置**：`default.lua` 开机直接加载预置 `irtu.cfg`，默认通道 = **AirCloud**。
2. **传感器走硬件 I2C1**：`sensor_task.lua` 读取 SHT30（温湿度，地址 0x44）与 VOC（TVOC，地址 0x1A），采集失败不影响主数据上报。
3. **LBS 基站定位**：无 GNSS，定位走基站，经纬度作为可选字段上报。
4. **结构化 TLV 上报**：`factory_app.lua` 构建 AirCloud 结构化 TLV 数据，默认每 **180 秒**上报一次。
5. **串口透传 + 下行控制**：UART1（115200）透传；支持 `cycle:秒数` / `led:blink|on|off`，保留 iRTU 原有 rrpc 指令。
6. **仅内核软狗**：使用 main.lua 中的 LuatOS 软狗 `wdt`（9s 超时 / 3s 喂狗）。**无外置看门狗、无音频 codec、无 GNSS**。

## 二、目录结构

```
factory/
├── lib/                     # iRTU 通用扩展库（db/dtulib/mapTile/testdebug/utils）
└── user/
    ├── main.lua             # 入口（软狗 wdt；FOTA；开机直接 require irtu_main）
    ├── irtu_main.lua        # 正常模式初始化（default/driver/create）
    ├── default.lua          # 配置加载 + 固定 GPIO 引脚集（直连 AirCloud，已移除网页拉取）
    ├── create.lua           # 网络通道（aircloudTask 结构化/GPS上报 + 下行命令 + 串口透传）
    ├── driver.lua           # 串口 / GPIO 灯 / rrpc 指令 / 自动任务
    ├── gnss.lua             # iRTU 自带 GNSS 模块（EPM 未启用，保留供 GNSS 工程复用）
    ├── factory_config.lua   # ⭐ Air780EPM 固定硬件配置（I2C/LBS/周期/灯脚）
    ├── factory_app.lua      # 业务编排：TLV/GPS 构建 / 控制命令 / LED / 上报周期
    ├── sensor_task.lua      # 硬件 I2C1 传感器采集（SHT30 + VOC，独立容错）
    ├── AirSHT30_1000.lua    # SHT30 驱动（open(bus) 兼容硬件 I2C id）
    ├── AirVOC_1000.lua      # AGS02MA VOC 驱动（open(bus) 兼容硬件 I2C id）
    ├── libfota3.lua         # FOTA 升级库
    ├── update.lua           # 升级任务（开机检测 + 每 8h）
    ├── irtu.cfg             # 预置配置（烧录到 /luadb/irtu.cfg）
    ├── irtu.json            # 配置参考（可导入 iRTU 配置工具）
    └── README.md
```

> 依赖：`../lib/` 下的 iRTU 扩展库（db/dtulib 等），与标准 iRTU 相同。

## 三、开机流程

`main.lua` 不再做产测/模式分流，开机顺序：

1. 初始化 fskv（上报周期、airlbs 配置持久化）。
2. 打开全局上拉 VREF(GPIO23)；启动内核软狗 `wdt`。
3. `require "update"` 启动 FOTA（开机检测 + 每 8h，异步不阻塞）。
4. `require "irtu_main"` 直接进入 AirCloud 正常上报模式。

## 四、出厂配置基线（irtu.cfg）

| 配置项 | 值 | 说明 |
|---|---|---|
| 通道 | `aircloud` | AirCloud 协议 |
| 传输 | `tcp` | TCP 承载 |
| 心跳 | `300` s | keepAlive 超时（无事件时发心跳） |
| 自动采集间隔 | `180` s | 结构化上报周期（`cycle:N` 可改，fskv 持久化） |
| AuthKey | `JQtKg5M7h8HTMw8CgqMpRh77hySLlUwx` | **必填**，错填连不上；按实际项目密钥修改 |
| 串口1 | `115200,8,N,1` | 透传串口 |
| pins | `["pio17","pio26"]` | netled=17、netready=26；**GPIO27 留给用户状态 LED** |

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

## 六、下行控制命令（tag 19 → 回 tag 20）

| 指令 | 格式 | 说明 |
|---|---|---|
| 设置上报频率 | `cycle:秒数`（最小 5） | 写 fskv 并重启上报定时器 |
| LED 控制 | `led:blink` / `led:on` / `led:off` | blink 闪烁 5 秒 |
| iRTU rrpc | `rrpc,getimei` 等（走 tag 21） | 保留全部原有 rrpc 查询指令 |

执行后以 tag 20（CONTROL_RESPONSE）回复执行结果。

## 七、传感器接入说明（硬件 I2C1）

- **总线固定为硬件 I2C1**：`factory_config.sensor_i2c = { mode="hw", hw_id=1 }`，对应 **PIN66=SDA / PIN67=SCL**，外部上拉、禁用内部上拉。
- 两传感器挂同一条 I2C 总线（SHT30 0x44 与 VOC 0x1A 不冲突）。
- **VCC 必须接板载 3.3V，禁止 GPIO 供电**（VOC 含加热元件，电流 20~30mA 级）。
- 每个传感器独立容错：失败不阻断上报，连续失败 10 次后停止重试该传感器。
- 若整机无传感器，可将 `factory_config.sensor_enable=false`，此时 `sensor_task.get_env` 直接返回 nil、跳过 I2C 初始化。

## 八、使用说明

1. 用 Luatools 将本工程 `user/` 目录 + `lib/` 扩展库一并烧录到 Air780EPM。
2. 修改 `irtu.cfg` 中的 AuthKey 为实际 AirCloud 项目密钥。
3. 开机即进入正常 AirCloud 上报模式，每 180s 结构化上报一次（含信号/IMEI/CPU温度/温湿度/VOC/LBS 经纬度），UART1 透传。
4. FOTA：`PROJECT = "Air780EPMFactory"`、`VERSION`、`PRODUCT_KEY` 决定升级目标，改名/换项目时需同步（见 main.lua、update.lua）。

## 九、官方支持渠道

- https://docs.openluat.com/ 查找文档
- https://gitee.com/openLuat/LuatOS/tree/master/module 查找代码
- 合宙官方企业微信群（https://docs.openluat.com/ 网站底部二维码，扫码加入）
- https://luat.taobao.com/ 选购核心板和开发板产品，对比验证
