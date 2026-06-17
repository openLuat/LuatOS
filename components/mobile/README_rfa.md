# mobile 库 RF 校准功能 (rfa 重构版)

> 替代旧 `README_rfcal.md` (2026-06-13 重构)
>
> 设计哲学: **Thin C / Fat Lua** — C 端只做"打开/收字节/存状态"三类原语, 所有 AT 协议由 Lua `rfa.*` 模块解析
>
> 本版补充 EC718HM/EC718PM 真机适配 (2026-06-15)

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
│  luat_mobile_rf_test_mode(uart, on_off)   ← 切模式        │
│  luat_mobile_rf_test_input(data, len)     ← 喂字节        │
│  luat_mobile_rf_test_nst(hex, len, out)   ← ECRFNST 同步处理 │
│  luat_mobile_rf_test_param(k, *v, is_set) ← 状态存取      │
│  luat_mobile_rf_test_imei_get/set         ← IMEI          │
│  luat_mobile_rf_test_set_rx_cb(cb)        ← Rx 钩子       │
│                                                        │
│  PC 仿真: s_rf_test 静态结构, 状态存取后端, 不做派发  │
│  真机  : 走 soc_mobile_rf_test_input → PLAT           │
└────────────────────────────────────────────────────────┘
```

## 2. C 端接口 (7 个, 全部沿用 `luat_mobile_rf_test_*` 前缀)

| 函数 | 用途 | PC 仿真 | 真机 |
|------|------|---------|------|
| `luat_mobile_rf_test_mode(uart, on)` | 切模式 + 绑 UART | 记 uart_id, 内部 log | `soc_mobile_rf_test_mode` |
| `luat_mobile_rf_test_input(data, len)` | 喂字节; `data=NULL` 触发 flush | 通过 cb 通知 Lua | `soc_mobile_rf_test_input` |
| `luat_mobile_rf_test_nst(hex, len, out)` | 同步处理 AT+ECRFNST hex 指令 | 返回占位 MT 响应 | 调用 `RfAtNstCmdPreHandle` |
| `luat_mobile_rf_test_param(k, *v, is_set)` | 状态存取 (NPI / state / erfMode / pmu / chipVer / bandList / facChk) | s_rf_test 后端 | NPI NV 读写 + 占位扩展 |
| `luat_mobile_rf_test_imei_get/set` | 15 位 IMEI 字符串 | s_rf_test 后端 | `appGetImeiNumSync` / `appSetImeiNumSync` |
| `luat_mobile_rf_test_gmdata_get/set` | Golden Unit 数据读写 | s_rf_test 内存缓冲 | `luat_fs_fopen/fread/fwrite` 操作 `/rfTestFile` |
| `luat_mobile_rf_test_set_rx_cb(cb)` | 注册/注销 Rx 回调 | PC 仿真用, 真机返 -1 | 返 0 (桩) |

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
| `AT+CFUN=0/1/4` | `\r\nOK\r\n` | 飞行模式开关 |
| `AT+CPIN?` | `\r\n+CME ERROR: 303\r\n` | — |
| `AT+ECRST` | `\r\nOK\r\n` | 触发 `mobile.restart()` |
| `AT+ECCGSN=1,<imei>` | `\r\nOK\r\n` / `ERROR` | 写 IMEI |
| `AT+ECGMDATA?` | `\r\n+ECGMDATA: "<data>"\r\n\r\nOK\r\n` | — |
| `AT+ECGMDATA=<data>` | `\r\nOK\r\n` | 写 Golden Unit 数据 |
| `AT+ECCHIPVER?` | `\r\n+ECCHIPVER: <ver>\r\n\r\nOK\r\n` | — |
| `AT+ECBAND=?` | `\r\n+ECBAND: (<bands>)\r\n\r\nOK\r\n` | — |
| `AT+ECICCID` | `\r\n+ECICCID: "<iccid>"\r\n\r\nOK\r\n` | 读 ICCID |
| `AT+ECPMUCFG=<enable>[,<mode>]` | `\r\nOK\r\n` | 设置 PMU 模式 |
| `AT+ECPMUCFG?` | `\r\n+ECPMUCFG: <enable>,<mode>\r\n\r\nOK\r\n` | — |
| `AT+ECFACCHK=1` | `\r\n+ECFACCHK: <result>\r\n\r\nOK\r\n` | — |
| `AT+ECRFNST=<hex>` | `\r\n<MT hex>\r\nOK\r\n` | 真机调用 `RfAtNstCmdPreHandle`; PC 占位; `setState` 按 cmdId 推进 |
| `AT+<other>` | `\r\nERROR\r\n` | 可由 `rfa.register` 扩展 |

## 6. 测试

- `testcase/utest/drv/mobile_rfa_basic/` — 4 套件, 42+ case
  - c_suite: C 端桩 (mobile.rfTest* 7 个)
  - lua_suite: Lua 绑定 (mobile.rfTest* 注册)
  - at_suite: 派发表覆盖 (18 条, 含 ECRST/ECCGSN/ECGMDATA/ECCHIPVER/ECBAND/ECICCID/ECPMUCFG/ECFACCHK)
  - rfa_suite: rfa.lua 模块 (state / IMEI / RFNST / 注册)
- `tools/rfa_com0com/test_rfa_com0com.py` — 端到端 com0com 测试 (basic 8 case + full 11 case)

构建验证:
- `luatos-soc-2024` `ec718pm` / `ec718hm` 目标编译通过
- `python build_luatos_types.py Air780EHM 1` 编译通过并生成 `.soc`
- LuatOS PC 端口 `mobile_rfa_basic` / `mobile_rfa_station1_replay` utest `OVERALL_PASS`

## 7. 迁移指南 (从旧 mobile.rfcal* 迁移)

| 旧 API | 新 API |
|--------|--------|
| `mobile.rfcalNpiGet(k)` | `mobile.rfTestParam(k)` |
| `mobile.rfcalNpiSet(k, v)` | `mobile.rfTestParam(k, v, true)` |
| `mobile.rfcalState()` | `rfa.state()` (或 `mobile.rfTestParam("state")`) |
| `mobile.rfcalReset()` | `rfa.reset()` |
| `mobile.rfcalAt(line)` | `rfa.dispatch(line)` |
| `mobile.rfcalRfnst(hex)` | `rfa.dispatch("AT+ECRFNST=" .. hex)` (走 rfa.lua, 真机调 `RfAtNstCmdPreHandle`) |
| `mobile.rfcalSetImei(imei)` | `mobile.rfTestImeiSet(imei)` |
| `mobile.nstOnOff(on, uart)` | `mobile.rfTestMode(uart, on)` |
| `mobile.nstInput(data)` | `mobile.rfTestInput(data)` |

**注意点**:
- C 绑定 `mobile.rfTestMode(uart_id, onoff)` 的 `onoff` 必须是 `true`/`false`/`nil`, **不能用整数 0** (整数 0 在 `lua_toboolean` 下 truthy, 会被当进入模式).
- C 绑定 `mobile.rfTestParam(k, v, is_set)` 的 `is_set` 必须是 `true`/`false`/`nil`, **不能用整数 0** (整数 0 在 `lua_toboolean` 下 truthy, 会被当写模式).
- `rfa.lua` 内部已处理, 业务代码不会踩.

## 8. 真机对接 (luatos-soc-2024)

已在 `interface/src/luat_mobile_ec7xx.c` 实现:
- `luat_mobile_rf_test_mode` — 转发 `soc_mobile_rf_test_mode`
- `luat_mobile_rf_test_input` — `toupper` 后转发 `soc_mobile_rf_test_input`
- `luat_mobile_rf_test_nst` — 将 hex 字符串转为二进制后调用 PLAT `RfAtNstCmdPreHandle`, 返回 MT 响应
- `luat_mobile_rf_test_param` — 映射到 `npi_config.h` 的 NPI 接口 (`rfCaliDone/rfNSTDone/rfCTDone/state/erfMode/pmu*/chipVer/bandList/facChk/save`)
- `luat_mobile_rf_test_imei_get/set` — 调用 `appGetImeiNumSync` / `appSetImeiNumSync`
- `luat_mobile_rf_test_gmdata_get/set` — 通过 `luat_fs_*` 读写 `/rfTestFile`
- `luat_mobile_rf_test_set_rx_cb` — 返 0 (真机不需要 Rx 回调)

EC718HM/EC718PM 共用同一接口文件。

**Air780EHM 固件编译适配**：当前 PLAT 未对 ec718hm 提供 i2s/audio 驱动，但 `luat_conf_bsp_air780ehm.h` 与原 xmake 配置仍启用了 media/volte/voip/tts 等功能，导致 `python build_luatos_types.py Air780EHM 1` 出现 `luat_crypto_ec7xx.o` 多重定义及大量 audio/i2s 未定义引用。已做以下适配：
- `project/project.lua`：ec718hm 排除 `luat_audio_ec7xx.c`、`luat_i2s_ec7xx.c`、`luat_multimedia_audio.c`；补充 `components/multimedia/audio/include` include 路径。
- `project/luatos/xmake.lua`：ec718hm 排除 mp3/tts/aisound 库、cc 组件、multimedia/audio 块、voip/speex、audio_v2；取消 `luat_crypto_ec7xx.c` 的重复编译。
- `project/luatos/inc/luat_conf_bsp_air780ehm.h`：禁用 `LUAT_USE_MEDIA`/`RECORD`/`AUDIO_G711`/`TTS`/`VOLTE`/`VOIP`/`VOIP_AEC`/`I2S`。
- `build_luatos_types.py`：强制 `MSYSTEM=` / `XMAKE_PLATFORM=windows`，避免 MSYS2/MINGW 下 host 误判。

注意:
- `AT+ECRFNST=<hex>` 真机后端已实化, 调用 PLAT `RfAtNstCmdPreHandle`, 与 ec7xx AT 固件行为一致。
- `AT+ECPMUCFG`、`AT+ECCHIPVER?`、`AT+ECBAND=?`、`AT+ECFACCHK=1` 的真机后端目前返回占位值, 待 PLAT 侧公开对应 API 后再实化。

## 9. AGC 校准项失败复盘 (2026-06-16)

### 现象
在校准工具上跑 LuatOS 流程时，**AGC 校准项失败**，`Rf_Cal_Nst_Log.txt` 反复打印：

```
Ue_Agc: Get Agc Cal Data Fail!
```

对比 AT 固件成功日志发现：
- `AT+ECRFNST=020D` 长响应在 LuatOS 日志中出现 **二进制脏数据**，且工具没有继续发送 `0A0D` 读取后续块；
- AT 固件中 `020D` 只返回约 **8KB**（两包：4096 + 3912），然后由 `0A0D` 再读约 **2KB**；
- LuatOS 中 `020D` 一次返回了约 **10KB**，并在 4096 边界处出现不可读字节。

### 根因
`interface/src/luat_mobile_ec7xx.c` 里拦截 `SIG_FAST_PHY_CMI_IND` 的 `__wrap_soc_cms_proc` 给 `atRfNstRspInd` 传入了 **12KB** 缓冲区：

```c
#define RF_NST_WORK_BUF_SIZE 12000
```

但 PLAT 闭源实现 `atRfNstRspInd` 的说明中明确写道：

> if the length of response content is large than 128 bytes, need to modify the below dataOutBuf's length;  
> **the maximum of length is 8K bytes**.

`atRfNstRspInd` 只会按自己的 8K 逻辑格式化数据；传入 12K 后，超过 8K 的位置被填入无效/非 hex 内容，导致：
1. `020D` 响应末尾被脏数据污染；
2. 原本应分两次返回的 `020D`(8K) + `0A0D`(2K) 被错误地合并成一次 10K 响应；
3. 校准工具解析 AGC 数据失败，流程中止。

### 修复
将缓冲区严格限制为 **8KB**，并与 AT 固件 `soc_mobile_test` 的共享内存布局保持一致（输出缓冲区在 `RF_NST_TEMP_BUFF_ADDR1 + 8000`，输入缓冲区在其后）：

- `luatos-soc-2024/interface/src/luat_mobile_ec7xx.c`
  - `RF_NST_WORK_BUF_SIZE`：`12000` → `8000`
  - `RfAtNstCmdPreHandle` 输出缓冲区：`temp_buf_addr` → `temp_buf_addr + RF_NST_WORK_BUF_SIZE`
  - 输入缓冲区：`temp_buf_addr + RF_NST_WORK_BUF_SIZE` → `rfBufOut + RF_NST_INPUT_BUF_SIZE`
- `LuatOS/components/mobile/luat_lib_mobile.c`
  - `l_mobile_rf_test_nst` 的 Lua 侧输出缓冲：`12000` → `8000`

### 验证
修复后重新编译、烧录 `LuatOS-SoC_V2043_Air780EHM_1.soc`，使用同一台校准工具和同一模块复测，**AGC 校准项通过**，整个 RFA 流程完成，无异常。

### 结论
`atRfNstRspInd` 的输出硬上限是 **8KB**，不能通过简单扩大缓冲区来“支持更长响应”。`020D`/`0A0D` 这类大响应必须沿用 AT 固件的分块机制：单次最多 8K，超出部分由工具继续发 `0A0D` 读取。
