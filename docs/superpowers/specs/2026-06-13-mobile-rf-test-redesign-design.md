# mobile RF 校准 rfa 重构设计 (Thin C / Fat Lua)

## Summary

LuatOS `mobile` 库的 RF 校准功能彻底重写. **C 端退化为 UART 字节透传层** (沿用 `luat_mobile_rf_test_*` 前缀), **所有 AT 解析/响应/状态机/私有协议生成全部移到 Lua** (新模块 `rfa.*`). 旧 `mobile.nst*` 和 `mobile.rfcal*` API 全删, 重新设计.

## Context

当前 `bsp/pc/port/luat_mobile_pc.c:312-319` 的 `luat_mobile_rf_test_mode/input` 是空桩 — 私有协议数据被静默丢弃. `bsp/pc/port/luat_mobile_pc.c:522-569` 的 `luat_mobile_rfcal_at_dispatch` 在 C 端用 strncmp 硬编码 AT 派发表, 真机 stub 返 -1, PC 仿真和真机行为脱节, Lua 端 `rfcal_at_server.lua` 形同虚设.

参考 `luatos-soc-2024/interface/src/luat_mobile_ec7xx.c:1071-1086` 把数据 toupper 后转给 `soc_mobile_rf_test_input`, 把"AT 解析在哪"踢给 BSP, 同样不符合"业务在 Lua"的设计哲学.

已有的 `luat_mobile_rf_test_mode` / `luat_mobile_rf_test_input` 两个原函数本身的设计是好的 (切模式绑 UART / 喂字节), 错的是实现 (空桩). 应保留并实化, 沿用 `luat_mobile_rf_test_*` 前缀扩展.

## Goals

1. 实化原 `luat_mobile_rf_test_mode` / `luat_mobile_rf_test_input` 空桩
2. 新增 4 个 C 函数: `param` (状态存取) / `imei_get` / `imei_set` / `set_rx_cb`
3. 新增 Lua 模块 `lua/luat/rfa.lua`, 完整接管 AT 协议 (12+ 条)
4. PC 端保留"协议回环模拟器" 让 Lua 端可独立运行单测
5. 删旧 `mobile.nst*` (2 个) 和 `mobile.rfcal*` (7 个) Lua 绑定
6. 删旧 `lua/luat/rfcal_at_server.lua` / `testcase/utest/drv/mobile_rfcal_basic/` / `tools/rfcal_com0com/`

## Non-goals

1. 不实现真机 PLAT 层的功能对接 (luatos-soc-2024 单独 PR)
2. 不重写 `npiGetProcessStatusItemValue` 等 PLAT 内部接口
3. 不动 `soc_mobile_rf_test_input` 的 PLAT 内部实现
4. 不重写 `mobile.status` / `mobile.getCellInfo` 等其他 mobile.* API

## Chosen approach

**Thin C / Fat Lua** 架构:
- C 端只做"打开/收字节/存状态"三类原语
- Lua 端是协议的唯一拥有者
- PC 仿真 = 真实 UART TX/RX 被重定向到内存缓冲
- 真机 = 真实 UART TX/RX 由 BSP 驱动, C 端只做"过路"

## Architecture

### 1. C 端 (沿用 `luat_mobile_rf_test_*` 前缀)

5 个新接口声明在 `components/mobile/luat_mobile.h`:

```c
void   luat_mobile_rf_test_mode(uint8_t uart_id, uint8_t on_off);
void   luat_mobile_rf_test_input(char *data, uint32_t data_len);
int    luat_mobile_rf_test_param(const char *key, int *value, int is_set);
int    luat_mobile_rf_test_imei_get(char *out, uint32_t len);
int    luat_mobile_rf_test_imei_set(const char *imei);
int    luat_mobile_rf_test_set_rx_cb(const luat_mobile_rf_test_rx_cb_t *cb);

/* 5 个 key 字符串 (PC 仿真全部有效; 真机支持 NPI 三键 + state + save) */
#define LUAT_MOBILE_RF_TEST_KEY_NPI_CALI   "rfCaliDone"
#define LUAT_MOBILE_RF_TEST_KEY_NPI_NST    "rfNSTDone"
#define LUAT_MOBILE_RF_TEST_KEY_NPI_CT     "rfCTDone"
#define LUAT_MOBILE_RF_TEST_KEY_STATE      "state"
#define LUAT_MOBILE_RF_TEST_KEY_ERF_MODE   "erfMode"
/* 真机批量写入: 设置若干 NPI 位后, key="save" 触发一次 flash 落盘 */

/* Rx 回调 */
typedef struct {
    void (*on_rx)(const uint8_t *data, uint32_t len, void *ud);
    void *userdata;
} luat_mobile_rf_test_rx_cb_t;
```

**约束**: C 端 **不**解析 AT 字符串 / **不**维护状态机 / **不**生成响应.

### 2. PC 端协议回环模拟器 (`bsp/pc/port/luat_mobile_pc.c`)

```c
/* 顶部 s_rf_test 静态结构 */
static struct {
    int      state, npi_rfCaliDone, npi_rfNSTDone, npi_rfCTDone;
    char     imei[16];
    int      erf_mode;
    uint8_t  uart_id;
    luat_mobile_rf_test_rx_cb_t cb;
} s_rf_test = { .state = 0, .imei = "864317081553409" };

/* 5 个新函数实现 (末尾) */
int luat_mobile_rf_test_set_rx_cb(...);
int luat_mobile_rf_test_param(...);    /* 状态存取 */
int luat_mobile_rf_test_imei_get(...);
int luat_mobile_rf_test_imei_set(...);
```

**实化原函数**:
```c
void luat_mobile_rf_test_mode(uint8_t uart_id, uint8_t on_off) {
    s_rf_test.uart_id = on_off ? uart_id : 0xff;
    LLOGD("rf_test: %s mode", on_off ? "enter" : "exit");
}
void luat_mobile_rf_test_input(char *data, uint32_t data_len) {
    if (data && data_len && s_rf_test.cb.on_rx) {
        s_rf_test.cb.on_rx((const uint8_t*)data, data_len, s_rf_test.cb.userdata);
    } else if (s_rf_test.cb.on_rx) {
        s_rf_test.cb.on_rx(NULL, 0, s_rf_test.cb.userdata);  /* flush */
    }
}
```

### 3. Lua 端 `rfa.*` API (`lua/luat/rfa.lua`)

```lua
local M = { _VERSION = "2.0.0" }
M.STATE = { IDLE=0, PREP=1, CALIB=2, SELF_CAL=3, WRITE_NV=4, NST_TEST=5, DONE=6 }

-- 状态机
function M.state()      return mobile.rfTestParam("state", 0, nil) end
function M.setState(s)  return mobile.rfTestParam("state", s, true) end
function M.reset()      ... end
function M.npiGet(k)    return mobile.rfTestParam(k, 0, nil) end
function M.npiSet(k, v) return mobile.rfTestParam(k, v and 1 or 0, true) end
function M.imei()       return mobile.rfTestImei() end
function M.setImei(s)   return mobile.rfTestImeiSet(s) == 0 end

-- 派发 (纯函数, 便于单测)
function M.dispatch(line)
    -- 1) 私有协议 AT+ECRFNST=<hex>
    -- 2) 扩展表 (rfa.register)
    -- 3) 内建表
end

-- UART 集成
function M.start(id, baud)  -- 内部 uart.on + mobile.rfTestMode(id, true)
function M.stop()           -- mobile.rfTestMode(uart_id_, false)
```

**关键 bug fix**: `param_get` 用 `nil` 而非整数 `0` 当第三参; `rfa.start/stop` 用 `true`/`false` 而非 `1`/`0`. `lua_toboolean(L, n)` 在整数 0 上返 1 (Lua 视 0 为 truthy), 会被当写模式 / 进入模式。

### 4. 状态机推进规则 (只升不降)

| 阶段 | 触发 | 副作用 |
|------|------|--------|
| IDLE | 初始 / `reset()` | `setState(0)` |
| PREP | `AT+CGSN=1` | `setState(max(s, 1))` |
| CALIB | `AT+ECRFNST=…` 任意 cmdId | `setState(max(s, 2))` |
| SELF_CAL | cmdId 0x0D/0x0A | `setState(3)` |
| WRITE_NV | `AT+ECNPICFG=rfCaliDone,1` | `setState(4)` |
| NST_TEST | cmdId 0x51~0x5A | `setState(5)` |
| DONE | `AT+ECNPICFG=rfNSTDone,1` | `setState(6)` |

### 5. AT 派发表 (12 条)

详见 README_rfa.md, 覆盖: `AT` / `ATE0` / `AT+CGSN=1` / `AT+ECNPICFG={k},{0,1}` / `AT+ECNPICFG?` / `AT+CFUN=0` / `AT+CPIN?` / `AT+ECCHIPVER?` / `AT+ECGMDATA?` / `AT+ECRFNST=<hex>`.

## Failure modes and signals

| 失败场景 | 哪里捕获 | 用户信号 |
|---|---|---|
| Lua 端解析失败 (line 格式错) | `rfa.dispatch` 返 nil + log.error | 测试 fail |
| C 端 in_buffer 溢出 | `luat_mobile_rf_test_input` 丢弃 + LLOGD warn | log |
| 状态机非法转移 | `rfa.dispatch` 拒绝 + log.error | 测试 fail |
| 私有协议 CRC 错误 | `rfa._handle_rfnst` 返 ERROR | 测试 fail |
| 业务调 `mobile.rfTestParam` 3rd arg 传整数 0 | lua_toboolean 视为写 | 业务代码会"误改"状态, 文档强调用 `nil`/`true`/`false` |

## Verification

### 单元测试 (`testcase/utest/drv/mobile_rfa_basic/`, 13 case)

- c_suite (5): NPI/State/IMEI/Mode/Input C 桩基本行为
- lua_suite (6): 5 个新绑定注册 + nst_* 已删除反向验证
- at_suite (11): 派发表覆盖, 12 条 AT 命令
- rfa_suite (13): state / IMEI / RFNST / 错误注入 / 动态 register

### 集成测试 (com0com)

`tools/rfa_com0com/test_rfa_com0com.py`:
- basic suite: 8 case (AT / CGSN / ECNPICFG / IMEI)
- full suite: 11 case (basic + RFNST + ERROR)

### 编译

- `cd bsp/pc && powershell -Command "& '.\build_windows_32bit_msvc.bat'"` 0 错误 0 警告 (除第三方)

### 回归

- `mobile.status` / `mobile.getCellInfo` / `mobile.imei` 等其他 API 不受影响 (utest 全跑过)

## Critical files

### 修改 (Modify)
- `components/mobile/luat_mobile.h` — 改 836-849 段 (rf_test_*), 删 851-917 段 (rfcal_*), 加 5 个新函数 + key 宏 + rx_cb
- `components/mobile/luat_lib_mobile.c` — 改 1415-1453 (nst_* 改调 rf_test_*), 删 1563-1670 (rfcal_*), 加 5 个新绑定
- `bsp/pc/port/luat_mobile_pc.c` — 改 312-319 (rf_test_* 空桩实化), 删 462-583 (rfcal_*), 加 s_rf_test + 5 个新函数
- `components/mobile/luat_mobile_airlink_rpc.c` — 改 419-427 (rf_test_* 空桩实化), 加 4 个新空桩
- `oldmodule/Air780E/demo/rf_test/main.lua` — 加 deprecation 注释

### 新增 (Create)
- `lua/luat/rfa.lua`
- `testcase/utest/drv/mobile_rfa_basic/{metas.json,scripts/main.lua,scripts/mobile_rfa_test.lua,scripts/rfa.lua}`
- `tools/rfa_com0com/{at_server_main/main.lua,at_server_main/rfa.lua,setup_com0com_pair.ps1,test_rfa_com0com.py}`
- `components/mobile/README_rfa.md`

### 删除 (Delete)
- `lua/luat/rfcal_at_server.lua`
- `testcase/utest/drv/mobile_rfcal_basic/` (整目录)
- `tools/rfcal_com0com/` (整目录)
- `components/mobile/README_rfcal.md`
- `components/utest/mobile/luat_mobile_rfcal_utest.c`

### 外部 (luatos-soc-2024, 单独 PR)
- `luatos-soc-2024/interface/src/luat_mobile_ec7xx.c` — 改 `luat_mobile_rf_test_input` 去掉 toupper, 增 3 个新函数实现
- `luatos-soc-2024/PLAT/…/atcReply` — 内部 toupper 保留 (因为 luat 层不再 toupper)

## 风险

- **R1**: luatos-soc-2024 必须双仓齐发 (主仓 header 改 + 真机实现). 阶段 4 留 stub PR, 主仓合并后切真实现.
- **R2**: toupper 语义迁移 (luat 层 → PLAT 层). 新设计 Lua 端可能喂小写 hex (如 `0a`), 不能粗暴 toupper.
- **R3**: 旧 demo `oldmodule/Air780E/demo/rf_test/main.lua` 用 `mobile.nst*`, 已加 deprecation 注释.
- **R4**: PC 仿真器 `s_rf_test` 是 static, 跨 utest case 复用, 不调 `rfa.reset()` 就会泄漏. 已在 utest 入口统一调 `_reset_for_test`.
- **R5**: 私有协议响应模板由 Lua 端维护, 模板不全时返默认 `MT<cmdId>00000001000000000000`. 阶段 2 跟产线对齐 cmdId 列表.
- **R6**: `mobile.rfTestParam` 第 3 arg 用法陷阱 — 文档/README 必须显式强调用 `nil`/`true`/`false`, 不能用整数 0/1.
