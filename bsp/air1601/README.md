# Air1601 LuatOS 侧注意事项

> 本文档**只列 LuatOS 仓库这边**关于 Air1601 真机开发的注意事项。
> - 编译流程见 SDK 仓库:`D:\github\luatos-sdk-ccm42xx-gcc\readme.md` "LuatOS 编译"
> - 刷机/抓日志/真机测试完整流程见 `/luatos-hw-test` skill(`.claude/skills/luatos-hw-test/SKILL.md`)
> - Air1601 pgfs 回归套件见 `testcase/platform/air1601/pgfs_regression/air1601_pgfs_regression_basic/`

## 环境(LuatOS 侧只关心这两件)

| env | 默认值 | LuatOS 这边要做的 |
|---|---|---|
| `LUATOS_REPO_DIR` | `D:\github\LuatOS` | **改成当前你在用的 worktree 路径**(如 `.worktrees\<name>`),否则 worktree 改动不进 .soc |
| `LUAT_EXT_REPO_DIR` | (无,SDK 找不到会报错) | 设为 `D:\github\luatos-ext-components` |

不要使用 `CI_REPOS_PATH=D:\github` + Junction 的老办法——它会固定引用 `D:\github\LuatOS`,忽略 worktree 变更。

## 校验:worktree 改动真的进了 .soc

每次重编后:

```powershell
Select-String `
  -Path "D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\build\.deps\luatos\cross\arm\debug\luatos.elf.d" `
  -Pattern "<你改的组件名>"
```

应看到对应 `.c.o` 文件,且路径指向**你当前用的 worktree**(不是 `D:\github\LuatOS`)。例如改了 pgfs 应看到:

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

## arm-gnu 编译能过 ≠ PC 能过(反之亦然)

历史 case(2026-06-03):`pgfs_file_remove` 在 `pgfs_core.c` 有实现但 `pgfs_internal.h` 漏 forward decl。MSVC(PC)只 warning 不挡,arm-gnu(Air1601)直接 error。**每次新增/修改函数同步加 header 声明**,别只靠 PC 编译验证。

## 实测验证(历史记录,可读可不读)

- 2026-05-31 在 `D:\github\LuatOS\.worktrees\air1601-env-verify-20260531` 建独立 worktree 做 env 切换验证
- 验证方法:在 worktree 源码 `lua\src\lapi.c` 注入 `#error "WORKTREE_ENV_VAR_PROOF"`,重编挂掉且报错路径指向该 worktree → 证明 env 生效
- 移除注入后重编通过

## 一些 LuatOS 侧特有的 .soc 变体

SDK 支持 `xmake f --debug_fw=y` 产 `_DEBUG` 后缀的 .soc(在 `csdk/core/src` + `csdk/project/luatos/src` 加 `-D_DEBUG` 和 `-fno-omit-frame-pointer` 帮助崩溃诊断)。详见 SDK readme。

## 故障树

刷机/抓日志/通讯类故障 → `/luatos-hw-test` skill §9。
本 README 不重复。
