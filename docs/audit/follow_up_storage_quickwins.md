# LF FTL 深度问题(F-01..F-10)实施规划

> 上下文:本次 8h 窗口跑了 S-XX(9 项)+ M-08(1 项)+ F-11/F-12(2 项)= 12 项 quickwin,都安全落地。
> 但 F-01..F-10 是结构性重构,每项 0.3-3 人周,**总工作量约 10 人周**,必须分阶段。

---

## 0. 总体策略

按依赖关系分 5 个 Phase,每个 Phase 是独立可交付的工程。

| Phase | 范围 | 工作量 | 优先级 | 完成前置 |
|---|---|---|---|---|
| **P1** | F-01 + F-10 | ~1.5 人天 | 🟢 低 | 无 |
| **P2** | F-04 + F-05 + F-06 | ~3 人周 | 🔴 高 | 无(必须三件套) |
| **P3** | F-08 | ~0.5 人周 | 🟡 中 | P2 之后(checkpoint 格式要稳定) |
| **P4** | F-02 + F-07 | ~3 人周 | 🔴 高 | P2 之后(需要 journal 原子性) |
| **P5** | F-03 | ~3 人周 | 🔴 高 | P4 之后(需要真 GC 做 victim 搬迁) |
| **保留** | F-09 | 视芯片 | 🟡 中 | 暂缓(per-chip ECC 需要逐个适配) |

总:约 **10 人周 / 2.5 个月**(单人全职)

---

## 1. Phase 1:F-01 文档澄清 + F-10 find_spare bitmap(1.5 天)

### F-01:FTL 是误称——加 Doxygen 块诚实声明

**问题**:组件以"FTL"自居,实际是"静态坏块替换 + 双 slot checkpoint"。pgfs 集成文档没点出这一点,容易让上层 FS 误以为有动态 remap / WL / GC 搬迁能力。

**改法**:在 `components/little_flash/src/little_flash_ftl.h` 顶部加 Doxygen 块,明确声明:

```c
/**
 * @file little_flash_ftl.h
 * @brief Static bad-block replacement layer for little_flash.
 *
 * SCOPE & HONESTY (read before assuming):
 * - This is a "static" mapping layer (l2p built once at init, identity),
 *   NOT a true FTL with dynamic remap / wear-leveling / GC victim move.
 * - Provides: per-page mapping for static bad-block replacement, double-slot
 *   checkpoint with CRC, journal for remap history.
 * - Does NOT provide: dynamic block reclaim, erase-count tracking, wear
 *   leveling, GC stalls for write backpressure. (see track_b_ftl_layer.md
 *   §10 for planned evolution.)
 * - Upper FS (e.g. pgfs) MUST NOT assume any write amplification control
 *   or block reclaim. Treat this as MTD skipbadblocks + journal, not FTL.
 *
 * Callers needing real FTL/WL behavior should migrate to little_flash_v3
 * (F-02/F-03 track) once available.
 */
```

**改动**:
- `components/little_flash/src/little_flash_ftl.h` 顶部加 block
- `components/pgfs/AGENTS.md` 第 13-17 行("pgfs 写失败的契约")末尾加引用链接到这段

**风险**:零(纯文档)

---

### F-10:find_spare 线性扫描换 bitmap

**问题**:`little_flash_ftl.c:95-109` 的 `find_spare` 每次 O(reserve_pages) 线性扫描。reserve 用到一半时,单次坏块替换可能扫数千页。hot path。

**改法**:
- 在 `ctx` 加 `uint64_t* spare_bitmap`(每 bit 一个 spare candidate,1Gbit/64 页/块 = 1024 块 → 1024 bits = 128 字节,可接受)
- `init` 时根据 `bad[]` 反向初始化 bitmap(0 = free, 1 = used/already-bad)
- `find_spare` 用 `__builtin_ctzll` 找第一个 0 bit,O(1)
- 占用后置 1,释放时清 0(释放路径暂时没有,先不实现)
- `bad[]` 仍是 source of truth,bitmap 只是 cache

**改动**:
- `little_flash_ftl_internal.h:36-63` `ctx_t` 加 `uint64_t* spare_bitmap` 字段
- `little_flash_ftl.c:62-89` 扫描后初始化 bitmap
- `little_flash_ftl.c:95-109` `find_spare` 改用 bitmap
- 加 utest case:`find_spare_from_bitmap_basic` / `find_spare_exhausted_returns_invalid`

**风险**:低(bitmap 是 cache,行为不变;性能提升 O(reserve) → O(1))

---

## 2. Phase 2:F-04 增量 journal + F-05 原子化 + F-06 并发保护(3 人周)

**这三件必须一起做,理由:incremental journal 解决 F-05 原子性,同时 journal 写要 mutex 保护(F-06);分开做会出现中间态不一致。**

### F-04 增量 journal(降低 checkpoint 写放大)

**问题**:`meta_write_slot` 每次写整张 l2p(256KB / 1Gbit)。`meta_append_journal` 每次 `mark_bad_and_remap` 都触发。坏块事件放大成 256KB 写。

**改法**:
- metadata region 扩到 ≥ 4 块(multi-region);用 block 0 末两字节存 `commit_gen` 作为 "active slot" 标记
- 写流程:
  1. 写新 slot(只写 l2p delta + journal entries)
  2. 校验新 slot CRC
  3. 翻转 `commit_gen` 标记(只有 commit_gen 翻了的 slot 才算"已确认")
  4. 才允许擦旧 slot
- journal 改为 append-only ring:先写 journal append,再写 l2p delta
- 恢复:先读 active slot(gen 由 commit_gen 决定),再 replay journal

**效果**:
- 写放大:256KB/坏块 → ~8KB(journal entry 大小)
- 掉电风险:从"丢全 l2p 滚 identity"降为"丢最近 1-2 条 remap"
- 风险:ring 满时强制 checkpoint,可能 stall,需背压(高水位时阻塞 mark_bad_and_remap)

**改动**:
- `little_flash_ftl_internal.h` 加 `LF_FTL_JOURNAL_RING_SIZE`,`LF_FTL_META_REGION_BLOCKS=4`
- `little_flash_ftl.c` 改 `meta_append_journal` 写 ring entry 而非全 l2p
- `little_flash_ftl_meta.c` 改 `meta_checkpoint` 走 new protocol(写 delta → 校验 → commit_gen flip → 擦旧)
- `little_flash_ftl_meta.c` 改 `meta_recover` 用 commit_gen 选 active slot
- 加 utest:断电注入测试(写到一半 kill 进程,验证 recover 状态正确)

### F-05 Checkpoint 原子化(被 F-04 顺手解决)

**问题**:`meta_write_slot` 是 erase-then-write,两步之间断电则 slot 数据全丢,降级 identity fallback。

**改法**:F-04 完成后自动满足。旧的"erase-then-write" 协议替换为 "write-new-slot → 校验 → commit_gen flip → 擦旧"。任何一步断电:
- 写新 slot 断电:旧 slot 完整,新 slot 不完整,`commit_gen` 未变 → 仍走旧 slot
- 校验 CRC 失败:同上
- commit_gen flip 断电:可能翻了一半,boot 时读 commit_gen,选完成的那个

**改动**:无独立改动(被 F-04 覆盖)

### F-06 并发保护

**问题**:`l2p/p2l/bad/journal/recover_state` 全部无锁。多 task 并发调 lf API 会读到撕裂状态。

**改法**:
- 在 `ctx` 加 mutex
- `map_page` / `mark_bad_and_remap` / `gc_collect` / `meta_checkpoint` 全部持锁
- `recover_state` 改 `atomic_uint32_t`(C11)或 volatile + critical section
- `meta_raw_begin/end` 切 `ftl_enabled` 与 `chip_info.capacity` 移到持锁内

**改动**:
- `little_flash_ftl_internal.h` `ctx_t` 加 `luat_mutex_t mutex` 字段
- `little_flash_ftl.c` 在每个公开 API 入口持锁
- `little_flash_ftl.c` 把 `recover_state` 类型从 uint32 改 atomic
- 加 utest:多 task 并发 mark_bad_and_remap 跑 1000 次,验证不撕裂

**风险**:性能损失小(单次操作 μs 级),但增加优先级反转风险——需确认 host RTOS 有 priority-inherit mutex

---

## 3. Phase 3:F-08 l2p/p2l 按需压缩(0.5 人周)

**前置**:P2 完成(checkpoint 格式稳定,新版 l2p 结构需要 round-trip 验证)

**问题**:`l2p`/`p2l` 各 `page_count × 4` 字节。1Gbit(64K 页)两个表 512KB,4Gbit = 2MB。Air780E 192KB RAM 装不下。

**改法**:
- `l2p` 改 "block table + per-block page table":
  - `block_of_logical[log] → block_index`(uint16,64K → 128KB)
  - `page_in_block[block] → phys_page_offset`(per-block,仅 remap 时分配)
- 默认未 remap 走 identity:`phys = logical`(纯公式,无内存)
- remap 后查 per-block table(只占 remap 数 × 4 字节)
- `p2l` 用反向 chain:page_in_block[block][page] 指向 logical(仅 remap 分配)

**效果**:
- 1Gbit 仅 remap 数 × 4 字节,典型几百字节
- 4Gbit 上限 ~100KB(假设 1% remap)
- checkpoint 格式要扩一个 `META_VERSION = 2`,加版本迁移路径(老版 → identity + rebuild p2l)

**改动**:
- `little_flash_ftl_internal.h` 重写 `ctx_t` l2p/p2l 字段
- `little_flash_ftl.c` `l2p_lookup` / `l2p_set` 函数实现 block_of_logical + page_in_block 双层查
- `little_flash_ftl_meta.c` 改 `meta_prepare_image` / `meta_apply_image` 序列化新格式
- bump `LF_FTL_META_VERSION = 2u`,恢复路径检测老版本 → 走 identity + 重新构建

**风险**:中等(checkpoint 格式破坏性变更,需要仔细测 round-trip)

---

## 4. Phase 4:F-02 真 GC + F-07 GC 阻塞写(3 人周)

**前置**:P2 完成(journal 原子性是 GC 搬迁断电恢复的基础)

### F-02 真 GC

**问题**:`little_flash_ftl_gc_collect` 只做 checkpoint,没有 victim 选择、有效页搬迁、block 回收。

**改法**(按 audit §3.4 伪代码):
- 引入 `uint16_t erase_count[block_count]`(每块 2 字节,1Gbit/64 页/块 = 1024 块 = 2KB RAM)
- 每次 `mark_bad` 路径顺便 `erase_count[block]++`,持久化到 metadata image
- 真正实现 `gc_collect_v2`:
  1. 选 victim:扫描所有 block,挑 erase_count 最低的(冷块)
  2. 读 victim 上的 valid pages(根据 p2l 反查)
  3. 搬到 free block(选 erase_count 同样最低的,保持均衡)
  4. 更新 l2p + journal(原 page → 新 page,老 block 标 free)
  5. 擦 victim block
- 静态 WL:周期把"长时间没写" block 的数据搬到高擦写次数 block,均值化

**效果**:写放大 1.1-1.5x,寿命延长 5-10x

**改动**:
- `little_flash_ftl_internal.h` `ctx_t` 加 `uint16_t* erase_count`
- `little_flash_ftl.c` `mark_bad_and_remap` 顺便 `erase_count[block]++`
- `little_flash_ftl_gc.c` 重写 `gc_collect`(50 行 → 估计 300-500 行)
- 加 utest:模拟 1000 次 remap,验证 erase_count 分布合理

### F-07 GC 阻塞写(被 F-02 顺手解决)

**问题**:低水位时 GC 不阻塞上层 write,reserve 用尽后下次坏块事件才 RECOVER_STATE_RETRY 但无效。

**改法**:F-02 完成后真 GC 自然能回收,在 `mark_bad_and_remap` 同步触发 + 阻塞。reserve 用尽时返回 `LF_ERR_NO_SPACE` 而不是默默 retry。

**改动**:无独立改动(被 F-02 覆盖)

---

## 5. Phase 5:F-03 磨损均衡(3 人周)

**前置**:P4 完成(需要真 GC 做 victim 搬迁)

**问题**:`erase_count[]` 加上后,需要在 `map_page` / `mark_bad_and_remap` 时主动选冷块,而不是"先来先得"。

**改法**:
- 在 `find_spare` 增强:不再选第一个 free block,而是选 erase_count 最低的
- 静态 WL 后台线程:每 N 次写操作触发一次,扫描"长时间没写"的 block,搬到高擦写次数 block
- WL 阈值:erace_count_max - erase_count_min > 10% 时触发

**效果**:寿命再延长 2-3x(配合 F-02 的 5-10x)

**改动**:
- `little_flash_ftl.c` `find_spare` 加 erase_count 排序
- 新文件 `little_flash_ftl_wl.c`:`wl_balance_once()` 函数
- `mark_bad_and_remap` 后调 `wl_balance_once` 一次
- 加 utest:模拟 10000 次写,验证 erase_count 方差 < 10%

**风险**:WL 搬迁是隐性 GC 行为,断电时需要 l2p 状态机保护(已被 F-04+F-05 解决)

---

## 6. F-09 坏块 OOB ECC 验证(暂缓)

**问题**:`scan_bad_blocks` 只读 OOB 字节是否为 0xFF,不验证数据完整性。

**改法**:对每块前两页发 `PAGE_DATA_READ + READ_DATA + ECC 校验`,失败视为亚健康块。

**为啥暂缓**:
- 不同 NAND 芯片 ECC 算法不同(W25N01GV 用 1-bit Hamming,GD5F 用 4-bit BCH,新一些的 8-bit on-die),没有统一接口
- 现有 port 抽象不暴露 ECC status,需要在 `little_flash_t` 加回调
- 实现成本高于其他项,且收益边际(坏块检测在实际使用中已经被 `mark_bad_and_remap` 兜住)

**如要推进**:逐个芯片适配,先做 W25N01GV(目前主力)。1-2 周 / 芯片。

---

## 7. 建议推进顺序

| 顺序 | Phase | 周期 | 里程碑 |
|---|---|---|---|
| 1 | P1 | 1.5 天 | F-01 doc + F-10 bitmap 落地,跑 utest 验证 |
| 2 | P2 | 3 周 | journal 原子 + 并发,断电注入测试 |
| 3 | P3 | 0.5 周 | l2p/p2l 压缩,RAM 占用降一个数量级 |
| 4 | P4 | 3 周 | 真 GC 落地,寿命提升 5-10x |
| 5 | P5 | 3 周 | WL 完成,寿命再延 2-3x |
| 6 | F-09 | 视芯片 | 按需 |

合计 ~10 人周 = 2.5 个月(单人)。

---

## 8. 建议立即做的事

P1 的 F-01 + F-10 是低风险高 ROI,可以**今天就做**:
- F-01 Doxygen 块:~30 分钟,纯文档,风险零
- F-10 bitmap find_spare:~2-3 小时,改动小,有 utest 可加

要不要我现在就把 P1 做完,作为第 6 个 commit 推到分支上?P2-P5 的深度工作就当正式工程规划,后续按 Phase 排期推。
