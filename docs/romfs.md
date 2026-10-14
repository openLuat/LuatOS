# romfs 只读文件系统

`components/romfs/` 提供标准 romfs(`-rom1fs-`, genromfs 兼容)的 VFS 实现, 供需要
"镜像即文件系统"的只读场景使用(当前主要用户: 各 BSP 的资源分区、PC 模拟器固件镜像)。

- 实现: `components/romfs/luat_vfs_romfs.c`
- 契约/配置宏: `components/romfs/luat_romfs.h`
- 镜像生成: `tools/romfs/mkromfs.py`
- 组件约定: `components/romfs/AGENTS.md`
- PC 回归: `testcase/utest/fs/romfs_basic/`(指针 + 回调双模式共用 `bsp/pc/src/luat_romfs_fixture.c`)

## 镜像格式

```text
head[16]  = magic "-rom1fs-" | full_size(be32) | checksum(be32)
volume    = 卷名 + NUL, 补齐到 16 字节
entry     = next_and_type(be32) | spec(be32) | size(be32) | checksum(be32)
            | name + NUL 补齐到 16 字节 | data 补齐到 16 字节
```

- `next_and_type` 低 4 位是条目类型(0 硬链接 / 1 目录 / 2 文件 / 3 符号链接), 高 28 位是
  同目录下一条目的偏移(0 = 链尾); 目录的 `spec` 是首个子节点偏移; 所有偏移是镜像内
  绝对偏移且 16 字节对齐。
- 挂载时按 magic → `full_size` → 从偏移 16 起按 16 字节块扫描卷名直到 NUL → 得到根目录头
  偏移; 随后校验头部 checksum(前 `min(512, full_size)` 字节按 BE u32 累加为 0,
  由 `LUAT_ROMFS_VERIFY_HEAD_CKSUM` 开关)。
- **条目自身的 checksum 不校验**(与 genromfs 一致, 仅为工具链兼容而写入)。
- 软/硬链接: 硬链接在挂载期解析为节点索引, 软链接运行时惰性展开(目标按根相对路径解析,
  不支持 `..`)。

## 挂载与配置

`luat_fs_conf_t.busname` 传 `luat_romfs_ctx_t*`, mount 时拷贝该 ctx(调用方无需保活):

```c
typedef struct luat_romfs_ctx {
    void* userdata;        // 指针模式: 镜像基址; 回调模式: 用户上下文
    luat_romfs_read read;  // NULL=指针模式(memcpy, 支持 mmap 零拷贝); 非 NULL=读回调模式
} luat_romfs_ctx_t;
```

| 宏 | 默认 | 语义 |
| --- | ---: | --- |
| `LUAT_ROMFS_MAX_NAME` | 64 | 单级文件名最大长度(不含 NUL)。**恰好 64 字节可用**, 更长者标记 `name_too_long` 并跳过(不参与匹配, 不出现在 `lsdir`) |
| `LUAT_ROMFS_MAX_DIR_DEPTH` | 4 | 目录嵌套深度上限。**第 4 层目录内的文件合法**, 只禁止再嵌套一层子目录(出现第 5 层目录则 mount 失败)。该检查只在 `LUAT_ROMFS_USE_DIR_CACHE=1` 的 mount 阶段生效 |
| `LUAT_ROMFS_MAX_PATH` | 128 | 运行时路径解析缓冲(含软链接展开) |
| `LUAT_ROMFS_MAX_DEPTH` | 8 | 软/硬链接链最大解析深度 |
| `LUAT_ROMFS_VERIFY_HEAD_CKSUM` | 1 | mount 是否校验头部 checksum |
| `LUAT_ROMFS_USE_DIR_CACHE` | 1 | mount 时把目录树载入内存(约 96B/节点); 0 = 退回镜像内联表查找(零 RAM, 但每次解析都读镜像) |

只读语义: `remove`/`rename`/`mkdir`/`rmdir` 显式返回 -1, `fwrite` 为 NULL;
`mkfs` 为 NULL。`info()` 返回 `filesystem = "romfs"`, `block_size = 512`,
`total_block = ceil(full_size / 512)`, `block_used = total_block`(只读镜像整块占用),
即 `total * block` 恒等于镜像长度按 512 向上取整。

## 上限语义的两处 off-by-one(已修复)

两处检查都比预期严格一档, 都会让**合法**镜像静默出错, 且此前没有测试覆盖:

| 位置 | 旧行为(错) | 症状 | 新行为 |
| --- | --- | --- | --- |
| `romfs_read_hdr` 名字判定 | "读满 `LUAT_ROMFS_MAX_NAME` 字节仍未遇到 NUL"即判过长 | 恰好 64 字节的名字其 NUL 落在下一块, 于是被**静默丢弃**(条目既不可匹配也不出现在 `lsdir`) | 按"到 NUL 为止的字节数"判定: 等于上限合法, 更长才标记过长; 仍保留超长时提前退出, 避免在损坏镜像里无限扫描 |
| `romfs_cache_count` 深度判定 | `depth + 1 > MAX` 作用于目录的**每个子节点(含普通文件)** | 第 4 层目录里的文件让**整个 mount 失败** | 只在进入子目录时检查: 第 4 层目录内的文件合法, 只禁止再嵌套一层 |

修复提交: `aa52d224e`(并入 `60c8c6bde`)。同时新增回归用例
`test_file_in_deepest_dir`(fixture 增加 `four/b/c/d/nested4.txt`, 旧实现会让整个镜像
挂载失败)与 `test_max_name_length_file`(恰好 64 字节的文件名), 并澄清了
`luat_romfs.h` / `AGENTS.md` 里两个宏的描述。

> 未带该修复的核心, 需要 BSP 自己把 `LUAT_ROMFS_MAX_DIR_DEPTH` / `LUAT_ROMFS_MAX_NAME`
> 覆写为 5 / 65 才能表达"目录 4 层、名字 64 字节"; 修复后按默认值即可, 不要再覆写。

## 典型用法: BK7258 的资源分区(`/res/`)

LuatOS 的 Air8101(BK7258)把一块数据分区当作只读资源区挂到 `/res/`, 镜像由烧录工具生成:

- 镜像 = 标准 romfs, 再按 BK CRC **帧化**(每 32 字节数据 + 2 字节大端 CRC16, 尾部 0xFF
  补齐到 32 字节)。
- 设备端经 CPU flash 窗口**指针直读**(`ctx.read == NULL`, 零拷贝, `mmap` 可用):
  帧化镜像的窗口基址 = `0x02000000 + 物理偏移 / 34 * 32`; 裸镜像(未帧化)则为
  `0x02000000 + 物理偏移`。分区物理偏移必须 **34 字节对齐**, 否则帧边界与窗口错位。
- 净载荷 = `容量 / 34 * 32`(帧化开销约 6.25%)。启动时固件先用 flash 控制器读 68 字节,
  与两个窗口候选的前 64 字节比对来判定 `framed`/`raw`, 判定失败只打印 hexdump 并跳过
  挂载, 不会触碰非镜像区域的窗口地址。
- 打包侧约束(工具保证): 单级文件名 ≤ 64 字节(超限报错)、目录 ≤ 4 层(更深的文件告警并
  跳过), 与上面的上限语义一致。

跨仓库文档: 固件侧 `luatos-sdk-bk72xx-smp` 的 `projects/luatos/README.md`(分区表与烧录
元数据)与 `tests/hardware/air8101_res/README.md`(实机验收与结果); 工具侧 `luatos-cli`
的 `README.md`("Air8101 通用资源分区下载")与 `tests/air8101_resource_download/README.md`
(fixture 与验收脚本)。

## 验证

- PC 回归: `bsp/pc/build_windows_32bit_msvc.bat` 后运行
  `build/out/luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/utest/fs/romfs_basic/scripts/`
  → 18 passed / 0 failed(含上述两个回归用例)。
- 边界镜像(host harness + `mkromfs.py` 产物): `a/b/c/d/file` 可挂载、5 层目录仍失败、
  恰好 64 字节名字可见、65 字节名字跳过。
- 实机(BK7258 资源分区): 挂载日志 `romfs mounted at /res/: window=0x02670000
  mode=framed partition=0x006d7000/1114112 bytes`; 工具侧 `CLI_RES_FULL_PASS`(8 条目含
  64 字节名)与 `CLI_RES_DEEP_PASS`(4 层保留 / 第 5 层跳过)通过。

## 已知限制

- 深度上限只在 `LUAT_ROMFS_USE_DIR_CACHE=1` 时检查; 关闭目录缓存(零 RAM 模式)不做深度
  检查, 由路径缓冲长度(`LUAT_ROMFS_MAX_PATH`)间接约束。
- 名字超长的条目**静默跳过**而不是报错, 生成端(如 `mkromfs.py`、luatos-cli)需自行限制。
- 条目 checksum 不校验; 只读镜像损坏后可能读到错误数据, 仅头部 checksum 能挡住明显错误。
- 不支持写操作, 也不支持运行时重新挂载/更新镜像(mount 后镜像内容必须保持不变)。
