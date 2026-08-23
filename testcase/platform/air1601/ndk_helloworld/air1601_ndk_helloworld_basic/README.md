# Air1601 真机 NDK helloworld 验证

## 背景

NDK 组件 (`components/ndk`) 当前仅在 PC 模拟器有回归套件
(`testcase/ndk/ndk_basic`, `ndk_hostabi_basic`)。真机 (air1601 / CCM4211) 侧
**没有**任何 NDK 测试用例。本套件是 NDK 真机冒烟的最小基线,验证:

- NDK 组件在 air1601 SDK `.soc` 中已正确链接 (`add_files` 进了 `components/ndk/src` + `binding`)
- Lua 侧 `ndk.rv32i()` 能从 VFS `/luadb/` 加载 RV32I guest 二进制
- `ndk.exec()` 同步执行完成, 通过 SYSCON `0x5555` 正常退出
- `ndk.getData()` 读 exchange 头 16 字节, 拿到 ASCII `HELLO_NDK_DONE` 标志

> 后续如需 RV32F 浮点 / crypto 回归, 直接在本套件下加用例即可, 模板一致。

## 编译 .soc

```powershell
$env:LUATOS_REPO_DIR   = 'D:\github\LuatOS\.claude\worktrees\ndk-hello-air1601'
$env:LUAT_EXT_REPO_DIR = 'D:\github\luatos-ext-components'
$env:Path = "D:\github\xmake;$env:Path"
Set-Location D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos
xmake -j8
```

产物: `out/LuatOS-SoC_V1021_Air1601.soc`

**前提:** `luatos-sdk-ccm42xx-gcc/csdk/project/luatos/xmake.lua` 中需注册 NDK
(本 worktree 假定 SDK 已加上, 见 `可能修改` 一节)。

## 验证 .soc 是否含 NDK 源

```powershell
Select-String `
  -Path "D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\build\.deps\luatos\cross\arm\debug\luatos.elf.d" `
  -Pattern "luat_ndk"
```

应看到 `luat_ndk.c.o` / `luat_ndk_host.c.o` / `luat_lib_ndk.c.o` 等, 路径指向
worktree (`\.claude\worktrees\ndk-hello-air1601\components\ndk\`), 不是 `D:\github\LuatOS\`。

## 烧录 + 跑测试

完整命令模板、模组矩阵、关键字契约见 `/luatos-hw-test` skill。本套件的标准调用:

```powershell
$cli    = 'D:\github\luatos-cli\target\release\luatos-cli.exe'
$soc    = 'D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\out\LuatOS-SoC_V1021_Air1601.soc'
$common = 'D:\github\LuatOS\testcase\common\scripts'
$case   = 'D:\github\LuatOS\.claude\worktrees\ndk-hello-air1601\testcase\platform\air1601\ndk_helloworld\air1601_ndk_helloworld_basic\scripts'

# 一次性: 烧 .soc + 烧脚本 (含 hello_world.bin) + 抓日志判断
& $cli flash test `
  --soc $soc `
  --port COM10 `
  --baud 6000000 `
  --script $common `
  --script $case `
  --timeout 30 `
  --keyword '### OVERALL_PASS ###' `
  --fail-keyword '### OVERALL_FAIL ###' `
  --fail-keyword 'panic' `
  --fail-keyword 'hardfault'
```

> ⚠️ `### OVERALL_FAIL ###` 必须是 `--fail-keyword` 不是 `--keyword`。
> 详见 skill §5, 本仓库 2026-06-03 之前曾因此长期 false-FAIL。

期望日志片段:

```
I/user.luatos main air1601_ndk_helloworld 0.1.0
I/air1601.ndk ===== test_load_and_exec_hello =====
I/air1601.ndk ndk.rv32i ok, ctx=...
I/air1601.ndk ndk.exec ok=true ret=0 mcause=0 mtval=0
I/air1601.ndk exchange[0..15] = HELLO_NDK_DONE
I/user.testrunner ### OVERALL_PASS ### air1601真机NDK helloworld
```

## 故障排查

- **`ndk` 全局表不存在**: NDK 没编进 .soc, 检查 SDK xmake.lua 是否注册 NDK, 重编.
- **`ndk.rv32i failed: can't open /luadb/hello_world.bin`**: 脚本分区没烧进 hello_world.bin,
  确认 `--script $case` 在 `flash test` 参数里 (luatos-cli 会自动二次连接覆盖脚本分区).
- **`exchange marker missing`**: guest 二进制被错误覆盖, 重新
  `cd components\ndk\guest\examples\hello_world && .\build.ps1` 后
  拷回本套件 scripts/. **或** 确认 hello_world.bin 是 92 B (RISC-V flat binary) 而不是空文件.
- **30s 内无 OVERALL_PASS**: 抓 `flash run --tail-log-secs 120` 全日志, 按 skill §9 故障树.
- **`panic` 命中 fail-keyword**: 注意不要把 `panic` / `assert` / `hardfault` / `fault` /
  `error` / `fatal` 写进测试函数名或日志 (与 `--fail-keyword` 子串冲突, 见 skill §5.3).

## 用例列表

| 用例 | 验证点 | 失败说明 |
|------|--------|----------|
| `test_load_and_exec_hello` | ndk.rv32i + ndk.exec + ndk.getData 三件套, HELLO_NDK_DONE 标志 | NDK runtime 链路有断, 或 VFS 挂载失败 |
