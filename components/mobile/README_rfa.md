# mobile 库 RF 校准功能 (rfa 重构版)

> 替代旧 `README_rfcal.md` (2026-06-13 重构)
>
> 设计哲学: **Thin C / Fat Lua** — C 端只做"打开/收字节/存状态"三类原语, 所有 AT 协议由 Lua `rfa.*` 模块解析

## 1. 模块分层

```
┌────────────────────────────────────────────────────────┐
│                    Lua 端 (业务大脑)                    │
│  ┌─────────────────────────────────────────────────┐   │
│  │  script/libs/rfa.lua                             │   │
│  │    - 状态机 7 阶段 (IDLE→DONE)                  │   │
│  │    - AT 派发表 (~12 条)                         │   │
│  │    - 私有协议 (AT+ECRFNST=hex) hex 编解码       │   │
│  │    - 动态 register 扩展点                       │   │
│  │    - UART 集成 (rfa.start/stop)                 │   │
│  └─────────────────────────────────────────────────┘   │
│           ▲ 调 mobile.rfTest* 桥        │ uart.write   │
└───────────┼──────────────────────────────┼─────────────┘
            ▼                              ▼
┌────────────────────────────────────────────────────────┐
│                C 端 (字节搬运工)                        │
│  luat_mobile_rf_test_mode(uart, on_off)   ← 切模式    │
│  luat_mobile_rf_test_input(data, len)     ← 喂字节    │
│  luat_mobile_rf_test_param(k, *v, is_set) ← 状态存取  │
│  luat_mobile_rf_test_imei_get/set         ← IMEI      │
│  luat_mobile_rf_test_set_rx_cb(cb)        ← Rx 钩子   │
│                                                        │
│  PC 仿真: s_rf_test 静态结构, 状态存取后端, 不做派发  │
│  真机  : 走 soc_mobile_rf_test_input → PLAT           │
└────────────────────────────────────────────────────────┘
```

## 2. C 端接口 (5 个, 全部沿用 `luat_mobile_rf_test_*` 前缀)

| 函数 | 用途 | PC 仿真 | 真机 |
|------|------|---------|------|
| `luat_mobile_rf_test_mode(uart, on)` | 切模式 + 绑 UART | 记 uart_id, 内部 log | RIL_EnterRFTestMode + bind |
| `luat_mobile_rf_test_input(data, len)` | 喂字节; `data=NULL` 触发 flush | 通过 cb 通知 Lua | push 到 RIL 队列 |
| `luat_mobile_rf_test_param(k, *v, is_set)` | 状态存取 (NPI / state / erfMode) | s_rf_test 后端 | 返 -1 (走 mobile.nv/pm) |
| `luat_mobile_rf_test_imei_get/set` | 15 位 IMEI 字符串 | s_rf_test 后端 | NPI IMEI |
| `luat_mobile_rf_test_set_rx_cb(cb)` | 注册/注销 Rx 回调 | PC 仿真用, 真机返 -1 | 返 -1 |

**C 端约束**:
- **不**解析任何 AT 字符串
- **不**维护状态机
- **不**生成响应
- 只做"打开/收字节/存状态"

## 3. Lua 端 `rfa.*` API

```lua
local rfa = require "rfa"

-- 启动 (内部挂 uart.on)
rfa.start(uart.VUART_1, 115200)

-- 业务 API
rfa.dispatch("AT+CGSN=1")        -- 派发单行, 返响应 string
rfa.feed("AT\r\nAT+CGSN=1\r\n") -- 喂 chunk, 切行并派发
rfa.state()                     -- 状态: 0..6
rfa.setState(4)                 -- 强制设状态
rfa.reset()                     -- 复位 (state + NPI)
rfa.npiGet("rfCaliDone")        -- 0/1
rfa.npiSet("rfCaliDone", 1)     -- 副作用 (立即落 flash)
rfa.reset()                     -- 复位 (state + NPI, 统一落一次 flash)
mobile.rfTestParam("save", 0, true)  -- 真机端: 批量保存之前 set 的 NPI 位
rfa.imei()                      -- 读 IMEI
rfa.setImei("864317081553409")  -- 写 IMEI
rfa.setErrMode(true)            -- 错误注入 (单测用)

-- 扩展
rfa.register("AT+MYCMD", fn)    -- 注册自定义 AT 命令
rfa.registerRfnst("9999", fn)   -- 注册私有协议 cmdId 模板

rfa.stop()
```

## 4. 状态机 (Lua 端, 只升不降)

| 阶段 | 值 | 触发命令 | 副作用 |
|------|---|---------|--------|
| IDLE | 0 | 初始 / `rfa.reset()` | `setState(0)` |
| PREP | 1 | `AT+CGSN=1` | `setState(max(s, 1))` |
| CALIB | 2 | `AT+ECRFNST=…` 任意 cmdId | `setState(max(s, 2))` |
| SELF_CAL | 3 | cmdId 0x0D/0x0A (留扩展) | `setState(3)` |
| WRITE_NV | 4 | `AT+ECNPICFG=rfCaliDone,1` | `setState(4)` |
| NST_TEST | 5 | cmdId 0x51~0x5A (留扩展) | `setState(5)` |
| DONE | 6 | `AT+ECNPICFG=rfNSTDone,1` | `setState(6)` |

## 5. AT 派发表 (内建)

| 命令 | 响应 | 副作用 |
|------|------|--------|
| `AT`, `ATE0`, `ATE1` | `\r\nOK\r\n` | — |
| `AT+CGSN=1` | `\r\n+CGSN: "<imei>"\r\n\r\nOK\r\n` | `setState(max(s, PREP))` |
| `AT+ECNPICFG=rfCaliDone,{0,1}` | `\r\nOK\r\n` | `npiSet` + `setState(WRITE_NV)` |
| `AT+ECNPICFG=rfNSTDone,{0,1}` | `\r\nOK\r\n` | `npiSet` + `setState(DONE)` |
| `AT+ECNPICFG=rfCTDone,{0,1}` | `\r\nOK\r\n` | `npiSet` |
| `AT+ECNPICFG?` | `\r\n+ECNPICFG: ...\r\n\r\nOK\r\n` | — |
| `AT+CFUN=0` | `\r\nOK\r\n` | — |
| `AT+CPIN?` | `\r\n+CME ERROR: 303\r\n` | — |
| `AT+ECCHIPVER?` | `\r\nERROR\r\n` | — |
| `AT+ECGMDATA?` | `\r\nOK\r\n` | — |
| `AT+ECRFNST=<hex>` | `\r\n<MT hex>\r\nOK\r\n` | `setState(max(s, CALIB))` |
| `AT+<other>` | `\r\nERROR\r\n` | 可由 `rfa.register` 扩展 |

## 6. 测试

- `testcase/utest/drv/mobile_rfa_basic/` — 4 套件, 13 case
  - c_suite: C 端桩 (mobile.rfTest* 5 个)
  - lua_suite: Lua 绑定 (mobile.rfTest* 注册)
  - at_suite: 派发表覆盖 (12 条)
  - rfa_suite: rfa.lua 模块 (state / IMEI / RFNST / 注册)
- `tools/rfa_com0com/test_rfa_com0com.py` — 端到端 com0com 测试 (basic 8 case + full 11 case)

## 7. 迁移指南 (从旧 mobile.rfcal* 迁移)

| 旧 API | 新 API |
|--------|--------|
| `mobile.rfcalNpiGet(k)` | `mobile.rfTestParam(k)` |
| `mobile.rfcalNpiSet(k, v)` | `mobile.rfTestParam(k, v, true)` |
| `mobile.rfcalState()` | `rfa.state()` (或 `mobile.rfTestParam("state")`) |
| `mobile.rfcalReset()` | `rfa.reset()` |
| `mobile.rfcalAt(line)` | `rfa.dispatch(line)` |
| `mobile.rfcalRfnst(hex)` | `rfa.rfnst(hex)` (走 rfa.lua) |
| `mobile.rfcalSetImei(imei)` | `mobile.rfTestImeiSet(imei)` |
| `mobile.nstOnOff(on, uart)` | `mobile.rfTestMode(uart, on)` |
| `mobile.nstInput(data)` | `mobile.rfTestInput(data)` |

**注意点**:
- C 绑定 `mobile.rfTestMode(uart_id, onoff)` 的 `onoff` 必须是 `true`/`false`/`nil`, **不能用整数 0** (整数 0 在 `lua_toboolean` 下 truthy, 会被当进入模式).
- C 绑定 `mobile.rfTestParam(k, v, is_set)` 的 `is_set` 必须是 `true`/`false`/`nil`, **不能用整数 0** (整数 0 在 `lua_toboolean` 下 truthy, 会被当写模式).
- `rfa.lua` 内部已处理, 业务代码不会踩.

## 8. 真机对接 (luatos-soc-2024)

单独的 PR, 在 `interface/src/luat_mobile_ec7xx.c` 实现:
- `luat_mobile_rf_test_mode` — 调 `RIL_EnterRFTestMode` + `RIL_BindUart`
- `luat_mobile_rf_test_input` — 去掉 toupper, 直接 push 到 RIL 队列
- `luat_mobile_rf_test_param` / `imei_get` / `imei_set` — 直读 NPI NV
- `luat_mobile_rf_test_set_rx_cb` — 返 -1 (真机不需要)

toupper 逻辑应从 luat 层移到 PLAT atcReply 内部, 避免破坏小写 hex (如 `0a`).
