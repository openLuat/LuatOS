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
└── <feature>/        # Feature tests
    └── <feature>_basic/
        ├── metas.json
        └── scripts/
            ├── main.lua
            └── <feature>_test.lua
```

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

- Follow the same structure used by `unit_testcase_tools/fastlz`:
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

**Example**: See `testcase/function_testcase_network/tcp_server/tcp_server_basic/` for a complete TCP server test with state polling + PING/PONG validation.
