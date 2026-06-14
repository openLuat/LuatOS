# mobile RF 校准 rfa 重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans
>
> **Status**: ✅ 已完成 5 阶段 6 commit (2026-06-13, branch: `mobile-rf-test-rewrite`)

**Goal:** 把 `mobile` 库的 RF 校准功能从 C 端硬编码改为 Thin C / Fat Lua 架构, 沿用 `luat_mobile_rf_test_*` 前缀扩展
**Architecture:** Thin C (5 函数) / Fat Lua (新模块 `rfa.*`)
**Tech Stack:** C (luat_mobile_*) + Lua 5.3 + xmake + MSVC

**Worktree:** `D:\github\LuatOS\.worktrees\mobile-rf-test-rewrite` (branch `mobile-rf-test-rewrite`)

---

## File Structure

### New (Create)
- `script/libs/rfa.lua` — Lua 端 rfa.* 模块
- `testcase/utest/drv/mobile_rfa_basic/metas.json`
- `testcase/utest/drv/mobile_rfa_basic/scripts/main.lua`
- `testcase/utest/drv/mobile_rfa_basic/scripts/mobile_rfa_test.lua` — 13 case
- `tools/rfa_com0com/at_server_main/main.lua`
- `tools/rfa_com0com/setup_com0com_pair.ps1`
- `tools/rfa_com0com/test_rfa_com0com.py`
- `components/mobile/README_rfa.md`
- `docs/superpowers/specs/2026-06-13-mobile-rf-test-redesign-design.md`
- `docs/superpowers/plans/2026-06-13-mobile-rf-test-redesign.md` (本文件)

### Modify
- `components/mobile/luat_mobile.h` — 改 rf_test_*, 删 rfcal_*, 加 3 个新函数
- `components/mobile/luat_lib_mobile.c` — 改 nst_*, 删 rfcal_*, 加 5 个新绑定
- `bsp/pc/port/luat_mobile_pc.c` — 改 rf_test_*, 删 rfcal_*, 加 s_rf_test + 3 个新函数
- `components/mobile/luat_mobile_airlink_rpc.c` — 改 rf_test_*, 加 4 个新空桩
- `oldmodule/Air780E/demo/rf_test/main.lua` — 加 deprecation 注释

### Delete
- `lua/luat/rfcal_at_server.lua`
- `testcase/utest/drv/mobile_rfcal_basic/` (整目录)
- `tools/rfcal_com0com/` (整目录)
- `components/mobile/README_rfcal.md`
- `components/utest/mobile/luat_mobile_rfcal_utest.c`

---

## Task 1: 实化原有 rf_test_* + 新增 5 个新函数 (不删旧的) ✅

**Files:** `luat_mobile.h`, `luat_mobile_pc.c`, `luat_mobile_airlink_rpc.c`, `luat_lib_mobile.c`

**Commit:** `refactor(mobile): realize luat_mobile_rf_test_mode/input; add param/imei/set_rx_cb`

- [x] **Step 1:** `components/mobile/luat_mobile.h` 末尾追加 5 个新函数声明 + key 宏 + rx_cb 结构
- [x] **Step 2:** `bsp/pc/port/luat_mobile_pc.c` 顶部加 `s_rf_test` 静态结构
- [x] **Step 3:** `luat_mobile_pc.c` 312-319 行替换空桩为实化实现 (调 s_rf_test)
- [x] **Step 4:** `luat_mobile_pc.c` 末尾加 4 个新函数 (set_rx_cb / param / imei_get / imei_set)
- [x] **Step 5:** `luat_mobile_airlink_rpc.c` 419-427 改空桩, 加 4 个新空桩 (返 -1)
- [x] **Step 6:** `luat_lib_mobile.c` 加 5 个新绑定 (rfTestMode/Input/Param/Imei/ImeiSet) 并注册到 reg_mobile
- [x] **Step 7:** 编译 `cd bsp/pc && powershell -Command "& '.\build_windows_32bit_msvc.bat'"`
- [x] **Step 8:** 烟雾测试 `mobile_rf_test_smoke` 14/14 全过

## Task 2: 新增 script/libs/rfa.lua + 新 utest 套件 ✅

**Files:** `script/libs/rfa.lua`, `testcase/utest/drv/mobile_rfa_basic/`

**Commit:** `feat(lua): add script/libs/rfa.lua state machine + dispatch`

- [x] **Step 1:** 新建 `script/libs/rfa.lua` (~200 行, 状态机 7 阶段 + 派发表 + 扩展点)
- [x] **Step 2:** 新建 `testcase/utest/drv/mobile_rfa_basic/metas.json`
- [x] **Step 3:** 新建 `testcase/utest/drv/mobile_rfa_basic/scripts/main.lua`
- [x] **Step 4:** 新建 `testcase/utest/drv/mobile_rfa_basic/scripts/mobile_rfa_test.lua` (4 套件, 13 case)
- [x] **Step 5:** 跑测试 `./luatos-lua.exe ../../../../testcase/common/scripts/ ../../../../testcase/utest/drv/mobile_rfa_basic/scripts/ ../../../../script/libs/`
- [x] **Step 7:** 验证 `### OVERALL_PASS ### mobile_rfa_basic`

## Task 3: 迁移 com0com 工具 (双轨运行期) ✅

**Files:** `tools/rfa_com0com/` (新), `tools/rfcal_com0com/` (保留到阶段 4)

**Commit:** `feat(com0com): migrate rfcal_com0com → rfa_com0com (双轨运行期)`

- [x] **Step 1:** `mkdir -p tools/rfa_com0com/at_server_main`
- [x] **Step 2:** 复制 `setup_com0com_pair.ps1` 到 `tools/rfa_com0com/`
- [x] **Step 3:** 新建 `tools/rfa_com0com/at_server_main/main.lua` (改用 rfa, 内部 mobile.rfTest* 桥, 通过 script/libs 加载)
- [x] **Step 4:** 新建 `tools/rfa_com0com/test_rfa_com0com.py` (复制 + 改名 + 注释更新)
- [x] **Step 5:** 验证 `tools/rfcal_com0com/` 仍存在 (双轨)

## Task 4: 删旧代码 (rfcal_* + nst_* + 旧 utest/demos) ✅

**Files:** 多文件删除

**Commit:** `refactor(mobile): remove old luat_mobile_rfcal_* and nst_*`

- [x] **Step 1:** `luat_mobile.h` 删 851-917 整段 (rfcal_* 7 个声明)
- [x] **Step 2:** `luat_mobile_pc.c` 删 493-615 整段 (rfcal_* PC 仿真实现)
- [x] **Step 3:** `luat_lib_mobile.c` 删 nst_* + rfcal_* + l_mobile_utest 块, reg_mobile 表对应项
- [x] **Step 4:** 新建 `components/mobile/README_rfa.md` (替代 README_rfcal.md)
- [x] **Step 5:** 删 `lua/luat/rfcal_at_server.lua`
- [x] **Step 6:** 删 `components/mobile/README_rfcal.md`
- [x] **Step 7:** 删 `components/utest/mobile/luat_mobile_rfcal_utest.c`
- [x] **Step 8:** 删 `testcase/utest/drv/mobile_rfcal_basic/` (整目录)
- [x] **Step 9:** 删 `tools/rfcal_com0com/` (整目录)
- [x] **Step 10:** `oldmodule/Air780E/demo/rf_test/main.lua` 加 deprecation 注释
- [x] **Step 11:** `testcase/utest/drv/mobile_rfa_basic/scripts/mobile_rfa_test.lua` 改 nst_aliases 为反向验证
- [x] **Step 12:** 编译 + 全测试, 验证 13/13 OVERALL_PASS

## Task 5: 写 spec/plan 落档 ✅

**Files:** `docs/superpowers/specs/...`, `docs/superpowers/plans/...`

**Commit:** `docs(mobile): spec + plan for rfa redesign`

- [x] **Step 1:** 新建 `docs/superpowers/specs/2026-06-13-mobile-rf-test-redesign-design.md`
- [x] **Step 2:** 新建 `docs/superpowers/plans/2026-06-13-mobile-rf-test-redesign.md` (本文件)
- [x] **Step 3:** 最终 commit

---

## Self-Review

### Spec coverage 检查表
- [x] Context 解释两个根本性错误
- [x] Goals 6 项明确
- [x] Non-goals 4 项边界
- [x] Chosen approach (Thin C / Fat Lua)
- [x] Architecture 5 段 (C 接口 / PC 仿真 / Lua API / 状态机 / AT 派发)
- [x] Failure modes 6 项
- [x] Verification 4 段
- [x] Critical files 完整列表 (Modify/Create/Delete)
- [x] 风险点 6 项

### Placeholder scan
- [x] 无 TBD / TODO
- [x] 无空章节
- [x] 无歧义需求

### Type consistency
- [x] 5 个 C 函数签名一致 (mode/input void, 其他 int)
- [x] 13 个 utest case 一致引用 mobile.rfTest*
- [x] README 表格/代码一致

### 验证
- [x] 13/13 utest OVERALL_PASS
- [x] 编译 0 错误 0 警告 (除 C4090 第三方)
- [x] smoke test 14/14 (阶段 1, 阶段 4 后已删)
- [x] com0com 文件双轨存在 (阶段 3 后, 阶段 4 已删旧)

### 落地
- [x] spec 落到 `docs/superpowers/specs/2026-06-13-mobile-rf-test-redesign-design.md`
- [x] plan 落到 `docs/superpowers/plans/2026-06-13-mobile-rf-test-redesign.md`
- [x] 5 个 commit 都在 `mobile-rf-test-rewrite` 分支
- [x] 主仓 `master` 不动

---

## Commit 历史 (已落)

```
1. refactor(mobile): realize luat_mobile_rf_test_mode/input; add param/imei/set_rx_cb
2. feat(lua): add script/libs/rfa.lua state machine + dispatch
3. feat(com0com): migrate rfcal_com0com → rfa_com0com (双轨运行期)
4. refactor(mobile): remove old luat_mobile_rfcal_* and nst_*
5. docs(mobile): spec + plan for rfa redesign
```

---

## 后续工作 (out of scope)

1. luatos-soc-2024 单独 PR — 实现真机端 5 个新 `luat_rfa_*` 函数 + 迁移 toupper 到 PLAT 层
2. 真机端 com0com 回归 (EC718 模组) — 验证 Lua rfa 在真机 UART 上行为一致
3. 产线工具对齐 — `AT+ECRFNST` 私有协议 cmdId 模板按需 `rfa.registerRfnst` 扩展
