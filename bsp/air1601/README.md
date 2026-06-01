# Air1601 编译与下载调试说明（COM10, 6M）

## 环境
- 不要直接使用 `CI_REPOS_PATH=D:\github`（会固定引用 `D:\github\LuatOS`，忽略 worktree 变更）
- LuatOS worktree：`D:\github\LuatOS\.worktrees\lfs2n-pc-air1601`
- SDK 工程：`D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos`
- 刷机工具：`D:\github\luatos-cli\target\release\luatos-cli.exe`
- 设备串口：`COM10`
- Air1601 固定波特率：`6000000`（6M）

## 编译 Air1601
worktree 开发推荐直接使用环境变量，不再依赖 `CI_REPOS_PATH` + Junction：

```powershell
$env:LUATOS_REPO_DIR = 'D:\github\LuatOS\.worktrees\lfs2n-pc-air1601'
$env:LUAT_EXT_REPO_DIR = 'D:\github\luatos-ext-components'
Set-Location D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos
xmake clean
xmake
```

产物：
- `out\LuatOS-SoC_V1021_Air1601.soc`

### 实测验证（COM10 同批次）
- 已在 `D:\github\LuatOS\.worktrees\air1601-env-verify-20260531` 建独立 worktree。
- 已验证 `xmake clean && xmake` 成功（`build ok`，生成 Air1601 `.soc`）。
- 已在 worktree 源码 `lua\src\lapi.c` 注入 `#error "WORKTREE_ENV_VAR_PROOF"` 后重编译，构建按预期失败，且报错路径指向该 worktree。
- 移除注入后再次 `xmake` 成功，确认 `LUATOS_REPO_DIR` / `LUAT_EXT_REPO_DIR` 路径生效正常。

## 下载与脚本下发

```powershell
$cli='D:\github\luatos-cli\target\release\luatos-cli.exe'
$soc='D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\out\LuatOS-SoC_V1021_Air1601.soc'

# 推荐：整包刷机后连续抓启动日志（减少开机日志丢失）
& $cli flash run --soc $soc --port COM10 --baud 6000000 --tail-log-secs 30

# 下发脚本目录（需包含 main.lua）
& $cli flash script --soc $soc --port COM10 --baud 6000000 --script <script_dir>

# 独立查看 Air1601 二进制日志（建议带 --probe）
& $cli log view-binary --port COM10 --baud 6000000 --probe
```

## 启动日志判定（建议统一）

```powershell
# Air1601/Air1602: flash test 传 --script 时，会先全量刷机，再覆盖脚本区，再抓日志判定
& $cli flash test --soc $soc --port COM10 --baud 6000000 --script <common_scripts> --script <case_scripts> --timeout 30 --keyword '### OVERALL_PASS ###' --keyword '### OVERALL_FAIL ###' --fail-keyword 'assert' --fail-keyword 'panic' --fail-keyword 'hardfault'

# LFS2N 指标校验（确认纯 wall 指标已落日志）
& $cli flash test --soc $soc --port COM10 --baud 6000000 --timeout 80 --keyword 'LFS2N_BASELINE_WRITE_PURE_WALL_MS' --keyword 'LFS2N_BASELINE_WRITE_WALL_MS' --fail-keyword 'assert' --fail-keyword 'panic' --fail-keyword 'hardfault'
```

规则：
- 刷机流程应在 2 分钟内完成。
- 开机后 30 秒内必须出现 PASS/FAIL 关键词，否则按 FAIL 处理。
- `--fail-keyword` 命中任意一项会立即 FAIL；建议避免把 `panic` 作为普通字符串出现在测试名（例如 `no_panic` 会触发快速失败）。

## 常见问题
- `lf.init` 失败：优先核对 SPI/CS/供电脚组合；当前板级已验证组合为 `spi2 + cs4 + pwr50`。
- 30 秒内无终态：先看是否卡在文件系统慢写（`/lfs2n`），再看脚本是否在失败后及时输出终态标记。
- 串口占用：关闭其他串口监控工具后重试。
