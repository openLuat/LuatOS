# Air1601 编译与下载调试说明（COM10）

## 环境
- 不要直接使用 `CI_REPOS_PATH=D:\github`（会固定引用 `D:\github\LuatOS`，忽略 worktree 变更）
- LuatOS worktree：`D:\github\LuatOS\.worktrees\lfs2n-pc-air1601`
- SDK 工程：`D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos`
- 刷机工具：`D:\github\luatos-cli\target\release\luatos-cli.exe`
- 设备串口：`COM10`

## 编译 Air1601
在 SDK 工程目录执行：

```powershell
$worktree = 'D:\github\LuatOS\.worktrees\lfs2n-pc-air1601'
$repos = 'D:\github\_ci_repos_lfs2n'
if (!(Test-Path $repos)) { New-Item -ItemType Directory -Path $repos | Out-Null }
if (Test-Path "$repos\LuatOS") { Remove-Item "$repos\LuatOS" -Recurse -Force }
if (Test-Path "$repos\luatos-ext-components") { Remove-Item "$repos\luatos-ext-components" -Recurse -Force }
New-Item -ItemType Junction -Path "$repos\LuatOS" -Target $worktree | Out-Null
New-Item -ItemType Junction -Path "$repos\luatos-ext-components" -Target 'D:\github\luatos-ext-components' | Out-Null
$env:CI_REPOS_PATH = $repos
Set-Location D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos
xmake
```

产物：
- `out\LuatOS-SoC_V1021_Air1601.soc`

## 下载与脚本下发

```powershell
$cli='D:\github\luatos-cli\target\release\luatos-cli.exe'
$soc='D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\out\LuatOS-SoC_V1021_Air1601.soc'

# 整包刷机
& $cli flash run --soc $soc --port COM10

# 下发脚本目录（需包含 main.lua）
& $cli flash script --soc $soc --port COM10 --script <script_dir>
```

## 启动日志判定（建议统一）

```powershell
# 先显式下发脚本，避免 flash test 读取到设备上的旧脚本
& $cli flash script --soc $soc --port COM10 --script <common_scripts> --script <case_scripts>

# 再做闭环日志判定
& $cli flash test --soc $soc --port COM10 --timeout 30 --keyword '### OVERALL_PASS ###' --keyword '### OVERALL_FAIL ###'

# LFS2N 指标校验（确认纯 wall 指标已落日志）
& $cli flash test --soc $soc --port COM10 --timeout 80 --keyword 'LFS2N_BASELINE_WRITE_PURE_WALL_MS' --keyword 'LFS2N_BASELINE_WRITE_WALL_MS'
```

规则：
- 刷机流程应在 2 分钟内完成。
- 开机后 30 秒内必须出现 PASS/FAIL 关键词，否则按 FAIL 处理。

## 常见问题
- `lf.init` 失败：优先核对 SPI/CS/供电脚组合；当前板级已验证组合为 `spi2 + cs4 + pwr50`。
- 30 秒内无终态：先看是否卡在文件系统慢写（`/lfs2n`），再看脚本是否在失败后及时输出终态标记。
- 串口占用：关闭其他串口监控工具后重试。
