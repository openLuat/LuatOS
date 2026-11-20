# 独立轻量产测脚本

项目标识为 `PROJECT = "rfa_factory"`、`VERSION = "1.0.0"`。上电后常驻 RFA 产测服务，不加载 iRTU、`default.lua` 或 `driver.lua`，不主动联网或运行 AGPS。

## 烧录与串口

1. 使用提供 `atc.create`、`atc.bind`、`atc.input`、`atc.on`、`atc.response` 的 LuatOS 固件，并确认所测硬件对应的底层接口可用。`AT+ECBAND=` 还需要已补齐该设置指令的底层 C 固件，仅更新 Lua 不会增加此原生命令。
2. 用 LuaTools **只烧录本目录的 `main.lua` 和 `rfa.lua`**。`README.md`、`tests/` 无需烧录，也无需加入 iRTU 文件。
3. USB 虚拟串口 `VUART_0` 和 UART1 均接收产测命令；串口工具设置为 **115200、8N1**，发送行尾使用 CRLF。虚拟串口的波特率不影响实际传输速度。
4. 两个端口共用 AT 通道，一次只从一个端口发送一条命令，收到完成结果或超时后再发送下一条。UART2 由 GNSS 测试按需使用，不作外部产测命令入口。

## 指令职责

本目录 `rfa.lua` 是当前产测库的独立版本快照；后续修正产测功能时，需同步更新此副本。以下九组扩展通过 atc 注册，响应及参数行为沿用原 RFA 实现。

| Lua 扩展与示例 | 用途 |
| --- | --- |
| `AT+STEST=1` | 恢复 AirLink 供电并等待就绪。 |
| `AT+SWIFIMAC?`；`AT+SWIFIMAC=sta,C8C2C68CDD22` | 查询 STA/AP MAC，或设置 STA MAC；设置时替换为实际分配的十二位十六进制 MAC。 |
| `AT+SWIFISCAN` | 扫描 Wi-Fi，按扫描顺序输出结果，最多32条。 |
| `AT+SWIFIVER?` | 查询 Wi-Fi 固件版本。 |
| `AT+YHM27XX` | 检测充电芯片；检查 `+YHM27XX:` 正文，最终 `OK` 本身不表示检测成功。 |
| `AT+GSENSOREXEC` | 检测 GSensor 芯片 ID。 |
| `AT+CGNSPWR=1`、`AT+CGNSPWR=0` | 开启/关闭 GNSS 主电源与 UART2 会话；支持 `?`、`=?`。 |
| `AT+CGNSTST=1`、`AT+CGNSTST=0` | 开启/关闭 GNSS 原始数据转发；支持 `?`、`=?`。 |
| `AT+CGNSCMD=0,"$FCTATEST,1"` | 向内置 GNSS 发送文本命令；`OK` 表示已提交发送，不代表 GNSS 已执行成功。 |

`AT+ES8311` 与 `AT+SETCFG` 由 RFA 内置分发处理。其余命令交给固件原生 AT 层，例如 `AT`、`ATE0`、`ATE1`、`AT+ECBAND?`、`AT+ECBAND=?`、`AT+ECBAND=3,5,8`；可用范围取决于底层固件。

回显与响应格式保持现有 RFA 行为。`ATE0` 关闭回显，`ATE1` 开启回显；开启回显时，ECBAND 设置成功的字节格式为 `AT+ECBAND=3,5,8\r\n\r\nOK\r\n`。

型号与接线沿用源实现，本示例不新增硬件适配：

- AirLink/Wi-Fi 和充电检测依赖对应型号的硬件与固件接口，不能据此认为所有型号都支持全部指令。
- GSensor 的专用供电/总线分支为 Air8000（GPIO24、I2C0）及 Air780EGP/Air780EGG（GPIO23、I2C1）。
- `AT+ES8311` 沿用 Air780EHV 的 GPIO20 供电、I2C0 接线。
- GNSS 型号表为 Air8000、Air8000A/G/D/U/N、Air780EGH/EGP/EGG，仍需模块实际具备内置 GNSS 和对应 `pm.GPS` 支持。

## GNSS 产测顺序

在同一个产测端口依次发送，每条先等待 `OK`。`CGNSCMD` 返回 `OK` 后，还需接收并确认 GNSS 产测结果，再发送 `CGNSTST=0`；有错误则先排查。

```text
AT+CGNSPWR=1
AT+CGNSTST=1
AT+CGNSCMD=0,"$FCTATEST,1"
AT+CGNSTST=0
AT+CGNSPWR=0
```

关闭会话释放 UART2、关闭 GNSS 主电源，保留 GNSS 备电。

## 产线配置兼容

保留以下配置操作及 `/factory.cfg`、fskv 的存取逻辑：

```text
AT+SETCFG?
AT+SETCFG="rfa_mode","true"
AT+SETCFG="rfa_mode","false"
```

查询优先读取 `/factory.cfg`，再读取 fskv；两处均无配置时默认为 `true`。写入 `false` 后查询仍返回保存的值，但本独立示例当次运行及重启后都继续提供产测服务。该配置用于兼容产线流程，不用于切换到 iRTU。

