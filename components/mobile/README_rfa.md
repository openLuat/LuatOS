# mobile 库 RF 校准功能 (rfa 重构版)

> 替代旧 `README_rfcal.md` (2026-06-13 重构)
>
> 设计哲学: **Thin C / Fat Lua** — C 端只做"打开/收字节/存状态"三类原语, 所有 AT 协议由 Lua `rfa.*` 模块解析
>
> 本版补充 EC718HM/EC718PM 真机适配 (2026-06-15)
>
> 后续修正: AGC 校准脏数据 (2026-06-16)、Air780EPM 020D 分块乱码 (2026-06-17)、`checkCaliFlag` NPI 保存失败 (2026-06-30)

## 1. 模块分层

```
┌────────────────────────────────────────────────────────┐
│                    Lua 端 (业务大脑)                    │
│  ┌─────────────────────────────────────────────────┐   │
│  │  script/libs/rfa.lua  (LuatOS 主仓)              │   │
│  │  rfa_script/rfa.lua   (ec7xx-at 产线固件)        │   │
│  │    - 状态机 7 阶段 (IDLE→DONE)                  │   │
│  │    - AT 派发表 (~25 条)                         │   │
│  │    - 私有协议 (AT+ECRFNST=hex) hex 编解码       │   │
│  │    - 指令回显 (ATE0/ATE1)                       │   │
│  │    - 网络注册状态上报 (AT+CEREG)                │   │
│  │    - 动态 register 扩展点                       │   │
│  │    - UART 集成 (rfa.start/stop)                 │   │
│  └─────────────────────────────────────────────────┘   │
│           ▲ 调 mobile.rfTest* 桥        │ uart.write   │
└───────────┼──────────────────────────────┼─────────────┘
            ▼                              ▼
┌────────────────────────────────────────────────────────┐
│                C 端 (字节搬运工)                        │
│  luat_mobile_rf_test_mode(uart, on_off)   ← 切模式        │
│  luat_mobile_rf_test_input(data, len)     ← 喂字节        │
│  luat_mobile_rf_test_nst(hex, len, out)   ← ECRFNST 同步处理 │
│  luat_mobile_rf_test_param(k, *v, is_set) ← 状态存取      │
│  luat_mobile_rf_test_imei_get/set         ← IMEI          │
│  luat_mobile_rf_test_gmdata_get/set       ← Golden Unit   │
│  luat_mobile_rf_test_version()            ← RF/CP 版本    │
│  luat_mobile_rf_test_band_list()          ← 支持频段列表  │
│  luat_mobile_rf_test_set_rx_cb(cb)        ← Rx 钩子 (PC)  │
│                                                        │
│  PC 仿真: s_rf_test 静态结构, 状态存取后端, 不做派发  │
│  真机  : 走 soc_mobile_rf_test_input / RIL / PLAT     │
└────────────────────────────────────────────────────────┘
```

## 2. C 端接口 (11 个, 全部沿用 `luat_mobile_rf_test_*` 前缀)

| 函数 | 用途 | PC 仿真 | 真机 (luatos-soc-2024) |
|------|------|---------|------------------------|
| `void luat_mobile_rf_test_mode(uart_id, on_off)` | 切模式 + 绑 UART | 记 uart_id, 注册 Rx 钩子 | `soc_mobile_rf_test_mode` |
| `void luat_mobile_rf_test_input(data, len)` | 喂字节; `data=NULL` 触发 flush | 通过 cb 通知 Lua | `soc_mobile_rf_test_input` (不做 toupper/解析) |
| `int luat_mobile_rf_test_nst(hex, len, out, out_len)` | 同步处理 AT+ECRFNST hex | 返回占位 MT 响应 | 调用 `RfAtNstCmdPreHandle` |
| `int luat_mobile_rf_test_param(k, *v, is_set)` | 状态/NPI 存取 | `s_rf_test` 后端 | NPI APNV2 读写 + 本地 state |
| `int luat_mobile_rf_test_imei_get(out, len)` | 读 15 位 IMEI | `s_rf_test` 后端 | `appGetImeiNumSync` |
| `int luat_mobile_rf_test_imei_set(imei)` | 写 15 位 IMEI | `s_rf_test` 后端 | `appSetImeiNumSync` |
| `int luat_mobile_rf_test_gmdata_get(out, len)` | 读 Golden Unit 数据 | 内存缓冲 | `/rfTestFile` 文件读写 |
| `int luat_mobile_rf_test_gmdata_set(data, len)` | 写 Golden Unit 数据 | 内存缓冲 | `/rfTestFile` 文件读写 |
| `int luat_mobile_rf_test_version(out, len)` | RF/CP 版本信息 | 占位字符串 | `ShareInfoAPGetCPVersionInfo` 等 |
| `int luat_mobile_rf_test_band_list(out, len)` | 支持频段列表 | 占位字符串 | `appGetSupportedBandModeSync` |
| `int luat_mobile_rf_test_set_rx_cb(cb)` | 注册/注销 Rx 回调 | PC 仿真用 | 返 -1 或 0 (桩) |

**C 端约束**:
- **不**解析任何 AT 字符串
- **不**维护状态机
- **不**生成响应
- 只做"打开/收字节/存状态"

### 2.1 `luat_mobile_rf_test_param` 支持的 key

| key | 读写 | 真机行为 | 说明 |
|-----|------|----------|------|
| `"state"` | 读/写 | 本地静态变量 `s_rfa_state` | 0..6, 见状态机 |
| `"rfCaliDone"` | 读/写 | `npiGet/SetProcessStatusItemValue(RFCALI)` | 校准完成标志 |
| `"rfNSTDone"` | 读/写 | `npiGet/SetProcessStatusItemValue(RFNST)` | NST 完成标志 |
| `"rfCTDone"` | 读/写 | `npiGet/SetProcessStatusItemValue(RFCT)` | CT 完成标志 |
| `"save"` | 写 | `npiSaveConfigToAPNV2()` | 批量把上面 3 个位落 APNV2 |
| `"erfMode"` | 读/写 | 本地占位 / PC 仿真 | 错误注入, 单测用 |
| `"pmuEnable"` / `"pmuMode"` | 读/写 | 本地占位 | 待 PLAT 公开 API 后实化 |
| `"bandList"` | 读 | 本地占位 | 建议优先用 `mobile.rfTestBandList()` |
| `"facChk"` | 读 | 本地占位 | 工厂 NV header 检查 |
| `"prodMode"` | 写 | 本地占位 | 生产模式 |
| `"chipVer"` | 读 | 本地占位 0 | 真机建议用 `hmeta.chip()` |

**重要**: `npiSaveConfigToAPNV2()` 是保存 `rfCaliDone/rfNSTDone/rfCTDone` 的正确接口。旧代码若调用 `npiSaveNvmConfig()` 只会保存 `prodModeStatus`, 导致校准标志读回始终为 0 (详见第 10 节)。

## 3. Lua 端 `mobile.rfTest*` API

```lua
mobile.rfTestMode(uart_id, true)     -- 进入 RF 测试模式
mobile.rfTestMode(nil, false)        -- 退出
mobile.rfTestInput(data)             -- 向 C 端喂字节 (data 可为 nil 触发 flush)

-- 参数存取
mobile.rfTestParam("state")          -- 读 state (默认读)
mobile.rfTestParam("rfCaliDone", 1, true)  -- 写 rfCaliDone
mobile.rfTestParam("save", 0, true)  -- 真机端: 批量保存之前 set 的 NPI 位

mobile.rfTestImei()                  -- 读 IMEI (string)
mobile.rfTestImeiSet("864317081553409")  -- 写 IMEI
mobile.rfTestGmData()                -- 读 Golden Unit 数据
mobile.rfTestGmDataSet("golden data") -- 写 Golden Unit 数据

local rc, resp = mobile.rfTestNst("02040900...")  -- ECRFNST 同步处理
mobile.rfTestVersion()               -- RF/CP 版本信息 (string)
mobile.rfTestBandList()              -- 支持频段列表 (string, 如 "1,3,5,8,34,38,39,40,41")
```

**Lua 绑定约束**:
- `mobile.rfTestMode(uart_id, onoff)` 的 `onoff` 必须是 `true`/`false`/`nil`, **不能用整数 0** (整数 0 在 `lua_toboolean` 下 truthy, 会被当进入模式).
- `mobile.rfTestParam(k, v, is_set)` 的 `is_set` 必须是 `true`/`false`/`nil`, **不能用整数 0**.
- `rfa.lua` 内部已处理, 业务代码不会踩.

## 4. Lua 端 `rfa.*` API

```lua
local rfa = require "rfa"

-- 启动 (内部挂 uart.on)
rfa.start(uart.VUART_1, 115200)

-- 业务 API
rfa.dispatch("AT+CGSN=1")           -- 派发单行, 返响应 string
rfa.feed("AT\r\nAT+CGSN=1\r\n")    -- 喂 chunk, 切行并派发
rfa.state()                         -- 状态: 0..6
rfa.setState(4)                     -- 强制设状态
rfa.reset()                         -- 复位 (state + NPI)
rfa.npiGet("rfCaliDone")            -- 0/1
rfa.npiSet("rfCaliDone", 1)         -- 写并立即落 flash
rfa.imei()                          -- 读 IMEI
rfa.setImei("864317081553409")      -- 写 IMEI
rfa.setErrMode(true)                -- 错误注入 (单测用)

-- 扩展
rfa.register("AT+MYCMD", fn)        -- 注册自定义 AT 命令
rfa.registerRfnst("9999", fn)       -- 注册私有协议 cmdId 模板

-- RFA 模式开关 (ec7xx-at 产线入口)
rfa.setRfOn(true)
rfa.getRFAOnStatus()

rfa.stop()
```

## 5. 状态机 (Lua 端, 只升不降)

| 阶段 | 值 | 触发命令 | 副作用 |
|------|---|---------|--------|
| IDLE | 0 | 初始 / `rfa.reset()` | `setState(0)` |
| PREP | 1 | `AT+CGSN=1` / `AT+CGSN` | `setState(max(s, 1))` |
| CALIB | 2 | `AT+ECRFNST=…` 任意 cmdId (除 0D0A/51-5A) | `setState(max(s, 2))` |
| SELF_CAL | 3 | `AT+ECRFNST=0D0A…` | `setState(3)` |
| WRITE_NV | 4 | `AT+ECNPICFG=rfCaliDone,1` | `setState(4)` |
| NST_TEST | 5 | `AT+ECRFNST=0051…005A` | `setState(5)` |
| DONE | 6 | `AT+ECNPICFG=rfNSTDone,1` | `setState(6)` |

## 6. AT 派发表 (内建)

### 6.1 基础 AT 控制

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `AT` | `\r\nOK\r\n` | — |
| `ATE`, `ATE1` | `\r\nOK\r\n` | 开启指令回显 |
| `ATE0` | `\r\nOK\r\n` | 关闭指令回显 |
| `ATQ[0,1]?` | `\r\nOK\r\n` | 兼容占位 |
| `AT+ECRST` | `\r\nOK\r\n` | 触发 `rtos.reboot()` |

### 6.2 信息查询

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `ATI` | `\r\nLuatOS_<型号>_<版本>\r\n\r\nOK\r\n` | — |
| `AT*I` | 多行制造商/型号/版本/IMEI/ICCID/IMSI | — |
| `AT+CGMR` | `\r\n+CGMR: "AirM2M_<型号>_<版本>_LTE_LuatOS"\r\n\r\nOK\r\n` | — |
| `AT+CGSN` | `\r\n<imei>\r\n\r\nOK\r\n` | `setState(PREP)` |
| `AT+CGSN=1` | `\r\n+CGSN: "<imei>"\r\n\r\nOK\r\n` | `setState(PREP)` |
| `AT+MUID?` | `\r\n+MUID: <muid>\r\n\r\nOK\r\n` | — |
| `AT+MUID="<muid>"` / `AT+MUID=<muid>` | `\r\nOK\r\n` | 调用 `mobile.muidSet()` |
| `AT+CCID` | `\r\n<iccid>\r\n\r\nOK\r\n` | — |
| `AT+ECICCID` / `AT+ECICCID?` | `\r\n+ECICCID: <iccid>\r\n\r\nOK\r\n` | — |
| `AT+ECCHIPVER?` | `\r\n+ECCHIPVER:<ver>\r\n\r\nOK\r\n` | 优先 `hmeta.chip()`, 回退 `mobile.rfTestParam("chipVer")` |
| `AT+ECVERSION?` | 多行 `+CP VER` / `+RfTable VER` / `+Customer Moduler` ... | 调用 `mobile.rfTestVersion()` |
| `AT+ECBAND=?` | `\r\n+ECBAND: (<bands>)\r\n\r\nOK\r\n` | 优先 `mobile.rfTestBandList()` |
| `AT+ECBAND?` | `\r\n+ECBAND: <bands>\r\n\r\nOK\r\n` | 优先 `mobile.rfTestBandList()` |
| `AT+ECGMDATA?` | `\r\n+ECGMDATA: "<data>"\r\n\r\nOK\r\n` | 调用 `mobile.rfTestGmData()` |
| `AT+ECGMDATA=<data>` | `\r\nOK\r\n` | 调用 `mobile.rfTestGmDataSet()` |

### 6.3 NPI / 校准标志

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `AT+ECNPICFG=?` | `\r\n+ECNPICFG:<option>,<setting>\r\n\r\nOK\r\n` | — |
| `AT+ECNPICFG?` | `\r\n+ECNPICFG: "rfCaliDone":%d,"rfNSTDone":%d, "rfCTDone":%d\r\n\r\nOK\r\n` | — |
| `AT+ECNPICFG=rfCaliDone,{0,1}` | `\r\nOK\r\n` | `npiSet` + `setState(WRITE_NV)` |
| `AT+ECNPICFG=rfNSTDone,{0,1}` | `\r\nOK\r\n` | `npiSet` + `setState(DONE)` |
| `AT+ECNPICFG=rfCTDone,{0,1}` | `\r\nOK\r\n` | `npiSet` |
| `AT+ECNPICFG=<key1>,<val1>,<key2>,<val2>…` | `\r\nOK\r\n` | 支持批量设置, 值变化时统一 `save` |

### 6.4 IMEI / 生产模式

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `AT+ECCGSN="IMEI","<imei>"` | `\r\nOK\r\n` | 写 IMEI |
| `AT+ECCGSN=1,<imei>` | `\r\nOK\r\n` | 写 IMEI |
| `AT+PRODUC` | `\r\nOK\r\n` | 写 `prodMode` 标志 |
| `AT+ECFACCHK=1` | `\r\n+ECFACCHK: <result>\r\n\r\nOK\r\n` | 读 `facChk` |

### 6.5 网络注册 (CEREG)

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `AT+CEREG` | `\r\nOK\r\n` | — |
| `AT+CEREG?` | `\r\n+CEREG: <n>,<stat>[,"<tac>","<ci>",7]\r\n\r\nOK\r\n` | `mobile.status()/tac()/eci()` |
| `AT+CEREG=?` | `\r\n+CEREG: (0,1,2,3,4,5)\r\n\r\nOK\r\n` | — |
| `AT+CEREG=<n>` (n=0..5) | `\r\nOK\r\n` | 设置上报模式 `cereg_mode_` |

### 6.6 飞行模式 / PMU / 配置

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `AT+CFUN=0` | `\r\nOK\r\n` | 进入飞行模式 |
| `AT+CFUN=1` | `\r\nOK\r\n` | 退出飞行模式 |
| `AT+CFUN=4` | `\r\nOK\r\n` | 进入飞行模式 (CFUN=0 别名) |
| `AT+CPIN?` | `\r\n+CPIN: READY\r\n\r\nOK\r\n` 或 `+CME ERROR: 10/304` | 检查 `mobile.simPin()` |
| `AT+ECPMUCFG=<enable>[,<mode>]` | `\r\nOK\r\n` | 设置 PMU 占位值 |
| `AT+ECPMUCFG?` | `\r\n+ECPMUCFG: <enable>,<mode>\r\n\r\nOK\r\n` | 读 PMU 占位值 |
| `AT+SETCFG="rfa_mode","true/false"` | `\r\nOK\r\n` | 调用 `rfa.setRfOn()` |
| `AT+SETCFG?` | `\r\n+SETCFG: "rfa_mode","true/false"\r\n\r\nOK\r\n` | 调用 `rfa.getRFAOnStatus()` |

### 6.7 私有协议 / 扩展

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `AT+ECRFNST=<hex>` | 见第 7 节 | 真机调用 `RfAtNstCmdPreHandle`; PC 占位; `setState` 按 cmdId 推进 |
| `AT+<other>` | `\r\nERROR\r\n` | 可由 `rfa.register` 扩展 |

## 7. 指令回显

`rfa.lua` 启动后默认开启回显 (`echo_on_ = true`)。收到完整 AT 行后, 在返回结果前先把收到的指令原样发回:

```
AT+CGSN=1\r\n          <-- 工具发送
AT+CGSN=1\r\n          <-- 模块回显
\r\n+CGSN: "..."\r\n\r\nOK\r\n
```

- `ATE0` 关闭回显。
- `ATE1` 或 `ATE` 开启回显。
- 回显开关是 `rfa.lua` 本地状态, 不依赖 C 后端。

## 8. AT+ECRFNST 私有协议处理

### 8.1 命令分类

`rfa.lua` 根据 cmdId 前缀决定响应顺序:

| 前缀 | 示例 | 顺序 | 说明 |
|------|------|------|------|
| `03` / `0A` / `12` / `020F` | `020F`, `0A0D` | 先 MT 后 OK (`mt_first`) | 同步响应 |
| 其他 `02xx` | `020D` | 先 OK 后 MT (`ok_first`) | MT 由 `SIG_FAST_PHY_CMI_IND` 异步返回 |

### 8.2 大响应分块 (`020D` / `0A0D`)

- `020D` 单次返回最多 **8KB**, 超出部分由工具继续发 `0A0D` 续读。
- C 端缓冲区 `RF_NST_WORK_BUF_SIZE` 必须严格限制为 **8000** 字节, 因为 `atRfNstRspInd` 硬上限 8K。
- `lenOut==0` 时不可主动 `ResumeTrans` 预读, 否则同步/异步路径数据交叉, 分块边界会出现脏数据。

### 8.3 状态机推进

| cmdId | 推进状态 |
|-------|---------|
| `0D0A` | SELF_CAL (3) |
| `0051` ~ `005A` | NST_TEST (5) |
| 其他 | CALIB (2) |

## 9. 测试

- `testcase/utest/drv/mobile_rfa_basic/` — 4 套件, 42+ case
  - c_suite: C 端桩 (mobile.rfTest* 11 个)
  - lua_suite: Lua 绑定 (mobile.rfTest* 注册)
  - at_suite: 派发表覆盖 (~25 条)
  - rfa_suite: rfa.lua 模块 (state / IMEI / RFNST / 注册 / 回显 / CEREG)
- `tools/rfa_com0com/test_rfa_com0com.py` — 端到端 com0com 测试

构建验证:
- `luatos-soc-2024` `ec718pm` / `ec718hm` 目标编译通过
- `python build_luatos_types.py Air780EPM 1` 编译通过并生成 `.soc`
- `python build_luatos_types.py Air780EHM 1` 编译通过并生成 `.soc`
- LuatOS PC 端口 `mobile_rfa_basic` / `mobile_rfa_station1_replay` utest `OVERALL_PASS`

## 10. 迁移指南 (从旧 mobile.rfcal* 迁移)

| 旧 API | 新 API |
|--------|--------|
| `mobile.rfcalNpiGet(k)` | `mobile.rfTestParam(k)` |
| `mobile.rfcalNpiSet(k, v)` | `mobile.rfTestParam(k, v, true)` |
| `mobile.rfcalState()` | `rfa.state()` (或 `mobile.rfTestParam("state")`) |
| `mobile.rfcalReset()` | `rfa.reset()` |
| `mobile.rfcalAt(line)` | `rfa.dispatch(line)` |
| `mobile.rfcalRfnst(hex)` | `rfa.dispatch("AT+ECRFNST=" .. hex)` |
| `mobile.rfcalSetImei(imei)` | `mobile.rfTestImeiSet(imei)` |
| `mobile.nstOnOff(on, uart)` | `mobile.rfTestMode(uart, on)` |
| `mobile.nstInput(data)` | `mobile.rfTestInput(data)` |

## 11. 真机对接 (luatos-soc-2024)

已在 `interface/src/luat_mobile_ec7xx.c` 实现:
- `luat_mobile_rf_test_mode` — 转发 `soc_mobile_rf_test_mode`
- `luat_mobile_rf_test_input` — 直接 push 到 RIL 队列
- `luat_mobile_rf_test_nst` — 调用 PLAT `RfAtNstCmdPreHandle`, 8K 输出缓冲, 异步 MT 走 `__wrap_soc_cms_proc`
- `luat_mobile_rf_test_param` — 映射到 `npi_config.h`:
  - `rfCaliDone/rfNSTDone/rfCTDone` → `npiGet/SetProcessStatusItemValue`
  - `"save"` → `npiSaveConfigToAPNV2()` (APNV2 持久化)
  - `"state"` → 本地静态变量
- `luat_mobile_rf_test_imei_get/set` — `appGetImeiNumSync` / `appSetImeiNumSync`
- `luat_mobile_rf_test_gmdata_get/set` — `/rfTestFile` 文件读写
- `luat_mobile_rf_test_version` — `ShareInfoAPGetCPVersionInfo` 等
- `luat_mobile_rf_test_band_list` — `appGetSupportedBandModeSync`
- `luat_mobile_rf_test_set_rx_cb` — 返 -1 或 0 (真机不需要)

EC718HM/EC718PM 共用同一接口文件。

### 11.1 占位/待实化项

- `AT+ECPMUCFG`、`AT+ECFACCHK=1` 的真机后端目前返回占位值, 待 PLAT 侧公开对应 API 后再实化。
- `AT+SETCFG` 的 `"rfa_mode"` 仅影响 Lua 层配置文件与 fskv, 不做 C 侧切换。

## 12. 关键问题复盘

### 12.1 AGC 校准项失败 (2026-06-16)

现象: `Rf_Cal_Nst_Log.txt` 反复打印 `Ue_Agc: Get Agc Cal Data Fail!`

根因: `RF_NST_WORK_BUF_SIZE` 设为 12000, 超过 `atRfNstRspInd` 8K 硬上限, 导致 `020D` 响应末尾被脏数据污染。

修复: 缓冲区改为 8000, 同步路径删除 `ResumeTrans` 循环, 大响应走"异步 MT + 工具发 `0A0D` 续读"。

### 12.2 Air780EPM 020D 分块边界乱码 (2026-06-17)

根因: `luat_mobile_rf_test_nst` 在 `lenOut==0` 时循环 `ResumeTrans` 预读, 与 `SIG_FAST_PHY_CMI_IND` 异步路径数据交叉。

修复: `lenOut==0` 直接返回空; 新增 `memset(temp_buf_addr, 0, RF_NST_WORK_BUF_SIZE)` 与 AT 固件保持一致。

### 12.3 `checkCaliFlag` FAIL — `rfCaliDone` 保存失败 (2026-06-30)

现象:
```
AT+ECNPICFG=rfCaliDone,1
OK
AT+ECNPICFG?
+ECNPICFG: "rfCaliDone":0,...
```

根因: `luat_mobile_rf_test_param("save", ...)` 调用 `npiSaveNvmConfig()`, 该函数只保存旧 NVM 文件里的 `prodModeStatus`, 不会保存已迁移到 APNV2 的 `NPIProcessStatus` 位域; 同时 `npiGetProcessStatusItemValue()` 因缺少 magic header 直接返回 0。

修复: `"save"` 改调用 `npiSaveConfigToAPNV2()`, 正确把 `rfCaliDone/rfNSTDone/rfCTDone` 写入 APNV2 并设置 magic header。
