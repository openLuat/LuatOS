# ROMFS 只读文件系统

## Scope
`components/romfs/` - 标准 romfs(`-rom1fs-`, genromfs 兼容)只读文件系统的 VFS 实现。

## Where to Look

| 事项 | 位置 |
|------|------|
| VFS 实现 | `luat_vfs_romfs.c` |
| 公开契约/配置宏 | `luat_romfs.h` |
| 镜像生成器 | `tools/romfs/mkromfs.py` |
| PC 测试套件 | `testcase/utest/fs/romfs_basic/` |

## 约定

- 挂载经 `luat_fs_conf_t.busname` 传 `luat_romfs_ctx_t*`;mount 时拷贝 ctx, 调用方不需保活。
- 双后端: `ctx.read == NULL` → userdata 是镜像基址(指针模式, 支持 mmap 零拷贝); 非 NULL → read 回调模式(SPI flash 等)。
- 所有镜像内偏移是**绝对偏移**(相对镜像起点), 大端; 文件名变长 NUL 结尾 + 16 字节对齐。
- 符号链接目标按**根相对**路径解析(前导 `/` 会被剥掉); 不支持 `..`。
- mount 默认校验镜像头 checksum(`LUAT_ROMFS_VERIFY_HEAD_CKSUM`)。

## 镜像 regen

```bash
python tools/romfs/mkromfs.py testcase/utest/fs/romfs_basic/fixture \
    --c-array bsp/pc/src/luat_romfs_fixture.c --name romfs_fixture_img \
    --hardlink link_hello.txt=hello.txt --symlink sym_hello.txt=hello.txt
```

## Anti-Patterns

- ❌ 磁盘结构体禁止使用 `size_t`/指针等可变宽度类型 — 一律 `uint8_t/uint32_t` + be32 转换。
- ❌ 链表遍历必须带 guard(`img_size/16`), 损坏镜像不得死循环。
- ❌ 不要给 romfs 加写操作的"伪实现" — mkfs/fwrite 保持 NULL, remove/rename/mkdir/rmdir 显式返回 -1。

## Related Docs

- 根 `AGENTS.md`(Build & Test)、`bsp/pc/AGENTS.md`(测试运行方式)
