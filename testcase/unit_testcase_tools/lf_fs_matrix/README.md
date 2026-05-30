# lf_fs_matrix

`lf_fs_matrix` 用于验证 little_flash 在 4 种文件系统下的一致行为：`lfs2`、`lfsn`、`pgfs`、`lfs3`。

## 覆盖项

- mount/read/write 基础可用性
- 压缩包解压（`pac_man.zip`）
- 可用空间查询（`fs.fsstat`）
- 结果统一输出：`LF_FS_MATRIX_RESULT`

## 关键测试资源

- 解压资源固定为：`testcase/unit_testcase_tools/lf_fs_matrix/scripts/pac_man.zip`

## FTL 初始化统计日志（NAND）

当启用 little_flash FTL 时，启动日志会输出：

1. `little_flash ftl init: blocks=... bad_blocks=... bad_pages=... logical_pages=... reserve_pages=...`
2. `little_flash ftl space: usable=... reserve_free=... reserve_total=... raw=...`

用于观测坏块统计、实际可用空间和保留空间余量。

## 坏块比例矩阵回归（1% / 5% / 10%）

使用脚本批量执行三档坏块比例：

```powershell
python testcase\unit_testcase_tools\lf_fs_matrix\run_lf_fs_matrix_ratios.py
```

环境变量：

- `LUAT_PC_NAND_BAD_BLOCK_RATIO`：坏块比例（脚本自动设置为 `0.01/0.05/0.10`）
- `LUAT_PC_NAND_SEED`：随机种子（默认 `0x13572468`，可外部覆盖）
- `LUAT_PC_NAND_OOB_SIZE`：每页 OOB 大小（默认 64）

日志输出目录：

- `testcase/unit_testcase_tools/lf_fs_matrix/outputs/lf_fs_matrix_ratio_*.log`

判定规则：

- 强制通过：`lfsn`、`pgfs`
- 观察项：`lfs2`、`lfs3`
