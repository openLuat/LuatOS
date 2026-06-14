# LuatOS RF 校准仿真接口

> **For agentic workers / 维护者:** 这份文档说明 PC 模拟器侧 RF 校准仿真接口的设计、状态机、测试,以及如何把 PC 桩迁移到真机固件(luatos-soc-2024)。

## 1. 概览

合宙 EC718 模组的 RF 校准工具通过 UART 发送 AT 命令进行射频校准和 NST 非信令测试。本模块让 PC 模拟器能够完整仿真该会话:

- **7 个 C 接口函数** (`luat_mobile_rfcal_*`) 在 `components/mobile/luat_mobile.h` 声明
- **7 个 Lua 绑定** (`mobile.rfcal*`) 在 `components/mobile/luat_lib_mobile.c`
- **PC 桩实现** 在 `bsp/pc/port/luat_mobile_pc.c` 用真实日志数据驱动
- **Lua AT server** `lua/luat/rfcal_at_server.lua` 挂接 UART 回环
- **utest 套件** `testcase/utest/drv/mobile_rfcal_basic/` 23 个 case
- **com0com 端到端** `tools/rfcal_com0com/` pyserial 回归

所有代码用 `LUAT_USE_MOBILE_RFCAL` 宏隔离,默认在 PC 构建中开启;真机固件只需提供同名 C 函数即可对接,无需改 Lua 绑定层。

## 2. C API 表面

声明在 `components/mobile/luat_mobile.h`,全部用 `#ifdef LUAT_USE_MOBILE_RFCAL` 包裹。

```c
/* NPI NV 位域操作 */
int  luat_mobile_rfcal_npi_get(const char *key, int *value);
int  luat_mobile_rfcal_npi_set(const char *key, int value);

/* 校准状态机 */
int  luat_mobile_rfcal_get_state(void);
int  luat_mobile_rfcal_reset(void);

/* AT 字符串派发 */
int  luat_mobile_rfcal_at_dispatch(const char *line, char *resp, uint32_t resp_len);

/* RFNST 私有协议 */
int  luat_mobile_rfcal_rfnst(const char *in_hex, char *out_hex, uint32_t out_hex_len);

/* 测试 IMEI 注入 */
int  luat_mobile_rfcal_set_imei(const char *imei);
```

### 2.1 真机对接指南(luatos-soc-2024)

这些签名与 `luatos-soc-2024/interface/src/luat_mobile_ec7xx.c` 现有 `luat_mobile_*` 命名风格一致。真机 PR 模板:

```c
// 在 luatos-soc-2024/interface/src/luat_mobile_ec7xx.c 末尾追加
#include "npi_config.h"   // NPIProcessStatus 定义
#include "RfDriver.h"     // RfAtNstCmdPreHandle

static NPIProcessStatus s_npi_status = {0};
static uint8_t s_rfcal_state = 0;

int luat_mobile_rfcal_npi_get(const char *key, int *value) {
    if (!key || !value) return -1;
    if      (strcmp(key, "rfCaliDone") == 0) *value = s_npi_status.rfCaliDone;
    else if (strcmp(key, "rfNSTDone")  == 0) *value = s_npi_status.rfNSTDone;
    else if (strcmp(key, "rfCTDone")   == 0) *value = s_npi_status.rfCTDone;
    else return -1;
    return 0;
}

int luat_mobile_rfcal_npi_set(const char *key, int value) {
    // 写入 AP NV,触发 NPIProcessStatus 持久化
    if (!key) return -1;
    int v = value ? 1 : 0;
    if      (strcmp(key, "rfCaliDone") == 0) s_npi_status.rfCaliDone = v;
    else if (strcmp(key, "rfNSTDone")  == 0) s_npi_status.rfNSTDone  = v;
    else if (strcmp(key, "rfCTDone")   == 0) s_npi_status.rfCTDone   = v;
    else return -1;
    // TODO: 持久化到 NV
    return 0;
}

int luat_mobile_rfcal_at_dispatch(const char *line, char *resp, uint32_t resp_len) {
    // 真机走标准 AT 任务 (atcReply),不要在 luat 层实现
    return -1;  // 占位,真机无需此函数
}

int luat_mobile_rfcal_rfnst(const char *in_hex, char *out_hex, uint32_t out_hex_len) {
    // 真机走 soc_mobile_rf_test_input,不要在 luat 层实现
    return -1;  // 占位,真机无需此函数
}

int luat_mobile_rfcal_set_imei(const char *imei) { return 0; }  // 真机用 NVRAM
int luat_mobile_rfcal_get_state(void) { return s_rfcal_state; }
int luat_mobile_rfcal_reset(void) {
    s_rfcal_state = 0;
    memset(&s_npi_status, 0, sizeof(s_npi_status));
    return 0;
}
```

**关键点:**
- 真机只需实现 `npi_get / npi_set / get_state / reset / set_imei` 5 个
- `at_dispatch / rfnst` 在真机由 `soc_mobile_rf_test_*` 已有的路径处理,不需要在 `luat_mobile_ec7xx.c` 实现(放空 stub 即可,Lua 层的 `mobile.rfcalAt / Rfnst` 在真机上不会被使用)
- 共享头文件 `components/mobile/luat_mobile.h` 是 LuatOS 主仓和 `luatos-soc-2024` 仓库的契约,需保持同步

## 3. Lua 绑定

注册在 `mobile.rfcal*`,全部用 `#ifdef LUAT_USE_MOBILE_RFCAL` 包裹:

```lua
mobile.rfcalNpiGet(key)         -- 0/1/nil
mobile.rfcalNpiSet(key, val)   -- 0 或 -1
mobile.rfcalState()            -- 0..6
mobile.rfcalReset()            -- 0
mobile.rfcalAt(line)           -- 响应 string,nil 表示未识别
mobile.rfcalRfnst(hex)         -- MT 响应 hex string
mobile.rfcalSetImei(imei)      -- 0 或 -1(长度检查)
```

## 4. 状态机

7 个阶段,AT 命令推进:

| 值 | 阶段 | 触发 |
|----|------|------|
| 0 | IDLE | 初始 / `mobile.rfcalReset()` |
| 1 | PREP | `AT+CGSN=1` 读取 IMEI |
| 2 | CALIB | `AT+ECRFNST=...` 任何 cmdId(主校准数据下发) |
| 3 | SELF_CAL | cmdId 0x0D / 0x0A 自校准(暂未细分,见下文) |
| 4 | WRITE_NV | `AT+ECNPICFG=rfCaliDone,1` 写 NV 标志 |
| 5 | NST_TEST | 0x51~0x5A 频段 NST 测试(暂未细分) |
| 6 | DONE | `AT+ECNPICFG=rfNSTDone,1` 全部完成 |

**当前实现:** PC 桩简化,只区分 IDLE / PREP / CALIB / WRITE_NV / DONE,SELF_CAL 和 NST_TEST 阶段共用 PREP/CALIB 路径,需要更细粒度时再扩展。

## 5. 真实日志 fixture

来自 `F:\hardware\calrf\864317081553409_UartComm_Log_Port14.txt`:

| 项目 | 值 |
|------|------|
| IMEI | `864317081553409` |
| 时间戳 | `2026-06-12-15-17` |
| DAC 校准值 | `46EC46EC46EC46EC46EC46EC46EC46EC` |
| 频段 | B1(0xCF4E) / B3(0x4344) / B5(0x4C4C) / B7(0x384A) / B8(0x8520) / B28(0xCC5B) / B40(0x4A65) |

## 6. Lua AT server 用法

```lua
local rfa = require "rfcal_at_server"
rfa.start(uart.VUART_1, 115200)  -- 挂接 UART receive 回调

-- 单独使用 dispatch / feed(便于单测)
rfa._reset_for_test()
local resp = rfa.dispatch("AT+CGSN=1")
-- resp = "\r\n+CGSN: \"864317081553409\"\r\n\r\nOK\r\n"

local lines = rfa.feed("AT\r\nATE0\r\nAT+CGSN=1\r\n")
-- lines = { "AT", "ATE0", "AT+CGSN=1" }
```

## 7. 构建与测试

### 7.1 编译(PC)

```bash
cd bsp/pc
export LUAT_USE_UTEST=y
cmd /c build_windows_32bit_msvc.bat
# 产物: bsp/pc/build/out/luatos-lua.exe
```

### 7.2 跑 utest

```bash
cd bsp/pc/build/out
./luatos-lua.exe ../../../../testcase/common/scripts/ \
                ../../../../testcase/utest/drv/mobile_rfcal_basic/scripts/
# 预期: ### OVERALL_PASS ###, 退出码 0
# 23 个 case: c_suite(6) + lua_suite(5) + at_suite(3) + rfa_suite(9)
```

### 7.3 com0com 端到端

```bash
# 1. 配对(管理员 PowerShell)
pwsh tools/rfcal_com0com/setup_com0com_pair.ps1

# 2. 启动 LuatOS AT server
cd bsp/pc/build/out
./luatos-lua.exe ../../../../testcase/common/scripts/ \
                ../../../../tools/rfcal_com0com/at_server_main/

# 3. 跑 Python 回归
cd <repo>
python tools/rfcal_com0com/test_rfcal_com0com.py --port COM5 --suite basic
# 预期: 8/8 PASS
python tools/rfcal_com0com/test_rfcal_com0com.py --port COM5 --suite full
# 预期: 11/11 PASS(含 RFNST + ERROR 路径)
```

## 8. 已知的限制与未来工作

| 限制 | 影响 | 建议 |
|------|------|------|
| 状态机 5 (NST_TEST) 未细分 | cmdId 0x51~0x5A 都进 PREP/CALIB | 后续按真实日志补 NST 子状态机 |
| RFNST 响应简化 | 所有 cmdId 返固定 MT 模板 | 后续按 cmdId 拆分 (0x0D AFC, 0x04 AGC1, 0x08 APC 等) |
| 大包响应未生成 | 4096+3912 字节扫频数据未模拟 | 后续按 cmdId 0x0E/0x20 模板 |
| AT 解析不识别 `AT\r` 后跟额外字符 | 严格按 \r\n 切分 | 真实工具用 \r\n,已足够 |

## 9. 参考资料

- 真实校准日志: `F:\hardware\calrf\864317081553409_UartComm_Log_Port14.txt`
- 合宙 AT 手册: `F:\hardware\calrf\EiGENCOMM EC CAT1 AT Command Manual V1.2.pdf`
- 真机 SDK 头: `D:\github\luatos-soc-2024\PLAT\driver\hal\ec7xx\ap\inc\hal_rfCali.h`
- 真机 NPI 配置: `D:\github\luatos-soc-2024\PLAT\middleware\develope\common\inc\npi_config.h`
- 设计文档: `docs/superpowers/plans/2026-06-12-uart-utest-design.md` (参考)
- 本计划: `C:\Users\wendal\.claude\plans\prancy-noodling-whistle.md`
