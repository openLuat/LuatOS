# LuatOS Test Framework

**Scope**: `testcase/` - Test suites and testing infrastructure.

## OVERVIEW

Automated testing framework for LuatOS with PC simulator and hardware test support.

## STRUCTURE

```
testcase/
├── common/scripts/   # Test framework
│   ├── testrunner.lua
│   ├── testsuite.lua
│   └── testreport.lua
├── utest/            # C-layer utest suites (xxx.utest(case) bridges)
│   ├── net/          #   tcp_basic, http_basic, https_basic, dtls_basic, socket_udp_limit_basic
│   ├── lib/          #   core_basic, crypto_basic
│   ├── sys/          #   ndk_basic
│   ├── fs/           #   pgfs_basic
│   └── drv/          #   uart_basic, mobile_rfa_basic
├── unit/             # Lua unit tests, grouped by functional domain
│   ├── driver/       #   adc, uart, spi, i2c, webp
│   ├── fs/           #   fs, ramfs, lf_fs_matrix, pgfs_*
│   ├── crypto/       #   crypto, gmssl, rsa, xxtea
│   ├── net/          #   canself, sntp, netdrv_*
│   ├── io/
│   ├── json/
│   ├── system/       #   bit64, core_check, mcu, os, zbuff
│   ├── middleware/   #   libgnss, protobuf, sqlite3
│   ├── media/        #   audio_*, hzfont
│   ├── perf/         #   fastlz, fft, miniz, pack, perf_basic
│   └── tools/        #   mreport, pcconf
├── func/             # Functional / integration / scenario tests
│   ├── network/      #   TCP, UDP, http, mqtt, websocket, ...
│   ├── airlink/
│   ├── appstore/
│   └── eink/
├── platform/         # Platform/chip-specific tests
│   └── air1601/
│       ├── ndk_helloworld/
│       └── pgfs_regression/
├── ndk/              # NDK common regression suites
│   ├── ndk_basic/
│   ├── ndk_hostabi_basic/
│   └── ndk_perf_guest/
└── tools/            # Standalone tooling / analysis tests
    └── memprof/
```

C-layer utest 套件统一住在 `testcase/utest/<group>/<suite>_basic/`,共享 `pc_utest_coverage.ps1 -Suite <suite>` 入口(详见 `testcase/README.md` 的"C层 utest"一节)。普通 Lua 单元测试按 `testcase/unit/<domain>/<feature>/` 摆放,功能/集成测试按 `testcase/func/<domain>/<feature>/` 摆放,平台专属测试按 `testcase/platform/<chip>/<feature>/` 摆放。

## RUNNING TESTS

```bash
# PC Simulator
build/out/luatos-lua.exe \
    ../../testcase/common/scripts/ \
    ../../testcase/<feature>/<feature>_basic/scripts/
```

### Running on Real Hardware

真机走 `luatos-cli flash test`,**完整流程、模组矩阵、关键字契约、故障树详见 `/luatos-hw-test` skill**。本节只记 testcase 这边必须遵守的约定:

- 终态契约:`### OVERALL_PASS ###` / `### OVERALL_FAIL ###` 由 `testrunner.runBatch` 通过 `log.info` 发出,是 luatos-cli 判定 PASS/FAIL 的唯一锚点。**不要在测试里直接 print 这两个字符串绕过 testrunner**。
- 真机 testcase 的 `main.lua` 必须有 WDT 喂狗任务,否则长用例(>10 秒)会被看门狗重启:
  ```lua
  if wdt and wdt.init then
      wdt.init(9000)
      sys.taskInit(function() while true do sys.wait(1000); if wdt.feed then wdt.feed() end end end)
  end
  ```
- `metas.json` 的 `platform` 字段当前没有任何 runner 消费,只是文档;但请按实际填(`["pc"]` / `["air1601"]` / `["air1601","air8000"]`),给人读。
- ⚠️ **testrunner 的"虚绿"陷阱**:`testsuite.lua` 用 `pcall` 包测试函数,**返回 `false` 不算 FAIL**,只有抛 lua 错误才算。要让失败可见,用 `assert(ok, "...")`,不要 `if not ok then return false`。

### RF 校准套件 (mobile_rfa_basic)

PC 模拟器侧的 RF 校准仿真测试,4 个 suite 共 13 个 case:

| Suite | 数量 | 覆盖 |
|-------|------|------|
| `c_suite` | 5 | `mobile.rfTestParam` NPI/State rw / IMEI 注入 / Mode/Input 不崩 |
| `lua_suite` | 6 | `mobile.rfTest*` 5 个绑定注册 + `mobile.nst*` 已删除反向验证 |
| `at_suite` | 12 | `rfa.dispatch` 内建 AT 派发表 (`AT` / `ATE0` / `AT+CGSN=1` / `AT+ECNPICFG` / `AT+CFUN` / `AT+CPIN?` / `AT+ECCHIPVER?` / `AT+ECGMDATA?` / `AT+ECRFNST`) |
| `rfa_suite` | 13 | `script/libs/rfa.lua` 状态机 / reset / IMEI / RFNST 模板 / 错误注入 / 扩展注册 / 行切分 |

跑法 (注意需要带上 `script/libs/`, 否则 `require("rfa")` 找不到模块):

```bash
cd bsp/pc/build/out
./luatos-lua.exe ../../../../testcase/common/scripts/ \
                ../../../../testcase/utest/drv/mobile_rfa_basic/scripts/ \
                ../../../../script/libs/
```

**端到端 com0com 回归** (需先 `setup_com0com_pair.ps1` 配对 COM5<->COM6):

```bash
# 终端 1: 启动 LuatOS AT server
cd bsp/pc/build/out
./luatos-lua.exe ../../../../testcase/common/scripts/ \
                ../../../../tools/rfa_com0com/at_server_main/ \
                ../../../../script/libs/

# 终端 2: Python 驱动
python tools/rfa_com0com/test_rfa_com0com.py --port COM5 --suite basic
```

详细 API、状态机说明、真机对接指南见 `components/mobile/README_rfa.md`。

## CREATING TESTS

1. Create directory: `testcase/<feature>/<feature>_basic/scripts/`
2. Add `metas.json` with test metadata
3. Add `main.lua` with test runner setup
4. Add `<feature>_test.lua` with test functions

**Test Function Pattern:**
```lua
function mytest.test_something()
    log.info("test", "Starting test")
    local result = function_under_test()
    assert(result == expected, "Test failed")
    log.info("test", "Test passed")
end
```

## CONVENTIONS

- Test functions MUST start with `test_`
- Tests should be independent
- Use `assert()` for validations
- Use `log.info()` for output

### Testcase File Style (Recommended)

- Follow the same structure used by `unit/perf/fastlz`:
    - `scripts/main.lua`: only does runner wiring (`PROJECT/VERSION`, `testrunner`, `runBatch`, `sys.run()`)
    - `scripts/<feature>_test.lua`: contains actual `test_` functions and assertions
- Avoid putting full test logic directly in `main.lua`.

### Media Fixture Convention (PC)

- For media testcase in PC simulator, place fixture files (e.g. mp3) in the same directory as `scripts/main.lua`.
- Load fixtures via `/luadb/<filename>` path in tests.
- Example: put `test_16k.mp3` under `scripts/`, and access it by `/luadb/test_16k.mp3`.

## ANTI-PATTERNS

- ❌ Do NOT depend on test execution order
- ❌ Do NOT leave test resources uncleaned
- ❌ Do NOT hardcode hardware-specific values

## NETWORK TEST PATTERN (PC Simulator)

For TCP server tests that require async callbacks, use **state polling** instead of relying on callbacks:

```lua
local function wait_state(netc, target, timeout)
    local deadline = socket.getStatistics(netc) -- use time-based deadline
    while true do
        local state = cycbuff.read(netc, 0x20000000, 0)  -- read socket state
        if state == target then return true end
        sys.wait(100)
        -- timeout check
    end
end
```

This is more reliable than callback-based testing because the 2-hop async chain (network adapter → framework → Lua) may not deliver callbacks during `sys.wait()` polling.

**Example**: See `testcase/func/network/tcp_server/tcp_server_basic/` for a complete TCP server test with state polling + PING/PONG validation.
