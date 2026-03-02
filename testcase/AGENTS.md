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

## ANTI-PATTERNS

- ❌ Do NOT depend on test execution order
- ❌ Do NOT leave test resources uncleaned
- ❌ Do NOT hardcode hardware-specific values
