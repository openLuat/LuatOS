---
name: luatos-dev
description: LuatOS 固件开发专家。用于编写/修改 LuatOS C 核心库、Lua 扩展库、模块 Demo、测试用例，理解架构层次，调试嵌入式问题。72 核心库 API + 44 扩展库 Lua 文件（其中 32 有正式文档）。
---

# LuatOS 固件开发技能

## 一、项目概述

LuatOS 是合宙（openLuat）基于 Lua 5.3.5 的嵌入式 IoT 操作系统，支持 Air8000/Air8101/Air780E 系列等硬件平台。

**构建系统**: xmake (3.0.4+)
**目标平台**: ARM/RISC-V MCU + PC 模拟器 (Windows/Linux/macOS)
**许可证**: MIT

---

## 二、核心概念：核心库 vs 扩展库

**核心库 (Core Library)** = 固件内置的 C 代码层功能。位于 `components/` 和 `luat/modules/`。固件编译时内置，**无需加载，直接调用**。例如：`gpio.setup()`、`socket.tcp()`、`mqtt.create()`。

文档收录 **72 个核心库 API**（编号 1-72）。

**扩展库 (Extension Library)** = 对核心库接口的 Lua 二次封装。位于 `script/libs/` 下的 `.lua` 文件。代码内**需要 `require` 加载**才能使用。例如：`require("libnet")`、`require("exgnss")`。

`script/libs/` 实际有 **44 个 .lua 文件**，其中 32 个有正式文档收录，12 个未收录的为变体或底层驱动。

每个型号的固件封装的核心库不同 → 功能不同。核心库功能只要固件内存在就可以直接调用其接口。

---

## 三、四层架构

```
┌─────────────────────────────┐
│  Layer 4: 脚本层 (script/)  │  Lua 库 + 应用模板
│  corelib/ | libs/ | turnkey/│
├─────────────────────────────┤
│  Layer 3: 组件层             │  60+ 子组件
│  components/                │  网络/安全/GUI/多媒体/存储/IoT
├─────────────────────────────┤
│  Layer 2: 核心框架 (luat/)  │  HAL + VFS + 任务调度
│  modules/ | vfs/ | include/ │
├─────────────────────────────┤
│  Layer 1: Lua 虚拟机 (lua/) │  Lua 5.3.5 优化版
└─────────────────────────────┘
                    ↕ BSP 层 (bsp/) 平台适配
```

### Layer 1: Lua VM (`lua/`) — Lua 5.3.5 优化版

### Layer 2: 核心框架 (`luat/`)
- `luat/include/` — 核心 C 头文件
- `luat/modules/` — C 实现的 Lua 库
- `luat/vfs/` — 虚拟文件系统

### Layer 3: 组件 (`components/`) — 60+ 子组件

| 类别 | 组件 |
|------|------|
| GUI | `airui/`, `lvgl/`, `u8g2/` |
| 网络 | `network/` (LwIP, MQTT, HTTP, WebSocket, CoAP) |
| 安全 | `mbedtls/`, `crypto/`, `gmssl/`, `xxtea/` |
| 多媒体 | `audio/`, `videoplayer/`, `camera/`, `codec/`, `multimedia/` |
| 存储 | `fatfs/`, `lfs/`, `sfud/`, `flashdb/`, `fskv/` |
| IoT协议 | `mqtt/`, `coap/`, `websocket/`, `rtmp/`, `rtsp/` |
| 硬件 | `adc/`, `can/`, `i2c/`, `spi/`, `uart/`, `pwm/` |
| BLE | `bluetooth/`, `nimble/` |
| 定位 | `minmea/` (libgnss), `lbs/` |
| 其他 | `fota/`, `eink/`, `nes/`, `mgba/`, `airlink/`, `airtalk/` |

---

## 四、扩展库完整目录 (script/libs/) — 44 个

★=已收录文档  ☆=未收录变体/驱动

| 文件 | 文档 | 功能 |
|------|------|------|
| `libnet.lua` | ★ | socket 同步阻塞 API |
| `libfota.lua` | ★ | 固件空中升级 |
| `libfota2.lua` | ★ | 固件空中升级 v2 |
| `exgnss.lua` | ★ | GNSS 定位扩展 |
| `exmodbus.lua` | ★ | Modbus 协议（总入口） |
| `exmodbus_tcp.lua` | ☆ | Modbus TCP 变体 |
| `exmodbus_rtu_ascii.lua` | ☆ | Modbus RTU/ASCII 变体 |
| `exaudio.lua` | ★ | 音频播放扩展 |
| `excamera.lua` | ★ | 摄像头扩展 |
| `exlcd.lua` | ★ | LCD 显示扩展 |
| `exftp.lua` | ☆ | FTP 客户端 |
| `exsip.lua` | ★ | SIP/VoIP 通话 |
| `exsipclient.lua` | ☆ | SIP 客户端 |
| `exsipproto.lua` | ☆ | SIP 协议底层 |
| `excloud.lua` | ★ | 云平台对接 |
| `exeasyui.lua` | ★ | EasyUI 界面 |
| `exnetif.lua` | ★ | 网络接口管理 |
| `exmux.lua` | ★ | MUX 多路复用 |
| `exremotecam.lua` | ★ | 远程摄像头 |
| `exremotefile.lua` | ★ | 远程文件管理 |
| `httpplus.lua` | ★ | HTTP 增强 |
| `httpdns.lua` | ★ | HTTP DNS 解析 |
| `dnsproxy.lua` | ★ | DNS 代理 |
| `dhcpsrv.lua` | ★ | DHCP 服务 |
| `udpsrv.lua` | ★ | UDP 服务 |
| `lbsLoc.lua` | ★ | 免费版单基站定位 |
| `lbsLoc2.lua` | ★ | 免费版单基站定位 v2 |
| `airlbs.lua` | ★ | 收费版基站/WiFi 定位 |
| `extalk.lua` | ★ | 对讲功能 |
| `extp.lua` | ★ | 触摸屏 |
| `exvib.lua` | ★ | 振动检测 |
| `exvib1.lua` | ★ | 振动监测 |
| `exwin.lua` | ★ | UI 窗口管理 |
| `exfotawifi.lua` | ★ | WiFi FOTA |
| `exapp.lua` | ☆ | 应用框架 |
| `exril_5101.lua` | ★ | RIL 蓝牙驱动 |
| `exmtn.lua` | ☆ | 移动网络管理 |
| `netLed.lua` | ☆ | 网络指示灯 |
| `xmodem.lua` | ★ | XModem 协议 |
| `air153C_wtd.lua` | ★ | 外部看门狗 |
| `bf30a2.lua` | ☆ | BF30A2 传感器 |
| `dhcam.lua` | ☆ | DHCam 摄像头 |
| `gc0310.lua` | ☆ | GC0310 传感器 |
| `gc032a.lua` | ☆ | GC032A 传感器 |

---

## 五、模块/Demo 系统

`module/` 下按硬件型号组织：

| 模块 | 说明 |
|------|------|
| Air780EPM/EHM | 4G 数传，**默认型号** |
| Air780EHM/EHV/EGH | 含语音/GNSS |
| Air8000 | 多网融合 UI SoC |
| Air8101 | WiFi UI SoC |
| Air1601/Air1602 | MCU UI SoC |
| Air780EGP/EGG | 4G+GNSS |
| Air780EHN/EHU | 海外型号 |
| Air700ECH/ECP | 迷你封装 |
| Air510W/Air530W | GNSS 模块 |
| iRTU | 透传固件 |
| PC | PC 模拟器 |

---

## 六、核心库 API — 72 个

adc, airlink, airui, audio, bit64, ble, camera, can, cc, codec, crypto, eink, errDump, fastlz, fatfs, fft, fota, fs, fskv, ftp, gmssl, gpio, hmeta, ht1621, http, httpsrv, hzfont, i2c, i2s, iconv, io, ioqueue, iotauth, iperf, json, lcd, libgnss, little_flash, log, lora2, mcu, miniz, mobile, mqtt, netdrv, onewire, os, otp, pack, pins, pm, protobuf, pwm, rsa, rtc, rtmp, rtos, sfud, sms, socket, spi, string, sys, tp, u8g2, uart, wdt, websocket, wlan, xxtea, ymodem, zbuff

---

## 七、构建系统

**禁止直接运行 `xmake -y`** — 必须用批处理脚本：

| 脚本 | 用途 |
|------|------|
| `build_windows_32bit_msvc.bat` | 日常增量编译 (推荐) |
| `build_windows_32bit_msvc_gui.bat` | GUI 变更验证 |

位置: `bsp/pc/`，运行: `cmd /c build_windows_32bit_msvc.bat`

---

## 八、编码规范

### C 代码
- 核心 API 用 `luat_` 前缀
- 模块文件: `luat_lib_<module>.c`
- **`#include "luat_base.h"` 必须作为第一个 include**
- 返回值: 0=成功，负数=错误

### Lua 代码
- `sys.taskInit(function() ... end)` 用于异步
- `sys.run()` 必须在末尾
- 日志: `log.info/warn/error(tag, msg)`
- 库结构: `local mod = {}` → 函数 → `return mod`
- 加载: `local mylib = require("mylib")`

### 反模式
- ❌ 不要轮询 — 用 `sys.wait()`
- ❌ 不要阻塞主线程
- ❌ 不要用全局变量存模块状态
- ❌ 不要绕开 `luat_` API
- ❌ 不要在 `modules/` 加平台特定代码

---

## 九、测试框架

```
testcase/
├── common/scripts/    # testrunner.lua, testsuite.lua
├── unit_testcase_tools/
├── unit_testcase_driver/
├── function_testcase_network/
└── memprof/
```

运行: `build/out/luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/<feature>/<feature>_basic/scripts/`

创建测试: `metas.json` + `main.lua` + `<feature>_test.lua` (函数名 `test_` 开头)

---

## 十、常见陷阱

- `lua_newuserdata` 不会零初始化 → 必须 `memset`
- `uv_async_send` 回调在不同线程
- 不能 memcpy libuv 句柄
- xmake `remove_files` 后 `add_files` 无效
- PC 测试必须 `os.exit(0)`，写在 `sys.run()` 之前

---

## 十一、关键文件

| 文件 | 说明 |
|------|------|
| `AGENTS.md` | 主 AI 配置 (454行) |
| `luat/include/luat_base.h` | 核心定义 |
| `luat/include/luat_libs.h` | 库注册表 |
| `script/corelib/sys.lua` | 任务系统核心 |
| `bsp/pc/xmake.lua` | 构建配置 |
| `bsp/pc/AGENTS.md` | PC 模拟器文档 |
| `testcase/README.md` | 测试指南 (458行) |
| `mcp/README.md` | MCP 服务器文档 |
