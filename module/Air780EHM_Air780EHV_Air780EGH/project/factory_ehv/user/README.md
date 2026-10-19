# Air780EHV 出厂固件（Air780EHVFactory）

> 技术底座：**Air8780 出厂固件（Air8780/project/factory，8780V 版本配置）**，Air780EHV 与 Air8780V 为同一份固件
>
> 日期：2026.10.16

## 一、项目简介

本工程由 Air8780 出厂固件整体移植，版本配置固定为 **8780V**（见 `factory_config.lua` 的 `DEVICE_VER`），作为 Air780EHV 出厂固件，核心能力：

1. **产测 + iRTU 合一（V3 分流）**：开机按「fskv 返工标记 → OTP1 判空」分流进产测模式或正常模式，无需维护两套固件。
2. **音频/TTS**：内置顺芯 ES8311 codec（I2C0，地址 0x18；codec 电源 GPIO20；外置 PA 使能 GPIO22）。开机联网后播报一次「上海合宙欢迎你」，并支持服务器下行 `tts:文本` / `ttshex:hex` 播报。
3. **LBS 基站定位**：无 GNSS，定位走基站，经纬度作为可选字段上报。
4. **不采 I2C 传感器**：8780V 配置 `sensor_enable=false`，`sensor_task` 直接跳过；如整机加装 SHT30/VOC，改配置即可恢复采集。
5. **结构化 TLV 上报**：`factory_app.lua` 构建 AirCloud 结构化 TLV，默认每 180 秒上报一次，UART1（115200）透传。
6. **外置硬件看门狗**：板载 Air153C/D（GPIO24，NPN 反相，180s 超时，exair153x_wdt 自动喂狗）+ 内核软狗 wdt（9s/3s）。

## 二、开机分流（V3）

`main.lua` 中 `BOOT_MODE` 默认 `"auto"`，判断顺序：

1. **fskv 返工标记优先**：`fskv.get("model_retest")` 存在 → 进产测模式（返工场景，OTP1 已有写号）。
2. **OTP1 判空**：读取 prodmeta 全部键值，为空（首测裸板）→ 进产测模式；读取异常按未产测处理。
3. 其余 → `require "irtu_main"` 进正常 AirCloud 上报模式。

### 返工指令（USB VUART_0，正常/产测模式均监听）

| 指令 | 作用 |
|---|---|
| `MODEL_RETEST#CONFIRM` | 正常模式下发：写 fskv 返工标记后重启进产测 |
| `MODEL_RETEST?` | 查询标记：返回 `HAS` / `NONE` |

- **首测**：OTP1 空 → 产测；`TEST_DONE#` 通过后 prodmeta 写 `PROD`/`PCB` 入 OTP1，重启进正常模式。
- **返工**：产测通过后删除 fskv 标记（`fskv.del("model_retest")`，不动 OTP1），重启恢复正常模式。

## 三、目录结构

```
factory_ehv/
├── lib/                     # iRTU 通用扩展库（db/dtulib/mapTile/testdebug/utils）
└── user/
    ├── main.lua             # 入口：V3 分流（fskv返工标记→OTP1判空）+ 软狗 + FOTA
    ├── factory.lua          # 产测模式：USB 指令 / 写号 / 音频录放测试（8780V 聚合）
    ├── retest.lua           # 返工指令模块（MODEL_RETEST#CONFIRM / ?）
    ├── irtu_main.lua        # 正常模式初始化（default/driver/create）
    ├── default.lua          # 配置加载（直连 AirCloud，不拉网页配置）
    ├── create.lua           # 网络通道（结构化/GPS 上报 + 下行命令 + 串口透传）
    ├── driver.lua           # 串口 / GPIO 灯 / rrpc 指令 / 自动任务
    ├── factory_config.lua   # ⭐ 版本配置（DEVICE_VER="8780V"，硬件差异集中在此）
    ├── factory_app.lua      # 业务编排：TLV 构建 / 控制命令 / LED / TTS / 上报周期
    ├── audio_config.lua     # ES8311 + exaudio 封装（TTS/放音，自动重初始化）
    ├── watchdog_app.lua     # 外置看门狗应用（exair153x_wdt 自动喂狗）
    ├── air153c_watchdog.lua # Air153 备用底层驱动（默认用 libs 的 exair153x_wdt）
    ├── gnss.lua             # iRTU 自带 GNSS 模块（8780V 未启用，保留复用）
    ├── sensor_task.lua      # I2C 传感器采集（8780V 关闭，保留复用）
    ├── AirSHT30_1000.lua    # SHT30 驱动（保留复用）
    ├── AirVOC_1000.lua      # VOC 驱动（保留复用）
    ├── update.lua           # FOTA 升级任务（开机检测 + 每 8h）
    ├── irtu.cfg             # 预置配置（烧录到 /luadb/irtu.cfg）
    ├── irtu.json            # 配置参考（可导入 iRTU 配置工具）
    └── README.md
```

## 四、默认库依赖（烧录必须勾选「添加默认 lib」）

本工程**不放公共库副本**，以下模块全部由 `script/libs` 默认扩展库提供：

| 库 | 用途 |
|---|---|
| prodmeta | OTP1 写号/读取（PROD 型号、PCB 版本） |
| libfota3 | FOTA 升级（update.lua 编排） |
| es8311 | codec 驱动（产测侧直调） |
| exaudio | 音频播放/录音封装（audio_config 使用） |
| exair153x_wdt | Air153 外置看门狗自动喂狗 |
| exgnss | GNSS 扩展（8780V 未启用） |

> LuaTools 烧录时勾选「添加默认 lib」，否则上述 require 将加载失败。

## 五、8780V 硬件配置基线（factory_config.lua）

| 配置项 | 值 |
|---|---|
| DEVICE_VER | `"8780V"` |
| 传感器 I2C | 硬件 I2C1（sensor_enable=false，不采集） |
| LBS 定位 | 启用 |
| TTS | 启用，文本「上海合宙欢迎你」，开机播报一次 |
| GNSS | 关闭 |
| RS485 | 关闭（UART1 普通透传，115200） |
| 上报周期 | 180 s |
| 网络灯 | netled=GPIO17 / netready=GPIO26 |
| 外置看门狗 | GPIO24，180 s |
| 音频 | ES8311 @ I2C0(0x18)，dac_ctrl=GPIO20，pa_ctrl=GPIO22 |

## 六、数据上报与下行命令

TLV 上报字段：782 信号强度 / 798 IMEI / 1280 时间戳 / 263 CPU 温度（必填）；513/512 LBS 经纬度（可选）。

| 下行指令 | 说明 |
|---|---|
| `cycle:秒数` | 修改上报周期（最小 5s，fskv 持久化） |
| `led:blink|on|off` | 状态 LED 控制 |
| `tts:文本` / `ttshex:hex` | TTS 播报（明文 / UTF-8 hex） |
| `rrpc,getimei` 等 | 保留 iRTU 原有 rrpc 查询 |

## 七、使用说明

1. LuaTools 烧录 `user/` + `lib/`，**务必勾选「添加默认 lib」**。
2. 裸板首测：OTP1 空自动进产测，产测通过写号后重启进正常模式。
3. 已写号整机返工：USB 发 `MODEL_RETEST#CONFIRM`，重启进产测。
4. FOTA：`PROJECT = "Air780EHVFactory"`、`VERSION`、`PRODUCT_KEY` 决定升级目标（见 main.lua、update.lua）。
5. 修改 `irtu.cfg` 的 AuthKey 为实际 AirCloud 项目密钥。

## 八、官方支持渠道

- https://docs.openluat.com/ 查找文档
- https://gitee.com/openLuat/LuatOS/tree/master/module 查找代码
- 合宙官方企业微信群（https://docs.openluat.com/ 网站底部二维码，扫码加入）
- https://luat.taobao.com/ 选购核心板和开发板产品，对比验证
