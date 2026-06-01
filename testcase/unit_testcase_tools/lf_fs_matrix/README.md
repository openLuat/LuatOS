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
