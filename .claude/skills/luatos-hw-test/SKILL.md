---
name: luatos-hw-test
description: LuatOS 在真机模组上跑测试的完整工作流——build .soc → flash → 抓启动日志 → 关键字判定 PASS/FAIL。覆盖 luatos-cli 全模组族(Air1601/1602/CCM4211、Air8000/EC7xx/Air780E、Air8101/BK7258、Air6208/XT804/Air101/103、Air8101-SF32)。用于"在 air1601 上跑 pgfs"、"刷机调试"、"真机回归测试"、"flash air8000"等场景。
---

# luatos-hw-test — LuatOS 真机测试工作流

本 skill 把"在 LuatOS 真机模组上跑一个 testcase"这件事的所有步骤、契约、坑、故障树串起来,**让人一页读完就能跑**。

## 何时调用

触发短语:"在 airXXXX 上跑 ..."、"刷机"、"flash test"、"真机测试"、"真机回归"、"上 air1601 验证 pgfs"、"luatos-cli flash" 等。如果用户只想在 PC 模拟器上跑测试,见 `bsp/pc/AGENTS.md` 和 `components/utest/AGENTS.md`——本 skill 不覆盖 PC。

---

## 1. 前置工具

| 工具 | 默认安装位置 | 用途 |
|---|---|---|
| `luatos-cli.exe` | `D:\github\luatos-cli\target\release\luatos-cli.exe` | 烧机、抓日志、自动判定 |
| `xmake` | `C:\Program Files\xmake\xmake.exe`(已加 PATH) | 编 .soc |
| arm-gnu-toolchain | SDK 自己拉取 / `sdk/sdk.lua set_sdkdir` | 交叉编译器 |
| `luatos-ext-components` | `D:\github\luatos-ext-components` | 扩展组件源码 |

`luatos-cli` 没编过的话:`cd D:\github\luatos-cli && cargo build --release -p luatos-cli`(需 Rust 1.78+,workspace edition 2021)。

---

## 2. 模组矩阵(luatos-cli 支持的全部)

| 模组族 | `chip_type` 标识 | SDK 仓库 | 默认 baud | port 自动检测 | log 模式 | `flash test` |
|---|---|---|---|---|---|---|
| **Air1601 / Air1602** | `ccm4211` | `luatos-sdk-ccm42xx-gcc` | 6 000 000 | ❌ 必须 `--port COMx` | binary (含 `--probe`) | ✅ 自动 overlay `--script` |
| **Air8000 / Air780E*** | `ec7xx` (EC718 系) | (用户提供) | 921 600 | ✅ `--port auto` | binary (含 `--probe`) | ✅ |
| **Air8101** | `bk72xx` (BK7258) | (用户提供) | 由 SOC info.json 协商 | ❌ | text | ✅ |
| **Air6208 / Air101 / Air103** | `xt804` | (用户提供) | XMODEM-1K | ❌ | binary | ✅ |
| **Air8101-SF32** | `sf32lb58` | (用户提供) | (依 sftool-lib) | ❌ | text | ❌ 未实现 |

`*`:Air780EPM/EHM/EHV/EHG/Air780E 都归 `ec7xx`。

**遇到表里没的模组**:`luatos-cli guide model --model <name>` 查别名;`luatos-cli guide models` 列全部。`docs/models/*.md`(在 luatos-cli 仓库)是每个模组族的协议级细节文档。

---

## 3. 编译 .soc

**不要在 LuatOS 这边复制 xmake 命令**。每个模组的 SDK 仓库 readme 是构建的权威——比如 air1601 见 `D:\github\luatos-sdk-ccm42xx-gcc\readme.md` 的 "LuatOS 编译" 一节。

LuatOS 这边只需关心三件事:

1. **`LUATOS_REPO_DIR` 必须指向你当前在用的 LuatOS 检出/worktree**,而不是默认的 `D:\github\LuatOS`(否则你的 worktree 改动不进 .soc)。同理 `LUAT_EXT_REPO_DIR` 指 `luatos-ext-components`。
2. **每次编完都校验源文件真进了 .soc**(避免 SDK 抓了旧路径):
   ```bash
   grep -oE "<相关组件>[a-z_]+\.c\.o" \
     "<SDK>/csdk/project/luatos/build/.deps/luatos/cross/arm/debug/luatos.elf.d" | sort -u
   ```
   例如 air1601 + pgfs 应看到:
   ```
   pgfs_alloc_gc.c.o
   pgfs_cache_lock.c.o
   pgfs_checkpoint.c.o
   pgfs_core.c.o
   pgfs_ecc.c.o
   pgfs_ftl_integration.c.o
   pgfs_nand_ftl.c.o
   pgfs_vfs_adapter.c.o
   ```
3. **PC 编译能过 ≠ 真机能过**。MSVC 对 implicit function declaration 是 warning,arm-gnu 是 error。每次新增/修改函数时同步加 header 声明,别只靠 PC 编译验证。(本仓库 2026-06-03 就发生过 `pgfs_file_remove` 漏声明、PC 编译过、Air1601 编译挂的事故。)

---

## 4. 三大核心命令(以 Air1601 为模板)

设环境变量更紧凑:
```bash
CLI='D:\github\luatos-cli\target\release\luatos-cli.exe'
SOC='D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\out\LuatOS-SoC_V1021_Air1601.soc'
```

### 4.1 `flash run` — 一次性刷 .soc + 抓启动日志
```bash
"$CLI" flash run --soc "$SOC" --port COM10 --baud 6000000 --tail-log-secs 30
```
适合:"我想看新固件起来啥样"。`--tail-log-secs 0` 不抓日志直接退出。

### 4.2 `flash script` — 只覆盖脚本分区(不刷 core)
```bash
"$CLI" flash script --soc "$SOC" --port COM10 --baud 6000000 --script <script_dir>
```
适合:核心固件没动、只改了 Lua 脚本的快速迭代。比 `flash run` 快 4~5 倍(只传 ~40 KB 而不是 4 MB)。

### 4.3 `flash test` — 自动化(CI 入口)
```bash
"$CLI" flash test --soc "$SOC" --port COM10 --baud 6000000 \
  --script <common_scripts> --script <case_scripts> \
  --timeout 90 \
  --keyword '### OVERALL_PASS ###' \
  --fail-keyword '### OVERALL_FAIL ###' \
  --fail-keyword 'panic' --fail-keyword 'hardfault'
```
退出码:PASS=0,FAIL=1。`--format json` 出 JSONL(进度事件 + 末尾 pretty 块,见 §6 解析方法)。

**Air1601/1602/CCM4211 专属**:`flash test` 收到 `--script` 时会**先全量刷 .soc,再二次连接覆盖脚本分区**,这是 luatos-cli 自动做的,不要手动两步。

### 4.4 `log view-binary` / `log view` — 手动看日志
```bash
"$CLI" log view-binary --port COM10 --baud 6000000 --probe         # CCM4211/EC718 binary 日志
"$CLI" log view --port COM10 --baud 921600                          # 文本日志
"$CLI" log view-binary --port auto --probe --save D:\logs\          # EC718 自动找 log port + 滚动归档
```

---

## 5. ⚠️ `flash test` 关键字契约(必读,踩过的坑)

`luatos-cli flash test` 用关键字判定结果。语义**很容易用错**:

| 标志 | 语义 |
|---|---|
| `--keyword <k>` | **每一个** k 都必须出现才算 PASS;不传则默认只检 `LuatOS@`;传了就不再混入默认值 |
| `--fail-keyword <k>` | **任一** k 出现立刻 FAIL(快速失败)|
| `--timeout <sec>` | 超时即 FAIL,无默认含义 |

### 5.1 testrunner 写的 case 的正确用法(强烈推荐)
```bash
--keyword '### OVERALL_PASS ###' \
--fail-keyword '### OVERALL_FAIL ###' \
--fail-keyword 'panic' --fail-keyword 'hardfault'
```
- PASS token 是必须出现的(由 `testrunner.runBatch` 在测试全过时通过 `log.info` 发出)
- FAIL token 是出现即失败的(testrunner 在任一 case 出错时发出)

### 5.2 ❌ 常见错误用法
```bash
# 错!这要求 PASS 和 FAIL 都出现,而测试只会发一个,永远判 FAIL
--keyword '### OVERALL_PASS ###' --keyword '### OVERALL_FAIL ###'
```
本仓库 `testcase/air1601_pgfs_regression/air1601_pgfs_regression_basic/README.md` 在 2026-06-03 之前就是这么写的,人为造成 false-FAIL。

### 5.3 ❌ 子串污染
- `--fail-keyword 'panic'` 会匹配 `no_panic_seen`、`panic_recovery_test` 等无害字符串
- `--fail-keyword 'assert'` 会被 lua 的 `assert(...)` 调用日志触发
- 写新真机测试时**不要用** `panic / assert / hardfault / fault / error / fatal` 这些保留词命名测试函数

### 5.4 真机超时建议
- 单元小用例:`--timeout 15`(默认)
- 回归套件(含 mount + 多次 IO + reset):`--timeout 60~120`
- 涉及大文件 unzip / NES 仿真负载:更长,先用 `flash run --tail-log-secs 180` 摸底再定

---

## 6. 解析 `--format json` 输出

`--format json` 给的是**混合流**:前半 JSONL 进度事件,末尾一个 pretty-printed 结果块。Python 解析方法:

```python
import json, io
with io.open('result.json', encoding='utf-8') as f:
    text = f.read()
# 末尾 pretty 块以 '{\n' 开头
tail = text[text.rfind('{\n'):]
obj = json.loads(tail)
data = obj.get('data', obj)
print(data['result'], data['matched_fail_keywords'], data['missing_keywords'])
for l in data.get('boot_log', []):
    if 'testrunner' in l or 'OVERALL_' in l:
        print(l)
```

注意 Windows 上要 `encoding='utf-8'`,boot_log 里有中文。

---

## 7. 写一个新真机 testcase

目录结构(参考 `testcase/air1601_pgfs_regression/air1601_pgfs_regression_basic/`):
```
testcase/<feature>/<feature>_basic/
├── README.md                     # 该套件如何编译/刷/跑(指向本 skill)
└── scripts/
    ├── metas.json                # 人读的元数据,framework 不解析
    ├── main.lua                  # testrunner 接线 + wdt 喂狗
    └── <feature>_test.lua        # test_* 函数 + assert
```

### 7.1 `metas.json`(只是文档,没人解析)
```json
{
  "name": "<feature>_basic",
  "summary": "...",
  "platform": ["air1601"],
  "timeout": 60
}
```

### 7.2 `main.lua` ⚠️ 必带 WDT 喂狗

测试套件超过几十秒的话,**必须**喂狗,否则真机会被 watchdog 重启,日志中断在中间:

```lua
PROJECT = "<feature>_basic"
VERSION = "1.0.0"

if wdt and wdt.init then
    wdt.init(9000)
    sys.taskInit(function()
        while true do
            sys.wait(1000)
            if wdt.feed then wdt.feed() end
        end
    end)
end

local testrunner = require("testrunner")
local tests = require("<feature>_test")
sys.taskInit(function()
    testrunner.runBatch("<feature>_basic", {
        { testTable = tests, testcase = "..." }
    })
end)
sys.run()
```

### 7.3 `<feature>_test.lua` — 用 production API,不用 utest

真机测试**不**通过 `<lib>.utest(case)` 入口(`LUAT_USE_UTEST` 只 PC 开,芯片侧不开)。改成调产品 API,配合运行时控制 API 做故障注入:

```lua
local M = {}

function M.test_basic_io()
    -- 用 lf.* / io.* / fs.* / sensor.* / spi.* 这类产品 API
    local flash = lf.init(spi.deviceSetup(2, 4, 0, 0, 8, 2000000, spi.MSB, 1, 0))
    assert(flash, "lf.init failed")
    assert(lf.mount(flash, "/mnt", 0, 0, "pgfs"), "mount failed")
    local f = io.open("/mnt/x", "wb"); f:write("hello"); f:close()
    local f2 = io.open("/mnt/x", "rb"); assert(f2:read("*a") == "hello"); f2:close()
    return true
end

return M
```

### 7.4 ⚠️ testrunner 的"虚绿"陷阱

`testcase/common/scripts/testsuite.lua` 把 `test_*` 函数包在 `pcall` 里——**函数返回 `false` 不会被判 FAIL**,只有抛 lua 错误(`error()` / `assert(false)`)才算 FAIL。所以测试一定要这样写:

```lua
function M.test_x()
    local ok = some_op()
    assert(ok, "some_op failed: " .. tostring(ok))   -- ✅ assert 才会传播失败
    return true
end

function M.test_y()
    local ok = some_op()
    if not ok then
        log.error("test", "some_op failed")
        return false                                  -- ❌ testrunner 会当成 PASS!
    end
    return true
end
```

本仓库 `air1601_pgfs_test.lua` 至 2026-06-03 仍是 ❌ 模式,导致 3 个真实失败(reset_runtime/powercut_stage/reopen_recover)被吞,exit code = 0 却有 bug——见 §10 known issues。

---

## 8. PC vs 真机的边界

| 维度 | PC 模拟器 | 真机 |
|---|---|---|
| 入口 | `build/out/luatos-lua.exe <common> <case>` | `luatos-cli flash test` |
| C-utest (`<lib>.utest(case)`) | ✅ 主战场,有 OpenCppCoverage | ❌ 不开 `LUAT_USE_UTEST` |
| 故障注入 | 模拟 flash 注入 + powercut stage 枚举 | `lf.pgfsctl(...)` 等运行时控制 API |
| 大规模 GC/FTL/契约 | ✅ 跑这里 | ⚠️ 真机回归只挑无 PC 等价物的(NAND 信号完整性、真 SPI 时序、wdt 行为) |

凡能在 PC 上写的契约/边界/单元测试,**优先在 PC 上写**——快、可重复、有覆盖率。真机回归只验证 PC 无法模拟的部分。

---

## 9. 故障树(按症状索引)

### 9.1 编译失败
- `LUATOS_REPO_DIR` / `LUAT_EXT_REPO_DIR` 没设或指向旧路径 → 改对 env 重编
- arm-gcc 报 `implicit declaration of function 'foo'` → header 漏声明;在对应 `<comp>_internal.h` 加 forward decl,PC 能过不代表 arm 能过
- `cannot match add_files` warning → 引用的某个组件源目录被删了,看 SDK 仓库的 xmake.lua 是否需要更新(LuatOS 侧通常不用管)

### 9.2 刷机阶段
- `Handshaking with ISP bootrom` 卡住 → 设备没进 ISP;手动按复位、或检查 USB 线/驱动
- 串口被占 → 关 LLCOM / SSCOM / PuTTY / Cutecom / VSCode Serial Monitor
- Air1601 USB 不识别 → CCM4211 自带 USB-ISP+USB-ACM,VID 应是合宙的;换 USB 口或 USB 线
- `auto_enter_boot_mode failed`(EC718) → VID `0x19D1` 没出现,换 USB 口、查驱动

### 9.3 启动后没终态(超时 FAIL)
- 多半是测试卡在某一步——抓完整日志看最后一条 `I/-` 是什么:
  ```bash
  "$CLI" flash run --soc "$SOC" --port COM10 --baud 6000000 --tail-log-secs 120
  ```
- 没 WDT 喂狗导致重启循环 → §7.2
- testrunner 卡在 `initNetwork()` 等 `IP_READY`(无网模组也会跑) → 容忍超时,或在 main.lua 里跳过 init_network

### 9.4 testrunner 报 PASS 但实际有问题
- ⚠️ §7.4 的"虚绿"陷阱——函数返回 `false` 不算 FAIL。逐行看 `air1601.pgfs` / `user.*` 日志,grep `E/` 错误行
- 如果改不了测试代码,至少看 `E/pgfs` / `E/user.*` / `W/pgfs` 的出现频率

### 9.5 SPI flash 相关(Air1601 pgfs)
- `lf.init failed` → 接线/CS/供电组合不对。Air1601 验证过的是 `spi2 + cs4 + pwr50`
- `pgfs mount failed` → 残留 SB/CP 没擦干净,在测试里加 `lf.erase(flash, 0, 0x4000)`
- `Read failed at addr=N` / `pgfs replay skip bad block read failure` → SPI 信号完整性,降 SPI clock(改测试脚本顶部 `SPI_SPEED = 1000000`)
- `pgfs replay skip unknown region at addr=... magic=474e5089` → flash 残留旧数据(PNG/NES 等),replay 在跳过,这是正常的、不是 bug
- `E/pgfs FTL re-init failed on runtime reset` → 已知 issue,见 §10

### 9.6 EC718 / Air8000
- flash 后串口找不到 → `find_ec718_log_port` 15s 超时,VID `0x19D1` 应在重枚后消失;若不消失换 USB 口
- baud 2000000 在 Windows USB CDC 上常被拒,EC718 已强制降到 921 600

---

## 10. Known issues(真机)

本节登记**已知但本 skill 范围外**的真实问题。修复后请删除对应条目。

### 10.1 air1601 pgfs `reset_runtime` 仍失败 — ✅ FIXED (2026-06-03)
- 现象:`lf.pgfsctl("reset_runtime")` 返回 `false`,日志 `E/pgfs FTL re-init failed on runtime reset`
- 根因:`pgfs_control_reset_runtime` 在 `pgfs_vfs_adapter.c` 无条件调 `pgfs_ftl_on_mount`,而该函数在 `flash_opts==NULL`(无 mount 或 umount 后)时返回 -1
- 修复:`pgfs_vfs_adapter.c:553-562` 加 `if (s_pgfs_ctx.flash_opts != NULL)` guard,Path A(无 mount)走 no-op success,Path B(mount 后 reset)正常调 re-init
- 真机验证(COM10/air1601/W25N01KVZEIR,2 MHz SPI):`test_pgfsctl_reset` 与 `test_reopen_recover` 均报 `reset_runtime -> true`,无 `E/pgfs FTL re-init` 日志
- PC utest:`pgfs_basic` 30+ 子用例全过

### 10.2 `powercut_stage("before_cp")` 字符串不认 — ✅ FIXED (2026-06-03)
- 现象:`lf.pgfsctl("powercut_stage", "before_cp")` 返回 `false`
- 根因:`pgfs_vfs_adapter.c:418-451` 字符串表只认 `before_checkpoint`(长形)
- 修复:`pgfs_vfs_adapter.c:426-430` 加 `|| "before_cp"` alias,都映射到 `PGFS_INJECT_POWERCUT_BEFORE_CP`
- 真机验证:`test_pgfsctl_powercut` 报 `powercut_stage before_cp -> true`
- PC utest:在 `pgfs_test_batch_api_boundaries` 加 alias 覆盖行,全过

### 10.3 air1601 pgfs `test_reopen_recover` 文件丢失 — ✅ FIXED in code path (2026-06-03)
- 现象:写入 31B + `reset_runtime` + 重 mount,读时 `open(rb) failed`,文件不存在
- 根因:`luat_vfs_pgfs_mount` 在 `pgfs_vfs_adapter.c:171-176` 走 Phase 4b "O(1) skip" 路径(CP/FTL log_tail 一致时跳 replay),但 file table 是纯内存的,跳过 replay 后 remount 的 file table 永远是空的
- 修复:`pgfs_vfs_adapter.c:158-200` 把 mount 路径的 O(1) skip 改为 **bounded replay**:
  1. 早调 `pgfs_ftl_on_mount` 拿 FTL 的 write_head / log_tail
  2. 用 CP 的 `log_tail_*` 把 `data_log_write_addr` 限定到 durable 区域(同 `fbeda6236` 在 reset 路径的逻辑,统一 mount/reset 两条路径语义)
  3. **总是**调 `pgfs_replay_data_log` — 性能保留(限定扫描范围到 `[base, log_tail]`),正确性恢复(file table 总是从数据日志重建)
- 真机验证:remount 日志 `I/pgfs mount: replay bound by CP log_tail=1/2048 (write_addr=788480)` 出现,replay 实际跑
- **附带**:同步把 air1601 测试脚本里 5 处 `return false` 改为 `assert(...)`/`error()`(打破 §7.4 的 虚绿 陷阱),让 testrunner 真实反映底层状态
- **剩余 1 个真机未通过原因(非本修复范围)**:W25N01KVZEIR 在 2 MHz/1 MHz SPI 下有 `replay skip bad block read failure at addr=786432` 信号完整性问题(AGENTS.md:230 登记),导致 data record 被静默 skip。后续:加 SPI 读 retry 或降到 500 KHz。

### 10.4 air1601 W25N01KVZEIR SPI 信号完整性 (NEW, 2026-06-03)
- 现象:2 MHz SPI 偶有 `replay skip bad block read failure at addr=N`(`E/little_flash Error: Read failed`);1 MHz 时问题移到不同地址
- 影响:长 data log 写入后,remount replay 可能因 SPI bit-flip 跳过 record,导致 test_reopen_recover fail
- 修复线索:在 `pgfs_lf_read` 加 retry 逻辑(目前 1 次读失败就放弃);或测试时把 SPI clock 降到 500 KHz
- 跟踪:见 `components/pgfs/AGENTS.md` §"真机已知限制"

---

## 11. 引用与对应的真实文档

- **luatos-cli**:`D:\github\luatos-cli\README.md`、`docs/models/*.md`(各模组族协议级细节)、`crates/luatos-cli/src/cmd_flash.rs:516` `cmd_flash_test` 实现
- **Air1601 SDK 编译**:`D:\github\luatos-sdk-ccm42xx-gcc\readme.md` "LuatOS 编译"
- **LuatOS 内部约定**:
  - `testcase/AGENTS.md` — testrunner / `test_*` 模式 / metas.json
  - `components/pgfs/AGENTS.md` — pgfs 内部设计、PC 验证矩阵、`lf.pgfsctl` 控制 API
  - `components/utest/AGENTS.md` — C-utest 只 PC 跑的声明
  - `bsp/pc/AGENTS.md` — PC 模拟器 build + 跑 utest
  - `bsp/air1601/README.md` — air1601 LuatOS 侧 worktree 用法 + .elf.d 校验
