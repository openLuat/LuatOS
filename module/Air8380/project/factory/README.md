# Air8380 出厂固件

Air8380 工业模组（主控 Air8000W，4G Cat.1 + WiFi/BLE 协处理器）的**默认出厂固件**，
一套固件同时承担产线与出货。

## 1 能力范围

| 模块 | 说明 |
| --- | --- |
| 多网融合 | 网口(CH390H) / WiFi(STA) / 4G，`exnetif` 优先级调度（默认 网口 > WiFi > 4G），配置持久化 |
| 产测模式 | USB 虚拟串口 115200，`#` 结尾指令；写号 / 校准位 / Flash / 网口 / WiFi 测试 |
| AirCloud | 周期上报（信号/ICCID/CPU 温度/VBAT/当前链路/经纬度）+ 运维日志 + 下行命令 |
| 定位 | airlbs 多基站 / 多基站+WiFi 定位，结果经字段 512/513 上报；未配置 ID/Key 自动跳过 |
| FOTA | `libfota3` 整机升级，自动检测，升级历史落盘 |
| 看门狗 | 软狗 9s/3s 喂 + 网络看门狗（长时间无 IP/无成功上报则重启） |
| SPI Flash | `little_flash` 挂载为 `/little_flash`，存运行日志与配置快照 |
| 指示灯 | **无模组侧可控灯**：RJ45 的 LINK/ACT 灯由 CH390H 硬件驱动，软件不参与 |

## 2 目录

```
8380/
├─ README.md
├─ doc/                     设计说明 + AirCloud 下行指令表
└─ firmware/                ← Luatools 烧录时选这个目录
   ├─ main.lua              入口：PROJECT/VERSION、上电顺序
   ├─ board.lua             硬件引脚与电源使能（唯一改引脚的文件）
   ├─ app_config.lua        运行配置 + fskv 持久化
   ├─ factory.lua           产测模式（USB 指令，集成自「8380出厂产测」）
   ├─ prodmeta.lua          OTP 产品元数据（PROD/PCB）
   ├─ net_drv.lua           网卡驱动 + 多网融合
   ├─ aircloud_app.lua      AirCloud 上报 / 运维日志 / 下行命令
   ├─ airlbs_app.lua        airlbs 定位（多基站 / 多基站+WiFi）
   ├─ fota_app.lua          FOTA 封装
   ├─ net_watchdog.lua      网络看门狗
   ├─ storage.lua           SPI Flash 挂载与文件读写
   └─ status.lua            运行状态聚合
```

## 3 烧录

1. USB 连接 8380（或 5 个调试过孔 + 下载转接板）；
2. Luatools 选脚本目录 `firmware/`，底层选 Air8000W 对应固件（114 号，V2052 及以上）；
3. 烧录后日志首行应为 `I/user.main Air8380_Factory 001.999.001`。

> 脚本区容量有限：不要把文档、图片、readme 放进 `firmware/`。

## 4 依赖

| 文件 | 用途 |
| --- | --- |
| `libfota3.lua` | FOTA 整机升级 |
| `exnetif.lua` | 多网融合优先级调度 |
| `dhcpsrv.lua` / `dnsproxy.lua` / `httpdns.lua` | exnetif 顶层依赖，必须随工程存在（本工程不再启用 AP） |
| `airlbs.lua` / `libnet.lua` | airlbs 定位服务及其网络底层 |

内核：Air8000W 固件（114 号，V2052 及以上），需含 `excloud`、`netdrv`、`wlan`、`fota`、`lf`。
WiFi/BLE 协处理器固件须 ≥ V20（低于 V20 需先升级）。

## 5 配置入口（没有网页后只剩这三条）

1. **出厂预置**：改 `app_config.lua` 的 `DEFAULTS`（网口 IP、WiFi SSID/密码、`project_key`、`lbs_project_id/key`、上报间隔）后重烧；
2. **远程下发**：设备 4G 上线后，AirCloud 下发
   `{"type":"set_wifi","ssid":"xxx","pwd":"yyy"}`，配置写入 fskv 并自动重建网络；
3. **恢复出厂**：无本地入口，需要时整片擦录（或临时在 `main.lua` 里调一次 `app_config.reset()`）。

> **AirCloud 不需要密钥**：`excloud.setup({use_getip = true})` 自动认证，联网即连。
> `project_key` 只给 **FOTA** 用，已预置；平台需上传脚本名 `Air8380_Factory`、
> 版本高于当前 `001.999.001` 的包，设备才会检测到升级。
> airlbs 定位的 `lbs_project_id/key` 已预置为合宙测试项目，量产建议换成客户自己的。

**全部下行指令（写法 / 应答 / 注意事项）见 [`doc/AirCloud下行指令表.md`](doc/AirCloud下行指令表.md)**。

## 6 已确认的硬件引脚（来自 Air8380_V0_20260914.pdf）

| 功能 | 引脚 | 说明 |
| --- | --- | --- |
| 网口 CH390H | SPI1，CS=GPIO12，IRQ=GPIO17 | LDO 使能 GPIO1，26MHz |
| 外挂 Flash W25N01KVZEIR（实测） | SPI1，CS=GPIO16 | LDO 使能 GPIO2，SPI NAND 1Gbit，半双工 2MHz |
| 外供 3.3V | 使能 GPIO20 | AGPIO，低功耗/PSM 保持 |
| SPI1 总线 | CLK=15 / MISO=14 / MOSI=13 | 网口与 NAND 共用 |
| 指示灯 | 无 | 仅 RJ45 内置 LINK/ACT 灯，硬件驱动 |

详见 `doc/出厂固件设计.md`。

## 7 下一步

- [ ] 实板联调：网口静态/DHCP、WiFi STA、NAND 挂载、4G 注网
- [ ] 产测实板验证：FLASH_TEST / NET_TEST / WIFI_TEST / 写号 / TEST_DONE 全流程
- [ ] 验证 AirCloud 上报 / 运维日志（无需 key）、airlbs 定位（ID/Key 已预置）
- [ ] 平台上传更高版本脚本包，验证 FOTA 检测 / 下载 / 重启升级
- [ ] 网口大流量 + Flash 写日志的长时间压力测试（SPI1 共用总线）
- [ ] BLE 近场配网（可选，可替代已取消的网页配网）

## 8 产测模式（集成自「8380出厂产测」）

**分流规则**（`main.lua`，与原产测工程一致）：

| 条件 | 运行模式 |
| --- | --- |
| fskv 有 `retest_flag` | 产测（返工） |
| OTP 里 `PROD` 为空 | 产测（首次） |
| 其他 | 用户模式 |

**通道**：USB 虚拟串口 `115200 8N1`，指令以 `#` 结尾。

| 指令 | 功能 |
| --- | --- |
| `VERSION#` | 返回 `PROJECT_VERSION` |
| `IMEI#` `IMSI#` `ICCID#` `CSQ#` `MUID#` `VBAT#` | 模组与插卡信息，无值回 `ERROR#` |
| `FLYMODE,0#` / `FLYMODE,1#` | 关 / 开飞行模式 |
| `ECNPICFG#` | RF 校准标志位，回 `true#` / `false#` |
| `MODEL,Air8380#` / `MODEL?#` | OTP 写入 / 读回工业型号（PROD） |
| `HVERSION,V1.0#` / `HVERSION#` | OTP 写入 / 读回硬件版本（PCB） |
| `FLASH_TEST#` | SPI NAND 写入→读回对比，回 `OK#` / `ERROR#` |
| `NET_TEST#` | 网口 WAN DHCP 取 IP，回 IP 或 `ERROR#` |
| `WIFI_TEST#` | WiFi 扫描，回热点数量 |
| `MODEL_RETEST,CONFIRM#` / `MODEL_RETEST?#` | 写 / 查返工标记（写入后重启进产测） |
| `RST#` | 重启 |
| `TEST_DONE#` | 结束：返工则清标记，3 秒后重启 |
| `PCBA_TEST_DONE#` | 3 秒后关机 |

**返工**：用户模式没有挂 retest 指令监听，出货后要返工只能
① 整片擦除重烧；② 代码里 `fskv.set("retest_flag", true)` 后重启；③ 后续在用户模式补 USB 指令监听。

**资源互斥**：产测模式下 `factory.lua` 自己开 LDO / SPI / 网口 / Flash / USB，
不会加载 net_drv / aircloud / fota / watchdog，两种模式不会互相抢外设。

## 9 板载 Flash 能做什么

芯片：W25N01KVZEIR，128MB SPI NAND，挂载为 littlefs（`/little_flash`）。
挂载后是**完整文件系统**，不是只能写日志：

| 能力 | 用法 |
| --- | --- |
| 读 / 写 | `io.readFile(path)` / `io.writeFile(path, data)` |
| 追加 | `io.open(path, "a")` |
| 目录 | `io.mkdir(path)` / `io.listdir(path)` |
| 删除 | `os.remove(path)` |
| 大小 | `io.fileSize(path)` |

当前代码实际只用了三种用途：

- `/little_flash/log/app.log`：运行日志（启动、FOTA、看门狗复位、定位结果），256KB 轮转；
- `/little_flash/fixed.txt`：一段固定值（默认 `1234567890`），首次挂载写入后不再改动，用于远程验证 Flash 读写通路；
- **配置与状态不在 NAND**：配置走 fskv（内置 Flash 的 KV），FOTA 状态文件在 `/fota_state.json`（内置文件系统）。

固定值怎么读：

- 远程：AirCloud 下发 `read_flash`，设备回 `{"val":"1234567890","len":10}`；
- 未挂载 / 未写入时回 `{"val":"","err":"flash_not_mounted"}` 或 `"fixed_missing"`。

日志怎么取出来：

- **只能本地导出**：Luatools 文件管理导出 `/little_flash/log/app.log`；
- 远程日志回读已取消：AirCloud 的 ASCII 型 TLV 只保证 7-bit，中文日志经它回传必然乱码，改用固定值验证 Flash 通路。

建议后续用它承载（目前没做）：

- FOTA 升级包缓存（避免反复下载）
- 断网期间的采集数据缓存（联网后补传）
- 故障快照 / 黑匣子（复位前的关键状态）
- 资源文件（页面、字库、图片）

注意：NAND 写寿命优于 SD 卡但也不是无限的，日志已做大小轮转；业务数据建议批量落盘，不要每条都写。
