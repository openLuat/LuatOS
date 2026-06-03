# LuatOS C-Layer UTest

**Scope**: `components/utest/` - C-layer unit-test implementations exposed as `xxx.utest(case)`.

## OVERVIEW

This directory holds library-specific C test implementations.  
Production library files only keep thin Lua export bridges; real test logic stays here.

## CONVENTIONS

1. **API shape**
   - Each library exports `xxx.utest(case_name)` in its own module table.
   - Bridge symbol pattern: `luat_<lib>_utest(lua_State *L, const char *case_name)`.

2. **Macro isolation**
   - Lua-side export entries in library files must be wrapped by `#ifdef LUAT_USE_UTEST`.
   - `components/utest/*_utest.c` files are isolated by build gating in `bsp/pc/xmake.lua` (`LUAT_USE_UTEST=y`), not by per-file `#ifdef`.

3. **File placement**
   - One library, one or more dedicated files under `components/utest/<lib>/`.
   - Do not embed test bodies into existing production module files.

4. **Test implementation style**
   - Use small, deterministic case handlers.
   - Prefer `luaL_loadstring + lua_pcallk` for snippets that may yield (`sys.wait*`, `http.request(...).wait()`, socket async waits).
   - Plain `lua_pcall` is fine only for purely synchronous snippets.
   - Return Lua boolean for pass/fail; avoid silent success fallbacks.

## BUILD INTEGRATION (PC)

- `bsp/pc/xmake.lua` enables utest only when:
  - env `LUAT_USE_UTEST=y`
  - `add_defines("LUAT_USE_UTEST=1")`
  - `add_files(components/utest/**.c)`

- Windows build (recommended helper script):
  - `bsp\pc\build_windows_32bit_msvc.bat`

## TESTCASE PATTERN

- Place Lua runner cases in:
  - `testcase/unit_testcase_tools/<suite>/scripts/`
- Typical launch:
  - `build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\<suite>\scripts\`
- PC scripts should still obey normal testcase framework rules (including explicit exit behavior when not handled by testrunner).

## COVERAGE (OpenCppCoverage)

- Tool script: `bsp\pc\pc_utest_coverage.ps1`
- Typical usage:
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite c_utest_dtls_basic`
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite c_utest_tcp_basic`
- Re-running additional suites after the first build:
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite c_utest_http_basic -SkipBuild`
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite c_utest_https_basic -SkipBuild`
- `-Suite` and `-TestcaseScripts` are mutually exclusive
- Requires installed executable:
  - `C:\Program Files\OpenCppCoverage\OpenCppCoverage.exe`
- The helper trims a trailing `\` from `-TestcaseScripts` automatically and derives `build\coverage\<suite>\`.
- Network-facing suites currently cover:
  - `socket.utest("dtls_loopback_psk")` via `c_utest_dtls_basic`
  - `socket.utest("tcp_external_qq")` via `c_utest_tcp_basic`
  - `http.utest("http_external_qq")` via `c_utest_http_basic`
  - `http.utest("https_external_qq")` via `c_utest_https_basic`

## EXTENDING TO A NEW LIBRARY

1. Add `xxx.utest` bridge under `#ifdef LUAT_USE_UTEST` in the library module file.
2. Add `components/utest/<lib>/luat_<lib>_utest.c` with case dispatch.
3. Add/extend Lua testcase suite to call `xxx.utest("case")`.
4. Run PC suite with `LUAT_USE_UTEST=y`.
5. Run coverage script for report output when needed.
