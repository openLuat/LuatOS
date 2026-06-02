# Air1601 真机 pgfs 回归测试 (FTL 迁移验证)

## 背景

master 分支的 6 个 commit 把 little_flash FTL 砍到 stub, 把 NAND FTL 落地到 pgfs。
PC 模拟器 (`pgfs_basic` 17/17, `c_utest_little_flash_basic` 1/1) 验证过。
这一组用例是 **真机回归**, 验证 EC618 (air1601) 上的 NOR 路径仍然健康,
且 `lf.pgfsctl` 运行时控制不崩。

注意: air1601 的外部 SPI flash 是 **NOR**, 走 little_flash identity-mapping 路径,
FTL 是 pgfs 内 NOP 状态, 所以这里**不验证 FTL 行为**——只验证:
- C 层改动没破坏 NOR 路径
- pgfs mount/IO/reopen 正常
- 运行时控制 API 可调用

## 编译 .soc

```powershell
$env:LUATOS_REPO_DIR = 'D:\github\LuatOS'
$env:LUAT_EXT_REPO_DIR = 'D:\github\luatos-ext-components'
$env:Path = "D:\github\xmake;$env:Path"
Set-Location D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos
xmake -j8
```

产物: `out/LuatOS-SoC_V1021_Air1601.soc`

> 增量构建即可, xmake 会自动拣到新增/删除的源文件 (pgfs_nand_ftl.c,
> pgfs_ftl_integration.c 进, pgfs_c_tests.c 出).

## 验证 .soc 是否含 FTL 改动

```powershell
# 期望看到 pgfs_nand_ftl.c.o / pgfs_ftl_integration.c.o, 不应有 pgfs_c_tests.c.o
Select-String -Path "D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\build\.deps\luatos\cross\arm\debug\luatos.elf.d" -Pattern "pgfs"
```

## 烧录 + 跑测试

```powershell
$cli = 'D:\github\luatos-cli\target\release\luatos-cli.exe'
$soc = 'D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\out\LuatOS-SoC_V1021_Air1601.soc'
$common = 'D:\github\LuatOS\testcase\common\scripts'
$case  = 'D:\github\LuatOS\testcase\air1601_pgfs_regression\air1601_pgfs_regression_basic\scripts'

# 一次性: 烧 .soc + 烧脚本 + 抓日志判断
& $cli flash test `
  --soc $soc `
  --port COM10 `
  --baud 6000000 `
  --script $common `
  --script $case `
  --timeout 60 `
  --keyword '### OVERALL_PASS ###' `
  --keyword '### OVERALL_FAIL ###' `
  --fail-keyword 'panic' `
  --fail-keyword 'hardfault'
```

期望日志片段:

```
I/air1601.pgfs ===== test_lf_init =====
I/air1601.pgfs lf.init ok, flash=...
I/air1601.pgfs ===== test_pgfs_mount =====
I/air1601.pgfs pgfs mounted at /pgfs_regr
I/air1601.pgfs fsstat: total=N used=0 block_size=4096 fs=pgfs
I/air1601.pgfs ===== test_basic_io =====
I/air1601.pgfs round-trip ok, content matches
I/air1601.pgfs ===== test_reopen_recover =====
I/air1601.pgfs reopen recovery ok, content matches after umount/remount
I/air1601.pgfs ===== test_pgfsctl_lock =====
I/air1601.pgfs lock_mode on -> true
I/air1601.pgfs lock_mode off -> true
I/air1601.pgfs ===== test_pgfsctl_powercut =====
I/air1601.pgfs powercut_stage before_cp -> true
I/air1601.pgfs ===== test_pgfsctl_badblock =====
I/air1601.pgfs bad_block_once on -> true
I/air1601.pgfs write after bad_block_inject ok (no-op on NOR)
I/air1601.pgfs ===== test_pgfsctl_reset =====
I/air1601.pgfs reset_runtime -> true
I/user.testrunner ### OVERALL_PASS ### air1601真机pgfs回归
```

## 硬件连接

默认按 `bsp/air1601/README.md` 验证的组合:

- SPI: bus=2, cs=4, speed=2 MHz
- 电源: gpio50 高电平使能外部 flash

如本机硬件不一致, 改 `air1601_pgfs_test.lua` 顶部的 `SPI_BUS` / `SPI_CS` /
`SPI_PWR` 三个常量.

## 用例列表

| 用例 | 验证点 | 失败说明 |
|------|--------|----------|
| `test_lf_init` | 外部 SPI flash 探测 | SPI 接线 / 供电问题 |
| `test_pgfs_mount` | pgfs mount + fsstat | C 改动破坏了 mount 路径 |
| `test_basic_io` | 写读 round-trip | pgfs 写入或读回有错 |
| `test_reopen_recover` | umount 后 remount, 内容还在 | CP 持久化/恢复出问题 |
| `test_pgfsctl_lock` | lock_mode on/off 切换 | 锁机制有崩 |
| `test_pgfsctl_powercut` | powercut_stage 注入 + reset | 注入 + 恢复路径崩 |
| `test_pgfsctl_badblock` | bad_block_once 注入 (NOR 上是 no-op) | API 本身有崩 |
| `test_pgfsctl_reset` | reset_runtime | 复位路径崩 |

## 故障排查

- **`lf.init failed`**: SPI 接线 / CS / 供电。优先核对 `spi2 + cs4 + pwr50` 组合。
- **30 秒内无终态**: 卡在文件系统慢写, 检查 `lf.pgfsctl "reset_runtime"` 是否被
  调用 (它会强制刷 CP). 也可能是 powercut 注入后没 reset, 后续 IO 全失败。
- **`pgfs mount failed`**: 前 16 KB 残留 SB/CP 没擦干净, `lf.erase(flash, 0, 0x4000)`
  在 `test_pgfs_mount` 已经做了, 持续失败请检查 `LF_DEBUG_MODE` 是否开了
  (master 应该是 off, 除非环境变量手动开了)。
- **串口占用**: 关其他串口工具重试。
